/// Aggressive random SQL generator for differential fuzzing. Produces a random
/// schema, random rows, and a stream of random SELECTs (expressions, predicates,
/// aggregates, grouping, joins) that both engines must answer identically.
/// Seeded for exact reproduction of any divergence.
///
/// The generator is **type-aware**: numeric expressions only combine numeric
/// operands and text expressions only combine text operands. This avoids the
/// already-catalogued text↔number coercion divergence so the fuzzer explores
/// *deeper* logic rather than re-reporting the same class forever.
library;

import 'dart:math';

enum _Ty { num_, text }

class SqlFuzzer {
  SqlFuzzer(this.seed) : _r = Random(seed);

  final int seed;
  final Random _r;

  static const tableA = 'a';
  static const tableB = 'b';
  final List<String> _numCols = ['i1', 'i2', 'r1'];
  final List<String> _textCols = ['t1'];
  List<String> get _allCols => [..._numCols, ..._textCols];

  List<String> schema() => [
        'CREATE TABLE a (id INTEGER PRIMARY KEY, i1 INTEGER, i2 INTEGER, '
            'r1 REAL, t1 TEXT)',
        'CREATE TABLE b (id INTEGER PRIMARY KEY, i1 INTEGER, i2 INTEGER, '
            'r1 REAL, t1 TEXT)',
      ];

  List<String> rows(String table, int n) {
    final words = ['apple', 'Banana', 'cherry', '', 'date', 'Egg'];
    final out = <String>[];
    for (var i = 1; i <= n; i++) {
      out.add('INSERT INTO $table (id, i1, i2, r1, t1) VALUES '
          '($i, ${_intOrNull(50)}, ${_intOrNull(10)}, ${_realOrNull()}, '
          '${_textOrNull(words)})');
    }
    return out;
  }

  String _intOrNull(int bound) =>
      _r.nextInt(6) == 0 ? 'NULL' : '${_r.nextInt(bound * 2) - bound}';

  String _realOrNull() => _r.nextInt(6) == 0
      ? 'NULL'
      : (_r.nextDouble() * 200 - 100).toStringAsFixed(3);

  String _textOrNull(List<String> words) =>
      _r.nextInt(6) == 0 ? 'NULL' : "'${words[_r.nextInt(words.length)]}'";

  String _numLit() => _r.nextBool()
      ? '${_r.nextInt(20) - 10}'
      : (_r.nextDouble() * 20 - 10).toStringAsFixed(2);

  String _textLit() => "'${['apple', 'x', '', 'Egg'][_r.nextInt(4)]}'";

  /// A random scalar expression of type [ty] over [prefix]-qualified columns.
  String _expr(_Ty ty, String prefix, int depth) {
    final numCols = _numCols.map((c) => '$prefix$c').toList();
    final textCols = _textCols.map((c) => '$prefix$c').toList();
    if (depth <= 0 || _r.nextInt(3) == 0) {
      if (ty == _Ty.num_) {
        return _r.nextBool() ? numCols[_r.nextInt(numCols.length)] : _numLit();
      }
      return _r.nextBool() ? textCols[_r.nextInt(textCols.length)] : _textLit();
    }
    if (ty == _Ty.num_) {
      switch (_r.nextInt(7)) {
        case 0:
          return '(${_expr(_Ty.num_, prefix, depth - 1)} + '
              '${_expr(_Ty.num_, prefix, depth - 1)})';
        case 1:
          return '(${_expr(_Ty.num_, prefix, depth - 1)} - '
              '${_expr(_Ty.num_, prefix, depth - 1)})';
        case 2:
          return '(${_expr(_Ty.num_, prefix, depth - 1)} * '
              '${_expr(_Ty.num_, prefix, depth - 1)})';
        case 3:
          return 'ABS(${_expr(_Ty.num_, prefix, depth - 1)})';
        case 4:
          return 'COALESCE(${_expr(_Ty.num_, prefix, depth - 1)}, '
              '${_expr(_Ty.num_, prefix, depth - 1)})';
        case 5:
          return 'LENGTH(${_expr(_Ty.text, prefix, depth - 1)})';
        default:
          return 'CASE WHEN ${_pred(prefix, depth - 1)} THEN '
              '${_expr(_Ty.num_, prefix, depth - 1)} ELSE '
              '${_expr(_Ty.num_, prefix, depth - 1)} END';
      }
    }
    switch (_r.nextInt(4)) {
      case 0:
        return 'UPPER(${_expr(_Ty.text, prefix, depth - 1)})';
      case 1:
        return 'LOWER(${_expr(_Ty.text, prefix, depth - 1)})';
      case 2:
        return 'COALESCE(${_expr(_Ty.text, prefix, depth - 1)}, '
            '${_expr(_Ty.text, prefix, depth - 1)})';
      default:
        return '(${_expr(_Ty.text, prefix, depth - 1)} || '
            '${_expr(_Ty.text, prefix, depth - 1)})';
    }
  }

