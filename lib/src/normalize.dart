/// Normalizes scalar values so results from dart_db_server and SQLite (or
/// authored golden values) compare on a common shape.
///
/// - `bool` → 0/1 (SQLite has no boolean type).
/// - integer-valued `double` → `int` (1.0 → 1).
/// - other `double`s → rounded to 12 significant digits to absorb
///   floating-point noise between two independent evaluators.
/// - BLOB-ish `Uint8List`/`List<int>` → unified to `List<int>`.
library;

Object? normalizeValue(Object? v) {
  if (v == null) return null;
  if (v is bool) return v ? 1 : 0;
  if (v is double) {
    if (v.isFinite && v == v.truncateToDouble()) return v.toInt();
    if (!v.isFinite) return v.toString();
    return double.parse(v.toStringAsPrecision(12));
  }
  if (v is List<int>) return List<int>.from(v);
  return v;
}

List<Object?> normalizeRow(Iterable<Object?> row) =>
    row.map(normalizeValue).toList();

List<List<Object?>> normalizeRows(Iterable<Iterable<Object?>> rows) =>
    rows.map(normalizeRow).toList();
