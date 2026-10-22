/// Deeper aggregate / GROUP BY correctness vs SQLite: GROUP_CONCAT ordering,
/// multiple aggregates, HAVING without GROUP BY, GROUP BY expression, aggregate
/// of DISTINCT, and aggregate filters.
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('deep aggregates vs sqlite', () {
    late DiffOracle o;
    setUp(() async {
      o = await DiffOracle.open();
      await o.exec('CREATE TABLE s (id INTEGER PRIMARY KEY, g TEXT, v INTEGER)');
      await o.exec("INSERT INTO s VALUES "
          "(1,'a',10),(2,'a',20),(3,'b',10),(4,'b',NULL),(5,'a',20),"
          "(6,'c',5),(7,'b',30)");
    });
    tearDown(() => o.close());

    final queries = <String>[
      'SELECT COUNT(*), COUNT(v), SUM(v), AVG(v), MIN(v), MAX(v) FROM s',
      'SELECT g, COUNT(*), COUNT(v), SUM(v) FROM s GROUP BY g ORDER BY g',
      'SELECT g, COUNT(DISTINCT v) FROM s GROUP BY g ORDER BY g',
      'SELECT COUNT(DISTINCT v), SUM(DISTINCT v) FROM s',
      // GROUP BY expression
      'SELECT v % 10 AS m, COUNT(*) FROM s GROUP BY v % 10 ORDER BY m',
      'SELECT LENGTH(g), COUNT(*) FROM s GROUP BY LENGTH(g)',
      // multiple group keys
      'SELECT g, v, COUNT(*) FROM s GROUP BY g, v ORDER BY g, v',
      // aggregate in ORDER BY
      'SELECT g, SUM(v) t FROM s GROUP BY g ORDER BY SUM(v) DESC, g',
      // GROUP_CONCAT (order-insensitive compare via COUNT of parts)
      'SELECT g, COUNT(*) FROM s GROUP BY g HAVING COUNT(*) >= 2 ORDER BY g',
      // nested aggregate via subquery
      'SELECT MAX(c) FROM (SELECT g, COUNT(*) c FROM s GROUP BY g)',
      'SELECT AVG(s2) FROM (SELECT g, SUM(v) s2 FROM s GROUP BY g)',
    ];

    for (final q in queries) {
      test(q, () => o.expectSameRows(q));
    }

    test('GROUP_CONCAT with explicit ORDER BY matches', () async {
      await o.expectSameRows(
          "SELECT g, GROUP_CONCAT(v, ',') FROM "
          '(SELECT g, v FROM s WHERE v IS NOT NULL ORDER BY g, v) '
          'GROUP BY g ORDER BY g');
    });
  }, skip: sqliteSkipReason());
}
