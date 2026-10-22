# Reliability findings — dart_db_server

Issues surfaced by the reliability harness. Each is reproduced by a test in this
project. **Data-integrity bugs** are the most severe (the engine silently
accepts invalid data). Dialect differences are *not* bugs — they are recorded so
the differential suite stays honest.

Run date: 2026-10-21 · Engine: `dart_db_server` 0.1.5 (path dep)

## Status update — 2026-10-22

**24 bugs found; F1–F22 fixed & verified; F23–F24 open (newly found).**
The first 22 are closed (every repro runs live and passes; fuzzer 0 divergences;
crash recovery 3/3; sakila + employees real-data differentials match SQLite).
Continued hunting surfaced two more:
- **F23** — the `COLLATE` operator (`COLLATE NOCASE`/`BINARY`) fails to parse in
  WHERE / ORDER BY / DISTINCT.
- **F24** — window functions (`RANK`/`ROW_NUMBER`/…) throw `Unknown function`
  in any query that also has `GROUP BY`.

**Two more found continuing the hunt (open):**
- **F25** — parenthesized row-value/tuple expressions `(a, b) = (…)` / `IN` are
  not parsed.
- **F26** — `CREATE TABLE <t> AS SELECT …` (CTAS) is not supported.

**One more from JSON (open):**
- **F27** — JSON path functions on a missing path return wrong values
  (`json_type` → `'null'` string, `json_array_length` → `0`) instead of SQL NULL.

**Two more from numeric edges (open):**
- **F28** — int64 overflow wraps silently (`MAX + 1` → negative) instead of
  promoting to float like SQLite.
- **F29** — scientific-notation literals are mis-lexed: `1e3` → `1` (exponent
  dropped), silently wrong with no error.

**One more from the lexer (open):**
- **F30** — hex integer literals `0x1F` → `0` (the `x1F` swallowed as an alias),
  silently wrong; parse error inside an expression. Minor relatives: `5.`
  (trailing-dot) and the SQLite `==` operator also unparsed.

**Tally: 30 found, F1–F22 fixed, F23–F30 open.**

_Historical detail of each bug is preserved below for the record._

## Summary

**22 bugs found to date** (F1–F22). F1–F18 fixed & verified; **F19–F22 open.**
Each has a minimal reproducible test. Suite status: `dart run bin/scorecard.dart`.

| Category | Bugs |
| --- | --- |
| Durability (critical) | F15 persistence not crash-atomic *(fixed)* |
| Three-valued logic | F7 *(fixed)* · **F20 NOT IN w/ NULL (open)** |
| Float semantics | **F19 `0 > -0.0` is TRUE (open)** |
| DDL / schema loading | **F21 named FK/UNIQUE/PK constraints (open)** · **F22 FK vs PRAGMA/forward-ref (open)** |
| Data integrity / atomicity | F1/F2/F10/F14 *(fixed)* |
| Correctness | F3/F4/F9/F13/F16/F17 *(fixed)* |
| Internal exception leaks | F6/F11/F12 *(fixed)* |
| Parity gaps | F5/F8/F18 *(fixed)* |

Dialect differences (not bugs) are catalogued at the end (D1–D5).

---

## Confirmed engine bugs

### F1 · CHECK constraint not enforced on UPDATE
- **Severity:** High (silent data corruption).
- **Repro:**
  ```sql
  CREATE TABLE t (id INTEGER PRIMARY KEY, age INTEGER CHECK (age >= 0));
  INSERT INTO t VALUES (1, 20);     -- ok
  INSERT INTO t VALUES (2, -5);     -- correctly rejected
  UPDATE t SET age = -1 WHERE id=1; -- WRONGLY ACCEPTED → age becomes -1
  ```
- **Expected:** the `UPDATE` violates `CHECK (age >= 0)` and must be rejected.
- **Actual:** the row is updated to `-1`. CHECK is evaluated on INSERT but not on
  UPDATE.
