# Reliability findings — dart_db_server

Issues surfaced by the reliability harness. Each is reproduced by a test in this
project. **Data-integrity bugs** are the most severe (the engine silently
accepts invalid data). Dialect differences are *not* bugs — they are recorded so
the differential suite stays honest.

Run date: 2026-10-21 · Engine: `dart_db_server` 0.1.5 (path dep)

## Status update — 2026-10-23

**141 bugs found; 136 fixed & verified; 5 open (F137–F141).**

> **Dataset coverage (honest):** HR fully loaded + 43-query three-way gate. SH
> schema + lookup data (engine-only gate); SH **fact** CSVs not loaded. CO
> (customer_orders) partially loaded three-way — surfaced F139–F141; products/
> orders blocked by F140. **Still untouched:** OE (order_entry) data,
> product_media, SH fact data. Oracle is NOT fully verified yet.
The author fixed F86–F93 and F95–F99 async (now active regression guards). A
date/time + regex sweep vs real Oracle 23ai then surfaced F100–F104:
- **F100** (open) — `TO_CHAR(date, fmt)` ignores the format model and returns
  the raw ISO value (`TO_CHAR(TO_DATE(…),'MON')` → `2021-06-15`, not `JUN`).
- **F101** (open, correctness) — date arithmetic is broken: `date - date` → 0
  (Oracle 60) and `date + n` → n. `EXTRACT`/`LAST_DAY`/`ADD_MONTHS` work, so
  this is arithmetic-specific, not a missing type.
- **F102** (open) — `INTERVAL '5' DAY` literals are a parse error and
  `NUMTOYMINTERVAL`/`NUMTODSINTERVAL` are unknown.
- **F103** (open, correctness) — `REGEXP_REPLACE` does not substitute `\1`/`\2`
  backreferences (returns the template literally); plain replacement works.
- **F104** (open, correctness) — `REGEXP_SUBSTR` ignores its occurrence/position
  arguments; `REGEXP_COUNT`/`REGEXP_INSTR` are missing.

An Oracle analytic / set-op / formatting sweep vs real Oracle then added F105–
F108:
- **F105** (open, correctness) — `KEEP (DENSE_RANK FIRST/LAST ORDER BY …)` now
  parses but is ignored; it returns the plain aggregate (MAX=40 instead of 10).
- **F106** (open) — `TO_CHAR(number, fmt)` ignores the number format model
  (`TO_CHAR(1234.5,'FM9,999.00')` → `1234.5`, not `1,234.50`). Companion to F100.
- **F107** (open) — the `MINUS` set operator (EXCEPT synonym) is a parse error.
- **F108** (open) — `RATIO_TO_REPORT`, `PERCENTILE_CONT`/`DISC`, `WIDTH_BUCKET`,
  `GROUPING_ID`, `NANVL`, the `IGNORE NULLS` clause, and the `CONNECT_BY_ROOT`
  operator are unsupported. (ROWNUM, MEDIAN, CUME_DIST, PERCENT_RANK, NTH_VALUE,
  LISTAGG DISTINCT, LEVEL all work.)

An Oracle DML/DDL effect sweep vs real Oracle then added F109–F112:
- **F109** (open) — IDENTITY columns (`GENERATED ALWAYS/BY DEFAULT AS IDENTITY`)
  are a parse error.
- **F110** (open, data integrity) — `NUMBER(p,s)` does not round to the declared
  scale (`1.239` into `NUMBER(5,2)` stays `1.239`, not `1.24`).
- **F111** (open) — the `MERGE … UPDATE … DELETE WHERE` clause is a parse error.
- **F112** (open) — `DEFAULT ON NULL <expr>` is a parse error. (Sequences,
  virtual columns, column DEFAULT, INSERT ALL, UPDATE, CHECK all work.)

An Oracle type-enforcement + CTE sweep vs real Oracle then added F113–F116:
- **F113** (open, data integrity) — `VARCHAR2(n)` length is not enforced (an
  oversized string is stored, not rejected; Oracle: ORA-12899).
- **F114** (open, data integrity) — `NUMBER(p)` precision is not enforced
  (out-of-precision values stored; Oracle: ORA-01438). Companion to F110.
- **F115** (open) — a recursive `WITH` requires the SQLite-style `RECURSIVE`
  keyword; Oracle auto-detects recursion, so plain `WITH r AS (…self-ref…)`
  fails. (`WITH RECURSIVE` works.)
- **F116** (open) — a `WITH` clause inside a parenthesized subquery / derived
  table is a parse error. (FK ON DELETE CASCADE/SET NULL, CLOB, TIMESTAMP,
  PL/SQL loops, CREATE FUNCTION, NOT NULL, UNIQUE all work.)

A functions/numeric/timestamp sweep vs real Oracle then added F117–F119:
- **F117** (open) — `BITAND`, `BIN_TO_NUM`, `SUBSTRB`/`LENGTHB`/`INSTRB`, and
  `ORA_HASH` are unknown functions.
