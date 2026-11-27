// Gene - Nov, 27, 2026: Dedicated HTTP client for the PowerSync Gateway (RS256 auth, token minting, unified upload batch, and multipart photo uploads).
import 'package:dio/dio.dart';

import '../constants/app_constants.dart';
import '../network/api_client.dart';

/// PowerSync token payload returned by `GET /api/Auth/powersync-token` or
/// nested under `powersync` in `POST /api/Auth/login`.
class PowerSyncTokenResult {
  final String token;
  final String userId;
  final String endpoint;
  final DateTime? expiresAt;

  const PowerSyncTokenResult({
    required this.token,
    required this.userId,
    required this.endpoint,
    this.expiresAt,
  });

  factory PowerSyncTokenResult.fromJson(Map<String, dynamic> json) {
    final rawToken = (json['token'] ?? '').toString().trim();
    final rawUserId = (json['userId'] ?? json['user_id'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final rawEndpoint = (json['endpoint'] ?? '').toString().trim();
    final rawExp = json['expiresAt'] ?? json['expires_at'];
    return PowerSyncTokenResult(
      token: rawToken,
      userId: rawUserId,
      endpoint: rawEndpoint,
      expiresAt: rawExp == null ? null : DateTime.tryParse(rawExp.toString()),
    );
  }
}

/// Gateway login response returned by `POST /api/Auth/login`.
class GatewayLoginResult {
  final Map<String, dynamic> rawJson;
  final String? email;
  final String sessionToken;
  final DateTime? tokenExpiresAt;
  final PowerSyncTokenResult? powerSync;

  const GatewayLoginResult({
    required this.rawJson,
    required this.email,
    required this.sessionToken,
    this.tokenExpiresAt,
    this.powerSync,
  });

  factory GatewayLoginResult.fromJson(Map<String, dynamic> json) {
    String? emailStr = json['email']?.toString().trim();
    if ((emailStr == null || emailStr.isEmpty) &&
        json['user'] is Map<String, dynamic>) {
      emailStr =
          (json['user'] as Map<String, dynamic>)['email']?.toString().trim();
    }
    final normalizedEmail = (emailStr != null && emailStr.isNotEmpty)
        ? emailStr.toLowerCase()
        : null;

    final sessionToken =
        (json['token'] ?? json['accessToken'] ?? '').toString().trim();
    final expRaw = json['tokenExpiresAt'] ?? json['token_expires_at'];
    final psMap = json['powersync'];

    return GatewayLoginResult(
      rawJson: json,
      email: normalizedEmail,
      sessionToken: sessionToken,
      tokenExpiresAt:
          expRaw == null ? null : DateTime.tryParse(expRaw.toString()),
      powerSync: psMap is Map<String, dynamic>
          ? PowerSyncTokenResult.fromJson(psMap)
          : (psMap is Map
              ? PowerSyncTokenResult.fromJson(Map<String, dynamic>.from(psMap))
              : null),
    );
  }
}

/// HTTP failure raised by [PowerSyncGatewayClient].
class PowerSyncUploadException implements Exception {
  final int? statusCode;
  final String message;
  final String? requestMethod;
  final String? requestUrl;
  final dynamic requestBody;
  final dynamic responseBody;

  const PowerSyncUploadException({
    this.statusCode,
    required this.message,
    this.requestMethod,
    this.requestUrl,
    this.requestBody,
    this.responseBody,
  });

  /// True for HTTP 401 Unauthorized, triggering a PowerSync token refresh.
  bool get isUnauthorized => statusCode == 401;

  /// True for permanent client-side 4xx rejections (excluding 401/408/429)
  /// that should be logged and cleared from `ps_crud` rather than blocking the queue.
  bool get isPermanent =>
      statusCode != null &&
      statusCode! >= 400 &&
      statusCode! < 500 &&
      statusCode != 401 &&
      statusCode != 408 &&
      statusCode != 429;

  @override
  String toString() => statusCode != null
      ? 'PowerSyncUploadException($statusCode): $message'
      : 'PowerSyncUploadException: $message';
}

/// Client communicating with the self-hosted PowerSync Gateway (`:8081`).
class PowerSyncGatewayClient {
  final String _baseUrl;
  final Dio _dio;
  final bool _customDio;

  PowerSyncGatewayClient({
    String? baseUrl,
    Dio? dio,
  })  : _baseUrl = _normalizeBaseUrl(
          baseUrl ?? AppConstants.defaultPowerSyncGatewayUrl,
        ),
        _customDio = dio != null,
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout:
                    const Duration(milliseconds: AppConstants.connectTimeout),
                receiveTimeout:
                    const Duration(milliseconds: AppConstants.receiveTimeout),
                headers: const {'Accept': 'application/json'},
              ),
            );

