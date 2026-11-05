#!/usr/bin/env bash
# Integration battery for WsusOfflineUpdater.exe and the accept-path hash
# gates (Phase 28 plan 02) - run from repo root.
#
# Section (a) drives the hash gates through the ci/tests/selfupdate-probe
# console project: ParseHashesFile fixtures (the MEASURED hashdeep format -
# %%%% headers, ## filtered lines, exactly one data line, field-position
# SHA256, lowercase-only, size > 0) and the fail-closed refusal comparison
# (probe sha256 of a real fixture zip vs the published digest - a corrupted
# byte must mismatch).
#
# Section (b) drives the PUBLISHED updater against a scratch install tree
# under the Windows temp directory (never the repo tree):
#   Fixture A happy path   - holder process exits on a signal file (wait
#                            phase), staged tree replaces the two app files
#                            AND the updater itself, user payload
#                            (client/w100/payload.dat) untouched, backup
#                            carries the OLD contents at the right relative
#                            paths, relaunch stub records --healthy-marker
#                            with the marker path, update.log carries
#                            updater-start through relaunch-start in order.
#   Fixture B bad args     - omitting --staging exits 2 with the usage line,
#                            nothing mutated.
#   Fixture C fail-closed  - staged tree missing client/UpdateInstallerModern.exe
#                            aborts BEFORE any mutation: exit 2, install
#                            tree byte-identical (per-file sha256 manifest
#                            before/after), no backup created.
#   Fixture D locked file  - a powershell holder keeps one app file open
#                            (FileShare.None); the retry loop outlasts it
#                            and the swap still completes exit 0.
#                            Environment-gated: SELFUPDATE-UPDATER-SKIP-D-LOCK
#                            when the lock cannot be proven held.
#
# Environment gates (named markers, exit 0 on skip, repo convention):
#   - not Windows, or dotnet absent -> SELFUPDATE-UPDATER-SKIP-ENV (the
#     ubuntu CI fixture-tests runner has no dotnet), whole battery skips
#   - powershell absent             -> SELFUPDATE-UPDATER-SKIP-POWERSHELL,
#     fixtures A and D skip (the holder needs powershell); B and C stay
#     binding
#
# The battery can fail: swapping one expected content byte in fixture A
# (NEW-GENERATOR-v2 -> NEW-GENERATOR-vX in this file) flips its
# content-equality assert red. Can-fail was demonstrated once on a sandbox
# copy of this battery at commit time (see the 28-02 SUMMARY).
set -u

UPDATER_CSProj="src-modern/updater/host/WsusOfflineUpdater.csproj"
PROBE_DIR="ci/tests/selfupdate-probe"

FAILED_CASES=0
FIXTURE_COUNT=0

fail_case () {
    echo "FAIL: $1"
    FAILED_CASES=$((FAILED_CASES + 1))
    return 0
}

# ---------------------------------------------------------------- helpers

native_path () {
    # Hand a path to a native Windows tool (dotnet -o, powershell -File,
    # the updater argv): use the mixed Windows form so both shell and
    # native sides resolve it the same.
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -m "$1"
    else
        printf '%s' "$1"
    fi
}

localappdata_posix () {
    if [ -n "${LOCALAPPDATA:-}" ] && command -v cygpath >/dev/null 2>&1; then
        cygpath -u "$LOCALAPPDATA"
    else
        printf '%s' "${LOCALAPPDATA:-$HOME/AppData/Local}"
    fi
}

UPDATE_LOG="$(localappdata_posix)/WsusOfflineNext/selfupdate/update.log"

log_lines () {
    if [ -f "$UPDATE_LOG" ]; then
        wc -l < "$UPDATE_LOG" | tr -d '[:space:]'
    else
        echo 0
    fi
}

# segment_has MARKER SINCE_LINE: grep only the lines appended after
# SINCE_LINE so append-only log runs stay independent.
segment_has () {
    if [ "$2" -eq 0 ]; then
        grep -q "$1" "$UPDATE_LOG" 2>/dev/null
    else
        tail -n +"$(( $2 + 1 ))" "$UPDATE_LOG" 2>/dev/null | grep -q "$1"
    fi
}

snapshot_tree () {
    (cd "$1" && find . -type f | LC_ALL=C sort | xargs sha256sum 2>/dev/null)
}

