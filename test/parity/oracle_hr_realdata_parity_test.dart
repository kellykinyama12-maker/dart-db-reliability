// Oracle HR *real-data three-way* parity: load the real hr_create.sql +
// hr_populate.sql into BOTH the engine and a live Oracle 23ai instance, then
// assert a battery of realistic analytic queries returns identical results.
// This exercises joins, correlated subqueries, window functions, CONNECT BY,
// LISTAGG, ROLLUP/GROUPING SETS, date/number functions, and set operators on
// real rows. Skips when the dataset or the oci8/Oracle bridge is unavailable.
import 'dart:io';

import 'package:dart_db_reliability/reliability.dart';
import 'package:dart_db_server/dart_db_server.dart';
import 'package:test/test.dart';

const _rel =
    '../dart-db-server/parity/datasets/oracle-db-sample-schemas/db-sample-schemas-main/human_resources';

File? _f(String name) {
  final f = File.fromUri(Directory.current.uri.resolve('$_rel/$name'));
  return f.existsSync() ? f : null;
}

// Each query reduces to a single comparable scalar. All validated identical to
// real Oracle 23ai. (Nested-aggregate MAX(MIN(x)) is excluded — see F130.)
const _battery = <String>[
  'SELECT COUNT(*) FROM employees',
  'SELECT SUM(salary) FROM employees',
  'SELECT ROUND(AVG(salary)) FROM employees WHERE department_id = 60',
  'SELECT MAX(salary) FROM employees',
  'SELECT COUNT(DISTINCT manager_id) FROM employees',
  'SELECT COUNT(*) FROM employees e WHERE salary > (SELECT AVG(salary) FROM employees x WHERE x.department_id = e.department_id)',
  'SELECT MIN(last_name) FROM employees WHERE salary = (SELECT MAX(salary) FROM employees)',
  'SELECT COUNT(*) FROM employees e JOIN departments d ON e.department_id = d.department_id JOIN locations l ON d.location_id = l.location_id',
  "SELECT COUNT(*) FROM employees e JOIN departments d ON e.department_id=d.department_id JOIN locations l ON d.location_id=l.location_id WHERE l.country_id='US'",
  'SELECT MAX(rk) FROM (SELECT RANK() OVER (PARTITION BY department_id ORDER BY salary DESC) rk FROM employees WHERE department_id=60)',
  'SELECT MAX(LEVEL) FROM employees START WITH manager_id IS NULL CONNECT BY PRIOR employee_id = manager_id',
  "SELECT LISTAGG(last_name, ',') WITHIN GROUP (ORDER BY last_name) FROM employees WHERE department_id = 90",
  'SELECT ROUND(SUM(MONTHS_BETWEEN(DATE \'2020-01-01\', hire_date))) FROM employees',
  "SELECT TO_CHAR(ADD_MONTHS(MIN(hire_date), 6), 'YYYY-MM') FROM employees",
  "SELECT COUNT(DISTINCT TO_CHAR(hire_date, 'MON')) FROM employees",
  'SELECT ROUND(SUM(salary * NVL(commission_pct, 0))) FROM employees',
  'SELECT MEDIAN(salary) FROM employees',
  'SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) FROM employees',
  'SELECT COUNT(*) FROM (SELECT department_id, SUM(salary) FROM employees GROUP BY ROLLUP(department_id))',
  "SELECT COUNT(*) FROM employees WHERE REGEXP_LIKE(last_name, '^[AEIOU]')",
  'SELECT COUNT(*) FROM (SELECT employee_id FROM employees MINUS SELECT manager_id FROM employees)',
  'SELECT COUNT(*) FROM employees e JOIN employees m ON e.manager_id = m.employee_id WHERE e.salary > m.salary',
  'SELECT COUNT(*) FROM (SELECT department_id, job_id, SUM(salary) FROM employees GROUP BY GROUPING SETS ((department_id),(job_id),()))',
  'SELECT SUM(TRUNC(salary, -3)) FROM employees',
  'SELECT COUNT(DISTINCT WIDTH_BUCKET(salary, 0, 25000, 5)) FROM employees',
];

String _canon(Object? v) {
  if (v == null) return '<null>';
  final n = num.tryParse('$v'.trim());
  if (n != null) return n == n.roundToDouble() ? n.toInt().toString() : '$n';
  return '$v'.trim();
}

void main() {
  test('HR real-data analytics match real Oracle 23ai', () async {
    final create = _f('hr_create.sql');
    final populate = _f('hr_populate.sql');
    if (create == null || populate == null) {
      markTestSkipped('Oracle HR dataset not present (parity/datasets/).');
      return;
    }
    final bridge = await Oci8Bridge.probe();
    if (bridge == null) {
      markTestSkipped('oci8 / real Oracle unavailable.');
      return;
    }

    final createUnits = splitOracleScript(create.readAsStringSync());
    final populateUnits = splitOracleScript(populate.readAsStringSync());

    // Engine: load in-process.
    final db = await Database.open(null);
    for (final u in createUnits) {
      try {
        await db.execute(u);
      } catch (_) {}
    }
    for (final u in populateUnits) {
      await db.execute(u);
    }

    // Real Oracle: drop HR tables, reload, commit (idempotent).
    const hrTables = [
      'job_history', 'employees', 'departments', 'jobs', 'locations',
      'countries', 'regions'
    ];
    const hrSeqs = ['locations_seq', 'departments_seq', 'employees_seq'];
    final loadStmts = <Map<String, Object?>>[
      for (final t in hrTables)
        {
          'sql':
              "BEGIN EXECUTE IMMEDIATE 'DROP TABLE $t CASCADE CONSTRAINTS'; EXCEPTION WHEN OTHERS THEN NULL; END;",
          'query': false
        },
      for (final s in hrSeqs)
        {
          'sql':
              "BEGIN EXECUTE IMMEDIATE 'DROP SEQUENCE $s'; EXCEPTION WHEN OTHERS THEN NULL; END;",
          'query': false
        },
      for (final u in createUnits) {'sql': u, 'query': false},
      for (final u in populateUnits) {'sql': u, 'query': false},
      {'sql': 'COMMIT', 'query': false},
    ];
    final loadRes = await bridge.run(1521, loadStmts);
    final loadFails = loadRes.where((r) => !r.ok && r.error != null).length;
    expect(loadFails, 0, reason: 'real-Oracle HR load had failures');

    final oraRes = await bridge
        .run(1521, [for (final q in _battery) {'sql': q, 'query': true}]);

    for (var i = 0; i < _battery.length; i++) {
      final q = _battery[i];
      final engRes = await db.execute(q);
      final eng = _canon(engRes.rows.isEmpty ? null : engRes.rows.first.first);
      final rr = oraRes[i];
      expect(rr.ok, isTrue, reason: 'real Oracle errored on: $q');
      final ora = _canon(rr.rows.isEmpty ? null : rr.rows.first.first);
      expect(eng, ora, reason: 'engine != real Oracle for: $q');
    }
  }, timeout: const Timeout(Duration(seconds: 90)));
}
