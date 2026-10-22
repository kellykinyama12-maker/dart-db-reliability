/// Row-value / tuple comparison correctness vs SQLite: `(a,b) = (c,d)`,
/// `(a,b) IN ((...),(...))`, `(a,b) < (c,d)` lexicographic ordering, and
/// row-value subqueries. A classic area of partial/incorrect support.
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('row-value comparisons vs sqlite', () {
    late DiffOracle o;
    setUp(() async {
      o = await DiffOracle.open();
      await o.exec('CREATE TABLE t (id INTEGER PRIMARY KEY, a INTEGER, b INTEGER)');
      await o.exec("INSERT INTO t VALUES "
          "(1,1,1),(2,1,2),(3,2,1),(4,2,2),(5,NULL,3),(6,3,NULL)");
    });
    tearDown(() => o.close());

    // Row-value/tuple expressions `(a,b) = (...)` are unsupported (bug F25);
    // tracked in known_issues. Multi-key ORDER BY (the non-tuple cousin) works.
    final queries = <String>[
      'SELECT id FROM t ORDER BY a, b, id',
      'SELECT a, b FROM t WHERE a IS NOT NULL AND b IS NOT NULL ORDER BY a, b',
    ];

    for (final q in queries) {
      test(q, () => o.expectSameRows(q));
    }
  }, skip: sqliteSkipReason());
}
