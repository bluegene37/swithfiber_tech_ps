// Gene - Nov, 28, 2026: DAO managing local-only disk-backed photo attachment mutations for PowerSync v12.
import 'dart:io';

import 'package:sqlite_async/sqlite_async.dart' show SqliteWriteContext;

import '../app_database.dart';
import '../models/pending_attachment.dart';
import '../sql_values.dart';

class PendingAttachmentsDao {
  final AppDatabase _db;

  PendingAttachmentsDao(this._db);

  static const String table = 'pending_attachments';

  static List<PendingAttachment> _map(Iterable<Map<String, Object?>> rows) =>
      [for (final r in rows) PendingAttachment.fromRow(r)];

  Future<void> upsertInTx(
    SqliteWriteContext tx, {
    required String entityType,
    required String entityId,
    required String slotName,
    String? filePath,
    bool deleteFlag = false,
    String status = PendingAttachment.statusPending,
  }) async {
    final now = DateTime.now().toUtc();
    final id =
        PendingAttachment.deterministicId(entityType, entityId, slotName);
    final entry = PendingAttachment(
      id: id,
      entityType: entityType,
      entityId: entityId,
      slotName: slotName,
      filePath: deleteFlag ? null : filePath,
      deleteFlag: deleteFlag,
      status: status,
      createdAt: now,
      updatedAt: now,
    );
    final row = entry.toRow();
    final cols = row.keys.toList();
    await tx.execute(
      insertOrReplaceSql(table, cols),
      [for (final c in cols) row[c]],
    );
  }

  Future<void> upsert({
    required String entityType,
    required String entityId,
    required String slotName,
    String? filePath,
    bool deleteFlag = false,
    String status = PendingAttachment.statusPending,
  }) =>
      _db.writeTransaction(
        (tx) => upsertInTx(
          tx,
          entityType: entityType,
          entityId: entityId,
          slotName: slotName,
          filePath: filePath,
          deleteFlag: deleteFlag,
          status: status,
        ),
      );

  Future<List<PendingAttachment>> getPendingForEntity(
    String entityType,
    String entityId,
  ) async =>
      _map(
        await _db.getAll(
          'SELECT * FROM $table WHERE entity_type = ? AND entity_id = ? AND status = ? ORDER BY updated_at ASC',
          [entityType, entityId, PendingAttachment.statusPending],
        ),
      );

  Future<List<PendingAttachment>> getAllForEntity(
    String entityType,
    String entityId,
  ) async =>
      _map(
        await _db.getAll(
          'SELECT * FROM $table WHERE entity_type = ? AND entity_id = ? ORDER BY updated_at ASC',
          [entityType, entityId],
        ),
      );

  Future<List<PendingAttachment>> getAllPending() async => _map(
        await _db.getAll(
          'SELECT * FROM $table WHERE status = ? ORDER BY created_at ASC',
          [PendingAttachment.statusPending],
        ),
      );

  Future<int> countPending() async {
    final row = await _db.get(
      'SELECT count(*) AS c FROM $table WHERE status = ?',
      [PendingAttachment.statusPending],
    );
    return rowInt(row['c']);
  }

  Stream<int> watchPendingCount() => _db.watch(
        'SELECT count(*) AS c FROM $table WHERE status = ?',
        parameters: [PendingAttachment.statusPending],
      ).map((rows) => rows.isEmpty ? 0 : rowInt(rows.first['c']));

  Future<void> markStatus(
    String entityType,
    String entityId,
    String status,
  ) =>
      _db.execute(
        'UPDATE $table SET status = ?, updated_at = ? WHERE entity_type = ? AND entity_id = ?',
        [status, dateText(DateTime.now().toUtc()), entityType, entityId],
      );

  /// Updates `entity_id` after an offline-created record receives a server numeric ID.
  Future<void> remapEntityId({
    required String entityType,
    required String oldEntityId,
    required String newEntityId,
  }) async {
    final rows = await getAllForEntity(entityType, oldEntityId);
    if (rows.isEmpty) return;
    await _db.writeTransaction((tx) async {
      for (final item in rows) {
        await tx.execute('DELETE FROM $table WHERE id = ?', [item.id]);
        final newId = PendingAttachment.deterministicId(
          entityType,
          newEntityId,
          item.slotName,
        );
        final updated = PendingAttachment(
          id: newId,
          entityType: entityType,
          entityId: newEntityId,
          slotName: item.slotName,
          filePath: item.filePath,
          deleteFlag: item.deleteFlag,
          status: item.status,
          createdAt: item.createdAt,
          updatedAt: DateTime.now().toUtc(),
        );
        final map = updated.toRow();
        final cols = map.keys.toList();
        await tx.execute(
          insertOrReplaceSql(table, cols),
          [for (final c in cols) map[c]],
        );
      }
    });
  }

  Future<void> deleteByIds(
    List<String> ids, {
    bool deleteFiles = true,
  }) async {
    if (ids.isEmpty) return;
    if (deleteFiles) {
      final rows = _map(
        await _db.getAll(
          'SELECT * FROM $table WHERE id IN (${placeholders(ids.length)})',
          ids,
        ),
      );
      await _deleteLocalFiles(rows);
    }
    await _db.execute(
      'DELETE FROM $table WHERE id IN (${placeholders(ids.length)})',
      ids,
    );
  }

  Future<void> deleteForEntity(
    String entityType,
    String entityId, {
    bool deleteFiles = true,
  }) async {
    if (deleteFiles) {
      final rows = await getAllForEntity(entityType, entityId);
      await _deleteLocalFiles(rows);
    }
    await _db.execute(
      'DELETE FROM $table WHERE entity_type = ? AND entity_id = ?',
      [entityType, entityId],
    );
  }

  Future<void> _deleteLocalFiles(List<PendingAttachment> items) async {
    for (final item in items) {
      final path = item.filePath?.trim();
      if (path == null || path.isEmpty) continue;
      // Clean up temporary captured media once uploaded or discarded.
      if (!path.contains('pending_media')) continue;
      try {
        final f = File(path);
        if (await f.exists()) {
          await f.delete();
        }
      } catch (_) {}
    }
  }
}
