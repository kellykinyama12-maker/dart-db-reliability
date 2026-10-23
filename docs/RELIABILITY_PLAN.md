# dart_db_server — Enterprise Reliability & Parity Certification Plan

> **Status:** master plan. This is the conclusive, end-to-end plan for proving
> `dart_db_server` behaves like an enterprise database (Oracle / MySQL class)
> across correctness, integrity, durability, concurrency, scale, and wire
> compatibility. It supersedes ad-hoc testing and ties together the two
> harnesses already in place.
>
> **Owning project:** `dart-db-reliability` (this repo). It depends on the
> engine by path and **never modifies engine code** — it observes, measures,
> and reports. Engine fixes land in `../dart-db-server`.

---

## 0. Objective & definition of done

**Objective.** Establish an automated, reproducible certification that answers
one question with evidence: *can this engine be trusted with enterprise data and
workloads the way Oracle/MySQL can?*

**Definition of done (certification bar).** The engine is "enterprise-certified"
when **all** of the following hold in CI, on every commit:

1. **Correctness** — 0 unexplained divergences from the SQLite oracle across the
   full differential corpus and fuzz seeds.
2. **Integrity** — 100% of constraint-enforcement tests pass (no `KNOWN ENGINE
   BUG` skips remain).
3. **Transactions** — ACID + savepoint suite green; documented isolation level
   is conformance-tested over the wire.
4. **Durability** — crash-recovery harness green across all storage backends.
5. **Concurrency** — multi-connection isolation suite green; no lost updates,
   no dirty reads at the declared level.
6. **Scale** — TPC-H SF1 (22 queries) results match the reference; load +
   query within budget.
7. **Wire parity** — real `mysql_client` and `oracledb` drivers pass the
   correctness corpus through the wire servers, not just the in-process API.
8. **Dialect parity** — sakila (MySQL) and HR/OE/SH (Oracle) sample schemas
   load ≥ 95% of statements (see `../dart-db-server/parity/`).

Each criterion below has concrete acceptance tests and a phase.

---

## 1. Current state (baseline, 2026-10-21)

| Asset | Location | What it does |
| --- | --- | --- |
| Dialect-ingestion harness | `../dart-db-server/parity/` + `test/parity/` | Loads real Oracle/MySQL dumps, reports what the engine accepts. |
| Reliability harness | this repo | Differential + authored correctness, constraints, ACID, durability, concurrency, scale. |
| Findings log | `findings/FINDINGS.md` | Confirmed bugs + dialect notes. |

**Baseline numbers.**
- Reliability suite: **238 pass, 27 skipped, 0 unexpected failures** (cert gate
  PASS). Run `dart run bin/scorecard.dart` for the live summary.
- **Bug status (2026-10-23): 146 found, 142 fixed & verified, 4 open (F143
  MEDIAN binary residual; F144–F146 real customer_orders load blockers —
  IS JSON check, JSON_TABLE view, TO_TIMESTAMP 9-digit FF).** The author drained
  the entire Oracle backlog; the strengthened SH gate + finishing the real CO
  load surfaced these. **Dataset coverage:** HR + SH real-data three-way gates
  (green); CO partial three-way (products/orders blocked by F144–F146); OE data
  still to load; product_media + SH-fact out of scope. MySQL wire clean.
- **Oracle parity gates:** HR schema, SH schema, and HR **data** (full dataset)
  run live/green; auto-skip if absent. A correct SQL*Plus splitter lives at
  `lib/src/oracle_script.dart`.
- **Oracle triple-threat match** (`test/wire/oracle_triple_threat_test.dart`,
  per `../dart-db-server/doc/oracle-triple-threat-testing.md`, thin client
  dropped): every case is adjudicated by three Oracle participants — Gun A the
  server emulator (`Database.execute`), Gun 2 the pure-Dart thick client
  (`OracleThickClient`), and Gun 3 the **real `oci8` / Instant Client** via
  `tool/oci8_exec.php`. Gun 3 auto-skips when Instant Client is absent; where
  present it has confirmed the emulator's wire bytes match real Oracle.
- Parity ingestion: employees 6/6 tables; sakila blocked by `INT UNSIGNED`;
  Oracle HR blocked by inline constraints + `COMMENT ON`.

