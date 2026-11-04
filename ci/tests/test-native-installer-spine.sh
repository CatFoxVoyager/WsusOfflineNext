#!/usr/bin/env bash
#
# test-native-installer-spine.sh
#
# Wave-0 compile+probe gate for the native installer spine (plan 26-01).
#
#   - resolves the scratch Lazarus toolchain: WO_LAZARUS_ROOT override,
#     else the documented scratch default .planning/tmp/23-tools/lazarus
#     (Phase 27 replaces this resolution with the production lane)
#   - builds the installer AND the spine probe in Release-i386 and
#     Release-x64 via lazbuild --build-mode
#   - stages a fixture client tree in a temp dir (READ-ONLY copies from
#     client/ - nothing under client/ is ever modified) and adds the stub
#     content that opens the two presence gates (\cpp\vcredist-x.exe,
#     \md\)
#   - runs the spine probe for BOTH arch binaries against the fixture;
#     every run must exit 0 and its stdout must carry at least one
#     STREAM: line and an OBSERVED-EXIT:<code> line
#   - fail-closed on every step; prints SPINE-PROBE-PASS at the end.

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

INSTALLER_LPI="$REPO_ROOT/src-native/installer/installer.lpi"
PROBE_LPI="$REPO_ROOT/src-native/installer/tests/spineprobe.lpi"
[ -f "$INSTALLER_LPI" ] || fail "installer project not found: $INSTALLER_LPI"
[ -f "$PROBE_LPI" ] || fail "spine probe project not found: $PROBE_LPI"

echo "== [1/5] lazbuild installer Release-i386 (i386-win32)..."
"$LAZBUILD" --build-mode=Release-i386 "$(cygpath -w "$INSTALLER_LPI")" \
    || fail "lazbuild Release-i386 failed for the installer"
I386_EXE="$REPO_ROOT/src-native/installer/bin/installer-i386.exe"
[ -f "$I386_EXE" ] || fail "installer-i386.exe was not produced"

echo "== [2/5] lazbuild installer Release-x64 (x86_64-win64)..."
"$LAZBUILD" --build-mode=Release-x64 "$(cygpath -w "$INSTALLER_LPI")" \
    || fail "lazbuild Release-x64 failed for the installer"
X64_EXE="$REPO_ROOT/src-native/installer/bin/installer-x64.exe"
[ -f "$X64_EXE" ] || fail "installer-x64.exe was not produced"

echo "== [3/5] lazbuild spine probe (both arches)..."
"$LAZBUILD" --build-mode=Release-i386 "$(cygpath -w "$PROBE_LPI")" \
    || fail "lazbuild Release-i386 failed for the spine probe"
"$LAZBUILD" --build-mode=Release-x64 "$(cygpath -w "$PROBE_LPI")" \
    || fail "lazbuild Release-x64 failed for the spine probe"
PROBE_I386="$REPO_ROOT/src-native/installer/tests/bin/spineprobe-i386.exe"
PROBE_X64="$REPO_ROOT/src-native/installer/tests/bin/spineprobe-x64.exe"
[ -f "$PROBE_I386" ] || fail "spineprobe-i386.exe was not produced"
[ -f "$PROBE_X64" ] || fail "spineprobe-x64.exe was not produced"

echo "== [4/5] Staging fixture client tree (read-only copies from client/)..."
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/cmd" "$FIXTURE/cpp" "$FIXTURE/md"
cp -r "$REPO_ROOT/client/cmd/." "$FIXTURE/cmd/" \
    || fail "cannot copy client/cmd/ into the fixture"
cp -r "$REPO_ROOT/client/UpdateTable" "$FIXTURE/UpdateTable" \
    || fail "cannot copy client/UpdateTable into the fixture"
[ -f "$REPO_ROOT/client/builddate.txt" ] \
    || fail "client/builddate.txt missing from the repo - fixture incomplete"
cp "$REPO_ROOT/client/builddate.txt" "$FIXTURE/builddate.txt" \
    || fail "cannot copy client/builddate.txt into the fixture"
[ -f "$REPO_ROOT/client/UpdateInstaller.ini" ] \
    || fail "client/UpdateInstaller.ini missing from the repo - fixture incomplete"
cp "$REPO_ROOT/client/UpdateInstaller.ini" "$FIXTURE/UpdateInstaller.ini" \
    || fail "cannot copy client/UpdateInstaller.ini into the fixture"
printf 'stub vcredist fixture for the cpp presence gate\n' > "$FIXTURE/cpp/vcredist-x.exe" \
    || fail "cannot write the cpp stub into the fixture"
printf 'stub hash fixture for the md presence gate\n' > "$FIXTURE/md/hashes-fixture.txt" \
    || fail "cannot write the md stub into the fixture"

echo "== [5/5] Running the spine probe against the real engine (both arches)..."
run_probe() {
    probe_exe="$1"
    log="$FIXTURE/probe-$(basename "$probe_exe" .exe).log"
    "$probe_exe" "$(cygpath -w "$FIXTURE")" > "$log" 2>&1
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "--- probe output ($log) ---"
        cat "$log"
        fail "$(basename "$probe_exe") exited $rc (expected 0)"
    fi
    grep -q "STREAM:" "$log" || {
        echo "--- probe output ($log) ---"
        cat "$log"
        fail "no STREAM: line in $(basename "$probe_exe") output"
    }
    grep -q "OBSERVED-EXIT:" "$log" || {
        echo "--- probe output ($log) ---"
        cat "$log"
        fail "no OBSERVED-EXIT: line in $(basename "$probe_exe") output"
    }
    # The engine's own hardcoded-English startup line proves the REAL
    # engine ran - a bare cmd error ("not recognized") would also stream
    # lines and exit 1, which must fail this gate.
    grep -q "Starting WSUS Offline Next" "$log" || {
        echo "--- probe output ($log) ---"
        cat "$log"
        fail "$(basename "$probe_exe") did not drive the real engine (no 'Starting WSUS Offline Next' startup line)"
    }
    echo "--- $(basename "$probe_exe"): first lines + observed exit ---"
    grep "STREAM:" "$log" | head -3
    grep "OBSERVED-EXIT:" "$log"
}

run_probe "$PROBE_I386"
run_probe "$PROBE_X64"

echo "SPINE-PROBE-PASS"
