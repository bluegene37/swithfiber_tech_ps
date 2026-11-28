import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:powersync/powersync.dart';
import 'package:sqlite_async/sqlite_async.dart' show SqliteWriteContext;

import '../sync/powersync_schema.dart';
import 'daos/job_orders_dao.dart';
import 'daos/lcp_nap_dao.dart';
import 'daos/service_orders_dao.dart';
import 'daos/sync_error_logs_dao.dart';
// Gene - Nov, 26, 2026: Added WorkTimingHistoryDao import and getter on AppDatabase.
import 'daos/work_timing_history_dao.dart';
// Gene - Nov, 28, 2026: Added PowerSync v12 DAOs for lookups, pending_attachments, sync_conflicts, and local_id_map.
import 'daos/local_id_map_dao.dart';
import 'daos/lookups_dao.dart';
import 'daos/pending_attachments_dao.dart';
import 'daos/sync_conflicts_dao.dart';

/// The app's local database: a [PowerSyncDatabase] opened on
/// [powerSyncSchema], with one DAO per table.
///
/// Production opens the database through [PowerSyncService] and wraps it
/// here; tests use [AppDatabase.forTesting], which opens a throwaway file
/// (PowerSync needs a real path: its read pool and write isolate cannot share
/// an in-memory database) and deletes it on [close].
class AppDatabase {
  final PowerSyncDatabase db;
  final Directory? _tempDir;

  AppDatabase(this.db) : _tempDir = null;

  AppDatabase._(this.db, this._tempDir);

  /// A fresh, empty database in a temporary directory, silent in the test
  /// log. Safe to call synchronously: PowerSync finishes opening on first
  /// use.
  factory AppDatabase.forTesting() {
    final dir = Directory.systemTemp.createTempSync('switchfiber_test_');
    // Opened in the root zone on purpose. PowerSync runs its writes on a
    // separate isolate and finishes opening through timers and port
    // callbacks; created inside a `testWidgets` body those would belong to
    // the fake-async zone, never fire unless pumped, and leave `close()`
    // waiting on an initialization that cannot complete.
    final database = Zone.root.run(
      () => PowerSyncDatabase(
        schema: powerSyncSchema,
        path: p.join(dir.path, 'test.db'),
        logger: Logger.detached('powersync.test')..level = Level.OFF,
      ),
    );
    return AppDatabase._(database, dir);
  }

  late final JobOrdersDao jobOrdersDao = JobOrdersDao(this);
  late final ServiceOrdersDao serviceOrdersDao = ServiceOrdersDao(this);
  late final LcpNapLocationsDao lcpNapLocationsDao = LcpNapLocationsDao(this);
  late final SyncErrorLogsDao syncErrorLogsDao = SyncErrorLogsDao(this);
  // Gene - Nov, 26, 2026: Expose workTimingHistoryDao on AppDatabase.
  late final WorkTimingHistoryDao workTimingHistoryDao =
      WorkTimingHistoryDao(this);
  // Gene - Nov, 28, 2026: Expose PowerSync v12 operational & lookup DAOs.
  late final PendingAttachmentsDao pendingAttachmentsDao =
      PendingAttachmentsDao(this);
  late final SyncConflictsDao syncConflictsDao = SyncConflictsDao(this);
  late final LocalIdMapDao localIdMapDao = LocalIdMapDao(this);
  late final LookupsDao lookupsDao = LookupsDao(this);

  // Every query goes through these so nothing runs before PowerSync has
  // finished applying the schema. Writes and reads await that on their own
  // inside the SDK, but `watch` does not: a subscription opened straight
  // after construction (which is when every signals class opens one) would
  // fail with "no such table". Awaiting the same future everywhere costs
  // nothing once it has completed.

  Future<void> get ready => db.initialize();

  /// Set as soon as [close] starts, so a background worker still running
  /// (a sync retry after the screen that started it is gone) gets a plain
  /// [StateError] it can catch, instead of the connection pool's own
  /// "closed" exception, which sqlite_async raises from inside its lock
  /// context where no caller can catch it.
  bool _closing = false;

