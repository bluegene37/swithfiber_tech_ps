import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';
import 'package:swithfiber_tech_ps/core/constants/app_constants.dart';
import 'package:swithfiber_tech_ps/core/database/daos/sync_error_logs_dao.dart';
import 'package:swithfiber_tech_ps/core/storage/secure_storage_service.dart';
import 'package:swithfiber_tech_ps/core/sync/powersync_backend_connector.dart';
import 'package:swithfiber_tech_ps/core/sync/powersync_schema.dart';

/// Singleton owning the PowerSync client database: the app's only local
/// store. Opens it on [activePowerSyncSchema] and, when a PowerSync endpoint
/// has been configured, joins the self-hosted PowerSync sync connection.
class PowerSyncService {
  PowerSyncService._();
  static final PowerSyncService instance = PowerSyncService._();

  PowerSyncDatabase? _db;
  SwitchFiberBackendConnector? _connector;
  // Gene - Nov, 27, 2026: Track replicated mode, statusStream, upload hooks, and ps_crud counts for live PowerSync sync.
  bool _replicatedMode = false;

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

  bool get isReplicatedMode => _replicatedMode;

  /// Whether the cloud sync connection is currently open.
  bool get isConnected => _db?.connected ?? false;

  Stream<SyncStatus>? get statusStream => _db?.statusStream;

  SyncStatus? get currentStatus => _db?.currentStatus;

  /// Opens the local database. Idempotent.
  /*
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
  */
  Future<void> initialize({
    String? dbFilename,
    SwitchFiberBackendConnector? connector,
    bool? replicated,
    SyncErrorLogsDao? errorLog,
    void Function(String table, int entityId)? onEntityUploaded,
  }) async {
    if (_db != null) return;

    /*
    final useReplicated = replicated ??
        (connector?.hasEndpoint ?? AppConstants.isPowerSyncConfigured);
    */
    // Gene - Nov, 28, 2026: Ensure replicated mode with a connector requires a gateway or upload hook, and never attach a no-op onUpload handler in replicated mode.
    final useReplicated = replicated ??
        (connector != null
            ? (connector.hasEndpoint &&
                (connector.hasGateway ||
                    connector.onUpload != null ||
                    connector.onEntryUpload != null))
            : AppConstants.isPowerSyncConfigured);
    final resolvedFilename = dbFilename ??
        (useReplicated
            ? 'switchfiber_powersync_v11.db'
            : 'switchfiber_powersync.db');

    final dir = await getApplicationSupportDirectory();
    final database = PowerSyncDatabase(
      schema: activePowerSyncSchema(replicated: useReplicated),
      path: join(dir.path, resolvedFilename),
    );
    await database.initialize();

    _replicatedMode = useReplicated;
    if (connector != null) {
      if (errorLog != null) connector.errorLog = errorLog;
      if (onEntityUploaded != null) {
        connector.onEntityUploaded = onEntityUploaded;
      }
      _connector = connector;
      /*
    } else if (useReplicated &&
        AppConstants.defaultPowerSyncGatewayUrl.trim().isNotEmpty) {
    */
    } else if (useReplicated) {
      _connector = SwitchFiberBackendConnector(
        errorLog: errorLog,
        onEntityUploaded: onEntityUploaded,
      );
    } else {
      _connector = SwitchFiberBackendConnector(
        onUpload: (tx) async {
          // In local-only / REST mode, local writes are acknowledged so
          // ps_crud never stalls.
        },
      );
    }
    _db = database;
  }

  /// Registers error logging and cache-invalidation callbacks on the active connector.
  void setUploadHooks({
    SyncErrorLogsDao? errorLog,
    void Function(String table, int entityId)? onEntityUploaded,
  }) {
    final connector = _connector;
    if (connector == null) return;
    if (errorLog != null) connector.errorLog = errorLog;
    if (onEntityUploaded != null) {
      connector.onEntityUploaded = onEntityUploaded;
    }
  }

  /// Returns the count of pending local mutations queued in `ps_crud`.
  Future<int> countPendingCrud() async {
    final database = _db;
    if (database == null || !_replicatedMode) return 0;
    try {
      final row =
          await database.getOptional('SELECT count(*) AS c FROM ps_crud');
      final val = row?['c'];
      if (val is int) return val;
      if (val is num) return val.toInt();
      return int.tryParse(val?.toString() ?? '0') ?? 0;
    } catch (_) {
      return 0;
    }
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
  /*
  Future<void> disconnectAndClear() async {
    if (_db != null) {
      await _db!.disconnectAndClear();
      _db = null;
      _connector = null;
    }
    _replicatedMode = false;
  }
  */
  // Gene - Nov, 27, 2026: Keep _db and _connector open across logout->login transitions so AppDatabase and reconnect() remain valid without app restart.
  Future<void> disconnectAndClear() async {
    if (_db != null) {
      await _db!.disconnectAndClear();
    }
  }

  /// Disconnects sync connection without clearing cached records.
  Future<void> disconnect() async {
    if (_db != null) {
      await _db!.disconnect();
    }
  }
}
