// D8 — MySQL wire-protocol round-trip fidelity.
//
// Drives the engine's MySQL classic-protocol server end-to-end with the real,
// published `mysql_client` driver. This exercises a code path the differential
// suite never touches: the wire encoders/decoders (text COM_QUERY result rows,
// binary COM_STMT_EXECUTE result rows, and binary parameter encoding).
//
// Two directions are checked for every value:
//   * READ  — insert via the engine API, read back over BOTH the text and the
//             binary protocol; the two must agree and must be correct.
//   * WRITE — insert over the binary protocol (bound parameters), read back via
//             the engine API; the stored value must be correct.
//
// A value that survives the engine's SQL executor but is mangled on the wire is
// still a client-visible bug, so this suite treats any wire divergence as a
// failure.
import 'package:dart_db_server/dart_db_server.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:test/test.dart';

void main() {
  group('D8 · MySQL wire round-trip', () {
    late Database db;
    late MySqlServer server;
    late MySQLConnection conn;

    setUp(() async {
      db = await Database.open(null);
      server = MySqlServer(db, port: 0);
      await server.start();
      conn = await MySQLConnection.createConnection(
        host: '127.0.0.1',
        port: server.boundPort,
        userName: 'root',
        password: '',
        secure: false,
      );
      await conn.connect();
    });

    tearDown(() async {
      await conn.close();
      await server.stop();
    });

    // Reads the single scalar in `SELECT <expr>` via the text protocol.
    Future<String?> textScalar(String sql) async {
      final r = await conn.execute(sql);
      return r.rows.first.colAt(0);
    }

    // Reads `SELECT v FROM t WHERE id = ?` via the binary protocol. A bound
    // parameter is used deliberately: a prepared statement with *zero*
    // parameters hangs the engine (tracked as F46), so the binary read path is
    // exercised with a placeholder.
    Future<String?> binaryScalar() async {
      final stmt = await conn.prepare('SELECT v FROM t WHERE id = ?');
      final r = await stmt.execute([1]);
      final rows = r.rows.toList();
      final v = rows.isEmpty ? null : rows.first.colAt(0);
      await stmt.deallocate();
      return v;
    }

    // ---- READ path: engine value must survive both wire encoders ----------
    //
    // Each case stores one value through the engine API, then reads column `v`
    // back over the text and binary protocols. Both renderings must equal the
    // expected client-visible string.
    final readCases = <String, (String column, String insert, String? expect)>{
      'small int': ('INTEGER', '42', '42'),
      'negative int': ('INTEGER', '-7', '-7'),
      'zero': ('INTEGER', '0', '0'),
      'int64 max': (
        'INTEGER',
        '9223372036854775807',
        '9223372036854775807'
      ),
      'simple double': ('REAL', '3.5', '3.5'),
      'negative double': ('REAL', '-2.25', '-2.25'),
      'small text': ('TEXT', "'hello'", 'hello'),
      'empty text': ('TEXT', "''", ''),
      'unicode text': ('TEXT', "'café ☕ 日本'", 'café ☕ 日本'),
      'text with quote': ('TEXT', "'O''Brien'", "O'Brien"),
      'text with newline': ('TEXT', "'a' || char(10) || 'b'", 'a\nb'),
      'null value': ('INTEGER', 'NULL', null),
    };

    readCases.forEach((name, spec) {
      final (column, insert, want) = spec;
      test('read · $name survives text and binary encoders', () async {
        await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v $column)');
        await db.execute('INSERT INTO t VALUES (1, $insert)');

        final viaText = await textScalar('SELECT v FROM t WHERE id = 1');
        final viaBinary = await binaryScalar();

        expect(viaText, want, reason: 'text protocol mangled $name');
        expect(viaBinary, want, reason: 'binary protocol mangled $name');
        expect(viaText, viaBinary,
            reason: 'text and binary encoders disagree for $name');
      });
    });

    // ---- WRITE path: bound parameter must survive the binary encoder -------
    //
    // Each case binds one parameter through a prepared INSERT, then reads the
    // stored value back via the engine API. The engine value must match.
    final writeCases = <String, (String column, Object? param, Object expect)>{
      'int param': ('INTEGER', 42, 42),
      'negative int param': ('INTEGER', -7, -7),
      'big int param': (
        'INTEGER',
        9223372036854775807,
        9223372036854775807
      ),
      'double param': ('REAL', 3.5, 3.5),
      'text param': ('TEXT', 'hello', 'hello'),
      'empty text param': ('TEXT', '', ''),
      'unicode param': ('TEXT', 'café ☕ 日本', 'café ☕ 日本'),
      'quote param': ('TEXT', "O'Brien", "O'Brien"),
    };

    writeCases.forEach((name, spec) {
      final (column, param, want) = spec;
      test('write · $name survives binary param encoder', () async {
        await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v $column)');

        final stmt = await conn.prepare('INSERT INTO t VALUES (1, ?)');
        await stmt.execute([param]);
        await stmt.deallocate();

        final r = await db.execute('SELECT v FROM t WHERE id = 1');
        expect(r.rows.first[0], want, reason: 'binary param encoder mangled $name');
      });
    });

    // ---- NULL bound parameter -------------------------------------------
    test('write · NULL param survives binary param encoder', () async {
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v INTEGER)');
      final stmt = await conn.prepare('INSERT INTO t VALUES (1, ?)');
      await stmt.execute([null]);
      await stmt.deallocate();
      final r = await db.execute('SELECT v FROM t WHERE id = 1');
      expect(r.rows.first[0], isNull);
    });

    // ---- Column metadata fidelity ---------------------------------------
    test('read · multi-column result preserves column order and names',
        () async {
      await db.execute('CREATE TABLE t (a INTEGER, b TEXT, c REAL)');
      await db.execute("INSERT INTO t VALUES (1, 'x', 2.5)");
      final r = await conn.execute('SELECT a, b, c FROM t');
      final cols = r.cols.map((c) => c.name).toList();
      expect(cols, ['a', 'b', 'c']);
      final row = r.rows.first;
      expect([row.colAt(0), row.colAt(1), row.colAt(2)], ['1', 'x', '2.5']);
    });

    // ---- Multi-row ordering fidelity ------------------------------------
    test('read · row order is preserved across the wire', () async {
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)');
      await db.execute("INSERT INTO t VALUES (1,'a'),(2,'b'),(3,'c')");
      final r = await conn.execute('SELECT v FROM t ORDER BY id');
      expect(r.rows.map((e) => e.colAt(0)).toList(), ['a', 'b', 'c']);
    });

    // ---- KNOWN ENGINE BUG F46 -------------------------------------------
    // A prepared statement with zero parameter markers hangs the connection:
    // COM_STMT_PREPARE never returns its response, so `conn.prepare` never
    // completes. A parameterised prepare (`WHERE id = ?`) works fine, so the
    // whole suite above binds a placeholder to avoid the hang. ORMs routinely
    // prepare parameterless statements (`SELECT COUNT(*) FROM t`), so this
    // would freeze real clients. The guard times out fast instead of hanging.
    test('F46 · prepared statement with no parameters hangs the connection',
        () async {
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v INTEGER)');
      await db.execute('INSERT INTO t VALUES (1, 42)');
      final stmt = await conn
          .prepare('SELECT v FROM t WHERE id = 1')
          .timeout(const Duration(seconds: 5));
      await stmt.execute([]);
      await stmt.deallocate();
    });
  });
}
