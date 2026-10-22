/// CAST / type-conversion correctness, validated differentially against SQLite.
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('CAST & conversion vs sqlite', () {
    late DiffOracle o;
    setUp(() async {
      o = await DiffOracle.open();
      await o.exec('CREATE TABLE t (id INTEGER PRIMARY KEY, s TEXT, r REAL)');
      await o.exec("INSERT INTO t VALUES "
          "(1,'123',1.9),(2,'45.67',2.5),(3,'abc',-3.5),(4,'  12 ',0.0),"
          "(5,'',100.4999)");
    });
    tearDown(() => o.close());

    final queries = <String>[
      'SELECT id, CAST(s AS INTEGER) FROM t ORDER BY id',
      'SELECT id, CAST(s AS REAL) FROM t ORDER BY id',
      'SELECT id, CAST(r AS INTEGER) FROM t ORDER BY id',
      'SELECT id, CAST(r AS TEXT) FROM t ORDER BY id',
      'SELECT id, CAST(id AS TEXT) FROM t ORDER BY id',
      "SELECT CAST('3.14159' AS REAL)",
      "SELECT CAST(3.99 AS INTEGER)",   // truncation, not rounding
      "SELECT CAST(-3.99 AS INTEGER)",
      'SELECT id, TYPEOF(CAST(s AS INTEGER)) FROM t ORDER BY id',
      'SELECT id, r || \'\' FROM t ORDER BY id', // implicit text coercion
    ];

    for (final q in queries) {
      test(q, () => o.expectSameRows(q));
    }
  }, skip: sqliteSkipReason());
}
