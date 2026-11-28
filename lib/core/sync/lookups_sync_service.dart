// Gene - Nov, 28, 2026: Cached lookup tables sync client for GET /api/sync/lookups with ETag (If-None-Match / 304) and atomic single-transaction localOnly replacement.
import '../../features/auth/services/auth_service.dart';
import '../../features/catalogs/services/catalog_service.dart';
import '../constants/app_constants.dart';
import '../database/daos/lookups_dao.dart';
import '../storage/secure_storage_service.dart';
import 'powersync_gateway_client.dart';

class LookupsSyncService {
  final PowerSyncGatewayClient _gateway;
  final LookupsDao _lookupsDao;
  final SecureStorageService _storage;
  final AuthService _authService;
  void Function()? onUnauthorized;

  LookupsSyncService({
    PowerSyncGatewayClient? gatewayClient,
    required LookupsDao lookupsDao,
    SecureStorageService? storage,
    AuthService? authService,
    this.onUnauthorized,
  })  : _gateway = gatewayClient ?? PowerSyncGatewayClient(),
        _lookupsDao = lookupsDao,
        _storage = storage ?? SecureStorageService.instance,
        _authService = authService ?? AuthService();

  bool _isSyncing = false;
  DateTime? _lastSyncedAt;

  bool get isSyncing => _isSyncing;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  Future<String?> _readBearerToken() async {
    final gw =
        (await _storage.read(AppConstants.keyPowerSyncGatewayToken))?.trim() ??
            '';
    if (gw.isNotEmpty) return gw;
    final jwt = (await _storage.getToken())?.trim() ?? '';
    return jwt.isNotEmpty ? jwt : null;
  }

  /// Pulls `GET /api/sync/lookups` using `If-None-Match` ETag header.
  /// Returns `true` when new lookup rows were committed inside a single DB transaction,
  /// `false` on `304 Not Modified`, missing credentials, or recoverable offline errors.
  Future<bool> sync({bool ignoreEtag = false}) async {
    if (!_gateway.hasBaseUrl || _isSyncing) return false;
    final initialToken = await _readBearerToken();
    if (initialToken == null) return false;

    _isSyncing = true;
    try {
      final savedEtag = ignoreEtag
          ? null
          : (await _storage.read(AppConstants.keyLookupsEtag))?.trim();
      var result = await _fetchWithRefreshRetry(
        bearerToken: initialToken,
        ifNoneMatch: savedEtag,
      );
      if (result == null || result.isNotModified) {
        return false;
      }

      await _lookupsDao.replaceAllLookups(result.tables);
      if (result.etag != null && result.etag!.trim().isNotEmpty) {
        await _storage.write(AppConstants.keyLookupsEtag, result.etag!.trim());
      }
      _lastSyncedAt = result.fetchedAt ?? DateTime.now().toUtc();
      CatalogService.instance.invalidateCache();
      return true;
    } on PowerSyncUploadException catch (e) {
      if (e.isUnauthorized) {
        await _storage.clearTokensOnly();
        onUnauthorized?.call();
      }
      return false;
    } catch (_) {
      // Offline or transient timeout: retain existing local lookup tables.
      return false;
    } finally {
      _isSyncing = false;
    }
  }

  Future<GatewayLookupsResult?> _fetchWithRefreshRetry({
    required String bearerToken,
    String? ifNoneMatch,
  }) async {
    try {
      return await _gateway.fetchLookups(
        bearerToken: bearerToken,
        ifNoneMatch: ifNoneMatch,
      );
    } on PowerSyncUploadException catch (e) {
      if (!e.isUnauthorized) rethrow;
      try {
        final refreshed = await _authService.refreshGatewaySession();
        if (refreshed == null || refreshed.sessionToken.trim().isEmpty) {
          rethrow;
        }
        return await _gateway.fetchLookups(
          bearerToken: refreshed.sessionToken,
          ifNoneMatch: ifNoneMatch,
        );
      } on PowerSyncUploadException catch (refreshErr) {
        if (refreshErr.isUnauthorized) {
          await _storage.clearTokensOnly();
          onUnauthorized?.call();
        }
        return null;
      }
    }
  }
}
