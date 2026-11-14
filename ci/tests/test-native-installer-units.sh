#!/usr/bin/env bash
#
# test-native-installer-units.sh
#
# Fail-closed pure-unit gate for the native installer (plan 26-02).
#
#   - resolves the toolchain like the spine gate: WO_LAZARUS_ROOT
#     override, else the documented scratch default
#     .planning/tmp/23-tools/lazarus (Phase 27 replaces this resolution
#     with the production lane)
#   - compiles the console testrunner (Release-i386 only; the runner
#     links the production units without the LCL forms)
#   - runs it and fail-closes on ANY `not ok` TAP line, a non-zero
#     UNIT-FAIL count, a missing summary line, or a TAP count below the
#     upg-parse-/upg-case- floors (>=5 / >=19 - review WR-03: the phase
#     record's floor claim is only real if a committed instrument
#     enforces it)
#   - prints UNIT-GATE-PASS at the end.

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

WO_LAZARUS_ROOT="${WO_LAZARUS_ROOT:-$REPO_ROOT/.planning/tmp/23-tools/lazarus}"
LAZBUILD="$WO_LAZARUS_ROOT/lazbuild.exe"

fail() {
    echo "ERROR: $1" >&2
    exit 1
}

[ -f "$LAZBUILD" ] \
    || fail "lazbuild.exe not found at $LAZBUILD (set WO_LAZARUS_ROOT to the Lazarus root)"
[ -f "$WO_LAZARUS_ROOT/fpc/3.2.2/bin/x86_64-win64/ppc386.exe" ] \
    || fail "ppc386.exe (i386-win32 cross units) not found under $WO_LAZARUS_ROOT - the i386 build is impossible"

RUNNER_LPI="$REPO_ROOT/src-native/installer/tests/testrunner.lpi"
[ -f "$RUNNER_LPI" ] || fail "testrunner project not found: $RUNNER_LPI"

echo "== [1/3] Pre-clean the testrunner build output (a stale artifact must never mask a locked build)..."
rm -f "$REPO_ROOT/src-native/installer/tests/bin/testrunner-i386.exe" \
    || fail "stale testrunner output is locked - close any running testrunner instance and retry"

echo "== [2/3] lazbuild testrunner Release-i386 (i386-win32)..."
"$LAZBUILD" --build-mode=Release-i386 "$(cygpath -w "$RUNNER_LPI")" \
    || fail "lazbuild Release-i386 failed for the testrunner"
RUNNER_EXE="$REPO_ROOT/src-native/installer/tests/bin/testrunner-i386.exe"
[ -f "$RUNNER_EXE" ] || fail "testrunner-i386.exe was not produced"

echo "== [3/3] Running the pure-unit battery..."
RUN_LOG="$RUNNER_EXE.log"
"$RUNNER_EXE" > "$RUN_LOG" 2>&1
rc=$?

grep -E "^ok [0-9]+ - " "$RUN_LOG" | tail -3
NOT_OK_COUNT="$(grep -c "^not ok " "$RUN_LOG" || true)"
UNIT_FAIL_LINE="$(grep -E "^UNIT-FAIL:[0-9]+$" "$RUN_LOG" | tail -1 || true)"

if [ "$NOT_OK_COUNT" -ne 0 ]; then
    echo "--- testrunner output ($RUN_LOG) ---"
    cat "$RUN_LOG"
    fail "$NOT_OK_COUNT failed unit case(s)"
fi

# TAP count floors for the upgrades decision layer (review WR-03): a
# deleted TestUpgradesParser/TestUpgradesVerdict call (or dropped cases)
# would otherwise leave every other check green. Shipped reality is
# 5 upg-parse- cases and 20 upg-case- cases; the floors sit below.
UPG_PARSE_OK="$(grep -c '^ok [0-9]* - upg-parse-' "$RUN_LOG" || true)"
UPG_CASE_OK="$(grep -c '^ok [0-9]* - upg-case-' "$RUN_LOG" || true)"
if [ "$UPG_PARSE_OK" -lt 5 ]; then
    echo "--- testrunner output ($RUN_LOG) ---"
    cat "$RUN_LOG"
    fail "upg-parse- floor violated: $UPG_PARSE_OK < 5"
