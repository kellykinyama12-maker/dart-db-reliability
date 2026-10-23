# Handoff — open engine bugs to fix

For the engine author working in `dart-db-server`. Many earlier bugs (through
~F252) were fixed by background mega-sweeps and verified. A parallel
multi-subagent differential sweep then surfaced a fresh batch (F254–F274),
each adjudicated vs real Oracle 23ai.

- **Verify:** `dart test test/known_issues --timeout 60s` (active guards green;
  open bugs skipped).
- **Full write-ups:** [`findings/FINDINGS.md`](findings/FINDINGS.md).

**Status: 274 found. Open (still failing vs real Oracle): 9 —
F225, F228, F232, F265, F267, F271, F272, F273, F274** (MATCH_RECOGNIZE,
PIVOT XML, XMLTABLE PASSING, and a JSON/XML tail). All loud errors — no silent
correctness bugs remain.

> **Reconciled this round (now ACTIVE guards):** F221 CHAR/VARCHAR2 padding is
> fixed the right way — **type-aware comparison** (CHAR pads, VARCHAR2 does not);
> F253 and F254–F263 are fixed and verified. The author's background sweeps also
> cleared most of F224–F252 and several of F264–F274.

> **F234 reclassified — dialect difference, not a bug (appeal upheld):** default
> NULLS ordering. Oracle treats NULL as greatest (NULLS LAST for ASC); the engine
> follows SQLite (NULL smallest) so the SQLite-parity guards hold. Explicit
> `NULLS FIRST/LAST` stays available for Oracle semantics.

> **Harness note:** the engine-vs-SQLite `random_differential_fuzz_test` is red
> by design — the engine now correctly follows Oracle on `NULL || x` and
> empty-string-is-NULL, which diverge from its SQLite reference. That is a
> fuzz-harness scoping task (exclude those families), not an engine bug.

## Reproduce the real-Oracle adjudication

Every F100+ bug was checked against a local **Oracle Database 23ai Free**
container (gvenzl image). One command does start + wait + run for you:

```powershell
./tool/ora.ps1 "SELECT TO_CHAR(1234.5,'FM9,999.00') FROM dual"   # -> 1,234.50
./tool/ora.ps1                                                   # interactive sqlplus
```

It starts the `orafree` container, waits for the PDB to open, and runs the SQL
on `FREEPDB1`. If you prefer to connect manually:

- **App user (what the harness oci8 bridge uses):** `127.0.0.1:1521` · service
  `FREEPDB1` · user `native` · password `Secret123`.
- **Passwordless OS auth:** `docker exec -i orafree sqlplus -S "/ as sysdba"`
  then `ALTER SESSION SET CONTAINER=FREEPDB1;`.

These are throwaway **local test credentials** (Oracle Free dev container), not
production secrets. Harness runner: `tool/oci8_exec.php`; bridge:
`lib/src/oci8_bridge.dart` (defaults `FREEPDB1` / `native` / `Secret123`).

## Current open bugs

### Complex-query / data-type / advanced-SQL — real-Oracle-adjudicated (F224–F234)

| # | Bug | engine → Oracle | Fix |
| --- | --- | --- | --- |
| **F224** | multi-column UPDATE | `SET (a,b) = (SELECT …)` → parse error (Oracle a+b=12) | parse the column-list = subquery UPDATE |
| **F225** | MATCH_RECOGNIZE | parse error (Oracle 1) | row pattern matching |
| **F226** | recursive WITH CYCLE/SEARCH | parse error (Oracle 4/3) | parse the CYCLE and SEARCH clauses |
| **F227** | TABLE() collection | `TABLE(coll)` unnest + COLUMN_VALUE → parse error (Oracle 3) | collection unnesting |
| **F228** | PIVOT XML | parse error (Oracle 2) | PIVOT XML |
| **F229** | LATERAL | inline view parse error (Oracle 106) | LATERAL inline views |
| **F230** | CROSS/OUTER APPLY | parse error (Oracle 2/3) | APPLY join |
| **F231** | SYS_CONTEXT/USERENV | missing (Oracle 1) | session-context functions |
| **F232** | XMLTABLE PASSING | parse error (Oracle 2) | XMLTABLE with a PASSING clause |
| **F233** | JSON dot-notation | `jt.col.key.string()` → parse error (Oracle `x`) | simplified JSON access |
| **F234** | NULLS ordering default | ORDER BY DESC returns 2, not NULL — engine uses SQLite NULL ordering (NULL smallest), Oracle NULL greatest | default NULLS LAST (ASC) / FIRST (DESC) |
| **F235** | ALTER ADD multi-col | `ADD (a, b)` adds only the first column | add all listed columns |
| **F236** | ALTER MODIFY | size/DEFAULT/NOT NULL changes are ignored | apply MODIFY |
| **F237** | ALTER DROP CONSTRAINT | the dropped CHECK is still enforced | actually drop it |
| **F238** | parameterless fn no-parens | `SELECT f0 FROM dual` → "Unknown column" (f0() works) | resolve no-arg function calls |
| **F239** | DETERMINISTIC clause | `CREATE FUNCTION … DETERMINISTIC` → parse error | parse DETERMINISTIC |
| **F240** | function DEFAULT param | `FUNCTION(x, y NUMBER DEFAULT 10)` → parse error | parse parameter defaults |
| **F241–F243** | DDL | DEFERRABLE constraints, GLOBAL TEMPORARY TABLE, INVISIBLE columns → parse errors | parse those DDL forms |
| **F244–F247** | misc built-ins | TO_TIMESTAMP_TZ/TZ_OFFSET, flashback VERSIONS, SAMPLE clause, STANDARD_HASH/ROWIDTOCHAR | add them |
| **F248** | TO_CHAR 'D' | numeric day-of-week element not applied (returns the date unchanged) | apply single-letter 'D' |
| **F249** | NLS_NUMERIC_CHARACTERS | the 3rd TO_CHAR arg (separator override) is ignored | honour the NLS parameter |
| **F250** | = ANY (value list) | non-subquery list form is a parse error (Oracle = IN) | parse the value-list quantifier |
| **F251** | tuple = (subquery) | `(a,b) = (SELECT …)` never matches (returns 0) | match row comparisons vs a subquery |
| **F252** | EXTRACT from interval literal | returns NULL for an INTERVAL literal (columns work) | extract from interval literals |

