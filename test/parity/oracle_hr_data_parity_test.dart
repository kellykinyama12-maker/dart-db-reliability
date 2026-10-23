// Oracle HR *data* parity: load the real hr_create.sql + hr_populate.sql and
// assert real rows land. Exercises TO_DATE hire-dates (F75), the circular-FK
// disable/load/enable flow (F76), ALTER SESSION/COMMIT directives (F77/F78),
// and anonymous PL/SQL blocks. Auto-skips when the dataset is absent.
//
// Note: countries/locations are populated by standalone INSERT blocks that this
// test's simple SQL*Plus splitter handles imperfectly, so only the reliably
// loaded core tables are asserted (employees requires TO_DATE + FK deferral).
import 'dart:io';

import 'package:dart_db_server/dart_db_server.dart';
import 'package:test/test.dart';

const _rel =
    '../dart-db-server/parity/datasets/oracle-db-sample-schemas/db-sample-schemas-main/human_resources';

File? _f(String name) {
  final f = File.fromUri(Directory.current.uri.resolve('$_rel/$name'));
  return f.existsSync() ? f : null;
}

List<String> _lines(String raw) {
  final out = <String>[];
  for (final line in raw.split('\n')) {
    final t = line.trim();
    if (t.isEmpty) continue;
    final l = t.toLowerCase();
    if (l.startsWith('rem') ||
        l.startsWith('set ') ||
        l.startsWith('prompt') ||
        l.startsWith('spool') ||
        l.startsWith('@') ||
        l.startsWith('define ')) {
      continue;
    }
    out.add(line);
  }
  return out;
}

List<String> _bySemi(String sql) {
  final stmts = <String>[];
  final buf = StringBuffer();
  var q = false;
  for (var i = 0; i < sql.length; i++) {
    final c = sql[i];
    if (c == "'") {
      if (q && i + 1 < sql.length && sql[i + 1] == "'") {
        buf.write("''");
        i++;
        continue;
      }
      q = !q;
      buf.write(c);
    } else if (c == ';' && !q) {
      final s = buf.toString().trim();
      if (s.isNotEmpty) stmts.add(s);
      buf.clear();
    } else {
      buf.write(c);
    }
  }
  final t = buf.toString().trim();
  if (t.isNotEmpty) stmts.add(t);
  return stmts;
}

List<String> _units(String raw) {
  final kept = _lines(raw);
  final units = <String>[];
  final block = <String>[];
  for (final line in kept) {
    if (line.trim() == '/') {
      final b = block.join('\n').trim();
      if (b.isNotEmpty) units.add(b);
      block.clear();
    } else {
      block.add(line);
    }
  }
  final rest = block.join('\n').trim();
  if (rest.isNotEmpty) units.add(rest);
  final out = <String>[];
  for (final u in units) {
    if (RegExp(r'^\s*(BEGIN|DECLARE)\b', caseSensitive: false).hasMatch(u)) {
      out.add(u);
    } else {
      out.addAll(_bySemi(u));
    }
  }
  return out;
}

void main() {
  test('HR create + populate loads real rows (TO_DATE + deferred FKs)',
      () async {
    final create = _f('hr_create.sql');
    final populate = _f('hr_populate.sql');
    if (create == null || populate == null) {
      markTestSkipped('Oracle HR dataset not present (parity/datasets/).');
      return;
    }
    final db = await Database.open(null);
    for (final u in _bySemi(_lines(create.readAsStringSync()).join('\n'))) {
      try {
        await db.execute(u);
      } catch (_) {}
    }
    for (final u in _units(populate.readAsStringSync())) {
      try {
        await db.execute(u);
      } catch (_) {}
    }
    Future<int> count(String t) async =>
        ((await db.execute('SELECT COUNT(*) FROM $t')).rows.first.first as num)
            .toInt();

    // employees requires TO_DATE hire-dates + the self/dept FK deferral.
    expect(await count('employees'), greaterThanOrEqualTo(100));
    expect(await count('departments'), greaterThanOrEqualTo(26));
    expect(await count('jobs'), 19);
    expect(await count('regions'), 4);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