cleanup () {
    # Release any holder still waiting on its signal file BEFORE removing
    # the scratch (a holder whose signal file is deleted waits forever).
    if [ -d "$SCRATCH" ]; then
        printf 'x' > "$SCRATCH/holderA.exit" 2>/dev/null
        printf 'x' > "$SCRATCH/holderD.exit" 2>/dev/null
    fi
    rm -rf "$SCRATCH" 2>/dev/null
    return 0
}
trap cleanup EXIT

# ------------------------------------------------- environment gating

IS_WINDOWS=0
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*|Windows*) IS_WINDOWS=1 ;;
esac

if [ "$IS_WINDOWS" -ne 1 ] || ! command -v dotnet >/dev/null 2>&1; then
    echo "SELFUPDATE-UPDATER-SKIP-ENV: requires Windows + dotnet (probe and published updater)"
    echo "SKIP: self-update updater battery skipped on this environment"
    exit 0
fi

HAVE_POWERSHELL=0
if command -v powershell >/dev/null 2>&1; then
    HAVE_POWERSHELL=1
else
    echo "SELFUPDATE-UPDATER-SKIP-POWERSHELL: fixtures A and D need powershell for the holder; B and C stay binding"
fi

# ---------------------------------------------------------- scratch

BASE_TMP="$(localappdata_posix)/Temp"
mkdir -p "$BASE_TMP" 2>/dev/null || BASE_TMP="$(pwd)"
SCRATCH="$(mktemp -d "$BASE_TMP/wson-selfupdate-updater.XXXXXX")" \
    || { echo "FAIL: cannot create scratch"; exit 1; }

# ================================================== section (a): hash gates

echo "--- section a: hash parse and fail-closed refusal via the probe"

dotnet build "$PROBE_DIR/SelfUpdateProbe.csproj" -v q > "$SCRATCH/probe-build.log" 2>&1
if [ $? -ne 0 ]; then
    echo "FAIL: probe project did not build"
    cat "$SCRATCH/probe-build.log"
    exit 1
fi
PROBE_EXE="$PROBE_DIR/bin/Debug/net8.0-windows/SelfUpdateProbe.exe"
[ -f "$PROBE_EXE" ] || { echo "FAIL: probe exe missing at $PROBE_EXE"; exit 1; }

run_probe () {
    "$PROBE_EXE" "$@" 2>/dev/null | tr -d '\r'
}

DIGEST64="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

check_hashes () {
    # $1 case name, $2 fixture content (printf %b argument), $3 expected verdict prefix
    FIXTURE_COUNT=$((FIXTURE_COUNT + 1))
    local fixture="$SCRATCH/hashes-$FIXTURE_COUNT.txt"
    # The content is a %b ARGUMENT, not a format string: %% has no special
    # meaning here, so the four real percent characters of the hashdeep
    # header are written as-is.
    printf '%b' "$2" > "$fixture"
    local verdict
    verdict=$(run_probe hashes "$fixture")
    case "$verdict" in
        "$3"*) echo "PASS: hashes $1 -> $verdict" ;;
        *) fail_case "hashes $1: expected $3*, got '${verdict:-<none>}'" ;;
    esac
}

check_hashes "good one-line with headers" \
    '%%%% v1.0\r\n%%%%\r\n12345,md5aaaaaaaaaaaaaaa,sha1aaaaaaaaaaaaaaaaaa,'"$DIGEST64"',wsusofflineCE-9.9.9.zip\r\n' \
    "SHA256 $DIGEST64 SIZE 12345"
check_hashes "short digest in sha256 slot rejected" \
    '%%%%\r\n12345,md5,sha1,abc123,file.zip\r\n' \
    "REJECT"
check_hashes "two data lines rejected" \
    '%%%%\r\n1,m,s,'"1$DIGEST64"',f1.zip\r\n2,m,s,'"2$DIGEST64"',f2.zip\r\n' \
    "REJECT"
check_hashes "uppercase digest rejected" \
    '%%%%\r\n9,m,s,'"$(printf '%s' "$DIGEST64" | tr 'a-f' 'A-F')"',file.zip\r\n' \
    "REJECT"
check_hashes "hashdeep ## lines filtered, one data line accepted" \
    '## Filtered\r\n## Another\r\n77,m,s,'"$DIGEST64"',wsusofflineCE-9.9.9.zip\r\n' \
    "SHA256 $DIGEST64 SIZE 77"
check_hashes "no data line rejected" \
    '%%%%\r\n## only\r\n' \
    "REJECT"
check_hashes "zero size rejected" \
    '%%%%\r\n0,m,s,'"$DIGEST64"',file.zip\r\n' \
    "REJECT"

