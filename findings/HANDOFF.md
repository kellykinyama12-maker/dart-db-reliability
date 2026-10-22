# Handoff — open engine bugs to fix

For the engine author working in `dart-db-server`. **0 open bugs** — the last
batch (F53–F54, both Oracle wire-server bugs) has been fixed and verified,
including three-way against real `oci8` / Instant Client. The full suite runs
live with nothing skipped.

- **Verify:** `dart test --timeout 30s` (all green, nothing skipped).
- **Full write-ups:** [`findings/FINDINGS.md`](findings/FINDINGS.md).

**Status: 54 found, 54 fixed & verified, 0 open.**

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
