// Gene - Nov, 28, 2026: DAO managing non-blocking 409 conflict alerts (REASSIGNED / CANCELLED) surfaced in Needs Review UI.
import '../app_database.dart';
import '../models/sync_conflict.dart';
import '../sql_values.dart';
import 'pending_attachments_dao.dart';

class SyncConflictsDao {
  final AppDatabase _db;

  SyncConflictsDao(this._db);

  static const String table = 'sync_conflicts';

  static List<SyncConflict> _map(Iterable<Map<String, Object?>> rows) =>
      [for (final r in rows) SyncConflict.fromRow(r)];

  Future<String> recordConflict({
    required String entityType,
    required String entityId,
    required String reason,
    int statusCode = 409,
    required String message,
    required String serverSnapshot,
    required String localPayload,
  }) async {
    final existing = await _db.getAll(
      'SELECT * FROM $table WHERE entity_type = ? AND entity_id = ? AND resolved = 0',
      [entityType, entityId],
    );
    for (final row in existing) {
      if ((rowText(row['reason']) ?? '') == reason &&
          (rowText(row['local_payload']) ?? '') == localPayload) {
        return rowText(row['id']) ?? '';
      }
    }

    final now = DateTime.now().toUtc();
    final id =
        'conflict_${entityType}_${entityId}_${now.microsecondsSinceEpoch}';
    final entry = SyncConflict(
      id: id,
      entityType: entityType,
      entityId: entityId,
      reason: reason,
      statusCode: statusCode,
      message: message,
      serverSnapshot: serverSnapshot,
      localPayload: localPayload,
      resolved: false,
      createdAt: now,
    );
    final map = entry.toRow();
    final cols = map.keys.toList();
    await _db.execute(
      insertOrReplaceSql(table, cols),
      [for (final c in cols) map[c]],
    );
    return id;
  }

  Stream<List<SyncConflict>> watchUnresolved() => _db
      .watch('SELECT * FROM $table WHERE resolved = 0 ORDER BY created_at DESC')
      .map(_map);

  Future<List<SyncConflict>> getUnresolved() async => _map(
        await _db.getAll(
          'SELECT * FROM $table WHERE resolved = 0 ORDER BY created_at DESC',
        ),
      );

  Future<int> countUnresolved() async {
    final row = await _db.get(
      'SELECT count(*) AS c FROM $table WHERE resolved = 0',
    );
    return rowInt(row['c']);
  }

  Future<void> markResolved(
    String id, {
    PendingAttachmentsDao? pendingAttachmentsDao,
  }) async {
    final row =
        await _db.getOptional('SELECT * FROM $table WHERE id = ?', [id]);
    await _db.execute('UPDATE $table SET resolved = 1 WHERE id = ?', [id]);
    if (row != null && pendingAttachmentsDao != null) {
      final conflict = SyncConflict.fromRow(row);
      await pendingAttachmentsDao.deleteForEntity(
        conflict.entityType,
        conflict.entityId,
      );
    }
  }

  Future<void> clearAll() => _db.execute('DELETE FROM $table');
}