- **F118** (open) — `POWER` with a non-integer exponent throws (`POWER(27,1.0/3)`
  → error; Oracle → 3).
- **F119** (open) — `TIMESTAMP - TIMESTAMP` does not yield a correct INTERVAL:
  `EXTRACT(DAY FROM (ts5 - ts1))` → 24 instead of 4. (CONNECT_BY_ISLEAF, ORDER
  SIBLINGS BY, NOCYCLE, LOG/LN, TO_CHAR '000', TO_NUMBER '9D999' all work.)

> **Drained async since last round:** F94 (SYS_CONNECT_BY_PATH/PIVOT), F105
> (KEEP ordering), F109 (IDENTITY), F112 (DEFAULT ON NULL) — now active guards.

A PL/SQL + TIMESTAMP-WITH-TIME-ZONE sweep vs real Oracle then added F120–F123:
- **F120** (open) — PL/SQL packages (`CREATE PACKAGE`/`PACKAGE BODY` and
  `pkg.func` calls) are unsupported.
- **F121** (open) — the PL/SQL `CASE … END CASE` statement is a parse error.
- **F122** (open) — `%TYPE`/`%ROWTYPE` anchored declarations are a parse error.
- **F123** (open) — the `TIMESTAMP WITH TIME ZONE` column type is a parse error;
  TZ functions (`FROM_TZ`, etc.) are missing. (PL/SQL exception handling, WHILE
  loops, cursor FOR loops, CREATE FUNCTION, CURRENT_TIMESTAMP all work.)

> **Also drained since:** F107 (MINUS), F110 (NUMBER scale), F111 (MERGE DELETE),
> F113 (VARCHAR2 length), F114 (NUMBER precision), F115 (recursive-WITH keyword),
> F116 (WITH-in-subquery) — now active guards.

Original write-up of the now-fixed F86–F99 batch follows for the record.

**(historical) 99 bugs found; F1–F85 fixed & verified; F86–F99 open.** With a correct
Oracle SQL*Plus script splitter (`lib/src/oracle_script.dart`), the real HR
**data** now loads completely — all 107 employees, 27 departments, 25 countries,
23 locations, 19 jobs, 5 regions, 10 job_history — via `TO_DATE`, the circular-FK
deferred flow, and anonymous PL/SQL blocks. Pushing the loader onto the SH
schema/data and OE surfaced six Oracle DDL gaps, now all closed:
- **F79** — a schema-qualified table reference in a FK (`REFERENCES
  schema.table`) now parses.
- **F80** — `ALTER TABLE ... MODIFY` (constraint `DISABLE/ENABLE` or a column)
  is supported; used heavily in the SH bulk-load (31 statements).
- **F81** — `CREATE BITMAP INDEX` is accepted (as a regular index).
- **F82** — a trailing storage clause on `CREATE INDEX` (`NOLOGGING`, `LOCAL`)
  is accepted.
- **F83** — `CREATE DIMENSION` (Oracle OLAP) is accepted.
- **F84** — the PL/SQL named-argument syntax (`arg => value`, e.g.
  `dbms_stats.gather_schema_stats`) now parses.

Loading the SH **lookup data** then surfaced one more, now closed:
- **F85** — `CREATE INDEX` / `CREATE BITMAP INDEX` on a materialized
  view now works (the MV is both queryable and indexable). The SH populate
  indexes its fact MVs this way; the SH populate now applies with 0 failures.

Probing the real OE **object-relational** schema (`oc_cre.sql`) surfaced three
more, still open:
- **F86** (open) — an object table (`CREATE TABLE t OF type`) is a parse error
  (`Expected ( but got OF`). OE: `CREATE TABLE categories_tab OF category_typ`.
- **F87** (open) — a `REF` column type (`col REF type`) is a parse error. OE:
  `product_ref REF product_information_typ`.
- **F88** (open) — the `NESTED TABLE <col> STORE AS <name>` storage clause is a
  parse error (`Unexpected token after statement: NESTED`).

A scalar/aggregate function sweep surfaced four more, still open:
- **F89** (open, correctness) — `INSTR` ignores its 3rd (start position) and
  4th (occurrence) arguments; it always returns the first-occurrence position
  (`INSTR('abcabc','a',2)` → 1 instead of 4). Silent wrong answer.
- **F90** (open, correctness) — `TRUNC(n, places)` ignores the places argument
  (`TRUNC(3.14159,2)` → 3), and `TRUNC(date)` throws an internal cast error.
- **F91** (open) — `LISTAGG(expr, sep) WITHIN GROUP (ORDER BY …)` is a parse
  error (`Expected BY but got (`).
- **F92** (open) — `TRANSLATE`, `ADD_MONTHS`, `MONTHS_BETWEEN`, and `NEXT_DAY`
  are unknown functions. (`ROUND(n, places)`, `REPLACE`, `REGEXP_REPLACE/SUBSTR`,
  `ASCII`, `SOUNDEX`, `DECODE`, `NVL2`, `GREATEST/LEAST`, `LAST_DAY` all work.)