  /// A random boolean predicate; operands are same-typed.
  String _pred(String prefix, int depth) {
    if (depth <= 0 || _r.nextInt(3) == 0) {
      final ty = _r.nextBool() ? _Ty.num_ : _Ty.text;
      final cols = (ty == _Ty.num_ ? _numCols : _textCols);
      final c = '$prefix${cols[_r.nextInt(cols.length)]}';
      switch (_r.nextInt(7)) {
        case 0:
          return '$c IS NULL';
        case 1:
          return '$c IS NOT NULL';
        case 2:
          return ty == _Ty.num_ ? '$c = ${_numLit()}' : '$c = ${_textLit()}';
        case 3:
          return ty == _Ty.num_ ? '$c <> ${_numLit()}' : '$c <> ${_textLit()}';
        case 4:
          return ty == _Ty.num_ ? '$c > ${_numLit()}' : '$c > ${_textLit()}';
        case 5:
          return ty == _Ty.num_
              ? '$c BETWEEN ${_r.nextInt(10) - 10} AND ${_r.nextInt(10)}'
              : "$c LIKE '%a%'";
        default:
          return ty == _Ty.num_
              ? '$c IN (${_r.nextInt(10)}, ${_r.nextInt(10)}, NULL)'
              : "$c IN ('apple','x',NULL)";
      }
    }
    switch (_r.nextInt(4)) {
      case 0:
        return '(${_pred(prefix, depth - 1)} AND ${_pred(prefix, depth - 1)})';
      case 1:
        return '(${_pred(prefix, depth - 1)} OR ${_pred(prefix, depth - 1)})';
      case 2:
        return 'NOT (${_pred(prefix, depth - 1)})';
      default:
        return '${_expr(_Ty.num_, prefix, depth - 1)} > '
            '${_expr(_Ty.num_, prefix, depth - 1)}';
    }
  }

  String query() {
    switch (_r.nextInt(4)) {
      case 0:
        return _projectionQuery();
      case 1:
        return _aggregateQuery();
      case 2:
        return _groupedQuery();
      default:
        return _joinQuery();
    }
  }

  /// A random predicate suitable for a top-level WHERE (unqualified columns).
  String predicate() => _pred('', 2);

  String _projectionQuery() {
    final e1 = _expr(_Ty.num_, '', 2);
    final e2 = _expr(_r.nextBool() ? _Ty.num_ : _Ty.text, '', 2);
    final where = _r.nextBool() ? 'WHERE ${_pred('', 2)} ' : '';
    final limit = _r.nextBool() ? 'LIMIT ${_r.nextInt(20)}' : '';
    return 'SELECT id, $e1, $e2 FROM a ${where}ORDER BY id $limit';
  }

  String _aggregateQuery() {
    final col = _numCols[_r.nextInt(_numCols.length)];
    final agg = ['COUNT', 'SUM', 'AVG', 'MIN', 'MAX', 'TOTAL'][_r.nextInt(6)];
    final where = _r.nextBool() ? 'WHERE ${_pred('', 2)} ' : '';
    return 'SELECT $agg($col), COUNT(*) FROM a $where';
  }

  String _groupedQuery() {
    final g = _allCols[_r.nextInt(_allCols.length)];
    final col = _numCols[_r.nextInt(_numCols.length)];
    final agg = ['COUNT', 'SUM', 'AVG', 'MIN', 'MAX'][_r.nextInt(5)];
    final having = _r.nextBool() ? 'HAVING $agg($col) IS NOT NULL ' : '';
    return 'SELECT $g, $agg($col) FROM a GROUP BY $g ${having}ORDER BY $g';
  }

  String _joinQuery() {
    final jt = ['JOIN', 'LEFT JOIN'][_r.nextInt(2)];
    final lc = _numCols[_r.nextInt(_numCols.length)];
    final rc = _numCols[_r.nextInt(_numCols.length)];
    final where = _r.nextBool() ? 'WHERE ${_pred('a.', 1)} ' : '';
    return 'SELECT a.id, b.id FROM a $jt b ON a.$lc = b.$rc '
        '${where}ORDER BY a.id, b.id';
  }
}
