/// Splits an Oracle SQL*Plus script into executable units.
///
/// Handles the two terminator conventions the sample schemas use: plain SQL
/// statements end at a top-level `;`, while PL/SQL blocks (`BEGIN … END;` /
/// `DECLARE … END;`) are terminated by a `/` on its own line and contain
/// internal `;`. SQL*Plus client directives (`rem`, `SET`, `Prompt`, `@…`,
/// `define`, `spool`) and blank lines are dropped.
library;

/// Returns the executable statements/blocks from [raw], in order.
List<String> splitOracleScript(String raw) {
  final kept = <String>[];
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
    kept.add(line);
  }

  final units = <String>[];
  final buf = StringBuffer();
  var inBlock = false; // inside a PL/SQL BEGIN…END / DECLARE…END block

  // A PL/SQL block starts when the pending text begins with BEGIN/DECLARE.
  final blockStart = RegExp(r'^\s*(BEGIN|DECLARE)\b', caseSensitive: false);

  // Emits each top-level `;`-terminated statement from buf; keeps the tail.
  void flushSqlStatements() {
    final text = buf.toString();
    var start = 0;
    var inStr = false;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (c == "'") {
        if (inStr && i + 1 < text.length && text[i + 1] == "'") {
          i++;
          continue;
        }
        inStr = !inStr;
      } else if (c == ';' && !inStr) {
        final s = text.substring(start, i).trim();
        if (s.isNotEmpty) units.add(s);
        start = i + 1;
      }
    }
    final rest = text.substring(start);
    buf
      ..clear()
      ..write(rest);
  }

  for (final line in kept) {
    final trimmed = line.trim();
    if (inBlock) {
      if (trimmed == '/') {
        final unit = buf.toString().trim();
        if (unit.isNotEmpty) units.add(unit);
        buf.clear();
        inBlock = false;
      } else {
        buf
          ..write(line)
          ..write('\n');
      }
      continue;
    }
    if (trimmed == '/') {
      // Slash outside a block flushes any buffered text as one unit.
      final unit = buf.toString().trim();
      if (unit.isNotEmpty) units.add(unit);
      buf.clear();
      continue;
    }
    buf
      ..write(line)
      ..write('\n');
    if (blockStart.hasMatch(buf.toString())) {
      inBlock = true;
      continue;
    }
    flushSqlStatements();
    // A block may start right after a flushed statement (`INSERT …; BEGIN …`).
    if (blockStart.hasMatch(buf.toString())) inBlock = true;
  }
  final tail = buf.toString().trim();
  if (tail.isNotEmpty) units.add(tail);
  return units;
}
