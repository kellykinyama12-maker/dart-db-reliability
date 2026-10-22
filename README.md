# dart_db_reliability

Enterprise-grade **reliability and correctness** test harness for
[`dart_db_server`](../dart-db-server). Where the sibling `parity/` suite in the
server repo measures *dialect ingestion* (can it load a stock dump), this
project measures whether the engine is **correct, safe, durable, and
concurrency-sound** — the properties that separate an enterprise database from a
query toy.

It is a standalone Dart project that depends on `dart_db_server` by path, so it
has **full control** over its own tests, dependencies, and tooling without
touching the engine repo.

> **The master plan** lives in [`docs/RELIABILITY_PLAN.md`](docs/RELIABILITY_PLAN.md)
> — the conclusive, phased certification plan (objectives, dimension matrix,
> roadmap, infrastructure backlog, CI tiering, and governance).

## Approach

1. **Differential testing** — the strongest signal. Every correctness suite runs
   the same SQL against `dart_db_server` *and* a reference **SQLite** engine
   (`package:sqlite3`) and asserts identical results. SQLite is the oracle; a
   divergence is a bug (or a documented dialect difference). Suites skip
   automatically when the native `sqlite3` library is unavailable.
2. **Authored golden expectations** — for engine-owned behavior where SQLite is
   not the right oracle (ACID, constraints, durability, concurrency, and
   MySQL/Oracle dialect choices), tests assert exact expected values.
3. **Seeded fuzzing** — a deterministic workload generator drives hundreds of
   rows and 20 query shapes across multiple seeds; failures reproduce exactly.

## Test dimensions

| Suite | Dimension | Oracle |
| --- | --- | --- |
| `correctness/differential_fuzz_test.dart` | random workloads, aggregates, filters | SQLite |
| `correctness/null_logic_test.dart` | NULL / three-valued logic | SQLite |
| `correctness/type_semantics_test.dart` | numeric & text value semantics | SQLite |
| `correctness/dialect_semantics_test.dart` | MySQL/Oracle-aligned dialect choices | authored |
| `sql_features/enterprise_sql_test.dart` | joins, subqueries, CTE/recursion, set ops, windows | SQLite |
| `constraints/constraints_test.dart` | PK / UNIQUE / NOT NULL / CHECK / FK + cascade | authored |
| `transactions/acid_test.dart` | atomicity, commit, savepoints | authored |
| `isolation/concurrency_test.dart` | concurrent-mutation integrity (no lost updates) | authored |
| `durability/persistence_test.dart` | persist + reopen (JSON & SQLite backends) | authored |
| `scale/scale_test.dart` | 50k-row aggregates & index lookups | SQLite |

## Run

```powershell
dart pub get
dart test                       # everything
dart test test/correctness      # one dimension
dart test -r expanded           # verbose
dart run bin/scorecard.dart     # dimension-by-dimension pass/skip/fail report
dart run bin/fuzz_triage.dart   # unleash the random SQL fuzzer for triage
```

Requires the native `sqlite3` shared library for the differential suites;
without it they skip (authored suites still run).

## Findings

**18 confirmed engine bugs (F1–F18)** surfaced so far — including a critical
durability bug (F15: committed data lost on crash) and a critical correctness
bug (F7: broken three-valued logic). Full detail, severities, and repros in
[`findings/FINDINGS.md`](findings/FINDINGS.md); run `dart run bin/scorecard.dart`
for the live pass/skip/fail tally by dimension. Each confirmed bug is a test
marked `skip:` with a `KNOWN ENGINE BUG` reason, so the suite stays green and
actionable — un-skip to verify a fix.

> This project never modifies the engine. It only observes and reports.
