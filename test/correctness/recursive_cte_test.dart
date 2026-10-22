/// Recursive & complex CTE correctness vs SQLite: multi-column recursion,
/// UNION (dedup) vs UNION ALL, cycle termination, fibonacci-style accumulation,
/// tree traversal, and multiple/chained CTEs.
@Timeout(Duration(minutes: 2))
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('recursive CTE vs sqlite', () {
    late DiffOracle o;
    setUp(() async {
      o = await DiffOracle.open();
      await o.exec('CREATE TABLE tree (id INTEGER PRIMARY KEY, parent INTEGER, name TEXT)');
      await o.exec("INSERT INTO tree VALUES "
          "(1,NULL,'root'),(2,1,'a'),(3,1,'b'),(4,2,'a1'),(5,2,'a2'),"
          "(6,3,'b1'),(7,6,'b1x')");
    });
    tearDown(() => o.close());

    test('counting sequence', () => o.expectSameRows('''
WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM seq WHERE n < 20)
SELECT n FROM seq ORDER BY n'''));

    test('sum accumulation', () => o.expectSameRows('''
WITH RECURSIVE s(n, total) AS (
  SELECT 1, 1 UNION ALL SELECT n+1, total+n+1 FROM s WHERE n < 10)
SELECT n, total FROM s ORDER BY n'''));

    test('fibonacci', () => o.expectSameRows('''
WITH RECURSIVE fib(a, b) AS (
  SELECT 0, 1 UNION ALL SELECT b, a+b FROM fib WHERE b < 200)
SELECT a FROM fib ORDER BY a'''));

    test('tree depth (downward traversal)', () => o.expectSameRows('''
WITH RECURSIVE sub(id, name, depth) AS (
  SELECT id, name, 0 FROM tree WHERE parent IS NULL
  UNION ALL
  SELECT t.id, t.name, s.depth+1 FROM tree t JOIN sub s ON t.parent = s.id)
SELECT name, depth FROM sub ORDER BY depth, name'''));

    test('ancestors (upward traversal)', () => o.expectSameRows('''
WITH RECURSIVE anc(id, parent, name) AS (
  SELECT id, parent, name FROM tree WHERE id = 7
  UNION ALL
  SELECT t.id, t.parent, t.name FROM tree t JOIN anc a ON t.id = a.parent)
SELECT name FROM anc ORDER BY id'''));

    test('path string accumulation', () => o.expectSameRows('''
WITH RECURSIVE p(id, path) AS (
  SELECT id, name FROM tree WHERE parent IS NULL
  UNION ALL
  SELECT t.id, p.path || '/' || t.name FROM tree t JOIN p ON t.parent = p.id)
SELECT path FROM p ORDER BY path'''));

    test('UNION dedup in recursion', () => o.expectSameRows('''
WITH RECURSIVE r(n) AS (
  SELECT 1 UNION SELECT (n*2) % 7 FROM r WHERE n < 100)
SELECT n FROM r ORDER BY n'''));

    test('chained non-recursive CTEs', () => o.expectSameRows('''
WITH a AS (SELECT id, name FROM tree WHERE parent IS NOT NULL),
     b AS (SELECT name FROM a WHERE id > 3)
SELECT name FROM b ORDER BY name'''));

    test('recursive with LIMIT', () => o.expectSameRows('''
WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM seq)
SELECT n FROM seq LIMIT 5'''));
  }, skip: sqliteSkipReason());
}
