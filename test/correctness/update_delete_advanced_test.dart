/// Advanced UPDATE / DELETE correctness: subquery in SET, correlated UPDATE,
/// UPDATE with WHERE subquery, UPDATE…FROM (SQLite 3.33+), and DELETE with
/// subquery/correlated predicates. Authored golden expectations.
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:dart_db_server/dart_db_server.dart' show Database;
import 'package:test/test.dart';

void main() {
  group('advanced UPDATE / DELETE', () {
    late Database db;
    setUp(() async {
      db = await openEngine();
      await db.execute('CREATE TABLE emp (id INTEGER PRIMARY KEY, dept INTEGER, '
          'salary INTEGER)');
      await db.execute('CREATE TABLE dept (id INTEGER PRIMARY KEY, bonus INTEGER)');
      await db.execute('INSERT INTO emp VALUES '
          '(1,1,100),(2,1,200),(3,2,150),(4,2,250),(5,3,300)');
      await db.execute('INSERT INTO dept VALUES (1,10),(2,20),(3,30)');
    });

    test('UPDATE with scalar subquery in SET', () async {
      await db.execute('UPDATE emp SET salary = salary + '
          '(SELECT MAX(salary) FROM emp) WHERE id = 1');
      await expectScalar(db, 'SELECT salary FROM emp WHERE id = 1', 400);
    });

    test('correlated UPDATE (per-row subquery)', () async {
      await db.execute('UPDATE emp SET salary = salary + '
          '(SELECT bonus FROM dept WHERE dept.id = emp.dept)');
      await expectRows(db, 'SELECT id, salary FROM emp ORDER BY id', [
        [1, 110],
        [2, 210],
        [3, 170],
        [4, 270],
        [5, 330],
      ]);
    });

    test('UPDATE WHERE col IN (subquery)', () async {
      await db.execute('UPDATE emp SET salary = 0 WHERE dept IN '
          '(SELECT id FROM dept WHERE bonus >= 20)');
      await expectRows(db, 'SELECT id, salary FROM emp ORDER BY id', [
        [1, 100],
        [2, 200],
        [3, 0],
        [4, 0],
        [5, 0],
      ]);
    });

    test('UPDATE WHERE EXISTS (correlated)', () async {
      await db.execute('UPDATE emp SET salary = salary * 2 WHERE EXISTS '
          '(SELECT 1 FROM dept WHERE dept.id = emp.dept AND dept.bonus > 15)');
      await expectRows(db, 'SELECT id, salary FROM emp ORDER BY id', [
        [1, 100],
        [2, 200],
        [3, 300],
        [4, 500],
        [5, 600],
      ]);
    });

    test('UPDATE with CASE expression', () async {
      await db.execute('UPDATE emp SET salary = CASE WHEN salary < 200 THEN '
          'salary + 50 ELSE salary END');
      await expectRows(db, 'SELECT id, salary FROM emp ORDER BY id', [
        [1, 150],
        [2, 200],
        [3, 200],
        [4, 250],
        [5, 300],
      ]);
    });

    test('DELETE WHERE col IN (subquery)', () async {
      await db.execute('DELETE FROM emp WHERE dept IN '
          '(SELECT id FROM dept WHERE bonus = 30)');
      await expectRows(db, 'SELECT id FROM emp ORDER BY id', [
        [1],
        [2],
        [3],
        [4],
      ]);
    });

    test('DELETE WHERE EXISTS (correlated)', () async {
      await db.execute('DELETE FROM emp WHERE EXISTS '
          '(SELECT 1 FROM dept WHERE dept.id = emp.dept AND dept.bonus < 15)');
      await expectRows(db, 'SELECT id FROM emp ORDER BY id', [
        [3],
        [4],
        [5],
      ]);
    });

    test('DELETE with aggregate subquery threshold', () async {
      await db.execute('DELETE FROM emp WHERE salary < '
          '(SELECT AVG(salary) FROM emp)');
      // avg = 200; rows with salary < 200 are id 1(100),3(150) → deleted.
      await expectRows(db, 'SELECT id FROM emp ORDER BY id', [
        [2],
        [4],
        [5],
      ]);
    });
  });
}
