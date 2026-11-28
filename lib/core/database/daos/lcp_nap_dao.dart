import 'package:sqlite_async/sqlite_async.dart' show SqliteWriteContext;

import '../../../features/lcp_nap/models/lcp_nap_model.dart';
import '../app_database.dart';
import '../sql_values.dart';

/// Reads and writes the `lcp_nap_locations` table through PowerSync.
class LcpNapLocationsDao {
  final AppDatabase _db;

  LcpNapLocationsDao(this._db);

  static const String table = 'lcp_nap_locations';
  /*
  static const String _byIdAsc = 'ORDER BY CAST(id AS INTEGER) ASC';
  */
  // Gene - Nov, 28, 2026: Sort non-numeric offline UUID creations cleanly alongside numeric IDs.
  static const String _byIdAsc =
      "ORDER BY CASE WHEN id GLOB '[0-9]*' THEN 1 ELSE 0 END ASC, CAST(id AS INTEGER) ASC, id ASC";

  static List<LcpNapDto> _map(Iterable<Map<String, Object?>> rows) =>
      [for (final r in rows) LcpNapDto.fromRow(r)];

  /// Watch all LCP NAP location records reactively
  Stream<List<LcpNapDto>> watchAllLocations() =>
      _db.watch('SELECT * FROM $table $_byIdAsc').map(_map);

  /// Watch a single LCP NAP location by ID
  Stream<LcpNapDto?> watchLocationById(int id) => _db
      .watch('SELECT * FROM $table WHERE id = ?', parameters: [idText(id)]).map(
          (rows) => rows.isEmpty ? null : LcpNapDto.fromRow(rows.first));

  /// Watch locations filtered by LCP cabinet name
  Stream<List<LcpNapDto>> watchLocationsByLcp(String lcpName) {
    if (lcpName.isEmpty || lcpName.toLowerCase() == 'all') {
      return watchAllLocations();
    }
    return _db.watch(
      'SELECT * FROM $table WHERE lcp = ? $_byIdAsc',
      parameters: [lcpName],
    ).map(_map);
  }

  /// Get all locations once
  Future<List<LcpNapDto>> getAllLocations() async =>
      _map(await _db.getAll('SELECT * FROM $table $_byIdAsc'));

  // Gene - Nov, 11, 2026: Added single-row lookup and unsynced queue queries so offline NAP image uploads, deletions, and GPS edits auto-sync on reconnect.
  /// Get a single location by ID
  /*
  Future<LcpNapDto?> getLocationById(int id) async {
    final row = await _db.getOptional(
      'SELECT * FROM $table WHERE id = ?',
      [idText(id)],
    );
    return row == null ? null : LcpNapDto.fromRow(row);
  }
  */
  // Gene - Nov, 28, 2026: Resolve locations by numeric UI id or non-numeric UUID localId.
  Future<LcpNapDto?> getLocationByRowId(String rowId) async {
    final row = await _db.getOptional(
      'SELECT * FROM $table WHERE id = ?',
      [rowId],
    );
    return row == null ? null : LcpNapDto.fromRow(row);
  }

  Future<LcpNapDto?> getLocationById(int id) async {
    final byText = await getLocationByRowId(idText(id));
    if (byText != null) return byText;
    if (id < 0) {
      final all = await getAllLocations();
      for (final loc in all) {
        if (loc.id == id) return loc;
      }
    }
    return null;
  }

  /// Get all locations with pending local photo or GPS edits (`is_synced = 0`)
  Future<List<LcpNapDto>> getUnsyncedLocations() async => _map(
        await _db.getAll(
          'SELECT * FROM $table WHERE is_synced = 0 $_byIdAsc',
        ),
      );

  /// Count locations waiting to sync
  Future<int> countUnsynced() async {
    final row = await _db.get(
      'SELECT count(*) AS c FROM $table WHERE is_synced = 0',
    );
    return rowInt(row['c']);
  }

  /// Insert or update single location
  Future<void> insertOrUpdateLocation(
    LcpNapDto location, {
    bool synced = true,
    bool omitPhotoColumns = false,
  }) =>
      insertAllLocations(
        [location],
        synced: synced,
        omitPhotoColumns: omitPhotoColumns,
      );

  Future<void> insertOrUpdateLocationInTx(
    SqliteWriteContext tx,
    LcpNapDto location, {
    bool synced = true,
    bool omitPhotoColumns = false,
  }) async {
    final row = location.toRow(
      synced: synced,
      omitPhotoColumns: omitPhotoColumns,
    );
    final columns = row.keys.toList();
    final sql = insertOrReplaceSql(table, columns);
    await tx.execute(sql, [for (final c in columns) row[c]]);
  }

  /// Batch insert / cache locations from API
  Future<void> insertAllLocations(
    List<LcpNapDto> locations, {
    bool synced = true,
    bool omitPhotoColumns = false,
  }) async {
    if (locations.isEmpty) return;
    final rows = [
      for (final l in locations)
        l.toRow(synced: synced, omitPhotoColumns: omitPhotoColumns),
    ];
    final columns = rows.first.keys.toList();
    final sql = insertOrReplaceSql(table, columns);
    await _db.writeTransaction((tx) async {
      for (var i = 0; i < rows.length; i += 100) {
        final chunk =
            rows.sublist(i, (i + 100 > rows.length) ? rows.length : i + 100);
        await tx.executeBatch(sql, [
          for (final r in chunk) [for (final c in columns) r[c]],
        ]);
      }
    });
  }

  // Gene - Nov, 13, 2026: Delete cached synced LCP NAP locations removed on the live server while preserving unsynced local edits (`is_synced = 0`).
  /// Drop cached synced rows that no longer exist on the server, preserving
  /// any row with a pending local edit (`is_synced = 0`).
  Future<int> deleteSyncedLocationsNotIn(Set<int> keepIds) async {
    final synced =
        await _db.getAll('SELECT id FROM $table WHERE is_synced = 1');
    final toDelete = [
      for (final r in synced)
        if (!keepIds.contains(rowInt(r['id']))) r['id'],
    ];
    if (toDelete.isEmpty) return 0;
    await _db.writeTransaction((tx) async {
      for (var i = 0; i < toDelete.length; i += 200) {
        final chunk = toDelete.sublist(
            i, (i + 200 > toDelete.length) ? toDelete.length : i + 200);
        await tx.execute(
          'DELETE FROM $table WHERE id IN (${placeholders(chunk.length)})',
          chunk,
        );
      }
    });
    return toDelete.length;
  }

  /// Delete a location
  Future<void> deleteLocation(int id) =>
      _db.execute('DELETE FROM $table WHERE id = ?', [idText(id)]);

  /// Clear all locations
  Future<void> clearAll() => _db.execute('DELETE FROM $table');

  /// Delete test/sample demo locations
  Future<int> deleteSampleLocations() async {
    const where = "street = 'Sample Street'";
    final row = await _db.get('SELECT count(*) AS c FROM $table WHERE $where');
    final count = rowInt(row['c']);
    if (count > 0) await _db.execute('DELETE FROM $table WHERE $where');
    return count;
  }
}
