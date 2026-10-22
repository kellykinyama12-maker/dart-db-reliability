/// Deep date/time arithmetic vs SQLite: chained modifiers, month-end clamping,
/// weekday, start-of-x, julianday round-trips, leap years, and date diffs.
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('date/time deep vs sqlite', () {
    late DiffOracle o;
    setUp(() async {
      o = await DiffOracle.open();
      await o.exec('CREATE TABLE d (id INTEGER PRIMARY KEY, ts TEXT)');
      await o.exec("INSERT INTO d VALUES "
          "(1,'2021-01-31'),(2,'2020-02-29'),(3,'2021-12-31'),"
          "(4,'2021-03-15 14:30:00'),(5,'2000-01-01')");
    });
    tearDown(() => o.close());

    final queries = <String>[
      // month arithmetic with end-of-month clamping
      "SELECT id, date(ts, '+1 month') FROM d ORDER BY id",
      "SELECT id, date(ts, '-1 month') FROM d ORDER BY id",
      "SELECT id, date(ts, '+1 month', '+1 day') FROM d ORDER BY id",
      // year arithmetic across leap day
      "SELECT id, date(ts, '+1 year') FROM d ORDER BY id",
      "SELECT id, date(ts, '-1 year') FROM d ORDER BY id",
      // start of units
      "SELECT id, date(ts, 'start of month') FROM d ORDER BY id",
      "SELECT id, date(ts, 'start of year') FROM d ORDER BY id",
      "SELECT id, datetime(ts, 'start of day') FROM d ORDER BY id",
      // weekday
      "SELECT id, strftime('%w', ts) FROM d ORDER BY id",
      "SELECT id, date(ts, 'weekday 0') FROM d ORDER BY id",
      "SELECT id, date(ts, 'weekday 1') FROM d ORDER BY id",
      // chained
      "SELECT id, date(ts, 'start of month', '+1 month', '-1 day') FROM d "
          'ORDER BY id',
      // julianday round-trip and diff
      "SELECT id, CAST(julianday(ts) AS INTEGER) FROM d ORDER BY id",
      "SELECT id, julianday('2021-12-31') - julianday(ts) FROM d ORDER BY id",
      // day/hour/minute additions
      "SELECT id, datetime(ts, '+36 hours') FROM d ORDER BY id",
      "SELECT id, datetime(ts, '+90 minutes') FROM d ORDER BY id",
      "SELECT id, datetime(ts, '-1 day', '+12 hours') FROM d ORDER BY id",
      // extract parts
      "SELECT id, strftime('%Y/%m/%d %H:%M', ts) FROM d ORDER BY id",
      "SELECT id, strftime('%d', ts) FROM d ORDER BY id",
      "SELECT id, strftime('%j', ts) FROM d ORDER BY id",
    ];

    for (final q in queries) {
      test(q.substring(0, q.length.clamp(0, 60)), () => o.expectSameRows(q));
    }
  }, skip: sqliteSkipReason());
}
