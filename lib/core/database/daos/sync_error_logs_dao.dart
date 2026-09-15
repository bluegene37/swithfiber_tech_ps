import 'package:uuid/uuid.dart';

import '../app_database.dart';
import '../models/sync_error_log.dart';
import '../sql_values.dart';

/// Reads and writes the on-phone record of pushes the server refused.
///
/// The app is offline-first: a refused edit stays saved locally and retries.
/// That is deliberate, but it used to be silent, so a job could sit on
/// "needs to sync" forever with nothing anywhere saying why. Each attempt
/// that the server refuses is written here instead, with what was sent and
/// what came back, so the failure can be read on the phone that hit it.
class SyncErrorLogsDao {
  final AppDatabase _db;

  SyncErrorLogsDao(this._db);

  static const String table = 'sync_error_logs';

  /// How many entries are kept. Old ones are dropped rather than growing
  /// without bound on a phone that has been offline for a week.
  static const int maxEntries = 200;

  /// Cap on a stored request or response. With images abbreviated a job
  /// order body is a few kilobytes; this only guards against a runaway
  /// server page.
  static const int maxBodyChars = 64 * 1024;

  static const _uuid = Uuid();

  static List<SyncErrorLog> _map(Iterable<Map<String, Object?>> rows) =>
      [for (final r in rows) SyncErrorLog.fromRow(r)];

  String _select({required bool onlyUnresolved}) =>
      'SELECT * FROM $table${onlyUnresolved ? ' WHERE resolved = 0' : ''} '
      'ORDER BY seq DESC';

  /// Newest first, so the screen shows the most recent failure at the top.
  Stream<List<SyncErrorLog>> watchAll({bool onlyUnresolved = false}) =>
      _db.watch(_select(onlyUnresolved: onlyUnresolved)).map(_map);

  Future<List<SyncErrorLog>> getAll({bool onlyUnresolved = false}) async =>
      _map(await _db.getAll(_select(onlyUnresolved: onlyUnresolved)));

  /// Number of records still failing, which is what a badge should show.
  Future<int> countUnresolved() async {
    final row =
        await _db.get('SELECT count(*) AS c FROM $table WHERE resolved = 0');
    return rowInt(row['c']);
  }

  Future<void> log({
    required String entityType,
    required int entityId,
    required String reference,
    required String operation,
    int? statusCode,
    required String message,
    int payloadBytes = 0,
    String requestMethod = '',
    String requestUrl = '',
    String? requestBody,
    String? responseBody,
  }) async {
    await _db.writeTransaction((tx) async {
      await tx.execute(
        'INSERT INTO $table (id, seq, entity_type, entity_id, reference, '
        'operation, status_code, message, payload_bytes, occurred_at, '
        'resolved, request_method, request_url, request_body, response_body) '
        'VALUES (?, (SELECT COALESCE(MAX(seq), 0) + 1 FROM $table), '
        '?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?)',
        [
          _uuid.v4(),
          entityType,
          entityId,
          reference,
          operation,
          statusCode,
          // A server can return a whole HTML error page; keep it readable.
          _clip(message, 2000),
          payloadBytes,
          dateText(DateTime.now()),
          requestMethod,
          requestUrl,
          requestBody == null ? null : _clip(requestBody, maxBodyChars),
          responseBody == null ? null : _clip(responseBody, maxBodyChars),
        ],
      );
      // Trimmed by seq, not occurredAt: several failures in one sync pass
      // share the same second, and a timestamp cutoff then deletes nothing.
      await tx.execute(
        'DELETE FROM $table WHERE seq <= '
        '(SELECT MAX(seq) FROM $table) - ?',
        [maxEntries],
      );
    });
  }

  static String _clip(String s, int max) => s.length > max
      ? '${s.substring(0, max)}\n… (${s.length - max} more characters)'
      : s;

  /// Called when a record finally syncs, so its past failures stop counting
  /// as outstanding. The history stays readable until it is cleared.
  Future<void> markResolved(String entityType, int entityId) => _db.execute(
        'UPDATE $table SET resolved = 1 '
        'WHERE entity_type = ? AND entity_id = ? AND resolved = 0',
        [entityType, entityId],
      );

  Future<void> clearAll() => _db.execute('DELETE FROM $table');
}
