/// Single-engine assertion helpers for suites that check dart_db_server against
/// authored golden expectations (ACID, constraints, durability, isolation) —
/// cases where SQLite is not the right oracle or the behavior is engine-owned.
library;

// ignore_for_file: depend_on_referenced_packages
// (test-harness package; `test` is a dev-dep used by these lib helpers)
import 'package:dart_db_server/dart_db_server.dart';
import 'package:test/test.dart';

import 'normalize.dart';

/// Opens a fresh in-memory engine.
Future<Database> openEngine([String? path]) => Database.open(path);

/// Runs [sql] and returns normalized rows.
Future<List<List<Object?>>> rows(Database db, String sql) async {
  final r = await db.execute(sql);
  return normalizeRows(r.rows);
}

/// Runs [sql] expected to yield a single scalar; returns it normalized.
Future<Object?> scalar(Database db, String sql) async {
  final r = await db.execute(sql);
  if (r.rows.isEmpty) return null;
  return normalizeValue(r.rows.first.first);
}

/// Asserts [sql] throws (constraint violation, syntax error, etc.).
Future<void> expectThrows(Database db, String sql, {String? reason}) async {
  await expectLater(
    () => db.execute(sql),
    throwsA(anything),
    reason: reason ?? 'expected `$sql` to throw',
  );
}

/// Asserts [sql] does NOT throw.
Future<void> expectOk(Database db, String sql, {String? reason}) async {
  try {
    await db.execute(sql);
  } catch (e) {
    fail(reason ?? 'expected `$sql` to succeed but it threw: $e');
  }
}

/// Convenience: assert a scalar query equals [expected] (normalized).
Future<void> expectScalar(Database db, String sql, Object? expected,
    {String? reason}) async {
  expect(await scalar(db, sql), equals(normalizeValue(expected)),
      reason: reason ?? 'scalar mismatch for `$sql`');
}

/// Convenience: assert a query's normalized rows equal [expected].
Future<void> expectRows(
    Database db, String sql, List<List<Object?>> expected,
    {String? reason}) async {
  expect(await rows(db, sql), equals(normalizeRows(expected)),
      reason: reason ?? 'rows mismatch for `$sql`');
}
