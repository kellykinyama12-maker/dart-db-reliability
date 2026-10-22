/// Concurrency integrity at the engine API: many in-flight `execute` futures
/// race on the single event loop. The engine must serialize them internally so
/// no write is lost and no row is corrupted. (True cross-connection isolation
/// is a wire-server property, covered by dart_db_server's own suites; here we
/// pin down single-engine concurrent-mutation safety.)
@Timeout(Duration(minutes: 1))
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('concurrent-mutation integrity', () {
    test('200 concurrent inserts all land, PKs unique', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v INTEGER)');
      await Future.wait([
        for (var i = 1; i <= 200; i++)
          db.execute('INSERT INTO t VALUES ($i, ${i * 2})'),
      ]);
      await expectScalar(db, 'SELECT COUNT(*) FROM t', 200);
      await expectScalar(db, 'SELECT COUNT(DISTINCT id) FROM t', 200);
      await expectScalar(db, 'SELECT SUM(v) FROM t', 200 * 201); // 2*(1..200)
    });

    test('concurrent increments do not lose updates', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE c (id INTEGER PRIMARY KEY, n INTEGER)');
      await db.execute('INSERT INTO c VALUES (1, 0)');
      await Future.wait([
        for (var i = 0; i < 100; i++)
          db.execute('UPDATE c SET n = n + 1 WHERE id = 1'),
      ]);
      await expectScalar(db, 'SELECT n FROM c WHERE id = 1', 100,
          reason: 'all 100 increments must be reflected (no lost updates)');
    });

    test('concurrent deletes and inserts keep a consistent count', () async {
      final db = await openEngine();
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY)');
      for (var i = 1; i <= 100; i++) {
        await db.execute('INSERT INTO t VALUES ($i)');
      }
      await Future.wait([
        for (var i = 1; i <= 50; i++) db.execute('DELETE FROM t WHERE id = $i'),
        for (var i = 101; i <= 150; i++) db.execute('INSERT INTO t VALUES ($i)'),
      ]);
      await expectScalar(db, 'SELECT COUNT(*) FROM t', 100);
      await expectScalar(db, 'SELECT MIN(id) FROM t', 51);
      await expectScalar(db, 'SELECT MAX(id) FROM t', 150);
    });
  });
}
