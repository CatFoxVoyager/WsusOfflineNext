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
#     UNIT-FAIL count, or a missing summary line
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