  /// Microtasks and timers on the real event loop, whatever zone the caller
  /// is in. This is the same construction `WidgetTester.runAsync` uses.
  ///
  /// The zone is forked from the caller's rather than taken from the root on
  /// purpose: Dart only hands a future's error to a listener in the same
  /// error zone, and a test zone has its own handler, so an operation run
  /// in the root zone that failed would crash the isolate instead of
  /// reaching the caller's `catch`. A fork without an error handler stays
  /// in the caller's error zone.
  static final ZoneSpecification _realAsync = ZoneSpecification(
    scheduleMicrotask: (self, parent, zone, f) =>
        Zone.root.scheduleMicrotask(() => zone.runGuarded(f)),
    createTimer: (self, parent, zone, duration, f) =>
        Zone.root.createTimer(duration, () => zone.runGuarded(f)),
    createPeriodicTimer: (self, parent, zone, period, f) => Zone.root
        .createPeriodicTimer(period, (timer) => zone.runUnaryGuarded(f, timer)),
  );

  static Zone get _dbZone => Zone.current.fork(specification: _realAsync);

  /// Runs [op] on real time once the database is open.
  ///
  /// A query holds a pooled connection until its callback chain completes.
  /// Started from a widget test's fake-async zone, that chain would resume
  /// only when the test pumps, so the connection would stay checked out and
  /// `close()` would wait on it forever. Running the operation's internals
  /// on the real event loop keeps the lock lifecycle out of the caller's
  /// zone; the caller still awaits the result in its own.
  Future<T> _run<T>(Future<T> Function() op) => _dbZone.run(() async {
        if (_closing) {
          throw StateError('AppDatabase is closed');
        }
        await ready;
        if (_closing) {
          throw StateError('AppDatabase is closed');
        }
        return op();
      });

  /// A live query. Re-emits whenever a table it reads from changes.
  ///
  /// The underlying subscription runs on real time (see [_realAsync]).
  /// PowerSync's change notifications and throttling run on timers and
  /// isolate ports; created from a widget test's fake-async zone they would
  /// only advance when the test pumps, and `close()` would wait on them
  /// forever. Listeners still receive rows in their own zone.
  Stream<List<Map<String, Object?>>> watch(String sql,
      {List<Object?> parameters = const []}) {
    late StreamController<List<Map<String, Object?>>> controller;
    StreamSubscription<List<Map<String, Object?>>>? inner;
    controller = StreamController(
      onListen: () => _dbZone.run(() {
        if (_closing) {
          controller.close();
          return;
        }
        inner = Stream.fromFuture(ready)
            .asyncExpand((_) => db.watch(sql, parameters: parameters))
            .listen(controller.add,
                onError: controller.addError, onDone: controller.close);
      }),
      onCancel: () => inner?.cancel(),
    );
    return controller.stream;
  }

  Future<List<Map<String, Object?>>> getAll(String sql,
          [List<Object?> parameters = const []]) =>
      _run(() => db.getAll(sql, parameters));

  Future<Map<String, Object?>> get(String sql,
          [List<Object?> parameters = const []]) =>
      _run(() => db.get(sql, parameters));

  Future<Map<String, Object?>?> getOptional(String sql,
          [List<Object?> parameters = const []]) =>
      _run(() => db.getOptional(sql, parameters));

  Future<void> execute(String sql, [List<Object?> parameters = const []]) =>
      _run(() => db.execute(sql, parameters));

  Future<T> writeTransaction<T>(
          Future<T> Function(SqliteWriteContext tx) action) =>
      _run(() => db.writeTransaction(action));

  /// Closes the database. Cancel any `watch` subscriptions first; a stream
  /// still listening when the connection goes away ends with an error.
  Future<void> close() async {
    _closing = true;
    if (!db.closed) {
      await db.close();
    }
    final dir = _tempDir;
    if (dir != null && dir.existsSync()) {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {
        // A file still held by the closing isolate; the OS temp dir cleans up.
      }
    }
  }
}
