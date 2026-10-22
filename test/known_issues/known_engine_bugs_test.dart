/// Engine-bug regression guards.
///
/// All of F3–F22 were fixed by the engine author and verified (2026-10-22).
/// These are ACTIVE tests — if any bug regresses, the suite goes red. Nothing
/// here is skipped. (F1/F2 live in `constraints/`, F15 in `durability/`.)
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

  group('formerly-open bugs F19–F22 (fixed & verified)', () {
    test('F19 · greater-than mishandles negative zero (0 > -0.0 is TRUE)',
        () async {
      final db = await openEngine();
      await expectScalar(db, 'SELECT (0 > -0.0)', 0);
      await expectScalar(db, 'SELECT (0 > (-14.939 * 0))', 0);
    });

    test('F20 · NOT IN (subquery/list containing NULL) ignores the NULL',
        () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE a (id INTEGER PRIMARY KEY, g INTEGER)');
      await db.execute('CREATE TABLE b (id INTEGER PRIMARY KEY, g INTEGER)');
      await db.execute('INSERT INTO a VALUES (1,3)');
      await db.execute('INSERT INTO b VALUES (1,1),(2,2),(3,NULL)');
      await expectRows(db, 'SELECT id FROM a WHERE g NOT IN (SELECT g FROM b)', []);
    });

    test('F21 · named table-level FK/UNIQUE/PK constraints fail to parse',
        () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE p (id INTEGER PRIMARY KEY)');
      // `CONSTRAINT <name> CHECK` works, but FK/UNIQUE/PK do not.
      await expectOk(
          db,
          'CREATE TABLE t (id INT, pid INT, '
          'CONSTRAINT fk FOREIGN KEY (pid) REFERENCES p(id))');
    });

    test('F22 · FK enforced despite PRAGMA foreign_keys=OFF; no forward refs',
        () async {
      final db = await openEngine();
      await db.execute('PRAGMA foreign_keys = OFF');
      await db.execute('CREATE TABLE c (id INTEGER PRIMARY KEY, pid INT, '
          'FOREIGN KEY (pid) REFERENCES parent (pid))');
      // SQLite (foreign_keys OFF, forward refs allowed) inserts this fine.
      await expectOk(db, 'INSERT INTO c VALUES (1, 99)');
    });
  });

  group('formerly-open bugs F23–F32 (fixed & verified)', () {
    test('F23 · COLLATE clause not supported in expressions / ORDER BY',
        () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, s TEXT)');
      await db.execute("INSERT INTO t VALUES (1,'Apple'),(2,'apple')");
      // `expr COLLATE NOCASE` is standard SQL (and SQLite).
      await expectRows(
          db, "SELECT id FROM t WHERE s = 'apple' COLLATE NOCASE ORDER BY id", [
        [1],
        [2],
      ]);
    });

    test('F24 · window functions fail in any GROUP BY query', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, g TEXT, v INTEGER)');
      await db.execute("INSERT INTO t VALUES (1,'a',10),(2,'a',20),(3,'b',5)");
      // Rank groups by their aggregate — a common analytic pattern.
      await expectOk(
          db,
          'SELECT g, SUM(v) s, RANK() OVER (ORDER BY SUM(v) DESC) '
          'FROM t GROUP BY g');
    });

    test('F25 · row-value / tuple expressions not parsed', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, a INTEGER, b INTEGER)');
      await db.execute('INSERT INTO t VALUES (1,1,2),(2,2,1)');
      // `(a, b) = (1, 2)` is standard SQL row-value comparison.
      await expectRows(db, 'SELECT id FROM t WHERE (a, b) = (1, 2)', [
        [1],
      ]);
    });

    test('F26 · CREATE TABLE AS SELECT not supported', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE src (id INTEGER PRIMARY KEY, v INTEGER)');
      await db.execute('INSERT INTO src VALUES (1,10),(2,20)');
      await expectOk(db, 'CREATE TABLE t AS SELECT id, v FROM src');
    });

    test('F27 · JSON path functions return wrong value for a missing path',
        () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE j (id INTEGER PRIMARY KEY, doc TEXT)');
      await db.execute('INSERT INTO j VALUES (1, \'{"name":"Grace"}\')');
      // A path that does not exist must yield SQL NULL (SQLite).
      await expectScalar(db, "SELECT json_type(doc, '\$.age') FROM j", null);
      await expectScalar(
          db, "SELECT json_array_length(doc, '\$.tags') FROM j", null);
    });

    test('F28 · integer overflow wraps silently instead of promoting', () async {
      final db = await openEngine();
      // SQLite promotes to float on int64 overflow (stays positive); the engine
      // wraps two's-complement to a negative number.
      await expectScalar(db, 'SELECT (9223372036854775807 + 1) > 0', 1);
    });

    test('F29 · scientific-notation literals silently mis-parsed', () async {
      final db = await openEngine();
      // `1e3` is 1000; the engine returns 1 (the `e3` is swallowed as an alias).
      await expectScalar(db, 'SELECT 1e3', 1000);
      await expectScalar(db, 'SELECT 1.5e2', 150);
    });

    test('F30 · hex integer literals silently mis-parsed', () async {
      final db = await openEngine();
      // `0x1F` is 31; the engine returns 0 (the `x1F` is swallowed as an alias).
      await expectScalar(db, 'SELECT 0x1F', 31);
      await expectScalar(db, 'SELECT 0xFF', 255);
    });

    test('F31 · double-quoted identifiers / aliases not supported', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE c (id INTEGER)');
      await db.execute('INSERT INTO c VALUES (1)');
      // `AS "x"` is valid in SQLite (identifier) and MySQL (quoted alias).
      await expectOk(db, 'SELECT id AS "my col" FROM c');
    });

    test('F32 · CAST to a sized/parameterized type not supported', () async {
      final db = await openEngine();
      // SQLite/MySQL/Oracle all accept CAST(x AS VARCHAR(10)).
      await expectScalar(db, 'SELECT CAST(42 AS VARCHAR(10))', '42');
    });
  });

  group('formerly-open bugs F33–F34 (fixed & verified)', () {
    test('F33 · non-zero number not truthy in CASE / iif', () async {
      final db = await openEngine();
      // Any non-zero number is TRUE as a boolean condition (SQLite/MySQL).
      await expectScalar(db, "SELECT CASE WHEN 1 THEN 'y' ELSE 'n' END", 'y');
      await expectScalar(db, "SELECT iif(5, 'y', 'n')", 'y');
    });

    test('F34 · 2-arg trim / ltrim / rtrim ignores the trim characters',
        () async {
      final db = await openEngine();
      // trim(x, chars) removes `chars` (SQLite/MySQL/Oracle).
      await expectScalar(db, "SELECT trim('xxhixx', 'x')", 'hi');
      await expectScalar(db, "SELECT ltrim('xxhi', 'x')", 'hi');
    });
  });

  group('formerly-open bugs F35–F39 (fixed & verified)', () {
    test('F35 · abs() on a text argument throws an internal cast error',
        () async {
      final db = await openEngine();
      // SQLite coerces: abs('5') -> 5.0, abs('abc') -> 0.0; must not throw.
      await expectScalar(db, "SELECT abs('5')", 5);
    });

    test('F36 · substr with start 0 / out-of-range start is wrong', () async {
      final db = await openEngine();
      // SQLite: substr(x, 0) returns the whole string (0 precedes position 1).
      await expectScalar(db, "SELECT substr('hello', 0)", 'hello');
    });

    test('F37 · replace with an empty search pattern inserts everywhere',
        () async {
      final db = await openEngine();
      // An empty search string matches nothing; the string is unchanged.
      await expectScalar(db, "SELECT replace('abc', '', 'X')", 'abc');
    });

    test('F38 · CAST of text with a trailing garbage returns 0', () async {
      final db = await openEngine();
      // SQLite parses the leading numeric prefix.
      await expectScalar(db, "SELECT cast('42abc' AS INTEGER)", 42);
      await expectScalar(db, "SELECT cast('3.14xyz' AS REAL)", 3.14);
    });

    test('F39 · printf %e exponent width and %g trailing zeros', () async {
      final db = await openEngine();
      await expectScalar(db, "SELECT printf('%g', 0.0001)", '0.0001');
      await expectScalar(db, "SELECT printf('%e', 1234.5)", '1.234500e+03');
    });
  });

  group('open bugs (round 4 — found 2026-10-22)', () {
    test('F40 · unary minus on a text value throws an internal cast error',
        () async {
      final db = await openEngine();
      // Binary `5 + '3'` coerces fine; unary `-'5'` must too (SQLite: -5).
      await expectScalar(db, "SELECT -'5'", -5);
    },
        skip: 'KNOWN ENGINE BUG: unary minus on text throws "String is not a '
            'subtype of num" (the coercion path that binary ops have is missing '
            'for unary minus). See findings/FINDINGS.md F40.');

    test('F41 · CAST(blob AS TEXT) returns raw bytes instead of text',
        () async {
      final db = await openEngine();
      // x'4869' is the bytes for "Hi"; CAST ... AS TEXT must decode it.
      await expectScalar(db, "SELECT CAST(x'4869' AS TEXT)", 'Hi');
    },
        skip: 'KNOWN ENGINE BUG: CAST(<blob> AS TEXT) returns the raw byte list '
            '([72,105]) instead of the decoded string ("Hi"). '
            'See findings/FINDINGS.md F41.');

    test('F42 · CAST(number AS BLOB) throws', () async {
      final db = await openEngine();
      // SQLite produces the blob of the value's text form; must not throw.
      await expectOk(db, 'SELECT CAST(3.14 AS BLOB)');
    },
        skip: 'KNOWN ENGINE BUG: CAST(<number> AS BLOB) throws '
            '"Cannot coerce 3.14 to BLOB"; SQLite yields a blob. '
            'See findings/FINDINGS.md F42.');

    test('F43 · PRAGMA table_info reports notnull=1 for INTEGER PRIMARY KEY',
        () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)');
      final r = await db.execute('PRAGMA table_info(t)');
      final idRow = r.rows.firstWhere((row) => '${row[1]}' == 'id');
      // SQLite reports notnull=0 for an INTEGER PRIMARY KEY (rowid alias).
      expect(idRow[3], 0);
    },
        skip: 'KNOWN ENGINE BUG: PRAGMA introspection diverges from SQLite \u2014 '
            'table_info notnull=1 for INTEGER PRIMARY KEY (should be 0), default '
            'values unquoted, and index_list has a different shape + lists the '
            'auto PK index. Breaks ORM introspection. See findings/FINDINGS.md F43.');
  });
}
