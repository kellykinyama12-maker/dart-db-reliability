// Oracle *real-data three-way* parity (HR + SH), kept in ONE file so the two
// real-Oracle-mutating tests run sequentially (dart test runs files in
// parallel, which would race on the shared `native` schema — both HR and SH
// define a `countries` table). Each test fully drops+reloads its own tables, so
// order-independent. Loads the real sample-schema SQL into BOTH the engine and
// a live Oracle 23ai instance and asserts analytic queries match. Skips when
// the dataset or the oci8/Oracle bridge is unavailable.
import 'dart:io';

import 'package:dart_db_reliability/reliability.dart';
import 'package:dart_db_server/dart_db_server.dart';
import 'package:test/test.dart';

const _base =
    '../dart-db-server/parity/datasets/oracle-db-sample-schemas/db-sample-schemas-main';

File? _f(String rel) {
  final f = File.fromUri(Directory.current.uri.resolve('$_base/$rel'));
  return f.existsSync() ? f : null;
}

final _load = RegExp(r'^\s*LOAD\s', caseSensitive: false);

String _canon(Object? v) {
  if (v == null) return '<null>';
  final n = num.tryParse('$v'.trim());
  if (n != null) return n == n.roundToDouble() ? n.toInt().toString() : '$n';
  return '$v'.trim();
}

Future<void> _diff(Database db, List<String> battery,
    List<Oci8Result> oraRes) async {
  for (var i = 0; i < battery.length; i++) {
    final q = battery[i];
    final engRes = await db.execute(q);
    final eng = _canon(engRes.rows.isEmpty ? null : engRes.rows.first.first);
    final rr = oraRes[i];
    expect(rr.ok, isTrue, reason: 'real Oracle errored on: $q');
    final ora = _canon(rr.rows.isEmpty ? null : rr.rows.first.first);
    expect(eng, ora, reason: 'engine != real Oracle for: $q');
  }
}

const _hrBattery = <String>[
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

const _shBattery = <String>[
  'SELECT COUNT(*) FROM products',
  'SELECT COUNT(DISTINCT prod_category) FROM products',
  'SELECT COUNT(DISTINCT prod_subcategory) FROM products',
  'SELECT ROUND(AVG(prod_list_price), 2) FROM products',
  'SELECT MAX(prod_list_price) FROM products',
  'SELECT MAX(c) FROM (SELECT COUNT(*) c FROM products GROUP BY prod_category)',
  'SELECT COUNT(*) FROM products p WHERE prod_list_price > (SELECT AVG(prod_list_price) FROM products x WHERE x.prod_category=p.prod_category)',
  "SELECT LENGTH(LISTAGG(DISTINCT prod_category, ',') WITHIN GROUP (ORDER BY prod_category)) FROM products",
  'SELECT MAX(rk) FROM (SELECT RANK() OVER (PARTITION BY prod_category ORDER BY prod_list_price DESC) rk FROM products)',
  'SELECT COUNT(DISTINCT WIDTH_BUCKET(prod_list_price, 0, 2000, 10)) FROM products',
  'SELECT COUNT(*) FROM channels',
  'SELECT COUNT(DISTINCT channel_class) FROM channels',
  'SELECT COUNT(*) FROM countries',
  'SELECT COUNT(DISTINCT country_region) FROM countries',
  'SELECT COUNT(DISTINCT country_subregion) FROM countries',
  "SELECT COUNT(*) FROM products WHERE prod_status = 'STATUS'",
  'SELECT COUNT(DISTINCT prod_weight_class) FROM products',
  // Exact-decimal NUMBER SUM (F142). (MEDIAN still binary — F143.)
  'SELECT SUM(prod_list_price) FROM products',
  'SELECT ROUND(SUM(prod_list_price - prod_min_price), 2) FROM products',
];

void main() {
  test('HR real-data analytics match real Oracle 23ai', () async {
    final create = _f('human_resources/hr_create.sql');
    final populate = _f('human_resources/hr_populate.sql');
    if (create == null || populate == null) {
      markTestSkipped('Oracle HR dataset not present.');
      return;
    }
    final bridge = await Oci8Bridge.probe();
    if (bridge == null) {
      markTestSkipped('oci8 / real Oracle unavailable.');
      return;
    }
    final createUnits = splitOracleScript(create.readAsStringSync());
    final populateUnits = splitOracleScript(populate.readAsStringSync());

    final db = await Database.open(null);
    for (final u in createUnits) {
      try {
        await db.execute(u);
      } catch (_) {}
    }
    for (final u in populateUnits) {
      await db.execute(u);
    }

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
    expect(loadRes.where((r) => !r.ok && r.error != null).length, 0,
        reason: 'real-Oracle HR load had failures');

    final oraRes = await bridge
        .run(1521, [for (final q in _hrBattery) {'sql': q, 'query': true}]);
    await _diff(db, _hrBattery, oraRes);
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('SH lookup-data analytics match real Oracle 23ai', () async {
    final create = _f('sales_history/sh_create.sql');
    final populate = _f('sales_history/sh_populate.sql');
    if (create == null || populate == null) {
      markTestSkipped('Oracle SH dataset not present.');
      return;
    }
    final bridge = await Oci8Bridge.probe();
    if (bridge == null) {
      markTestSkipped('oci8 / real Oracle unavailable.');
      return;
    }
    final createUnits = splitOracleScript(create.readAsStringSync());
    final populateUnits = splitOracleScript(populate.readAsStringSync())
        .where((u) => !_load.hasMatch(u))
        .toList();

    final db = await Database.open(null);
    for (final u in createUnits) {
      try {
        await db.execute(u);
      } catch (_) {}
    }
    for (final u in populateUnits) {
      try {
        await db.execute(u);
      } catch (_) {}
    }

    const shDrop = [
      'DROP MATERIALIZED VIEW cal_month_sales_mv',
      'DROP MATERIALIZED VIEW fweek_pscat_sales_mv',
      'DROP TABLE costs CASCADE CONSTRAINTS',
      'DROP TABLE sales CASCADE CONSTRAINTS',
      'DROP TABLE supplementary_demographics CASCADE CONSTRAINTS',
      'DROP TABLE customers CASCADE CONSTRAINTS',
      'DROP TABLE countries CASCADE CONSTRAINTS',
      'DROP TABLE products CASCADE CONSTRAINTS',
      'DROP TABLE promotions CASCADE CONSTRAINTS',
      'DROP TABLE channels CASCADE CONSTRAINTS',
      'DROP TABLE times CASCADE CONSTRAINTS',
    ];
    final loadStmts = <Map<String, Object?>>[
      for (final d in shDrop)
        {
          'sql':
              "BEGIN EXECUTE IMMEDIATE '$d'; EXCEPTION WHEN OTHERS THEN NULL; END;",
          'query': false
        },
      for (final u in createUnits) {'sql': u, 'query': false},
      for (final u in populateUnits) {'sql': u, 'query': false},
      {'sql': 'COMMIT', 'query': false},
    ];
    await bridge.run(1521, loadStmts);

    final oraRes = await bridge
        .run(1521, [for (final q in _shBattery) {'sql': q, 'query': true}]);
    await _diff(db, _shBattery, oraRes);
  }, timeout: const Timeout(Duration(seconds: 90)));
}
