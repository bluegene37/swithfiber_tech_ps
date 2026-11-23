import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';
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

    _connector = connector ??
        SwitchFiberBackendConnector(
          onUpload: (tx) async {
            // In hybrid REST mode, downstream changes flow via PowerSync, while
            // REST sync operations or local writes are acknowledged so ps_crud
            // does not throw StateError or stall replication streaming.
          },
        );
    _db = database;
  }

  /// Connects to the PowerSync service using the configured connector.
  Future<void> connectIfConfigured({SecureStorageService? storage}) async {
    final database = _db;
    final connector = _connector;
    // Gene - Nov, 23, 2026: Stay cleanly in local-only mode when POWERSYNC_ENDPOINT is not configured.
    if (database == null ||
        connector == null ||
        !connector.hasEndpoint ||
        database.connected) {
      return;
    }
    try {
      await database.connect(connector: connector);
    } catch (_) {
      // Offline or initial network failure: PowerSync client retries automatically.
    }
  }

  /// Forces a fresh credentials fetch and reconnects to PowerSync with the current user.
  Future<void> reconnect() async {
    final database = _db;
    final connector = _connector;
    if (database == null || connector == null || !connector.hasEndpoint) return;
    try {
      if (database.connected) {
        await database.disconnect();
      }
      await database.connect(connector: connector);
    } catch (_) {
      // Offline or initial network failure: PowerSync retries automatically.
    }
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
