import '../../../features/service_orders/models/service_order_model.dart';
import '../app_database.dart';
import '../sql_values.dart';

/// Reads and writes the `service_orders` table through PowerSync.
class ServiceOrdersDao {
  final AppDatabase _db;

  ServiceOrdersDao(this._db);

  static const String table = 'service_orders';
  static const String _byIdDesc = 'ORDER BY CAST(id AS INTEGER) DESC';

  static List<ServiceOrderDto> _map(Iterable<Map<String, Object?>> rows) =>
      [for (final r in rows) ServiceOrderDto.fromRow(r)];

  /// Watch all cached service orders sorted by ID descending.
  Stream<List<ServiceOrderDto>> watchAllOrders() =>
      _db.watch('SELECT * FROM $table $_byIdDesc').map(_map);

  /// Get all service orders once.
  Future<List<ServiceOrderDto>> getAllOrders() async =>
      _map(await _db.getAll('SELECT * FROM $table $_byIdDesc'));

  /// Get a single service order by id.
  Future<ServiceOrderDto?> getOrderById(int id) async {
    final row = await _db.getOptional(
      'SELECT * FROM $table WHERE id = ?',
      [idText(id)],
    );
    return row == null ? null : ServiceOrderDto.fromRow(row);
  }

  /// Insert or update a single service order.
  Future<void> insertOrUpdateOrder(ServiceOrderDto order,
          {bool synced = true}) =>
      insertAllOrders([order], synced: synced);

  /// Batch insert or cache service orders from API.
  Future<void> insertAllOrders(List<ServiceOrderDto> orders,
      {bool synced = true}) async {
    if (orders.isEmpty) return;
    final rows = [for (final o in orders) o.toRow(synced: synced)];
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

  /// Get all unsynced service orders.
  Future<List<ServiceOrderDto>> getUnsyncedOrders() async =>
      _map(await _db.getAll('SELECT * FROM $table WHERE is_synced = 0'));

  /// IDs of rows with local edits not yet synced to the server.
  Future<Set<int>> getUnsyncedIds() async {
    final rows = await _db.getAll('SELECT id FROM $table WHERE is_synced = 0');
    return {for (final r in rows) rowInt(r['id'])};
  }

  /// Count of unsynced items.
  Future<int> countUnsynced() async {
    final row =
        await _db.get('SELECT count(*) AS c FROM $table WHERE is_synced = 0');
    return rowInt(row['c']);
  }

  /// Mark an order as synced.
  Future<void> markAsSynced(int id) => _db.execute(
        'UPDATE $table SET is_synced = 1, updated_at = ? WHERE id = ?',
        [dateText(DateTime.now()), idText(id)],
      );

  /// Delete cached rows that no longer exist on the server, preserving any
  /// row with an unsynced local edit.
  /*
  Future<int> deleteSyncedOrdersNotIn(Set<int> keepIds) async {
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
  */
  // Gene - Oct 3, 2026: Guard deleteSyncedOrdersNotIn against empty keepIds to prevent accidental full cache wipes when remote calls return empty.
  Future<int> deleteSyncedOrdersNotIn(Set<int> keepIds) async {
    if (keepIds.isEmpty) return 0;
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

  /// Delete a single service order.
  Future<void> deleteOrder(int id) =>
      _db.execute('DELETE FROM $table WHERE id = ?', [idText(id)]);

  /// Clear all service orders.
  Future<void> clearAllOrders() => _db.execute('DELETE FROM $table');
}