# Fail-closed refusal comparison: the probe digest of a real fixture zip
# must match its published digest line, and a one-byte corruption must
# mismatch (the comparison VerifyZipAgainstHashes makes, driven from bash).
FIXTURE_COUNT=$((FIXTURE_COUNT + 1))
ZIPFIX="$SCRATCH/update-fixture.zip"
printf 'PK-fixture-bytes-for-the-refusal-probe-0123456789' > "$ZIPFIX"
ACTUAL=$(run_probe sha256 "$ZIPFIX")
ZIPSIZE=$(wc -c < "$ZIPFIX" | tr -d '[:space:]')
PUB="$SCRATCH/published.txt"
printf '%%%%%%%%\r\n%s,md5,sha1,%s,wsusofflineCE-9.9.9.zip\r\n' "$ZIPSIZE" "$ACTUAL" > "$PUB"
PARSED=$(run_probe hashes "$PUB")
if [ "$PARSED" = "SHA256 $ACTUAL SIZE $ZIPSIZE" ]; then
    echo "PASS: published digest parses and matches the real zip digest"
else
    fail_case "refusal setup: parsed '$PARSED' vs actual '$ACTUAL' size $ZIPSIZE"
fi
printf 'XK-fixture-bytes-for-the-refusal-probe-0123456789' > "$ZIPFIX"
TAMPERED=$(run_probe sha256 "$ZIPFIX")
if [ "$TAMPERED" != "$ACTUAL" ]; then
    echo "PASS: corrupted zip digest mismatches the published digest (fail-closed refusal)"
else
    fail_case "refusal: tampered digest equals published digest - the gate would pass a corrupt zip"
fi

echo "section a fixtures: $FIXTURE_COUNT"
if [ "$FIXTURE_COUNT" -eq 0 ]; then
    fail_case "section a enumerated zero fixtures (vacuous pass guard)"
fi

# ============================================ section (b): the updater

echo "--- section b: published updater on a scratch install tree"

dotnet publish "$UPDATER_CSProj" -c Release -r win-x64 \
    -o "$(native_path "$SCRATCH/pub")" > "$SCRATCH/publish.log" 2>&1
if [ $? -ne 0 ] || [ ! -f "$SCRATCH/pub/WsusOfflineUpdater.exe" ]; then
    echo "FAIL: updater publish failed or exe missing (see scratch publish.log)"
    cat "$SCRATCH/publish.log"
    exit 1
fi

build_fixture_tree () {
    # $1 install root, $2 staging root
    local inst="$1" stage="$2"
    rm -rf "$inst" "$stage"
    mkdir -p "$inst/client/w100" "$stage/wsusoffline/client"
    printf 'OLD-GENERATOR-v1' > "$inst/UpdateGeneratorModern.exe"
    printf 'OLD-INSTALLER-v1' > "$inst/client/UpdateInstallerModern.exe"
    printf 'USER-PAYLOAD-BYTES-0123456789' > "$inst/client/w100/payload.dat"
    cp "$SCRATCH/pub/WsusOfflineUpdater.exe" "$inst/WsusOfflineUpdater.exe"
    printf 'NEW-GENERATOR-v2' > "$stage/wsusoffline/UpdateGeneratorModern.exe"
    printf 'NEW-INSTALLER-v2' > "$stage/wsusoffline/client/UpdateInstallerModern.exe"
    printf 'NEW-UPDATER-v2' > "$stage/wsusoffline/WsusOfflineUpdater.exe"
}

cat > "$SCRATCH/holder.ps1" << 'PSEOF'
param([string]$SignalFile, [string]$PidFile)
Set-StrictMode -Version Latest
"$PID" | Out-File -FilePath $PidFile -Encoding ascii
while (-not (Test-Path -LiteralPath $SignalFile)) { Start-Sleep -Milliseconds 200 }
exit 0
PSEOF

