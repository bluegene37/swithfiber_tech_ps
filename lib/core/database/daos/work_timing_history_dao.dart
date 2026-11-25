// Gene - Nov, 26, 2026: DAO for persisting and querying technician Start/Finish/Stop work timing sessions by userId and date.
import 'package:uuid/uuid.dart';

import '../../widgets/work_timing_bar.dart';
import '../app_database.dart';
import '../models/work_timing_entry.dart';
import '../sql_values.dart';

/// Reads and writes `work_timing_history` rows in PowerSync SQLite.
class WorkTimingHistoryDao {
  final AppDatabase _db;

  WorkTimingHistoryDao(this._db);

  static const String table = 'work_timing_history';
  static const _uuid = Uuid();

  static List<WorkTimingEntry> _map(Iterable<Map<String, Object?>> rows) =>
      [for (final r in rows) WorkTimingEntry.fromRow(r)];

  /// Records a new `Start` (or `Start Again`) work session and returns its ID.
  Future<String> recordStart({
    required String orderType,
    required int orderId,
    required String orderReference,
    required String customerName,
    required String userId,
    String? userName,
    required DateTime startTime,
    bool isSynced = false,
  }) async {
    final id = _uuid.v4();
    final workDate = formatTimingDateKey(startTime);
    await _db.execute(
      'INSERT INTO $table (id, order_type, order_id, order_reference, '
      'customer_name, user_id, user_name, work_date, start_time, end_time, '
      'duration_minutes, is_synced, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?, ?)',
      [
        id,
        orderType,
        orderId,
        orderReference,
        customerName,
        userId,
        userName,
        workDate,
        dateText(startTime),
        boolInt(isSynced),
        dateText(DateTime.now().toUtc()),
      ],
    );
    return id;
  }

  /// Completes the latest open session for `(orderType, orderId, userId)`, or
  /// inserts a completed session when none is open, returning the row ID.
  Future<String> recordFinish({
    required String orderType,
    required int orderId,
    required String orderReference,
    required String customerName,
    required String userId,
    String? userName,
    required DateTime startTime,
    required DateTime endTime,
    bool isSynced = false,
  }) async {
    final durationMins =
        endTime.difference(startTime).inMinutes.clamp(1, 999999);
    final openRow = await _db.getOptional(
      'SELECT id, start_time FROM $table '
      'WHERE order_type = ? AND order_id = ? AND user_id = ? AND end_time IS NULL '
      'ORDER BY start_time DESC, created_at DESC LIMIT 1',
      [orderType, orderId, userId],
    );

    if (openRow != null) {
      final id = openRow['id']?.toString() ?? _uuid.v4();
      final rowStart = rowDate(openRow['start_time']) ?? startTime;
      final effectiveMins =
          endTime.difference(rowStart).inMinutes.clamp(1, 999999);
      await _db.execute(
        'UPDATE $table SET end_time = ?, duration_minutes = ?, is_synced = ? '
        'WHERE id = ?',
        [
          dateText(endTime),
          effectiveMins,
          boolInt(isSynced),
          id,
        ],
      );
      return id;
    }

    final id = _uuid.v4();
    await _db.execute(
      'INSERT INTO $table (id, order_type, order_id, order_reference, '
      'customer_name, user_id, user_name, work_date, start_time, end_time, '
      'duration_minutes, is_synced, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        id,
        orderType,
        orderId,
        orderReference,
        customerName,
        userId,
        userName,
        formatTimingDateKey(startTime),
        dateText(startTime),
        dateText(endTime),
        durationMins,
        boolInt(isSynced),
        dateText(DateTime.now().toUtc()),
      ],
    );
    return id;
  }

  /// Updates the remote sync status of a single history row.
  Future<void> markSynced(String id, {bool isSynced = true}) => _db.execute(
        'UPDATE $table SET is_synced = ? WHERE id = ?',
        [boolInt(isSynced), id],
      );

  (String, List<Object?>) _buildUserDateQuery({
    String? userId,
    String? workDate,
    String? orderType,
  }) {
    final where = <String>[];
    final params = <Object?>[];

    if (userId != null && userId.trim().isNotEmpty) {
      where.add('user_id = ?');
      params.add(userId.trim());
    }
    if (workDate != null && workDate.trim().isNotEmpty) {
      where.add('work_date = ?');
      params.add(workDate.trim());
    }
    if (orderType != null && orderType.trim().isNotEmpty) {
      where.add('order_type = ?');
      params.add(orderType.trim());
    }

    final clause = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')} ';
    return (
      'SELECT * FROM $table ${clause}ORDER BY start_time DESC, created_at DESC',
      params,
    );
  }

  /// Reactive stream of timing history filtered by [userId], [workDate] (`YYYY-MM-DD`),
  /// and optional [orderType].
  Stream<List<WorkTimingEntry>> watchByUserAndDate({
    String? userId,
    String? workDate,
    String? orderType,
  }) {
    final (sql, params) = _buildUserDateQuery(
      userId: userId,
      workDate: workDate,
      orderType: orderType,
    );
    return _db.watch(sql, parameters: params).map(_map);
  }

  /// One-shot query of timing history filtered by [userId] and [workDate].
  Future<List<WorkTimingEntry>> getByUserAndDate({
    String? userId,
    String? workDate,
    String? orderType,
  }) async {
    final (sql, params) = _buildUserDateQuery(
      userId: userId,
      workDate: workDate,
      orderType: orderType,
    );
    return _map(await _db.getAll(sql, params));
  }

  /// Reactive stream of all timing sessions for a specific Job Order or Service Order.
  Stream<List<WorkTimingEntry>> watchByOrder({
    required String orderType,
    required int orderId,
  }) =>
      _db.watch(
        'SELECT * FROM $table WHERE order_type = ? AND order_id = ? '
        'ORDER BY start_time DESC, created_at DESC',
        parameters: [orderType, orderId],
      ).map(_map);

  /// One-shot query of all timing sessions for a specific Job Order or Service Order.
  Future<List<WorkTimingEntry>> getByOrder({
    required String orderType,
    required int orderId,
  }) async =>
      _map(await _db.getAll(
        'SELECT * FROM $table WHERE order_type = ? AND order_id = ? '
        'ORDER BY start_time DESC, created_at DESC',
        [orderType, orderId],
      ));

  Future<void> clearAll() => _db.execute('DELETE FROM $table');
}
