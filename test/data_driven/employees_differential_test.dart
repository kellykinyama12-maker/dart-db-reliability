/// Data-driven differential against the real MySQL **employees** (`test_db`)
/// dataset. Loads the 300k-row `employees` table and `departments` into both
/// dart_db_server and SQLite (ENUM→TEXT, FK stripped per F21/F22) and diffs real
/// aggregate analytics. The multi-million-row salary/junction dumps are skipped
/// to keep the run fast. Skips when the dataset or sqlite3 is unavailable.
@Timeout(Duration(minutes: 5))
library;

import 'package:dart_db_reliability/reliability.dart';
import 'package:test/test.dart';

void main() {
  const base = 'mysql-employees/test_db-master';
  final schema = sampleDataFile(['$base/employees.sql']);
  final depts = sampleDataFile(['$base/load_departments.dump']);
  final emps = sampleDataFile(['$base/load_employees.dump']);

  group('employees data-driven differential', () {
    late DiffOracle o;
    late List<String> tables;

    setUpAll(() async {
      o = await DiffOracle.open();
      // Portable CREATE TABLE for just the two tables we load (the dump files
      // carry the data). Avoids ENUM / FK (F21/F22) and SQL*plucked DDL.
      const ddl = <String>[
        'CREATE TABLE departments (dept_no CHAR(4) NOT NULL, '
            'dept_name VARCHAR(40) NOT NULL, PRIMARY KEY (dept_no))',
        'CREATE TABLE employees (emp_no INTEGER NOT NULL, birth_date DATE NOT NULL, '
            'first_name VARCHAR(14) NOT NULL, last_name VARCHAR(16) NOT NULL, '
            'gender TEXT NOT NULL, hire_date DATE NOT NULL, PRIMARY KEY (emp_no))',
      ];
      for (final c in ddl) {
        try { await o.ours.execute(c); } catch (_) {}
        try { o.ref.execute(c); } catch (_) {}
      }
      for (final f in [depts!, emps!]) {
        for (final stmt in splitSql(f.readAsStringSync())) {
          if (!stmt.toUpperCase().startsWith('INSERT')) continue;
          try { await o.ours.execute(stmt); } catch (_) {}
          try { o.ref.execute(stmt); } catch (_) {}
        }
      }
      tables = ['departments', 'employees'];
    });

    tearDownAll(() => o.close());

    test('row-count parity', () async {
      for (final t in tables) {
        await o.expectSameRows('SELECT COUNT(*) FROM $t',
            reason: 'row-count parity for $t');
      }
    });

    final analytics = <String>[
      'SELECT gender, COUNT(*) FROM employees GROUP BY gender ORDER BY gender',
      "SELECT strftime('%Y', hire_date) y, COUNT(*) FROM employees "
          'GROUP BY y ORDER BY y',
      "SELECT substr(last_name,1,1) ini, COUNT(*) FROM employees "
          'GROUP BY ini ORDER BY ini',
      'SELECT MIN(hire_date), MAX(hire_date) FROM employees',
      'SELECT MIN(birth_date), MAX(birth_date) FROM employees',
      "SELECT CASE WHEN birth_date < '1955-01-01' THEN 'pre55' "
          "WHEN birth_date < '1960-01-01' THEN '55-59' ELSE '60plus' END b, "
          'COUNT(*) FROM employees GROUP BY b ORDER BY b',
      'SELECT COUNT(DISTINCT first_name) FROM employees',
      'SELECT first_name, COUNT(*) c FROM employees '
          'GROUP BY first_name ORDER BY c DESC, first_name LIMIT 20',
      "SELECT gender, strftime('%Y', hire_date) y, COUNT(*) FROM employees "
          'GROUP BY gender, y ORDER BY gender, y',
      'SELECT COUNT(*) FROM employees WHERE last_name LIKE \'S%\'',
      'SELECT dept_no, dept_name FROM departments ORDER BY dept_no',
    ];

    for (final q in analytics) {
      test('analytic: ${q.substring(0, q.length.clamp(0, 55))}…',
          () => o.expectSameRows(q));
    }
  },
      skip: (sqliteSkipReason() != null)
          ? sqliteSkipReason()
          : (schema == null || depts == null || emps == null)
              ? 'employees dataset not downloaded (see parity/test-data.md)'
              : null);
}
