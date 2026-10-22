// D8 (Oracle) — Oracle native (thick) client round-trip fidelity.
//
// Drives the engine's Oracle wire server (OracleServer) with the engine's own
// exported pure-Dart native thick client (OracleThickClient): native CONNECT +
// O5LOGON/PBKDF2 auth and OALL8 EXECUTE/FETCH round-trips. This exercises a
// code path the SQL differential suite never touches: the Oracle TTC column
// encoder (Oracle's base-100 NUMBER + VARCHAR2) and the bind encoder.
//
// Two directions are checked:
//   * READ  — insert via the engine API, SELECT back over the native client,
//             and assert the decoded value is correct.
//   * BIND  — INSERT over the native client with bound parameters, read back
//             via the engine API, and assert the stored value is correct.
import 'package:dart_db_server/dart_db_server.dart';
import 'package:dart_db_server/oracle_thick_client.dart';
import 'package:test/test.dart';

void main() {
  group('D8(Oracle) · native thick-client round-trip', () {
    late Database db;
    late OracleServer server;
    late OracleThickClient client;

    setUp(() async {
      db = await Database.open(null);
      server = OracleServer(db, port: 0);
      await server.start();
      server.userStore.addPbkdf2User('app', 'Secret123');
      client = await OracleThickClient.connect(server.boundPort);
      final login = await client.login(username: 'app', password: 'Secret123');
      expect(login.authenticated, isTrue, reason: 'native login should succeed');
    });

    tearDown(() async {
      await client.close();
      await server.stop();
    });

    // ---- READ path: engine value must survive the TTC column encoder -------
    // The thick client decodes NUMBER -> num and VARCHAR2 -> String, so a
    // whole-valued REAL may arrive as an int; numeric comparisons below use
    // closeTo to stay agnostic to the int/double representation.
    final readCases = <String, (String column, String insert, Object? expect)>{
      'small int': ('INTEGER', '42', 42),
      'negative int': ('INTEGER', '-7', -7),
      'zero': ('INTEGER', '0', 0),
      'large int': ('INTEGER', '1234567890123', 1234567890123),
      'simple double': ('REAL', '3.5', 3.5),
      'negative double': ('REAL', '-2.25', -2.25),
      'small fraction': ('REAL', '0.001', 0.001),
      'high-precision double': ('REAL', '3.141592653589793', 3.141592653589793),
      'small text': ('TEXT', "'hello'", 'hello'),
      'unicode text': ('TEXT', "'café ☕ 日本'", 'café ☕ 日本'),
      'text with quote': ('TEXT', "'O''Brien'", "O'Brien"),
      'null value': ('INTEGER', 'NULL', null),
    };

    readCases.forEach((name, spec) {
      final (column, insert, want) = spec;
      test('read · $name survives the TTC encoder', () async {
        await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v $column)');
        await db.execute('INSERT INTO t VALUES (1, $insert)');

        final r = await client.query('SELECT v FROM t WHERE id = 1');
        expect(r.rows.length, 1, reason: 'expected one row for $name');
        final got = r.rows.first.first;
        if (want is num && got is num) {
          expect(got, closeTo(want.toDouble(), 1e-12),
              reason: 'TTC encoder mangled $name');
        } else {
          expect(got, want, reason: 'TTC encoder mangled $name');
        }
      });
    });

    // ---- BIND path: bound parameter must survive the TTC bind encoder ------
    final bindCases = <String, (String column, Object? bind, Object? expect)>{
      'int bind': ('INTEGER', 42, 42),
      'negative int bind': ('INTEGER', -7, -7),
      'large int bind': ('INTEGER', 1234567890123, 1234567890123),
      'double bind': ('REAL', 3.5, 3.5),
      'text bind': ('TEXT', 'hello', 'hello'),
      'unicode bind': ('TEXT', 'café ☕ 日本', 'café ☕ 日本'),
    };

    bindCases.forEach((name, spec) {
      final (column, bind, want) = spec;
      test('bind · $name survives the TTC bind encoder', () async {
        await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v $column)');
        final affected =
            await client.execute('INSERT INTO t VALUES (1, :1)', binds: [bind]);
        expect(affected, 1, reason: 'wire INSERT bind failed for $name');

        final back = await db.execute('SELECT v FROM t WHERE id = 1');
        expect(back.rows.first[0], want, reason: 'bind encoder mangled $name');
      });
    });

    // ---- Bound query filter ---------------------------------------------
    test('bind · a bound query filters on the supplied value', () async {
      await db.execute('CREATE TABLE p (id INTEGER PRIMARY KEY, v INTEGER)');
      await db.execute('INSERT INTO p VALUES (1,10),(2,20),(3,30)');
      final r = await client
          .query('SELECT id FROM p WHERE v > :min ORDER BY id', binds: [15]);
      expect(r.rows, [
        [2],
        [3],
      ]);
    });

    // ---- Multi-column / ordering fidelity -------------------------------
    test('read · multi-column row preserves column order and names', () async {
      await db.execute('CREATE TABLE t (a INTEGER, b TEXT, c REAL)');
      await db.execute("INSERT INTO t VALUES (1, 'x', 2.5)");
      final r = await client.query('SELECT a, b, c FROM t');
      expect(r.columns.map((e) => e.toLowerCase()).toList(), ['a', 'b', 'c']);
      expect(r.rows.first, [1, 'x', 2.5]);
    });

    test('read · row order is preserved across the wire', () async {
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)');
      await db.execute("INSERT INTO t VALUES (1,'a'),(2,'b'),(3,'c')");
      final r = await client.query('SELECT v FROM t ORDER BY id');
      expect(r.rows.map((e) => e.first).toList(), ['a', 'b', 'c']);
    });

    // ---- FETCH pagination past one prefetch batch -----------------------
    test('read · a result larger than one fetch batch paginates correctly',
        () async {
      await db.execute('CREATE TABLE big (id INTEGER PRIMARY KEY)');
      const total = 250; // > native batch size (100): forces FETCH pagination
      final values = [for (var i = 1; i <= total; i++) '($i)'].join(',');
      await db.execute('INSERT INTO big VALUES $values');
      final r = await client.query('SELECT id FROM big ORDER BY id');
      expect(r.rows.length, total);
      expect(r.rows.first, [1]);
      expect(r.rows.last, [total]);
    });

    // ---- Error surfacing -------------------------------------------------
    test('a bad statement surfaces as an OracleThickException', () async {
      await expectLater(
        client.query('SELECT * FROM does_not_exist'),
        throwsA(isA<OracleThickException>()),
      );
    });

    // ---- FORMERLY-OPEN BUG F53 (fixed & verified) -----------------------
    // A column value larger than one SDU (~8KB) used not to be chunked across
    // TNS packets; now it round-trips. Uses a fresh client (the old failure
    // desynced the connection).
    test('F53 · a VARCHAR2 value larger than one SDU round-trips', () async {
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)');
      await db.execute("INSERT INTO t VALUES (1, '${'x' * 9000}')");
      final probe = await OracleThickClient.connect(server.boundPort);
      await probe.login(username: 'app', password: 'Secret123');
      try {
        final r = await probe.query('SELECT v FROM t WHERE id = 1');
        expect((r.rows.first.first as String).length, 9000);
      } finally {
        await probe.close();
      }
    });

    // ---- FORMERLY-OPEN BUG F54 (fixed & verified) -----------------------
    // A non-ASCII (multi-byte UTF-8) character in inbound SQL text used to be
    // mis-length-counted (char vs byte), corrupting the statement; now it is
    // decoded correctly.
    test('F54 · non-ASCII characters in inbound SQL round-trip', () async {
      final r = await client.query("SELECT 'héllo' AS v FROM dual");
      expect(r.rows, [
        ['héllo']
      ]);
    });
  });
}
