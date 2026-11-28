// Gene - Nov, 28, 2026: DAO managing the 11 PowerSync v12 local-only lookup tables populated via GET /api/sync/lookups.
import '../../../features/catalogs/models/catalog_model.dart';
import '../app_database.dart';
import '../sql_values.dart';

class LookupsDao {
  final AppDatabase _db;

  LookupsDao(this._db);

  static const List<String> allTableNames = [
    'inventory_items',
    'inventory_categories',
    'inventory_logs',
    'plans',
    'lcp',
    'nap',
    'vlans',
    'lcpnap',
    'ports',
    'lcpnap_ports',
    'routers',
  ];

  static const Map<String, List<String>> tableColumns = {
    'inventory_items': [
      'id',
      'item_id',
      'name',
      'description',
      'category',
      'supplier',
      'quantity',
      'image',
      'user_email',
      'modified_by',
      'modified_date',
    ],
    'inventory_categories': [
      'id',
      'name',
      'description',
      'modified_by',
      'modified_date',
    ],
    'inventory_logs': [
      'id',
      'item_id',
      'quantity',
      'requested_by',
      'requested_with',
      'status',
      'remarks',
      'created_date',
    ],
    'plans': [
      'id',
      'name',
      'description',
      'amount',
      'discount_id',
      'created_by',
      'created_date',
      'modified_by',
      'modified_date',
    ],
    'lcp': [
      'id',
      'name',
      'description',
      'created_by',
      'created_date',
      'modified_by',
      'modified_date',
    ],
    'nap': [
      'id',
      'name',
      'description',
      'created_by',
      'created_date',
      'modified_by',
      'modified_date',
    ],
    'vlans': [
      'id',
      'name',
      'description',
      'created_by',
      'created_date',
      'modified_by',
      'modified_date',
    ],
    'lcpnap': [
      'id',
      'name',
      'description',
      'created_by',
      'created_date',
      'modified_by',
      'modified_date',
    ],
    'ports': [
      'id',
      'name',
      'description',
      'created_by_user_id',
      'created_date',
      'modified_by_user_id',
      'modified_date',
    ],
    'lcpnap_ports': [
      'id',
      'name',
      'description',
      'created_by_user_id',
      'created_date',
      'modified_by_user_id',
      'modified_date',
    ],
    'routers': [
      'id',
      'name',
      'description',
      'brand',
      'model',
      'created_by',
      'created_date',
      'modified_by',
      'modified_date',
    ],
  };

  /// Atomically replaces all 11 lookup tables inside a single writeTransaction.
  Future<void> replaceAllLookups(
    Map<String, List<Map<String, dynamic>>> tables,
  ) async {
    final normalizedInput = <String, List<Map<String, dynamic>>>{};
    for (final entry in tables.entries) {
      normalizedInput[entry.key.trim().toLowerCase()] = entry.value;
    }

    await _db.writeTransaction((tx) async {
      for (final table in allTableNames) {
        await tx.execute('DELETE FROM $table');
        final rows = normalizedInput[table] ?? const [];
        if (rows.isEmpty) continue;
        final cols = tableColumns[table]!;
        final sql = insertOrReplaceSql(table, cols);
        for (var i = 0; i < rows.length; i += 200) {
          final chunk = rows.sublist(
            i,
            (i + 200 > rows.length) ? rows.length : i + 200,
          );
          final paramBatches = <List<Object?>>[];
          for (var j = 0; j < chunk.length; j++) {
            paramBatches.add(_extractRowValues(table, chunk[j], cols, i + j));
          }
          await tx.executeBatch(sql, paramBatches);
        }
      }
    });
  }

  static List<Object?> _extractRowValues(
    String table,
    Map<String, dynamic> raw,
    List<String> cols,
    int rowIndex,
  ) {
    final lowerMap = <String, dynamic>{};
    for (final entry in raw.entries) {
      lowerMap[_canonicalKey(entry.key)] = entry.value;
    }

    final values = <Object?>[];
    for (final col in cols) {
      if (col == 'id') {
        final rawId = lowerMap['id'] ??
            lowerMap['${table}_id'] ??
            lowerMap['itemid'] ??
            'row_$rowIndex';
        values.add(rawId.toString());
        continue;
      }
      final val = lowerMap[col.replaceAll('_', '')] ?? raw[col];
      values.add(_coerceColumnValue(table, col, val));
    }
    return values;
  }

  static String _canonicalKey(String key) =>
      key.toLowerCase().replaceAll('_', '');

