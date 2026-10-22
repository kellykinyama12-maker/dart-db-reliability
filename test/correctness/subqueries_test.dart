/// Subquery-heavy correctness: IN (SELECT), NOT IN with NULL, EXISTS / NOT
/// EXISTS, scalar subqueries in projection and WHERE, and correlated forms.
/// Validated differentially against SQLite.
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('subqueries vs sqlite', () {
    late DiffOracle o;
    setUp(() async {
      o = await DiffOracle.open();
      await o.exec('CREATE TABLE a (id INTEGER PRIMARY KEY, g INTEGER, v INTEGER)');
      await o.exec('CREATE TABLE b (id INTEGER PRIMARY KEY, g INTEGER)');
      await o.exec("INSERT INTO a VALUES "
          "(1,1,10),(2,1,20),(3,2,NULL),(4,2,30),(5,3,5),(6,NULL,7)");
      await o.exec('INSERT INTO b VALUES (1,1),(2,2),(3,NULL)');
    });
    tearDown(() => o.close());

    final queries = <String>[
      'SELECT id FROM a WHERE g IN (SELECT g FROM b) ORDER BY id',
      'SELECT id FROM a WHERE g NOT IN (SELECT g FROM b WHERE g IS NOT NULL) '
          'ORDER BY id',
      'SELECT id FROM a WHERE EXISTS (SELECT 1 FROM b WHERE b.g = a.g) ORDER BY id',
      'SELECT id FROM a WHERE NOT EXISTS (SELECT 1 FROM b WHERE b.g = a.g) '
          'ORDER BY id',
      'SELECT id, (SELECT COUNT(*) FROM b WHERE b.g = a.g) c FROM a ORDER BY id',
      'SELECT id FROM a WHERE v > (SELECT AVG(v) FROM a) ORDER BY id',
      'SELECT id FROM a WHERE v = (SELECT MAX(v) FROM a a2 WHERE a2.g = a.g) '
          'ORDER BY id',
      'SELECT g, (SELECT COUNT(*) FROM a a2 WHERE a2.g = a.g) FROM a '
          'GROUP BY g ORDER BY g',
      'SELECT id FROM a WHERE g = (SELECT MIN(g) FROM b) ORDER BY id',
      // scalar subquery returning NULL
      'SELECT id FROM a WHERE v = (SELECT v FROM a WHERE id = 99) ORDER BY id',
    ];

    for (final q in queries) {
      test(q, () => o.expectSameRows(q));
    }
  }, skip: sqliteSkipReason());
}