**Open engine bugs (must close for cert): 18.** All reproduced by skipped
regression tests in `known_issues/`, `constraints/`, and `durability/`; full
detail in `findings/FINDINGS.md`.
- **Durability (critical):** F15 persistence is not crash-atomic — a hard kill
  during `flush()` can lose already-committed data (reopen returns 0 rows).
- **Integrity:** F1 `CHECK` not enforced on `UPDATE`; F2 composite `PRIMARY KEY`
  not enforced; F10 `UNIQUE` not enforced on `UPDATE`; F14 multi-row `INSERT`
  not statement-atomic.
- **Correctness (critical):** F7 NULL left operand short-circuits `AND`/`OR`
  (breaks three-valued logic everywhere).
- **Correctness:** F3 date month-underflow year; F4 correlated-subquery
  name-collision scoping; F9 divide-by-zero → `Infinity`; F13 `ORDER BY`
  aggregate mis-sorts NULL group; F16 view-over-join columns unresolved;
  F17 view `alias.*` leaks inner alias.
- **Robustness (internal exception leaks):** F6 text+number coercion;
  F12 boolean-in-arithmetic; F11 lexer backslash-in-string.
- **Parity gaps:** F5 `GROUP BY` alias; F8 `SUBSTR` negative length;
  F18 `HAVING` without `GROUP BY`.

---

## 2. Dimension matrix

The nine dimensions of enterprise reliability, current coverage, and the gap to
certification.

| # | Dimension | Method | Now | Target |
| --- | --- | --- | --- | --- |
| D1 | SQL correctness | differential vs SQLite + fuzz | partial | full corpus + 10k fuzz seeds |
| D2 | Data integrity (constraints) | authored | 2 bugs open | 100% green |
| D3 | Transactions (ACID, savepoints) | authored | green (API) | + error-path & interleaving |
| D4 | Isolation (multi-connection) | wire clients | **none** | levels conformance-tested |
| D5 | Durability & recovery | reopen + crash harness | reopen only | kill-mid-write recovery |
| D6 | Concurrency integrity | `Future.wait` races | green (single engine) | + wire-level contention |
| D7 | Scale & performance | differential at 50k | correctness only | TPC-H SF1 + perf budgets |
| D8 | Wire-protocol parity | real drivers | engine API only | driver round-trips |
| D9 | Dialect ingestion | sample-dump load | measured | ≥95% on sakila + HR/OE/SH |

---

## 2A. Bug-hunting strategy (maximize catch rate)

> **Goal:** systematically surface a *substantial* number of defects before a
> client does. This section distills what the first 34 bugs taught us into a
> repeatable method and a wide coverage sweep.

### What the 34 bugs taught us
- **The executor is robust; the parser/lexer is where bugs live.** 60k fuzz
  queries + every feature sweep passed, yet targeted literal/parser probes found
  F23–F34. **Lesson:** spend hunting budget on *input surface* (lexer, parser,
  type/affinity, functions), not just execution.
- **Silent corruption is the highest-risk class.** F29 (`1e3`→`1`), F30
  (`0x1F`→`0`), F28 (overflow), F34 (2-arg trim), F33 (truthiness) return a
  *wrong value with no error*. Prioritize anything that can silently mis-value.
- **The fuzzer only finds what it generates.** It missed F33 (bare-number
  conditions), COLLATE, tuples, CTAS because the grammar never emitted them.
  **Lesson:** every manual find must be *fed back into the generator* so the
  class is covered forever.
- **Differential-vs-SQLite is the workhorse**; authored goldens cover engine-
  owned behavior; real datasets catch what synthetic data misses (F21/F22).

### The method (apply to every surface area)
1. **Differential first** — run the construct on the engine *and* SQLite; diff
   as a sorted multiset. Divergence → triage bug vs dialect.
2. **Probe the edges** — NULLs, empty, zero, negative, overflow, missing keys,
   case, whitespace, type mismatches, absent/extra args.
3. **Classify honestly** — bug (fix) vs dialect (assert engine behavior, record
   in the D-table). Never assert a bug away.
4. **Minimize & regress** — reduce to a one-line repro, add a skipped
   `KNOWN ENGINE BUG` test, and (if generative) extend the fuzzer.
5. **Re-verify live** — once fixed, un-skip and run with **nothing skipped**.

