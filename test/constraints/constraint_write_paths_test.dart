/// Constraint enforcement on mutation paths beyond plain INSERT — UPDATE,
/// INSERT OR IGNORE / OR REPLACE, UPSERT, and multi-row inserts. A reliable
/// engine must enforce UNIQUE / NOT NULL / PK / CHECK on every write path.
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('constraint enforcement on all write paths', () {
    test('UNIQUE enforced on UPDATE', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, e TEXT UNIQUE)');
      await db.execute("INSERT INTO t VALUES (1,'a'),(2,'b')");
      await expectThrows(db, "UPDATE t SET e = 'a' WHERE id = 2",
          reason: 'UPDATE must not create a duplicate UNIQUE value');
      await expectRows(db, 'SELECT e FROM t ORDER BY id', [
        ['a'],
        ['b'],
      ]);
    });

    test('NOT NULL enforced on UPDATE', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT NOT NULL)');
      await db.execute("INSERT INTO t VALUES (1,'x')");
      await expectThrows(db, 'UPDATE t SET v = NULL WHERE id = 1');
      await expectRows(db, 'SELECT v FROM t', [
        ['x'],
      ]);
    });

    test('PRIMARY KEY enforced on UPDATE', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v INTEGER)');
      await db.execute('INSERT INTO t VALUES (1,10),(2,20)');
      await expectThrows(db, 'UPDATE t SET id = 1 WHERE id = 2',
          reason: 'UPDATE must not create a duplicate PK');
    });

    test('multi-row INSERT is atomic on constraint violation', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY)');
      await db.execute('INSERT INTO t VALUES (1)');
      // The batch contains a dup (1). The whole statement must fail and insert
      // nothing new (statement atomicity).
      await expectThrows(db, 'INSERT INTO t VALUES (2), (3), (1), (4)');
      await expectRows(db, 'SELECT id FROM t ORDER BY id', [
        [1],
      ], reason: 'failed multi-row insert must not leave partial rows');
    });

    test('INSERT OR IGNORE skips the conflicting row only', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v INTEGER)');
      await db.execute('INSERT INTO t VALUES (1,10)');
      await expectOk(db, 'INSERT OR IGNORE INTO t VALUES (1,99),(2,20)');
      await expectRows(db, 'SELECT id, v FROM t ORDER BY id', [
        [1, 10], // original kept
        [2, 20],
      ]);
    });

    test('INSERT OR REPLACE overwrites the conflicting row', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v INTEGER)');
      await db.execute('INSERT INTO t VALUES (1,10)');
      await expectOk(db, 'INSERT OR REPLACE INTO t VALUES (1,99)');
      await expectRows(db, 'SELECT id, v FROM t ORDER BY id', [
        [1, 99],
      ]);
    });

    test('UPSERT (ON CONFLICT DO UPDATE) updates in place', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v INTEGER)');
      await db.execute('INSERT INTO t VALUES (1,10)');
      await expectOk(
          db,
          'INSERT INTO t VALUES (1,5) '
          'ON CONFLICT(id) DO UPDATE SET v = v + excluded.v');
      await expectRows(db, 'SELECT id, v FROM t', [
        [1, 15],
      ]);
    });

    test('CHECK enforced on multi-row INSERT', () async {
      final db = await openEngine();
      await db.execute(
          'CREATE TABLE t (id INTEGER PRIMARY KEY, n INTEGER CHECK (n > 0))');
      await expectThrows(db, 'INSERT INTO t VALUES (1,5),(2,-1),(3,9)');
      await expectRows(db, 'SELECT COUNT(*) FROM t', [
        [0],
      ]);
    });
  });
}