> Found by complex-query, data-type, advanced-SQL, ALTER TABLE, and PL/SQL-
> routine three-way sweeps. F234 (NULLS ordering) is the most impactful. The
> engine already handles basic stored functions/procedures/packages, anon-block
> loops, MERGE, constraints, IDENTITY, sequences, and virtual columns.

---

### HR feature sweep IV — fixed & verified except F169 (F167–F173)

| # | Bug | engine → Oracle | Fix |
| --- | --- | --- | --- |
| **F155** | TO_CHAR(date) WW/IW/J | returns the date unchanged (Oracle `29` / `29` / `2460512`) | apply the week-of-year, ISO-week, and Julian-day format elements |
| **F156** | TO_CHAR(date,'DDD') | Jan 1 → `012`, Jul 20 → `207` (Oracle `001` / `202`) | fix the day-of-year computation |
| **F157** | JSON_EXISTS | unknown function (Oracle true) | add the JSON_EXISTS predicate |
| **F158** | JSON_VALUE RETURNING | `JSON_VALUE(… RETURNING NUMBER)` → parse error (Oracle `12.5`) | parse the RETURNING clause |
| **F159** | VSIZE / DUMP | unknown function (Oracle `3` / `Typ=96 Len=1: 65`) | add the datatype-introspection functions |

> Found by a second 39-query HR three-way feature sweep (29 already matched real
> Oracle, incl. windowing frames ROWS/RANGE, CUME_DIST, PERCENT_RANK, NTH_VALUE,
> LAST_VALUE, RPAD/LTRIM/RTRIM, REGEXP_REPLACE backrefs, CEIL/FLOOR/POWER/LOG/LN,
> WIDTH_BUCKET, LAST_DAY, MONTHS_BETWEEN, ADD_MONTHS, EXTRACT, TO_CHAR Q/DAY,
> JSON_VALUE nested, JSON_QUERY).

---

### HR feature sweep — real-Oracle-adjudicated (F150–F154)

| # | Bug | engine → Oracle | Fix |
| --- | --- | --- | --- |
| **F150** | ROUND(date, fmt) | `ROUND(DATE '2024-07-20','MONTH')` → "2024" (Oracle `2024-08-01`; `2024-07-01` for day < 16) | apply the date rounding model (companion to F137 TRUNC) |
| **F151** | TO_CHAR hex fmt | `TO_CHAR(255,'FMXXX')` → `255` (Oracle `FF`) | apply the `X` hex number-format model (companion to F106) |
| **F152** | JSON_OBJECT VALUE | `JSON_OBJECT('k' VALUE 1)` → parse error (Oracle `{"k":1}`) | parse the `KEY … VALUE` JSON_OBJECT syntax |
| **F153** | REMAINDER | `REMAINDER(17,6)` → unknown function (Oracle `-1`) | add REMAINDER (rounds the quotient, unlike MOD which floors) |
| **F154** | STATS_MODE | `STATS_MODE(d)` → unknown function (Oracle most-frequent value) | add the STATS_MODE aggregate |

> Found by a 42-query HR three-way feature sweep (37 already matched real Oracle,
> incl. DECODE/NVL2/GREATEST/LEAST/COALESCE, BITAND, SUBSTR neg, INSTR occurrence,
> TRANSLATE, REGEXP_SUBSTR/INSTR/COUNT, SOUNDEX, VARIANCE/STDDEV/CORR, NTILE,
> LAG, FIRST_VALUE, INTERSECT, CONNECT_BY_ISLEAF, NEXT_DAY, NUMTODSINTERVAL,
> TO_NUMBER, JSON_ARRAY).

---

### MEDIAN decimal precision — real-Oracle-adjudicated (F143)

| # | Bug | engine → Oracle | Fix |
| --- | --- | --- | --- |
| **F143** | MEDIAN is binary | `MEDIAN(1.01,1.02)` over NUMBER(8,2) → `1.0150000000000001` (Oracle `1.015`); real SH `MEDIAN(prod_list_price)` → `31.990000000000002` (Oracle `31.99`) | average the two middle values in exact decimal, like the F142 SUM fix |

