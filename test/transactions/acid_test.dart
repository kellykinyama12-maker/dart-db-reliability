/// ACID transaction semantics: atomicity (rollback undoes all), commit
/// durability within a session, nested SAVEPOINT / ROLLBACK TO / RELEASE, and
/// error-driven rollback. Authored expectations (standard SQL semantics).
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('ACID transactions', () {
    late final open = openEngine;

    test('rollback undoes all changes (atomicity)', () async {
      final db = await open();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v INTEGER)');
      await db.execute('INSERT INTO t VALUES (1, 100)');
      await db.execute('BEGIN');
      await db.execute('INSERT INTO t VALUES (2, 200)');
      await db.execute('UPDATE t SET v = 999 WHERE id = 1');
      await db.execute('DELETE FROM t WHERE id = 1');
      await db.execute('ROLLBACK');
      await expectRows(db, 'SELECT id, v FROM t ORDER BY id', [
        [1, 100],
      ]);
    });

    test('commit persists changes within the session', () async {
      final db = await open();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v INTEGER)');
      await db.execute('BEGIN');
      await db.execute('INSERT INTO t VALUES (1, 10), (2, 20)');
      await db.execute('COMMIT');
      await expectRows(db, 'SELECT id, v FROM t ORDER BY id', [
        [1, 10],
        [2, 20],
      ]);
    });

    test('savepoint: ROLLBACK TO keeps earlier work, drops later', () async {
      final db = await open();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY)');
      await db.execute('BEGIN');
      await db.execute('INSERT INTO t VALUES (1)');
      await db.execute('SAVEPOINT s1');
      await db.execute('INSERT INTO t VALUES (2)');
      await db.execute('ROLLBACK TO s1');
      await db.execute('INSERT INTO t VALUES (3)');
      await db.execute('COMMIT');
      await expectRows(db, 'SELECT id FROM t ORDER BY id', [
        [1],
        [3],
      ]);
    });

    test('nested savepoints release correctly', () async {
      final db = await open();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY)');
      await db.execute('BEGIN');
      await db.execute('INSERT INTO t VALUES (1)');
      await db.execute('SAVEPOINT a');
      await db.execute('INSERT INTO t VALUES (2)');
      await db.execute('SAVEPOINT b');
      await db.execute('INSERT INTO t VALUES (3)');
      await db.execute('RELEASE b');
      await db.execute('ROLLBACK TO a');
      await db.execute('COMMIT');
      await expectRows(db, 'SELECT id FROM t ORDER BY id', [
        [1],
      ]);
    });

    test('constraint error inside txn then rollback leaves table clean',
        () async {
      final db = await open();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v INTEGER)');
      await db.execute('INSERT INTO t VALUES (1, 1)');
      await db.execute('BEGIN');
      await db.execute('INSERT INTO t VALUES (2, 2)');
      await expectThrows(db, 'INSERT INTO t VALUES (1, 9)',
          reason: 'duplicate PK must fail');
      await db.execute('ROLLBACK');
      await expectRows(db, 'SELECT id, v FROM t ORDER BY id', [
        [1, 1],
      ]);
    });
  });
}
