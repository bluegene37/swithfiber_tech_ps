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

// Gene - Nov, 28, 2026: Parse Asia/Manila local ISO strings (YYYY-MM-DDTHH:mm:ss.SSS, no Z) without shifting by +8h UTC.
final RegExp _naiveLocalIsoRegex = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,6}))?)?)?$',
);

DateTime? parseManilaLocalDate(Object? v) {
  if (v == null) return null;
  if (v is DateTime) {
    return v.isUtc
        ? DateTime(v.year, v.month, v.day, v.hour, v.minute, v.second,
            v.millisecond, v.microsecond)
        : v;
  }
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  final m = _naiveLocalIsoRegex.firstMatch(s);
  if (m != null) {
    final year = int.parse(m.group(1)!);
    final month = int.parse(m.group(2)!);
    final day = int.parse(m.group(3)!);
    final hour = int.tryParse(m.group(4) ?? '0') ?? 0;
    final minute = int.tryParse(m.group(5) ?? '0') ?? 0;
    final second = int.tryParse(m.group(6) ?? '0') ?? 0;
    final frac = m.group(7) ?? '';
    final paddedMicro = frac.padRight(6, '0').substring(0, 6);
    final totalMicro = int.tryParse(paddedMicro) ?? 0;
    return DateTime(
      year,
      month,
      day,
      hour,
      minute,
      second,
      totalMicro ~/ 1000,
      totalMicro % 1000,
    );
  }
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
