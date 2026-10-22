/// Durability & recovery: write data, flush/close, reopen the same file, and
/// verify every row (and schema) survived. Exercises the persistence backends
/// end-to-end — the property that separates a database from a cache.
@Timeout(Duration(minutes: 1))
library;

import 'dart:io';

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('durability & recovery', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('ddb_rel_'));
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    Future<void> roundTrip(String fileName) async {
      final path = '${tmp.path}/$fileName';

      final db = await openEngine(path);
      await db.execute('CREATE TABLE acct (id INTEGER PRIMARY KEY, '
          'owner TEXT NOT NULL, balance REAL)');
      await db.execute("INSERT INTO acct VALUES "
          "(1,'ada',100.5),(2,'alan',250.0),(3,'grace',0.0)");
      await db.execute('CREATE INDEX idx_owner ON acct(owner)');
      await db.execute('UPDATE acct SET balance = balance + 10 WHERE id = 1');
      await db.flush();
      await db.close();

      final re = await openEngine(path);
      await expectRows(re, 'SELECT id, owner, balance FROM acct ORDER BY id', [
        [1, 'ada', 110.5],
        [2, 'alan', 250.0],
        [3, 'grace', 0.0],
      ], reason: 'rows must survive reopen of $fileName');
      // Index-backed lookup must still resolve after reload.
      await expectRows(re, "SELECT owner FROM acct WHERE owner = 'alan'", [
        ['alan'],
      ]);
      await re.close();
    }

    test('JSON backend persists and reloads', () => roundTrip('data.json'));

    test('SQLite-format backend persists and reloads',
        () => roundTrip('data.db'));

    test('transaction committed before close survives reopen', () async {
      final path = '${tmp.path}/txn.json';
      final db = await openEngine(path);
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v INTEGER)');
      await db.execute('BEGIN');
      await db.execute('INSERT INTO t VALUES (1, 10), (2, 20)');
      await db.execute('COMMIT');
      await db.flush();
      await db.close();

      final re = await openEngine(path);
      await expectRows(re, 'SELECT id, v FROM t ORDER BY id', [
        [1, 10],
        [2, 20],
      ]);
      await re.close();
    });
  });
}
