import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';
import 'package:swithfiber_tech_ps/core/sync/powersync_backend_connector.dart';
import 'package:swithfiber_tech_ps/core/sync/powersync_schema.dart';

/// Singleton service managing the PowerSync client database lifecycle,
/// schema initialization, and cloud synchronization.
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

  /// Initializes the local SQLite database with PowerSync schema and
  /// connects to the PowerSync Cloud service.
  Future<void> initialize({
    String dbFilename = 'switchfiber_powersync.db',
    SwitchFiberBackendConnector? connector,
  }) async {
    if (_db != null) return;

    final dir = await getApplicationSupportDirectory();
    final dbPath = join(dir.path, dbFilename);

    final database = PowerSyncDatabase(
      schema: powerSyncSchema,
      path: dbPath,
    );

    await database.initialize();

    final activeConnector = connector ?? SwitchFiberBackendConnector();
    _connector = activeConnector;

    await database.connect(connector: activeConnector);
    _db = database;
  }

  /// Disconnects from PowerSync and clears local database storage (e.g. on logout).
  Future<void> disconnectAndClear() async {
    if (_db != null) {
      await _db!.disconnectAndClear();
      _db = null;
    }
  }

  /// Disconnects sync connection without clearing cached records.
  Future<void> disconnect() async {
    if (_db != null) {
      await _db!.disconnect();
    }
  }
}
