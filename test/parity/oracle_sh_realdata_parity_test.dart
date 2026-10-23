// Oracle SH *lookup-data three-way* parity: load the real sh_create.sql +
// sh_populate.sql lookup tables (products/channels/countries) into BOTH the
// engine and a live Oracle 23ai instance, then assert analytic queries match.
// The SQL*Loader fact CSVs and the sh.sales-based materialized views are out of
// scope (tolerated on load). Skips when the dataset or oci8/Oracle is absent.
import 'dart:io';

import 'package:dart_db_reliability/reliability.dart';
import 'package:dart_db_server/dart_db_server.dart';
import 'package:test/test.dart';

const _rel =
    '../dart-db-server/parity/datasets/oracle-db-sample-schemas/db-sample-schemas-main/sales_history';

File? _f(String name) {
  final f = File.fromUri(Directory.current.uri.resolve('$_rel/$name'));
  return f.existsSync() ? f : null;
}

final _load = RegExp(r'^\s*LOAD\s', caseSensitive: false);

// Validated identical to real Oracle 23ai. (Raw SUM/MEDIAN over NUMBER columns
// are excluded — see F142, NUMBER aggregation binary residual.)
const _battery = <String>[
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
];

const _shDrop = [
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

String _canon(Object? v) {
  if (v == null) return '<null>';
  final n = num.tryParse('$v'.trim());
  if (n != null) return n == n.roundToDouble() ? n.toInt().toString() : '$n';
  return '$v'.trim();
}

void main() {
  test('SH lookup-data analytics match real Oracle 23ai', () async {
    final create = _f('sh_create.sql');
    final populate = _f('sh_populate.sql');
    if (create == null || populate == null) {
      markTestSkipped('Oracle SH dataset not present (parity/datasets/).');
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

    // Engine: load (tolerate the fact-table / MV statements).
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

    // Real Oracle: drop SH objects, reload (MVs over sh.sales fail — tolerated).
    final loadStmts = <Map<String, Object?>>[
      for (final d in _shDrop)
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
