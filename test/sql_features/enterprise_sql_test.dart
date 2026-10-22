/// Enterprise SQL surface — joins, subqueries, CTEs (incl. recursive), set
/// operations, window functions, and grouping extensions — validated
/// differentially against SQLite.
@Timeout(Duration(minutes: 2))
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('enterprise SQL vs sqlite', () {
    late DiffOracle o;
    setUp(() async {
      o = await DiffOracle.open();
      await o.exec('CREATE TABLE emp (id INTEGER PRIMARY KEY, dept INTEGER, '
          'mgr INTEGER, name TEXT, salary INTEGER)');
      await o.exec('CREATE TABLE dept (id INTEGER PRIMARY KEY, name TEXT)');
      await o.exec("INSERT INTO dept VALUES (1,'Eng'),(2,'Sales'),(3,'Ops')");
      await o.exec('INSERT INTO emp VALUES '
          "(1,1,NULL,'Ada',200),(2,1,1,'Alan',150),(3,1,1,'Grace',150),"
          "(4,2,1,'Ken',120),(5,2,4,'Dennis',110),(6,3,1,'Edsger',130)");
    });
    tearDown(() => o.close());

    group('joins', () {
      final qs = [
        'SELECT e.name, d.name FROM emp e JOIN dept d ON e.dept = d.id '
            'ORDER BY e.id',
        'SELECT e.name, d.name FROM emp e LEFT JOIN dept d ON e.dept = d.id '
            'ORDER BY e.id',
        'SELECT d.name, COUNT(e.id) FROM dept d LEFT JOIN emp e ON e.dept = d.id '
            'GROUP BY d.name ORDER BY d.name',
        'SELECT a.name, b.name FROM emp a JOIN emp b ON a.mgr = b.id '
            'ORDER BY a.id',
      ];
      for (final q in qs) {
        test(q, () => o.expectSameRows(q));
      }
    });

    group('subqueries', () {
      final qs = [
        'SELECT name FROM emp WHERE salary > (SELECT AVG(salary) FROM emp) '
            'ORDER BY id',
        'SELECT name FROM emp WHERE dept IN (SELECT id FROM dept WHERE name=\'Eng\') '
            'ORDER BY id',
        'SELECT name, (SELECT name FROM dept WHERE dept.id = emp.dept) dn '
            'FROM emp ORDER BY id',
        'SELECT d.name FROM dept d WHERE EXISTS '
            '(SELECT 1 FROM emp e WHERE e.dept = d.id AND e.salary > 140) '
            'ORDER BY d.name',
        'SELECT name FROM emp e WHERE salary = '
            '(SELECT MAX(salary) FROM emp x WHERE x.dept = e.dept) ORDER BY id',
      ];
      for (final q in qs) {
        test(q, () => o.expectSameRows(q));
      }
    });

    group('CTE and recursion', () {
      test('simple CTE', () => o.expectSameRows(
          'WITH hi AS (SELECT * FROM emp WHERE salary >= 150) '
          'SELECT name FROM hi ORDER BY id'));
      test('recursive CTE (org chart depth)', () => o.expectSameRows('''
WITH RECURSIVE chain(id, name, lvl) AS (
  SELECT id, name, 0 FROM emp WHERE mgr IS NULL
  UNION ALL
  SELECT e.id, e.name, c.lvl + 1 FROM emp e JOIN chain c ON e.mgr = c.id
)
SELECT name, lvl FROM chain ORDER BY lvl, name'''));
      test('recursive numbers', () => o.expectSameRows('''
WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x < 10)
SELECT x FROM n ORDER BY x'''));
    });

    group('set operations', () {
      final qs = [
        'SELECT dept FROM emp UNION SELECT id FROM dept ORDER BY 1',
        'SELECT dept FROM emp UNION ALL SELECT id FROM dept ORDER BY 1',
        'SELECT dept FROM emp INTERSECT SELECT id FROM dept ORDER BY 1',
        'SELECT id FROM dept EXCEPT SELECT dept FROM emp ORDER BY 1',
      ];
      for (final q in qs) {
        test(q, () => o.expectSameRows(q));
      }
    });

    group('window functions', () {
      final qs = [
        'SELECT name, ROW_NUMBER() OVER (ORDER BY salary DESC, id) rn '
            'FROM emp ORDER BY rn',
        'SELECT name, RANK() OVER (ORDER BY salary DESC) r FROM emp ORDER BY id',
        'SELECT name, DENSE_RANK() OVER (ORDER BY salary DESC) r FROM emp '
            'ORDER BY id',
        'SELECT name, dept, SUM(salary) OVER (PARTITION BY dept) s FROM emp '
            'ORDER BY id',
        'SELECT name, LAG(salary) OVER (ORDER BY id) l FROM emp ORDER BY id',
        'SELECT name, LEAD(salary) OVER (ORDER BY id) l FROM emp ORDER BY id',
        'SELECT name, AVG(salary) OVER (PARTITION BY dept) a FROM emp '
            'ORDER BY id',
      ];
      for (final q in qs) {
        test(q, () => o.expectSameRows(q));
      }
    });
  }, skip: sqliteSkipReason());
}
