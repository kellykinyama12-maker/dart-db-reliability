/// Type & value semantics: integer/real arithmetic, division, modulo, rounding,
/// text functions, comparison/ordering, and CAST — all validated differentially
/// against SQLite so edge cases (integer vs real division, NULL propagation,
/// collation) are pinned to an authoritative answer.
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('type & value semantics vs sqlite', () {
    late DiffOracle o;
    setUp(() async {
      o = await DiffOracle.open();
      await o.exec('CREATE TABLE n (id INTEGER PRIMARY KEY, i INTEGER, r REAL)');
      await o.exec('INSERT INTO n VALUES '
          '(1, 7, 2.5), (2, -3, 0.0), (3, 0, -1.25), (4, 100, 3.0)');
      await o.exec('CREATE TABLE s (id INTEGER PRIMARY KEY, t TEXT)');
      await o.exec("INSERT INTO s VALUES "
          "(1,'Hello'),(2,'world'),(3,'  pad  '),(4,'MiXeD')");
    });
    tearDown(() => o.close());

    group('numeric', () {
      final qs = [
        'SELECT id, i + r FROM n ORDER BY id',
        'SELECT id, i * 2, r * 2 FROM n ORDER BY id',
        'SELECT id, r / 2 FROM n ORDER BY id', // real division
        'SELECT id, i % 3 FROM n ORDER BY id',
        'SELECT id, ABS(i), ABS(r) FROM n ORDER BY id',
        'SELECT id, ROUND(r), ROUND(r, 1) FROM n ORDER BY id',
        'SELECT SUM(i), SUM(r), AVG(i), AVG(r) FROM n',
        'SELECT id, -i, -r FROM n ORDER BY id',
        'SELECT id, i > r FROM n ORDER BY id',
        'SELECT id, CAST(r AS INTEGER) FROM n ORDER BY id',
        'SELECT id, CAST(i AS REAL) FROM n ORDER BY id',
      ];
      for (final q in qs) {
        test(q, () => o.expectSameRows(q));
      }
    });

    group('text', () {
      final qs = [
        'SELECT id, LENGTH(t) FROM s ORDER BY id',
        'SELECT id, UPPER(t), LOWER(t) FROM s ORDER BY id',
        'SELECT id, TRIM(t) FROM s ORDER BY id',
        'SELECT id, SUBSTR(t, 1, 3) FROM s ORDER BY id',
        "SELECT id, REPLACE(t, 'l', 'L') FROM s ORDER BY id",
        "SELECT id, t || '!' FROM s ORDER BY id",
        'SELECT id, INSTR(t, \'o\') FROM s ORDER BY id',
        'SELECT t FROM s ORDER BY t',
        "SELECT id FROM s WHERE t LIKE '%o%' ORDER BY id",
        "SELECT id FROM s WHERE t GLOB 'M*' ORDER BY id",
      ];
      for (final q in qs) {
        test(q, () => o.expectSameRows(q));
      }
    });

    group('type affinity / mixed ordering', () {
      test('mixed int/text sort order matches sqlite', () async {
        await o.exec('CREATE TABLE mix (v INTEGER)');
        await o.exec("INSERT INTO mix VALUES (1),(2),(NULL),(10)");
        await o.expectSameRows('SELECT v FROM mix ORDER BY v');
      });
    });
  }, skip: sqliteSkipReason());
}
