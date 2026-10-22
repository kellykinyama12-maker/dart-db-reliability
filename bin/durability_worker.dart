/// Durability worker: opens a DB at the given path, writes a committed baseline,
/// then enters an infinite insert loop (flushing) so the parent can hard-kill it
/// mid-write. Invoked as a subprocess by crash_recovery_test.dart.
///
/// Usage: `dart run bin/durability_worker.dart PATH COMMITTED_ROWS`
library;

import 'package:dart_db_server/dart_db_server.dart';

Future<void> main(List<String> args) async {
  final path = args[0];
  final committed = int.parse(args[1]);

  final db = await Database.open(path);
  await db.execute('CREATE TABLE acct (id INTEGER PRIMARY KEY, bal INTEGER)');

  // Durable baseline inside an explicit transaction, then flush to disk.
  await db.execute('BEGIN');
  for (var i = 1; i <= committed; i++) {
    await db.execute('INSERT INTO acct VALUES ($i, ${i * 100})');
  }
  await db.execute('COMMIT');
  await db.flush();

  // Signal readiness so the parent knows the baseline is durable.
  // ignore: avoid_print
  print('READY');

  // Churn forever: continuous writes + flushes until the process is killed.
  var next = committed + 1;
  while (true) {
    await db.execute('INSERT INTO acct VALUES ($next, ${next * 100})');
    if (next % 50 == 0) await db.flush();
    next++;
  }
}
