/// Differential correctness harness: drives dart_db_server and a reference
/// SQLite engine in lockstep and asserts they agree. SQLite is the *oracle* —
/// when the two diverge the test fails and reports both outputs.
///
/// If the native `sqlite3` shared library is unavailable, [sqliteSkipReason]
/// returns a non-null reason so suites skip instead of failing.
library;

// ignore_for_file: depend_on_referenced_packages
// (test-harness package; `test` and `sqlite3` are dev-deps used by lib helpers)
import 'package:dart_db_server/dart_db_server.dart' as ddb;
import 'package:sqlite3/sqlite3.dart' as sq;
import 'package:test/test.dart';

import 'normalize.dart';

class _SqliteAvailability {
  static bool? _available;
  static String? _reason;

  static bool check() {
    if (_available != null) return _available!;
    try {
      sq.sqlite3.openInMemory().dispose();
      _available = true;
    } catch (e) {
      _available = false;
      _reason = 'sqlite3 native library not available: $e';
    }
    return _available!;
  }

  static String? get reason => _available == true ? null : _reason;
}

/// Non-null skip reason when SQLite is not available on this host.
String? sqliteSkipReason() {
  if (_SqliteAvailability.check()) return null;
  return _SqliteAvailability.reason ?? 'sqlite3 native library not available';
}

/// A paired (ours, reference) database driven in lockstep.
class DiffOracle {
  DiffOracle._(this.ours, this.ref);

  final ddb.Database ours;
  final sq.Database ref;

  static Future<DiffOracle> open() async {
    if (!_SqliteAvailability.check()) {
      throw StateError(_SqliteAvailability.reason!);
    }
    final ours = await ddb.Database.open();
    final ref = sq.sqlite3.openInMemory();
    return DiffOracle._(ours, ref);
  }

  void close() => ref.dispose();

  /// Runs a non-query (DDL/DML) on both. Asserts both-or-neither throw; a
  /// one-sided throw is a divergence.
  Future<void> exec(String sql) async {
    Object? oursErr;
    Object? refErr;
    try {
      await ours.execute(sql);
    } catch (e) {
      oursErr = e;
    }
    try {
      ref.execute(sql);
    } catch (e) {
      refErr = e;
    }
    if ((oursErr == null) != (refErr == null)) {
      fail('Divergence on `$sql`:\n  ours: $oursErr\n  ref:  $refErr');
    }
  }

  /// Runs [sql] on both, then runs the [verify] query on both and asserts the
  /// normalized rows match positionally. Always ORDER the verify query.
  Future<void> expectSameRows(String sql, {String? reason}) async {
    final ourRes = await ours.execute(sql);
    final refRes = ref.select(sql);
    final a = normalizeRows(ourRes.rows);
    final b = normalizeRows(refRes.rows);
    expect(a, equals(b), reason: reason ?? 'Row mismatch for: `$sql`');
  }

  /// Like [expectSameRows] but also asserts column names match (case-folded).
  Future<void> expectSameResult(String sql, {String? reason}) async {
    final ourRes = await ours.execute(sql);
    final refRes = ref.select(sql);
    final oc = ourRes.columns.map((c) => c.toLowerCase()).toList();
    final rc = refRes.columnNames.map((c) => c.toLowerCase()).toList();
    expect(oc, equals(rc), reason: reason ?? 'Column mismatch for: `$sql`');
    final a = normalizeRows(ourRes.rows);
    final b = normalizeRows(refRes.rows);
    expect(a, equals(b), reason: reason ?? 'Row mismatch for: `$sql`');
  }

  /// Non-failing differential check for fuzzing/triage. Runs [sql] on both,
  /// compares results as a **sorted multiset** (so ORDER BY need not be total),
  /// and returns a human-readable divergence description, or null if they
  /// agree. A one-sided throw is also a divergence (unless both throw).
  Future<String?> diff(String sql) async {
    Object? ourErr;
    Object? refErr;
    List<List<Object?>>? a;
    List<List<Object?>>? b;
    try {
      a = normalizeRows((await ours.execute(sql)).rows);
    } catch (e) {
      ourErr = e;
    }
    try {
      b = normalizeRows(ref.select(sql).rows);
    } catch (e) {
      refErr = e;
    }
    if (ourErr != null || refErr != null) {
      if (ourErr != null && refErr != null) return null; // both reject: fine
      return 'one-sided error | ours=${_short(ourErr)} ref=${_short(refErr)}';
    }
    final sa = _sortBag(a!);
    final sb = _sortBag(b!);
    if (sa.toString() == sb.toString()) return null;
    return 'rows differ | ours=${_short(sa)} ref=${_short(sb)}';
  }

  static String _short(Object? v) {
    final s = '$v';
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }

  static List<List<Object?>> _sortBag(List<List<Object?>> rows) {
    final copy = rows.map((r) => r.toList()).toList();
    copy.sort((x, y) {
      final n = x.length < y.length ? x.length : y.length;
      for (var i = 0; i < n; i++) {
        final c = _cmp(x[i], y[i]);
        if (c != 0) return c;
      }
      return x.length - y.length;
    });
    return copy;
  }

  static int _cmp(Object? a, Object? b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    if (a is num && b is num) return a.compareTo(b);
    return '$a'.compareTo('$b');
  }
}