### Coverage sweep — surface areas to hunt (checklist)
Tracks each area's state so the sweep is auditable. ✅ swept clean · ⚠️ bug(s)
found & fixed · ◻ not yet swept.

| Area | State | Notes / next probes |
| --- | --- | --- |
| Numeric literals (int/real/hex/sci/underscore) | ⚠️→✅ | F28/F29/F30 fixed; add `0o`/binary, huge decimals |
| String/blob literals, quote/escape | ⚠️→✅ | F11 fixed; probe `\x`, unicode escapes, `X''` empty |
| Identifier quoting (`"`/`` ` ``/`[]`) | ⚠️→✅ | F31 fixed; probe reserved-word idents, schema-qualified |
| Operators (`=`/`==`/`<>`/`!=`/`||`/bitwise) | ◻ | `==`, `IS`, `IS DISTINCT FROM`, `->`/`->>`, `#>` |
| Boolean/truthiness in CASE/iif/WHERE/HAVING | ⚠️→✅ | F33 fixed; probe `WHERE 1`, `HAVING col`, `ON 1` |
| NULL / three-valued logic | ⚠️→✅ | F7/F20 fixed; probe `IS DISTINCT FROM`, `COALESCE` chains |
| Type affinity & coercion | ⚠️→✅ | F6/F12 fixed; probe text↔num in ORDER BY, index, join keys |
| CAST (bare/sized/exotic targets) | ⚠️→✅ | F32 fixed; probe `CAST(x AS JSON/INTERVAL/BLOB)` |
| Scalar functions (string/num/date) | ⚠️→✅ | F34 fixed; sweep every documented function's edge cases |
| Aggregates (DISTINCT/FILTER/empty/overflow) | ◻ | `SUM` overflow, `AVG` empty, ordered-set aggregates |
| Window functions (frames/EXCLUDE/groups) | ⚠️→✅ | F24 fixed; probe `RANGE`, `EXCLUDE`, `GROUPS`, named windows |
| JSON / JSONB function family | ⚠️→✅ | F27 fixed; probe `json_set/insert/replace/patch/each/tree` |
| Subqueries (scalar/correlated/EXISTS/IN) | ✅ | tuple-IN (F25) fixed; probe lateral, multiple columns |
| CTE (recursive/cycles/limits) | ✅ | probe cycle detection, `MATERIALIZED`, mutual recursion |
| Set ops (UNION/INTERSECT/EXCEPT typing) | ✅ | probe mixed-type arms, `ORDER BY` ordinal in compound |
| DDL (CTAS/ALTER/generated/constraints) | ⚠️→✅ | F21/F26 fixed; probe `ALTER` add-constraint, check expr eval |
| Constraints (PK/UNIQUE/FK/CHECK, all paths) | ⚠️→✅ | F1/F2/F10/F14 fixed; probe deferred FK, partial-index unique |
| Transactions / savepoints / isolation | ✅(API) | **D4 wire isolation not yet done** |
| Durability / crash recovery | ⚠️→✅ | F15 fixed; probe WAL modes, torn writes, fsync ordering |
| Collation / case / sort | ⚠️→✅ | F23 fixed; probe `COLLATE` in index/PK, custom collations |
| Row values / tuples | ⚠️→✅ | F25 fixed; probe tuple in `IN (subquery)`, `VALUES` rows |
| Dates / times / intervals / zones | ✅ | probe `INTERVAL` arithmetic, TZ conversions, 2-digit years |
| `RETURNING` / UPSERT variants | ✅ | probe `RETURNING *`, multi-row, `ON CONFLICT` multi-target |
| PRAGMA / introspection / `EXPLAIN` | ◻ | `table_info`, `foreign_key_list`, plan shape correctness |
| ATTACH / multi-database | ◻ | cross-db joins, name resolution, txn across DBs |
| Wire protocols (MySQL/Oracle) | ◻ | **D8** — real-driver round-trips of the whole corpus |
| Security (injection/limits/DoS) | ◻ | deep nesting, huge IN-lists, recursion/stack limits |

### Fuzzer enhancement backlog (so classes stay covered)
The generator currently emits type-safe projection/aggregate/group/join queries
with comparison predicates. Extend it to also emit — and thereby *regress* —
the classes manual probes found:
- bare-value conditions (`WHERE <number>`, `CASE WHEN <col>`), truthiness;
- numeric literals in all forms (hex/sci/underscore) as a correctness check;
- `COLLATE`, row-value tuples, scalar subqueries, `CASE`/`COALESCE`/`NULLIF`
  nests, `IN (subquery)`, `EXISTS`;
- string/date function calls with edge arguments;
- window functions with/without `GROUP BY` and explicit frames.
Target: **≥10 seeds × thousands of queries per shape**, 0 divergences as the
standing gate.

### Highest-value unswept areas (do next)
1. **Operators** (`==`, `IS DISTINCT FROM`, JSON `->`/`->>`) — cheap, likely hits.
2. **Aggregate edges** (overflow, empty, ordered-set) — silent-corruption risk.
3. **PRAGMA / introspection / `EXPLAIN`** — ORMs depend on these.
4. **Wire round-trips (D8)** and **cross-connection isolation (D4)** — the two
   remaining dimensions with **no** coverage; highest enterprise value.
5. **Security/limits** — deep nesting, huge lists, recursion caps.

---

## 3. Phased roadmap

### Phase 1 — Close the correctness & integrity core (highest priority)
**Scope.** Make D1–D3 airtight at the engine-API level. **(In progress.)**
- ✅ Differential corpus expanded: date/time, `CAST`/coercion, aggregation &
  grouping edges, NULL/3-valued logic, type semantics — surfaced F3–F6.
- Raise fuzz to parameterized seeds (≥ 1k), add schema-shape randomization
  (random column counts/types, random predicates).
- Drive F1–F6 to resolution with the engine owner; un-skip when fixed.
- Add negative-path transaction tests (error inside txn → rollback invariants).

**Acceptance.** D1 differential corpus + fuzz: 0 divergences. D2: no
`KNOWN ENGINE BUG` skips. D3: atomicity holds under every injected error.

**Effort:** M · **Risk:** low · **Depends on:** engine fixes for F1/F2.

### Phase 2 — Wire-level correctness & isolation (the enterprise differentiator)
**Scope.** Prove the Oracle/MySQL **wire servers** — not just the core — are
correct and isolate sessions.
- New harness: boot `MySqlServer` / `OracleServer` on an ephemeral port, connect
  with real `mysql_client` and `oracledb` drivers, and replay the D1 corpus;
  diff results against SQLite.
- Isolation conformance: two concurrent connections; assert the declared level
  (serializable per the Oracle front-end docs) — no dirty reads, no lost
  updates, writer/reader blocking semantics as documented.
- Prepared-statement binds, large result sets split across frames, TLS upgrade.

**Acceptance.** D4 + D8 green: both drivers pass the corpus over the wire;
isolation anomalies absent at the declared level.

**Effort:** L · **Risk:** medium (driver/protocol surface) · **Depends on:** P1.

### Phase 3 — Durability under failure
**Scope.** Real crash-recovery, not just clean reopen (D5).
- Subprocess harness: a child process opens a DB on a file, applies a workload,
  and is **hard-killed** (SIGKILL/`Process.kill`) mid-write at randomized
  points. Parent reopens and asserts: no corruption, committed data present,
  uncommitted data absent (atomic recovery).
- Repeat across backends: JSON, paged, SQLite-format, WAL/WAL2 modes.
- Torn-write / partial-flush simulation where the backend allows.

**Acceptance.** D5 green: across N randomized kill points and all backends, the
database always reopens consistent with the last durable commit.

**Effort:** L · **Risk:** medium · **Depends on:** P1.

### Phase 4 — Scale, performance & the optimizer
**Scope.** D7 at enterprise size.
- Load TPC-H SF1 (`parity/datasets`, generator noted in
  `../dart-db-server/parity/test-data.md`) into engine + a reference; diff all
  22 queries for correctness.
- Load the full `employees` dataset (~4M rows) via its `.dump` files.
- Performance budgets: capture load time, query latency (p50/p95), and memory;
  fail the build on regressions beyond a threshold (ratchet, not absolute).
- Index-selection assertions via `EXPLAIN QUERY PLAN` on representative queries.

**Acceptance.** D7 green: TPC-H SF1 results correct; perf within the ratchet;
plans use the expected indexes.

**Effort:** XL · **Risk:** medium · **Depends on:** P1, dataset generation.

### Phase 5 — Dialect ingestion to ≥95%
**Scope.** D9 — make stock Oracle/MySQL dumps load (feeds back into the engine).
- Track the prioritized gaps already found: `INT UNSIGNED`, Oracle inline named
  constraints, `COMMENT ON`, `ALTER TABLE ADD (CONSTRAINT …)`, `CREATE/DROP
  SCHEMA`, single-quoted aliases (see `parity/parity-report.md`).
- As each lands in the engine, re-measure; gate at ≥95% statement acceptance on
  sakila + HR/OE/SH, with the core tables queryable.

**Acceptance.** D9 green: sakila & Oracle HR/OE/SH load ≥95%; a post-load
differential query set passes.

**Effort:** M (harness) + engine work · **Risk:** low · **Depends on:** engine.

### Phase 6 — Adversarial & property-based hardening
**Scope.** Beyond happy paths.
- SQLancer-style **metamorphic/oracle-free** testing (e.g. TLP, NoREC,
  PQS-style) to find logic bugs without a reference.
- SQL fuzzing for parser/executor crashes and resource exhaustion.
- Security: injection surface through the wire layer, malformed binds, deeply
  nested queries, OOM guards.

**Acceptance.** D1 hardened: a fixed adversarial budget (N generated programs)
finds 0 crashes/divergences; security probes rejected cleanly.

**Effort:** L · **Risk:** low · **Depends on:** P1, P2.

---

## 4. Infrastructure to build (harness backlog)

| Component | Phase | Purpose |
| --- | --- | --- |
| Wire-driver corpus runner | P2 | Replay the differential corpus through MySQL/Oracle front-ends with real drivers. |
| Multi-connection isolation driver | P2 | Interleave two sessions; assert isolation-level invariants. |
| Subprocess crash/recovery harness | P3 | Hard-kill mid-write; reopen; assert atomic recovery. |
| TPC-H/C/DS loader + query runner | P4 | Scale correctness + perf budgets. |
| Perf ratchet + report | P4 | Track latency/memory, fail on regression. |
| Property-based / metamorphic engine | P6 | Oracle-free logic-bug discovery. |
| CI workflow | all | Run tiered suites on PR vs nightly; publish the scorecard. |

---

## 5. Test taxonomy & tiering (for CI)

- **Tier 0 — fast (every PR, < 30s):** correctness differential (reduced
  corpus), constraints, ACID, durability reopen, concurrency, dialect unit.
- **Tier 1 — nightly:** full fuzz seeds, wire-driver corpus, crash-recovery,
  isolation conformance.
- **Tier 2 — weekly/release:** TPC-H SF1, full `employees` load, perf ratchet,
  adversarial budget.

Datasets stay git-ignored and are fetched on demand (see
`../dart-db-server/parity/test-data.md`); suites `skip` when data or native
`sqlite3` is unavailable, so Tier 0 is always runnable.

---

## 6. Reporting & governance

- **Scorecard.** Each run emits a dimension-by-dimension pass/skip/fail summary
  (the certification bar in §0). Published to `findings/` and surfaced in CI.
- **Findings lifecycle.** New divergence → reproduce with a seeded test →
  classify (bug vs dialect) → log in `findings/FINDINGS.md` → bugs tracked as
  `KNOWN ENGINE BUG` skips until fixed, then un-skipped (the regression guard).
- **No silent green.** A dialect difference is only accepted after it is
  explicitly asserted as intended behavior (as done for real division / typed
  columns). Bugs are never asserted away.
- **Separation of duties.** This project tests; the engine repo fixes. The two
  evolve independently via the path dependency.

---

## 7. Immediate next actions

1. **File F1 & F2** with the engine owner; keep the two skipped tests as the
   regression guard.
2. **Phase 1 expansion** — grow the differential corpus (date/time, CAST,
   collation) and parameterize fuzz seeds.
3. **Stand up the Phase 2 wire-driver runner** — the single highest-value gap,
   since it is what makes "enterprise engine" claims real.

> The through-line: **differential + reproducible + tiered + reported.** Every
> claim about the engine is backed by a test that another engine (or an authored
> golden) agrees with, re-runnable on demand, and visible in a scorecard.
