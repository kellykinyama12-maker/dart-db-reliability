/// Date/time correctness — a notorious source of engine divergence. Uses
/// SQLite's date/time functions (the engine is SQLite-rooted) and asserts
/// identical results differentially.
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('date/time vs sqlite', () {
    late DiffOracle o;
    setUp(() async {
      o = await DiffOracle.open();
      await o.exec('CREATE TABLE ev (id INTEGER PRIMARY KEY, ts TEXT)');
      await o.exec("INSERT INTO ev VALUES "
          "(1,'2021-01-01 00:00:00'),"
          "(2,'2021-06-15 12:30:45'),"
          "(3,'2020-02-29 23:59:59'),"  // leap day
          "(4,'1999-12-31 23:59:59')");
    });
    tearDown(() => o.close());

    final queries = <String>[
      "SELECT id, date(ts) FROM ev ORDER BY id",
      "SELECT id, time(ts) FROM ev ORDER BY id",
      "SELECT id, datetime(ts) FROM ev ORDER BY id",
      "SELECT id, strftime('%Y', ts) FROM ev ORDER BY id",
      "SELECT id, strftime('%Y-%m', ts) FROM ev ORDER BY id",
      "SELECT id, strftime('%H:%M', ts) FROM ev ORDER BY id",
      "SELECT id, strftime('%w', ts) FROM ev ORDER BY id", // day of week
      "SELECT id, strftime('%j', ts) FROM ev ORDER BY id", // day of year
      "SELECT id, date(ts, '+1 day') FROM ev ORDER BY id",
      "SELECT id, date(ts, '+1 year') FROM ev ORDER BY id",
      "SELECT id, date(ts, 'start of month') FROM ev ORDER BY id",
      "SELECT id, julianday(ts) > 2451544 FROM ev ORDER BY id",
      "SELECT id FROM ev WHERE date(ts) >= '2021-01-01' ORDER BY id",
      "SELECT id FROM ev WHERE ts < '2021-01-01' ORDER BY id",
      "SELECT MIN(ts), MAX(ts) FROM ev",
    ];

    for (final q in queries) {
      test(q, () => o.expectSameRows(q));
    }
  }, skip: sqliteSkipReason());
}
