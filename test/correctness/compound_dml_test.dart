/// Compound-SELECT (UNION/INTERSECT/EXCEPT) and DML-with-subquery correctness,
/// validated differentially against SQLite: set-op dedup with NULLs, type
/// coercion across arms, ORDER BY over a compound, and UPDATE/DELETE whose
/// predicate references a subquery.
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('compound select + DML-subquery vs sqlite', () {
    late DiffOracle o;
    setUp(() async {
      o = await DiffOracle.open();
      await o.exec('CREATE TABLE a (id INTEGER PRIMARY KEY, v INTEGER)');
      await o.exec('CREATE TABLE b (id INTEGER PRIMARY KEY, v INTEGER)');
      await o.exec('INSERT INTO a VALUES (1,10),(2,20),(3,NULL),(4,20)');
      await o.exec('INSERT INTO b VALUES (1,20),(2,30),(3,NULL)');
    });
    tearDown(() => o.close());

    group('compound', () {
      final qs = [
        'SELECT v FROM a UNION SELECT v FROM b ORDER BY v',        // dedup + NULL
        'SELECT v FROM a UNION ALL SELECT v FROM b ORDER BY v',
        'SELECT v FROM a INTERSECT SELECT v FROM b ORDER BY v',
        'SELECT v FROM a EXCEPT SELECT v FROM b ORDER BY v',
        'SELECT v FROM a UNION SELECT v FROM b ORDER BY v DESC LIMIT 2',
        // three-way compound
        'SELECT v FROM a UNION SELECT v FROM b UNION SELECT 99 ORDER BY v',
      ];
      for (final q in qs) {
        test(q, () => o.expectSameRows(q));
      }
    });

    group('DML with subquery', () {
      test('UPDATE ... WHERE col IN (subquery)', () async {
        await o.exec('UPDATE a SET v = 0 WHERE v IN (SELECT v FROM b)');
        await o.expectSameRows('SELECT id, v FROM a ORDER BY id');
      });

      test('DELETE ... WHERE EXISTS (correlated)', () async {
        await o.exec(
            'DELETE FROM a WHERE EXISTS (SELECT 1 FROM b WHERE b.v = a.v)');
        await o.expectSameRows('SELECT id, v FROM a ORDER BY id');
      });

      test('UPDATE with scalar subquery value', () async {
        await o.exec('UPDATE a SET v = (SELECT MAX(v) FROM b) WHERE id = 1');
        await o.expectSameRows('SELECT id, v FROM a ORDER BY id');
      });

      test('DELETE ... WHERE col NOT IN (subquery without NULL)', () async {
        await o.exec(
            'DELETE FROM a WHERE v NOT IN (SELECT v FROM b WHERE v IS NOT NULL)');
        await o.expectSameRows('SELECT id, v FROM a ORDER BY id');
      });
    });
  }, skip: sqliteSkipReason());
}
