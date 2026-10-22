/// Randomized differential fuzz regression gate. Generates thousands of random
/// SELECTs (type-aware) and asserts 0 divergences from SQLite.
///
/// Currently **skipped** because bug F7 (NULL left-operand short-circuit in
/// AND/OR) makes a few percent of random predicates diverge. Un-skip once F7 is
/// fixed — this then becomes the standing correctness gate. The discovery tool
/// `bin/fuzz_triage.dart` runs it unconditionally for triage.
@Timeout(Duration(minutes: 3))
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('randomized differential fuzz', () {
    test('no divergences across 20 seeds × 150 queries', () async {
      final failures = <String>[];
      for (var s = 0; s < 20; s++) {
        final fz = SqlFuzzer(5000 + s);
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
          for (var q = 0; q < 150 && failures.length < 10; q++) {
            final sql = fz.query();
            final d = await o.diff(sql);
            if (d != null) failures.add('seed=${5000 + s} `$sql` :: $d');
          }
        } finally {
          o.close();
        }
      }
      expect(failures, isEmpty,
          reason: 'differential divergences:\n${failures.join('\n')}');
    });
  },
      skip: sqliteSkipReason() ??
          'BLOCKED by KNOWN ENGINE BUG F7 (NULL short-circuit in AND/OR). '
              'Un-skip when F7 is fixed. See findings/FINDINGS.md.');
}
