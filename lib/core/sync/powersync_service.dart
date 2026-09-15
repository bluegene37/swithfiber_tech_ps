import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';
import 'package:swithfiber_tech_ps/core/constants/app_constants.dart';
import 'package:swithfiber_tech_ps/core/storage/secure_storage_service.dart';
import 'package:swithfiber_tech_ps/core/sync/powersync_backend_connector.dart';
import 'package:swithfiber_tech_ps/core/sync/powersync_schema.dart';

/// Singleton owning the PowerSync client database: the app's only local
/// store. Opens it on [powerSyncSchema] and, when a PowerSync token has been
/// configured, joins the cloud sync connection.
class PowerSyncService {
  PowerSyncService._();
  static final PowerSyncService instance = PowerSyncService._();

  PowerSyncDatabase? _db;
  SwitchFiberBackendConnector? _connector;

  PowerSyncDatabase get db {
    final database = _db;
    if (database == null) {
      throw StateError(
        'PowerSyncDatabase has not been initialized. Call initialize() first.',
      );
    }
    return database;
  }

  bool get isInitialized => _db != null;

  /// Whether the cloud sync connection is currently open.
  bool get isConnected => _db?.connected ?? false;

  /// Opens the local database. Idempotent.
  Future<void> initialize({
    String dbFilename = 'switchfiber_powersync.db',
    SwitchFiberBackendConnector? connector,
  }) async {
    if (_db != null) return;

    final dir = await getApplicationSupportDirectory();
    final database = PowerSyncDatabase(
      schema: powerSyncSchema,
      path: join(dir.path, dbFilename),
    );
    await database.initialize();

    _connector = connector ?? SwitchFiberBackendConnector();
    _db = database;
  }

  /// Joins the PowerSync Cloud connection if, and only if, a dedicated
  /// PowerSync token is stored. Every table is local-only today, so the
  /// connection carries nothing yet; the gate keeps the sync client from
  /// retrying forever with the API's own JWT, which the PowerSync instance
  /// does not accept.
  Future<void> connectIfConfigured({SecureStorageService? storage}) async {
    final database = _db;
    final connector = _connector;
    if (database == null || connector == null || database.connected) return;
    final store = storage ?? SecureStorageService();
    final token = await store.read(AppConstants.keyPowerSyncToken);
    if (token == null || token.isEmpty) return;
    await database.connect(connector: connector);
  }

  /// Disconnects from PowerSync and clears local database storage (e.g. on logout).
  Future<void> disconnectAndClear() async {
    if (_db != null) {
      await _db!.disconnectAndClear();
      _db = null;
      _connector = null;
    }
  }

  /// Disconnects sync connection without clearing cached records.
  Future<void> disconnect() async {
    if (_db != null) {
      await _db!.disconnect();
    }
  }
}
