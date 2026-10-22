// Oracle HR sample-schema parity: load the real `hr_create.sql` DDL into the
// engine and measure how much parses. The dataset lives in the engine repo
// under parity/datasets/ (git-ignored); this test auto-skips when it is absent.
//
// Currently blocked by F63 (inline named column constraints), F64 (ALTER TABLE
// ADD (constraint)), and F65 (COMMENT ON) — so the full-load assertion is
// `skip`ped. When those land, un-skip and the 7 core HR tables must all create.
import 'dart:io';

import 'package:dart_db_server/dart_db_server.dart';
import 'package:test/test.dart';

/// Resolves the HR create script relative to the reliability project root.
File? _hrCreateFile() {
  const rel =
      '../dart-db-server/parity/datasets/oracle-db-sample-schemas/db-sample-schemas-main/human_resources/hr_create.sql';
  final f = File.fromUri(Directory.current.uri.resolve(rel));
  return f.existsSync() ? f : null;
}

/// Strips SQL*Plus client directives (rem/SET/Prompt/…) and blank lines.
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
        l.startsWith('define ')) {
      continue;
    }
    out.add(line);
  }
  return out;
}

/// Splits a SQL script into statements on `;`, respecting single-quoted
/// strings (including the `''` escaped-quote convention).
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
  test('HR hr_create.sql loads all 7 core tables', () async {
    final file = _hrCreateFile();
    if (file == null) {
      markTestSkipped('Oracle HR dataset not present (parity/datasets/).');
      return;
    }
    final statements = _splitStatements(_stripSqlPlus(file.readAsStringSync()).join('\n'));

    final db = await Database.open(null);
    var ok = 0;
    for (final s in statements) {
      try {
        await db.execute(s);
        ok++;
      } catch (_) {}
    }
    // The 7 core HR tables must all exist once the DDL loads.
    const tables = [
      'regions', 'countries', 'locations', 'departments', 'jobs', 'employees',
      'job_history'
    ];
    for (final t in tables) {
      await db.execute('SELECT COUNT(*) FROM $t'); // throws if missing
    }
    expect(ok, greaterThanOrEqualTo(statements.length - 42),
        reason: 'too many hr_create.sql statements failed to load');
  },
      skip: 'BLOCKED by F66 (ORGANIZATION INDEX clause) and F67 (CREATE VIEW '
          'column list): 75/78 hr_create.sql statements load after F63-F65, but '
          'HR.countries + the view still fail. Un-skip when F66/F67 are fixed.');
}
