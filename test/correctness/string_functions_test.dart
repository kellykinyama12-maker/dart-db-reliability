/// String-function correctness, validated differentially against SQLite.
/// Targets the edge cases engines get wrong: negative SUBSTR, out-of-range
/// indices, REPLACE with empty, INSTR misses, LIKE escapes, TRIM variants.
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('string functions vs sqlite', () {
    late DiffOracle o;
    setUp(() async {
      o = await DiffOracle.open();
      await o.exec('CREATE TABLE s (id INTEGER PRIMARY KEY, t TEXT)');
      await o.exec("INSERT INTO s VALUES "
          "(1,'Hello World'),(2,''),(3,'aXbXc'),(4,'  trim me  '),"
          "(5,'café'),(6,'100%_done')");
    });
    tearDown(() => o.close());

    final queries = <String>[
      'SELECT id, SUBSTR(t, 1, 5) FROM s ORDER BY id',
      'SELECT id, SUBSTR(t, -3) FROM s ORDER BY id',       // negative start
      'SELECT id, SUBSTR(t, 100) FROM s ORDER BY id',      // out of range
      'SELECT id, LENGTH(t) FROM s ORDER BY id',
      'SELECT id, TRIM(t), LTRIM(t), RTRIM(t) FROM s ORDER BY id',
      "SELECT id, REPLACE(t, 'X', '-') FROM s ORDER BY id",
      "SELECT id, REPLACE(t, 'X', '') FROM s ORDER BY id",  // delete
      "SELECT id, INSTR(t, 'X') FROM s ORDER BY id",
      "SELECT id, INSTR(t, 'zzz') FROM s ORDER BY id",      // miss -> 0
      "SELECT id, t || '!' FROM s ORDER BY id",
      "SELECT id FROM s WHERE t LIKE '%o%' ORDER BY id",
      "SELECT id FROM s WHERE t LIKE '_ello%' ORDER BY id",
      "SELECT id, printf('[%s]', t) FROM s ORDER BY id",
      'SELECT id, quote(t) FROM s ORDER BY id',
    ];

    for (final q in queries) {
      test(q, () => o.expectSameRows(q));
    }
  }, skip: sqliteSkipReason());
}
