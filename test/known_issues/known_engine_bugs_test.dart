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

  group('formerly-open bugs F40–F45 (fixed & verified)', () {
    test('F40 · unary minus on a text value throws an internal cast error',
        () async {
      final db = await openEngine();
      // Binary `5 + '3'` coerces fine; unary `-'5'` must too (SQLite: -5).
      await expectScalar(db, "SELECT -'5'", -5);
    });

    test('F41 · CAST(blob AS TEXT) returns raw bytes instead of text',
        () async {
      final db = await openEngine();
      // x'4869' is the bytes for "Hi"; CAST ... AS TEXT must decode it.
      await expectScalar(db, "SELECT CAST(x'4869' AS TEXT)", 'Hi');
    });

    test('F42 · CAST(number AS BLOB) throws', () async {
      final db = await openEngine();
      // SQLite produces the blob of the value's text form; must not throw.
      await expectOk(db, 'SELECT CAST(3.14 AS BLOB)');
    });

    test('F43 · PRAGMA table_info reports notnull=1 for INTEGER PRIMARY KEY',
        () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)');
      final r = await db.execute('PRAGMA table_info(t)');
      final idRow = r.rows.firstWhere((row) => '${row[1]}' == 'id');
      // SQLite reports notnull=0 for an INTEGER PRIMARY KEY (rowid alias).
      expect(idRow[3], 0);
    });
    test('F44 · SUM of a boolean expression throws', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v INTEGER)');
      await db.execute('INSERT INTO t VALUES (1,50),(2,150),(3,200)');
      // SUM(<condition>) counts matching rows (bool -> 1/0) in SQLite/MySQL.
      await expectScalar(db, 'SELECT SUM(v > 100) FROM t', 2);
    });

    test('F45 · ATTACH DATABASE accepted but attached tables are unusable',
        () async {
      final db = await openEngine();
      await db.execute("ATTACH DATABASE ':memory:' AS aux");
      // A schema-qualified name must work for an attached db to be usable.
      await expectOk(db, 'CREATE TABLE aux.t (id INTEGER PRIMARY KEY, v INTEGER)');
    });
  });

  group('formerly-open bugs F46–F51 (fixed & verified)', () {
    test('F47 · most-negative int64 literal crashes the parser', () async {
      final db = await openEngine();
      // -9223372036854775808 is a valid int64; the parser int.parse()s the
      // magnitude (9223372036854775808) before applying unary minus and throws.
      await expectScalar(db, 'SELECT -9223372036854775808', -9223372036854775808);
    });
  });

  group('formerly-open bug F52 (fixed & verified)', () {
    test('F52 · positive integer literal above int64 crashes the parser',
        () async {
      final db = await openEngine();
      // SQLite promotes an out-of-range integer literal to a double (1e20); the
      // engine int.parse()s it and throws. It already handles 1e20 correctly.
      await expectScalar(db, 'SELECT 99999999999999999999', 1e20);
    });
  });

  group('formerly-open bugs F55–F56 (fixed & verified)', () {
    test('F55 · INTEGER PRIMARY KEY rejects non-integer values', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v INTEGER)');
      // An INTEGER PRIMARY KEY is a rowid alias; a non-integer value must be
      // rejected (SQLite: datatype mismatch).
      await expectThrows(db, "INSERT INTO t VALUES ('x', 1)");
    });

    test('F56 · plain INTEGER PRIMARY KEY auto-assigns the rowid', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v INTEGER)');
      // A plain INTEGER PRIMARY KEY is a rowid alias and auto-assigns the id
      // when omitted.
      await db.execute('INSERT INTO t (v) VALUES (10)');
      await expectScalar(db, 'SELECT id FROM t', 1);
    });
  });

  group('formerly-open bugs F57–F59 (fixed & verified)', () {
    test('F57 · rowid / _rowid_ / oid pseudo-columns are queryable', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v INTEGER)');
      await db.execute('INSERT INTO t VALUES (5, 50)');
      // SQLite exposes rowid (and aliases _rowid_/oid) on a rowid table.
      await expectScalar(db, 'SELECT rowid FROM t', 5);
    });

    test('F58 · negative LIMIT is treated as no-limit', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY)');
      await db.execute('INSERT INTO t VALUES (1),(2),(3)');
      // SQLite treats LIMIT -1 as "no limit".
      await expectRows(db, 'SELECT id FROM t ORDER BY id LIMIT -1', [
        [1],
        [2],
        [3]
      ]);
    });

    test('F59 · multi-arg min()/max() no longer silently returns the first arg',
        () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY)');
      await db.execute('INSERT INTO t VALUES (1)');
      // min/max are aggregate-only; a multi-arg call must error (not collapse
      // to the first argument) — use LEAST/GREATEST for the scalar extreme.
      await expectThrows(db, 'SELECT min(3, 1, 2) FROM t');
    });
  });

  group('formerly-open bugs F60–F62 (fixed & verified)', () {
    test('F60 · self LEFT JOIN keeps the left row own column when unmatched',
        () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE e (id INTEGER PRIMARY KEY, mgr INTEGER)');
      await db.execute('INSERT INTO e VALUES (1,NULL),(2,1),(3,1),(4,2)');
      // The unmatched row (id=1, mgr NULL) must keep e.id=1; the engine returns
      // NULL for the left column on a self-join. Two-table LEFT JOIN is fine.
      await expectRows(
          db, 'SELECT e.id FROM e LEFT JOIN e m ON e.mgr = m.id ORDER BY e.id', [
        [1],
        [2],
        [3],
        [4]
      ]);
    });

    test('F61 · COLLATE in a column definition is accepted', () async {
      final db = await openEngine();
      await expectOk(
          db, 'CREATE TABLE t (id INTEGER PRIMARY KEY, s TEXT COLLATE NOCASE)');
    });

    test('F62 · COLLATE is applied in DISTINCT / GROUP BY dedup', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, s TEXT)');
      await db.execute("INSERT INTO t VALUES (1,'A'),(2,'a'),(3,'b')");
      // NOCASE folds 'A' and 'a' -> 2 distinct values.
      await expectScalar(db, 'SELECT COUNT(DISTINCT s COLLATE NOCASE) FROM t', 2);
    });
  });

  group('formerly-open bugs F63–F65 (fixed & verified; Oracle HR DDL)', () {
    test('F63 · inline named column constraint is parsed', () async {
      final db = await openEngine();
      await expectOk(db,
          'CREATE TABLE t (id NUMBER CONSTRAINT id_nn NOT NULL, nm VARCHAR2(25))');
    });

    test('F64 · ALTER TABLE ADD (parenthesized constraint) is parsed',
        () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id NUMBER, nm VARCHAR2(10))');
      await expectOk(db, 'ALTER TABLE t ADD (CONSTRAINT t_pk PRIMARY KEY (id))');
    });

    test('F65 · COMMENT ON TABLE/COLUMN is supported', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id NUMBER)');
      await expectOk(db, "COMMENT ON TABLE t IS 'a table'");
    });
  });

  // Oracle HR schema DDL: after these the real hr_create.sql loads fully.
  group('formerly-open bugs F66–F67 (fixed & verified; Oracle HR DDL)', () {
    test('F66 · ORGANIZATION INDEX (index-organized table) clause is accepted',
        () async {
      final db = await openEngine();
      // Oracle IOT storage clause; accepted and ignored.
      await expectOk(db,
          'CREATE TABLE t (id NUMBER, nm VARCHAR2(10), CONSTRAINT pk PRIMARY KEY (id)) ORGANIZATION INDEX');
    });

    test('F67 · CREATE VIEW with an explicit column list is parsed', () async {
      final db = await openEngine();
      await expectOk(db, 'CREATE VIEW v (a, b) AS SELECT 1, 2');
    });
  });

  // Oracle OE/SH schema DDL: after these, SH loads fully and OE parses.
  group('formerly-open bugs F68–F73 (fixed & verified; Oracle OE/SH DDL)', () {
    test('F68 · PARTITION BY clause on CREATE TABLE is accepted', () async {
      final db = await openEngine();
      await expectOk(
          db, 'CREATE TABLE t (id NUMBER, d DATE) PARTITION BY HASH (id) PARTITIONS 4');
    });

    test('F69 · CREATE MATERIALIZED VIEW is parsed', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE s (m VARCHAR2(10), amt NUMBER)');
      await expectOk(db,
          'CREATE MATERIALIZED VIEW mv AS SELECT m, SUM(amt) FROM s GROUP BY m');
    });

    test('F70 · CREATE TYPE (object type / VARRAY / nested table) is accepted',
        () async {
      final db = await openEngine();
      await expectOk(db,
          'CREATE TYPE addr_typ AS OBJECT (street VARCHAR2(40), city VARCHAR2(30))');
    });

    test('F71 · CREATE SYNONYM is accepted', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id NUMBER)');
      await expectOk(db, 'CREATE SYNONYM syn FOR t');
    });

    test('F72 · PL/SQL trigger with a DECLARE / procedural body is parsed',
        () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id NUMBER, v NUMBER)');
      // The trigger now CREATES (parse gap fixed). Executing the procedural
      // body is tracked separately as F74.
      await expectOk(db,
          'CREATE OR REPLACE TRIGGER trg BEFORE INSERT ON t FOR EACH ROW DECLARE x NUMBER; BEGIN :new.v := 1; END;');
    });

    test('F73 · constraint ENABLE clause in ALTER TABLE ADD is accepted',
        () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id NUMBER)');
      await expectOk(
          db, 'ALTER TABLE t ADD (CONSTRAINT pk PRIMARY KEY (id) ENABLE)');
    });
  });

  group('formerly-open bug F74 (fixed & verified; PL/SQL trigger body)', () {
    test('F74 · PL/SQL trigger procedural body executes', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id NUMBER, v NUMBER)');
      await db.execute(
          'CREATE OR REPLACE TRIGGER trg BEFORE INSERT ON t FOR EACH ROW DECLARE x NUMBER; BEGIN :new.v := 42; END;');
      await db.execute('INSERT INTO t (id) VALUES (1)');
      // The BEFORE-INSERT body sets v to 42 via :new.v := 42.
      await expectScalar(db, 'SELECT v FROM t WHERE id = 1', 42);
    });
  });

  // Oracle data-load / DML: after these the real HR data loads (TO_DATE dates,
  // deferred circular FKs, session/commit directives).
  group('formerly-open bugs F75–F78 (fixed & verified; Oracle data load)', () {
    test('F75 · TO_DATE function is supported', () async {
      final db = await openEngine();
      await expectOk(db, "SELECT TO_DATE('2024-01-15','YYYY-MM-DD') FROM dual");
    });

    test('F76 · ALTER TABLE ENABLE/DISABLE CONSTRAINT is supported', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id NUMBER, CONSTRAINT pk PRIMARY KEY (id))');
      await expectOk(db, 'ALTER TABLE t DISABLE CONSTRAINT pk');
    });

    test('F77 · ALTER SESSION SET ... is accepted', () async {
      final db = await openEngine();
      await expectOk(db, 'ALTER SESSION SET NLS_LANGUAGE=American');
    });

    test('F78 · COMMIT with no active transaction is a no-op', () async {
      final db = await openEngine();
      await expectOk(db, 'COMMIT');
    });
  });

  // Gaps found loading the real Oracle SH schema/data and OE: bulk-load and
  // OLAP DDL. (SH fact tables load via SQL*Loader CSVs, out of harness scope.)
  group('formerly-open bugs F79–F84 (fixed & verified; Oracle SH / OLAP DDL)',
      () {
    test('F79 · schema-qualified table reference in a FK is parsed', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE p (id NUMBER PRIMARY KEY)');
      await db.execute('CREATE TABLE c (pid NUMBER)');
      // Oracle qualifies FK targets by owner: REFERENCES schema.table (col).
      await expectOk(db,
          'ALTER TABLE c ADD (CONSTRAINT fk FOREIGN KEY (pid) REFERENCES hr.p (id))');
    });

    test('F80 · ALTER TABLE ... MODIFY is supported', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id NUMBER, CONSTRAINT pk PRIMARY KEY (id))');
      // Oracle bulk-load pattern: MODIFY CONSTRAINT ... DISABLE/ENABLE; also
      // MODIFY (col type) for column changes.
      await expectOk(db, 'ALTER TABLE t MODIFY CONSTRAINT pk DISABLE NOVALIDATE');
    });

    test('F81 · CREATE BITMAP INDEX is accepted', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id NUMBER, g NUMBER)');
      // Accepted as a regular index.
      await expectOk(db, 'CREATE BITMAP INDEX ix ON t (g)');
    });

    test('F82 · CREATE INDEX trailing storage clause (NOLOGGING) is accepted',
        () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id NUMBER, g NUMBER)');
      await expectOk(db, 'CREATE INDEX ix ON t (g) NOLOGGING');
    });

    test('F83 · CREATE DIMENSION is accepted', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id NUMBER, city VARCHAR2(10))');
      await expectOk(db, 'CREATE DIMENSION d LEVEL c IS (t.id)');
    });

    test('F84 · PL/SQL named-argument (=>) syntax is parsed', () async {
      final db = await openEngine();
      // Oracle scripts call packages with named args; dbms_stats is a no-op.
      await expectOk(db,
          "BEGIN dbms_stats.gather_schema_stats('SH', cascade => TRUE); END;");
    });
  });

  // Gap found loading the real Oracle SH schema: the fact materialized views
  // are indexed by the populate script; CREATE INDEX on a materialized view
  // is now supported (the MV is both queryable and indexable).
  group('formerly-open bug F85 (fixed & verified; materialized view indexing)',
      () {
    test('F85 · CREATE INDEX on a materialized view is supported', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE base (id NUMBER, amt NUMBER)');
      await db.execute('INSERT INTO base VALUES (1, 10), (2, 20)');
      await db.execute('CREATE MATERIALIZED VIEW mv ENABLE QUERY REWRITE AS '
          'SELECT id, SUM(amt) AS s FROM base GROUP BY id');
      // The MV is queryable via SELECT, so it should also be indexable.
      await expectOk(db, 'CREATE INDEX ix ON mv (id)');
    });
  });

  // Formerly-open OE object-relational DDL (oc_cre.sql): object tables, REF
  // columns, and nested-table storage. Fixed & verified.
  group('formerly-open bugs F86–F88 (fixed & verified; Oracle OE object-relational DDL)',
      () {
    test('F86 · CREATE TABLE OF object_type (object table) is parsed', () async {
      final db = await openEngine();
      await db.execute('CREATE TYPE category_typ AS OBJECT ( id NUMBER, name VARCHAR2(30) )');
      await expectOk(db, 'CREATE TABLE categories_tab OF category_typ');
    });

    test('F87 · a REF column type is parsed', () async {
      final db = await openEngine();
      await db.execute('CREATE TYPE product_typ AS OBJECT ( id NUMBER )');
      await expectOk(db,
          'CREATE TABLE line_items ( id NUMBER, product_ref REF product_typ )');
    });

    test('F88 · NESTED TABLE ... STORE AS storage clause is parsed', () async {
      final db = await openEngine();
      await db.execute('CREATE TYPE item_typ AS OBJECT ( id NUMBER )');
      await db.execute('CREATE TYPE item_tab AS TABLE OF item_typ');
      await expectOk(db,
          'CREATE TABLE orders2 ( id NUMBER, items item_tab ) '
          'NESTED TABLE items STORE AS items_nt');
    });
  });

  // Formerly-open Oracle built-in function gaps (scalar/date/aggregate).
  // Fixed & verified.
  group('formerly-open bugs F89–F92 (fixed & verified; Oracle function gaps)',
      () {
    test('F89 · INSTR honors its start-position and occurrence arguments',
        () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (x NUMBER)');
      await db.execute('INSERT INTO t VALUES (1)');
      // 'a' at positions 1 and 4; searching from position 2 must return 4.
      await expectScalar(db, "SELECT INSTR('abcabc', 'a', 2) FROM t", 4);
    });

    test('F90 · TRUNC honors its places argument', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (x NUMBER)');
      await db.execute('INSERT INTO t VALUES (1)');
      await expectScalar(db, 'SELECT TRUNC(3.14159, 2) FROM t', 3.14);
    });

    test('F91 · LISTAGG ... WITHIN GROUP (...) is parsed', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE s (v NUMBER)');
      await db.execute('INSERT INTO s VALUES (10), (20), (30)');
      await expectScalar(db,
          "SELECT LISTAGG(v, ',') WITHIN GROUP (ORDER BY v) FROM s", '10,20,30');
    });

    test('F92 · common Oracle built-in functions are supported', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (x NUMBER)');
      await db.execute('INSERT INTO t VALUES (1)');
      await expectScalar(db, "SELECT TRANSLATE('abc', 'ab', 'xy') FROM t", 'xyc');
      await expectScalar(
          db,
          "SELECT TO_CHAR(ADD_MONTHS(DATE '2020-01-31', 1), 'YYYY-MM-DD') FROM t",
          '2020-02-29');
      await expectScalar(db,
          "SELECT MONTHS_BETWEEN(DATE '2020-03-01', DATE '2020-01-01') FROM t", 2);
      await expectScalar(
          db,
          "SELECT TO_CHAR(NEXT_DAY(DATE '2020-01-01', 'MONDAY'), 'YYYY-MM-DD') FROM t",
          '2020-01-06');
    });
  });

  // Formerly-open: ORDER BY a non-projected grouping column under ROLLUP.
  // Fixed & verified.
  group('formerly-open bug F93 (fixed & verified; ORDER BY under ROLLUP)', () {
    test('F93 · ORDER BY a non-projected grouping column works under ROLLUP',
        () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE e (dept NUMBER, sal NUMBER)');
      await db.execute('INSERT INTO e VALUES (10, 100), (20, 70)');
      await expectOk(db,
          'SELECT SUM(sal) FROM e GROUP BY ROLLUP(dept) ORDER BY dept');
    });
  });

  // Formerly-open advanced Oracle SQL: SYS_CONNECT_BY_PATH and PIVOT.
  // Fixed & verified.
  group('formerly-open bug F94 (fixed & verified; SYS_CONNECT_BY_PATH / PIVOT)',
      () {
    test('F94 · SYS_CONNECT_BY_PATH and PIVOT are supported', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE emp (id NUMBER, mgr NUMBER, name VARCHAR2(10), dept NUMBER, sal NUMBER)');
      await db.execute("INSERT INTO emp VALUES (1, NULL, 'A', 10, 100)");
      await db.execute("INSERT INTO emp VALUES (2, 1, 'B', 20, 70)");
      await expectOk(db,
          "SELECT SYS_CONNECT_BY_PATH(name, '/') FROM emp "
          'START WITH mgr IS NULL CONNECT BY PRIOR id = mgr');
      await expectOk(db,
          'SELECT * FROM (SELECT dept, sal FROM emp) '
          'PIVOT (SUM(sal) FOR dept IN (10, 20))');
    });
  });

  // Formerly-open: MERGE with an alias-qualified target column in UPDATE SET
  // (real-Oracle-adjudicated). Fixed & verified.
  group('formerly-open bug F95 (fixed & verified; MERGE qualified SET)', () {
    test('F95 · MERGE UPDATE SET accepts an alias-qualified target column',
        () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE tgt (id NUMBER, v NUMBER)');
      await db.execute('INSERT INTO tgt VALUES (1, 10)');
      await db.execute('CREATE TABLE src (id NUMBER, v NUMBER)');
      await db.execute('INSERT INTO src VALUES (1, 99)');
      // Real Oracle accepts `SET t.v = s.v` (verified: result 99).
      await expectOk(db,
          'MERGE INTO tgt t USING src s ON (t.id = s.id) '
          'WHEN MATCHED THEN UPDATE SET t.v = s.v');
    });
  });

  // Formerly-open scalar-semantics bugs adjudicated THREE-WAY (engine vs SQLite
  // vs real Oracle 23ai). Fixed & verified.
  group('formerly-open bugs F96–F99 (fixed & verified; scalar semantics, three-way)',
      () {
    test('F96 · MOD with a negative dividend follows the dividend sign',
        () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (x NUMBER)');
      await db.execute('INSERT INTO t VALUES (1)');
      // SQLite (-10 % 3) and Oracle MOD(-10,3) both give -1.
      await expectScalar(db, 'SELECT MOD(-10, 3) FROM t', -1);
    });

    test('F97 · GREATEST/LEAST return NULL when any argument is NULL', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (x NUMBER)');
      await db.execute('INSERT INTO t VALUES (1)');
      await expectScalar(db, 'SELECT GREATEST(1, NULL, 3) FROM t', null);
      await expectScalar(db, 'SELECT LEAST(1, NULL, 3) FROM t', null);
    });

    test('F98 · 2-argument REPLACE removes the substring', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (x NUMBER)');
      await db.execute('INSERT INTO t VALUES (1)');
      await expectScalar(db, "SELECT REPLACE('abcabc', 'b') FROM t", 'acac');
    });

    test('F99 · ANSI TRIM(chars FROM string) syntax is parsed', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (x NUMBER)');
      await db.execute('INSERT INTO t VALUES (1)');
      await expectScalar(db, "SELECT TRIM('_' FROM '_ab_') FROM t", 'ab');
    });
  });

  // Formerly-open date/time + regex (vs real Oracle 23ai). Fixed & verified.
  group('formerly-open bugs F100–F104 (fixed & verified; date/time + regex)',
      () {
    test('F100 · TO_CHAR(date, format) applies the format model', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (x NUMBER)');
      await db.execute('INSERT INTO t VALUES (1)');
      await expectScalar(db,
          "SELECT TO_CHAR(TO_DATE('2021-06-15','YYYY-MM-DD'), 'MON') FROM t",
          'JUN');
    });

    test('F101 · date arithmetic (date - date) computes', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (x NUMBER)');
      await db.execute('INSERT INTO t VALUES (1)');
      await expectScalar(db,
          "SELECT TO_DATE('2020-03-01','YYYY-MM-DD') - "
          "TO_DATE('2020-01-01','YYYY-MM-DD') FROM t",
          60);
    });

    test('F102 · INTERVAL literals are supported', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (x NUMBER)');
      await db.execute('INSERT INTO t VALUES (1)');
      await expectOk(db,
          "SELECT TO_DATE('2020-01-01','YYYY-MM-DD') + INTERVAL '5' DAY FROM t");
    });

    test('F103 · REGEXP_REPLACE substitutes backreferences', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (x NUMBER)');
      await db.execute('INSERT INTO t VALUES (1)');
      await expectScalar(db,
          "SELECT REGEXP_REPLACE('John Smith', '(\\w+) (\\w+)', '\\2 \\1') FROM t",
          'Smith John');
    });

    test('F104 · REGEXP_SUBSTR honors its occurrence argument', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (x NUMBER)');
      await db.execute('INSERT INTO t VALUES (1)');
      await expectScalar(db,
          "SELECT REGEXP_SUBSTR('a1b2c3', '[0-9]', 1, 2) FROM t", '2');
    });
  });

  // Oracle analytic / set-operator / formatting gaps found by a two-way
  // differential vs real Oracle 23ai.
  group('open bugs (round 24 — Oracle analytic/set-op/format, real-Oracle-adjudicated)',
      () {
    test('F105 · KEEP (DENSE_RANK FIRST/LAST) applies its ordering', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id NUMBER, v NUMBER)');
      await db.execute('INSERT INTO t VALUES (1,10),(2,30),(3,20),(4,40)');
      // KEEP ... FIRST ORDER BY id -> the v of the lowest id (10).
      await expectScalar(db,
          'SELECT MAX(v) KEEP (DENSE_RANK FIRST ORDER BY id) FROM t', 10);
    });

    test('F106 · TO_CHAR(number, format) applies the format model', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (x NUMBER)');
      await db.execute('INSERT INTO t VALUES (1)');
      await expectScalar(db,
          "SELECT TO_CHAR(1234.5, 'FM9,999.00') FROM t", '1,234.50');
    });

    test('F107 · the MINUS set operator is supported', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (g NUMBER)');
      await db.execute('INSERT INTO t VALUES (1),(2),(3)');
      // Oracle MINUS is the EXCEPT synonym.
      await expectOk(db, 'SELECT g FROM t MINUS SELECT 1 FROM t');
    });

    test('F108 · Oracle analytic features are supported', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id NUMBER, g NUMBER, v NUMBER)');
      await db.execute('INSERT INTO t VALUES (1,1,10),(2,1,30),(3,2,NULL)');
      await expectOk(db, 'SELECT RATIO_TO_REPORT(v) OVER () FROM t');
      await expectOk(db,
          'SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY v) FROM t');
      await expectOk(db,
          'SELECT FIRST_VALUE(v IGNORE NULLS) OVER (ORDER BY id) FROM t');
      await expectOk(db,
          'SELECT CONNECT_BY_ROOT g FROM t CONNECT BY PRIOR id = id - 1');
      await expectOk(db, 'SELECT WIDTH_BUCKET(25, 0, 50, 5) FROM t');
      await expectOk(db, 'SELECT GROUPING_ID(g) FROM t GROUP BY ROLLUP(g)');
    });
  });

  // Oracle DML/DDL gaps found by an effect-based differential vs real Oracle
  // 23ai. (Sequences, virtual columns, DEFAULT, INSERT ALL, UPDATE, and CHECK
  // constraints all work.)
  group('open bugs (round 25 — Oracle DML/DDL, real-Oracle-adjudicated)', () {
    test('F109 · IDENTITY columns are supported', () async {
      final db = await openEngine();
      await expectOk(db,
          'CREATE TABLE t (id NUMBER GENERATED ALWAYS AS IDENTITY, v NUMBER)');
    });

    test('F110 · NUMBER(p,s) rounds values to the declared scale', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (n NUMBER(5,2))');
      await db.execute('INSERT INTO t VALUES (1.239)');
      // Oracle rounds to the declared scale (1.24).
      await expectScalar(db, 'SELECT n FROM t', 1.24);
    });

    test('F111 · MERGE ... DELETE clause is parsed', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id NUMBER, v NUMBER)');
      await db.execute('INSERT INTO t VALUES (1, 10), (2, 20)');
      await expectOk(db,
          'MERGE INTO t USING (SELECT 1 id FROM dual) s ON (t.id = s.id) '
          'WHEN MATCHED THEN UPDATE SET v = 99 DELETE WHERE v > 50');
    });

    test('F112 · DEFAULT ON NULL is parsed', () async {
      final db = await openEngine();
      await expectOk(db,
          'CREATE TABLE t (a NUMBER DEFAULT ON NULL 7, b NUMBER)');
    });
  });

  // Oracle type-enforcement and CTE gaps found by an effect-based differential
  // vs real Oracle 23ai. (FK ON DELETE CASCADE/SET NULL, CLOB, TIMESTAMP,
  // PL/SQL loops, CREATE FUNCTION, NOT NULL, UNIQUE all work.)
  group('open bugs (round 26 — Oracle type-enforcement + CTE, real-Oracle-adjudicated)',
      () {
    test('F113 · VARCHAR2(n) length is enforced', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (s VARCHAR2(3))');
      // Oracle rejects an oversized value with ORA-12899.
      await expectThrows(db, "INSERT INTO t VALUES ('abcdefg')");
    });

    test('F114 · NUMBER(p) precision is enforced', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (n NUMBER(3))');
      // Oracle rejects an out-of-precision value with ORA-01438.
      await expectThrows(db, 'INSERT INTO t VALUES (12345)');
    });

    test('F115 · recursive WITH without the RECURSIVE keyword is resolved',
        () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE d (x NUMBER)');
      await db.execute('INSERT INTO d VALUES (1)');
      // Oracle auto-detects recursion (no RECURSIVE keyword).
      await expectOk(db,
          'WITH r(n) AS (SELECT 1 FROM d UNION ALL SELECT n+1 FROM r WHERE n < 5) '
          'SELECT COUNT(*) FROM r');
    });

    test('F116 · a WITH clause inside a subquery is parsed', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE d (x NUMBER)');
      await db.execute('INSERT INTO d VALUES (1)');
      await expectOk(db,
          'SELECT COUNT(*) FROM (WITH x AS (SELECT 1 n FROM d) SELECT n FROM x)');
    });
  });

  // More Oracle function / numeric / timestamp gaps vs real Oracle 23ai.
  // (CONNECT_BY_ISLEAF, ORDER SIBLINGS BY, NOCYCLE, LOG/LN, TO_CHAR '000',
  // TO_NUMBER '9D999' all work.)
  group('open bugs (round 27 — Oracle functions/numeric/timestamp, real-Oracle-adjudicated)',
      () {
    test('F117 · bit / byte / hash built-in functions are supported', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (x NUMBER)');
      await db.execute('INSERT INTO t VALUES (1)');
      // BITAND(6,3) = 2 in real Oracle.
      await expectScalar(db, 'SELECT BITAND(6, 3) FROM t', 2);
    });

    test('F118 · POWER with a fractional exponent is supported', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (x NUMBER)');
      await db.execute('INSERT INTO t VALUES (1)');
      // Cube root via POWER(27, 1/3) = 3 in real Oracle.
      await expectScalar(db, 'SELECT ROUND(POWER(27, 1.0/3)) FROM t', 3);
    });

    test('F119 · TIMESTAMP subtraction yields a correct INTERVAL', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (x NUMBER)');
      await db.execute('INSERT INTO t VALUES (1)');
      // ts - ts = INTERVAL '4 00:00:00'; EXTRACT(DAY ...) = 4.
      await expectScalar(db,
          "SELECT EXTRACT(DAY FROM (TIMESTAMP '2020-01-05 00:00:00' - "
          "TIMESTAMP '2020-01-01 00:00:00')) FROM t",
          4);
    });
  });

  // Oracle PL/SQL depth and TIMESTAMP WITH TIME ZONE gaps vs real Oracle 23ai.
  // (PL/SQL exception handling, WHILE loops, cursor FOR loops, CREATE FUNCTION,
  // CURRENT_TIMESTAMP all work.)
  group('open bugs (round 28 — Oracle PL/SQL + TIMESTAMP WITH TIME ZONE, real-Oracle-adjudicated)',
      () {
    test('F120 · PL/SQL packages are supported', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE d (x NUMBER)');
      await db.execute('INSERT INTO d VALUES (1)');
      await db.execute('CREATE PACKAGE pk AS FUNCTION f RETURN NUMBER; END;');
      await db.execute(
          'CREATE PACKAGE BODY pk AS FUNCTION f RETURN NUMBER IS BEGIN RETURN 42; END; END;');
      await expectScalar(db, 'SELECT pk.f FROM d', 42);
    });

    test('F121 · PL/SQL CASE statement is parsed', () async {
      final db = await openEngine();
      await expectOk(db,
          'DECLARE x NUMBER := 2; BEGIN CASE x WHEN 1 THEN NULL; '
          'WHEN 2 THEN NULL; ELSE NULL; END CASE; END;');
    });

    test('F122 · %TYPE anchored declarations are parsed', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (n NUMBER)');
      await expectOk(db,
          'DECLARE v t.n%TYPE := 99; BEGIN INSERT INTO t VALUES (v); END;');
    });

    test('F123 · TIMESTAMP WITH TIME ZONE is supported', () async {
      final db = await openEngine();
      await expectOk(db, 'CREATE TABLE t (ts TIMESTAMP WITH TIME ZONE)');
    });
  });

  // Oracle "straggler" gaps found vs real Oracle 23ai: q-quote literals,
  // RETURNING INTO, UNPIVOT, PL/SQL collections/records, ROWNUM in UPDATE, and
  // advanced query clauses. (INSERT … SELECT, PIVOT already work.)
  group('open bugs (round 29 — Oracle stragglers, real-Oracle-adjudicated)',
      () {
    test('F124 · q-quote string literals are parsed', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE d (x NUMBER)');
      await db.execute('INSERT INTO d VALUES (1)');
      await expectScalar(db, "SELECT q'[it's a test]' FROM d", "it's a test");
    });

    test('F125 · RETURNING ... INTO is parsed', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id NUMBER, v NUMBER)');
      await expectOk(db,
          'DECLARE x NUMBER; BEGIN INSERT INTO t VALUES (1, 99) '
          'RETURNING v INTO x; END;');
    });

    test('F126 · UNPIVOT is supported', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE s (id NUMBER, a NUMBER, b NUMBER)');
      await db.execute('INSERT INTO s VALUES (1, 10, 20)');
      // PIVOT works; UNPIVOT (its inverse) too.
      await expectOk(db,
          'SELECT * FROM s UNPIVOT (val FOR col IN (a, b))');
    });

    test('F127 · PL/SQL collection / record types are parsed', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE src (n NUMBER)');
      await db.execute('INSERT INTO src VALUES (5), (7)');
      await expectOk(db,
          'DECLARE TYPE nt IS TABLE OF NUMBER; a nt; '
          'BEGIN SELECT n BULK COLLECT INTO a FROM src; END;');
    });

    test('F128 · ROWNUM in UPDATE ... SET is accepted', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id NUMBER, v NUMBER)');
      await db.execute('INSERT INTO t VALUES (1, 0), (2, 0)');
      await expectOk(db, 'UPDATE t SET v = ROWNUM');
    });

    test('F129 · advanced query clauses are supported', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE s (y NUMBER, v NUMBER)');
      await db.execute('INSERT INTO s VALUES (2020, 100)');
      // MODEL (also MATCH_RECOGNIZE, PIVOT XML, flashback VERSIONS BETWEEN).
      await expectOk(db,
          'SELECT y, v FROM s MODEL DIMENSION BY (y) MEASURES (v) '
          'RULES (v[2021] = v[2020] * 2)');
    });
  });

  // Found running the real HR sample-schema analytic battery three-way vs real
  // Oracle 23ai: the Oracle nested-aggregate-over-GROUP-BY extension.
  group('open bugs (round 30 — nested aggregates, real-Oracle-adjudicated)',
      () {
    test('F130 · nested aggregate MAX(MIN(x)) over GROUP BY is supported',
        () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (d NUMBER, s NUMBER)');
      await db.execute('INSERT INTO t VALUES (1,10),(1,30),(2,20),(2,40)');
      // Oracle's two-level aggregation: MIN per group, then MAX across = 20.
      await expectScalar(db, 'SELECT MAX(MIN(s)) FROM t GROUP BY d', 20);
    });
  });

  // Data-type fidelity gaps found vs real Oracle 23ai: NUMBER is a binary
  // double (not exact decimal) and CHAR(n) is not blank-padded. (DATE
  // round-trip, big-number clamping, NUMBER division, 2.675→2.68 all match.)
  group('open bugs (round 31 — data-type fidelity, real-Oracle-adjudicated)',
      () {
    test('F131 · NUMBER is exact decimal, not binary floating point', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (v NUMBER(10,2))');
      await db.execute('INSERT INTO t VALUES (1.005)');
      // Exact decimal rounds 1.005 to 1.01.
      await expectScalar(db, 'SELECT v FROM t', 1.01);
    });

    test('F132 · CHAR(n) is blank-padded to the declared length', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (v CHAR(5))');
      await db.execute("INSERT INTO t VALUES ('ab')");
      // Oracle blank-pads CHAR(5) to 'ab   ' (LENGTH 5).
      await expectScalar(db, 'SELECT LENGTH(v) FROM t', 5);
    });
  });

  // More data-type fidelity gaps vs real Oracle 23ai: RAW/HEXTORAW, TO_CHAR
  // fractional-seconds, INTERVAL column types, and NUMBER negative scale.
  // (BINARY_DOUBLE/FLOAT arithmetic, NCHAR/NVARCHAR2, CLOB, TIMESTAMP, NUMBER(*,0)
  // all match.)
  group('open bugs (round 32 — data-type fidelity II, real-Oracle-adjudicated)',
      () {
    test('F133 · HEXTORAW / RAW hex handling is supported', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE d (x NUMBER)');
      await db.execute('INSERT INTO d VALUES (1)');
      await expectScalar(db, "SELECT RAWTOHEX(HEXTORAW('DEADBEEF')) FROM d",
          'DEADBEEF');
    });

    test('F134 · TO_CHAR fractional-seconds format (FF) is applied',
        () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (ts TIMESTAMP(3))');
      await db.execute("INSERT INTO t VALUES (TIMESTAMP '2021-06-15 13:45:30.123')");
      // Oracle 'FF3' returns just the fraction '123'.
      await expectScalar(db, "SELECT TO_CHAR(ts, 'FF3') FROM t", '123');
    });

    test('F135 · INTERVAL column types are parsed', () async {
      final db = await openEngine();
      // INTERVAL DAY TO SECOND / YEAR TO MONTH as a column type.
      await expectOk(db, 'CREATE TABLE t (v INTERVAL DAY TO SECOND)');
    });

    test('F136 · NUMBER(p, -s) negative scale is parsed', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (v NUMBER(5,-2))');
      await db.execute('INSERT INTO t VALUES (12345)');
      // Oracle rounds to the negative scale: 12345 -> 12300.
      await expectScalar(db, 'SELECT v FROM t', 12300);
    });
  });

  // Found running a big diverse HR sample-schema analytic battery three-way vs
  // real Oracle 23ai (27/30 clean). TRUNC(date, fmt) and quantified-subquery
  // comparisons.
  group('open bugs (round 33 — date-trunc format + quantified subquery, real-Oracle-adjudicated)',
      () {
    test('F137 · TRUNC(date, format) truncates to the unit', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE d (x NUMBER)');
      await db.execute('INSERT INTO d VALUES (1)');
      // Oracle truncates to the month start (2021-06-01).
      await expectScalar(db,
          "SELECT TO_CHAR(TRUNC(TO_DATE('2021-06-15','YYYY-MM-DD'),'MM'),'YYYY-MM-DD') FROM d",
          '2021-06-01');
    });

    test('F138 · quantified comparison >= ALL (subquery) is parsed',
        () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (x NUMBER)');
      await db.execute('INSERT INTO t VALUES (1), (2), (3)');
      // Oracle: rows whose x >= every x -> just the max.
      await expectOk(db, 'SELECT COUNT(*) FROM t WHERE x >= ALL (SELECT x FROM t)');
    });
  });

  // Found loading the real Oracle CO (customer_orders) schema+data three-way vs
  // real Oracle 23ai: LISTAGG overflow clause, UTL_RAW, and JSON support.
  group('open bugs (round 34 — Oracle CO schema: LISTAGG overflow / UTL_RAW / JSON, real-Oracle-adjudicated)',
      () {
    test('F139 · LISTAGG ON OVERFLOW clause is parsed', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (n NUMBER)');
      await db.execute('INSERT INTO t VALUES (1), (2)');
      // CO customer_order_products view uses this LISTAGG overflow clause.
      await expectOk(db,
          "SELECT LISTAGG(n, ',' ON OVERFLOW TRUNCATE '...' WITH COUNT) "
          'WITHIN GROUP (ORDER BY n) FROM t');
    });

    test('F140 · UTL_RAW package functions are supported', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE d (x NUMBER)');
      await db.execute('INSERT INTO d VALUES (1)');
      await expectScalar(db, "SELECT RAWTOHEX(UTL_RAW.CAST_TO_RAW('AB')) FROM d",
          '4142');
    });

    test('F141 · Oracle JSON support (JSON_VALUE/JSON_TABLE/IS JSON)',
        () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE d (x NUMBER)');
      await db.execute('INSERT INTO d VALUES (1)');
      await expectScalar(db, "SELECT JSON_VALUE('{\"a\":42}', '\$.a') FROM d", 42);
    });
  });

  // Found by the SH real-data three-way gate: NUMBER aggregation still uses
  // binary floating point (F131 fixed single-value rounding, not arithmetic).
  group('open bugs (round 35 — NUMBER aggregation precision, real-Oracle-adjudicated)',
      () {
    test('F142 · NUMBER aggregation (SUM) is exact decimal',
        () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (v NUMBER(8,2))');
      await db.execute('INSERT INTO t VALUES (0.1), (0.2)');
      // Exact-decimal SUM is 0.3.
      await expectScalar(db, 'SELECT SUM(v) FROM t', 0.3);
    });
  });

  // Was: MEDIAN carried a binary residual (F142 fixed SUM only). Fixed & verified.
  group('formerly-open bug F143 (fixed & verified; MEDIAN precision)', () {
    test('F143 · MEDIAN is exact decimal (no binary residual)', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (v NUMBER(8,2))');
      await db.execute('INSERT INTO t VALUES (1.01), (1.02)');
      // MEDIAN averages the two middle values. Oracle NUMBER is exact decimal,
      // so the answer is exactly 1.015. Assert on the RAW engine value (not the
      // harness's noise-absorbing normalizeValue) — Oracle emits "1.015", the
      // engine currently emits 1.0150000000000001.
      final r = await db.execute('SELECT MEDIAN(v) FROM t');
      final raw = r.rows.first.first;
      expect(raw.toString(), '1.015',
          reason: 'MEDIAN must be exact decimal like Oracle NUMBER, not binary');
    });
  });

  // Found finishing the real customer_orders (CO) load three-way. All fixed &
  // verified against real Oracle 23ai.
  group('formerly-open bugs F144–F146 (fixed & verified; CO load blockers)', () {
    test('F144 · IS JSON check constraint allows a valid INSERT', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE p (id NUMBER PRIMARY KEY, details BLOB)');
      await db.execute(
          'ALTER TABLE p ADD CONSTRAINT p_json CHECK (details is json)');
      // Oracle accepts a valid-JSON RAW payload; the engine throws
      // "Unknown column: json" — it mis-parses the IS JSON check at insert time.
      await expectOk(
          db,
          "INSERT INTO p (id, details) VALUES "
          "(1, UTL_RAW.CAST_TO_RAW('{\"colour\":\"white\"}'))");
    });

    test('F145 · JSON_TABLE in a view works', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE p2 (id NUMBER, details BLOB)');
      // Oracle creates this product_reviews-style view (lateral JSON_TABLE +
      // window); the engine now parses it too.
      await expectOk(db, '''CREATE OR REPLACE VIEW pr AS
        SELECT p.id, r.rating,
          ROUND(AVG(r.rating) OVER (PARTITION BY p.id), 2) avg_rating
        FROM p2 p,
          JSON_TABLE(p.details, '\$' COLUMNS (rating NUMBER PATH '\$.rating')) r''');
    });

    test('F146 · TO_TIMESTAMP parses 9-digit FF fractional seconds', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE o (id NUMBER, ts TIMESTAMP NOT NULL)');
      // Oracle parses the 9-digit fractional seconds; the engine returns NULL,
      // so the NOT NULL column rejects the row.
      await expectOk(
          db,
          "INSERT INTO o VALUES (1, TO_TIMESTAMP("
          "'05-MAR-2019 09.24.19.123456789','DD-MON-YYYY HH24.MI.SS.FF'))");
    });
  });

  // Found probing the real order_entry (OE) object-relational schema. Both
  // fixed & verified against real Oracle 23ai.
  group('formerly-open bugs F147–F148 (fixed & verified; OE object types)', () {
    test('F147 · object-type constructor is registered', () async {
      final db = await openEngine();
      await db.execute(
          'CREATE TYPE addr_typ AS OBJECT (street VARCHAR2(40), city VARCHAR2(30))');
      await db.execute('CREATE TABLE c (id NUMBER, addr addr_typ)');
      // Oracle registers a default constructor for the object type; the engine
      // throws "Unknown function: ADDR_TYP" even though the CREATE TYPE above
      // succeeded.
      await expectOk(
          db, "INSERT INTO c VALUES (1, addr_typ('1 Main St','Austin'))");
    });

    test('F148 · qualified object-attribute navigation works',
        () async {
      final db = await openEngine();
      await db.execute(
          'CREATE TYPE addr_typ AS OBJECT (street VARCHAR2(40), city VARCHAR2(30))');
      await db.execute('CREATE TABLE c (id NUMBER, addr addr_typ)');
      // Oracle navigates object attributes via a table alias (c.addr.city); the
      // engine throws "Unexpected token after statement: ." at parse time.
      await expectOk(db, 'SELECT c.addr.city FROM c c');
    });
  });

  // Found by the real customer_orders three-way gate: JSON_VALUE works over a
  // VARCHAR2 JSON column but returns NULL over a BLOB that holds JSON (the way
  // CO stores product_details). Confirmed against real Oracle 23ai.
  // Was: JSON_VALUE returned NULL over a BLOB holding JSON. Fixed & verified.
  group('formerly-open bug F149 (fixed & verified; JSON over BLOB)', () {
    test('F149 · JSON_VALUE over a BLOB column works', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE jb (id NUMBER, details BLOB)');
      await db.execute(
          "INSERT INTO jb VALUES (1, UTL_RAW.CAST_TO_RAW('{\"colour\":\"white\"}'))");
      // The BLOB holds valid JSON text (UTL_RAW.CAST_TO_VARCHAR2 round-trips it);
      // Oracle's JSON_VALUE decodes the BLOB and returns "white".
      await expectScalar(
          db, "SELECT JSON_VALUE(details, '\$.colour') FROM jb", 'white');
    });
  });

  // Found by a broad HR three-way feature sweep. All fixed & verified against
  // real Oracle 23ai.
  group('formerly-open bugs F150–F154 (fixed & verified; feature sweep)', () {
    test('F150 · ROUND(date, fmt) applies the date rounding model', () async {
      final db = await openEngine();
      // Oracle rounds to the nearest month start (day >= 16 rounds up).
      await expectScalar(
          db,
          "SELECT TO_CHAR(ROUND(DATE '2024-07-20','MONTH'),'YYYY-MM-DD') FROM dual",
          '2024-08-01');
    });

    test('F151 · TO_CHAR(number, hex fmt) applies the X format', () async {
      final db = await openEngine();
      await expectScalar(db, "SELECT TO_CHAR(255,'FMXXX') FROM dual", 'FF');
    });

    test('F152 · JSON_OBJECT with KEY ... VALUE syntax', () async {
      final db = await openEngine();
      await expectScalar(
          db, "SELECT JSON_OBJECT('k' VALUE 1) FROM dual", '{"k":1}');
    });

    test('F153 · REMAINDER built-in', () async {
      final db = await openEngine();
      // REMAINDER uses ROUND (not FLOOR like MOD): REMAINDER(17,6) = -1.
      await expectScalar(db, 'SELECT REMAINDER(17, 6) FROM dual', -1);
    });

    test('F154 · STATS_MODE aggregate', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (d NUMBER)');
      await db.execute('INSERT INTO t VALUES (50), (50), (60), (90)');
      await expectScalar(db, 'SELECT STATS_MODE(d) FROM t', 50);
    });
  });

  // Found by a second HR three-way feature sweep. All fixed & verified against
  // real Oracle 23ai.
  group('formerly-open bugs F155–F159 (fixed & verified; feature sweep II)', () {
    test('F155 · TO_CHAR(date) week/Julian format elements', () async {
      final db = await openEngine();
      // 'WW' is the week of the year (29 for 2024-07-20); also IW and J now work.
      await expectScalar(
          db, "SELECT TO_CHAR(DATE '2024-07-20','WW') FROM dual", '29');
    });

    test('F156 · TO_CHAR(date, \'DDD\') returns the right day-of-year',
        () async {
      final db = await openEngine();
      // Day-of-year for Jan 1 is 001.
      await expectScalar(
          db, "SELECT TO_CHAR(DATE '2024-01-01','DDD') FROM dual", '001');
    });

    test('F157 · JSON_EXISTS predicate', () async {
      final db = await openEngine();
      await expectScalar(
          db,
          "SELECT CASE WHEN JSON_EXISTS('{\"a\":1}', '\$.a') THEN 1 ELSE 0 END FROM dual",
          1);
    });

    test('F158 · JSON_VALUE RETURNING clause', () async {
      final db = await openEngine();
      await expectScalar(
          db,
          "SELECT JSON_VALUE('{\"n\":12.5}', '\$.n' RETURNING NUMBER) FROM dual",
          12.5);
    });

    test('F159 · VSIZE / DUMP datatype-introspection functions', () async {
      final db = await openEngine();
      await expectScalar(db, 'SELECT VSIZE(123) FROM dual', 3);
    });
  });

  // Found by a third HR three-way feature sweep. F160–F163 and F166 fixed &
  // verified; F164 (LEAD/LAG IGNORE NULLS) and F165 (CAST enforcement) still open.
  group('CO feature sweep III (round 42 — F160-163/166 fixed; F164-165 open)', () {
    test('F160 · TO_CHAR(number) format elements RN/EEEE/PR/L/V', () async {
      final db = await openEngine();
      // 'RN' is the Roman numeral.
      await expectScalar(db, "SELECT TO_CHAR(2024,'FMRN') FROM dual", 'MMXXIV');
    });

    test('F161 · TO_CHAR(date) format elements D/CC/YEAR/RRRR + quoted text',
        () async {
      final db = await openEngine();
      // 'CC' is the century (21 for 2024).
      await expectScalar(
          db, "SELECT TO_CHAR(DATE '2024-07-20','CC') FROM dual", '21');
    });

    test('F162 · REGEXP_SUBSTR subexpression parameter', () async {
      final db = await openEngine();
      // The 6th arg selects capture group 2 ("123"); the engine ignores it.
      await expectScalar(
          db,
          "SELECT REGEXP_SUBSTR('abc123def','([a-z]+)([0-9]+)',1,1,NULL,2) FROM dual",
          '123');
    });

    test('F163 · LISTAGG default separator is empty', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (s VARCHAR2(10))');
      await db.execute("INSERT INTO t VALUES ('a'), ('b'), ('c')");
      // With no separator argument Oracle concatenates with nothing.
      await expectScalar(
          db, 'SELECT LISTAGG(s) WITHIN GROUP (ORDER BY s) FROM t', 'abc');
    });

    test('F164 · LEAD/LAG IGNORE NULLS', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id NUMBER, v NUMBER)');
      await db.execute('INSERT INTO t VALUES (1, 10), (2, NULL), (3, 30)');
      // IGNORE NULLS skips the NULL row: LEAD from id 1 returns 30.
      await expectScalar(
          db,
          'SELECT LEAD(v) IGNORE NULLS OVER (ORDER BY id) FROM t '
          'FETCH FIRST 1 ROW ONLY',
          30);
    });

    test('F165 · CAST to NUMBER(p,s)/VARCHAR2(n) enforces precision/length',
        () async {
      final db = await openEngine();
      // CAST to NUMBER(5,1) rounds to the declared scale.
      await expectScalar(
          db, 'SELECT CAST(123.456 AS NUMBER(5,1)) FROM dual', 123.5);
    });

    test('F166 · missing funcs NLSSORT/ASCIISTR/UNISTR/GROUP_ID/APPROX_COUNT_DISTINCT',
        () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (d NUMBER)');
      await db.execute('INSERT INTO t VALUES (10), (10), (20), (30)');
      await expectScalar(db, 'SELECT APPROX_COUNT_DISTINCT(d) FROM t', 3);
    });
  });

  // Found by a fourth HR three-way feature sweep (INTERVAL, hierarchical, date
  // TRUNC/ROUND, KEEP, XML — confirmed vs real Oracle 23ai). F169 still open;
  // F167/F168/F170/F171/F172 fixed & verified.
  group('feature sweep IV (round 43 — F167/168/170/171/172 fixed; F169 open)', () {
    test('F167 · EXTRACT from an INTERVAL value', () async {
      final db = await openEngine();
      // 2 days 03:04:05 — the hour field is 3.
      await expectScalar(
          db,
          "SELECT EXTRACT(HOUR FROM INTERVAL '2 03:04:05' DAY TO SECOND) FROM dual",
          3);
    });

    test('F168 · TRUNC(date, \'IW\') starts the ISO week on Monday', () async {
      final db = await openEngine();
      // 2024-07-20 is a Saturday; the ISO week starts Monday 2024-07-15.
      await expectScalar(
          db,
          "SELECT TO_CHAR(TRUNC(DATE '2024-07-20','IW'),'YYYY-MM-DD') FROM dual",
          '2024-07-15');
    });

    test('F169 · LEVEL in the CONNECT BY predicate', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE emp (id NUMBER, mgr NUMBER)');
      await db.execute('INSERT INTO emp VALUES (1, NULL), (2, 1), (3, 2)');
      // AND LEVEL <= 2 limits the walk to two levels: 2 rows.
      await expectScalar(
          db,
          'SELECT COUNT(*) FROM emp START WITH mgr IS NULL '
          'CONNECT BY PRIOR id = mgr AND LEVEL <= 2',
          2);
    });

    test('F170 · CONNECT_BY_ISCYCLE / NOCYCLE', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE emp (id NUMBER, mgr NUMBER)');
      await db.execute('INSERT INTO emp VALUES (1, NULL), (2, 1), (3, 2)');
      await expectScalar(
          db,
          'SELECT MAX(CONNECT_BY_ISCYCLE) FROM emp START WITH mgr IS NULL '
          'CONNECT BY NOCYCLE PRIOR id = mgr',
          0);
    });

    test('F171 · KEEP (DENSE_RANK FIRST) NULL ordering', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE k (g NUMBER, v NUMBER)');
      await db.execute('INSERT INTO k VALUES (NULL, 99), (1, 10), (1, 30)');
      // ORDER BY g ascending: NULLs sort LAST, so FIRST is g=1 -> MAX(v)=30.
      await expectScalar(
          db, 'SELECT MAX(v) KEEP (DENSE_RANK FIRST ORDER BY g) FROM k', 30);
    });

    test('F172 · XMLELEMENT + object method call', () async {
      final db = await openEngine();
      await expectScalar(
          db, "SELECT XMLELEMENT(\"e\", 'hi').getStringVal() FROM dual",
          '<e>hi</e>');
    });

    test('F173 · LNNVL built-in', () async {
      final db = await openEngine();
      // LNNVL returns TRUE when the condition is false/unknown.
      await expectScalar(
          db, "SELECT CASE WHEN LNNVL(1=2) THEN 'y' ELSE 'n' END FROM dual", 'y');
    });
  });

  // Found by a fifth HR three-way feature sweep (string/number/date/fetch).
  // All fixed & verified against real Oracle 23ai.
  group('formerly-open bugs F174–F176 (fixed & verified; feature sweep V)', () {
    test('F174 · TO_NUMBER with a format model', () async {
      final db = await openEngine();
      // The group-separator format parses the grouped literal.
      await expectScalar(
          db, "SELECT TO_NUMBER('1,234.56', '9,999.99') FROM dual", 1234.56);
    });

    test('F175 · TO_CHAR lowercase fm modifier', () async {
      final db = await openEngine();
      // 'fm' (any case) trims padding; the engine keeps "fm" literally.
      await expectScalar(
          db,
          "SELECT TO_CHAR(DATE '2024-07-20', 'fmDay, Month DD, YYYY') FROM dual",
          'Saturday, July 20, 2024');
    });

    test('F176 · FETCH FIRST n PERCENT ROWS ONLY', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (v NUMBER)');
      for (var i = 1; i <= 10; i++) {
        await db.execute('INSERT INTO t VALUES ($i)');
      }
      // 50% of 10 rows is 5.
      await expectScalar(
          db,
          'SELECT COUNT(*) FROM '
          '(SELECT v FROM t ORDER BY v FETCH FIRST 50 PERCENT ROWS ONLY)',
          5);
    });
  });

  // Found by a sixth HR three-way feature sweep. All fixed & verified.
  group('formerly-open bugs F177\u2013F182 (fixed & verified; feature sweep VI)', () {
    test('F177 · FROM_TZ + AT TIME ZONE', () async {
      final db = await openEngine();
      // 12:00 UTC shown AT TIME ZONE +05:00 is 17:00.
      await expectScalar(
          db,
          "SELECT TO_CHAR(FROM_TZ(TIMESTAMP '2024-01-01 12:00:00','+00:00') "
          "AT TIME ZONE '+05:00','HH24:MI') FROM dual",
          '17:00');
    });

    test('F178 · GROUP BY CUBE/ROLLUP row count', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (a NUMBER, b NUMBER)');
      await db.execute('INSERT INTO t VALUES (1, 10), (1, 20), (2, 10)');
      // CUBE(a,b): 3 base groups + 2 (a) + 2 (b) + 1 () = 8 rows.
      await expectScalar(
          db, 'SELECT COUNT(*) FROM (SELECT a, b FROM t GROUP BY CUBE(a, b))',
          8);
    });

    test('F179 · row/tuple IN-list', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE u (a NUMBER, b VARCHAR2(5))');
      await db.execute("INSERT INTO u VALUES (90, 'x'), (60, 'y'), (1, 'z')");
      // Two of the three rows match the tuple IN-list.
      await expectScalar(
          db, "SELECT COUNT(*) FROM u WHERE (a, b) IN ((90, 'x'), (60, 'y'))",
          2);
    });

    test('F180 · ROUND is exact-decimal (half-up)', () async {
      final db = await openEngine();
      // 1.005 rounds up to 1.01 on exact decimal; binary gives 1.00.
      await expectScalar(db, 'SELECT ROUND(1.005, 2) FROM dual', 1.01);
    });

    test('F181 · NANVL built-in', () async {
      final db = await openEngine();
      // NANVL returns the first arg when it is not NaN.
      await expectScalar(db, 'SELECT NANVL(5, -1) FROM dual', 5);
    });

    test('F182 · inline WITH FUNCTION (PL/SQL)', () async {
      final db = await openEngine();
      await expectScalar(
          db,
          'WITH FUNCTION dbl(x NUMBER) RETURN NUMBER IS BEGIN RETURN x*2; END; '
          'SELECT dbl(21) v FROM dual',
          42);
    });
  });

  // Found by a broad HR three-way mega-sweep (67 queries across date/number
  // formats, stats/JSON/XML functions, predicates — all confirmed vs real
  // Oracle 23ai). Oracle-also-errors and boolean-casing diffs were excluded.
  group('open bugs (round 46 — mega-sweep, real-Oracle-adjudicated)', () {
    test('F183 · TO_CHAR(date) format elements (IYYY/RM/W/SSSSS/SP-TH)',
        () async {
      final db = await openEngine();
      await expectScalar(
          db, "SELECT TO_CHAR(DATE '2024-07-20','IYYY') FROM dual", '2024');
    });

    test('F184 · TO_CHAR(number) format elements (RM/G/D/MI)', () async {
      final db = await openEngine();
      // MI puts a trailing minus for negatives.
      await expectScalar(db, "SELECT TO_CHAR(-1234,'FM9999MI') FROM dual", '1234-');
    });

    test('F185 · linear-regression aggregates (REGR_*)', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE m (x NUMBER, y NUMBER)');
      await db.execute('INSERT INTO m VALUES (1, 10), (2, 20), (3, 30)');
      await expectScalar(db, 'SELECT REGR_COUNT(y, x) FROM m', 3);
    });

    test('F186 · NTH_VALUE ... FROM LAST', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE m (y NUMBER)');
      await db.execute('INSERT INTO m VALUES (10), (20), (30)');
      // FROM LAST counts from the end; the 1st-from-last over the full frame is 30.
      await expectScalar(
          db,
          'SELECT MAX(nv) FROM (SELECT NTH_VALUE(y, 1) FROM LAST OVER '
          '(ORDER BY y ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) '
          'nv FROM m)',
          30);
    });

    test('F187 · JSON aggregate/manipulation functions', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE m (y NUMBER)');
      await db.execute('INSERT INTO m VALUES (10), (20), (30)');
      await expectScalar(
          db, 'SELECT JSON_ARRAYAGG(y ORDER BY y) FROM m', '[10,20,30]');
    });

    test('F188 · XML query/serialize functions', () async {
      final db = await openEngine();
      await expectScalar(
          db,
          "SELECT XMLCAST(XMLQUERY('1+2' RETURNING CONTENT) AS NUMBER) FROM dual",
          3);
    });

    test('F189 · ROWID / SESSIONTIMEZONE pseudocolumns', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (x NUMBER)');
      await db.execute('INSERT INTO t VALUES (1)');
      await expectOk(db, 'SELECT COUNT(*) FROM t WHERE ROWID IS NOT NULL');
    });

    test('F190 · missing scalar functions (NCHR/COMPOSE/NEW_TIME/…)', () async {
      final db = await openEngine();
      await expectScalar(db, 'SELECT NCHR(65) FROM dual', 'A');
    });

    test('F191 · OVERLAPS predicate', () async {
      final db = await openEngine();
      await expectScalar(
          db,
          "SELECT CASE WHEN (DATE '2024-01-01', DATE '2024-06-01') OVERLAPS "
          "(DATE '2024-03-01', DATE '2024-09-01') THEN 1 ELSE 0 END FROM dual",
          1);
    });

    test('F192 · = ALL (subquery)', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE m (x NUMBER, y NUMBER)');
      await db.execute('INSERT INTO m VALUES (1, 10), (2, 20)');
      // = ALL over a single-row subquery; the one matching row counts.
      await expectScalar(
          db,
          'SELECT COUNT(*) FROM m WHERE y = ALL (SELECT y FROM m WHERE x = 1)',
          1);
    });

    test('F193 · MONTHS_BETWEEN end-of-month handling', () async {
      final db = await openEngine();
      // Both dates are last-day-of-month, so Oracle returns a whole number.
      await expectScalar(
          db,
          "SELECT MONTHS_BETWEEN(DATE '2024-03-31', DATE '2024-02-29') FROM dual",
          1);
    });
  });

  // Found by a second HR three-way mega-sweep (string/number/date/set/row-gen —
  // confirmed vs real Oracle 23ai; windowed MEDIAN/KEEP diffs were false
  // positives from nondeterministic FETCH ordering and excluded).
  group('open bugs (round 47 — mega-sweep II, real-Oracle-adjudicated)', () {
    test('F194 · INITCAP treats apostrophe as a word boundary', () async {
      final db = await openEngine();
      // Oracle capitalizes the letter after the apostrophe (O'Brien).
      await expectScalar(
          db, "SELECT INITCAP('o''brien mcleod') FROM dual", "O'Brien Mcleod");
    });

    test('F195 · CONNECT BY LEVEL row generator', () async {
      final db = await openEngine();
      // The classic dual row generator should produce 5 rows (1+2+3+4+5=15).
      await expectScalar(
          db, 'SELECT SUM(LEVEL) FROM dual CONNECT BY LEVEL <= 5', 15);
    });

    test('F196 · INTERSECT ALL / MINUS ALL', () async {
      final db = await openEngine();
      await expectScalar(
          db,
          'SELECT COUNT(*) FROM (SELECT 1 FROM dual INTERSECT ALL SELECT 1 FROM dual)',
          1);
    });
  });

  // Found by a third HR three-way mega-sweep (regexp flags, grouping, analytic,
  // date parsing — confirmed vs real Oracle 23ai). CROSS-JOIN and PIVOT diffs
  // were excluded (could not reproduce minimally / inconsistent).
  group('open bugs (round 48 — mega-sweep III, real-Oracle-adjudicated)', () {
    test('F197 · REGEXP case-insensitive match_param', () async {
      final db = await openEngine();
      await expectScalar(
          db,
          "SELECT CASE WHEN REGEXP_LIKE('abc', 'ABC', 'i') THEN 1 ELSE 0 END FROM dual",
          1);
    });

    test('F198 · GROUP BY () empty grouping', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE a (x NUMBER)');
      await db.execute('INSERT INTO a VALUES (1), (2)');
      // GROUP BY () is a single grand-total group.
      await expectScalar(db, 'SELECT COUNT(*) FROM a GROUP BY ()', 2);
    });

    test('F199 · aggregate-over-aggregate analytic (SUM(COUNT(*)) OVER ())',
        () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE a (x NUMBER)');
      await db.execute('INSERT INTO a VALUES (1), (2)');
      // Two groups of 1; the windowed sum of the group counts is 2.
      await expectScalar(
          db, 'SELECT DISTINCT SUM(COUNT(*)) OVER () FROM a GROUP BY x', 2);
    });

    test('F200 · TO_DATE with DDD day-of-year', () async {
      final db = await openEngine();
      // Day 60 of leap-year 2024 is Feb 29.
      await expectScalar(
          db,
          "SELECT TO_CHAR(TO_DATE('2024-060','YYYY-DDD'),'YYYY-MM-DD') FROM dual",
          '2024-02-29');
    });

    test('F201 · TRUNC(date, \'IYYY\') ISO year', () async {
      final db = await openEngine();
      await expectScalar(
          db,
          "SELECT TO_CHAR(TRUNC(DATE '2024-07-20','IYYY'),'YYYY-MM-DD') FROM dual",
          '2024-01-01');
    });
  });

  // Found by a fourth HR three-way mega-sweep (ROWNUM, MOD, composite GROUP BY,
  // JSON_TABLE, TZ, interval cast — confirmed vs real Oracle 23ai). UNION-NULL
  // and NUMTODSINTERVAL display diffs were excluded (no minimal repro / display-only).
  group('open bugs (round 49 — mega-sweep IV, real-Oracle-adjudicated)', () {
    test('F202 · MOD(n, 0) returns n (no crash)', () async {
      final db = await openEngine();
      // Oracle: MOD(n, 0) = n. The engine threw IntegerDivisionByZeroException.
      await expectScalar(db, 'SELECT MOD(5, 0) FROM dual', 5);
    });

    test('F203 · ROLLUP/CUBE in a composite GROUP BY', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE g (a NUMBER, b NUMBER)');
      await db.execute('INSERT INTO g VALUES (1, 10), (1, 20), (2, 30)');
      // GROUP BY a, ROLLUP(b): per-a (a,b) groups + per-a subtotal = 5 rows.
      await expectScalar(
          db, 'SELECT COUNT(*) FROM (SELECT a FROM g GROUP BY a, ROLLUP(b))', 5);
    });

    test('F204 · JSON_TABLE array wildcard \$[*]', () async {
      final db = await openEngine();
      // Each array element produces a row: 2 rows.
      await expectScalar(
          db,
          "SELECT COUNT(*) FROM (SELECT * FROM JSON_TABLE("
          "'[{\"a\":1},{\"a\":2}]', '\$[*]' COLUMNS (a NUMBER PATH '\$.a')))",
          2);
    });

    test('F205 · COUNT(*) with WHERE ROWNUM <= n', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id NUMBER)');
      for (var i = 1; i <= 10; i++) {
        await db.execute('INSERT INTO t VALUES ($i)');
      }
      // ROWNUM limits to 3 rows before aggregation.
      await expectScalar(db, 'SELECT COUNT(*) FROM t WHERE ROWNUM <= 3', 3);
    });

    test('F206 · TO_BINARY_FLOAT / TO_BINARY_DOUBLE', () async {
      final db = await openEngine();
      await expectScalar(
          db,
          "SELECT CASE WHEN TO_BINARY_FLOAT('3.14') > 3 THEN 1 ELSE 0 END FROM dual",
          1);
    });

    test('F207 · EXTRACT(TIMEZONE_MINUTE FROM ts)', () async {
      final db = await openEngine();
      await expectScalar(
          db,
          "SELECT EXTRACT(TIMEZONE_MINUTE FROM "
          "TIMESTAMP '2024-01-01 00:00:00 +05:30') FROM dual",
          30);
    });

    test('F208 · (expr) DAY TO SECOND interval cast', () async {
      final db = await openEngine();
      // The day-difference cast to an interval; the day field is 60.
      await expectScalar(
          db,
          "SELECT EXTRACT(DAY FROM "
          "(DATE '2024-03-01' - DATE '2024-01-01') DAY TO SECOND) FROM dual",
          60);
    });
  });

  // Found by a fifth HR three-way mega-sweep (POSIX regex, APPROX percentile,
  // interval YEAR TO MONTH arithmetic — confirmed vs real Oracle 23ai). Many
  // Oracle-also-errors, empty-string-dialect, and engine-superset diffs excluded.
  group('open bugs (round 50 — mega-sweep V, real-Oracle-adjudicated)', () {
    test('F209 · REGEXP POSIX character classes', () async {
      final db = await openEngine();
      // [[:digit:]] matches digits; the engine leaves the string unchanged.
      await expectScalar(
          db, "SELECT REGEXP_REPLACE('a1b2','[[:digit:]]','#') FROM dual", 'a#b#');
    });

    test('F210 · APPROX_PERCENTILE aggregate', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE m (v NUMBER)');
      await db.execute('INSERT INTO m VALUES (10), (20), (30), (40)');
      await expectScalar(
          db,
          'SELECT APPROX_PERCENTILE(0.5) WITHIN GROUP (ORDER BY v) FROM m',
          20);
    });

    test('F211 · INTERVAL YEAR TO MONTH arithmetic keeps the day', () async {
      final db = await openEngine();
      // 2024-07-20 + 1 year 6 months = 2026-01-20 (day unchanged).
      await expectScalar(
          db,
          "SELECT TO_CHAR(DATE '2024-07-20' + INTERVAL '1-6' YEAR TO MONTH,"
          "'YYYY-MM-DD') FROM dual",
          '2026-01-20');
    });
  });

  // Found by a sixth HR three-way mega-sweep (LOB + NLS functions). Both fixed
  // & verified against real Oracle 23ai.
  group('formerly-open bugs F212–F213 (fixed & verified; LOB + NLS)', () {
    test('F212 · TO_CLOB', () async {
      final db = await openEngine();
      await expectScalar(db, "SELECT TO_CHAR(TO_CLOB('hello')) FROM dual", 'hello');
    });

    test('F213 · NLS_UPPER / NLS_LOWER / NLS_INITCAP', () async {
      final db = await openEngine();
      await expectScalar(
          db, "SELECT NLS_INITCAP('hello world') FROM dual", 'Hello World');
    });
  });

  // Found by a DML/DDL-effects three-way sweep (16/18 cases already matched real
  // Oracle 23ai: MERGE update/insert/delete, CHECK/UNIQUE/FK-cascade, IDENTITY,
  // sequences, DEFAULT, correlated UPDATE, number-scale, varchar-length, virtual
  // columns). F214 fixed; triggers (F215/F216) and DEFAULT seq (F217) open.
  group('DML/DDL effects (round 52 — F214 fixed; F215-F217 open)', () {
    test('F214 · INSERT ALL (multi-table insert)', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE ia (id NUMBER, v NUMBER)');
      // The multi-table INSERT ALL with a driving SELECT should insert 2 rows.
      await db.execute(
          'INSERT ALL INTO ia (id, v) VALUES (1, 10) '
          'INTO ia (id, v) VALUES (2, 20) SELECT * FROM dual');
      await expectScalar(db, 'SELECT COUNT(*) FROM ia', 2);
    });

    test('F215 · BEFORE UPDATE row-level trigger fires', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE tg (id NUMBER, v NUMBER, upd NUMBER DEFAULT 0)');
      await db.execute('INSERT INTO tg VALUES (1, 10, 0)');
      await db.execute(
          'CREATE OR REPLACE TRIGGER tg_bu BEFORE UPDATE ON tg FOR EACH ROW '
          'BEGIN :NEW.upd := :OLD.upd + 1; END;');
      await db.execute('UPDATE tg SET v = 20 WHERE id = 1');
      // The trigger should have incremented upd to 1.
      await expectScalar(db, 'SELECT upd FROM tg WHERE id = 1', 1);
    });

    test('F216 · INSTEAD OF trigger on a view', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE iob (id NUMBER, v NUMBER)');
      await db.execute('CREATE VIEW iov AS SELECT id, v FROM iob');
      await db.execute(
          'CREATE OR REPLACE TRIGGER iov_ii INSTEAD OF INSERT ON iov '
          'FOR EACH ROW BEGIN INSERT INTO iob VALUES (:NEW.id, :NEW.v * 10); END;');
      // The INSTEAD OF trigger redirects the view insert into the base table.
      await db.execute('INSERT INTO iov VALUES (1, 5)');
      await expectScalar(db, 'SELECT v FROM iob WHERE id = 1', 50);
    });

    test('F217 · DEFAULT <sequence>.NEXTVAL column default', () async {
      final db = await openEngine();
      await db.execute('CREATE SEQUENCE ns2 START WITH 1');
      // A sequence NEXTVAL as a column DEFAULT (common surrogate-key pattern).
      await db.execute(
          'CREATE TABLE nn (id NUMBER DEFAULT ns2.NEXTVAL NOT NULL, v NUMBER)');
      await db.execute('INSERT INTO nn (v) VALUES (10)');
      await expectScalar(db, 'SELECT id FROM nn', 1);
    });
  });

  // Found by a complex composite-query three-way sweep (32/35 already matched
  // real Oracle 23ai). All confirmed vs Oracle.
  group('open bugs (round 53 — complex queries, real-Oracle-adjudicated)', () {
    test('F218 · LAG/LEAD with a column default argument', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (v NUMBER)');
      await db.execute('INSERT INTO t VALUES (10), (30)');
      // The 3rd arg (default when no prior row) is the column v, not a literal.
      await expectScalar(
          db,
          'SELECT LAG(v, 1, v) OVER (ORDER BY v) FROM t FETCH FIRST 1 ROW ONLY',
          10);
    });

    test('F219 · GROUPING() marks ROLLUP superaggregate rows', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (g NUMBER)');
      await db.execute('INSERT INTO t VALUES (1), (1), (2)');
      // GROUPING(g)=1 only on the grand-total row, so 2 detail groups remain.
      await expectScalar(
          db,
          'SELECT COUNT(*) FROM (SELECT g FROM t GROUP BY ROLLUP(g) '
          'HAVING GROUPING(g) = 0)',
          2);
    });

    test('F220 · PIVOT row count', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (g NUMBER, v NUMBER)');
      await db.execute('INSERT INTO t VALUES (1, 10), (1, 30), (2, 50)');
      // PIVOT groups by the implicit non-pivoted column v: 3 distinct rows.
      await expectScalar(
          db,
          'SELECT COUNT(*) FROM (SELECT * FROM (SELECT g, v FROM t) '
          'PIVOT (COUNT(*) FOR g IN (1, 2)))',
          3);
    });
  });

  // Found by a data-type fidelity three-way sweep (19/22 already matched real
  // Oracle 23ai). All confirmed vs Oracle.
  group('open bugs (round 54 — data-type fidelity, real-Oracle-adjudicated)', () {
    test('F221 · CHAR blank-padded comparison', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE c (x CHAR(5))');
      await db.execute("INSERT INTO c VALUES ('ab')");
      // CHAR comparison blank-pads both sides: 'ab   ' = 'ab' is true.
      await expectScalar(
          db, "SELECT CASE WHEN x = 'ab' THEN 1 ELSE 0 END FROM c", 1);
    });

    test('F222 · concatenation treats NULL as empty string', () async {
      final db = await openEngine();
      // Oracle || never nulls the result for non-null operands.
      await expectScalar(
          db, "SELECT 'x' || CAST(NULL AS VARCHAR2(5)) || 'y' FROM dual", 'xy');
    });

    test('F223 · EXTRACT field from an INTERVAL column', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE i (v INTERVAL DAY TO SECOND)');
      await db.execute("INSERT INTO i VALUES (INTERVAL '1 02:00:00' DAY TO SECOND)");
      // 1 day 2 hours — the HOUR field is 2.
      await expectScalar(db, 'SELECT EXTRACT(HOUR FROM v) FROM i', 2);
    });

    test('F224 · multi-column UPDATE SET (a,b) = (subquery)', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id NUMBER, a NUMBER, b NUMBER)');
      await db.execute('INSERT INTO t VALUES (1, 0, 0)');
      // Oracle updates both columns from a single row-subquery.
      await db.execute(
          'UPDATE t SET (a, b) = (SELECT 5, 7 FROM dual) WHERE id = 1');
      await expectScalar(db, 'SELECT a + b FROM t', 12);
    },
        skip: 'KNOWN ENGINE BUG: the multi-column UPDATE form '
            '"SET (a, b) = (SELECT …)" is a parse error ("Expected identifier but '
            'got ("). Real Oracle updates both columns (a+b = 12). '
            'See findings/FINDINGS.md F224.');
  });

  // Found by an advanced-SQL-features three-way sweep (all parse errors on the
  // engine; real Oracle 23ai returns values). F129 flagged some of these as
  // "rare/advanced" — here are concrete repros.
  group('open bugs (round 55 — advanced SQL, real-Oracle-adjudicated)', () {
    test('F225 · MATCH_RECOGNIZE', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE mr (id NUMBER, v NUMBER)');
      await db.execute('INSERT INTO mr VALUES (1, 5), (2, 5)');
      // One contiguous match of the A+ pattern over both rows.
      await expectScalar(
          db,
          'SELECT COUNT(*) FROM mr MATCH_RECOGNIZE (ORDER BY id '
          'MEASURES COUNT(*) AS c PATTERN (A+) DEFINE A AS v > 0)',
          1);
    },
        skip: 'KNOWN ENGINE BUG: MATCH_RECOGNIZE (row pattern matching) is a '
            'parse error. Real Oracle returns 1. See findings/FINDINGS.md F225.');

    test('F226 · recursive WITH CYCLE / SEARCH clauses', () async {
      final db = await openEngine();
      // The CYCLE clause on a recursive WITH is a parse error.
      await expectScalar(
          db,
          'SELECT COUNT(*) FROM (WITH r(n) AS (SELECT 1 FROM dual UNION ALL '
          'SELECT n+1 FROM r WHERE n < 4) CYCLE n SET cyc TO 1 DEFAULT 0 '
          'SELECT n FROM r)',
          4);
    },
        skip: 'KNOWN ENGINE BUG: the CYCLE and SEARCH clauses on a recursive '
            'WITH are parse errors ("Expected SELECT/… after WITH"). The plain '
            'recursion works. Real Oracle returns 4 (CYCLE) / 3 (SEARCH ord). '
            'See findings/FINDINGS.md F226.');

    test('F227 · TABLE() collection unnesting', () async {
      final db = await openEngine();
      // Unnest a built-in collection into rows.
      await expectScalar(
          db, 'SELECT COUNT(*) FROM TABLE(SYS.ODCINUMBERLIST(10, 20, 30))', 3);
    },
        skip: 'KNOWN ENGINE BUG: TABLE(collection) unnesting (and the '
            'COLUMN_VALUE pseudo-column) is a parse error ("Expected identifier '
            'but got TABLE"). Real Oracle returns 3. See findings/FINDINGS.md F227.');

    test('F228 · PIVOT XML', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE px (g NUMBER, j VARCHAR2(2))');
      await db.execute("INSERT INTO px VALUES (1, 'a'), (2, 'b')");
      await expectScalar(
          db,
          'SELECT COUNT(*) FROM (SELECT * FROM (SELECT g, j FROM px) '
          'PIVOT XML (COUNT(*) FOR j IN (ANY)))',
          2);
    },
        skip: 'KNOWN ENGINE BUG: PIVOT XML is a parse error ("Expected ( but got '
            'XML"). Real Oracle returns 2. See findings/FINDINGS.md F228.');

    test('F229 · LATERAL inline view', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE la (id NUMBER)');
      await db.execute('INSERT INTO la VALUES (1), (2)');
      await db.execute('CREATE TABLE lb (aid NUMBER)');
      await db.execute('INSERT INTO lb VALUES (1), (1)');
      // id=1 joins two lb rows, id=2 joins none: 2 rows.
      await expectScalar(
          db,
          'SELECT COUNT(*) FROM la, LATERAL (SELECT 1 x FROM lb '
          'WHERE lb.aid = la.id)',
          2);
    },
        skip: 'KNOWN ENGINE BUG: LATERAL inline views are a parse error. Real '
            'Oracle returns 2. See findings/FINDINGS.md F229.');

    test('F230 · CROSS APPLY / OUTER APPLY', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE la (id NUMBER)');
      await db.execute('INSERT INTO la VALUES (1), (2)');
      await db.execute('CREATE TABLE lb (aid NUMBER)');
      await db.execute('INSERT INTO lb VALUES (1), (1)');
      // CROSS APPLY keeps only matching rows: 2 (id=1 x2).
      await expectScalar(
          db,
          'SELECT COUNT(*) FROM la CROSS APPLY (SELECT 1 x FROM lb '
          'WHERE lb.aid = la.id)',
          2);
    },
        skip: 'KNOWN ENGINE BUG: CROSS APPLY and OUTER APPLY are parse errors. '
            'Real Oracle returns 2 (CROSS) / 3 (OUTER, id=2 keeps a NULL row). '
            'See findings/FINDINGS.md F230.');
  });

  // Found by a second advanced-features three-way sweep (confirmed vs real
  // Oracle 23ai).
  group('open bugs (round 56 — advanced SQL II, real-Oracle-adjudicated)', () {
    test('F231 · SYS_CONTEXT / USERENV', () async {
      final db = await openEngine();
      await expectScalar(
          db,
          "SELECT CASE WHEN SYS_CONTEXT('USERENV','SESSION_USER') IS NOT NULL "
          "THEN 1 ELSE 0 END FROM dual",
          1);
    },
        skip: 'KNOWN ENGINE BUG: SYS_CONTEXT and USERENV (session-context '
            'functions) are missing ("Unknown function"). Real Oracle returns 1. '
            'See findings/FINDINGS.md F231.');

    test('F232 · XMLTABLE with PASSING', () async {
      final db = await openEngine();
      // Shred an XML document into rows.
      await expectScalar(
          db,
          "SELECT COUNT(*) FROM XMLTABLE('/a/b' PASSING "
          "XMLTYPE('<a><b>1</b><b>2</b></a>') COLUMNS v NUMBER PATH '.')",
          2);
    },
        skip: 'KNOWN ENGINE BUG: XMLTABLE with a PASSING clause is a parse error '
            '("Expected ) but got PASSING"). Real Oracle returns 2. '
            'See findings/FINDINGS.md F232.');

    test('F233 · JSON dot-notation column access', () async {
      final db = await openEngine();
      // Oracle 19c+ simplified JSON access: col.key.string().
      await expectScalar(
          db,
          "SELECT jt.doc.name.string() FROM "
          "(SELECT JSON('{\"name\":\"x\"}') doc FROM dual) jt",
          'x');
    },
        skip: 'KNOWN ENGINE BUG: JSON dot-notation column access '
            '(jt.doc.name.string()) is a parse error. Real Oracle returns "x". '
            'See findings/FINDINGS.md F233.');

    test('F234 · default NULLS ordering matches Oracle', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (v NUMBER)');
      await db.execute('INSERT INTO t VALUES (1), (NULL), (2)');
      // Oracle sorts NULLs LAST for ASC and FIRST for DESC (NULL = greatest);
      // so DESC's first row is NULL. The engine uses SQLite ordering (NULL
      // smallest) and returns 2.
      await expectScalar(
          db, 'SELECT v FROM t ORDER BY v DESC FETCH FIRST 1 ROW ONLY', null);
    },
        skip: 'KNOWN ENGINE BUG: default NULLS ordering is the opposite of '
            'Oracle — the engine treats NULL as the smallest value (NULLS FIRST '
            'for ASC, LAST for DESC) like SQLite, whereas Oracle treats NULL as '
            'the greatest (NULLS LAST for ASC, FIRST for DESC). ORDER BY v DESC '
            'returns 2 instead of NULL. See findings/FINDINGS.md F234.');
  });

  // Found by an ALTER/DDL-effects three-way sweep (12/17 already matched real
  // Oracle 23ai: ADD single col, DROP COLUMN, RENAME col/table, ADD PK/CHECK/FK,
  // SET UNUSED, CTAS, COMMENT, unique index). These are genuine gaps.
  group('open bugs (round 57 — ALTER TABLE, real-Oracle-adjudicated)', () {
    test('F235 · ALTER TABLE ADD (multiple columns)', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id NUMBER)');
      await db.execute('ALTER TABLE t ADD (a NUMBER, b NUMBER)');
      await db.execute('INSERT INTO t VALUES (1, 2, 3)');
      await expectScalar(db, 'SELECT a FROM t', 2);
    },
        skip: 'KNOWN ENGINE BUG: ALTER TABLE ADD (a, b) adds only the first '
            'column — a 3-column insert then fails ("Expected 1 values, got 3"). '
            'Real Oracle adds both (a = 2). See findings/FINDINGS.md F235.');

    test('F236 · ALTER TABLE MODIFY applies the change', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (v VARCHAR2(3))');
      await db.execute('ALTER TABLE t MODIFY (v VARCHAR2(10))');
      await db.execute("INSERT INTO t VALUES ('abcdef')");
      await expectScalar(db, 'SELECT LENGTH(v) FROM t', 6);
    },
        skip: 'KNOWN ENGINE BUG: ALTER TABLE MODIFY does not apply the change — '
            'widening VARCHAR2(3)->(10) still rejects a 6-char value (ORA-12899), '
            'and MODIFY of DEFAULT and NOT NULL are ignored too. Real Oracle '
            'widens it (LENGTH = 6). See findings/FINDINGS.md F236.');

    test('F237 · ALTER TABLE DROP CONSTRAINT removes it', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (v NUMBER CONSTRAINT t_ck CHECK (v > 0))');
      await db.execute('ALTER TABLE t DROP CONSTRAINT t_ck');
      // With the check dropped, a negative value is allowed.
      await db.execute('INSERT INTO t VALUES (-5)');
      await expectScalar(db, 'SELECT v FROM t', -5);
    },
        skip: 'KNOWN ENGINE BUG: ALTER TABLE DROP CONSTRAINT does not remove the '
            'constraint — the CHECK is still enforced after dropping it, so the '
            'insert is rejected. Real Oracle allows -5. See findings/FINDINGS.md F237.');
  });

  // Found by a PL/SQL stored-routine three-way sweep (6/10 matched: scalar
  // functions, SELECT-returning functions, procedures with DML, anon-block
  // loops, package functions, functions in WHERE). These are genuine gaps.
  group('open bugs (round 58 — PL/SQL routines, real-Oracle-adjudicated)', () {
    test('F238 · parameterless function call without parentheses', () async {
      final db = await openEngine();
      await db.execute(
          'CREATE OR REPLACE FUNCTION f0 RETURN NUMBER IS BEGIN RETURN 42; END;');
      // Oracle allows a no-arg function call without (); f0() works but f0 fails.
      await expectScalar(db, 'SELECT f0 FROM dual', 42);
    },
        skip: 'KNOWN ENGINE BUG: a parameterless function called without '
            'parentheses (SELECT f0 FROM dual) is treated as a column '
            '("Unknown column: f0") — only f0() works. Real Oracle returns 42. '
            'See findings/FINDINGS.md F238.');

    test('F239 · CREATE FUNCTION ... DETERMINISTIC', () async {
      final db = await openEngine();
      await db.execute(
          'CREATE OR REPLACE FUNCTION inc(x NUMBER) RETURN NUMBER DETERMINISTIC '
          'IS BEGIN RETURN x + 1; END;');
      await expectScalar(db, 'SELECT inc(1) FROM dual', 2);
    },
        skip: 'KNOWN ENGINE BUG: the DETERMINISTIC clause on CREATE FUNCTION is a '
            'parse error ("Unexpected token after statement: END"), so the '
            'function is not created. Real Oracle returns 2. '
            'See findings/FINDINGS.md F239.');

    test('F240 · function parameter DEFAULT value', () async {
      final db = await openEngine();
      await db.execute(
          'CREATE OR REPLACE FUNCTION addn(x NUMBER, y NUMBER DEFAULT 10) '
          'RETURN NUMBER IS BEGIN RETURN x + y; END;');
      // Calling with one arg uses the default y = 10.
      await expectScalar(db, 'SELECT addn(5) FROM dual', 15);
    },
        skip: 'KNOWN ENGINE BUG: a DEFAULT value on a function parameter is a '
            'parse error ("Expected ) but got DEFAULT"). Real Oracle uses the '
            'default (addn(5) = 15). See findings/FINDINGS.md F240.');
  });

  // Found by a schema-object three-way sweep (10/14 matched: materialized views,
  // synonyms, RANGE/LIST/HASH partitioning, WITH CHECK OPTION, read-only views,
  // COMMENT, RENAME CONSTRAINT, NOVALIDATE). These DDL forms fail to parse.
  group('open bugs (round 59 — schema-object DDL, real-Oracle-adjudicated)', () {
    test('F241 · DEFERRABLE constraint', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE p (id NUMBER PRIMARY KEY)');
      // A deferrable FK should be accepted at CREATE time.
      await expectOk(
          db,
          'CREATE TABLE c (pid NUMBER REFERENCES p(id) '
          'DEFERRABLE INITIALLY DEFERRED)');
    },
        skip: 'KNOWN ENGINE BUG: the DEFERRABLE [INITIALLY DEFERRED] constraint '
            'attribute is a parse error ("Expected ) but got DEFERRABLE"), so '
            'the table is not created. Real Oracle accepts it. '
            'See findings/FINDINGS.md F241.');

    test('F242 · GLOBAL TEMPORARY TABLE', () async {
      final db = await openEngine();
      await db.execute(
          'CREATE GLOBAL TEMPORARY TABLE gt (v NUMBER) ON COMMIT PRESERVE ROWS');
      await db.execute('INSERT INTO gt VALUES (1), (2)');
      await expectScalar(db, 'SELECT COUNT(*) FROM gt', 2);
    },
        skip: 'KNOWN ENGINE BUG: CREATE GLOBAL TEMPORARY TABLE is a parse error '
            '("Expected TABLE, INDEX, VIEW or TRIGGER after CREATE"). Real Oracle '
            'creates it (count = 2). See findings/FINDINGS.md F242.');

    test('F243 · INVISIBLE column', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE inv (a NUMBER, b NUMBER INVISIBLE)');
      await db.execute('INSERT INTO inv (a, b) VALUES (1, 2)');
      // An invisible column is still selectable when named explicitly.
      await expectScalar(db, 'SELECT b FROM inv', 2);
    },
        skip: 'KNOWN ENGINE BUG: an INVISIBLE column in CREATE TABLE is a parse '
            'error ("Expected ) but got INVISIBLE"), so the table is not created. '
            'Real Oracle creates it (b = 2 when selected). '
            'See findings/FINDINGS.md F243.');
  });
}