- **Test:** `constraints/constraints_test.dart` → *CHECK constraint enforced on
  UPDATE* (skipped as `KNOWN ENGINE BUG`).

### F2 · Composite PRIMARY KEY does not enforce uniqueness
- **Severity:** High (duplicate primary keys).
- **Repro:**
  ```sql
  CREATE TABLE t (a INTEGER, b INTEGER, PRIMARY KEY (a, b));
  INSERT INTO t VALUES (1, 1);  -- ok
  INSERT INTO t VALUES (1, 2);  -- ok
  INSERT INTO t VALUES (1, 1);  -- WRONGLY ACCEPTED → duplicate composite PK
  ```
- **Expected:** the second `(1, 1)` violates the composite primary key and must
  be rejected.
- **Actual:** the duplicate row is inserted.
- **Test:** `constraints/constraints_test.dart` → *composite PRIMARY KEY
  uniqueness* (skipped as `KNOWN ENGINE BUG`).

### F3 · Date month-underflow does not decrement the year
- **Severity:** High (wrong date arithmetic).
- **Repro:** `SELECT date('2021-01-01', '-1 month')`.
- **Expected:** `2020-12-01`. **Actual:** `2021-12-01` (month wrapped Jan→Dec
  but the year stayed 2021).
- **Test:** `known_issues/known_engine_bugs_test.dart` → F3.

### F4 · Correlated subquery binds outer reference to inner table on name clash
- **Severity:** High (wrong results, silent).
- **Repro:**
  ```sql
  CREATE TABLE s (id INTEGER PRIMARY KEY, g TEXT);
  INSERT INTO s VALUES (1,'a'),(2,'a'),(3,'b');
  SELECT id, (SELECT COUNT(*) FROM s x WHERE x.g = s.g) FROM s ORDER BY id;
  ```
- **Expected:** `[[1,2],[2,2],[3,1]]`. **Actual:** `[[1,3],[2,3],[3,3]]` — the
  outer reference `s.g` binds to the **inner** table (same base name `s`, even
  though aliased `x`), so the correlation is lost and the global count is
  returned. **Works correctly with distinct aliases** (`FROM s o … x.g = o.g`),
  so the bug is name-resolution/scoping, not correlation in general.
- **Test:** `known_issues/known_engine_bugs_test.dart` → F4.

### F5 · GROUP BY / ORDER BY cannot reference a SELECT-list alias
- **Severity:** Medium (MySQL parity gap).
- **Repro:** `SELECT strftime('%Y', ts) y, COUNT(*) FROM ev GROUP BY y`.
- **Expected:** groups by the aliased expression (MySQL and SQLite both allow
  this). **Actual:** `Bad state: Unknown column: y`.
- **Note:** standard SQL / Oracle do *not* allow alias in GROUP BY, but MySQL
  and SQLite do; supporting it improves MySQL parity.
- **Test:** `known_issues/known_engine_bugs_test.dart` → F5.

### F6 · Implicit text+number coercion leaks an internal Dart cast error
- **Severity:** Medium-High (unhandled internal exception, not a clean SQL error).
- **Repro:** `SELECT 'abc' + 0`.
- **Expected:** non-numeric text coerces to `0` (SQLite) — or a clean SQL-level
  type error. **Actual:** throws `type 'String' is not a subtype of type 'num'`
  — an internal implementation exception leaks to the caller.
- **Scope:** pervasive — a fuzz run of 18k queries hit this class **1991×**
  (any text value flowing into a numeric context: `ABS(t1)`, `t1 + 1`, etc.).
- **Test:** `known_issues/known_engine_bugs_test.dart` → F6.

### F7 · NULL left-operand short-circuits AND/OR (broken three-valued logic)
- **Severity:** Critical (silent wrong results across a huge query class).
- **Root cause:** a `NULL`/`UNKNOWN` **left** operand short-circuits the boolean
  operator and returns `NULL` *without evaluating the right operand*.
