/// Copy-me template: a self-contained tour of the `dart_db_reliability` toolkit
/// that reproduces, in miniature, the same kinds of checks the `test/` suite
/// runs. Everything is driven through the single public import below.
///
/// Run it like any suite:
///
/// ```powershell
/// dart test example/reliability_toolkit_demo.dart
/// ```
///
/// The differential/fuzz cases skip automatically when the native `sqlite3`
/// library is absent; the real-Oracle case skips when php/oci8/Instant Client
/// is not installed.
@TestOn('vm')
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  // 1. Single-engine golden assertions (ACID/constraint/dialect style).
  group('engine assertions', () {
    test('scalar, rows, and constraint violations', () async {
      final db = await openEngine(); // fresh in-memory dart_db_server
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v INTEGER)');
      await db.execute('INSERT INTO t VALUES (1, 10), (2, 20)');
      await expectScalar(db, 'SELECT SUM(v) FROM t', 30);
      await expectRows(db, 'SELECT id, v FROM t ORDER BY id', [
        [1, 10],
        [2, 20],
      ]);
      await expectThrows(db, 'INSERT INTO t VALUES (1, 99)'); // PK violation
    });
  });

  // 2. Differential testing: same SQL on dart_db_server and SQLite; any
  //    divergence is a bug (or a documented dialect difference).
  group('differential vs SQLite', () {
    test('grouped aggregate matches SQLite', () async {
      final diff = await DiffOracle.open();
      try {
        await diff.exec(
            'CREATE TABLE s (id INTEGER PRIMARY KEY, g INTEGER, a REAL)');
        await diff.exec('INSERT INTO s VALUES (1,1,1.5),(2,1,2.5),(3,2,NULL)');
        // Always ORDER the verify query so row order is deterministic on both.
        await diff.expectSameRows(
            'SELECT g, COUNT(*), SUM(a) FROM s GROUP BY g ORDER BY g');
      } finally {
        diff.close();
      }
    }, skip: sqliteSkipReason());
  });

  // 3. Seeded fuzzing: random schema + rows + random SELECTs; both engines must
  //    agree. The seed makes any divergence reproduce exactly.
  group('seeded differential fuzz', () {
    for (final seed in [1, 2, 3]) {
      test('seed $seed · 50 random queries agree with SQLite', () async {
        final fuzz = SqlFuzzer(seed);
        final diff = await DiffOracle.open();
        try {
          for (final ddl in fuzz.schema()) {
            await diff.exec(ddl);
          }
          for (final ins in fuzz.rows(SqlFuzzer.tableA, 40)) {
            await diff.exec(ins);
          }
          for (final ins in fuzz.rows(SqlFuzzer.tableB, 40)) {
            await diff.exec(ins);
          }
          for (var i = 0; i < 50; i++) {
            // Compare row DATA; computed-column auto-naming legitimately
            // differs between engines, so don't assert on column labels here.
            await diff.expectSameRows(fuzz.query());
          }
        } finally {
          diff.close();
        }
      }, skip: sqliteSkipReason());
    }
  });

  // 4. Authored workload: a deterministic bulk dataset + a fixed query pool.
  group('authored workload', () {
    test('200 rows, fixed query pool matches SQLite', () async {
      final wl = Workload(42);
      final diff = await DiffOracle.open();
      try {
        await diff.exec(Workload.createTable);
        for (final ins in wl.inserts(200)) {
          await diff.exec(ins);
        }
        for (final q in wl.readQueries()) {
          await diff.expectSameRows(q);
        }
      } finally {
        diff.close();
      }
    }, skip: sqliteSkipReason());
  });

  // 5. Oracle SQL*Plus script loading: the splitter plays the role of the
  //    `sqlplus` client (strips directives, honors the `/` PL/SQL terminator)
  //    so a stock `.sql` script feeds the engine one statement at a time.
  group('Oracle SQL*Plus script splitter', () {
    test('splits directives + PL/SQL block and the engine runs each unit',
        () async {
      const script = '''
REM sample schema fragment
SET define off
CREATE TABLE emp (id NUMBER PRIMARY KEY, name VARCHAR2(20));
INSERT INTO emp VALUES (1, 'Ada');
CREATE OR REPLACE TRIGGER emp_bi BEFORE INSERT ON emp FOR EACH ROW
BEGIN
  :new.name := UPPER(:new.name);
END;
/
INSERT INTO emp VALUES (2, 'grace');
''';
      final units = splitOracleScript(script);
      // REM / SET directives are dropped; the PL/SQL block is one unit.
      expect(units, hasLength(4));
      final db = await openEngine();
      for (final stmt in units) {
        await expectOk(db, stmt);
      }
      await expectScalar(db, 'SELECT COUNT(*) FROM emp', 2);
    });
  });

  // 6. Real-Oracle triple-threat: compare the engine's Oracle wire output
  //    against the real `oci8` client. Skips cleanly when the client stack is
  //    not installed.
  group('real Oracle oci8 bridge (Gun 3)', () {
    test('bridge resolves when php/oci8/Instant Client are present', () async {
      final bridge = await Oci8Bridge.probe();
      if (bridge == null) {
        markTestSkipped('php/oci8/Instant Client absent');
        return;
      }
      // Stand up the engine's OracleServer on a port, then diff:
      //   final real = await bridge.run(port, [{'sql': '...', 'query': true}]);
      // against the engine's own result for the same SQL.
    });
  });
}
