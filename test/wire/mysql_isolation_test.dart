// D4 — cross-connection transaction isolation (MySQL wire).
//
// Opens TWO independent client connections (A and B) to the SAME engine
// Database through the MySQL wire server and drives them in a deterministic,
// sequentially-awaited interleaving. These probe whether each connection gets
// its own transaction context.
//
// ROOT CAUSE (shared by F48–F51): the engine keeps transaction state
// (`_snapshot` / `inTransaction`) GLOBALLY on the one shared `Database`, not
// per session/connection, and the read/write lock is released after each
// statement rather than held for the whole transaction. So one connection's
// BEGIN/COMMIT/ROLLBACK affects every other connection. The single fix is to
// make transaction state per-connection; it is tracked as four separate
// client-visible symptoms below.
import 'package:dart_db_server/dart_db_server.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:test/test.dart';

void main() {
  group('D4 · cross-connection isolation', () {
    late Database db;
    late MySqlServer server;
    late MySQLConnection a;
    late MySQLConnection b;

    Future<MySQLConnection> connect() async {
      final c = await MySQLConnection.createConnection(
        host: '127.0.0.1',
        port: server.boundPort,
        userName: 'root',
        password: '',
        secure: false,
      );
      await c.connect();
      return c;
    }

    setUp(() async {
      db = await Database.open(null);
      server = MySqlServer(db, port: 0);
      await server.start();
      a = await connect();
      b = await connect();
      await a.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v INTEGER)');
      await a.execute('INSERT INTO t VALUES (1, 100)');
    });

    tearDown(() async {
      // Defensively end any transaction left open by a failing assertion.
      for (final c in [a, b]) {
        try {
          await c.execute('ROLLBACK');
        } catch (_) {}
      }
      await a.close();
      await b.close();
      await server.stop();
    });

    Future<int> countOn(MySQLConnection c) async {
      final r = await c.execute('SELECT COUNT(*) FROM t');
      return int.parse(r.rows.first.colAt(0)!);
    }

    test('F48 · uncommitted write from one connection is visible to another',
        () async {
      await a.execute('BEGIN');
      await a.execute('INSERT INTO t VALUES (2, 200)');
      // B is a separate connection; it must NOT see A's uncommitted row.
      expect(await countOn(b), 1);
      await a.execute('ROLLBACK');
    });

    test('F49 · one connection ROLLBACK discards another connection\'s '
        'committed write', () async {
      await a.execute('BEGIN');
      // B is in autocommit: this row must be durable immediately.
      await b.execute('INSERT INTO t VALUES (3, 300)');
      await a.execute('ROLLBACK');
      // A's rollback must not touch B's committed data.
      final r = await b.execute('SELECT v FROM t WHERE id = 3');
      expect(r.rows, isNotEmpty, reason: 'B committed row was lost');
    });

    test('F50 · one connection can COMMIT another connection\'s transaction',
        () async {
      await a.execute('BEGIN');
      await a.execute('INSERT INTO t VALUES (4, 400)');
      // B has no open transaction; its COMMIT must not commit A's work.
      await b.execute('COMMIT');
      await a.execute('ROLLBACK');
      // After A rolls back its own transaction, row 4 must be gone.
      final r = await a.execute('SELECT v FROM t WHERE id = 4');
      expect(r.rows, isEmpty,
          reason: 'B\'s COMMIT durably committed A\'s uncommitted row');
    });

    test('F51 · a second connection cannot open its own transaction', () async {
      await a.execute('BEGIN');
      // B must be able to run its own independent transaction.
      await b.execute('BEGIN');
      await b.execute('ROLLBACK');
      await a.execute('ROLLBACK');
    });
  });
}