- **Repro & truth table** (engine vs required):
  ```
  NULL OR  1=1   → engine NULL, required TRUE   ❌
  NULL AND 1=0   → engine NULL, required FALSE  ❌
  1=1  OR  NULL  → TRUE   ✔ (right-side NULL works)
  1=0  AND NULL  → FALSE  ✔ (right-side NULL works)
  NULL OR  1=0   → NULL   ✔
  NULL AND 1=1   → NULL   ✔
  ```
- **Impact:** corrupts any `WHERE` / `CASE` / `CHECK` / `HAVING` where a
  NULL-producing predicate sits on the **left** of `AND`/`OR` with a decisive
  right operand. **Found by the fuzzer** (1173 divergences / 32k type-aware
  queries) — it slipped past authored NULL tests because those never placed a
  NULL-producing predicate left of a `TRUE`/`FALSE`.
- **Test:** `known_issues/known_engine_bugs_test.dart` → F7; also gates
  `fuzz/random_differential_fuzz_test.dart` (skipped until fixed).

### F8 · SUBSTR with negative length returns empty
- **Severity:** Low-Medium. `SUBSTR('Hello', 2, -1)` → `''`; SQLite returns the
  character(s) *preceding* the start (`'H'`). Negative length unsupported.
- **Test:** F8.

### F9 · Division by zero yields Infinity instead of NULL
- **Severity:** High (invalid value enters the result/stored data).
- **Repro:** `SELECT 5 / 0` → `Infinity`. SQL requires `NULL` (SQLite) or a
  clean divide-by-zero error. The engine's real division leaks IEEE `Infinity`.
- **Test:** F9.

### F10 · UNIQUE not enforced on UPDATE
- **Severity:** High (integrity — duplicate unique values).
- **Repro:** `UPDATE t SET e='a'` where `'a'` already exists in a `UNIQUE`
  column succeeds, creating a duplicate. (Same family as F1/F2: constraints are
  checked on INSERT but not on UPDATE.)
- **Test:** F10; `constraints/constraint_write_paths_test.dart`.

