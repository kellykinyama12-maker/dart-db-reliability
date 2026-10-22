/// GROUP_CONCAT / string-aggregation correctness vs SQLite: default and custom
/// separators, DISTINCT, ordering within groups, and NULL handling.
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('group_concat vs sqlite', () {
    late DiffOracle o;
    setUp(() async {
      o = await DiffOracle.open();
      await o.exec('CREATE TABLE t (id INTEGER PRIMARY KEY, g TEXT, v INTEGER, s TEXT)');
      await o.exec("INSERT INTO t VALUES "
          "(1,'a',3,'x'),(2,'a',1,'y'),(3,'a',2,'z'),(4,'b',5,NULL),"
          "(5,'b',5,'w'),(6,'c',9,'q')");
    });
    tearDown(() => o.close());

    final queries = <String>[
      // default separator (comma); order within group via an ordered subquery
      "SELECT g, GROUP_CONCAT(v) FROM (SELECT g, v FROM t ORDER BY g, v) "
          'GROUP BY g ORDER BY g',
      // custom separator
      "SELECT g, GROUP_CONCAT(v, '|') FROM (SELECT g, v FROM t ORDER BY g, v) "
          'GROUP BY g ORDER BY g',
      // DISTINCT values
      'SELECT g, GROUP_CONCAT(DISTINCT v) FROM '
          '(SELECT g, v FROM t ORDER BY g, v) GROUP BY g ORDER BY g',
      // NULLs are skipped by GROUP_CONCAT
      "SELECT g, GROUP_CONCAT(s) FROM (SELECT g, s FROM t ORDER BY g, s) "
          'GROUP BY g ORDER BY g',
      // whole-table concat
      'SELECT GROUP_CONCAT(v) FROM (SELECT v FROM t ORDER BY v)',
      // count-based cross-check (order-independent)
      'SELECT g, COUNT(v), COUNT(DISTINCT v) FROM t GROUP BY g ORDER BY g',
      // length of concatenation (order-independent magnitude)
      "SELECT g, LENGTH(GROUP_CONCAT(v, '')) FROM t GROUP BY g ORDER BY g",
    ];

    for (final q in queries) {
      test(q.substring(0, q.length.clamp(0, 55)), () => o.expectSameRows(q));
    }
  }, skip: sqliteSkipReason());
}
