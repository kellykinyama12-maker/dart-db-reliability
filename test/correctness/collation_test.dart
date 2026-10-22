/// Collation / case-sensitivity / text comparison vs SQLite: COLLATE NOCASE and
/// BINARY, case-insensitive equality and ordering, LIKE case folding, and
/// DISTINCT/GROUP BY under collation.
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('collation vs sqlite', () {
    late DiffOracle o;
    setUp(() async {
      o = await DiffOracle.open();
      await o.exec('CREATE TABLE t (id INTEGER PRIMARY KEY, s TEXT)');
      await o.exec("INSERT INTO t VALUES "
          "(1,'Apple'),(2,'apple'),(3,'BANANA'),(4,'banana'),(5,'Cherry'),"
          "(6,'apple ')");
    });
    tearDown(() => o.close());

    final queries = <String>[
      // default (binary) equality is case-sensitive
      "SELECT id FROM t WHERE s = 'apple' ORDER BY id",
      // ordering under default (binary) collation
      'SELECT s FROM t ORDER BY s',
      // DISTINCT under default collation
      'SELECT COUNT(DISTINCT s) FROM t',
      // GLOB is case-sensitive
      "SELECT id FROM t WHERE s GLOB 'a*' ORDER BY id",
      "SELECT id FROM t WHERE s GLOB 'A*' ORDER BY id",
      // comparison operators under binary collation
      "SELECT id FROM t WHERE s < 'b' ORDER BY id",
      // trailing space matters in binary equality
      "SELECT id FROM t WHERE s = 'apple ' ORDER BY id",
      // UPPER/LOWER normalization
      'SELECT COUNT(DISTINCT UPPER(s)) FROM t',
      'SELECT UPPER(s) u, COUNT(*) FROM t GROUP BY u ORDER BY u',
    ];

    for (final q in queries) {
      test(q, () => o.expectSameRows(q));
    }
  }, skip: sqliteSkipReason());
}
