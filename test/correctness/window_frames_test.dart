/// Window-function frame correctness vs SQLite: explicit ROWS/RANGE frames,
/// multiple partitions/orderings, running totals, moving averages, and frame
/// boundaries (UNBOUNDED/CURRENT ROW/n PRECEDING-FOLLOWING).
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('window frames vs sqlite', () {
    late DiffOracle o;
    setUp(() async {
      o = await DiffOracle.open();
      await o.exec('CREATE TABLE t (id INTEGER PRIMARY KEY, g TEXT, v INTEGER)');
      await o.exec("INSERT INTO t VALUES "
          "(1,'a',10),(2,'a',20),(3,'a',30),(4,'b',5),(5,'b',15),"
          "(6,'b',25),(7,'c',100),(8,'a',NULL)");
    });
    tearDown(() => o.close());

    final queries = <String>[
      // running total (default frame)
      'SELECT id, SUM(v) OVER (ORDER BY id) FROM t ORDER BY id',
      // explicit ROWS frame
      'SELECT id, SUM(v) OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING '
          'AND CURRENT ROW) FROM t ORDER BY id',
      // moving window of 3
      'SELECT id, AVG(v) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND '
          '1 FOLLOWING) FROM t ORDER BY id',
      'SELECT id, SUM(v) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND '
          'CURRENT ROW) FROM t ORDER BY id',
      // partitioned running total
      'SELECT id, g, SUM(v) OVER (PARTITION BY g ORDER BY id) FROM t ORDER BY id',
      // partitioned frame
      'SELECT id, g, MAX(v) OVER (PARTITION BY g ORDER BY id ROWS BETWEEN '
          'UNBOUNDED PRECEDING AND CURRENT ROW) FROM t ORDER BY id',
      // ranking functions
      'SELECT id, g, ROW_NUMBER() OVER (PARTITION BY g ORDER BY v) FROM t '
          'ORDER BY id',
      'SELECT id, v, RANK() OVER (ORDER BY v) FROM t ORDER BY id',
      'SELECT id, v, DENSE_RANK() OVER (ORDER BY v) FROM t ORDER BY id',
      'SELECT id, v, PERCENT_RANK() OVER (ORDER BY v) FROM t ORDER BY id',
      'SELECT id, v, CUME_DIST() OVER (ORDER BY v) FROM t ORDER BY id',
      'SELECT id, g, NTILE(2) OVER (PARTITION BY g ORDER BY id) FROM t ORDER BY id',
      // lag/lead with default & offset
      'SELECT id, LAG(v, 1, -1) OVER (ORDER BY id) FROM t ORDER BY id',
      'SELECT id, LEAD(v, 2) OVER (ORDER BY id) FROM t ORDER BY id',
      // first/last/nth value
      'SELECT id, FIRST_VALUE(v) OVER (PARTITION BY g ORDER BY id) FROM t '
          'ORDER BY id',
      'SELECT id, NTH_VALUE(v, 2) OVER (PARTITION BY g ORDER BY id) FROM t '
          'ORDER BY id',
      // multiple windows in one query
      'SELECT id, SUM(v) OVER (ORDER BY id), COUNT(*) OVER () FROM t ORDER BY id',
    ];

    for (final q in queries) {
      test(q.substring(0, q.length.clamp(0, 70)), () => o.expectSameRows(q));
    }
  }, skip: sqliteSkipReason());
}