cat > "$SCRATCH/locker.ps1" << 'PSEOF'
param([string]$FileToLock, [string]$ReadyFile, [int]$HoldSeconds)
$fs = [System.IO.File]::Open($FileToLock, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
try {
    "ready" | Out-File -FilePath $ReadyFile -Encoding ascii
    Start-Sleep -Seconds $HoldSeconds
} finally { $fs.Close() }
PSEOF

printf '@echo off\r\necho %%* >> "%%~dp0witness.txt"\r\n' > "$SCRATCH/relaunch.cmd"

start_holder () {
    # $1 scratch tag (writes $SCRATCH/$1.pid, waits for $SCRATCH/$1.exit)
    rm -f "$SCRATCH/$1.pid" "$SCRATCH/$1.exit"
    powershell -NoProfile -ExecutionPolicy Bypass \
        -File "$(native_path "$SCRATCH/holder.ps1")" \
        -SignalFile "$(native_path "$SCRATCH/$1.exit")" \
        -PidFile "$(native_path "$SCRATCH/$1.pid")" \
        > /dev/null 2>&1 &
    local i
    for (( i = 0; i < 40; i++ )); do
        [ -f "$SCRATCH/$1.pid" ] && return 0
        sleep 0.25
    done
    return 1
}

wait_updater_exit () {
    # $1 bash pid of the updater, $2 bound seconds; sets UPDATER_RC to the
    # exit code (or RUNNING). Must run in the MAIN shell - wait only works
    # on children of this shell, never from a command substitution.
    local i
    for (( i = 0; i < "$2"; i++ )); do
        kill -0 "$1" 2>/dev/null || break
        sleep 1
    done
    if kill -0 "$1" 2>/dev/null; then
        UPDATER_RC="RUNNING"
        return 0
    fi
    wait "$1"
    UPDATER_RC="$?"
    return 0
}

# ---------- Fixture A: happy path (wait, swap, backup, relaunch, payload immunity)

if [ "$HAVE_POWERSHELL" -ne 1 ]; then
    echo "SELFUPDATE-UPDATER-SKIP-A: fixture A needs powershell for the holder"
else
    echo "--- fixture A: happy path"
    ASSERT_A=0
    pass_a () { echo "PASS: A $1"; ASSERT_A=$((ASSERT_A + 1)); return 0; }

    build_fixture_tree "$SCRATCH/instA" "$SCRATCH/stageA"
    if start_holder holderA; then
        HOLDER_A=$(tr -d '\r\n ' < "$SCRATCH/holderA.pid")
        BACKUP_A="$SCRATCH/instA.bak-ts"
        MARKER_A="$SCRATCH/markerA/launch-testA.ok"
        SINCE_A=$(log_lines)
        "$SCRATCH/instA/WsusOfflineUpdater.exe" \
            --pid "$HOLDER_A" \
            --staging "$(native_path "$SCRATCH/stageA")" \
            --backup "$(native_path "$BACKUP_A")" \
            --relaunch "$(native_path "$SCRATCH/relaunch.cmd")" \
            --marker "$(native_path "$MARKER_A")" \
            > "$SCRATCH/fixtureA.log" 2>&1 &
        UPD_A=$!
        # Release the holder: the updater must observe its exit before swapping.
        printf 'x' > "$SCRATCH/holderA.exit"
        wait_updater_exit "$UPD_A" 90
        RC_A="$UPDATER_RC"
        if [ "$RC_A" = "0" ]; then
            pass_a "updater exit code 0"
        else
            fail_case "fixture A: updater exit code '$RC_A' (log: $(tail -3 "$SCRATCH/fixtureA.log" 2>/dev/null | tr '\n' ' '))"
        fi
        [ "$(cat "$SCRATCH/instA/UpdateGeneratorModern.exe" 2>/dev/null)" = "NEW-GENERATOR-v2" ] \
            && pass_a "generator replaced" \
            || fail_case "fixture A: generator not replaced"
        [ "$(cat "$SCRATCH/instA/client/UpdateInstallerModern.exe" 2>/dev/null)" = "NEW-INSTALLER-v2" ] \
            && pass_a "installer replaced" \
            || fail_case "fixture A: installer not replaced"
        [ "$(cat "$SCRATCH/instA/WsusOfflineUpdater.exe" 2>/dev/null)" = "NEW-UPDATER-v2" ] \
            && pass_a "updater replaced itself" \
            || fail_case "fixture A: updater did not replace itself"
        [ "$(cat "$SCRATCH/instA/client/w100/payload.dat" 2>/dev/null)" = "USER-PAYLOAD-BYTES-0123456789" ] \
            && pass_a "user payload untouched (bytes and path)" \
            || fail_case "fixture A: user payload was modified or moved"
        [ ! -f "$BACKUP_A/client/w100/payload.dat" ] \
            && pass_a "user payload never archived" \
            || fail_case "fixture A: payload archived into the backup"
        [ "$(cat "$BACKUP_A/UpdateGeneratorModern.exe" 2>/dev/null)" = "OLD-GENERATOR-v1" ] \
            && [ "$(cat "$BACKUP_A/client/UpdateInstallerModern.exe" 2>/dev/null)" = "OLD-INSTALLER-v1" ] \
            && cmp -s "$BACKUP_A/WsusOfflineUpdater.exe" "$SCRATCH/pub/WsusOfflineUpdater.exe" \
            && pass_a "backup carries the OLD contents at the right relative paths" \
            || fail_case "fixture A: backup contents wrong (expect OLD-*-v1 text pair plus the archived updater binary)"
        WITNESS=""
        for (( i = 0; i < 20; i++ )); do
            [ -f "$SCRATCH/witness.txt" ] && { WITNESS=$(cat "$SCRATCH/witness.txt"); break; }
            sleep 0.5
        done
        case "$WITNESS" in
            *--healthy-marker*launch-testA.ok*) pass_a "relaunch received --healthy-marker with the marker path" ;;
            *) fail_case "fixture A: witness missing marker argument (witness='${WITNESS:-<none>}')" ;;
        esac
        if segment_has "updater-start" "$SINCE_A" && segment_has "wait-exit" "$SINCE_A" \
            && segment_has "archive-start" "$SINCE_A" && segment_has "archive-complete" "$SINCE_A" \
            && segment_has "swap-complete" "$SINCE_A" && segment_has "relaunch-start" "$SINCE_A"; then
            pass_a "update.log carries updater-start through relaunch-start"
        else
            fail_case "fixture A: update.log event sequence incomplete"
        fi
        START_LINE=$(tail -n +"$(( SINCE_A + 1 ))" "$UPDATE_LOG" 2>/dev/null | grep -n "|updater|updater-start" | head -1 | cut -d: -f1)
        RELAUNCH_LINE=$(tail -n +"$(( SINCE_A + 1 ))" "$UPDATE_LOG" 2>/dev/null | grep -n "|updater|relaunch-start" | head -1 | cut -d: -f1)
        if [ -n "$START_LINE" ] && [ -n "$RELAUNCH_LINE" ] && [ "$START_LINE" -lt "$RELAUNCH_LINE" ]; then
            pass_a "event order updater-start before relaunch-start"
        else
            fail_case "fixture A: event order wrong (start=$START_LINE relaunch=$RELAUNCH_LINE)"
        fi
        echo "fixture A asserts: $ASSERT_A"
        if [ "$ASSERT_A" -lt 10 ]; then
            fail_case "fixture A asserted $ASSERT_A checks - a run that replaced nothing must not get here (broken harness guard)"
        fi
    else
        fail_case "fixture A: holder pid never appeared"
    fi
