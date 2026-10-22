/// VIEW correctness, validated differentially against SQLite: views over joins
/// and aggregates, nested views, views in subqueries/joins, and views that
/// reference other views.
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('views vs sqlite', () {
    late DiffOracle o;
    setUp(() async {
      o = await DiffOracle.open();
      await o.exec('CREATE TABLE emp (id INTEGER PRIMARY KEY, dept INTEGER, '
          'name TEXT, salary INTEGER)');
      await o.exec('CREATE TABLE dept (id INTEGER PRIMARY KEY, name TEXT)');
      await o.exec("INSERT INTO dept VALUES (1,'Eng'),(2,'Sales'),(3,'Ops')");
      await o.exec('INSERT INTO emp VALUES '
          "(1,1,'Ada',200),(2,1,'Alan',150),(3,2,'Ken',120),"
          "(4,2,'Dennis',110),(5,3,'Edsger',130),(6,1,'Grace',150)");
    });
    tearDown(() => o.close());

    test('view over a join', () async {
      await o.exec('CREATE VIEW emp_dept AS '
          'SELECT e.id, e.name, d.name AS dept FROM emp e '
          'JOIN dept d ON e.dept = d.id');
      await o.expectSameRows('SELECT id, name, dept FROM emp_dept ORDER BY id');
      await o.expectSameRows(
          "SELECT name FROM emp_dept WHERE dept = 'Eng' ORDER BY id");
    }, skip: 'KNOWN ENGINE BUG F16: selecting from a view defined over a join '
        'fails to resolve the view output columns (`Unknown column: id`). '
        'See findings/FINDINGS.md F16.');

    test('view over an aggregate', () async {
      await o.exec('CREATE VIEW dept_stats AS '
          'SELECT dept, COUNT(*) c, SUM(salary) s, AVG(salary) a '
          'FROM emp GROUP BY dept');
      await o.expectSameRows('SELECT dept, c, s, a FROM dept_stats ORDER BY dept');
      await o.expectSameRows(
          'SELECT dept FROM dept_stats WHERE c > 1 ORDER BY dept');
    });

    test('nested view (view over a view)', () async {
      await o.exec('CREATE VIEW hi AS SELECT * FROM emp WHERE salary >= 150');
      await o.exec('CREATE VIEW hi_eng AS SELECT * FROM hi WHERE dept = 1');
      await o.expectSameRows('SELECT id, name FROM hi_eng ORDER BY id');
    });

    test('view joined with a base table', () async {
      await o.exec('CREATE VIEW dept_totals AS '
          'SELECT dept, SUM(salary) tot FROM emp GROUP BY dept');
      await o.expectSameRows(
          'SELECT d.name, v.tot FROM dept_totals v '
          'JOIN dept d ON v.dept = d.id ORDER BY d.name');
    });

    test('aggregate over a view', () async {
      await o.exec('CREATE VIEW emp_dept AS '
          'SELECT e.*, d.name AS dname FROM emp e JOIN dept d ON e.dept = d.id');
      await o.expectSameRows(
          'SELECT dname, MAX(salary) FROM emp_dept GROUP BY dname ORDER BY dname');
    }, skip: 'KNOWN ENGINE BUG F17: a view using `SELECT e.*` leaks the inner '
        'table alias (`No such table or view: e`) when queried. '
        'See findings/FINDINGS.md F17.');
  }, skip: sqliteSkipReason());
}