> Found by the **strengthened SH real-data three-way gate**
> (`oracle_realdata_parity_test.dart`). F142 fixed exact-decimal `SUM`; `MEDIAN`
> (and likely other percentile/averaging aggregates) still averages the middle
> values in binary floating point. The repro asserts on the **raw** engine value
> because the harness's generic `normalizeValue` rounds to 12 significant digits
> and would otherwise absorb the residual — Oracle NUMBER is exact decimal.

### customer_orders load blockers — real-Oracle-adjudicated (F144–F146)

| # | Bug | engine → Oracle | Fix |
| --- | --- | --- | --- |
| **F144** | IS JSON check breaks INSERT | `CHECK (details is json)` then `INSERT … UTL_RAW.CAST_TO_RAW('{…}')` → "Unknown column: json" (Oracle inserts the row) | evaluate the IS JSON predicate inside a CHECK constraint instead of treating `json` as a column |
| **F145** | JSON_TABLE in a view | `CREATE VIEW … FROM p, JSON_TABLE(p.details,'$' COLUMNS(…))` → parse error (Oracle creates it) | support lateral JSON_TABLE in a view/FROM clause |
| **F146** | TO_TIMESTAMP 9-digit FF | `TO_TIMESTAMP('….123456789','… HH24.MI.SS.FF')` → NULL, so a NOT NULL column rejects the row (Oracle parses it) | parse 9-digit fractional seconds in the `FF` format |

> Found finishing the real **customer_orders** three-way load. With F140
> (UTL_RAW) and F141 (JSON) landed, CO now loads customers=392, stores=23,
> shipments=1892; **products** is blocked by F144, its **product_reviews** view
> by F145, and **orders/order_items/inventory** by F146 (orders rows get a NULL
> timestamp, cascading FK failures). Fixing these three should let the whole CO
> schema load for a full three-way gate.

### order_entry object types — real-Oracle-adjudicated (F147–F148)

| # | Bug | engine → Oracle | Fix |
| --- | --- | --- | --- |
| **F147** | object constructor | `CREATE TYPE … AS OBJECT` succeeds, but `INSERT … addr_typ('…','…')` → "Unknown function: ADDR_TYP" (Oracle inserts) | register the default object-type constructor |
| **F148** | attribute navigation | `SELECT c.addr.city FROM c c` → parse error (Oracle returns the attribute) | parse table-alias-qualified object attribute paths |

> Found probing the real **order_entry** (OE) object-relational schema. The
> engine already parses `CREATE TYPE … AS OBJECT` / `VARRAY` / `TABLE OF` and
> object/`XMLType` columns, but the object DML/query semantics are missing. OE
> also uses `@&`-include + `DEFINE &1` SQL*Plus substitution and SQL*Loader
> `.ctl`/`.dat` + a `.dmp` for data — those loader mechanics remain out of scope
> (like product_media). F147–F148 are the SQL-level object-type gaps worth fixing.

---

## Fixed & verified this round (F137–F142)

All drained and un-skipped — now active regression guards.

### Date-trunc format + quantified subquery — real-Oracle-adjudicated (F137–F138)

| # | Bug | engine → Oracle | Fix |
| --- | --- | --- | --- |
| **F137** | TRUNC(date, fmt) | `TRUNC(date,'MM')` returns the unchanged date, Oracle → month start | apply the date-trunc format model (MM/YYYY/…) |
| **F138** | quantified subquery | `x >= ALL (SELECT …)` → parse error | parse `>= ALL`/`ANY`/`SOME (subquery)` |

### CO schema — LISTAGG overflow / UTL_RAW / JSON (F139–F141)

| # | Bug | engine → Oracle | Fix |
| --- | --- | --- | --- |
| **F139** | LISTAGG ON OVERFLOW | `LISTAGG(n,',' ON OVERFLOW TRUNCATE …)` → parse error | parse the `ON OVERFLOW TRUNCATE … WITH COUNT` clause |
| **F140** | UTL_RAW package | `UTL_RAW.CAST_TO_RAW('AB')` → unknown function | add UTL_RAW (CAST_TO_RAW, etc.) |
| **F141** | Oracle JSON | `JSON_VALUE` / `JSON_TABLE` / `IS JSON` → unsupported | add JSON query functions + the IS JSON predicate/constraint |

> Found loading the real **customer_orders** schema (co_create + co_populate).
> The CO data partially loads on the engine (customers=392, stores=23,
> shipments=1892); products/orders/order_items/inventory are blocked by F140
> (UTL_RAW BLOBs) and a `TO_TIMESTAMP('…','DD-MON-YYYY HH24.MI.SS.FF')` variant.

### NUMBER aggregation precision (F142)

| # | Bug | engine → Oracle | Fix |
| --- | --- | --- | --- |
| **F142** | NUMBER agg is binary | `SUM(0.1,0.2)` over NUMBER(8,2) → `0.30000000000000004` (Oracle `0.3`) | exact-decimal aggregation (F131 fixed single-value rounding, not arithmetic) |

> Found by the new **SH real-data three-way gate**
> (`oracle_realdata_parity_test.dart`): raw `SUM` over NUMBER columns carried a
> binary residual. Fixed — the gate's exact-decimal `SUM` assertion is green.
> (Its sibling `MEDIAN` residual is tracked separately as F143.)

