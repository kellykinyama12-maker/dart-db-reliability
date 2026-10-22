/// Engine-bug regression guards.
///
/// Two groups:
///  - **fixed regressions** — bugs F3–F18 that the engine author fixed
///    (verified 2026-10-22). These are now ACTIVE tests: if any regresses, the
///    suite goes red.
///  - **open bugs** — F19, F20, still failing; marked `skip:` with a
///    `KNOWN ENGINE BUG` reason. Un-skip when fixed.
///
/// (F1/F2 live in `constraints/`, F15 in `durability/` — same policy there.)
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('fixed regressions (active guards)', () {
    test('F3 · date month-underflow decrements the year', () async {
      final db = await openEngine();
      await expectScalar(db, "SELECT date('2021-01-01', '-1 month')",
          '2020-12-01');
    });

    test('F4 · correlated subquery binds outer ref correctly on name clash',
        () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE s (id INTEGER PRIMARY KEY, g TEXT)');
      await db.execute("INSERT INTO s VALUES (1,'a'),(2,'a'),(3,'b')");
      await expectRows(
        db,
        'SELECT id, (SELECT COUNT(*) FROM s x WHERE x.g = s.g) FROM s ORDER BY id',
        [
          [1, 2],
          [2, 2],
          [3, 1],
        ],
      );
    });

    test('F5 · GROUP BY can reference a SELECT-list alias', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE ev (id INTEGER PRIMARY KEY, ts TEXT)');
      await db.execute("INSERT INTO ev VALUES (1,'2021-01-01'),(2,'2021-02-01')");
      await expectOk(
          db, "SELECT strftime('%Y', ts) y, COUNT(*) FROM ev GROUP BY y");
    });

    test('F6 · implicit text+number coercion does not leak a cast error',
        () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, s TEXT)');
      await db.execute("INSERT INTO t VALUES (1,'abc')");
      await expectScalar(db, 'SELECT s + 0 FROM t', 0);
    });

    test('F7 · NULL does not short-circuit AND/OR (3-valued logic)', () async {
      final db = await openEngine();
      await expectScalar(db, 'SELECT (NULL OR 1=1)', 1);
      await expectScalar(db, 'SELECT (NULL AND 1=0)', 0);
    });

    test('F8 · SUBSTR with negative length', () async {
      final db = await openEngine();
      await expectScalar(db, "SELECT SUBSTR('Hello', 2, -1)", 'H');
    });

    test('F9 · division by zero yields NULL', () async {
      final db = await openEngine();
      await expectScalar(db, 'SELECT 5 / 0', null);
    });

    test('F10 · UNIQUE enforced on UPDATE', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, e TEXT UNIQUE)');
      await db.execute("INSERT INTO t VALUES (1,'a'),(2,'b')");
      await expectThrows(db, "UPDATE t SET e = 'a' WHERE id = 2");
    });

    test('F11 · lexer handles backslash in single-quoted string', () async {
      final db = await openEngine();
      await expectScalar(db, r"SELECT '\'", r'\');
    });

    test('F12 · boolean subexpression in arithmetic does not throw', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE n (id INTEGER PRIMARY KEY, a INTEGER)');
      await db.execute('INSERT INTO n VALUES (1, 5), (2, -5)');
      await expectRows(db, 'SELECT id, (a > 0) - (a < 0) FROM n ORDER BY id', [
        [1, 1],
        [2, -1],
      ]);
    });

    test('F13 · ORDER BY aggregate DESC sorts a NULL group key correctly',
        () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, g TEXT)');
      await db.execute("INSERT INTO t VALUES "
          "(1,'a'),(2,'a'),(3,'a'),(4,NULL),(5,NULL),(6,'b'),(7,'b'),(8,'c')");
      await expectRows(
          db, 'SELECT g FROM t GROUP BY g ORDER BY COUNT(*) DESC, g', [
        ['a'],
        [null],
        ['b'],
        ['c'],
      ]);
    });

    test('F14 · multi-row INSERT is statement-atomic', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY)');
      await db.execute('INSERT INTO t VALUES (1)');
      await expectThrows(db, 'INSERT INTO t VALUES (2), (3), (1), (4)');
      await expectRows(db, 'SELECT id FROM t ORDER BY id', [
        [1],
      ]);
    });

    test('F16 · selecting from a view over a join resolves columns', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE a (id INTEGER PRIMARY KEY, x INTEGER)');
      await db.execute('CREATE TABLE b (id INTEGER PRIMARY KEY, y INTEGER)');
      await db.execute('INSERT INTO a VALUES (1, 10)');
      await db.execute('INSERT INTO b VALUES (1, 20)');
      await db.execute('CREATE VIEW v AS '
          'SELECT a.id, a.x, b.y FROM a JOIN b ON a.id = b.id');
      await expectRows(db, 'SELECT id, x, y FROM v', [
        [1, 10, 20],
      ]);
    });

    test('F17 · view using SELECT alias.* expands correctly', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE a (id INTEGER PRIMARY KEY, x INTEGER)');
      await db.execute('CREATE TABLE b (id INTEGER PRIMARY KEY, y INTEGER)');
      await db.execute('INSERT INTO a VALUES (1, 10)');
      await db.execute('INSERT INTO b VALUES (1, 20)');
      await db.execute('CREATE VIEW v AS '
          'SELECT a.*, b.y FROM a JOIN b ON a.id = b.id');
      await expectRows(db, 'SELECT id, x, y FROM v', [
        [1, 10, 20],
      ]);
    });

    test('F18 · HAVING without GROUP BY', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE s (id INTEGER PRIMARY KEY, v INTEGER)');
      await db.execute('INSERT INTO s VALUES (1,10),(2,20)');
      await expectScalar(db, 'SELECT SUM(v) FROM s HAVING SUM(v) > 5', 30);
    });
  });

  group('open bugs (documented repros)', () {
    test('F19 · greater-than mishandles negative zero (0 > -0.0 is TRUE)',
        () async {
      final db = await openEngine();
      await expectScalar(db, 'SELECT (0 > -0.0)', 0);
      await expectScalar(db, 'SELECT (0 > (-14.939 * 0))', 0);
    },
        skip: 'KNOWN ENGINE BUG: `>` treats negative zero as less than zero, so '
            '`0 > -0.0` returns TRUE. See findings/FINDINGS.md F19.');

    test('F20 · NOT IN (subquery/list containing NULL) ignores the NULL',
        () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE a (id INTEGER PRIMARY KEY, g INTEGER)');
      await db.execute('CREATE TABLE b (id INTEGER PRIMARY KEY, g INTEGER)');
      await db.execute('INSERT INTO a VALUES (1,3)');
      await db.execute('INSERT INTO b VALUES (1,1),(2,2),(3,NULL)');
      await expectRows(db, 'SELECT id FROM a WHERE g NOT IN (SELECT g FROM b)', []);
    },
        skip: 'KNOWN ENGINE BUG: NOT IN with a NULL in the list/subquery ignores '
            'the NULL and returns rows that 3-valued logic must exclude. '
            'See findings/FINDINGS.md F20.');

    test('F21 · named table-level FK/UNIQUE/PK constraints fail to parse',
        () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE p (id INTEGER PRIMARY KEY)');
      // `CONSTRAINT <name> CHECK` works, but FK/UNIQUE/PK do not.
      await expectOk(
          db,
          'CREATE TABLE t (id INT, pid INT, '
          'CONSTRAINT fk FOREIGN KEY (pid) REFERENCES p(id))');
    },
        skip: 'KNOWN ENGINE BUG: `CONSTRAINT <name> FOREIGN KEY|UNIQUE|PRIMARY '
            'KEY` table constraints fail to parse (only named CHECK works). '
            'Blocks 10/16 sakila tables and Oracle HR. See findings/FINDINGS.md F21.');

    test('F22 · FK enforced despite PRAGMA foreign_keys=OFF; no forward refs',
        () async {
      final db = await openEngine();
      await db.execute('PRAGMA foreign_keys = OFF');
      await db.execute('CREATE TABLE c (id INTEGER PRIMARY KEY, pid INT, '
          'FOREIGN KEY (pid) REFERENCES parent (pid))');
      // SQLite (foreign_keys OFF, forward refs allowed) inserts this fine.
      await expectOk(db, 'INSERT INTO c VALUES (1, 99)');
    },
        skip: 'KNOWN ENGINE BUG: `PRAGMA foreign_keys=OFF` is ignored and a FK '
            'to a not-yet-created table throws `Bad state: FK references missing '
            'table`. SQLite defaults OFF and allows forward refs. Blocks loading '
            'real FK schemas (sakila). See findings/FINDINGS.md F22.');
  });
}
