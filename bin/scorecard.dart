/// Reliability scorecard: runs the test suite via `dart test --reporter json`
/// and prints a dimension-by-dimension pass / skip / fail summary plus the
/// certification-bar status. Reporting is first-class — this is the single
/// command to answer "where does the engine stand?".
///
/// Usage: dart run bin/scorecard.dart
library;

import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final proc = await Process.start(
    Platform.resolvedExecutable,
    ['test', '--reporter', 'json'],
    runInShell: true,
  );

  final tests = <int, _T>{};
  final suites = <int, String>{};
  var done = false;

  final lines = proc.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter());

  await for (final line in lines) {
    if (line.isEmpty || !line.startsWith('{')) continue;
    final Object? parsed = jsonDecode(line);
    if (parsed is! Map) continue;
    final type = parsed['type'];
    switch (type) {
      case 'suite':
        final s = parsed['suite'] as Map;
        suites[s['id'] as int] = (s['path'] as String?) ?? '';
        break;
      case 'testStart':
        final t = parsed['test'] as Map;
        final name = t['name'] as String? ?? '';
        if (name.startsWith('loading ')) break;
        tests[t['id'] as int] = _T(
          name,
          suites[t['suiteID'] as int] ?? '',
        );
        break;
      case 'testDone':
        final t = tests[parsed['testID'] as int];
        if (t == null) break;
        if (parsed['hidden'] == true) {
          tests.remove(parsed['testID']);
          break;
        }
        t.result = parsed['result'] as String? ?? 'unknown';
        t.skipped = parsed['skipped'] == true;
        break;
      case 'done':
        done = true;
        break;
    }
  }
  await proc.exitCode;
  if (!done) {
    stderr.writeln('warning: test run did not emit a done event');
  }

  // Aggregate by dimension (top-level test/<dim>/ folder).
  final byDim = <String, _Counts>{};
  for (final t in tests.values) {
    final dim = _dimension(t.suitePath);
    final c = byDim.putIfAbsent(dim, () => _Counts());
    if (t.skipped) {
      c.skipped++;
    } else if (t.result == 'success') {
      c.passed++;
    } else {
      c.failed++;
      c.failures.add(t.name);
    }
  }

  final total = _Counts();
  byDim.values.forEach(total.add);

  print('');
  print('════════════════════ RELIABILITY SCORECARD ════════════════════');
  print('  ${DateTime.now().toIso8601String()}');
  print('');
  print('  ${'Dimension'.padRight(26)} ${'pass'.padLeft(5)} '
      '${'skip'.padLeft(5)} ${'fail'.padLeft(5)}');
  print('  ${'-' * 26} ${'-' * 5} ${'-' * 5} ${'-' * 5}');
  final dims = byDim.keys.toList()..sort();
  for (final d in dims) {
    final c = byDim[d]!;
    print('  ${d.padRight(26)} ${'${c.passed}'.padLeft(5)} '
        '${'${c.skipped}'.padLeft(5)} ${'${c.failed}'.padLeft(5)}');
  }
  print('  ${'-' * 26} ${'-' * 5} ${'-' * 5} ${'-' * 5}');
  print('  ${'TOTAL'.padRight(26)} ${'${total.passed}'.padLeft(5)} '
      '${'${total.skipped}'.padLeft(5)} ${'${total.failed}'.padLeft(5)}');
  print('');

  if (total.failures.isNotEmpty) {
    print('  UNEXPECTED FAILURES (not documented skips):');
    for (final f in total.failures) {
      print('    ✗ $f');
    }
    print('');
  }

  final certified = total.failed == 0;
  print('  Certification gate (0 unexpected failures): '
      '${certified ? 'PASS ✅' : 'FAIL ❌'}');
  print('  Documented open bugs (skipped regression guards): ${total.skipped}');
  print('════════════════════════════════════════════════════════════════');

  exitCode = certified ? 0 : 1;
}

String _dimension(String suitePath) {
  final norm = suitePath.replaceAll('\\', '/');
  final m = RegExp(r'test/([^/]+)/').firstMatch(norm);
  return m != null ? m.group(1)! : 'other';
}

class _T {
  _T(this.name, this.suitePath);
  final String name;
  final String suitePath;
  String result = 'unknown';
  bool skipped = false;
}

class _Counts {
  int passed = 0;
  int skipped = 0;
  int failed = 0;
  final List<String> failures = <String>[];
  void add(_Counts o) {
    passed += o.passed;
    skipped += o.skipped;
    failed += o.failed;
    failures.addAll(o.failures);
  }
}
