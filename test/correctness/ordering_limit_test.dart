/// ORDER BY / LIMIT / OFFSET / DISTINCT correctness, validated differentially
/// against SQLite: NULL ordering, multi-key sort, LIMIT/OFFSET windows,
/// DISTINCT with NULLs, and ORDER BY on expressions/positions.
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('ordering/limit/distinct vs sqlite', () {
    late DiffOracle o;
    setUp(() async {
      o = await DiffOracle.open();
      await o.exec('CREATE TABLE t (id INTEGER PRIMARY KEY, g TEXT, v INTEGER)');
      await o.exec("INSERT INTO t VALUES "
          "(1,'b',3),(2,'a',NULL),(3,'a',3),(4,NULL,1),(5,'b',NULL),"
          "(6,'a',2),(7,'c',3),(8,NULL,2)");
    });
    tearDown(() => o.close());

    final queries = <String>[
      'SELECT v FROM t ORDER BY v',                         // NULLs first (asc)
      'SELECT v FROM t ORDER BY v DESC',                    // NULLs last (desc)
      'SELECT v FROM t ORDER BY v ASC NULLS LAST',
      'SELECT v FROM t ORDER BY v DESC NULLS FIRST',
      'SELECT g, v FROM t ORDER BY g, v',                   // multi-key w/ NULL
      'SELECT g, v FROM t ORDER BY g DESC, v DESC',
      'SELECT id FROM t ORDER BY v, id',
      'SELECT id, v FROM t ORDER BY v LIMIT 3',
      'SELECT id, v FROM t ORDER BY v LIMIT 3 OFFSET 2',
      'SELECT id, v FROM t ORDER BY id LIMIT 100 OFFSET 6', // tail
      'SELECT id FROM t ORDER BY id LIMIT 0',               // empty
      'SELECT DISTINCT g FROM t ORDER BY g',                // NULL distinct
      'SELECT DISTINCT v FROM t ORDER BY v',
      'SELECT DISTINCT g, v FROM t ORDER BY g, v',
      'SELECT COUNT(DISTINCT g) FROM t',
      'SELECT id, v FROM t ORDER BY 2, 1',                   // ordinal positions
      'SELECT v*1 AS vv FROM t ORDER BY vv',
    ];

    for (final q in queries) {
      test(q, () => o.expectSameRows(q));
    }
  }, skip: sqliteSkipReason());
}
