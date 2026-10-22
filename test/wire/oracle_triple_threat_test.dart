// Oracle triple-threat match (per doc/oracle-triple-threat-testing.md, with the
// thin client dropped per request).
//
// Three Oracle participants adjudicate every case against each other:
//   Gun A — the server emulator itself (`Database.execute`), the ground truth
//           of what the engine computed.
//   Gun 2 — the pure-Dart thick client (`OracleThickClient`) over the Oracle
//           wire.
//   Gun 3 — the real Oracle thick client (`oci8` + Instant Client) over the
//           same wire, via the PHP bridge. Auto-skipped when unavailable.
//
// A bug has to fool all present guns to pass: Gun 2 ≠ Gun A is a pure-Dart
// client/codec bug; Gun 3 ≠ Gun A is a wire bug real Oracle catches that the
// Dart clients tolerate.
import 'package:dart_db_reliability/reliability.dart';
import 'package:dart_db_server/dart_db_server.dart';
import 'package:dart_db_server/oracle_thick_client.dart';
import 'package:test/test.dart';

void main() {
  group('Oracle triple-threat match', () {
    late Database db;
    late OracleServer server;
    late OracleThickClient thick;
    Oci8Bridge? oci8; // null => Gun 3 (real Instant Client) unavailable

    setUpAll(() async {
      oci8 = await Oci8Bridge.probe();
      // ignore: avoid_print
      print(oci8 == null
          ? 'Gun 3 (real oci8) UNAVAILABLE — matching Gun A vs Gun 2 only'
          : 'Gun 3 (real oci8) ACTIVE — three-way match');
    });

    setUp(() async {
      db = await Database.open(null);
      server = OracleServer(db, port: 0);
      await server.start();
      server.userStore.addPbkdf2User('native', 'Secret123');
      thick = await OracleThickClient.connect(server.boundPort);
      await thick.login(username: 'native', password: 'Secret123');
    });

    tearDown(() async {
      await thick.close();
      await server.stop();
    });

    // Canonical token for a normalized cell so num/int/String/null line up
    // across all three clients.
    String tok(Object? v) {
      final n = normalizeValue(v);
      if (n == null) return '∅';
      if (n is List) return n.join(',');
      return '$n';
    }

    String render(List<List<Object?>> rows) =>
        rows.map((r) => r.map(tok).join('\u0001')).join('\u0002');

    // Substitutes positional binds into :name placeholders for the emulator,
    // which takes literal SQL (no positional bind API).
    String lit(String sql, List<Object?> binds) {
      if (binds.isEmpty) return sql;
      final names = <String>[];
      for (final m in RegExp(r':(\w+)').allMatches(sql)) {
        if (!names.contains(m.group(1))) names.add(m.group(1)!);
      }
      var out = sql;
      for (var i = 0; i < names.length && i < binds.length; i++) {
        final v = binds[i];
        final l = v is String ? "'${v.replaceAll("'", "''")}'" : '$v';
        out = out.replaceAll(':${names[i]}', l);
      }
      return out;
    }

    Future<void> threeWay(
      String name,
      String probe, {
      List<Object?> binds = const [],
    }) async {
      // Gun A — emulator ground truth.
      final gunA = render((await db.execute(lit(probe, binds))).rows);

      // Gun 2 — pure-Dart thick client.
      final gun2 = render((await thick.query(probe, binds: binds)).rows);
      expect(gun2, gunA,
          reason: 'Gun 2 (pure-Dart thick) diverges from the emulator for $name');

      // Gun 3 — real oci8 (if present).
      if (oci8 != null) {
        final r = await oci8!.run(server.boundPort, [
          {'sql': probe, 'binds': binds, 'query': true}
        ]);
        expect(r.single.ok, isTrue,
            reason: 'Gun 3 (real oci8) errored for $name: ${r.single.error}');
        final gun3 = render(r.single.rows);
        expect(gun3, gunA,
            reason: 'Gun 3 (real oci8) diverges from the emulator for $name');
      }
    }

    // Each test seeds the shared Database once (all guns see it), then probes
    // several SELECTs every gun runs. Empty strings are avoided (Oracle maps
    // '' -> NULL, dialect D7), as are values > int64 / > one SDU (F52/F53).
    test('scalar + NUMBER + VARCHAR2 values', () async {
      await db.execute(
          'CREATE TABLE t (id INTEGER PRIMARY KEY, n REAL, s VARCHAR2(40))');
      await db.execute("INSERT INTO t VALUES "
          "(1, 42, 'a'),(2, -7, 'a'),(3, 0.125, 'a'),(4, 1.0/3.0, NULL),"
          "(5, 123456789012345, NULL),(6, 0, 'O''Brien'),(7, 0, 'café ☕ 日本'),"
          "(8, NULL, 'x')");
      await threeWay('int', 'SELECT n FROM t WHERE id = 1');
      await threeWay('negative', 'SELECT n FROM t WHERE id = 2');
      await threeWay('fraction', 'SELECT n FROM t WHERE id = 3');
      await threeWay('third', 'SELECT n FROM t WHERE id = 4');
      await threeWay('big-but-in-range', 'SELECT n FROM t WHERE id = 5');
      await threeWay('text', 'SELECT s FROM t WHERE id = 6');
      await threeWay('unicode', 'SELECT s FROM t WHERE id = 7');
      await threeWay('null number', 'SELECT n FROM t WHERE id = 8');
    });

    test('multi-row ordering + mixed NULL rows', () async {
      await db.execute(
          'CREATE TABLE t (id INTEGER PRIMARY KEY, n REAL, s VARCHAR2(40))');
      await db.execute(
          "INSERT INTO t VALUES (1, 10, 'a'),(2, 20, NULL),(3, 30, 'c')");
      await threeWay('order asc', 'SELECT id, n, s FROM t ORDER BY id');
      await threeWay('order desc n', 'SELECT n FROM t ORDER BY n DESC');
    });

    test('aggregates + expressions + dual', () async {
      await db.execute('CREATE TABLE g (id INTEGER PRIMARY KEY, v INTEGER)');
      await db.execute('INSERT INTO g VALUES (1,10),(2,20),(3,NULL),(4,30)');
      await threeWay('count star', 'SELECT COUNT(*) FROM g');
      await threeWay('count v', 'SELECT COUNT(v) FROM g');
      await threeWay('sum', 'SELECT SUM(v) FROM g');
      await threeWay('avg', 'SELECT AVG(v) FROM g');
      await threeWay('min', 'SELECT MIN(v) FROM g');
      await threeWay('distinct', 'SELECT DISTINCT v FROM g ORDER BY v');
      await threeWay('case',
          'SELECT CASE WHEN v IS NULL THEN -1 ELSE v END FROM g ORDER BY id');
      await threeWay('dual expr', 'SELECT 6 * 7 AS answer FROM dual');
    });

    test('bound queries match three ways', () async {
      await db.execute('CREATE TABLE p (id INTEGER PRIMARY KEY, v INTEGER)');
      await db.execute('INSERT INTO p VALUES (1,10),(2,20),(3,30)');
      await threeWay('bound filter',
          'SELECT id FROM p WHERE v > :min ORDER BY id',
          binds: [15]);
      await threeWay('reused bind', 'SELECT :x + :x AS d FROM dual',
          binds: [21]);
    });
  });
}