fi

# ---------- Fixture B: bad args (omit --staging)

echo "--- fixture B: missing --staging exits 2 with usage, nothing mutated"
build_fixture_tree "$SCRATCH/instB" "$SCRATCH/stageB"
SNAP_B=$(snapshot_tree "$SCRATCH/instB")
"$SCRATCH/instB/WsusOfflineUpdater.exe" \
    --pid 999999 \
    --backup "$(native_path "$SCRATCH/instB.bak")" \
    --relaunch "$(native_path "$SCRATCH/relaunch.cmd")" \
    --marker "$(native_path "$SCRATCH/markerB.ok")" \
    > "$SCRATCH/fixtureB.log" 2>&1
RC_B=$?
[ "$RC_B" -eq 2 ] && echo "PASS: B exit 2" || fail_case "fixture B: expected exit 2, got $RC_B"
grep -q "usage:" "$SCRATCH/fixtureB.log" \
    && echo "PASS: B usage printed" \
    || fail_case "fixture B: usage line not printed (output: $(head -2 "$SCRATCH/fixtureB.log" | tr '\n' ' '))"
[ "$(snapshot_tree "$SCRATCH/instB")" = "$SNAP_B" ] \
    && echo "PASS: B install tree byte-identical" \
    || fail_case "fixture B: install tree mutated on bad args"
[ ! -d "$SCRATCH/instB.bak" ] \
    && echo "PASS: B no backup created" \
    || fail_case "fixture B: backup created on bad args"

# ---------- Fixture C: fail-closed staging validation

