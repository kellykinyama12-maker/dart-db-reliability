// D8 (Oracle) — Oracle TTC/TNS wire-protocol round-trip fidelity.
//
// Drives the engine's Oracle wire server (OracleServer) with the vendored
// thin-client helpers in test/support/oracle_support.dart (the same client-side
// TNS framing + O5LOGON + TTC EXECUTE codecs the engine's own suite uses). This
// exercises a code path the SQL differential suite never touches: the Oracle
// TTC column encoder (notably Oracle's base-100 NUMBER format) and the bind
// decoder.
//
// Two directions are checked:
//   * READ  — insert via the engine API, SELECT back over the Oracle wire, and
//             assert the TTC-decoded value is correct.
//   * BIND  — INSERT over the wire with bound parameters, read back via the
//             engine API, and assert the stored value is correct.
import 'dart:io';

import 'package:dart_db_server/dart_db_server.dart';
import 'package:test/test.dart';

import '../support/oracle_support.dart';

void main() {
  group('D8(Oracle) · TTC wire round-trip', () {
    late Database db;
    late OracleServer server;
    late Socket socket;
    late FrameReader frames;

    setUp(() async {
      db = await Database.open(null);
      server = OracleServer(db, port: 0, users: {'app': 'secret'});
      await server.start();
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        server.boundPort,
      );
      frames = FrameReader(socket);
      await handshakeAndLogin(socket, frames,
          username: 'app', password: 'secret');
    });

    tearDown(() async {
      await socket.close();
      await server.stop();
    });

    // Runs one EXECUTE over the wire and reassembles the response.
    Future<ExecuteResponse> wireExec(String sql,
        {bool isQuery = false, List<Object?> binds = const []}) async {
      socket.add(wrapData(
          buildExecuteRequest(sql, isQuery: isQuery, binds: binds)));
      return readExecuteResponse(frames, isQuery: isQuery);
    }

    // ---- READ path: engine value must survive the TTC column encoder -------
    final readCases = <String, (String column, String insert, Object? expect)>{
      'small int': ('INTEGER', '42', 42),
      'negative int': ('INTEGER', '-7', -7),
      'zero': ('INTEGER', '0', 0),
      'large int': ('INTEGER', '1234567890123', 1234567890123),
      'simple double': ('REAL', '3.5', 3.5),
      'negative double': ('REAL', '-2.25', -2.25),
      'small fraction': ('REAL', '0.001', 0.001),
      'small text': ('TEXT', "'hello'", 'hello'),
      'empty text': ('TEXT', "''", null),
      'unicode text': ('TEXT', "'café ☕ 日本'", 'café ☕ 日本'),
      'text with quote': ('TEXT', "'O''Brien'", "O'Brien"),
      'null value': ('INTEGER', 'NULL', null),
    };

    readCases.forEach((name, spec) {
      final (column, insert, want) = spec;
      test('read · $name survives the TTC encoder', () async {
        await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v $column)');
        await db.execute('INSERT INTO t VALUES (1, $insert)');

        final r = await wireExec('SELECT v FROM t WHERE id = 1', isQuery: true);
        expect(r.errorNum, 0, reason: 'wire SELECT errored for $name');
        expect(r.rows.length, 1, reason: 'expected one row for $name');
        expect(r.rows.first.first, want,
            reason: 'TTC encoder mangled $name');
      });
    });

    // ---- BIND path: bound parameter must survive the TTC bind decoder ------
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
      test('bind · $name survives the TTC bind decoder', () async {
        await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v $column)');
        final r = await wireExec('INSERT INTO t VALUES (1, :1)', binds: [bind]);
        expect(r.errorNum, 0, reason: 'wire INSERT bind errored for $name');

        final back = await db.execute('SELECT v FROM t WHERE id = 1');
        expect(back.rows.first[0], want, reason: 'bind decoder mangled $name');
      });
    });

    // ---- Multi-column / ordering fidelity -------------------------------
    test('read · multi-column row preserves column order and names', () async {
      await db.execute('CREATE TABLE t (a INTEGER, b TEXT, c REAL)');
      await db.execute("INSERT INTO t VALUES (1, 'x', 2.5)");
      final r = await wireExec('SELECT a, b, c FROM t', isQuery: true);
      expect(r.errorNum, 0);
      expect(r.columns.map((e) => e.toLowerCase()).toList(), ['a', 'b', 'c']);
      expect(r.rows.first, [1, 'x', 2.5]);
    });

    test('read · row order is preserved across the wire', () async {
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)');
      await db.execute("INSERT INTO t VALUES (1,'a'),(2,'b'),(3,'c')");
      final r = await wireExec('SELECT v FROM t ORDER BY id', isQuery: true);
      expect(r.rows.map((e) => e.first).toList(), ['a', 'b', 'c']);
    });
  });
}
