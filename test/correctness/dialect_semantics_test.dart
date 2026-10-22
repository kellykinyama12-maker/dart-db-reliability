/// Dialect semantics where dart_db_server deliberately follows **MySQL/Oracle**
/// rather than SQLite — so SQLite is the wrong oracle. These assert the engine's
/// enterprise-aligned behavior directly (authored expectations).
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('MySQL/Oracle-aligned dialect semantics', () {
    test('`/` is real division (7/2 = 3.5), matching MySQL & Oracle', () async {
      final db = await openEngine();
      await expectScalar(db, 'SELECT 7 / 2', 3.5);
      await expectScalar(db, 'SELECT 1 / 4', 0.25);
    });

    test('GREATEST / LEAST scalar functions (Oracle/MySQL)', () async {
      final db = await openEngine();
      await expectScalar(db, 'SELECT GREATEST(3, 7, 5)', 7);
      await expectScalar(db, 'SELECT LEAST(3, 7, 5)', 3);
    });

    test('column types are required (like Oracle/MySQL, unlike SQLite)',
        () async {
      final db = await openEngine();
      // Typeless `CREATE TABLE t (v)` is an SQLite-only permissiveness; an
      // enterprise-dialect engine requires a declared type.
      await expectThrows(db, 'CREATE TABLE typeless (v)');
      await expectOk(db, 'CREATE TABLE typed (v INTEGER)');
    });

    test('CONCAT and || string concatenation', () async {
      final db = await openEngine();
      await expectScalar(db, "SELECT 'a' || 'b' || 'c'", 'abc');
    });

    test('MOD and integer arithmetic', () async {
      final db = await openEngine();
      await expectScalar(db, 'SELECT 17 % 5', 2);
      await expectScalar(db, 'SELECT 10 * 10', 100);
    });

    test('CAST parses hex string literals (unlike SQLite)', () async {
      final db = await openEngine();
      // SQLite returns 0 for CAST('0x10' AS INTEGER); the engine parses hex.
      await expectScalar(db, "SELECT CAST('0x10' AS INTEGER)", 16);
    });
  });
}
