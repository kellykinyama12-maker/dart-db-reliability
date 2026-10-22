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
- **Bug status (2026-10-22): 30 found, 22 fixed & verified, 8 open.**
  F1–F22 are closed. **Open (F23–F30):** COLLATE not parsed, window fns in
  GROUP BY, row-value tuples, CREATE TABLE AS SELECT, JSON missing-path, int64
  overflow wrap, scientific-notation + hex literals mis-lexed. The 60k-query
  fuzzer and feature suites (VALUES/FILTER/UPSERT/ALTER/generated columns) are
  clean; the open bugs are parser/lexer gaps and numeric-literal edges.
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
