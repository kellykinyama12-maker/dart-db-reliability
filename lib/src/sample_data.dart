/// Loads real sample datasets (from the sibling engine repo's git-ignored
/// `parity/datasets/` tree) for data-driven differential testing. The
/// SQLite-compatible sakila port loads identically into both engines, so real
/// analytic queries can be diffed against SQLite as the oracle.
library;

import 'dart:io';

/// Resolves the first existing file among [relativePaths], each relative to the
/// engine repo's `parity/datasets/` directory. Returns null when absent so
/// suites can skip.
File? sampleDataFile(List<String> relativePaths) {
  final roots = <String>[
    '../dart-db-server/parity/datasets',
    '../../dart-db-server/parity/datasets',
    'parity/datasets',
  ];
  for (final root in roots) {
    if (!Directory(root).existsSync()) continue;
    for (final rel in relativePaths) {
      final f = File('$root/$rel');
      if (f.existsSync()) return f;
    }
  }
  return null;
}

/// Splits a SQL dump into statements, quote-aware so a `;` inside a string
/// literal (e.g. a film description) is not a boundary. Handles `--` line
/// comments and `/* … */` block comments.
List<String> splitSql(String input) {
  final out = <String>[];
  final buf = StringBuffer();
  var i = 0;
  final n = input.length;
  while (i < n) {
    final c = input[i];
    if (c == '-' && i + 1 < n && input[i + 1] == '-') {
      while (i < n && input[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && i + 1 < n && input[i + 1] == '*') {
      i += 2;
      while (i + 1 < n && !(input[i] == '*' && input[i + 1] == '/')) {
        i++;
      }
      i += 2;
      continue;
    }
    if (c == "'" || c == '"') {
      final q = c;
      buf.write(c);
      i++;
      while (i < n) {
        final d = input[i];
        buf.write(d);
        i++;
        if (d == q) {
          if (i < n && input[i] == q) {
            buf.write(input[i]);
            i++;
            continue;
          }
          break;
        }
      }
      continue;
    }
    if (c == ';') {
      final s = buf.toString().trim();
      if (s.isNotEmpty) out.add(s);
      buf.clear();
      i++;
      continue;
    }
    buf.write(c);
    i++;
  }
  final tail = buf.toString().trim();
  if (tail.isNotEmpty) out.add(tail);
  return out;
}
