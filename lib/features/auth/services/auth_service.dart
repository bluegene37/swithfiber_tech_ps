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
  /*
  Future<UserModel> login({
    required String username,
    required String password,
  }) async {
  ...
    return user;
  }
  */
  // Gene - Nov, 28, 2026: Use RS256 PowerSync Gateway POST /api/Auth/login as authoritative when user profile is returned, persist tokenExpiresAt, and expose POST /api/Auth/refresh.
  Future<void> _persistGatewayTokens(
    GatewayLoginResult gwResult, {
    bool alsoSaveAsJwt = false,
  }) async {
    if (gwResult.sessionToken.isNotEmpty) {
      await _storage.write(
        AppConstants.keyPowerSyncGatewayToken,
        gwResult.sessionToken,
      );
      if (alsoSaveAsJwt) {
        await _storage.saveToken(gwResult.sessionToken);
      }
    }
    if (gwResult.tokenExpiresAt != null) {
      await _storage.write(
        AppConstants.keyPowerSyncGatewayTokenExpiresAt,
        gwResult.tokenExpiresAt!.toUtc().toIso8601String(),
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
  }

  Future<UserModel> login({
    required String username,
    required String password,
  }) async {
    GatewayLoginResult? gwResult;
    if (_gateway.hasBaseUrl) {
      try {
        gwResult = await _gateway.login(
          username: username.trim(),
          password: password,
        );
        final rawMap = gwResult.rawJson;
        final gwUserJson = rawMap['user'] is Map<String, dynamic>
            ? rawMap['user'] as Map<String, dynamic>
            : rawMap;
        final hasUserFields = gwUserJson['id'] != null &&
            (gwUserJson['username'] != null || gwUserJson['fname'] != null);
        if (hasUserFields) {
          var gwUser = UserModel.fromJson(gwUserJson);
          if (!gwUser.active) {
            throw Exception(
              'Your technician account is inactive. Please contact Dispatch.',
            );
          }
          final resolvedEmail = gwResult.email ?? gwResult.powerSync?.userId;
          if (gwUser.email.trim().isEmpty &&
              resolvedEmail != null &&
              resolvedEmail.isNotEmpty) {
            gwUser = UserModel(
              id: gwUser.id,
              username: gwUser.username,
              fname: gwUser.fname,
              lname: gwUser.lname,
              email: resolvedEmail,
              accessLevelId: gwUser.accessLevelId,
              active: gwUser.active,
              menus: gwUser.menus,
              contactNumber: gwUser.contactNumber,
              address: gwUser.address,
            );
          }
          await _persistGatewayTokens(gwResult, alsoSaveAsJwt: true);
          await _storage.saveUserSession(gwUser.toRawJson());
          return gwUser;
        }
      } on PowerSyncUploadException catch (e) {
        if (e.isUnauthorized || e.statusCode == 400 || e.statusCode == 403) {
          throw Exception(e.message);
        }
      } catch (e) {
        if (e.toString().contains('inactive')) rethrow;
      }
    }

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

    if (_gateway.hasBaseUrl) {
      try {
        gwResult ??= await _gateway.login(
          username: username.trim(),
          password: password,
        );
        await _persistGatewayTokens(
          gwResult,
          alsoSaveAsJwt: token.toString().isEmpty,
        );
        final resolvedEmail = gwResult.email ?? gwResult.powerSync?.userId;
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
        // Non-fatal: PowerSyncBackendConnector will refresh/mint as needed.
      }
    }

    await _storage.saveUserSession(user.toRawJson());

    return user;
  }

  /// Refreshes the Gateway session & RS256 PowerSync token via `POST /api/Auth/refresh`.
  Future<GatewayLoginResult?> refreshGatewaySession() async {
    if (!_gateway.hasBaseUrl) return null;
    final bearer =
        (await _storage.read(AppConstants.keyPowerSyncGatewayToken))?.trim() ??
            (await _storage.getToken())?.trim() ??
            '';
    if (bearer.isEmpty) return null;
    final refreshed = await _gateway.refreshSession(bearerToken: bearer);
    await _persistGatewayTokens(refreshed, alsoSaveAsJwt: true);
    return refreshed;
  }

  /// Restore active technician session from local storage on app start
  /*
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
  */
  // Gene - Nov, 28, 2026: Require at least one valid stored bearer token when restoring a session so orphaned iOS/Android backups cannot leave the app stuck on an empty authenticated shell.
  Future<UserModel?> restoreSession() async {
    try {
      final userJson = await _storage.getUserSession();
      if (userJson == null || userJson.isEmpty) {
        return null;
      }

      /*
      final jwt = (await _storage.getJwtToken())?.trim() ?? '';
      */
      // Gene - Nov, 28, 2026: Use SecureStorageService.getToken() for reading stored JWT bearer token.
      final jwt = (await _storage.getToken())?.trim() ?? '';
      final gwToken =
          (await _storage.read(AppConstants.keyPowerSyncGatewayToken))
                  ?.trim() ??
              '';
      final psToken =
          (await _storage.read(AppConstants.keyPowerSyncToken))?.trim() ?? '';
      if (jwt.isEmpty && gwToken.isEmpty && psToken.isEmpty) {
        await _storage.clearCredentials();
        return null;
      }

      var user = UserModel.fromRawJson(userJson);
      if (user.email.trim().isEmpty) {
        final storedUserId =
            (await _storage.read(AppConstants.keyPowerSyncUserId))?.trim() ??
                '';
        if (storedUserId.isNotEmpty) {
          user = UserModel(
            id: user.id,
            username: user.username,
            fname: user.fname,
            lname: user.lname,
            email: storedUserId,
            accessLevelId: user.accessLevelId,
            active: user.active,
            menus: user.menus,
            contactNumber: user.contactNumber,
            address: user.address,
          );
        }
      }
      return user;
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
    /*
    final user = UserModel.fromJson(data);
    await _storage.saveUserSession(user.toRawJson());
    return user;
    */
    // Gene - Nov, 28, 2026: Preserve canonical email from cached session / gateway login when /Users/{id} omits an email field.
    var user = UserModel.fromJson(data);
    if (user.email.trim().isEmpty) {
      String? fallbackEmail;
      final existingJson = await _storage.getUserSession();
      if (existingJson != null && existingJson.isNotEmpty) {
        try {
          fallbackEmail = UserModel.fromRawJson(existingJson).email.trim();
        } catch (_) {}
      }
      if (fallbackEmail == null || fallbackEmail.isEmpty) {
        fallbackEmail =
            (await _storage.read(AppConstants.keyPowerSyncUserId))?.trim();
      }
      if (fallbackEmail != null && fallbackEmail.isNotEmpty) {
        user = UserModel(
          id: user.id,
          username: user.username,
          fname: user.fname,
          lname: user.lname,
          email: fallbackEmail,
          accessLevelId: user.accessLevelId,
          active: user.active,
          menus: user.menus,
          contactNumber: user.contactNumber,
          address: user.address,
        );
      }
    }
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
