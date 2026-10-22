/// Differential fuzz: generate a seeded workload, load it into both engines,
/// and assert every read query returns identical results. A divergence is a
/// correctness bug in the engine (or an intentional dialect difference worth
/// documenting). Deterministic seeds make any failure reproducible.
@Timeout(Duration(minutes: 2))
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('differential fuzz vs sqlite', () {
    for (final seed in [1, 7, 42, 1234, 99991]) {
      test('seed $seed · 500 rows · ${20} queries', () async {
        final o = await DiffOracle.open();
        try {
          final wl = Workload(seed);
          await o.exec(Workload.createTable);
          for (final ins in wl.inserts(500)) {
            await o.exec(ins);
          }
          for (final q in wl.readQueries()) {
            await o.expectSameRows(q, reason: 'seed=$seed query=`$q`');
          }
        } finally {
          o.close();
        }
      });
    }
  }, skip: sqliteSkipReason());
}