> Found by a 30-query HR real-data battery (27/30 already matched real Oracle,
> incl. STDDEV/CORR, FIRST_VALUE, RATIO_TO_REPORT, REGEXP backrefs, TRANSLATE,
> CUBE, SYS_CONNECT_BY_PATH, PIVOT, KEEP LAST, PERCENTILE_DISC, TO_CHAR FM).

### Data-type fidelity II — real-Oracle-adjudicated (F133–F136)

| # | Bug | engine → Oracle | Fix |
| --- | --- | --- | --- |
| **F133** | HEXTORAW / RAW | `RAWTOHEX(HEXTORAW('DEADBEEF'))` → unknown function | add HEXTORAW + RAW/BLOB hex handling |
| **F134** | TO_CHAR fractional sec | `TO_CHAR(ts,'FF3')` → full value, Oracle → `123` | apply the `FF[n]` format |
| **F135** | INTERVAL column types | `v INTERVAL DAY TO SECOND` → parse error | parse INTERVAL DAY-TO-SECOND / YEAR-TO-MONTH column types |
| **F136** | NUMBER negative scale | `NUMBER(5,-2)` → parse error; Oracle rounds `12345`→`12300` | parse negative scale |

> Already clean: BINARY_DOUBLE/FLOAT arithmetic, NCHAR/NVARCHAR2, CLOB,
> TIMESTAMP, NUMBER(*,0), and (now) NUMBER exact decimal (F131) + CHAR padding
> (F132).

### Stragglers — real-Oracle-adjudicated (F124–F129)

| # | Bug | engine → Oracle | Fix |
| --- | --- | --- | --- |
| **F124** | q-quote literals | `q'[it's a test]'` → parse error | parse `q'[…]'`/`q'{…}'` alternative quoting |
| **F125** | RETURNING INTO | `INSERT … RETURNING v INTO x` → parse error | parse the RETURNING INTO clause |
| **F126** | UNPIVOT | `FROM s UNPIVOT (val FOR col IN (a,b))` → parse error | support UNPIVOT (PIVOT already works) |
| **F127** | PL/SQL collections/records | `TYPE … IS TABLE OF`/`IS RECORD`, BULK COLLECT, FORALL, %ROWTYPE fields | support PL/SQL composite types |
| **F128** | ROWNUM in UPDATE | `UPDATE t SET v = ROWNUM` → rejected | allow ROWNUM outside a projection |
| **F129** | advanced clauses | `MODEL` / `MATCH_RECOGNIZE` / `PIVOT XML` / flashback `VERSIONS` | rare/advanced; low priority |

> F124–F128 are common real-world SQL/PL-SQL; **F129 is rare/advanced** and can
> wait. Already clean: `INSERT … SELECT`, PIVOT.

### Nested aggregates — real-Oracle-adjudicated (F130)

| # | Bug | engine → Oracle | Fix |
| --- | --- | --- | --- |
| **F130** | nested aggregate over GROUP BY | `SELECT MAX(MIN(s)) FROM t GROUP BY d` → throws, Oracle → 20 | support Oracle's two-level `MAX(MIN(x))` aggregation |

> Found by the new **HR real-data three-way gate**
> (`test/parity/oracle_hr_realdata_parity_test.dart`): the real HR schema+data is
> loaded into both the engine and real Oracle and 25 analytic queries are
> diffed — all identical except this one. A strong signal the engine matches
> Oracle on real rows (joins, correlated subqueries, windows, CONNECT BY,
> LISTAGG, ROLLUP, MONTHS_BETWEEN/ADD_MONTHS, MINUS, WIDTH_BUCKET, …).

### Data-type fidelity — real-Oracle-adjudicated (F131–F132)

| # | Bug | engine → Oracle | Fix |
| --- | --- | --- | --- |
| **F131** | NUMBER is binary, not decimal | `0.1 * 3` → `0.30000000000000004` (Oracle `0.3`); `NUMBER(10,2)` rounds `1.005`→`1.00` not `1.01` | store NUMBER as exact decimal |
| **F132** | CHAR(n) not blank-padded | `CHAR(5)` holding `'ab'` → LENGTH 2, Oracle → 5 (`'ab   '`) | blank-pad CHAR to the declared length |

> **F131 is a financial-precision / data-integrity bug** (NUMBER must be exact
> decimal). Already clean: `2.675`→`2.68`, big-number clamping, NUMBER division,
> DATE round-trip, FLOAT.

---

## Resolved batch (F85–F123) — ✅ fixed 2026-10-23

> **✅ RESOLVED (async).** The F86–F99 batch; SYS_CONNECT_BY_PATH + PIVOT (F94);
> KEEP ordering (F105); MINUS (F107); IDENTITY (F109); NUMBER scale (F110);
> MERGE DELETE (F111); DEFAULT ON NULL (F112); VARCHAR2 length (F113); NUMBER
> precision (F114); recursive-WITH keyword (F115); WITH-in-subquery (F116); the
> date/time + regex batch (F100–F104); TO_CHAR number format + analytics (F106,
> F108); and bit/byte/hash functions + POWER fractional exponent (F117, F118).
> All verified live and kept as active regression guards.

