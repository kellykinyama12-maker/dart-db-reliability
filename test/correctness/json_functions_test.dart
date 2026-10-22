/// JSON function correctness vs SQLite's json1: json_extract, ->/->> operators,
/// json_array / json_object, json_type, json_valid, json_array_length. The
/// engine advertises a JSON function family; this checks it against SQLite.
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  group('JSON functions vs sqlite', () {
    late DiffOracle o;
    setUp(() async {
      o = await DiffOracle.open();
      await o.exec('CREATE TABLE j (id INTEGER PRIMARY KEY, doc TEXT)');
      await o.exec('INSERT INTO j VALUES '
          '(1, \'{"name":"Ada","age":36,"tags":["a","b"]}\'), '
          '(2, \'{"name":"Alan","age":41,"tags":[]}\'), '
          '(3, \'{"name":"Grace","nested":{"x":1,"y":2}}\')');
    });
    tearDown(() => o.close());

    final queries = <String>[
      "SELECT id, json_extract(doc, '\$.name') FROM j ORDER BY id",
      "SELECT id, json_extract(doc, '\$.age') FROM j ORDER BY id",
      "SELECT id, json_extract(doc, '\$.tags[0]') FROM j ORDER BY id",
      "SELECT id, json_extract(doc, '\$.nested.x') FROM j ORDER BY id",
      "SELECT id, json_array_length(doc, '\$.tags') FROM j WHERE id IN (1,2) "
          'ORDER BY id',
      "SELECT id, json_type(doc, '\$.age') FROM j WHERE id IN (1,2) ORDER BY id",
      "SELECT id, json_type(doc, '\$.tags') FROM j WHERE id IN (1,2) ORDER BY id",
      "SELECT json_valid('{\"a\":1}'), json_valid('not json')",
      "SELECT json_array(1, 2, 'three', NULL)",
      "SELECT json_object('k', 'v', 'n', 42)",
      "SELECT json_extract('[10,20,30]', '\$[1]')",
      "SELECT id FROM j WHERE json_extract(doc, '\$.age') > 38 ORDER BY id",
      "SELECT id, json_extract(doc, '\$.age') + 1 FROM j WHERE id IN (1,2) "
          'ORDER BY id',
    ];

    for (final q in queries) {
      test(q.substring(0, q.length.clamp(0, 55)), () => o.expectSameRows(q));
    }
  }, skip: sqliteSkipReason());
}
