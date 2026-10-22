# Handoff — open engine bugs to fix

For the engine author working in `dart-db-server`. **4 open bugs (F40–F43)**,
found by a math-coercion / CAST / PRAGMA sweep. Each has a minimal repro and a
skipped regression test that turns green when fixed.

- **Verify one:** un-skip its test in `test/known_issues/known_engine_bugs_test.dart`.
- **Verify all at once:** `dart test --run-skipped`.
- **Full write-ups:** [`findings/FINDINGS.md`](findings/FINDINGS.md).

**Status: 43 found, 39 fixed & verified, 4 open.** The executor stays robust;
the open bugs are in *coercion / CAST / introspection*.

## Current open batch (F40–F43)

| # | Bug | Severity | One-line repro → wrong result |
| --- | --- | --- | --- |
| **F40** | unary minus on text crashes | 🟠 internal exception | `SELECT -'5'` → `"String is not a subtype of num"` (should be `-5`) |
| **F41** | `CAST(blob AS TEXT)` → bytes | 🟠 wrong value | `CAST(x'4869' AS TEXT)` → `[72,105]` (should be `'Hi'`) |
| **F43** | PRAGMA introspection | 🟠 ORM-compat | `table_info` `notnull=1` for PK (should be 0); unquoted defaults; `index_list` wrong shape |
| **F42** | `CAST(num AS BLOB)` throws | 🟡 one-sided error | `CAST(3.14 AS BLOB)` → `Cannot coerce` (should yield a blob) |

> **Fix order:** F40 first (internal crash — the coercion path that binary ops
> and `abs()` already have is missing for **unary minus**; grep for the operator
> eval and route text through the same coercion). Then F41/F43 (wrong values /
> ORM-visible introspection), then F42.

**F43 detail** — match SQLite's `PRAGMA` output: `table_info(t)` should report
`notnull=0` for an `INTEGER PRIMARY KEY` (rowid alias), quote default-value
literals (`'x'` not `x`), and `index_list(t)` should use SQLite's 5-column shape
(`seq,name,unique,origin,partial`) and omit the implicit PK index.

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
