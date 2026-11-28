// Gene - Nov, 28, 2026: DAO mapping client-generated offline UUIDs to server-assigned numeric IDs (PowerSync v12).
import '../app_database.dart';
import '../sql_values.dart';

class LocalIdMapDao {
  final AppDatabase _db;

  LocalIdMapDao(this._db);

  static const String table = 'local_id_map';

  Future<void> putMapping({
    required String entityType,
    required String localId,
    required String serverId,
  }) async {
    final id = '${entityType}_$localId';
    await _db.execute(
      insertOrReplaceSql(table, const [
        'id',
        'entity_type',
        'local_id',
        'server_id',
        'created_at',
      ]),
      [
        id,
        entityType,
        localId,
        serverId,
        dateText(DateTime.now().toUtc()),
      ],
    );
  }

  Future<String?> resolveServerId({
    required String entityType,
    required String localId,
  }) async {
    final row = await _db.getOptional(
      'SELECT server_id FROM $table WHERE entity_type = ? AND local_id = ? LIMIT 1',
      [entityType, localId],
    );
    final resolved = rowText(row?['server_id'])?.trim();
    return (resolved != null && resolved.isNotEmpty) ? resolved : null;
  }

  Future<Map<String, String>> getAllForEntityType(String entityType) async {
    final rows = await _db.getAll(
      'SELECT local_id, server_id FROM $table WHERE entity_type = ?',
      [entityType],
    );
    final result = <String, String>{};
    for (final row in rows) {
      final localId = rowText(row['local_id'])?.trim();
      final serverId = rowText(row['server_id'])?.trim();
      if (localId != null &&
          localId.isNotEmpty &&
          serverId != null &&
          serverId.isNotEmpty) {
        result[localId] = serverId;
      }
    }
    return result;
  }
}
