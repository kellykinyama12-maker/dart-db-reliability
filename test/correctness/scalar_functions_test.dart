/// Scalar function correctness vs SQLite: numeric (abs/round/min/max/mod/
/// coalesce/nullif), string (hex/char/unicode/replace/trim/instr/substr),
/// and type (typeof/cast). A broad sweep for edge-case divergences.
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('scalar functions vs sqlite', () {
    late DiffOracle o;
    setUp(() async => o = await DiffOracle.open());
    tearDown(() => o.close());

    final queries = <String>[
      // numeric
      'SELECT abs(-5), abs(5), abs(-3.14)',
      'SELECT round(2.5), round(3.5), round(-2.5), round(2.567, 2)',
      'SELECT coalesce(NULL, NULL, 3, 4)',
      'SELECT nullif(5, 5), nullif(5, 6)',
      'SELECT 17 % 5, -17 % 5, 17 % -5',
      'SELECT 2 * 3 + 4, 2 * (3 + 4), 10 - 3 - 2',
      // string
      "SELECT length('hello'), length(''), length('héllo')",
      "SELECT upper('abc'), lower('ABC')",
      "SELECT substr('hello', 2, 3), substr('hello', -2)",
      "SELECT replace('aXbXc', 'X', '-')",
      "SELECT trim('  hi  '), ltrim('  hi  '), rtrim('  hi  ')",
      "SELECT instr('hello', 'l'), instr('hello', 'z')",
      "SELECT hex('AB'), hex(255)",
      "SELECT char(72, 105), unicode('H')",
      "SELECT 'a' || 'b' || 'c', 'x' || 1 || 'y'",
      "SELECT printf('%05d', 42), printf('%.2f', 3.14159)",
      "SELECT quote('it''s'), quote(42)",
      // type
      "SELECT typeof(1), typeof(1.5), typeof('x'), typeof(NULL)",
      "SELECT cast('42' AS INTEGER), cast(3.9 AS INTEGER), cast(42 AS TEXT)",
      // conditional
      "SELECT iif(1 > 0, 'y', 'n'), iif(0 > 1, 'y', 'n')",
      // sign-like
      'SELECT sign(-5), sign(0), sign(5)',
    ];

    for (final q in queries) {
      test(q, () => o.expectSameRows(q));
    }
  }, skip: sqliteSkipReason());
}
