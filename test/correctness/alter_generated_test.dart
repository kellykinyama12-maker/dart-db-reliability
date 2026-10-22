/// ALTER TABLE and generated-column correctness (authored golden expectations):
/// ADD COLUMN with default, RENAME TABLE, RENAME COLUMN, DROP COLUMN, and
/// STORED/VIRTUAL generated columns — common schema-evolution operations.
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('ALTER TABLE + generated columns', () {
    test('ADD COLUMN with default backfills existing rows', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, a INTEGER)');
      await db.execute('INSERT INTO t VALUES (1, 10), (2, 20)');
      await db.execute("ALTER TABLE t ADD COLUMN note TEXT DEFAULT 'n/a'");
      await expectRows(db, 'SELECT id, a, note FROM t ORDER BY id', [
        [1, 10, 'n/a'],
        [2, 20, 'n/a'],
      ]);
    });

    test('RENAME TABLE', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v INTEGER)');
      await db.execute('INSERT INTO t VALUES (1, 100)');
      await db.execute('ALTER TABLE t RENAME TO t2');
      await expectRows(db, 'SELECT id, v FROM t2', [
        [1, 100],
      ]);
      await expectThrows(db, 'SELECT * FROM t');
    });

    test('RENAME COLUMN', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, old_name INTEGER)');
      await db.execute('INSERT INTO t VALUES (1, 42)');
      await db.execute('ALTER TABLE t RENAME COLUMN old_name TO new_name');
      await expectRows(db, 'SELECT id, new_name FROM t', [
        [1, 42],
      ]);
    });

    test('DROP COLUMN', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, a INTEGER, b INTEGER)');
      await db.execute('INSERT INTO t VALUES (1, 10, 20)');
      await db.execute('ALTER TABLE t DROP COLUMN b');
      await expectRows(db, 'SELECT * FROM t', [
        [1, 10],
      ]);
      await expectThrows(db, 'SELECT b FROM t');
    });

    test('generated column (STORED)', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, price REAL, '
          'qty INTEGER, total REAL GENERATED ALWAYS AS (price * qty) STORED)');
      await db.execute('INSERT INTO t (id, price, qty) VALUES (1, 2.5, 4)');
      await expectScalar(db, 'SELECT total FROM t WHERE id = 1', 10.0);
    });

    test('generated column (VIRTUAL)', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, a INTEGER, '
          'b INTEGER, sum_ab INTEGER GENERATED ALWAYS AS (a + b) VIRTUAL)');
      await db.execute('INSERT INTO t (id, a, b) VALUES (1, 3, 4)');
      await expectScalar(db, 'SELECT sum_ab FROM t WHERE id = 1', 7);
    });
  });
}
