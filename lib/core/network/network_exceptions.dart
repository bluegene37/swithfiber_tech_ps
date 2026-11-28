import 'package:dio/dio.dart';

/// Standardized application network exception.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic details;
  // Gene - Nov, 28, 2026: Expose parsed backend errorCode (NOT_ASSIGNED / RATE_LIMITED) and retryAfterSeconds for PowerSync v13 gateway errors.
  final String? errorCode;
  final int? retryAfterSeconds;

  /// The call that failed, e.g. `PUT` and
  /// `https://host:8090/api/JobOrders/123`. Null when the exception was not
  /// raised from an HTTP round trip.
  final String? requestMethod;
  final String? requestUrl;

  ApiException({
    required this.message,
    this.statusCode,
    this.details,
    this.errorCode,
    this.retryAfterSeconds,
    this.requestMethod,
    this.requestUrl,
  });

  bool get isNotAssigned =>
      statusCode == 403 && (errorCode == null || errorCode == 'NOT_ASSIGNED');

  bool get isRateLimited => statusCode == 429 || errorCode == 'RATE_LIMITED';

  factory ApiException.fromDioException(DioException error) {
    String message = 'An unexpected network error occurred.';
    int? status = error.response?.statusCode;
    String? errorCode;
    int? retryAfterSeconds;

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        message =
            'Connection timed out. Please check your internet connection.';
        status = 408;
        break;
      case DioExceptionType.badResponse:
        final data = error.response?.data;
        if (data is Map) {
          if (data['message'] != null) {
            message = data['message'].toString();
          } else if (data['error'] != null) {
            message = data['error'].toString();
          } else if (data['title'] != null) {
            message = data['title'].toString();
          }
          final rawCode = data['code']?.toString().trim();
          if (rawCode != null && rawCode.isNotEmpty) {
            errorCode = rawCode.toUpperCase();
          }
          final rawRetry = data['retryAfterSeconds'];
          if (rawRetry is int) {
            retryAfterSeconds = rawRetry;
          } else if (rawRetry != null) {
            retryAfterSeconds = int.tryParse(rawRetry.toString());
          }

          // Handle ASP.NET ModelState validation error dictionaries
          if (data['errors'] is Map) {
            final errMap = data['errors'] as Map;
            final fieldErrors = <String>[];
            errMap.forEach((key, val) {
              if (val is List) {
                fieldErrors.add('$key: ${val.join(", ")}');
              } else {
                fieldErrors.add('$key: $val');
              }
            });
            if (fieldErrors.isNotEmpty) {
              message = '$message (${fieldErrors.join(" | ")})';
            }
          }
        } else if (data is String && data.isNotEmpty) {
          message = data;
        } else {
          message = 'Server returned error ($status).';
        }
        if (retryAfterSeconds == null && status == 429) {
          final headerRetry = error.response?.headers.value('retry-after');
          if (headerRetry != null) {
            retryAfterSeconds = int.tryParse(headerRetry.trim());
          }
        }
        break;
      case DioExceptionType.cancel:
        message = 'Request was cancelled.';
        break;
      case DioExceptionType.connectionError:
        message = 'Cannot connect to Switch Fiber servers. You may be offline.';
        break;
      case DioExceptionType.unknown:
      default:
        message = error.message ?? 'An unknown network error occurred.';
        break;
    }

    return ApiException(
      message: message,
      statusCode: status,
      details: error.response?.data,
      errorCode: errorCode,
      retryAfterSeconds: retryAfterSeconds,
      requestMethod: error.requestOptions.method,
      requestUrl: error.requestOptions.uri.toString(),
    );
  }

  @override
  String toString() => message;
}