  static Object? _coerceColumnValue(String table, String col, Object? val) {
    if (val == null) return null;
    if (col == 'amount') {
      return rowDouble(val) ?? 0.0;
    }
    /*
    if (col == 'quantity' ||
        col == 'discount_id' ||
        col == 'created_by_user_id' ||
        col == 'modified_by_user_id') {
      return rowIntOrNull(val);
    }
    */
    // Gene - Nov, 28, 2026: Store ports user IDs as text and keep integer lookup counts coerced cleanly; preserve naive Manila timestamps verbatim.
    if (col == 'quantity' || col == 'discount_id') {
      return rowIntOrNull(val);
    }
    return val.toString();
  }

  Future<List<PlanDto>> getPlans() async {
    final rows = await _db
        .getAll('SELECT * FROM plans ORDER BY CAST(id AS INTEGER) ASC');
    return [
      for (final r in rows)
        PlanDto(
          id: rowInt(r['id']),
          name: rowText(r['name'])?.trim() ?? '',
          description: rowText(r['description'])?.trim() ?? '',
          amount: rowDouble(r['amount']) ?? 0.0,
          discountId: rowIntOrNull(r['discount_id']),
        ),
    ];
  }

  Future<List<RouterDto>> getRouters() async {
    final rows = await _db.getAll(
      'SELECT * FROM routers ORDER BY CAST(id AS INTEGER) ASC',
    );
    return [
      for (final r in rows)
        RouterDto(
          id: rowInt(r['id']),
          name: rowText(r['name'])?.trim() ?? '',
          description: rowText(r['description'])?.trim() ?? '',
          brand: rowText(r['brand'])?.trim() ?? '',
          model: rowText(r['model'])?.trim() ?? '',
        ),
    ];
  }

  Future<List<LcpOptionDto>> getLcps() async {
    final rows = await _db.getAll('SELECT * FROM lcp ORDER BY name ASC');
    return [
      for (final r in rows)
        LcpOptionDto(
          id: rowInt(r['id']),
          name: rowText(r['name'])?.trim() ?? '',
          description: rowText(r['description'])?.trim() ?? '',
        ),
    ];
  }

  Future<List<NapDto>> getNaps() async {
    final rows = await _db.getAll('SELECT * FROM nap ORDER BY name ASC');
    return [
      for (final r in rows)
        NapDto(
          id: rowInt(r['id']),
          name: rowText(r['name'])?.trim() ?? '',
          description: rowText(r['description'])?.trim() ?? '',
          createdDate: parseManilaLocalDate(r['created_date']),
        ),
    ];
  }

  Future<List<PortDto>> getPorts() async {
    final rows = await _db.getAll('SELECT * FROM ports ORDER BY name ASC');
    return [
      for (final r in rows)
        PortDto(
          id: rowInt(r['id']),
          name: rowText(r['name'])?.trim() ?? '',
          description: rowText(r['description'])?.trim() ?? '',
          createdByUserId: rowIntOrNull(r['created_by_user_id']),
          createdDate: parseManilaLocalDate(r['created_date']),
        ),
    ];
  }

  Future<List<InventoryItemDto>> getInventoryItems() async {
    final rows =
        await _db.getAll('SELECT * FROM inventory_items ORDER BY name ASC');
    return [
      for (final r in rows)
        InventoryItemDto(
          id: rowInt(r['id']),
          itemId: rowText(r['item_id'])?.trim() ?? '',
          name: rowText(r['name'])?.trim() ?? '',
          description: rowText(r['description'])?.trim() ?? '',
          category: rowText(r['category'])?.trim(),
          supplier: rowText(r['supplier'])?.trim() ?? '',
          quantity: rowInt(r['quantity']),
          image: rowText(r['image'])?.trim(),
          userEmail: rowText(r['user_email'])?.trim(),
          modifiedDate: parseManilaLocalDate(r['modified_date']),
        ),
    ];
  }

  Future<List<Map<String, Object?>>> getRawTable(String tableName) {
    if (!allTableNames.contains(tableName)) {
      throw ArgumentError('Unsupported lookup table: $tableName');
    }
    return _db.getAll('SELECT * FROM $tableName ORDER BY name ASC');
  }

  Future<List<Map<String, Object?>>> getVlans() => getRawTable('vlans');
  Future<List<Map<String, Object?>>> getLcpNaps() => getRawTable('lcpnap');
  Future<List<Map<String, Object?>>> getLcpNapPorts() =>
      getRawTable('lcpnap_ports');
  Future<List<Map<String, Object?>>> getInventoryCategories() =>
      getRawTable('inventory_categories');
  Future<List<Map<String, Object?>>> getInventoryLogs() =>
      _db.getAll('SELECT * FROM inventory_logs ORDER BY created_date DESC');
}
