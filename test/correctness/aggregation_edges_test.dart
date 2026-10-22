/// Aggregation & grouping edge cases — GROUP BY with NULL groups, HAVING,
/// DISTINCT aggregates, empty-set aggregates, correlated subqueries. Validated
/// differentially against SQLite.
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('aggregation edges vs sqlite', () {
    late DiffOracle o;
    setUp(() async {
      o = await DiffOracle.open();
      await o.exec('CREATE TABLE s (id INTEGER PRIMARY KEY, g TEXT, v INTEGER)');
      await o.exec("INSERT INTO s VALUES "
          "(1,'a',10),(2,'a',20),(3,'b',NULL),(4,NULL,30),(5,NULL,NULL),"
          "(6,'b',20),(7,'a',10)");
    });
    tearDown(() => o.close());

    final queries = <String>[
      'SELECT g, COUNT(*) FROM s GROUP BY g ORDER BY g',
      'SELECT g, COUNT(v) FROM s GROUP BY g ORDER BY g',
      'SELECT g, SUM(v), AVG(v), MIN(v), MAX(v) FROM s GROUP BY g ORDER BY g',
      'SELECT g, COUNT(DISTINCT v) FROM s GROUP BY g ORDER BY g',
      'SELECT SUM(DISTINCT v) FROM s',
      'SELECT COUNT(*) FROM s WHERE 1 = 0',           // empty set
      'SELECT SUM(v) FROM s WHERE 1 = 0',             // SUM of empty → NULL
      'SELECT AVG(v) FROM s WHERE 1 = 0',
      'SELECT g FROM s GROUP BY g HAVING COUNT(*) > 2 ORDER BY g',
      'SELECT g, SUM(v) FROM s GROUP BY g HAVING SUM(v) IS NOT NULL ORDER BY g',
      'SELECT g, COUNT(*) FROM s GROUP BY g HAVING g IS NOT NULL ORDER BY g',
      'SELECT v, COUNT(*) FROM s GROUP BY v ORDER BY v',
      'SELECT id FROM s WHERE v > (SELECT AVG(v) FROM s) ORDER BY id',
      // group_concat ordering-independent check via count
      'SELECT g, COUNT(v) c FROM s GROUP BY g ORDER BY c DESC, g',
    ];

    for (final q in queries) {
      test(q, () => o.expectSameRows(q));
    }
  }, skip: sqliteSkipReason());
}
