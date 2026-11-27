import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_storage_service.dart';
import '../../../core/sync/powersync_gateway_client.dart';
import '../models/user_model.dart';

/// Authentication service for field technician login and session management.
class AuthService {
  final ApiClient _api;
  final SecureStorageService _storage;
  // Gene - Nov, 27, 2026: Optional PowerSyncGatewayClient to acquire RS256 gateway/PowerSync tokens and canonical lowercase email on login.
  final PowerSyncGatewayClient _gateway;

  AuthService({
    ApiClient? api,
    SecureStorageService? storage,
    PowerSyncGatewayClient? gatewayClient,
  })  : _api = api ?? ApiClient.instance,
        _storage = storage ?? SecureStorageService.instance,
        _gateway = gatewayClient ?? PowerSyncGatewayClient();

  /// Authenticate a technician with their account username and password.
  Future<UserModel> login({
    required String username,
    required String password,
  }) async {
    final response = await _api.post(
      '/Users/login',
      data: {
        'username': username.trim(),
        'password': password,
      },
    );

    final data = response.data;
    if (data == null) {
      throw Exception('Empty response from authentication server.');
    }

    // Extract user profile and token
    final rawUser = data is Map<String, dynamic> && data['user'] != null
        ? data['user']
        : data;

    if (rawUser is! Map<String, dynamic>) {
      throw Exception('Invalid user data returned from authentication server.');
    }

    var user = UserModel.fromJson(rawUser);

    if (!user.active) {
      throw Exception(
          'Your technician account is inactive. Please contact Dispatch.');
    }

    final token = data is Map<String, dynamic>
        ? (data['token'] ?? data['accessToken'] ?? '')
        : '';

    if (token.toString().isNotEmpty) {
      await _storage.saveToken(token.toString());
    }

    // Best-effort PowerSync Gateway auth so RS256 tokens and canonical email
    // are persisted immediately when POWERSYNC_GATEWAY_URL is configured.
    if (_gateway.hasBaseUrl) {
      try {
        final gwResult = await _gateway.login(
          username: username.trim(),
          password: password,
        );
        if (gwResult.sessionToken.isNotEmpty) {
          await _storage.write(
            AppConstants.keyPowerSyncGatewayToken,
            gwResult.sessionToken,
          );
        }
        final ps = gwResult.powerSync;
        if (ps != null) {
          if (ps.token.isNotEmpty) {
            await _storage.write(AppConstants.keyPowerSyncToken, ps.token);
          }
          if (ps.expiresAt != null) {
            await _storage.write(
              AppConstants.keyPowerSyncTokenExpiresAt,
              ps.expiresAt!.toUtc().toIso8601String(),
            );
          }
          if (ps.userId.isNotEmpty) {
            await _storage.write(AppConstants.keyPowerSyncUserId, ps.userId);
          }
          if (ps.endpoint.isNotEmpty) {
            await _storage.write(
              AppConstants.keyPowerSyncEndpoint,
              ps.endpoint,
            );
          }
        }
        final resolvedEmail = gwResult.email ?? ps?.userId;
        if (user.email.trim().isEmpty &&
            resolvedEmail != null &&
            resolvedEmail.isNotEmpty) {
          user = UserModel(
            id: user.id,
            username: user.username,
            fname: user.fname,
            lname: user.lname,
            email: resolvedEmail,
            accessLevelId: user.accessLevelId,
            active: user.active,
            menus: user.menus,
            contactNumber: user.contactNumber,
            address: user.address,
          );
        }
      } catch (_) {
        // Non-fatal: PowerSyncBackendConnector will mint via legacy Bearer token if needed.
      }
    }

    await _storage.saveUserSession(user.toRawJson());

    return user;
  }

  /// Restore active technician session from local storage on app start
  Future<UserModel?> restoreSession() async {
    try {
      final userJson = await _storage.getUserSession();
      if (userJson != null && userJson.isNotEmpty) {
        return UserModel.fromRawJson(userJson);
      }
    } catch (_) {
      await _storage.clearCredentials();
    }
    return null;
  }

  /// Fetch the technician's full profile.
  ///
  /// The login response carries only name, username and access level; contact
  /// number, address and email live on this endpoint.
  ///
  /// NOTE: this endpoint also returns the account password in plaintext.
  /// [UserModel] deliberately ignores that field so it never reaches storage.
  Future<UserModel> fetchProfile(int userId) async {
    final response = await _api.get('/Users/$userId');
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw Exception('Unexpected profile response from server.');
    }
    final user = UserModel.fromJson(data);
    await _storage.saveUserSession(user.toRawJson());
    return user;
  }

  /// Ask the server to email a reset link for [username].
  ///
  /// The endpoint keys off the account username, not the email address; it
  /// rejects an `email` field with a 400 and answers an unknown account with a
  /// 404. The reset link it sends carries a JWT that `/Auth/reset-password`
  /// consumes.
  Future<void> requestPasswordReset(String username) async {
    await _api.post(
      '/Auth/request-password-reset',
      data: {'username': username.trim()},
    );
  }

  /// Terminate session and clear secure storage
  Future<void> logout() async {
    await _storage.clearCredentials();
  }
}