An advanced-SQL sweep (grouping/hierarchical/pivot) surfaced two more, still
open:
- **F93** (open) — `ORDER BY` a grouping column that is not in the SELECT list
  fails under `ROLLUP`/`CUBE`/`GROUPING SETS` ("Compound ORDER BY only supports
  projected columns or positions") though it works under plain `GROUP BY`.
- **F94** (open) — `SYS_CONNECT_BY_PATH`, `PIVOT`, and the `KEEP (DENSE_RANK
  FIRST/LAST)` aggregate are unsupported. (`CONNECT BY`, `LEVEL`, `ROLLUP`,
  `CUBE`, `GROUPING SETS`, `GROUPING()`, `MERGE` with unqualified SET,
  `FETCH FIRST`/`OFFSET`, `NULLS FIRST/LAST`, window `RANGE` frames all work.)

> **Adjudicated against real Oracle — confirmed bug (F95):** `MERGE … WHEN
> MATCHED THEN UPDATE SET t.v = s.v` with an *alias-qualified* target column is
> rejected by the engine (`Expected = but got "."`) but **accepted by real
> Oracle** (verified via gvenzl/oracle-free 23ai: qualified SET → 99, unqualified
> SET → 77). Unqualified `SET v = s.v` works in the engine.

A **three-way** scalar sweep (engine vs SQLite vs real Oracle 23ai) surfaced
four more universal bugs — each wrong in *both* references or crashing, so not
dialect differences:
- **F96** (open, correctness) — `MOD(-10, 3)` returns 2; both SQLite and Oracle
  return -1 (result follows the dividend sign).
- **F97** (open, correctness) — `GREATEST(1,NULL,3)`→3 and `LEAST(1,NULL,3)`→1;
  both SQLite and Oracle return NULL when any argument is NULL.
- **F98** (open, crash) — the 2-argument `REPLACE(s, sub)` throws an internal
  Dart `RangeError` instead of removing the substring (Oracle → `acac`).
- **F99** (open) — the ANSI `TRIM(chars FROM string)` form (and LEADING/
  TRAILING/BOTH) is a parse error; Oracle → `ab`.

> **Oracle-only dialect/feature differences (NOT filed):** empty-string IS NULL
> (`LENGTH('')`, `NVL('',…)`, `''` concatenation, `'' IS NULL` — the D7 stance),
> `SUBSTR(s,0,n)` treating 0 as 1 (engine matches SQLite), `DATE` literal +/-
> arithmetic, `TO_NUMBER` with a format model, and `REMAINDER`. These diverge
> from Oracle but match SQLite or are documented dialect choices.

> **Three-way CLEAN (engine == SQLite == real Oracle 23ai):** aggregates
> (AVG/SUM/MIN/MAX/COUNT, COUNT DISTINCT, empty-set, HAVING, NULL grouping),
> window functions (ROW_NUMBER/RANK/DENSE_RANK/LAG/running SUM/NTILE), and
> NULL/three-valued-logic predicates (`= NULL`, `<>`, `NOT IN (…, NULL)`,
> `NOT BETWEEN`, `NOT EXISTS`, COALESCE predicates) — 0 divergences across ~50
> probed cases. Bugs cluster in scalar functions and advanced/OR DDL, not the
> relational core.

> **Parity gates GREEN:** HR schema, SH schema, HR **data** (full dataset,
> `oracle_hr_data_parity_test.dart`), and SH **lookup data**
> (`oracle_sh_data_parity_test.dart` — channels=5, countries=35, products=72).
> SH *fact* data (sales/costs/customers/times) loads via SQL*Loader CSVs — out
> of the harness's SQL scope.

> **Broad differential otherwise clean:** rowid allocation with `AUTOINCREMENT`,
> `last_insert_rowid()`, LIMIT/OFFSET (incl. 0 and beyond-end), UNION/UNION
> ALL/INTERSECT/EXCEPT, NULL in IN/NOT IN/BETWEEN/LIKE/IS, COUNT DISTINCT,
> group_concat, empty-set aggregates, mixed-type ORDER BY (type-class ordering),
> CAST, numeric-string compare, and date/time functions all match SQLite.
> **Dialect (not a bug, D9):** the engine requires an explicit column type in
> `CREATE TABLE` (e.g. `CREATE TABLE t (id INTEGER PRIMARY KEY, v)` is rejected);
> SQLite allows a typeless column. The engine matches Oracle/MySQL here.

> **Oracle path otherwise clean (~70 cases):** NUMBER fidelity to 1e30 and 38
> digits, aggregates, NULLs, expressions, consistent ORA error codes, bound
> params (incl. reused/null binds), wire COMMIT/ROLLBACK, DML affected-row
> counts, FETCH pagination at the 99/100/101/200 boundaries, and DATE /
> TIMESTAMP / BLOB decode all round-trip correctly. Cross-connection isolation
> is safe: a second client blocks on an uncommitted writer (no dirty read) and
> resumes correctly after the writer rolls back.
> **Dialect (not a bug):** an empty string `''` reads back as `NULL` over the
> Oracle wire — correct Oracle `'' = NULL` semantics — while the engine’s
> SQLite-style core keeps it as `''` (see D7).
- **F40** — unary minus on text (`-'5'`) threw an internal cast error (binary
  arithmetic coerced fine; unary minus was missing the coercion path).
- **F41** — `CAST(<blob> AS TEXT)` returned the raw byte list instead of the
  decoded string.
- **F42** — `CAST(<number> AS BLOB)` threw instead of producing a blob.
- **F43** — `PRAGMA` introspection diverged from SQLite (table_info `notnull=1`
  for an INTEGER PRIMARY KEY, unquoted defaults, different index_list shape).
- **F44** — `SUM(<boolean>)` threw instead of coercing the bool to 1/0 (the
  common `SUM(cond)` count-matching idiom).
- **F45** — `ATTACH DATABASE` was accepted but attached tables were unusable
  (schema-qualified `aux.t` names failed to parse / resolve).

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

### F31 · Double-quoted identifiers / aliases not supported *(OPEN — found 2026-10-22)*
- **Severity:** Medium (standard SQL / Oracle identifier quoting; common alias).
- **Repro:** `SELECT id AS "my col" FROM c` and `CREATE TABLE (... "col two"
  INTEGER)` → `FormatException: Expected name but got "…"`. The engine treats
  `"…"` as a string literal, so it is rejected in identifier/alias positions.
  SQLite (identifier) and MySQL (quoted alias) both accept it. Backticks work.
- **Test:** F31.

### F32 · CAST to a sized/parameterized type not supported *(OPEN — found 2026-10-22)*
- **Severity:** Medium (common in portable SQL).
- **Repro:** `CAST(42 AS VARCHAR(10))` / `CAST(x AS CHAR(5))` /
  `CAST(x AS DECIMAL(5,2))` → `FormatException: Expected ) but got "("`. Only
  bare type names parse; SQLite, MySQL, and Oracle all accept the sized form.
- **Test:** F32.

---

## Dialect differences (not bugs — engine follows MySQL/Oracle)

These diverge from SQLite but match MySQL/Oracle, which is the engine's intended
dialect. The differential suite asserts the enterprise-aligned behavior directly
in `correctness/dialect_semantics_test.dart`.

| ID | Behavior | SQLite | dart_db_server (MySQL/Oracle) |
| --- | --- | --- | --- |
| D1 | `7 / 2` | `3` (integer division) | `3.5` (real division) ✔ |
| D2 | `MIN(x, y)` two-arg scalar | scalar least | aggregate-only; use `LEAST`/`GREATEST` (⚠ multi-arg min/max silently returns the first arg — see F59) |
| D3 | `CREATE TABLE t (v)` typeless column | allowed | rejected (types required) ✔ |
| D4 | `CAST('0x10' AS INTEGER)` | `0` | `16` (parses hex) |

D1 and D3 are arguably *more* correct for an enterprise (MySQL/Oracle) target.
D2 is a capability note: use `GREATEST`/`LEAST` for scalar min/max. D4 is a minor
convenience divergence asserted in `correctness/dialect_semantics_test.dart`.

| ID | Behavior | SQLite | dart_db_server |
| --- | --- | --- | --- |
| D5 | `UPPER('café')` / `LOWER` | ASCII-only (`é` unchanged) | Unicode-aware (`É`) |
| D6 | `'Apple' LIKE 'apple'` | TRUE (case-insensitive ASCII) | FALSE (case-sensitive, like Oracle) |
| D7 | empty string `''` over the Oracle wire | distinct empty string | reads back as `NULL` (correct Oracle `'' = NULL` semantics) |
| D8 | `NULL` in a non-integer PRIMARY KEY | allowed (SQLite quirk) | rejected (standard SQL / Oracle / MySQL) |
| D9 | typeless column in `CREATE TABLE` | allowed (BLOB affinity) | rejected — an explicit column type is required (like Oracle/MySQL) |
| D10 | SELECT-list alias used in `WHERE` | allowed (SQLite extension) | rejected — alias not in scope in WHERE (standard SQL / Oracle / MySQL) |
| D11 | `7 / 2` (int ÷ int) | `3` (integer division) | `3.5` (float division, like Oracle/MySQL `/`; use integer cast for truncation) |
| D12 | `round(2.675, 2)` | `2.67` (binary double) | `2.68` (decimal round-half-away, like Oracle/MySQL) |

D5: the engine's Unicode-aware case folding is arguably more correct than
SQLite's ASCII-only `UPPER`/`LOWER`; recorded so the differential suite excludes
non-ASCII case comparisons.

---

## Open bugs (round 2 — found 2026-10-22)

### F33 · Non-zero number not truthy in a boolean context *(OPEN)*
- **Severity:** High (broad correctness — wrong branch selection).
- **Repro:** `SELECT CASE WHEN 1 THEN 'y' ELSE 'n' END` → `'n'`; `iif(5,'y','n')`
  → `'n'`. A bare non-zero number is treated as FALSE; only an explicit
  comparison (`1=1`) evaluates true. SQLite/MySQL treat any non-zero as TRUE.
- **Test:** `known_issues/known_engine_bugs_test.dart` → F33.

### F34 · 2-arg trim / ltrim / rtrim ignores the trim characters *(OPEN)*
- **Severity:** Medium (silent wrong string).
- **Repro:** `trim('xxhixx', 'x')` → `'xxhixx'` (unchanged); should be `'hi'`.
  Same for `ltrim(x, chars)` / `rtrim(x, chars)`. The 2nd argument is ignored.
  SQLite, MySQL, Oracle all support custom trim characters.
- **Test:** F34.

## Open bugs (round 3 — found 2026-10-22, function-edge sweep)

### F35 · abs() on a text argument throws an internal cast error *(OPEN)*
- **Severity:** Medium-High (internal exception leak; same family as F6/F12).
- **Repro:** `SELECT abs('5')` / `abs('abc')` → `type 'String' is not a subtype
  of type 'num'`. SQLite coerces: `abs('5')`→5.0, `abs('abc')`→0.0.
- **Test:** F35.

### F36 · substr edge (start 0 / out-of-range) is wrong *(OPEN)*
- **Severity:** Medium.
- **Repro:** `substr('hello', 0)` → `''`; SQLite returns `'hello'` (position 0
  precedes 1). `substr('hello', -10, 3)` → `'hel'`; SQLite returns `''`.
- **Test:** F36.

### F37 · replace with an empty search pattern inserts everywhere *(OPEN)*
- **Severity:** Medium (silent wrong string).
- **Repro:** `replace('abc', '', 'X')` → `'XaXbXcX'`; an empty search matches
  nothing, so SQLite returns `'abc'` unchanged.
- **Test:** F37.

### F38 · CAST of text with trailing garbage returns 0 *(OPEN)*
- **Severity:** Medium (silent wrong value on import).
- **Repro:** `CAST('42abc' AS INTEGER)` → `0` (SQLite `42`);
  `CAST('3.14xyz' AS REAL)` → `0` (SQLite `3.14`). SQLite parses the leading
  numeric prefix.
- **Test:** F38.

### F39 · printf %e exponent width and %g trailing zeros *(OPEN)*
- **Severity:** Low (formatting).
- **Repro:** `printf('%e', 1234.5)` → `1.234500e+3` (should be `e+03`);
  `printf('%g', 0.0001)` → `0.000100000` (should trim to `0.0001`).
- **Test:** F39.

## Open bugs (round 4 — found 2026-10-22, math-coercion / CAST / PRAGMA sweep)

### F40 · Unary minus on text throws an internal cast error *(OPEN)*
- **Severity:** Medium-High (internal exception leak; F35/F6/F12 family).
- **Repro:** `SELECT -'5'` → `type 'String' is not a subtype of type 'num'`.
  Binary arithmetic (`5 + '3'`) coerces correctly; unary minus does not. SQLite
  returns `-5`.
- **Test:** F40.

### F41 · CAST(blob AS TEXT) returns raw bytes *(OPEN)*
- **Severity:** Medium.
- **Repro:** `CAST(x'4869' AS TEXT)` → `[72, 105]` (byte list); SQLite decodes
  to `'Hi'`.
- **Test:** F41.

### F42 · CAST(number AS BLOB) throws *(OPEN)*
- **Severity:** Low-Medium (one-sided error).
- **Repro:** `CAST(3.14 AS BLOB)` → `FormatException: Cannot coerce 3.14 to
  BLOB`; SQLite yields the blob of the value's text form.
- **Test:** F42.

### F43 · PRAGMA introspection diverges from SQLite *(OPEN)*
- **Severity:** Medium (breaks ORM / tooling schema introspection).
- **Repro:** `PRAGMA table_info(t)` reports `notnull=1` for an
  `INTEGER PRIMARY KEY` (SQLite: `0`) and returns default values unquoted
  (`x` vs `'x'`); `PRAGMA index_list(t)` has a different column shape and lists
  the auto PK index that SQLite omits.
- **Test:** F43.

### F44 · SUM of a boolean expression throws *(OPEN)*
- **Severity:** Medium (common `SUM(cond)` count idiom).
- **Repro:** `SELECT SUM(v > 100) FROM t` → `Bad state: SUM requires numeric,
  got bool`. SQLite/MySQL coerce the boolean to 1/0, so `SUM(cond)` counts the
  matching rows.
- **Test:** F44.

> **Note (not counted):** `SUM` of values that exceed int64 returns `NULL` in the
> engine, where SQLite raises an "integer overflow" error and MySQL promotes to
> DECIMAL. Behavior is implementation-defined; recorded as an observation.

### F45 · ATTACH DATABASE accepted but non-functional *(OPEN)*
- **Severity:** Medium (cross-database feature unusable).
- **Repro:** `ATTACH DATABASE ':memory:' AS aux` and `DETACH` succeed, but
  `CREATE TABLE aux.t (…)` → `Expected ( but got "."`, `INSERT INTO aux.t …` →
  parse error, and `SELECT … FROM aux.t` → `No such table or view: aux.t`.
  Schema-qualified `db.table` names are not parsed/resolved, so attached
  databases (and cross-db joins) are unusable despite ATTACH being accepted.
- **Test:** F45.

### Robustness — clean
Deep nesting (100 parens, 50-level CASE), 1000-element `IN` lists, 200-term
arithmetic, 10k-char strings, 10k-deep recursive CTE, nested subqueries, and
50-way `UNION` all match SQLite with no crashes or stack overflows.

### F46 · prepared statement with no parameters hangs *(FIXED & VERIFIED)*
- **Severity:** High (client freeze — no error, no timeout on the engine side).
- **Repro:** over the MySQL wire, `conn.prepare('SELECT v FROM t WHERE id = 1')`
  (no `?`) never completes; the engine's `COM_STMT_PREPARE` response is never
  sent. `conn.prepare('… WHERE id = ?')` + `execute([1])` works. Many ORMs and
  drivers prepare parameterless statements, so this hangs real clients.
- **Test:** F46 (wire suite, skipped; fails via a 5s timeout guard when forced).

### F47 · most-negative int64 literal crashes the parser *(FIXED & VERIFIED)*
- **Severity:** Medium (valid literal rejected with an internal exception).
- **Repro:** `SELECT -9223372036854775808` → `FormatException: Positive input
  exceeds the limit of integer`. The parser `int.parse`s the magnitude
  `9223372036854775808` (which overflows int64) before applying unary minus.
  SQLite returns `-9223372036854775808`.
- **Test:** F47.

### F48–F51 · cross-connection transaction isolation *(FIXED & VERIFIED, one root cause)*
Transaction state is global on the shared Database, so BEGIN/COMMIT/ROLLBACK on
one connection affects all others. Verified with two live `mysql_client`
connections; each symptom has its own repro in `test/wire/mysql_isolation_test.dart`.
- **F48 · dirty read** *(High)* — A: `BEGIN; INSERT`; B then sees the uncommitted
  row (`COUNT` = 2 instead of 1).
- **F49 · lost committed write** *(Critical — data loss)* — A: `BEGIN`; B
  (autocommit) `INSERT`; A: `ROLLBACK` → B’s committed row is gone, because A’s
  rollback restores the global snapshot captured at A’s BEGIN.
- **F50 · cross-connection commit** *(Critical)* — A: `BEGIN; INSERT`; B:
  `COMMIT` commits A’s row; A’s subsequent `ROLLBACK` is a no-op.
- **F51 · no concurrent transactions** *(High)* — while A has a transaction open,
  B’s `BEGIN` throws “Already in a transaction”; two connections can never
  transact independently.
- **Fix:** move transaction state (snapshot, inTransaction, savepoints) onto the
  per-connection session, and hold isolation for the duration of each
  transaction rather than per statement.

### F52 · positive integer literal above int64 crashes the parser *(FIXED & VERIFIED)*
- **Severity:** Medium (valid literal rejected with an internal exception).
- **Repro:** `SELECT 99999999999999999999` (or `9223372036854775808`, int64
  max + 1) → `FormatException: Positive input exceeds the limit of integer`.
  SQLite promotes an out-of-range integer literal to a double (`1e20`); the
  engine already handles `1e20` correctly, so only the integer-literal path is
  affected. Positive-side analog of the (fixed) F47; on overflow, fall back to
  `double.parse`.
- **Test:** F52.

### F53 · large Oracle column value crashes the wire codec *(FIXED & VERIFIED)*
- **Severity:** High (crash + connection desync on any large value).
- **Repro:** store a VARCHAR2 of ~9000 chars, then `SELECT` it over the Oracle
  wire (`OracleThickClient`) → `RangeError (end): ...range 167..8182`. A value of
  8000 chars works; ~8100+ fails, i.e. the limit is one SDU (~8182 bytes). The
  server does not split a column value larger than the SDU across TNS packets,
  so the client decode overruns its single-packet buffer. The failure also
  leaves the connection **desynced** — subsequent queries on it return shifted
  data or an `unexpected native response message` error, with no recovery.
- **Fix:** chunk column payloads larger than the SDU across multiple TNS DATA
  packets (and have the client reassemble), as real Oracle does for long
  VARCHAR2 / CLOB.
- **Test:** F53 (Oracle round-trip suite, skipped; uses a fresh client).

### F54 · non-ASCII inbound SQL is corrupted over the Oracle wire *(FIXED & VERIFIED)*
- **Severity:** High (any SQL with non-ASCII text returns wrong results/errors).
- **Repro:** over the Oracle wire, `SELECT 'héllo' FROM dual` → empty; `SELECT
  LENGTH('héllo') FROM dual` → empty (direct engine → 5); `... WHERE 'ü' = 'ü'`
  → `ORA-00900` on a mangled parse. ASCII SQL and stored unicode *data* are
  fine. **Confirmed server-side:** real `oci8` (Gun 3) gets the same wrong
  answer, so it is not a client decode issue.
- **Root cause:** the Oracle wire server counts the inbound SQL length in
  characters vs bytes (or truncates at a multi-byte boundary), so a statement
  containing any multi-byte UTF-8 char is parsed shifted/truncated.
- **Fix:** read the inbound SQL by its byte length and decode UTF-8 once, so the
  statement text is intact regardless of multi-byte characters.
- **Test:** F54 (Oracle round-trip suite, skipped).

### F55 · INTEGER PRIMARY KEY accepts non-integer values *(FIXED & VERIFIED)*
- **Severity:** Medium (data integrity — a PK/rowid column holds a wrong type).
- **Repro:** `CREATE TABLE t (id INTEGER PRIMARY KEY, v INTEGER);
  INSERT INTO t VALUES ('x', 1)` is accepted and stores `'x'` (text) in `id`;
  `INSERT INTO t VALUES (1.5, 1)` stores `1.5` (double). SQLite rejects both with
  `datatype mismatch` because an `INTEGER PRIMARY KEY` is a rowid alias that must
  be an integer. Regular (non-PK) INTEGER columns correctly mirror SQLite's loose
  affinity, so only the rowid-alias path is affected. Not wire-specific
  (reproduced on the direct engine vs SQLite).
- **Fix:** enforce integer type on insert/update into an `INTEGER PRIMARY KEY`
  (rowid alias) column, rejecting non-integer values as SQLite does.
- **Test:** F55 (`known_issues/known_engine_bugs_test.dart`, skipped).

### F56 · plain INTEGER PRIMARY KEY does not auto-assign the rowid *(FIXED & VERIFIED)*
- **Severity:** High (the standard autoincrement-PK idiom is broken).
- **Repro:** `CREATE TABLE t (id INTEGER PRIMARY KEY, v INTEGER);
  INSERT INTO t (v) VALUES (10)` → `FormatException: Column "id" cannot be NULL`
  (SQLite auto-assigns `id = 1`). Explicit `VALUES (NULL, 10)` fails the same
  way. `INTEGER PRIMARY KEY AUTOINCREMENT` *does* work, so the engine only
  auto-assigns with the explicit keyword.
- **Root cause:** a plain `INTEGER PRIMARY KEY` is treated as a NOT NULL column
  rather than a rowid alias. In SQLite `INTEGER PRIMARY KEY` always auto-assigns
  the next rowid; `AUTOINCREMENT` only changes the allocation guarantee.
- **Fix:** treat a plain `INTEGER PRIMARY KEY` as a rowid alias — auto-assign the
  next rowid when the id is omitted or NULL.
- **Test:** F56 (`known_issues/known_engine_bugs_test.dart`, skipped).

### F57 · rowid pseudo-column is not queryable *(FIXED & VERIFIED)*
- **Severity:** Medium (a core SQLite row-access feature is missing).
- **Repro:** `SELECT rowid FROM t` (and aliases `_rowid_`, `oid`, and
  `WHERE rowid = 5`) → `Unknown column: rowid`. SQLite exposes `rowid` on every
  rowid table (here it equals the `INTEGER PRIMARY KEY`).
- **Fix:** resolve `rowid`/`_rowid_`/`oid` to the table's rowid in both the
  SELECT list and predicates.
- **Test:** F57 (skipped).

### F58 · negative LIMIT is a parse error *(FIXED & VERIFIED)*
- **Severity:** Medium (a common SQLite/ORM idiom fails to parse).
- **Repro:** `SELECT id FROM t ORDER BY id LIMIT -1` → `FormatException: Expected
  number but got "-"`. SQLite treats `LIMIT -1` as *no limit* (used as
  `LIMIT -1 OFFSET n` to skip without capping). `LIMIT 0` already works.
- **Fix:** accept a negative LIMIT and treat it as unlimited, as SQLite does.
- **Test:** F58 (skipped).

### F59 · multi-arg min()/max() silently returns the first argument *(FIXED & VERIFIED)*
- **Severity:** High (silent wrong result for a common function name).
- **Repro:** `SELECT min(3, 1, 2)` → `3` (should be `1`); `SELECT max(1, 9, 5)`
  → `1` (should be `9`); `min('b','a','c')` → `'b'`. The engine returns the
  *first* argument regardless of value, and ignores NULLs (`min(3, NULL, 1)`
  → `3`; SQLite → `NULL`). `LEAST`/`GREATEST` work correctly.
- **Root cause:** `min`/`max` are aggregate-only (dialect D2), but a multi-arg
  call is accepted and collapses to the first argument instead of erroring.
- **Fix:** raise a wrong-argument-count error for multi-arg `min()`/`max()`
  (Oracle/MySQL behaviour — direct users to `LEAST`/`GREATEST`), or compute the
  scalar extreme (SQLite). Either is fine; silently returning the first arg is
  not.
- **Test:** F59 (skipped).

### F60 · self LEFT JOIN nulls the left row's own column *(FIXED & VERIFIED)*
- **Severity:** High (silent wrong result in a common query shape).
- **Repro:** `CREATE TABLE e (id INTEGER PRIMARY KEY, mgr INTEGER);
  INSERT INTO e VALUES (1,NULL),(2,1),(3,1),(4,2);
  SELECT e.id FROM e LEFT JOIN e m ON e.mgr = m.id ORDER BY e.id` → the
  unmatched row (id 1, mgr NULL) comes back as `NULL` instead of `1`. A
  two-table LEFT JOIN with the same shape is correct.
- **Root cause:** on a self-join the engine resolves the left alias's column to
  the NULL-padded right instance for unmatched rows.
- **Cascade:** the nulled left column corrupts downstream aggregation —
  `COUNT(e.id)` undercounts, `GROUP BY m.id` reports `0` for the unmatched
  group, and `COALESCE`/projections see NULL. Confirmed via a self-join sweep.
- **Fix:** keep the left row's own columns intact; only NULL-pad the right side.
- **Test:** F60 (skipped).

### F61 · COLLATE in a column definition is a parse error *(FIXED & VERIFIED)*
- **Severity:** Medium (schema-level collation unusable).
- **Repro:** `CREATE TABLE t (id INTEGER PRIMARY KEY, s TEXT COLLATE NOCASE)` →
  `Expected ) but got "COLLATE"`. SQLite accepts a column-level COLLATE.
- **Fix:** parse `COLLATE <name>` in a column definition and use it as the
  column's default collation.
- **Test:** F61 (skipped).

### F62 · COLLATE not applied in DISTINCT / GROUP BY *(FIXED & VERIFIED)*
- **Severity:** Medium (wrong de-duplication under a collation).
- **Repro:** `COUNT(DISTINCT s COLLATE NOCASE)` over `'A','a','b'` → `3` (SQLite
  `2`); `GROUP BY s COLLATE NOCASE` likewise doesn't fold `'A'`/`'a'`. `COLLATE
  RTRIM` in a comparison is also unimplemented. COLLATE does work in
  `WHERE`/`ORDER BY` (F23).
- **Fix:** honor a `COLLATE` override (and column default collation) in
  DISTINCT/GROUP BY keying and comparisons; implement `RTRIM`.
- **Test:** F62.

### F63–F65 · Oracle HR DDL — inline named constraints / ALTER ADD / COMMENT ON *(FIXED & VERIFIED)*
- Named inline column constraints (`col TYPE CONSTRAINT name NOT NULL`),
  `ALTER TABLE t ADD (CONSTRAINT … PRIMARY KEY/FOREIGN KEY (cols))`, and
  `COMMENT ON TABLE/COLUMN … IS '…'` now parse. After these, the real
  `hr_create.sql` loads 75/78 statements. Tests F63–F65.

### F66 · ORGANIZATION INDEX clause not parsed *(FIXED & VERIFIED)*
- **Severity:** Medium (blocks Oracle index-organized tables, e.g. HR.countries).
- **Repro:** `CREATE TABLE t (… CONSTRAINT pk PRIMARY KEY (id)) ORGANIZATION
  INDEX` → `Unexpected token after statement: ORGANIZATION`.
- **Fix:** accept (and ignore) a trailing `ORGANIZATION INDEX` / IOT storage
  clause on CREATE TABLE.
- **Test:** F66 (skipped).

### F67 · CREATE VIEW with an explicit column list not parsed *(FIXED & VERIFIED)*
- **Severity:** Medium (standard SQL; blocks HR.emp_details_view).
- **Repro:** `CREATE VIEW v (a, b) AS SELECT 1, 2` → `Expected AS but got "("`.
  The column-less form works.
- **Fix:** parse an optional `(col-list)` after the view name and use it to
  rename the view's output columns.
- **Test:** F67 (skipped).


---

## Coverage that still needs real infrastructure

The harness is strong on correctness, constraints, transactions, durability, and
single-engine concurrency. Not yet covered (would need more than a path dep):

- **Crash/kill-mid-write recovery** — requires a subprocess harness that hard-
  kills the engine and reopens.
- **Fault injection / Jepsen-style** partition and clock testing.
- **TPC-H/TPC-C/TPC-DS** at scale factor for optimizer and throughput.
