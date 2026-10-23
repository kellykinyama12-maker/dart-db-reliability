# One-command real-Oracle access for adjudicating engine parity bugs.
#
#   ./tool/ora.ps1 "SELECT TO_CHAR(1234.5,'FM9,999.00') FROM dual"   # run + print
#   ./tool/ora.ps1                                                   # interactive
#
# Starts the local Oracle 23ai Free container (gvenzl), waits for the PDB to
# open, then runs the SQL on FREEPDB1 (or drops into sqlplus). Throwaway local
# dev credentials only.
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Sql)

$ErrorActionPreference = 'Stop'

docker start orafree | Out-Null
# Wait (inside the container) until the PDB is open.
docker exec orafree bash -c 'for i in $(seq 1 60); do /opt/oracle/healthcheck.sh >/dev/null 2>&1 && exit 0; sleep 2; done; exit 1' | Out-Null

if ($Sql) {
    $q = ($Sql -join ' ').TrimEnd(';')
    $script = @"
ALTER SESSION SET CONTAINER=FREEPDB1;
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 200;
$q;
EXIT;
"@
    $script | docker exec -i orafree sqlplus -S "/ as sysdba"
}
else {
    Write-Host 'Interactive sqlplus on FREEPDB1 (user native). Ctrl-D / exit to quit.'
    docker exec -it orafree sqlplus "native/Secret123@//localhost:1521/FREEPDB1"
}
