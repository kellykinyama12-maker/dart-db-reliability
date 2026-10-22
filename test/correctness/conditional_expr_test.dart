/// CASE / COALESCE / NULLIF / IFNULL and conditional-expression correctness,
/// validated differentially against SQLite. These concentrate NULL and
/// branch-selection logic where engines frequently diverge.
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('conditional expressions vs sqlite', () {
    late DiffOracle o;
    setUp(() async {
      o = await DiffOracle.open();
      await o.exec('CREATE TABLE t (id INTEGER PRIMARY KEY, a INTEGER, b INTEGER, s TEXT)');
      await o.exec("INSERT INTO t VALUES "
          "(1,10,1,'x'),(2,NULL,2,'y'),(3,0,NULL,NULL),(4,-5,0,''),(5,10,10,'z')");
    });
    tearDown(() => o.close());

    final queries = <String>[
      // searched CASE
      'SELECT id, CASE WHEN a > 0 THEN \'pos\' WHEN a < 0 THEN \'neg\' '
          'ELSE \'zero/null\' END FROM t ORDER BY id',
      // simple CASE
      'SELECT id, CASE a WHEN 10 THEN \'ten\' WHEN 0 THEN \'zero\' '
          'ELSE \'other\' END FROM t ORDER BY id',
      // CASE without ELSE → NULL
      'SELECT id, CASE WHEN a > 5 THEN 1 END FROM t ORDER BY id',
      // simple CASE with NULL operand (NULL never matches)
      'SELECT id, CASE a WHEN NULL THEN \'n\' ELSE \'d\' END FROM t ORDER BY id',
      // COALESCE chains
      'SELECT id, COALESCE(a, b, -1) FROM t ORDER BY id',
      'SELECT id, COALESCE(s, \'none\') FROM t ORDER BY id',
      // NULLIF
      'SELECT id, NULLIF(a, b) FROM t ORDER BY id',
      'SELECT id, NULLIF(a, 10) FROM t ORDER BY id',
      // IFNULL
      'SELECT id, IFNULL(a, 0) FROM t ORDER BY id',
      // nested CASE in aggregate
      'SELECT SUM(CASE WHEN a > 0 THEN a ELSE 0 END) FROM t',
      'SELECT COUNT(CASE WHEN a IS NULL THEN 1 END) FROM t',
      // CASE in GROUP BY
      'SELECT CASE WHEN a > 0 THEN \'p\' ELSE \'np\' END k, COUNT(*) '
          'FROM t GROUP BY k ORDER BY k',
      // CASE in ORDER BY
      'SELECT id FROM t ORDER BY CASE WHEN a IS NULL THEN 1 ELSE 0 END, id',
    ];

    for (final q in queries) {
      test(q, () => o.expectSameRows(q));
    }
  }, skip: sqliteSkipReason());
}
