/// JSON readers for the Phase 3 inventory and procurement shapes (PLAN 1.7).
///
/// Quantities (3 dp), unit costs (6 dp) and money (2 dp) arrive as strings and
/// are kept as strings. The `...Amount` helpers below give numbers for display
/// and client-side previews only; the server totals are the ones saved.
library;

Map<String, dynamic> jsonMap(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> jsonMaps(Object? v) => [
      for (final e in (v as List?) ?? const []) jsonMap(e),
    ];

List<String> jsonStrings(Object? v) => [
      for (final e in (v as List?) ?? const []) e.toString(),
    ];

String jsonStr(Map<String, dynamic> j, String key, [String fallback = '']) {
  final v = j[key];
  return v == null ? fallback : v.toString();
}

String? jsonStrOrNull(Map<String, dynamic> j, String key) {
  final v = j[key];
  return v == null ? null : v.toString();
}

int jsonInt(Map<String, dynamic> j, String key, [int fallback = 0]) {
  final v = j[key];
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

bool jsonBool(Map<String, dynamic> j, String key, [bool fallback = false]) {
  final v = j[key];
  return v is bool ? v : fallback;
}

/// Decimal text as sent by the server (for example "6410.000"). Missing gives
/// [fallback].
String jsonDecimal(Map<String, dynamic> j, String key, [String fallback = '0']) {
  final v = j[key];
  return v == null ? fallback : v.toString();
}

String? jsonDecimalOrNull(Map<String, dynamic> j, String key) {
  final v = j[key];
  return v == null ? null : v.toString();
}

/// Numeric value of a decimal string or number. Unreadable gives 0.
num decimalValue(Object? v) => v == null ? 0 : (num.tryParse(v.toString()) ?? 0);

num? decimalOrNull(Object? v) => v == null ? null : num.tryParse(v.toString());

DateTime? jsonDate(Map<String, dynamic> j, String key) {
  final v = j[key];
  return v is String ? DateTime.tryParse(v) : null;
}

/// Date for a request body: yyyy-MM-dd.
String wireDay(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
}

/// Decimal text with three places, for quantities sent to the server.
String wireQty(num v) => v.toStringAsFixed(3);

/// A `{ id, name }` reference as the server sends it inside views.
class RefName {
  const RefName({required this.id, required this.name});

  final String id;
  final String name;

  /// Null when the value is absent or has no id.
  static RefName? maybe(Object? v) {
    final m = jsonMap(v);
    if (m['id'] == null) return null;
    return RefName(id: m['id'].toString(), name: jsonStr(m, 'name'));
  }
}
