<?php
/**
 * Parameterised real-Oracle (thick / OCI "Gun 3") runner for the triple-threat
 * match. Reads a JSON request on stdin and runs each statement in ONE oci8
 * session against a running dart_db_server Oracle wire, emitting JSON results.
 *
 * Request (stdin):
 *   {"host":"127.0.0.1","port":NNNN,"service":"FREEPDB1",
 *    "user":"native","password":"Secret123",
 *    "statements":[{"sql":"SELECT ...","binds":[...],"query":true}, ...]}
 *
 * Response (stdout):
 *   {"ok":true,"results":[
 *       {"query":true,"columns":[...],"rows":[[...]]},
 *       {"query":false,"affected":N},
 *       {"error":"ORA-....."} ]}
 *
 * A per-statement `error` is reported inline (so an expected ORA error is a
 * comparable outcome, not a crash). A connect failure is a top-level
 * {"ok":false,"error":...}. NUMBER columns are cast to PHP numbers so the JSON
 * types line up with the pure-Dart thick client (num vs String).
 */
declare(strict_types=1);

if (!extension_loaded('oci8')) {
    echo json_encode(['ok' => false, 'error' => 'oci8 not loaded']) . "\n";
    exit(2);
}

$raw = stream_get_contents(STDIN);
$req = json_decode($raw, true);
if (!is_array($req)) {
    echo json_encode(['ok' => false, 'error' => 'bad request json']) . "\n";
    exit(2);
}

$host = $req['host'] ?? '127.0.0.1';
$port = $req['port'] ?? 1521;
$service = $req['service'] ?? 'FREEPDB1';
$user = $req['user'] ?? 'native';
$password = $req['password'] ?? 'Secret123';
$dsn = "//$host:$port/$service";

$conn = @oci_connect($user, $password, $dsn, 'AL32UTF8');
if (!$conn) {
    $e = oci_error();
    echo json_encode(['ok' => false, 'phase' => 'connect',
        'error' => trim($e['message'] ?? 'oci_connect failed')]) . "\n";
    exit(1);
}

$results = [];
foreach (($req['statements'] ?? []) as $s) {
    $sql = $s['sql'] ?? '';
    $binds = $s['binds'] ?? [];
    $isQuery = $s['query'] ?? false;

    $stmt = @oci_parse($conn, $sql);
    if (!$stmt) {
        $e = oci_error($conn);
        $results[] = ['error' => trim($e['message'] ?? 'parse failed')];
        continue;
    }

    // Bind each :name placeholder (unique, in first-appearance order) to the
    // positional bind value, matching how the pure-Dart thick client binds.
    $bindVals = [];
    if ($binds) {
        preg_match_all('/:(\w+)/', $sql, $m);
        $seen = [];
        $i = 0;
        foreach ($m[1] as $name) {
            if (isset($seen[$name])) continue;
            $seen[$name] = true;
            if ($i < count($binds)) {
                $bindVals[$i] = $binds[$i];
                oci_bind_by_name($stmt, ':' . $name, $bindVals[$i]);
            }
            $i++;
        }
    }

    $mode = $isQuery ? OCI_DEFAULT : OCI_COMMIT_ON_SUCCESS;
    if (!@oci_execute($stmt, $mode)) {
        $e = oci_error($stmt);
        $results[] = ['error' => trim($e['message'] ?? 'execute failed')];
        continue;
    }

    if ($isQuery) {
        $ncol = oci_num_fields($stmt);
        $cols = [];
        $numeric = [];
        for ($c = 1; $c <= $ncol; $c++) {
            $cols[] = oci_field_name($stmt, $c);
            $numeric[$c] = oci_field_type($stmt, $c) === 'NUMBER';
        }
        $rows = [];
        while (($row = oci_fetch_array($stmt,
            OCI_NUM + OCI_RETURN_NULLS + OCI_RETURN_LOBS)) !== false) {
            $out = [];
            for ($c = 0; $c < $ncol; $c++) {
                $v = $row[$c];
                if ($v !== null && $numeric[$c + 1]) {
                    $v = $v + 0; // cast NUMBER string -> int/float
                }
                $out[] = $v;
            }
            $rows[] = $out;
        }
        $results[] = ['query' => true, 'columns' => $cols, 'rows' => $rows];
    } else {
        $results[] = ['query' => false, 'affected' => oci_num_rows($stmt)];
    }
}

oci_close($conn);
echo json_encode(['ok' => true, 'results' => $results]) . "\n";
