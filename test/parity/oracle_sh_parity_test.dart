// Oracle SH (sales history) sample-schema parity: load the real `sh_create.sql`
// DDL and measure how much parses. Dataset lives in the engine repo under
// parity/datasets/ (git-ignored); auto-skips when absent.
//
// Currently 96/100 statements load; blocked only by F68 (PARTITION BY) and F69
// (CREATE MATERIALIZED VIEW). Un-skip when those land.
import 'dart:io';

import 'package:dart_db_server/dart_db_server.dart';
import 'package:test/test.dart';

File? _shCreateFile() {
  const rel =
      '../dart-db-server/parity/datasets/oracle-db-sample-schemas/db-sample-schemas-main/sales_history/sh_create.sql';
  final f = File.fromUri(Directory.current.uri.resolve(rel));
  return f.existsSync() ? f : null;
}

List<String> _stripSqlPlus(String raw) {
  final out = <String>[];
  for (final line in raw.split('\n')) {
    final t = line.trim();
    if (t.isEmpty || t == '/') continue;
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

List<String> _splitStatements(String sql) {
  final stmts = <String>[];
  final buf = StringBuffer();
  var inStr = false;
  for (var i = 0; i < sql.length; i++) {
    final c = sql[i];
    if (c == "'") {
      if (inStr && i + 1 < sql.length && sql[i + 1] == "'") {
        buf.write("''");
        i++;
        continue;
      }
      inStr = !inStr;
      buf.write(c);
    } else if (c == ';' && !inStr) {
      final s = buf.toString().trim();
      if (s.isNotEmpty) stmts.add(s);
      buf.clear();
    } else {
      buf.write(c);
    }
  }
  final tail = buf.toString().trim();
  if (tail.isNotEmpty) stmts.add(tail);
  return stmts;
}

void main() {
  test('SH sh_create.sql loads its core tables', () async {
    final file = _shCreateFile();
    if (file == null) {
      markTestSkipped('Oracle SH dataset not present (parity/datasets/).');
      return;
    }
    final statements =
        _splitStatements(_stripSqlPlus(file.readAsStringSync()).join('\n'));
    final db = await Database.open(null);
    var ok = 0;
    for (final s in statements) {
      try {
        await db.execute(s);
        ok++;
      } catch (_) {}
    }
    for (final t in ['times', 'channels', 'promotions', 'products', 'customers',
      'countries', 'sales', 'costs']) {
      await db.execute('SELECT COUNT(*) FROM $t'); // throws if missing
    }
    expect(ok, greaterThanOrEqualTo(statements.length - 2));
  });
}
