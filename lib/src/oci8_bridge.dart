/// Bridge to the real Oracle thick client ("Gun 3") via the PHP `oci8`
/// extension + Oracle Instant Client. Spawns [runnerScript] with a JSON request
/// on stdin and parses its JSON response.
///
/// The bridge self-detects: if `php` or the `oci8` extension (or Instant
/// Client) is unavailable, [probe] reports it so the triple-threat match can
/// skip Gun 3 instead of failing.
library;

import 'dart:convert';
import 'dart:io';

/// One statement outcome from the real `oci8` client.
class Oci8Result {
  Oci8Result.query(this.columns, this.rows)
      : affected = 0,
        isQuery = true,
        error = null;
  Oci8Result.dml(this.affected)
      : columns = const [],
        rows = const [],
        isQuery = false,
        error = null;
  Oci8Result.failed(this.error)
      : columns = const [],
        rows = const [],
        affected = 0,
        isQuery = false;

  final List<String> columns;
  final List<List<Object?>> rows;
  final int affected;
  final bool isQuery;
  final String? error;

  bool get ok => error == null;
}

class Oci8Bridge {
  Oci8Bridge._(this._runnerScript);

  final String _runnerScript;

  /// Resolves the bridge if `php`, the `oci8` extension, and the runner script
  /// are all present. Returns `null` (with a reason on stderr) otherwise, so
  /// callers can skip Gun 3 gracefully.
  static Future<Oci8Bridge?> probe({String runnerScript = 'tool/oci8_exec.php'}) async {
    if (!File(runnerScript).existsSync()) return null;
    try {
      final r = await Process.run(
          'php', ['-r', "echo extension_loaded('oci8') ? '1' : '0';"]);
      if (r.exitCode != 0 || '${r.stdout}'.trim() != '1') return null;
    } on ProcessException {
      return null; // php not on PATH
    }
    return Oci8Bridge._(runnerScript);
  }

  /// Runs [statements] (each `{sql, binds, query}`) in one `oci8` session
  /// against the Oracle wire server on [port]. Throws [StateError] if the
  /// connection itself fails; per-statement errors surface as
  /// [Oci8Result.error].
  Future<List<Oci8Result>> run(
    int port,
    List<Map<String, Object?>> statements, {
    String host = '127.0.0.1',
    String service = 'FREEPDB1',
    String user = 'native',
    String password = 'Secret123',
  }) async {
    final req = jsonEncode({
      'host': host,
      'port': port,
      'service': service,
      'user': user,
      'password': password,
      'statements': statements,
    });
    final proc = await Process.start('php', [_runnerScript]);
    proc.stdin.write(req);
    await proc.stdin.close();
    final out = await proc.stdout.transform(utf8.decoder).join();
    await proc.stderr.transform(utf8.decoder).join();
    await proc.exitCode;

    final decoded = jsonDecode(out.trim()) as Map<String, Object?>;
    if (decoded['ok'] != true) {
      throw StateError('oci8 connect failed: ${decoded['error']}');
    }
    final results = (decoded['results'] as List).cast<Map<String, Object?>>();
    return results.map((r) {
      if (r['error'] != null) return Oci8Result.failed('${r['error']}');
      if (r['query'] == true) {
        final cols = (r['columns'] as List).cast<String>();
        final rows = (r['rows'] as List)
            .map((row) => (row as List).cast<Object?>())
            .toList();
        return Oci8Result.query(cols, rows);
      }
      return Oci8Result.dml((r['affected'] as num).toInt());
    }).toList();
  }
}
