import '../../../features/lcp_nap/models/lcp_nap_model.dart';
import '../app_database.dart';
import '../sql_values.dart';

/// Reads and writes the `lcp_nap_locations` table through PowerSync.
class LcpNapLocationsDao {
  final AppDatabase _db;

  LcpNapLocationsDao(this._db);

  static const String table = 'lcp_nap_locations';
  static const String _byIdAsc = 'ORDER BY CAST(id AS INTEGER) ASC';

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

  /// Insert or update single location
  Future<void> insertOrUpdateLocation(LcpNapDto location,
          {bool synced = true}) =>
      insertAllLocations([location], synced: synced);

  /// Batch insert / cache locations from API
  Future<void> insertAllLocations(List<LcpNapDto> locations,
      {bool synced = true}) async {
    if (locations.isEmpty) return;
    final rows = [for (final l in locations) l.toRow(synced: synced)];
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
