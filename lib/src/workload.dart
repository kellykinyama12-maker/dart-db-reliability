/// Deterministic pseudo-random workload generator for differential fuzzing.
/// Seeded so failures reproduce exactly. Generates a schema, bulk rows, and a
/// stream of SELECT statements that both engines must answer identically.
library;

import 'dart:math';

class Workload {
  Workload(int seed) : _rng = Random(seed);

  final Random _rng;

  int nextInt(int maxExclusive) => _rng.nextInt(maxExclusive);

  /// A canonical test table both engines accept, with mixed types and NULLs.
  static const String createTable = '''
CREATE TABLE t (
  id INTEGER PRIMARY KEY,
  grp INTEGER,
  amount REAL,
  qty INTEGER,
  label TEXT,
  flag INTEGER
)''';

  /// Generates [n] INSERT statements with deterministic, reproducible values
  /// including NULLs, negatives, and floating-point amounts.
  List<String> inserts(int n) {
    final labels = ['alpha', 'beta', 'gamma', 'delta', null];
    final out = <String>[];
    for (var i = 1; i <= n; i++) {
      final grp = _rng.nextInt(5);
      final amount = (_rng.nextDouble() * 2000 - 1000);
      final qty = _rng.nextBool() ? _rng.nextInt(100) : null;
      final label = labels[_rng.nextInt(labels.length)];
      final flag = _rng.nextInt(2);
      final amtStr = amount.toStringAsFixed(4);
      final qtyStr = qty?.toString() ?? 'NULL';
      final labelStr = label == null ? 'NULL' : "'$label'";
      out.add('INSERT INTO t (id, grp, amount, qty, label, flag) '
          'VALUES ($i, $grp, $amtStr, $qtyStr, $labelStr, $flag)');
    }
    return out;
  }

  /// A deterministic pool of read queries exercising filters, aggregates,
  /// grouping, ordering, DISTINCT, arithmetic and NULL handling. Every query
  /// has a total order so positional row comparison is stable.
  List<String> readQueries() => <String>[
        'SELECT id, grp, amount, qty, label, flag FROM t ORDER BY id',
        'SELECT grp, COUNT(*) FROM t GROUP BY grp ORDER BY grp',
        'SELECT grp, SUM(amount) FROM t GROUP BY grp ORDER BY grp',
        'SELECT grp, AVG(amount) FROM t GROUP BY grp ORDER BY grp',
        'SELECT grp, MIN(qty), MAX(qty) FROM t GROUP BY grp ORDER BY grp',
        'SELECT COUNT(qty), COUNT(*) FROM t',
        'SELECT grp, SUM(qty) FROM t GROUP BY grp ORDER BY grp',
        'SELECT id, amount FROM t WHERE amount > 0 ORDER BY id',
        'SELECT id FROM t WHERE qty IS NULL ORDER BY id',
        'SELECT id FROM t WHERE qty IS NOT NULL AND qty > 50 ORDER BY id',
        'SELECT DISTINCT label FROM t ORDER BY label',
        'SELECT label, COUNT(*) FROM t GROUP BY label ORDER BY label',
        'SELECT id, qty * 2 + 1 FROM t WHERE qty IS NOT NULL ORDER BY id',
        'SELECT id FROM t WHERE label LIKE \'a%\' ORDER BY id',
        'SELECT grp, COUNT(*) FROM t WHERE flag = 1 GROUP BY grp ORDER BY grp',
        'SELECT id FROM t ORDER BY amount DESC, id ASC LIMIT 10',
        'SELECT grp, SUM(amount) s FROM t GROUP BY grp HAVING SUM(amount) > 0 '
            'ORDER BY grp',
        'SELECT CASE WHEN qty IS NULL THEN -1 ELSE qty END c FROM t ORDER BY id',
        'SELECT id, label FROM t WHERE label IN (\'alpha\',\'beta\') ORDER BY id',
        'SELECT COUNT(DISTINCT grp) FROM t',
      ];
}
