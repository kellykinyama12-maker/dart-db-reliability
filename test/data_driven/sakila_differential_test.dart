/// Data-driven differential test against the real **sakila** sample database
/// (SQLite-compatible port). Loads the identical schema + 47k rows into both
/// dart_db_server and SQLite, confirms row-count parity per table, then diffs a
/// battery of real analytic queries. Bugs found here come from *real* data, not
/// synthetic fixtures. Skips when the dataset or sqlite3 is unavailable.
@Timeout(Duration(minutes: 4))
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  final schema = sampleDataFile([
    'mysql-sakila/sakila-main/sqlite-sakila-db/sqlite-sakila-schema.sql',
  ]);
  final data = sampleDataFile([
    'mysql-sakila/sakila-main/sqlite-sakila-db/sqlite-sakila-insert-data.sql',
  ]);

  group('sakila data-driven differential', () {
    late DiffOracle o;
    late List<String> tables;

    setUpAll(() async {
      o = await DiffOracle.open();
      // Strip ALL foreign-key clauses (named or not, incl. ON DELETE/UPDATE)
      // so the FK-parse gap (F21) and FK-enforcement gap (F22) don't block the
      // load — FK constraints are irrelevant to read-only analytic queries.
      // Also rewrite named UNIQUE/PK and the port's `BLOB SUB_TYPE TEXT`.
      String sanitize(String sql) => sql
          .replaceAll(
              RegExp(
                  r',?\s*(CONSTRAINT\s+\w+\s+)?FOREIGN\s+KEY\s*\([^)]*\)\s*'
                  r'REFERENCES\s+\w+\s*\([^)]*\)'
                  r'(\s+ON\s+(DELETE|UPDATE)\s+'
                  r'(NO\s+ACTION|CASCADE|SET\s+NULL|RESTRICT))*',
                  caseSensitive: false),
              '')
          .replaceAll(
              RegExp(r'CONSTRAINT\s+\w+\s+UNIQUE', caseSensitive: false),
              'UNIQUE')
          .replaceAll(
              RegExp(r'CONSTRAINT\s+\w+\s+PRIMARY\s+KEY', caseSensitive: false),
              'PRIMARY KEY')
          .replaceAll(
              RegExp(r'BLOB\s+SUB_TYPE\s+TEXT', caseSensitive: false), 'TEXT')
          // tidy any dangling comma a stripped clause left before the `)`
          .replaceAll(RegExp(r',(\s*)\)'), r')');

      final schemaStmts = splitSql(sanitize(schema!.readAsStringSync()))
          .where((s) => s.toUpperCase().startsWith('CREATE TABLE'));
      for (final stmt in schemaStmts) {
        try {
          await o.ours.execute(stmt);
        } catch (_) {}
        try {
          o.ref.execute(stmt);
        } catch (_) {}
      }
      final dataStmts = splitSql(data!.readAsStringSync())
          .where((s) => s.toUpperCase().startsWith('INSERT'));
      for (final stmt in dataStmts) {
        try {
          await o.ours.execute(stmt);
        } catch (_) {}
        try {
          o.ref.execute(stmt);
        } catch (_) {}
      }
      tables = o.ref
          .select("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
          .rows
          .map((r) => '${r.first}')
          .toList();
    });

    tearDownAll(() => o.close());

    test('both engines loaded the same tables with the same row counts',
        () async {
      expect(tables, isNotEmpty, reason: 'sakila schema should have loaded');
      for (final t in tables) {
        await o.expectSameRows('SELECT COUNT(*) FROM $t',
            reason: 'row-count parity for table $t');
      }
    });

    // Real analytic queries an app would run against sakila.
    final analytics = <String>[
      // top customers by payment
      'SELECT customer_id, COUNT(*), SUM(amount) FROM payment '
          'GROUP BY customer_id ORDER BY SUM(amount) DESC, customer_id LIMIT 20',
      // films per category
      'SELECT c.name, COUNT(*) FROM film_category fc '
          'JOIN category c ON fc.category_id = c.category_id '
          'GROUP BY c.name ORDER BY c.name',
      // actor film counts
      'SELECT a.actor_id, a.last_name, COUNT(*) n FROM actor a '
          'JOIN film_actor fa ON a.actor_id = fa.actor_id '
          'GROUP BY a.actor_id, a.last_name ORDER BY n DESC, a.actor_id LIMIT 25',
      // rentals by rating
      'SELECT f.rating, COUNT(*) FROM film f '
          'JOIN inventory i ON f.film_id = i.film_id '
          'JOIN rental r ON i.inventory_id = r.inventory_id '
          'GROUP BY f.rating ORDER BY f.rating',
      // average payment per staff
      'SELECT staff_id, COUNT(*), ROUND(AVG(amount), 2) FROM payment '
          'GROUP BY staff_id ORDER BY staff_id',
      // films never rented (NOT IN over a non-NULL key)
      'SELECT COUNT(*) FROM film WHERE film_id NOT IN '
          '(SELECT i.film_id FROM inventory i)',
      // customers with above-average total payments (correlated-ish via subquery)
      'SELECT COUNT(*) FROM (SELECT customer_id, SUM(amount) s FROM payment '
          'GROUP BY customer_id) WHERE s > (SELECT AVG(amount)*20 FROM payment)',
      // distinct rental durations
      'SELECT rental_duration, COUNT(*) FROM film '
          'GROUP BY rental_duration ORDER BY rental_duration',
      // payment totals by month
      "SELECT strftime('%Y-%m', payment_date) ym, COUNT(*), SUM(amount) "
          'FROM payment GROUP BY ym ORDER BY ym',
      // length buckets
      'SELECT CASE WHEN length < 60 THEN \'short\' WHEN length < 120 THEN \'mid\' '
          'ELSE \'long\' END bucket, COUNT(*) FROM film GROUP BY bucket ORDER BY bucket',
      // multi-join with filter
      'SELECT co.country, COUNT(*) FROM customer cu '
          'JOIN address a ON cu.address_id = a.address_id '
          'JOIN city ci ON a.city_id = ci.city_id '
          'JOIN country co ON ci.country_id = co.country_id '
          'GROUP BY co.country ORDER BY COUNT(*) DESC, co.country LIMIT 20',
    ];

    for (final q in analytics) {
      test('analytic: ${q.substring(0, q.length.clamp(0, 60))}…',
          () => o.expectSameRows(q));
    }
  },
      skip: (sqliteSkipReason() != null)
          ? sqliteSkipReason()
          : (schema == null || data == null)
              ? 'sakila SQLite dataset not downloaded (see parity/test-data.md)'
              : null);
}
