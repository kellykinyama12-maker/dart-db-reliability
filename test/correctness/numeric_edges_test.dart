/// Numeric edge-case correctness, validated differentially against SQLite:
/// division by zero, negative modulo, rounding mode, large integers, and
/// REAL/INTEGER boundary behavior.
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('numeric edges vs sqlite', () {
    late DiffOracle o;
    setUp(() async {
      o = await DiffOracle.open();
      await o.exec('CREATE TABLE n (id INTEGER PRIMARY KEY, a INTEGER, b INTEGER, r REAL)');
      await o.exec("INSERT INTO n VALUES "
          "(1, 7, 2, 2.5),(2, -7, 2, -2.5),(3, 7, -2, 0.5),"
          "(4, 5, 0, 1.5),(5, 0, 3, -0.5)");
    });
    tearDown(() => o.close());

    final queries = <String>[
      'SELECT id, a % b FROM n WHERE b <> 0 ORDER BY id',  // negative modulo
      'SELECT id, -a % b FROM n WHERE b <> 0 ORDER BY id',
      'SELECT id, ROUND(r) FROM n ORDER BY id',            // half rounding
      'SELECT id, ROUND(r, 0) FROM n ORDER BY id',
      'SELECT id, ABS(a), ABS(r) FROM n ORDER BY id',
      'SELECT id, CAST(r AS INTEGER) FROM n ORDER BY id',  // truncation
      'SELECT id, a * a * a FROM n ORDER BY id',
      'SELECT MAX(a), MIN(a), SUM(a), AVG(a) FROM n',
      'SELECT id, a + r FROM n ORDER BY id',               // int+real
      'SELECT 9223372036854775807 + 0',                    // int64 max
      'SELECT id, r * 1.0 FROM n ORDER BY id',
    ];

    for (final q in queries) {
      test(q, () => o.expectSameRows(q));
    }
  }, skip: sqliteSkipReason());
}
