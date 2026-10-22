/// Scale & large-result correctness: bulk-load tens of thousands of rows and
/// verify aggregates, grouping, ordering and index-backed lookups stay correct
/// at size. Differential against SQLite so the expected values are exact.
@Timeout(Duration(minutes: 3))
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('scale correctness vs sqlite', () {
    test('50k rows: aggregates, grouping, ordering, distinct', () async {
      final o = await DiffOracle.open();
      try {
        await o.exec('CREATE TABLE big (id INTEGER PRIMARY KEY, '
            'grp INTEGER, v INTEGER)');
        // Deterministic bulk load into both engines, batched for speed.
        const n = 50000;
        final buf = StringBuffer();
        for (var i = 1; i <= n; i++) {
          if (buf.isEmpty) {
            buf.write('INSERT INTO big (id, grp, v) VALUES ');
          } else {
            buf.write(',');
          }
          buf.write('($i, ${i % 100}, ${(i * 7919) % 10007})');
          if (i % 1000 == 0) {
            await o.exec(buf.toString());
            buf.clear();
          }
        }
        if (buf.isNotEmpty) await o.exec(buf.toString());

        await o.expectSameRows('SELECT COUNT(*), SUM(v), MIN(v), MAX(v) FROM big');
        await o.expectSameRows(
            'SELECT grp, COUNT(*), SUM(v), AVG(v) FROM big GROUP BY grp '
            'ORDER BY grp');
        await o.expectSameRows('SELECT COUNT(DISTINCT v) FROM big');
        await o.expectSameRows(
            'SELECT id, v FROM big ORDER BY v DESC, id ASC LIMIT 25');
        await o.expectSameRows(
            'SELECT grp, SUM(v) s FROM big GROUP BY grp HAVING SUM(v) > 2000000 '
            'ORDER BY grp');
      } finally {
        o.close();
      }
    });

    test('index-backed point lookups at scale', () async {
      final o = await DiffOracle.open();
      try {
        await o.exec('CREATE TABLE u (id INTEGER PRIMARY KEY, k INTEGER, t TEXT)');
        final buf = StringBuffer();
        for (var i = 1; i <= 20000; i++) {
          if (buf.isEmpty) {
            buf.write('INSERT INTO u (id, k, t) VALUES ');
          } else {
            buf.write(',');
          }
          buf.write("($i, ${(i * 104729) % 20000}, 'row$i')");
          if (i % 1000 == 0) {
            await o.exec(buf.toString());
            buf.clear();
          }
        }
        if (buf.isNotEmpty) await o.exec(buf.toString());
        await o.exec('CREATE INDEX idx_k ON u(k)');

        for (final k in [0, 1, 9999, 15000, 19999]) {
          await o.expectSameRows(
              'SELECT id, k, t FROM u WHERE k = $k ORDER BY id');
        }
        await o.expectSameRows(
            'SELECT COUNT(*) FROM u WHERE k BETWEEN 5000 AND 6000');
      } finally {
        o.close();
      }
    });
  }, skip: sqliteSkipReason());
}
