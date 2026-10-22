/// Data-movement correctness vs SQLite: INSERT…SELECT, CREATE TABLE AS SELECT,
/// INSERT with column lists/defaults, and SELECT from derived tables
/// (subquery-in-FROM), including nested and joined derived tables.
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('data movement + derived tables vs sqlite', () {
    late DiffOracle o;
    setUp(() async {
      o = await DiffOracle.open();
      await o.exec('CREATE TABLE src (id INTEGER PRIMARY KEY, g TEXT, v INTEGER)');
      await o.exec("INSERT INTO src VALUES "
          "(1,'a',10),(2,'a',20),(3,'b',30),(4,'b',40),(5,'c',50)");
    });
    tearDown(() => o.close());

    test('INSERT ... SELECT copies filtered rows', () async {
      await o.exec('CREATE TABLE dst (id INTEGER PRIMARY KEY, g TEXT, v INTEGER)');
      await o.exec("INSERT INTO dst SELECT id, g, v FROM src WHERE v > 20");
      await o.expectSameRows('SELECT id, g, v FROM dst ORDER BY id');
    });

    test('INSERT ... SELECT with aggregation', () async {
      await o.exec('CREATE TABLE agg (g TEXT PRIMARY KEY, total INTEGER)');
      await o.exec('INSERT INTO agg SELECT g, SUM(v) FROM src GROUP BY g');
      await o.expectSameRows('SELECT g, total FROM agg ORDER BY g');
    });

    test('CREATE TABLE AS SELECT', () async {
      await o.exec('CREATE TABLE cta AS SELECT g, COUNT(*) c, SUM(v) s '
          'FROM src GROUP BY g');
      await o.expectSameRows('SELECT g, c, s FROM cta ORDER BY g');
    });

    test('INSERT with explicit column list and omitted (default) column',
        () async {
      await o.exec('CREATE TABLE d2 (id INTEGER PRIMARY KEY, g TEXT, '
          'note TEXT DEFAULT \'none\')');
      await o.exec("INSERT INTO d2 (id, g) SELECT id, g FROM src WHERE id <= 2");
      await o.expectSameRows('SELECT id, g, note FROM d2 ORDER BY id');
    });

    final derived = <String>[
      // subquery in FROM
      'SELECT g, mx FROM (SELECT g, MAX(v) mx FROM src GROUP BY g) '
          'WHERE mx > 20 ORDER BY g',
      // nested derived tables
      'SELECT * FROM (SELECT * FROM (SELECT id, v FROM src WHERE v > 15) '
          'WHERE v < 45) ORDER BY id',
      // join of two derived tables
      'SELECT a.g, a.s, b.c FROM '
          '(SELECT g, SUM(v) s FROM src GROUP BY g) a '
          'JOIN (SELECT g, COUNT(*) c FROM src GROUP BY g) b ON a.g = b.g '
          'ORDER BY a.g',
      // derived table joined to base table
      'SELECT s.id, t.mx FROM src s '
          'JOIN (SELECT g, MAX(v) mx FROM src GROUP BY g) t ON s.g = t.g '
          'ORDER BY s.id',
      // aggregate over a derived table
      'SELECT AVG(s) FROM (SELECT g, SUM(v) s FROM src GROUP BY g)',
    ];
    for (final q in derived) {
      test(q.substring(0, q.length.clamp(0, 55)), () => o.expectSameRows(q));
    }
  }, skip: sqliteSkipReason());
}
