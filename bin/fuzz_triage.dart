/// Fuzz triage runner: unleashes the random SQL generator at both engines and
/// collects (deduplicated) divergences for classification. Not a test — a
/// discovery tool. Run: `dart run bin/fuzz_triage.dart [seeds] [queriesPerSeed]`.
library;

import 'package:dart_db_reliability/reliability.dart';

Future<void> main(List<String> args) async {
  final seeds = args.isNotEmpty ? int.parse(args[0]) : 50;
  final perSeed = args.length > 1 ? int.parse(args[1]) : 200;

  if (sqliteSkipReason() != null) {
    // ignore: avoid_print
    print('sqlite3 unavailable: ${sqliteSkipReason()}');
    return;
  }

  final divergences = <String, _Hit>{}; // keyed by normalized signature
  var totalQueries = 0;
  var totalDiffs = 0;

  for (var s = 0; s < seeds; s++) {
    final fz = SqlFuzzer(1000 + s);
    final o = await DiffOracle.open();
    try {
      for (final ddl in fz.schema()) {
        await o.exec(ddl);
      }
      for (final ins in fz.rows(SqlFuzzer.tableA, 40)) {
        await o.exec(ins);
      }
      for (final ins in fz.rows(SqlFuzzer.tableB, 40)) {
        await o.exec(ins);
      }
      for (var q = 0; q < perSeed; q++) {
        final sql = fz.query();
        totalQueries++;
        String? d;
        try {
          d = await o.diff(sql);
        } catch (e) {
          d = 'HARNESS/throw | ${e.toString().split('\n').first}';
        }
        if (d != null) {
          totalDiffs++;
          final sig = _signature(d);
          divergences.putIfAbsent(sig, () => _Hit(sig)).add(SqlFuzzer(1000 + s).seed, sql, d);
        }
      }
    } finally {
      o.close();
    }
  }

  // ignore: avoid_print
  print('═══ FUZZ TRIAGE ═══');
  // ignore: avoid_print
  print('seeds=$seeds perSeed=$perSeed queries=$totalQueries '
      'divergences=$totalDiffs uniqueClasses=${divergences.length}\n');
  final sorted = divergences.values.toList()
    ..sort((a, b) => b.count.compareTo(a.count));
  for (final h in sorted) {
    // ignore: avoid_print
    print('• [${h.count}×] ${h.signature}');
    // ignore: avoid_print
    print('    e.g. ${h.sampleSql}');
    // ignore: avoid_print
    print('    ${h.sampleDiff}\n');
  }
}

String _signature(String diff) {
  // Collapse to a stable class: the leading reason + any error type name.
  final head = diff.split('|').first.trim();
  final typeMatch = RegExp(r"type '([^']+)'|(\w+Exception|Bad state|FormatException)")
      .firstMatch(diff);
  final t = typeMatch?.group(0) ?? '';
  return t.isEmpty ? head : '$head :: $t';
}

class _Hit {
  _Hit(this.signature);
  final String signature;
  int count = 0;
  int sampleSeed = 0;
  String sampleSql = '';
  String sampleDiff = '';
  void add(int seed, String sql, String diff) {
    count++;
    if (sampleSql.isEmpty || sql.length < sampleSql.length) {
      sampleSeed = seed;
      sampleSql = sql;
      sampleDiff = diff;
    }
  }
}
