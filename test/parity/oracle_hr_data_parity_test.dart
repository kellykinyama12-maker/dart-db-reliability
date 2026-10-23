// Oracle HR *data* parity: load the real hr_create.sql + hr_populate.sql and
// assert the full HR dataset lands. Exercises TO_DATE hire-dates, the circular-
// FK disable/load/enable flow, ALTER SESSION/COMMIT directives, and anonymous
// PL/SQL blocks. Auto-skips when the dataset is absent.
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

void main() {
  test('HR create + populate loads the full dataset (TO_DATE + deferred FKs)',
      () async {
    final create = _f('hr_create.sql');
    final populate = _f('hr_populate.sql');
    if (create == null || populate == null) {
      markTestSkipped('Oracle HR dataset not present (parity/datasets/).');
      return;
    }
    final db = await Database.open(null);
    for (final u in splitOracleScript(create.readAsStringSync())) {
      try {
        await db.execute(u);
      } catch (_) {}
    }
    // Populate must apply cleanly end-to-end.
    for (final u in splitOracleScript(populate.readAsStringSync())) {
      await db.execute(u);
    }
    Future<int> count(String t) async =>
        ((await db.execute('SELECT COUNT(*) FROM $t')).rows.first.first as num)
            .toInt();

    // The full HR dataset.
    expect(await count('regions'), 5);
    expect(await count('countries'), 25);
    expect(await count('locations'), 23);
    expect(await count('departments'), 27);
    expect(await count('jobs'), 19);
    expect(await count('employees'), 107);
    expect(await count('job_history'), 10);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
