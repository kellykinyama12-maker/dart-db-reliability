# Handoff — open engine bugs to fix

For the engine author working in `dart-db-server`. **5 open bugs (F35–F39)**,
found by a systematic function-edge sweep. Each has a minimal repro and a skipped
regression test that turns green when fixed.

- **Verify one:** un-skip its test in `test/known_issues/known_engine_bugs_test.dart`.
- **Verify all at once:** `dart test --run-skipped`.
- **Full write-ups:** [`findings/FINDINGS.md`](findings/FINDINGS.md).

**Status: 39 found, 34 fixed & verified, 5 open.** The executor stays robust
(60k-query fuzzer + feature sweeps clean); all five open bugs are in scalar
*functions / CAST*.

## Current open batch (F35–F39)

| # | Bug | Severity | One-line repro → wrong result |
| --- | --- | --- | --- |
| **F35** | `abs(text)` crashes | 🟠 internal exception | `abs('5')` → `"String is not a subtype of num"` (should coerce → 5.0) |
| **F38** | CAST trailing garbage | 🟠 silent wrong value | `CAST('42abc' AS INTEGER)` → `0` (should be 42) |
| **F37** | `replace` empty pattern | 🟠 silent wrong string | `replace('abc','','X')` → `'XaXbXcX'` (should be `'abc'`) |
| **F36** | `substr(x, 0)` | 🟡 wrong window | `substr('hello', 0)` → `''` (should be `'hello'`) |
| **F39** | `printf` `%e`/`%g` | 🟡 formatting | `printf('%e',1234.5)` → `1.234500e+3` (should be `e+03`); `%g` keeps trailing zeros |

> **Fix order:** F35 (internal crash — same cast-leak family as the already-fixed
> F6/F12; `abs()` was simply uncovered), then the two silent-wrong-value bugs
> (F38 CAST, F37 replace), then the formatting/window edges (F36, F39).

Likely shared roots: **F35** is the text→num coercion path missing for `abs()`
(and probably other math functions — sweep `round`/`ceil`/`floor`/`sign` the same
way). **F38** is the CAST string-to-number parser not taking a leading numeric
prefix.

---

## Resolved batch (F33–F34) — ✅ fixed 2026-10-22

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