fi
if [ "$UPG_CASE_OK" -lt 19 ]; then
    echo "--- testrunner output ($RUN_LOG) ---"
    cat "$RUN_LOG"
    fail "upg-case- floor violated: $UPG_CASE_OK < 19"
fi

# Plan 36-02 consent-layer floors: the same WR-03 logic over the
# consent battery - a deleted consent case family (or dropped cases)
# would otherwise leave every other check green. Shipped reality is
# 3 consent-family-, 3 consent-gate-, 11 consent-map-, 6 consent-pick-,
# 4 consent-disk- and (plan 36-04) 3 consent-argv- cases; the floors
# sit below.
CONS_FAMILY_OK="$(grep -c '^ok [0-9]* - consent-family-' "$RUN_LOG" || true)"
CONS_GATE_OK="$(grep -c '^ok [0-9]* - consent-gate-' "$RUN_LOG" || true)"
CONS_MAP_OK="$(grep -c '^ok [0-9]* - consent-map-' "$RUN_LOG" || true)"
CONS_PICK_OK="$(grep -c '^ok [0-9]* - consent-pick-' "$RUN_LOG" || true)"
CONS_DISK_OK="$(grep -c '^ok [0-9]* - consent-disk-' "$RUN_LOG" || true)"
CONS_ARGV_OK="$(grep -c '^ok [0-9]* - consent-argv-' "$RUN_LOG" || true)"
if [ "$CONS_FAMILY_OK" -lt 2 ]; then
    echo "--- testrunner output ($RUN_LOG) ---"
    cat "$RUN_LOG"
    fail "consent-family- floor violated: $CONS_FAMILY_OK < 2"
fi
if [ "$CONS_GATE_OK" -lt 3 ]; then
    echo "--- testrunner output ($RUN_LOG) ---"
    cat "$RUN_LOG"
    fail "consent-gate- floor violated: $CONS_GATE_OK < 3"
fi
if [ "$CONS_MAP_OK" -lt 10 ]; then
    echo "--- testrunner output ($RUN_LOG) ---"
    cat "$RUN_LOG"
    fail "consent-map- floor violated: $CONS_MAP_OK < 10"
fi
if [ "$CONS_PICK_OK" -lt 3 ]; then
    echo "--- testrunner output ($RUN_LOG) ---"
    cat "$RUN_LOG"
    fail "consent-pick- floor violated: $CONS_PICK_OK < 3"
fi
if [ "$CONS_DISK_OK" -lt 2 ]; then
    echo "--- testrunner output ($RUN_LOG) ---"
    cat "$RUN_LOG"
    fail "consent-disk- floor violated: $CONS_DISK_OK < 2"
fi
if [ "$CONS_ARGV_OK" -lt 3 ]; then
    echo "--- testrunner output ($RUN_LOG) ---"
    cat "$RUN_LOG"
    fail "consent-argv- floor violated: $CONS_ARGV_OK < 3"
fi

if [ -z "$UNIT_FAIL_LINE" ]; then
    echo "--- testrunner output ($RUN_LOG) ---"
    cat "$RUN_LOG"
    fail "no UNIT-FAIL:<count> summary line - the runner did not complete"
fi

UNIT_FAIL_COUNT="${UNIT_FAIL_LINE#UNIT-FAIL:}"
if [ "$UNIT_FAIL_COUNT" -ne 0 ]; then
    echo "--- testrunner output ($RUN_LOG) ---"
    cat "$RUN_LOG"
    fail "UNIT-FAIL count is $UNIT_FAIL_COUNT"
fi

if [ "$rc" -ne 0 ]; then
    echo "--- testrunner output ($RUN_LOG) ---"
    cat "$RUN_LOG"
    fail "testrunner exited $rc despite a zero UNIT-FAIL count"
fi

echo "UNIT-GATE-PASS"