---

## Resolved batch (F85) — ✅ fixed 2026-10-23 (materialized view indexing)

> **✅ RESOLVED.** `CREATE INDEX` / `CREATE BITMAP INDEX` on a materialized view
> now works (the MV is both queryable and indexable). The SH populate indexes
> its fact MVs this way and now applies with 0 failures. Verified live; the
> repro is an active regression guard in
> `test/known_issues/known_engine_bugs_test.dart`.

---

## Resolved batch (F79–F84) — ✅ fixed 2026-10-23 (Oracle SH / OLAP DDL)

> **✅ RESOLVED.** Verified live; the six skipped repros are now active
> regression guards in `test/known_issues/known_engine_bugs_test.dart`.

| # | Bug | Repro → now |
| --- | --- | --- |
| **F79** | schema-qualified FK ref | `… REFERENCES hr.p (id)` now parses |
| **F80** | ALTER TABLE MODIFY | `ALTER TABLE t MODIFY CONSTRAINT pk DISABLE NOVALIDATE` is supported (31× in SH bulk-load) |
| **F81** | CREATE BITMAP INDEX | `CREATE BITMAP INDEX ix ON t (g)` accepted as a regular index |
| **F82** | CREATE INDEX storage clause | trailing `NOLOGGING`/`LOCAL` accepted/ignored |
| **F83** | CREATE DIMENSION | `CREATE DIMENSION …` accepted (OLAP) |
| **F84** | PL/SQL named-arg `=>` | `dbms_stats.gather_schema_stats('SH', cascade => TRUE)` parses |

> SH *fact* data loads via SQL*Loader CSVs (out of harness scope); the lookup
> tables (channels=5, countries=35, products=72) load via INSERTs —
> `oracle_sh_data_parity_test.dart`.

---

## Resolved batch (F75–F78) — ✅ fixed 2026-10-23 (Oracle data load)

> **✅ RESOLVED.** `TO_DATE` (F75), `ALTER TABLE ENABLE/DISABLE CONSTRAINT`
> (F76), `ALTER SESSION SET` (F77), and `COMMIT`-no-tx no-op (F78). The real HR
> data now loads (100 employees via `TO_DATE` + the circular-FK deferred flow);
> `oracle_hr_data_parity_test.dart` runs live/green.

---

## Resolved batch (F74) — ✅ fixed 2026-10-22 (PL/SQL trigger body executes)

> **✅ RESOLVED.** A PL/SQL `BEFORE INSERT` trigger body now executes its
> procedural assignment (`:new.v := 42` sets `v`). Verified live.

---

## Resolved batch (F68–F73) — ✅ fixed 2026-10-22 (Oracle OE/SH DDL)