echo "--- fixture C: incomplete staged tree aborts before any mutation"
build_fixture_tree "$SCRATCH/instC" "$SCRATCH/stageC"
rm "$SCRATCH/stageC/wsusoffline/client/UpdateInstallerModern.exe"
SNAP_C=$(snapshot_tree "$SCRATCH/instC")
"$SCRATCH/instC/WsusOfflineUpdater.exe" \
    --pid 999999 \
    --staging "$(native_path "$SCRATCH/stageC")" \
    --backup "$(native_path "$SCRATCH/instC.bak")" \
    --relaunch "$(native_path "$SCRATCH/relaunch.cmd")" \
    --marker "$(native_path "$SCRATCH/markerC.ok")" \
    > "$SCRATCH/fixtureC.log" 2>&1
RC_C=$?
[ "$RC_C" -eq 2 ] && echo "PASS: C exit 2 (validation class)" || fail_case "fixture C: expected exit 2, got $RC_C"
grep -q "incomplete" "$SCRATCH/fixtureC.log" \
    && echo "PASS: C incomplete-staging named on console" \
    || fail_case "fixture C: no incomplete-staging message (output: $(head -3 "$SCRATCH/fixtureC.log" | tr '\n' ' '))"
[ "$(snapshot_tree "$SCRATCH/instC")" = "$SNAP_C" ] \
    && echo "PASS: C install tree byte-identical" \
    || fail_case "fixture C: install tree mutated despite fail-closed staging"
[ ! -d "$SCRATCH/instC.bak" ] \
    && echo "PASS: C no backup created" \
    || fail_case "fixture C: backup created despite fail-closed staging"

# ---------- Fixture D: locked-file retry (environment-gated)

if [ "$HAVE_POWERSHELL" -ne 1 ]; then
    echo "SELFUPDATE-UPDATER-SKIP-D: fixture D needs powershell for the holders"
else
    echo "--- fixture D: locked file outlasted by the retry loop"
    build_fixture_tree "$SCRATCH/instD" "$SCRATCH/stageD"
    rm -f "$SCRATCH/lockerD.ready"
    powershell -NoProfile -ExecutionPolicy Bypass \
        -File "$(native_path "$SCRATCH/locker.ps1")" \
        -FileToLock "$(native_path "$SCRATCH/instD/UpdateGeneratorModern.exe")" \
        -ReadyFile "$(native_path "$SCRATCH/lockerD.ready")" \
        -HoldSeconds 6 > /dev/null 2>&1 &
    LOCK_READY=0
    for (( i = 0; i < 20; i++ )); do
        [ -f "$SCRATCH/lockerD.ready" ] && { LOCK_READY=1; break; }
        sleep 0.5
    done
    if [ "$LOCK_READY" -ne 1 ]; then
        echo "SELFUPDATE-UPDATER-SKIP-D-LOCK: this environment cannot hold a Windows file handle (locker never became ready)"
    else
        if start_holder holderD; then
            HOLDER_D=$(tr -d '\r\n ' < "$SCRATCH/holderD.pid")
            "$SCRATCH/instD/WsusOfflineUpdater.exe" \
                --pid "$HOLDER_D" \
                --staging "$(native_path "$SCRATCH/stageD")" \
                --backup "$(native_path "$SCRATCH/instD.bak")" \
                --relaunch "$(native_path "$SCRATCH/relaunch.cmd")" \
                --marker "$(native_path "$SCRATCH/markerD.ok")" \
                > "$SCRATCH/fixtureD.log" 2>&1 &
            UPD_D=$!
            printf 'x' > "$SCRATCH/holderD.exit"
            wait_updater_exit "$UPD_D" 90
            RC_D="$UPDATER_RC"
            if [ "$RC_D" = "0" ]; then
                echo "PASS: D swap completed exit 0 despite the lock"
            else
                fail_case "fixture D: exit '$RC_D' (log: $(grep -c "failed" "$SCRATCH/fixtureD.log" 2>/dev/null) retry lines)"
            fi
            [ "$(cat "$SCRATCH/instD/UpdateGeneratorModern.exe" 2>/dev/null)" = "NEW-GENERATOR-v2" ] \
                && echo "PASS: D locked file replaced after retries" \
                || fail_case "fixture D: locked file never replaced"
        else
            fail_case "fixture D: holder pid never appeared"
        fi
    fi
fi

# ------------------------------------------------------------- verdict

if [ "$FAILED_CASES" -ne 0 ]; then
    echo "SELFUPDATE-UPDATER: RED ($FAILED_CASES failing case(s))"
    exit 1
fi
echo "SELFUPDATE-UPDATER: GREEN"
exit 0
