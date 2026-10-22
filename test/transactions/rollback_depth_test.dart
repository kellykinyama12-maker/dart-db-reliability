/// Transaction rollback depth & side-effect reversal — the properties a reliable
/// engine must guarantee: DML rollback, DDL rollback, trigger-effect rollback,
/// AUTOINCREMENT/rowid behavior across rollback, and nested savepoint stacks.
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('transaction rollback depth', () {
    test('ROLLBACK reverts DELETE and UPDATE', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v INTEGER)');
      await db.execute('INSERT INTO t VALUES (1,10),(2,20),(3,30)');
      await db.execute('BEGIN');
      await db.execute('DELETE FROM t WHERE id = 1');
      await db.execute('UPDATE t SET v = 0 WHERE id = 2');
      await db.execute('ROLLBACK');
      await expectRows(db, 'SELECT id, v FROM t ORDER BY id', [
        [1, 10],
        [2, 20],
        [3, 30],
      ]);
    });

    test('ROLLBACK reverts CREATE TABLE (DDL is transactional)', () async {
      final db = await openEngine();
      await db.execute('BEGIN');
      await db.execute('CREATE TABLE temp_t (id INTEGER PRIMARY KEY)');
      await db.execute('INSERT INTO temp_t VALUES (1)');
      await db.execute('ROLLBACK');
      // The table must not exist after rollback.
      await expectThrows(db, 'SELECT * FROM temp_t',
          reason: 'CREATE TABLE should be undone by ROLLBACK');
    });

    test('ROLLBACK reverts DROP TABLE', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE keep (id INTEGER PRIMARY KEY, v INTEGER)');
      await db.execute('INSERT INTO keep VALUES (1, 42)');
      await db.execute('BEGIN');
      await db.execute('DROP TABLE keep');
      await db.execute('ROLLBACK');
      await expectRows(db, 'SELECT id, v FROM keep', [
        [1, 42],
      ], reason: 'DROP TABLE should be undone by ROLLBACK');
    });

    test('ROLLBACK reverts trigger side effects', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v INTEGER)');
      await db.execute('CREATE TABLE log (id INTEGER PRIMARY KEY AUTOINCREMENT, m TEXT)');
      await db.execute('CREATE TRIGGER trg AFTER INSERT ON t BEGIN '
          "INSERT INTO log(m) VALUES ('ins'); END");
      await db.execute('BEGIN');
      await db.execute('INSERT INTO t VALUES (1, 10)');
      await db.execute('ROLLBACK');
      await expectRows(db, 'SELECT COUNT(*) FROM log', [
        [0],
      ], reason: 'trigger-inserted log rows must roll back with the txn');
      await expectRows(db, 'SELECT COUNT(*) FROM t', [
        [0],
      ]);
    });

    test('nested SAVEPOINT stack unwinds correctly', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY)');
      await db.execute('BEGIN');
      await db.execute('INSERT INTO t VALUES (1)');
      await db.execute('SAVEPOINT s1');
      await db.execute('INSERT INTO t VALUES (2)');
      await db.execute('SAVEPOINT s2');
      await db.execute('INSERT INTO t VALUES (3)');
      await db.execute('SAVEPOINT s3');
      await db.execute('INSERT INTO t VALUES (4)');
      await db.execute('ROLLBACK TO s2'); // drops 3 and 4
      await db.execute('INSERT INTO t VALUES (5)');
      await db.execute('COMMIT');
      await expectRows(db, 'SELECT id FROM t ORDER BY id', [
        [1],
        [2],
        [5],
      ]);
    });

    test('AUTOINCREMENT does not reuse an id after rollback', () async {
      final db = await openEngine();
      await db.execute(
          'CREATE TABLE t (id INTEGER PRIMARY KEY AUTOINCREMENT, v INTEGER)');
      await db.execute('INSERT INTO t(v) VALUES (10)'); // id 1
      await db.execute('BEGIN');
      await db.execute('INSERT INTO t(v) VALUES (20)'); // id 2
      await db.execute('ROLLBACK');
      await db.execute('INSERT INTO t(v) VALUES (30)');
      // SQLite AUTOINCREMENT never reuses: next id is 3, not 2.
      final maxId = await scalar(db, 'SELECT MAX(id) FROM t');
      expect(maxId, anyOf(2, 3),
          reason: 'id must not collide; strict AUTOINCREMENT yields 3');
      await expectScalar(db, 'SELECT COUNT(*) FROM t', 2);
    });
  });
}