> **✅ RESOLVED.** `PARTITION BY` (F68), `CREATE MATERIALIZED VIEW` (F69),
> `CREATE TYPE` (F70), `CREATE SYNONYM` (F71), PL/SQL trigger *parsing* (F72),
> and the constraint `ENABLE` clause (F73). The real SH schema now loads fully.
> (F72's body-execution caveat is tracked as F74 above.)

---

## Resolved batch (F66–F67) — ✅ fixed 2026-10-22 (finish Oracle HR schema)

> **✅ RESOLVED.** `ORGANIZATION INDEX` clause (F66) and `CREATE VIEW` column
> list (F67) now parse. The real `hr_create.sql` loads fully —
> `test/parity/oracle_hr_parity_test.dart` runs live and is green.

---

## Resolved batch (F60–F65) — ✅ fixed 2026-10-22

> **✅ RESOLVED.** Self LEFT JOIN left-column (F60), column-level COLLATE +
> DISTINCT/GROUP BY collation (F61/F62), and the Oracle HR DDL trio — inline
> named column constraints (F63), `ALTER TABLE ADD (constraint)` (F64), and
> `COMMENT ON` (F65). Verified live; kept as active regression guards.

---

## Resolved batch (F57–F59) — ✅ fixed 2026-10-22 (SQLite-semantics gaps)

> **✅ RESOLVED.** Verified live; kept as active regression guards.

| # | Bug | Repro → now |
| --- | --- | --- |
| **F57** | rowid pseudo-column | `SELECT rowid FROM t` / `WHERE rowid = 5` now resolves (also `_rowid_`, `oid`) |
| **F58** | negative LIMIT | `LIMIT -1` now treated as unlimited (SQLite) |
| **F59** | multi-arg min()/max() | now errors (Oracle/MySQL — use `LEAST`/`GREATEST`) instead of silently returning the first arg |

## Probe coverage log — recently verified clean (no bugs)

Differential vs SQLite + three-way vs real `oci8`; no divergences beyond those
filed above.

- **Triggers:** AFTER INSERT/UPDATE/DELETE with `OLD`/`NEW`, `WHEN` clause,
  BEFORE `RAISE(ABORT)` rollback, cascade triggers (a→b→c).
- **Views:** over a join, with aggregate+GROUP BY, nested, filtered.
- **Aggregates:** `FILTER (WHERE …)`, `group_concat`, `COUNT/SUM/AVG DISTINCT`,
  `COUNT(DISTINCT)` multi, MIN/MAX over mixed types, GROUP BY expression,
  correlated aggregate subquery, aggregate in ORDER BY.
- **Functions/features (round 8):** JSON (`json_extract`/`array`/`object`/`->`/
  `->>`/`json_type`), window frames (`LAG`/`LEAD`/`NTILE`/`FIRST_VALUE`/
  `ROWS BETWEEN`/`DENSE_RANK`), UPSERT (`ON CONFLICT`), `INSERT OR REPLACE/IGNORE`,
  generated columns, recursive CTEs, GLOB, LIKE ESCAPE, `typeof`, `LEAST`/
  `GREATEST`.
- **Oracle path:** 15 Oracle-specific features, binds, transactions, isolation,
  FETCH, concurrency (4 clients), session survival after every error type.

---

## Resolved — ✅ F55–F56 fixed 2026-10-22 (INTEGER PRIMARY KEY rowid alias)

> **✅ RESOLVED.** A plain `INTEGER PRIMARY KEY` now auto-assigns the rowid when
> the id is omitted/NULL (F56) and rejects non-integer values (F55), verified
> vs SQLite. Kept as active regression guards.

---

## Resolved batch (F53–F54) — ✅ fixed 2026-10-22 (Oracle wire server)

> **✅ RESOLVED.** Both verified three-ways (emulator, pure-Dart thick, real
> `oci8`). Kept as a record.

| # | Bug | Severity | Repro → now |
| --- | --- | --- | --- |
| **F53** | large value crashes wire codec | 🔴 crash + desync | `SELECT` a 9000-char VARCHAR2 → now round-trips (chunked across TNS packets) |
| **F54** | non-ASCII inbound SQL corrupted | 🔴 wrong results | `SELECT 'héllo' FROM dual` → `héllo`; `WHERE 'ü'='ü'` → `1` (inbound SQL byte-length-decoded) |

> **Triple-threat result:** the pure-Dart thick client (Gun 2) matched real
> `oci8` (Gun 3) on every case — 0 pure-Dart client bugs throughout.

---

## ⬅ Reply from the engine author — new test tooling (2026-10-22)

Two deliverables landed in `dart-db-server` to turn the Oracle sweep into a
**triple threat** (thin Dart · pure-Dart thick · real `oci8`). Wire these into
the harness.

**Gun 2 — importable pure-Dart thick client (full query round-trip).**
`lib/oracle_thick_client.dart`, import as
`package:dart_db_server/oracle_thick_client.dart`:

```dart
final c = await OracleThickClient.connect(1521);
await c.login(username: 'native', password: 'Secret123');     // native O5LOGON
final r = await c.query('SELECT id, name FROM t WHERE id > :m', binds: [0]);
r.columns; r.rows;                                            // decoded result
await c.execute('INSERT ...');                                // -> affected count
// errors surface as OracleThickException(code, message)
```
Decodes NUMBER (base-100) + VARCHAR2 (UTF-8), handles NULLs and **FETCH
pagination** past 100 rows. Round-trip matrix:
`test/oracle_thick_client_roundtrip_test.dart` (6 tests green).

**Gun 3 — real `oci8` runner (closed-source `libclntsh`).**
`tool/oci8_runner.php` — the Python version was dropped; this matches the PHP
`oci8` client already on the box. **Verified live** end to end against
`dart_db_server` (native auth + create/bind-insert/select/bound-select/update/
drop, correct results, JSON output for diffing):

```bash
php tool/oci8_runner.php                       # -> {"ok":true,"steps":[...]}
ORA_USER=native ORA_PASSWORD=Secret123 php tool/oci8_runner.php
```

**Run the server for Gun 2 / Gun 3** (PBKDF2 user is **required** for any thick
client; use a **non-zero `--port`** — `--port 0` drops into a REPL that blocks
the Oracle listener and the client hangs):

```bash
dart run bin/dart_db_server.dart --memory --port 4555 \
    --oracle-port 1521 --oracle-pbkdf2-user native/Secret123
```

Method + harness wiring: `doc/oracle-triple-threat-testing.md`. A case that
passes Gun 1/Gun 2 but fails Gun 3 = the server emits bytes the open-source
clients tolerate but real Oracle rejects (e.g. **F53** below, first seen via
`OracleThickClient`).

---

## Current open bug (F53)

| # | Bug | Severity | One-line repro → wrong result |
| --- | --- | --- | --- |
| **F53** | large Oracle value crashes wire codec | 🔴 crash + desync | `SELECT` a ~9000-char VARCHAR2 over `OracleThickClient` → `RangeError ...167..8182` (8000 OK) |

> **F53 detail** — a column value larger than one SDU (~8182 bytes) is not split
> across TNS DATA packets, so the client decode overruns its single-packet
> buffer and throws `RangeError`. 8000 chars work, ~8100+ fail. The crash also
> leaves the connection desynced (later queries return shifted data / an
> `unexpected native response message` with no recovery). Fix: chunk oversized
> column payloads across multiple TNS packets and reassemble on the client, as
> real Oracle does for long VARCHAR2 / CLOB.

> **Oracle sweep was otherwise clean (~70 cases):** NUMBER fidelity (to 1e30 /
> 38 digits), binds (incl. null/reused), wire COMMIT/ROLLBACK, DML counts, FETCH
> boundaries, DATE/TIMESTAMP/BLOB decode, consistent ORA error codes, and safe
> cross-connection isolation (reader blocks on an uncommitted writer, resumes
> after rollback).

---

## Resolved — ✅ F52 fixed 2026-10-22 (parser)

> **✅ RESOLVED.** `SELECT 99999999999999999999` (a positive integer literal
> above int64 max) now promotes to a double like SQLite instead of throwing
> `Positive input exceeds the limit of integer`. Fixed and verified live.

---

## Resolved batch (F48–F51) — ✅ fixed 2026-10-22 (cross-connection isolation)

> **✅ RESOLVED.** Transaction state is now per-connection; the four isolation
> symptoms below are fixed and verified with two live `mysql_client`
> connections. Kept as a record.

| # | Symptom | Severity | Deterministic repro |
| --- | --- | --- | --- |
| **F49** | lost committed write | 🔴 data loss | A `BEGIN`; B (autocommit) `INSERT r`; A `ROLLBACK` → **B’s row r is gone** |
| **F50** | cross-connection commit | 🔴 corruption | A `BEGIN; INSERT r`; B `COMMIT` commits A’s r; A’s later `ROLLBACK` is a no-op |
| **F48** | dirty read | 🟠 isolation | A `BEGIN; INSERT r` (uncommitted); B `SELECT COUNT(*)` already sees r |
| **F51** | no concurrent transactions | 🟠 concurrency | while A has a tx open, B `BEGIN` → “Already in a transaction” |

## Resolved batch (F46–F47) — ✅ fixed 2026-10-22 (MySQL wire / parser)

> **✅ RESOLVED.** Fixed and verified.

| # | Bug | Severity | One-line repro → wrong result |
| --- | --- | --- | --- |
| **F46** | parameterless prepared stmt hangs | 🔴 client freeze | `conn.prepare('SELECT v FROM t WHERE id = 1')` (no `?`) never returned; `… WHERE id = ?` worked |
| **F47** | int64-min literal crashes parser | 🟠 internal exception | `SELECT -9223372036854775808` → `"Positive input exceeds the limit of integer"` |

---

## Resolved batch (F40–F45) — ✅ fixed 2026-10-22

> **✅ RESOLVED.** All six bugs (coercion / CAST / PRAGMA / aggregate / ATTACH)
> are fixed and verified; the suite runs with nothing skipped. Kept below as a
> record of the handoff.

| # | Bug | Severity | One-line repro → wrong result |
| --- | --- | --- | --- |
| **F40** | unary minus on text crashes | 🟠 internal exception | `SELECT -'5'` → `"String is not a subtype of num"` (should be `-5`) |
| **F41** | `CAST(blob AS TEXT)` → bytes | 🟠 wrong value | `CAST(x'4869' AS TEXT)` → `[72,105]` (should be `'Hi'`) |
| **F43** | PRAGMA introspection | 🟠 ORM-compat | `table_info` `notnull=1` for PK (should be 0); unquoted defaults; `index_list` wrong shape |
| **F44** | `SUM(<bool>)` throws | 🟠 common idiom | `SUM(v > 100)` → `"SUM requires numeric, got bool"` (should coerce bool→1/0) |
| **F42** | `CAST(num AS BLOB)` throws | 🟡 one-sided error | `CAST(3.14 AS BLOB)` → `Cannot coerce` (should yield a blob) |
| **F45** | ATTACH non-functional | 🟡 feature unusable | `ATTACH … AS aux` OK but `aux.t` fails to parse/resolve → attached dbs unusable |

---

## Resolved batch (F35–F39) — ✅ fixed 2026-10-22

> **✅ RESOLVED.** The function-edge bugs F35–F39 (`abs(text)` crash, `substr(x,0)`,
> `replace` empty pattern, `CAST` trailing-garbage, `printf` `%e`/`%g`) have been
> fixed and verified (440 pass / 0 skip). Kept as a record below.

### F35–F39 (resolved)

| # | Bug | Repro → wrong result |
| --- | --- | --- |
| **F35** | `abs(text)` crash | `abs('5')` → cast error |
| **F36** | `substr(x, 0)` | `substr('hello', 0)` → `''` |
| **F37** | `replace` empty pattern | `replace('abc','','X')` → `'XaXbXcX'` |
| **F38** | CAST trailing garbage | `CAST('42abc' AS INTEGER)` → `0` |
| **F39** | `printf` `%e`/`%g` | `1.234500e+3` vs `e+03` |

---


> **✅ RESOLVED.** F33 (non-zero not truthy) and F34 (2-arg trim) have been fixed
> and verified. Kept as a record below.

### F33–F34 (resolved)

| # | Bug | Repro → wrong result |
| --- | --- | --- |
| **F33** | non-zero not truthy | `CASE WHEN 1 THEN 'y' ELSE 'n' END` → `'n'` |
| **F34** | 2-arg trim ignored | `trim('xxhixx','x')` → `'xxhixx'` |

---


## Resolved batch (F23–F32) — ✅ fixed 2026-10-22

> **✅ RESOLVED.** All 10 parser/lexer bugs (F23–F32) have been fixed and
> verified — the suite runs live with **nothing skipped** (433 pass / 0 fail),
> and the fuzzer finds 0 divergences. Combined with the earlier F1–F22 waves,
> F1–F32 are all closed. Kept below as a record of the handoff.

## Priority order (F23–F32, resolved)

| # | Bug | Severity | One-line repro → wrong result |
| --- | --- | --- | --- |
| **F29** | sci-notation literal | 🔴 silent corruption | `SELECT 1e3` → `1` (should be 1000) |
| **F30** | hex literal | 🔴 silent corruption | `SELECT 0x1F` → `0` (should be 31) |
| **F28** | int64 overflow | 🟠 silent corruption | `SELECT 9223372036854775807 + 1` → negative wrap |
| **F27** | JSON missing path | 🟠 wrong value | `json_type(doc,'$.absent')` → `'null'` string (should be NULL) |
| **F24** | window + GROUP BY | 🟠 feature broken | `RANK() OVER(...) … GROUP BY g` → `Unknown function: RANK` |
| **F26** | CREATE TABLE AS SELECT | 🟠 feature missing | `CREATE TABLE t AS SELECT …` → `Expected ( but got "AS"` |
| **F23** | COLLATE operator | 🟡 feature missing | `… COLLATE NOCASE` → `Unexpected token: COLLATE` |
| **F25** | row-value tuples | 🟡 feature missing | `WHERE (a,b) = (1,2)` → `Expected ) but got ","` |
| **F31** | double-quoted idents | 🟡 feature missing | `SELECT id AS "x"` → `Expected name but got "x"` |
| **F32** | sized-type CAST | 🟡 feature missing | `CAST(x AS VARCHAR(10))` → `Expected ) but got "("` |

> **The two 🔴 silent-corruption bugs (F29, F30) are the highest risk to a
> client** — a numeric literal in scientific or hex form yields the *wrong
> value with no error*, so bad data lands silently. Fix those first, then the
> 🟠 wrong-value/feature bugs, then the 🟡 parser gaps.

Lexer/literal family (F28/F29/F30) likely shares a root cause: the number
scanner stops early and the trailing `e..`/`x..` becomes a stray alias token —
worth fixing together.

---

## Resolved batch (F19–F22) — ✅ fixed 2026-10-22

> All four earlier blockers (F19–F22) were fixed and verified: the suite runs
> live with nothing skipped, the fuzzer finds 0 divergences, and the
> sakila/employees real-data differentials match SQLite. Kept below as a record.

---

## 🔴 F21 — Named table-level FK / UNIQUE / PK constraints fail to parse
**Highest impact.** Blocks loading standard SQL schemas (10/16 sakila tables,
Oracle HR).

```sql
CREATE TABLE p (id INTEGER PRIMARY KEY);
CREATE TABLE t (id INT, pid INT, CONSTRAINT fk FOREIGN KEY (pid) REFERENCES p(id));
-- FormatException: Expected ) but got "FOREIGN"
```

- `CONSTRAINT <name> CHECK (...)` works; `CONSTRAINT <name> FOREIGN KEY`,
  `... UNIQUE (...)`, and `... PRIMARY KEY (...)` all fail.
- **Fix:** in the CREATE TABLE parser, after consuming `CONSTRAINT <name>`,
  dispatch to the FK / UNIQUE / PK table-constraint branches (not only CHECK).
- **Verify:** `known_issues` → F21.

## 🔴 F22 — FK enforced despite `PRAGMA foreign_keys=OFF`; no forward references
Blocks loading real FK data (sakila `customer`/`payment`/`inventory`/… load
**0 rows**).

```sql
PRAGMA foreign_keys = OFF;
CREATE TABLE c (id INTEGER PRIMARY KEY, pid INT,
                FOREIGN KEY (pid) REFERENCES parent(pid));
INSERT INTO c VALUES (1, 99);
-- Bad state: FK references missing table parent
```

- **Two defects:** (1) `foreign_keys=OFF` is ignored (FK always enforced);
  (2) a FK to a not-yet-created table errors instead of being allowed/deferred.
- SQLite defaults `foreign_keys=OFF` and permits forward references.
- **Verify:** `known_issues` → F22.

## 🟠 F20 — `NOT IN (… NULL …)` ignores the NULL (silent wrong results)
```sql
-- a:(g=3)   b:(1),(2),(NULL)
SELECT id FROM a WHERE g NOT IN (SELECT g FROM b);   -- returns [1]; must be []
```

- `x NOT IN (…, NULL)` is UNKNOWN (never TRUE), so the result must be empty.
  The engine drops the NULL. Same three-valued-logic family as the fixed F7.
- **Verify:** `known_issues` → F20.

## 🟡 F19 — Greater-than mishandles negative zero
```sql
SELECT (0 > -0.0);   -- returns 1 (TRUE); must be 0 (FALSE)
```

- IEEE 754: `-0.0 == 0.0`. Any `negative * 0` yields `-0.0` and poisons a
  subsequent `>`. Found by the differential fuzzer (2 / 32000 queries).
- **Verify:** `known_issues` → F19.

---

### After F21 + F22 land
The sakila data-driven differential (`test/data_driven/sakila_differential_test.dart`)
currently strips FK clauses to work around these; once fixed, it can load the
schema as-is and the 11 real analytic queries become a standing real-data gate.
