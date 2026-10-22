/// Feature-surface differential vs SQLite: VALUES as a table source, aggregate
/// FILTER clause, UPSERT variations, and LIMIT/OFFSET inside subqueries — common
/// modern-SQL features a client reaches for.
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('misc features vs sqlite', () {
    late DiffOracle o;
    setUp(() async {
      o = await DiffOracle.open();
      await o.exec('CREATE TABLE t (id INTEGER PRIMARY KEY, g TEXT, v INTEGER)');
      await o.exec("INSERT INTO t VALUES "
          "(1,'a',10),(2,'a',20),(3,'b',30),(4,'b',40),(5,'c',50),(6,'a',NULL)");
    });
    tearDown(() => o.close());

    final queries = <String>[
      // VALUES as a table source
      'SELECT column1, column2 FROM (VALUES (1, 10), (2, 20), (3, 30)) '
          'ORDER BY column1',
      'SELECT SUM(column2) FROM (VALUES (1, 10), (2, 20), (3, 30))',
      // aggregate FILTER clause
      'SELECT g, COUNT(*) FILTER (WHERE v > 15) FROM t GROUP BY g ORDER BY g',
      'SELECT SUM(v) FILTER (WHERE v IS NOT NULL) FROM t',
      'SELECT COUNT(*) FILTER (WHERE v IS NULL) FROM t',
      // LIMIT/OFFSET in subquery
      'SELECT v FROM (SELECT v FROM t ORDER BY v LIMIT 3 OFFSET 1) ORDER BY v',
      // IN with VALUES-like list
      'SELECT id FROM t WHERE g IN (SELECT column1 FROM '
          "(VALUES ('a'), ('c'))) ORDER BY id",
      // WITH + VALUES
      "WITH nums(x) AS (VALUES (1), (2), (3)) SELECT SUM(x) FROM nums",
      // aggregate FILTER with GROUP BY and multiple aggregates
      'SELECT g, COUNT(*) a, COUNT(*) FILTER (WHERE v >= 30) b FROM t '
          'GROUP BY g ORDER BY g',
    ];

    for (final q in queries) {
      test(q.substring(0, q.length.clamp(0, 55)), () => o.expectSameRows(q));
    }

    test('UPSERT ON CONFLICT DO NOTHING', () async {
      await o.exec('CREATE TABLE u (id INTEGER PRIMARY KEY, v INTEGER)');
      await o.exec('INSERT INTO u VALUES (1, 10)');
      await o.exec('INSERT INTO u VALUES (1, 99) ON CONFLICT(id) DO NOTHING');
      await o.exec('INSERT INTO u VALUES (2, 20) ON CONFLICT(id) DO NOTHING');
      await o.expectSameRows('SELECT id, v FROM u ORDER BY id');
    });

    test('UPSERT DO UPDATE with WHERE', () async {
      await o.exec('CREATE TABLE u (id INTEGER PRIMARY KEY, v INTEGER)');
      await o.exec('INSERT INTO u VALUES (1, 10)');
      await o.exec('INSERT INTO u VALUES (1, 5) ON CONFLICT(id) '
          'DO UPDATE SET v = excluded.v WHERE excluded.v > u.v');
      await o.exec('INSERT INTO u VALUES (1, 99) ON CONFLICT(id) '
          'DO UPDATE SET v = excluded.v WHERE excluded.v > u.v');
      await o.expectSameRows('SELECT id, v FROM u ORDER BY id');
    });
  }, skip: sqliteSkipReason());
}
