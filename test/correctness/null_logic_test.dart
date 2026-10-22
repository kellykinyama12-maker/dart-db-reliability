/// Three-valued logic and NULL semantics — a classic source of engine bugs.
/// Differential against SQLite so the expected answer is authoritative.
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('NULL / three-valued logic vs sqlite', () {
    late DiffOracle o;
    setUp(() async {
      o = await DiffOracle.open();
      await o.exec('CREATE TABLE t (a INTEGER, b INTEGER, s TEXT)');
      await o.exec('INSERT INTO t VALUES '
          '(1, 10, \'x\'), (2, NULL, \'y\'), (NULL, 30, NULL), (4, 4, \'\')');
    });
    tearDown(() => o.close());

    final queries = <String>[
      // NULL comparisons are UNKNOWN → excluded by WHERE.
      'SELECT a FROM t WHERE b = NULL ORDER BY a',
      'SELECT a FROM t WHERE b <> 10 ORDER BY a',
      'SELECT a FROM t WHERE b IS NULL ORDER BY a',
      'SELECT a FROM t WHERE b IS NOT NULL ORDER BY a',
      // NULL in arithmetic propagates.
      'SELECT a, a + b AS s FROM t ORDER BY a',
      // NULL in aggregates is skipped; COUNT(col) vs COUNT(*).
      'SELECT COUNT(a), COUNT(b), COUNT(*) FROM t',
      'SELECT SUM(b), AVG(b), MIN(b), MAX(b) FROM t',
      // IN / NOT IN with NULL.
      'SELECT a FROM t WHERE b IN (10, 30) ORDER BY a',
      'SELECT a FROM t WHERE a NOT IN (2, 4) ORDER BY a',
      // COALESCE / NULLIF / CASE.
      'SELECT COALESCE(a, b, -1) FROM t ORDER BY COALESCE(a, b, -1)',
      'SELECT NULLIF(a, b) FROM t ORDER BY a',
      'SELECT CASE WHEN b IS NULL THEN \'n\' ELSE \'v\' END FROM t ORDER BY a',
      // NULL ordering.
      'SELECT b FROM t ORDER BY b',
      'SELECT b FROM t ORDER BY b DESC',
      // DISTINCT treats NULLs as equal.
      'SELECT DISTINCT b FROM t ORDER BY b',
      // Empty string is not NULL.
      'SELECT a FROM t WHERE s = \'\' ORDER BY a',
      'SELECT a FROM t WHERE s IS NULL ORDER BY a',
    ];

    for (final q in queries) {
      test(q, () => o.expectSameRows(q));
    }
  }, skip: sqliteSkipReason());
}