### F11 · Lexer applies C-style backslash escaping in single-quoted strings
- **Severity:** Medium (parse failure on valid SQL; can't represent `\`).
- **Repro:** `SELECT '\'` or `... LIKE '100\%%' ESCAPE '\'` →
  `FormatException: Unterminated string`. SQL single-quoted strings escape a
  quote by doubling (`''`), not with `\`; a lone `\` is a literal backslash.
- **Test:** F11.

### F12 · Boolean subexpression in arithmetic leaks a Dart cast error
- **Severity:** Medium-High (internal exception on valid SQL).
- **Repro:** `SELECT (a > 0) - (a < 0)` →
  `type 'bool' is not a subtype of type 'num'` (expression.dart `BinaryExpr`).
  SQL treats booleans as 1/0 in arithmetic. (Same leak family as F6.)
- **Test:** F12.

### F13 · ORDER BY aggregate DESC mis-sorts a NULL group key
- **Severity:** Medium (wrong row order).
- **Repro:** `SELECT g FROM t GROUP BY g ORDER BY COUNT(*) DESC, g` with a NULL
  group present sorts the NULL group to the **front** regardless of its count
  (observed `[null, a, …]` where `a` has the higher count). Expected the NULL
  group to order by its aggregate value, then by `g`.
- **Test:** F13.

### F14 · Multi-row INSERT is not statement-atomic
- **Severity:** High (partial writes / statement atomicity).
- **Repro:** `INSERT INTO t VALUES (2),(3),(1),(4)` where `1` violates the PK —
  the statement fails but rows `2,3` remain committed. Likewise a `CHECK`
  violation mid-batch leaves the other rows. A failed statement must roll back
  entirely.
- **Test:** F14; `constraints/constraint_write_paths_test.dart`.

### F15 · Persistence is not crash-atomic (committed data lost on hard kill)
- **Severity:** Critical (durability — the "D" in ACID).
- **Repro:** a worker commits 200 rows in an explicit transaction, calls
  `flush()`, then churns more writes; the parent **hard-kills** it (SIGKILL)
  mid-write and reopens. The committed+flushed baseline is **intermittently
  lost** — reopen returns `0` of `200` rows.
- **Behavior:** *non-deterministic* across runs (timing of the kill relative to
  a flush), observed on **both** the JSON and SQLite-format backends.
- **Root cause:** `flush()`/persist rewrites the whole data file in place
  without an atomic temp-file-plus-rename (and without fsync ordering), so a
  crash during the rewrite leaves the file truncated/partial; on reopen the
  engine sees an empty/incomplete database.
- **Impact:** a power loss or crash can discard **already-committed**
  transactions — unacceptable for a system of record. A clean `close()` round
  trip is fine (`durability/persistence_test.dart` passes); only the crash path
  loses data.
- **Test:** `durability/crash_recovery_test.dart` (+ `bin/durability_worker.dart`),
  skipped because the loss is intermittent — un-skip to reproduce.

### F16 · Selecting from a view defined over a join fails
- **Severity:** High (views over joins are unusable).
- **Repro:** `CREATE VIEW v AS SELECT a.id, a.x, b.y FROM a JOIN b ON a.id=b.id;`
  then `SELECT id, x, y FROM v` → `Bad state: Unknown column: id`. The view's
  output columns are not exposed to an outer query.
- **Test:** F16; `sql_features/views_test.dart`.

### F17 · A view projecting `alias.*` leaks the inner table alias
- **Severity:** High (common view idiom broken).
- **Repro:** `CREATE VIEW v AS SELECT a.*, b.y FROM a JOIN b ON a.id=b.id;`
  then querying `v` → `Bad state: No such table or view: a` — the inner alias
  `a` from the view's `a.*` leaks out instead of being expanded at view-creation.
- **Test:** F17; `sql_features/views_test.dart`.

### F18 · HAVING without GROUP BY is a parse error
- **Severity:** Medium (standard SQL / MySQL / SQLite all allow it).
- **Repro:** `SELECT SUM(v) FROM s HAVING SUM(v) > 5` →
  `FormatException: Unexpected token after statement: HAVING`. `HAVING` should
  apply to the implicit single group when `GROUP BY` is absent.
- **Test:** F18.

### F19 · Greater-than mishandles negative zero *(OPEN — found 2026-10-22)*
- **Severity:** Low-Medium (wrong comparison result; rare but real).
- **Repro:** `SELECT (0 > -0.0)` → `1` (TRUE). IEEE 754 defines `-0.0 == 0.0`,
  so `0 > -0.0` must be `0` (FALSE). Any expression producing `-0.0` (e.g. a
  `negative * 0`) poisons a subsequent `>` comparison.
- **Discovery:** the differential fuzzer (seed 1013, row with `t1=''`, `i2=0`,
  `r1=-14.939` → `LENGTH('') > (r1*0)` i.e. `0 > -0.0`). 2 hits / 32000 queries.
- **Test:** `known_issues/known_engine_bugs_test.dart` → F19.

### F20 · NOT IN with a NULL in the list/subquery ignores the NULL *(OPEN — 2026-10-22)*
- **Severity:** High (silent wrong results — classic SQL NULL trap).
- **Repro:**
  ```sql
  a: (id=1, g=3);  b: (g=1),(g=2),(g=NULL)
  SELECT id FROM a WHERE g NOT IN (SELECT g FROM b);
  ```
  `3 NOT IN (1, 2, NULL)` is UNKNOWN (never TRUE), so the result must be **empty**.
  The engine returns `[1]` — it drops the NULL from the list and evaluates
  `3 NOT IN (1, 2)` as TRUE.
- **Test:** `known_issues/known_engine_bugs_test.dart` → F20.

### F21 · Named table-level FK / UNIQUE / PK constraints fail to parse *(OPEN — from sakila)*
- **Severity:** High (cannot load standard SQL schemas with named constraints).
- **Repro:** `CREATE TABLE t (id INT, pid INT, CONSTRAINT fk FOREIGN KEY (pid)
  REFERENCES p(id))` → `FormatException: Expected ) but got "FOREIGN"`. Same for
  `CONSTRAINT <name> UNIQUE (...)` and `CONSTRAINT <name> PRIMARY KEY (...)`.
  Only `CONSTRAINT <name> CHECK (...)` and *unnamed* constraints parse.
- **Impact:** blocks **10 of 16 sakila tables** and the Oracle **HR** schema
  (which also uses named inline constraints). Found by loading the real
  SQLite-sakila schema.
- **Test:** `known_issues/known_engine_bugs_test.dart` → F21;
  `data_driven/sakila_differential_test.dart` (blocked).

### F22 · FK enforced despite `PRAGMA foreign_keys=OFF`; no forward references *(OPEN — from sakila)*
- **Severity:** Medium-High (blocks loading real FK schemas; ignores a PRAGMA).
- **Repro:** with `PRAGMA foreign_keys = OFF`, inserting a child row whose FK
  references a not-yet-created table throws `Bad state: FK references missing
  table <t>`. SQLite defaults `foreign_keys=OFF` and permits forward references,
  so it loads the same data cleanly.
- **Two defects:** (1) the `foreign_keys=OFF` PRAGMA is ignored (FK always
  enforced); (2) a FK to a table that does not yet exist errors instead of being
  allowed/deferred. Together they stop the sakila data (customer/payment/
  inventory/rental/address/staff/store/city load **0 rows** in the engine vs
  full in SQLite).
- **Test:** `known_issues/known_engine_bugs_test.dart` → F22;
  `data_driven/sakila_differential_test.dart` (blocked).

### F23 · COLLATE operator not supported *(OPEN — found 2026-10-22)*
- **Severity:** Medium (standard SQL; blocks case-insensitive query logic).
- **Repro:** `... WHERE s = 'apple' COLLATE NOCASE` / `... ORDER BY s COLLATE
  NOCASE` → `FormatException: Unexpected token after statement: COLLATE`. The
  `COLLATE` operator is unparsed anywhere (WHERE, ORDER BY, DISTINCT).
- **Test:** F23.

### F24 · Window functions fail in any GROUP BY query *(OPEN — found 2026-10-22)*
- **Severity:** High (ranking groups by an aggregate is a core analytic).
- **Repro:** `SELECT g, SUM(v) s, RANK() OVER (ORDER BY SUM(v) DESC) FROM t
  GROUP BY g` → `Bad state: Unknown function: RANK`. Even `RANK() OVER (ORDER BY
  g) FROM t GROUP BY g` fails. Window functions work on *ungrouped* queries; the
  window path is not reached once `GROUP BY` is present.
- **Test:** F24.

### F25 · Row-value / tuple expressions not parsed *(OPEN — found 2026-10-22)*
- **Severity:** Medium (standard SQL row values).
- **Repro:** `WHERE (a, b) = (1, 2)` → `FormatException: Expected ) but got ","`.
  Same for `(a, b) IN ((1,1),(2,2))`, `(a, b) < (c, d)`, tuple `IN (subquery)`.
- **Test:** F25.

### F26 · CREATE TABLE AS SELECT not supported *(OPEN — found 2026-10-22)*
- **Severity:** High (common ETL / materialization idiom).
- **Repro:** `CREATE TABLE t AS SELECT … FROM src` → `FormatException: Expected (
  but got "AS"`. The CREATE TABLE parser requires a column-def `(` with no
  `AS SELECT` branch. Supported by SQLite, MySQL, Oracle, Postgres.
- **Test:** F26.

### F27 · JSON path functions return wrong value for a missing path *(OPEN — found 2026-10-22)*
- **Severity:** Medium (wrong JSON results when a key is absent — common).
- **Repro:** on a doc without `age`/`tags`:
  `json_type(doc, '\$.age')` → `'null'` (the string) and
  `json_array_length(doc, '\$.tags')` → `0`; SQLite returns **SQL NULL** for a
  path that does not exist.
- **Test:** F27.

### F28 · Integer overflow wraps silently *(OPEN — found 2026-10-22)*
- **Severity:** Medium (silent numeric corruption).
- **Repro:** `SELECT 9223372036854775807 + 1` → `-9223372036854775808` (two's-
  complement wrap). SQLite promotes to float (stays positive); MySQL errors.
  Silent wraparound is the worst of the three. Also `-9223372036854775808` (int64
  min literal) fails to lex.
- **Test:** F28.

### F29 · Scientific-notation literals silently mis-parsed *(OPEN — found 2026-10-22)*
- **Severity:** Medium-High (silent wrong value, no error).
- **Repro:** `SELECT 1e3` → `1` (the `e3` is swallowed as a column alias) instead
  of `1000`; `1.5e2` → `1.5`; `1.0e-3` → parse error. Any data carrying
  scientific-notation numbers (CSV/JSON imports) is silently corrupted.
- **Test:** F29.

### F30 · Hex integer literals silently mis-parsed *(OPEN — found 2026-10-22)*
- **Severity:** Medium (silent wrong value).
- **Repro:** `SELECT 0x1F` → `0` (the `x1F` becomes a column alias) instead of
  `31`; `0xFF + 1` → parse error. SQLite and MySQL support `0x..` hex literals.
- **Minor relatives:** `SELECT 5.` (trailing-dot number) and `SELECT 1 == 1`
  (SQLite `==` operator) also fail to parse.
- **Test:** F30.

---

## Dialect differences (not bugs — engine follows MySQL/Oracle)

These diverge from SQLite but match MySQL/Oracle, which is the engine's intended
dialect. The differential suite asserts the enterprise-aligned behavior directly
in `correctness/dialect_semantics_test.dart`.

| ID | Behavior | SQLite | dart_db_server (MySQL/Oracle) |
| --- | --- | --- | --- |
| D1 | `7 / 2` | `3` (integer division) | `3.5` (real division) ✔ |
| D2 | `MIN(x, y)` two-arg scalar | scalar least | aggregate-only; use `LEAST`/`GREATEST` |
| D3 | `CREATE TABLE t (v)` typeless column | allowed | rejected (types required) ✔ |
| D4 | `CAST('0x10' AS INTEGER)` | `0` | `16` (parses hex) |

D1 and D3 are arguably *more* correct for an enterprise (MySQL/Oracle) target.
D2 is a capability note: use `GREATEST`/`LEAST` for scalar min/max. D4 is a minor
convenience divergence asserted in `correctness/dialect_semantics_test.dart`.

| ID | Behavior | SQLite | dart_db_server |
| --- | --- | --- | --- |
| D5 | `UPPER('café')` / `LOWER` | ASCII-only (`é` unchanged) | Unicode-aware (`É`) |
| D6 | `'Apple' LIKE 'apple'` | TRUE (case-insensitive ASCII) | FALSE (case-sensitive, like Oracle) |

D5: the engine's Unicode-aware case folding is arguably more correct than
SQLite's ASCII-only `UPPER`/`LOWER`; recorded so the differential suite excludes
non-ASCII case comparisons.

---

## Coverage that still needs real infrastructure

The harness is strong on correctness, constraints, transactions, durability, and
single-engine concurrency. Not yet covered (would need more than a path dep):

- **Cross-connection isolation levels** (dirty/non-repeatable/phantom reads) —
  requires driving the Oracle/MySQL **wire servers** with concurrent clients.
- **Crash/kill-mid-write recovery** — requires a subprocess harness that hard-
  kills the engine and reopens.
- **Fault injection / Jepsen-style** partition and clock testing.
- **TPC-H/TPC-C/TPC-DS** at scale factor for optimizer and throughput.
