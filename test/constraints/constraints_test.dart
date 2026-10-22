/// Constraint enforcement: PRIMARY KEY, UNIQUE, NOT NULL, CHECK, and FOREIGN
/// KEY (incl. cascade / restrict). A database that silently accepts violations
/// is not reliable — each test asserts the violating statement throws and the
/// valid one succeeds.
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('constraint enforcement', () {
    test('PRIMARY KEY rejects duplicates', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)');
      await expectOk(db, "INSERT INTO t VALUES (1, 'a')");
      await expectThrows(db, "INSERT INTO t VALUES (1, 'b')");
      await expectRows(db, 'SELECT COUNT(*) FROM t', [
        [1],
      ]);
    });

    test('UNIQUE rejects duplicates, allows multiple NULLs', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, email TEXT UNIQUE)');
      await expectOk(db, "INSERT INTO t VALUES (1, 'a@x')");
      await expectThrows(db, "INSERT INTO t VALUES (2, 'a@x')");
      // SQL standard: NULLs are distinct for UNIQUE.
      await expectOk(db, 'INSERT INTO t VALUES (3, NULL)');
      await expectOk(db, 'INSERT INTO t VALUES (4, NULL)');
    });

    test('NOT NULL rejects nulls', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT NOT NULL)');
      await expectThrows(db, 'INSERT INTO t VALUES (1, NULL)');
      await expectOk(db, "INSERT INTO t VALUES (1, 'ok')");
    });

    test('CHECK constraint enforced on insert', () async {
      final db = await openEngine();
      await db.execute(
          'CREATE TABLE t (id INTEGER PRIMARY KEY, age INTEGER CHECK (age >= 0))');
      await expectOk(db, 'INSERT INTO t VALUES (1, 20)');
      await expectThrows(db, 'INSERT INTO t VALUES (2, -5)');
      await expectRows(db, 'SELECT age FROM t WHERE id = 1', [
        [20],
      ]);
    });

    test('CHECK constraint enforced on UPDATE', () async {
      final db = await openEngine();
      await db.execute(
          'CREATE TABLE t (id INTEGER PRIMARY KEY, age INTEGER CHECK (age >= 0))');
      await db.execute('INSERT INTO t VALUES (1, 20)');
      await expectThrows(db, 'UPDATE t SET age = -1 WHERE id = 1',
          reason: 'CHECK must also guard UPDATE');
      await expectRows(db, 'SELECT age FROM t WHERE id = 1', [
        [20],
      ]);
    });

    test('FOREIGN KEY rejects orphan child', () async {
      final db = await openEngine();
      await db.execute('PRAGMA foreign_keys = ON');
      await db.execute('CREATE TABLE parent (id INTEGER PRIMARY KEY)');
      await db.execute('CREATE TABLE child (id INTEGER PRIMARY KEY, '
          'pid INTEGER REFERENCES parent(id))');
      await db.execute('INSERT INTO parent VALUES (1)');
      await expectOk(db, 'INSERT INTO child VALUES (10, 1)');
      await expectThrows(db, 'INSERT INTO child VALUES (11, 99)',
          reason: 'orphan FK must be rejected');
    });

    test('FOREIGN KEY ON DELETE CASCADE removes children', () async {
      final db = await openEngine();
      await db.execute('PRAGMA foreign_keys = ON');
      await db.execute('CREATE TABLE parent (id INTEGER PRIMARY KEY)');
      await db.execute('CREATE TABLE child (id INTEGER PRIMARY KEY, '
          'pid INTEGER REFERENCES parent(id) ON DELETE CASCADE)');
      await db.execute('INSERT INTO parent VALUES (1), (2)');
      await db.execute('INSERT INTO child VALUES (10, 1), (11, 1), (12, 2)');
      await db.execute('DELETE FROM parent WHERE id = 1');
      await expectRows(db, 'SELECT id FROM child ORDER BY id', [
        [12],
      ]);
    });

    test('composite PRIMARY KEY uniqueness', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (a INTEGER, b INTEGER, PRIMARY KEY (a, b))');
      await expectOk(db, 'INSERT INTO t VALUES (1, 1)');
      await expectOk(db, 'INSERT INTO t VALUES (1, 2)');
      await expectThrows(db, 'INSERT INTO t VALUES (1, 1)');
    });
  });
}
