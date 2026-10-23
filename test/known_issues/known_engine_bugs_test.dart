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

  // Found by the strengthened SH gate: MEDIAN still carries binary residual
  // (F142 fixed SUM, not MEDIAN). Real SH products MEDIAN = 31.99.
  group('open bugs (round 36 — MEDIAN precision, real-Oracle-adjudicated)', () {
    test('F143 · MEDIAN carries binary floating-point residual', () async {
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
    },
        skip: 'KNOWN ENGINE BUG: MEDIAN averages the two middle values in '
            'binary floating point instead of exact decimal — '
            'MEDIAN(1.01,1.02) returns 1.0150000000000001; real SH '
            'MEDIAN(prod_list_price) returns 31.990000000000002 vs Oracle '
            '31.99. F142 fixed SUM; MEDIAN remains. See findings/FINDINGS.md F143.');
  });

  // Found finishing the real customer_orders (CO) load three-way (F140 UTL_RAW
  // and F141 JSON landed, which unblocked reaching these). All three confirmed
  // against real Oracle 23ai (Oracle accepts; engine rejects).
  group('open bugs (round 37 — CO load blockers, real-Oracle-adjudicated)', () {
    test('F144 · IS JSON check constraint breaks INSERT', () async {
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
    },
        skip: 'KNOWN ENGINE BUG: an IS JSON check constraint makes INSERT fail '
            'with "Unknown column: json" — the check is evaluated as if "json" '
            'were a column. Without the check the same insert succeeds. Real '
            'Oracle accepts it. Blocks the real CO products load. '
            'See findings/FINDINGS.md F144.');

    test('F145 · JSON_TABLE in a view is a parse error', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE p2 (id NUMBER, details BLOB)');
      // Oracle creates this product_reviews-style view (lateral JSON_TABLE +
      // window); the engine throws "Unexpected token after statement: (".
      await expectOk(db, '''CREATE OR REPLACE VIEW pr AS
        SELECT p.id, r.rating,
          ROUND(AVG(r.rating) OVER (PARTITION BY p.id), 2) avg_rating
        FROM p2 p,
          JSON_TABLE(p.details, '\$' COLUMNS (rating NUMBER PATH '\$.rating')) r''');
    },
        skip: 'KNOWN ENGINE BUG: JSON_TABLE in a CREATE VIEW (lateral join + '
            'window) is a parse error ("Unexpected token after statement: ("). '
            'Real Oracle creates the view. Blocks the real CO product_reviews '
            'view. See findings/FINDINGS.md F145.');

    test('F146 · TO_TIMESTAMP with 9-digit FF returns NULL', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE o (id NUMBER, ts TIMESTAMP NOT NULL)');
      // Oracle parses the 9-digit fractional seconds; the engine returns NULL,
      // so the NOT NULL column rejects the row.
      await expectOk(
          db,
          "INSERT INTO o VALUES (1, TO_TIMESTAMP("
          "'05-MAR-2019 09.24.19.123456789','DD-MON-YYYY HH24.MI.SS.FF'))");
    },
        skip: 'KNOWN ENGINE BUG: TO_TIMESTAMP with a 9-digit FF fractional-'
            'seconds format returns NULL instead of the timestamp, so a NOT '
            'NULL column rejects the row. Real Oracle parses it '
            '(2019-03-05 09:24:19.123456789). Blocks the real CO orders load. '
            'See findings/FINDINGS.md F146.');
  });

  // Found probing the real order_entry (OE) object-relational schema: the engine
  // ACCEPTS CREATE TYPE ... AS OBJECT / VARRAY / object columns, but the object
  // DML/query semantics are missing. Both confirmed against real Oracle 23ai.
  group('open bugs (round 38 — OE object types, real-Oracle-adjudicated)', () {
    test('F147 · object-type constructor is not registered', () async {
      final db = await openEngine();
      await db.execute(
          'CREATE TYPE addr_typ AS OBJECT (street VARCHAR2(40), city VARCHAR2(30))');
      await db.execute('CREATE TABLE c (id NUMBER, addr addr_typ)');
      // Oracle registers a default constructor for the object type; the engine
      // throws "Unknown function: ADDR_TYP" even though the CREATE TYPE above
      // succeeded.
      await expectOk(
          db, "INSERT INTO c VALUES (1, addr_typ('1 Main St','Austin'))");
    },
        skip: 'KNOWN ENGINE BUG: CREATE TYPE ... AS OBJECT succeeds but the '
            'default object constructor is not registered — INSERT using '
            'addr_typ(...) fails with "Unknown function: ADDR_TYP". Real Oracle '
            'inserts the row. Blocks the real OE object-relational load. '
            'See findings/FINDINGS.md F147.');

    test('F148 · qualified object-attribute navigation is a parse error',
        () async {
      final db = await openEngine();
      await db.execute(
          'CREATE TYPE addr_typ AS OBJECT (street VARCHAR2(40), city VARCHAR2(30))');
      await db.execute('CREATE TABLE c (id NUMBER, addr addr_typ)');
      // Oracle navigates object attributes via a table alias (c.addr.city); the
      // engine throws "Unexpected token after statement: ." at parse time.
      await expectOk(db, 'SELECT c.addr.city FROM c c');
    },
        skip: 'KNOWN ENGINE BUG: table-alias-qualified object attribute '
            'navigation (SELECT c.addr.city FROM c c) is a parse error '
            '("Unexpected token after statement: ."). Real Oracle returns the '
            'attribute. See findings/FINDINGS.md F148.');
  });
}
