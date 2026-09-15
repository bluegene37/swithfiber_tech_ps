/// Conversions between Dart values and what SQLite hands back through
/// PowerSync's `Row` maps.
///
/// PowerSync stores every `id` as TEXT, dates as ISO-8601 text and booleans
/// as 0/1, so these keep that mapping in one place.
library;

/// The API's integer id in the form PowerSync stores it.
String idText(int id) => id.toString();

int rowInt(Object? v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? fallback;
}

int? rowIntOrNull(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

double? rowDouble(Object? v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

String? rowText(Object? v) => v?.toString();

bool rowBool(Object? v, {bool fallback = false}) {
  if (v == null) return fallback;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v.toString().toLowerCase();
  return s == '1' || s == 'true';
}

DateTime? rowDate(Object? v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

String? dateText(DateTime? d) => d?.toIso8601String();

int boolInt(bool b) => b ? 1 : 0;

/// `?, ?, ?` for [count] bound parameters.
String placeholders(int count) => List.filled(count, '?').join(', ');

/// Column list and matching placeholders for an `INSERT OR REPLACE`.
///
/// PowerSync's views cannot take `ON CONFLICT ... DO UPDATE`, but they do
/// honour `INSERT OR REPLACE`, which is what every upsert here uses.
String insertOrReplaceSql(String table, List<String> columns) =>
    'INSERT OR REPLACE INTO $table (${columns.join(', ')}) '
    'VALUES (${placeholders(columns.length)})';
