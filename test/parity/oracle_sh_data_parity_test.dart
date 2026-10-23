// Oracle SH *lookup-table data* parity: load the real sh_create.sql +
// sh_populate.sql and assert the three INSERT-populated lookup tables land in
// full. Exercises the F79-F84 SH/OLAP DDL and the anonymous PL/SQL INSERT
// blocks. The fact tables (sales/costs/customers/times/promotions) are loaded
// via SQL*Loader CSVs (`LOAD … csv`), which is out of this harness's SQL scope,
// so those directives are skipped. Auto-skips when the dataset is absent.
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

// SQL*Loader DSL used by the sample-schema installer for the fact CSVs.
final _loadDirective = RegExp(r'^\s*LOAD\s', caseSensitive: false);

void main() {
  test('SH create + populate loads the lookup tables (channels/countries/products)',
      () async {
    final create = _f('sh_create.sql');
    final populate = _f('sh_populate.sql');
    if (create == null || populate == null) {
      markTestSkipped('Oracle SH dataset not present (parity/datasets/).');
      return;
    }
    final db = await Database.open(null);
    for (final u in splitOracleScript(create.readAsStringSync())) {
      try {
        await db.execute(u);
      } catch (_) {}
    }

    // Run the populate, skipping only the SQL*Loader fact-CSV directives.
    // Everything else — constraint toggles, PL/SQL INSERT blocks, and the
    // fact materialized-view bitmap indexes — must apply cleanly.
    final failures = <String>[];
    for (final u in splitOracleScript(populate.readAsStringSync())) {
      if (_loadDirective.hasMatch(u)) continue;
      try {
        await db.execute(u);
      } catch (e) {
        failures.add('${u.split('\n').first} -> $e');
      }
    }
    expect(failures, isEmpty,
        reason: 'populate failures:\n${failures.join('\n')}');

    Future<int> count(String t) async =>
        ((await db.execute('SELECT COUNT(*) FROM $t')).rows.first.first as num)
            .toInt();

    expect(await count('channels'), 5);
    expect(await count('countries'), 35);
    expect(await count('products'), 72);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
