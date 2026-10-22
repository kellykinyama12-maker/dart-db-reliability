/// Crash-recovery durability: spawn a worker that commits a durable baseline and
/// then churns writes, **hard-kill** it mid-write (SIGKILL-equivalent), reopen
/// the database, and assert it recovers consistently — the committed baseline
/// survives and the file is not corrupted. This is the property that separates a
/// database from a cache.
@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('crash recovery', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('ddb_crash_'));
    tearDown(() async {
      // The hard-killed worker may briefly retain file handles on Windows;
      // deletion is best-effort and must not fail the test.
      for (var attempt = 0; attempt < 5; attempt++) {
        try {
          if (tmp.existsSync()) tmp.deleteSync(recursive: true);
          return;
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
    });

    Future<void> crashAndRecover(String fileName, int committed) async {
      final path = '${tmp.path}/$fileName';
      final proc = await Process.start(
        Platform.resolvedExecutable,
        ['run', 'bin/durability_worker.dart', path, '$committed'],
      );

      // Wait for the worker to report its durable baseline is flushed.
      final ready = Completer<void>();
      proc.stdout
          .transform(const SystemEncoding().decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim() == 'READY' && !ready.isCompleted) ready.complete();
      });
      proc.stderr.drain<void>();
      await ready.future.timeout(const Duration(seconds: 60));

      // Let it churn a bit past the baseline, then HARD kill (no cleanup).
      await Future<void>.delayed(const Duration(milliseconds: 150));
      proc.kill(ProcessSignal.sigkill);
      await proc.exitCode;
      // Give the OS a moment to release the worker's file handles (Windows).
      await Future<void>.delayed(const Duration(milliseconds: 300));

      // Reopen: the committed baseline must be intact and queryable.
      final db = await openEngine(path);
      final count = await scalar(db, 'SELECT COUNT(*) FROM acct WHERE id <= $committed');
      final sum = await scalar(db, 'SELECT SUM(bal) FROM acct WHERE id <= $committed');
      expect(count, committed,
          reason: 'all $committed committed rows must survive a crash');
      expect(sum, committed * (committed + 1) * 100 ~/ 2,
          reason: 'committed balances must be intact (no torn writes)');
      await db.close();
    }

    test('JSON backend recovers committed baseline after SIGKILL',
        () => crashAndRecover('crash.json', 200));

    test('SQLite-format backend recovers committed baseline after SIGKILL',
        () => crashAndRecover('crash.db', 200));
  });
}
