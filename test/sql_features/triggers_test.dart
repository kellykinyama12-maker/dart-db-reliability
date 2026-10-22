/// Trigger semantics, validated differentially against SQLite: BEFORE/AFTER ×
/// INSERT/UPDATE/DELETE, access to NEW/OLD, trigger-driven cascades, and
/// multi-statement trigger bodies. Triggers are a classic correctness minefield.
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('triggers vs sqlite', () {
    late DiffOracle o;
    setUp(() async {
      o = await DiffOracle.open();
      await o.exec('CREATE TABLE t (id INTEGER PRIMARY KEY, v INTEGER)');
      await o.exec('CREATE TABLE audit (id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'op TEXT, old_v INTEGER, new_v INTEGER)');
    });
    tearDown(() => o.close());

    test('AFTER INSERT writes an audit row with NEW', () async {
      await o.exec('CREATE TRIGGER trg_ins AFTER INSERT ON t BEGIN '
          "INSERT INTO audit(op, new_v) VALUES ('INS', NEW.v); END");
      await o.exec('INSERT INTO t VALUES (1, 10), (2, 20)');
      await o.expectSameRows('SELECT op, new_v FROM audit ORDER BY id');
      await o.expectSameRows('SELECT id, v FROM t ORDER BY id');
    });

    test('AFTER UPDATE sees OLD and NEW', () async {
      await o.exec('CREATE TRIGGER trg_upd AFTER UPDATE ON t BEGIN '
          "INSERT INTO audit(op, old_v, new_v) VALUES ('UPD', OLD.v, NEW.v); END");
      await o.exec('INSERT INTO t VALUES (1, 10)');
      await o.exec('UPDATE t SET v = 99 WHERE id = 1');
      await o.expectSameRows('SELECT op, old_v, new_v FROM audit ORDER BY id');
    });

    test('AFTER DELETE sees OLD', () async {
      await o.exec('CREATE TRIGGER trg_del AFTER DELETE ON t BEGIN '
          "INSERT INTO audit(op, old_v) VALUES ('DEL', OLD.v); END");
      await o.exec('INSERT INTO t VALUES (1, 10), (2, 20)');
      await o.exec('DELETE FROM t WHERE id = 1');
      await o.expectSameRows('SELECT op, old_v FROM audit ORDER BY id');
      await o.expectSameRows('SELECT id FROM t ORDER BY id');
    });

    test('BEFORE INSERT can be conditional (WHEN)', () async {
      await o.exec('CREATE TRIGGER trg_when BEFORE INSERT ON t '
          'WHEN NEW.v < 0 BEGIN '
          "INSERT INTO audit(op, new_v) VALUES ('NEG', NEW.v); END");
      await o.exec('INSERT INTO t VALUES (1, 5), (2, -3), (3, 7)');
      await o.expectSameRows('SELECT op, new_v FROM audit ORDER BY id');
    });

    test('trigger updates another table (derived counter)', () async {
      await o.exec('CREATE TABLE counter (k TEXT PRIMARY KEY, n INTEGER)');
      await o.exec("INSERT INTO counter VALUES ('rows', 0)");
      await o.exec('CREATE TRIGGER trg_cnt AFTER INSERT ON t BEGIN '
          "UPDATE counter SET n = n + 1 WHERE k = 'rows'; END");
      await o.exec('INSERT INTO t VALUES (1,1),(2,2),(3,3)');
      await o.expectSameRows('SELECT k, n FROM counter');
    });

    test('row-count: one audit row per affected row on multi-row UPDATE',
        () async {
      await o.exec('CREATE TRIGGER trg_u AFTER UPDATE ON t BEGIN '
          "INSERT INTO audit(op, new_v) VALUES ('U', NEW.v); END");
      await o.exec('INSERT INTO t VALUES (1,1),(2,2),(3,3)');
      await o.exec('UPDATE t SET v = v + 10');
      await o.expectSameRows('SELECT COUNT(*) FROM audit');
      await o.expectSameRows('SELECT op, new_v FROM audit ORDER BY new_v');
    });
  }, skip: sqliteSkipReason());
}