  static String _normalizeBaseUrl(String raw) {
    var s = raw.trim();
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.toLowerCase().endsWith('/api')) {
      s = s.substring(0, s.length - 4);
      while (s.endsWith('/')) {
        s = s.substring(0, s.length - 1);
      }
    }
    return s;
  }

  /// Normalized base origin without trailing `/` or `/api`.
  String get baseUrl => _baseUrl;

  /// Whether a PowerSync Gateway URL is configured.
  bool get hasBaseUrl => _baseUrl.isNotEmpty;

  String _endpoint(String path) {
    if (!hasBaseUrl) {
      throw const PowerSyncUploadException(
        message: 'PowerSync Gateway URL is not configured.',
      );
    }
    final cleanPath = path.startsWith('/') ? path : '/$path';
    final apiPath = cleanPath.toLowerCase().startsWith('/api/') ||
            cleanPath.toLowerCase() == '/api'
        ? cleanPath
        : '/api$cleanPath';
    return '$_baseUrl$apiPath';
  }

  void _guardNetwork(String method, String url) {
    if (!_customDio && ApiClient.isNetworkBlocked) {
      throw PowerSyncUploadException(
        message: 'Network access is disabled in tests',
        requestMethod: method,
        requestUrl: url,
      );
    }
  }

  /// Authenticates against `POST /api/Auth/login` on the Gateway.
  Future<GatewayLoginResult> login({
    required String username,
    required String password,
  }) async {
    final url = _endpoint('/api/Auth/login');
    _guardNetwork('POST', url);
    try {
      final response = await _dio.post<dynamic>(
        url,
        data: {
          'username': username.trim(),
          'password': password,
        },
        options: Options(contentType: 'application/json'),
      );
      final map = _asMap(response.data);
      if (map == null) {
        throw PowerSyncUploadException(
          statusCode: response.statusCode,
          message: 'Unexpected response from gateway login.',
          requestMethod: 'POST',
          requestUrl: url,
          responseBody: response.data,
        );
      }
      return GatewayLoginResult.fromJson(map);
    } on DioException catch (e) {
      throw _mapDioError(e, method: 'POST', url: url);
    }
  }

  /// Mints or refreshes a short-lived RS256 PowerSync token via
  /// `GET /api/Auth/powersync-token`.
  Future<PowerSyncTokenResult> fetchPowerSyncToken({
    required String bearerToken,
  }) async {
    final url = _endpoint('/api/Auth/powersync-token');
    _guardNetwork('GET', url);
    try {
      final response = await _dio.get<dynamic>(
        url,
        options: Options(
          headers: {'Authorization': 'Bearer ${bearerToken.trim()}'},
        ),
      );
      final map = _asMap(response.data);
      if (map == null) {
        throw PowerSyncUploadException(
          statusCode: response.statusCode,
          message: 'Unexpected response from powersync-token endpoint.',
          requestMethod: 'GET',
          requestUrl: url,
          responseBody: response.data,
        );
      }
      final result = PowerSyncTokenResult.fromJson(map);
      if (result.token.isEmpty) {
        throw PowerSyncUploadException(
          statusCode: response.statusCode,
          message: 'Gateway returned an empty PowerSync token.',
          requestMethod: 'GET',
          requestUrl: url,
          responseBody: response.data,
        );
      }
      return result;
    } on DioException catch (e) {
      throw _mapDioError(e, method: 'GET', url: url);
    }
  }

  /// Sends one or more PowerSync scalar CRUD operations to `POST /api/powersync/upload`.
  Future<void> uploadBatch({
    required List<Map<String, dynamic>> operations,
    required String bearerToken,
  }) async {
    if (operations.isEmpty) return;
    final url = _endpoint('/api/powersync/upload');
    _guardNetwork('POST', url);
    final body = {'operations': operations};
    try {
      await _dio.post<dynamic>(
        url,
        data: body,
        options: Options(
          contentType: 'application/json',
          headers: {'Authorization': 'Bearer ${bearerToken.trim()}'},
        ),
      );
    } on DioException catch (e) {
      throw _mapDioError(
        e,
        method: 'POST',
        url: url,
        requestBody: body,
      );
    }
  }

  /// Sends a `multipart/form-data` write (`PUT` or `POST`) to the Gateway
  /// (used when captured photo bytes or signatures are attached).
  Future<Map<String, dynamic>?> uploadMultipart({
    required String method,
    required String apiPath,
    required FormData formData,
    required String bearerToken,
    String? idempotencyKey,
  }) async {
    final upperMethod = method.toUpperCase();
    final url = _endpoint(apiPath);
    _guardNetwork(upperMethod, url);
    try {
      final response = await _dio.request<dynamic>(
        url,
        data: formData,
        options: Options(
          method: upperMethod,
          contentType: 'multipart/form-data',
          headers: {
            'Authorization': 'Bearer ${bearerToken.trim()}',
            if (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
              'Idempotency-Key': idempotencyKey.trim(),
          },
        ),
      );
      return _asMap(response.data);
    } on DioException catch (e) {
      throw _mapDioError(
        e,
        method: upperMethod,
        url: url,
      );
    }
  }

  static Map<String, dynamic>? _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  static PowerSyncUploadException _mapDioError(
    DioException error, {
    required String method,
    required String url,
    dynamic requestBody,
  }) {
    int? status = error.response?.statusCode;
    String message = 'Gateway request failed.';

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        status = 408;
        message = 'Connection timed out reaching PowerSync gateway.';
        break;
      case DioExceptionType.badResponse:
        final data = error.response?.data;
        if (data is Map) {
          message = (data['message'] ??
                  data['error'] ??
                  data['title'] ??
                  'Gateway returned HTTP $status.')
              .toString();
          if (data['errors'] is Map) {
            final errMap = data['errors'] as Map;
            final details = <String>[];
            errMap.forEach((k, v) {
              if (v is List) {
                details.add('$k: ${v.join(", ")}');
              } else {
                details.add('$k: $v');
              }
            });
            if (details.isNotEmpty) {
              message = '$message (${details.join(" | ")})';
            }
          }
        } else if (data is String && data.trim().isNotEmpty) {
          message = data.trim();
        } else {
          message = 'Gateway returned HTTP ${status ?? "unknown"}.';
        }
        break;
      case DioExceptionType.connectionError:
        message = 'Cannot reach PowerSync gateway. Device may be offline.';
        break;
      case DioExceptionType.cancel:
        message = 'Gateway request cancelled.';
        break;
      case DioExceptionType.badCertificate:
        message = 'TLS certificate rejected by PowerSync gateway.';
        break;
      case DioExceptionType.unknown:
        message = error.message ?? 'Unexpected gateway error.';
        break;
    }

    return PowerSyncUploadException(
      statusCode: status,
      message: message,
      requestMethod: method,
      requestUrl: url,
      requestBody: requestBody,
      responseBody: error.response?.data,
    );
  }
}
