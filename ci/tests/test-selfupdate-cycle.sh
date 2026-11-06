#!/usr/bin/env bash
# Full-cycle self-update battery (Phase 28 plan 03) - the phase end-to-end
# proof on a SCRATCH INSTALLATION against a local fake channel. Run from
# repo root. Never touches the repo tree: the installation, the channel
# and the updater's %TEMP% surface all live under the scratch.
#
# One scenario proves the whole chain against the REAL published binaries:
#   offer (check slice) -> accept (WSON_UPDATE_AUTO_ACCEPT=1, no dialogs)
#   -> verified download from the local fake channel (WSON_UPDATE_ALLOW_HTTP=1
#   relaxes ONLY the https scheme pin so 127.0.0.1 can serve the package)
#   -> staging -> the app exits by itself (restart-now auto-answers Yes)
#   -> WsusOfflineUpdater waits for the pid, swaps the tree, relaunches.
#
#   HEALTHY: the fixture zip's relaunch slot is a real executable built
#   from the same source with -p:Version=9.0.0+2099.01 (byte-distinct from
#   the installed OLD build): the NEW app writes the healthy-launch marker
#   after its window opens, the updater logs marker-received, cleans the
#   staging tree and keeps exactly the newest backup.
#
#   BROKEN: the fixture zip's relaunch slot is a non-executable renamed
#   .exe (hashes regenerated for the new zip): the updater logs
#   relaunch-failed, restores the tree from the backup, relaunches the OLD
#   app WITHOUT the marker argument (rollback-complete), and the OLD app
#   is proven running again before it is killed.
#
#   NATIVE-HEALTHY (29-02): the same full cycle driven by the native
#   FPC installer (client/UpdateInstallerLegacy.exe, i386 lazbuild lane)
#   as the offer/accept host: the OLD native build accepts the offer,
#   the accept pipeline verifies the download (fail-closed SHA256),
#   stages, hands off to the real updater with the frozen CLI, exits by
#   itself (WSON_UPDATE_AUTO_ACCEPT closes the form), the updater swaps
#   the byte-distinct NEW native build into client/UpdateInstallerLegacy.exe
#   and relaunches it with --healthy-marker: the relaunched app writes
#   the marker (first line 9.0.0) only after its window shows, the
#   daily cache keeps it from re-offering (update-accepted exactly
#   once), and no rollback happens.
#
#   NATIVE-BROKEN (29-02): the same native cycle with a non-executable
#   relaunch slot (hashes regenerated): the updater cannot relaunch the
#   new build, the watchdog restores the OLD native build into
#   client/UpdateInstallerLegacy.exe (sha-asserted), relaunches it, and
#   no marker file remains.
#
#   Both NATIVE scenarios run from an ELEVATED shell - the shipped
#   UpdateInstallerLegacy.exe carries a requireAdministrator manifest,
#   and the asInvoker updater must inherit real elevation from it (no
#   new UAC prompt, SC4). A non-elevated shell (or a missing
#   WO_LAZARUS_ROOT) skips them with the named marker
#   SELFUPDATE-CYCLE-NATIVE-SKIP; the .NET scenarios above stay binding.
#
# The relaunched app re-runs its launch check: the daily cache (written by
# the first instance BEFORE the offer) makes it log check-skip-cache - that
# is the update-loop guard, and each scenario asserts update-accepted
# happened exactly once.
#
# Exit-code note: the updater is a GRANDCHILD of this script (the app
# launches it), so its exit code is not capturable here; exit 0 is asserted
# through its exit-0-only effects (marker-received, staging deleted, no
# rollback) and exit 4 through rollback-complete plus the restored tree.
#
# Can-fail control (documented contract): corrupting the fixture zip AFTER
# the hashes file is generated flips HEALTHY to hash-mismatch with NOTHING
# applied - the fail-closed refusal the updater battery proves at the parse
# level, here through the real app (the update.log segment would carry
# hash-mismatch, no staged, no updater-launched, the app still running).
#
# Environment gates (named markers, exit 0 on skip, repo convention):
#   - not Windows, or dotnet absent -> SELFUPDATE-CYCLE-SKIP-ENV
#   - powershell absent             -> SELFUPDATE-CYCLE-SKIP-POWERSHELL
#   - python absent                 -> SELFUPDATE-CYCLE-SKIP-PYTHON
set -u

GEN_CSproj="src-modern/generator/host/UpdateGenerator.csproj"
UPDATER_CSproj="src-modern/updater/host/WsusOfflineUpdater.csproj"
APP_SLOT="UpdateGeneratorModern.exe"

FAILED_CASES=0
SCENARIO_EVENTS=0

fail_case () {
    echo "FAIL: $1"
    FAILED_CASES=$((FAILED_CASES + 1))
    return 0
}

# ---------------------------------------------------------------- helpers

native_path () {
    if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

localappdata_posix () {
    if [ -n "${LOCALAPPDATA:-}" ] && command -v cygpath >/dev/null 2>&1; then
        cygpath -u "$LOCALAPPDATA"
    else
        printf '%s' "${LOCALAPPDATA:-$HOME/AppData/Local}"
    fi
}

STATE_DIR="$(localappdata_posix)/WsusOfflineNext/selfupdate"
UPDATE_LOG="$STATE_DIR/update.log"

log_lines () {
    if [ -f "$UPDATE_LOG" ]; then wc -l < "$UPDATE_LOG" | tr -d '[:space:]'; else echo 0; fi
}

segment_has () {
    if [ "$2" -eq 0 ]; then
        grep -q "$1" "$UPDATE_LOG" 2>/dev/null
    else
        tail -n +"$(( $2 + 1 ))" "$UPDATE_LOG" 2>/dev/null | grep -q "$1"
    fi
}

segment_count () {
    if [ "$2" -eq 0 ]; then
        grep -c "$1" "$UPDATE_LOG" 2>/dev/null || true
    else
        tail -n +"$(( $2 + 1 ))" "$UPDATE_LOG" 2>/dev/null | grep -c "$1" || true
    fi
}

wait_for_segment_marker () {
    # $1 marker, $2 since-line, $3 bound seconds
    local i
    for (( i = 0; i < "$3"; i++ )); do
        segment_has "$1" "$2" && return 0
        sleep 1
    done
    return 1
}

clear_state () {
    rm -rf "$STATE_DIR"
}

ps_path () {
    # Windows-native backslash form: PowerShell's $_.Path compares with
    # backslash separators - the mixed form never matches.
    if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi
}

count_by_path () {
    # Process census by executable path: immune to pid reuse, precise
    # about WHICH instance is alive (the scratch install's own exe).
    powershell -NoProfile -Command \
        "@(Get-Process | Where-Object { \$_.Path -eq '$(ps_path "$1")' }).Count" \
        2>/dev/null | tr -d '\r\n '
}

kill_by_path () {
    powershell -NoProfile -Command \
        "Get-Process | Where-Object { \$_.Path -eq '$(ps_path "$1")' } | Stop-Process -Force" \
        >/dev/null 2>&1
    return 0
}

cleanup () {
    if [ -n "${SCRATCH:-}" ]; then
        [ -n "${INST_H:-}" ] && kill_by_path "$INST_H/$APP_SLOT"
        [ -n "${INST_B:-}" ] && kill_by_path "$INST_B/$APP_SLOT"
        [ -n "${NINST:-}" ] && kill_by_path "$NINST/client/UpdateInstallerLegacy.exe"
    fi
    # Any leaked native instance (from a crashed earlier battery) holds
    # the repo-tree build output - kill by NAME (29-01 convention).
    powershell -NoProfile -Command \
        "Get-Process -Name 'UpdateInstallerLegacy' -ErrorAction SilentlyContinue | Stop-Process -Force" \
        >/dev/null 2>&1
    if [ -n "${FAKE_PORT:-}" ]; then
        local listener
        listener=$(netstat -ano 2>/dev/null | grep ":${FAKE_PORT}" | grep -i LISTENING \
            | awk '{print $NF}' | head -1)
        if [ -n "$listener" ]; then
            powershell -NoProfile -Command "Stop-Process -Id $listener -Force" \
                >/dev/null 2>&1
        fi
    fi
    if [ -n "${NATIVE_FAKE_PORT:-}" ]; then
        local nlistener
        nlistener=$(netstat -ano 2>/dev/null | grep ":${NATIVE_FAKE_PORT}" | grep -i LISTENING \
            | awk '{print $NF}' | head -1)
        if [ -n "$nlistener" ]; then
            powershell -NoProfile -Command "Stop-Process -Id $nlistener -Force" \
                >/dev/null 2>&1
        fi
    fi
    rm -rf "${SCRATCH:-/nonexistent-wson-cycle}" 2>/dev/null
    return 0
}
trap cleanup EXIT

# ------------------------------------------------- environment gating

IS_WINDOWS=0
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*|Windows*) IS_WINDOWS=1 ;;
esac

if [ "$IS_WINDOWS" -ne 1 ] || ! command -v dotnet >/dev/null 2>&1; then
    echo "SELFUPDATE-CYCLE-SKIP-ENV: requires Windows + dotnet (real published binaries)"
    echo "SKIP: self-update cycle battery skipped on this environment"
    exit 0
fi
if ! command -v powershell >/dev/null 2>&1; then
    echo "SELFUPDATE-CYCLE-SKIP-POWERSHELL: app launch/kill and holders need powershell"
    exit 0
fi
if ! command -v python >/dev/null 2>&1; then
    echo "SELFUPDATE-CYCLE-SKIP-PYTHON: the fake channel server and fixture zip need python"
    exit 0
fi

# ---------------------------------------------------------- scratch

BASE_TMP="$(localappdata_posix)/Temp"
mkdir -p "$BASE_TMP" 2>/dev/null || BASE_TMP="$(pwd)"
SCRATCH="$(mktemp -d "$BASE_TMP/wson-selfupdate-cycle.XXXXXX")" \
    || { echo "FAIL: cannot create scratch"; exit 1; }
# Isolate the app's and updater's %TEMP% surface (staging, backup
# fallback, pruning) inside the scratch - never the real user temp.
UPDATER_TEMP="$SCRATCH/tmpdir"
mkdir -p "$UPDATER_TEMP"

echo "--- publish: OLD build (repo version), NEW build (channel version), updater"

dotnet publish "$GEN_CSproj" -c Release -r win-x64 -p:PublishSingleFile=true \
    -p:SelfContained=false -o "$(native_path "$SCRATCH/pub-old")" \
    > "$SCRATCH/pub-old.log" 2>&1
if [ $? -ne 0 ] || [ ! -f "$SCRATCH/pub-old/UpdateGenerator.exe" ]; then
    echo "FAIL: OLD generator publish failed"
    tail -5 "$SCRATCH/pub-old.log"
    exit 1
fi
dotnet publish "$GEN_CSproj" -c Release -r win-x64 -p:PublishSingleFile=true \
    -p:SelfContained=false -p:Version=9.0.0+2099.01 \
    -o "$(native_path "$SCRATCH/pub-new")" > "$SCRATCH/pub-new.log" 2>&1
if [ $? -ne 0 ] || [ ! -f "$SCRATCH/pub-new/UpdateGenerator.exe" ]; then
    echo "FAIL: NEW generator publish failed"
    tail -5 "$SCRATCH/pub-new.log"
    exit 1
fi
dotnet publish "$UPDATER_CSproj" -c Release -r win-x64 -p:PublishSingleFile=true \
    -p:SelfContained=false -o "$(native_path "$SCRATCH/pub-updater")" \
    > "$SCRATCH/pub-updater.log" 2>&1
if [ $? -ne 0 ] || [ ! -f "$SCRATCH/pub-updater/WsusOfflineUpdater.exe" ]; then
    echo "FAIL: updater publish failed"
    tail -5 "$SCRATCH/pub-updater.log"
    exit 1
fi

OLD_SHA=$(sha256sum "$SCRATCH/pub-old/UpdateGenerator.exe" | cut -d' ' -f1)
NEW_SHA=$(sha256sum "$SCRATCH/pub-new/UpdateGenerator.exe" | cut -d' ' -f1)
if [ "$OLD_SHA" = "$NEW_SHA" ]; then
    echo "FAIL: OLD and NEW builds are byte-identical - the slot-content asserts would be vacuous"
    exit 1
fi

# ---------------------------------------------------------- fake channel

FAKE_PORT=$(( (RANDOM % 2000) + 50000 ))
SERVE_DIR="$SCRATCH/channel"
mkdir -p "$SERVE_DIR"
printf '9.0.0+2099.01,release\r\n' > "$SERVE_DIR/SelfUpdateVersion-recent.txt"
printf 'http://127.0.0.1:%s/release.zip\r\nhttp://127.0.0.1:%s/release_hashes.txt\r\n' \
    "$FAKE_PORT" "$FAKE_PORT" > "$SERVE_DIR/StaticDownloadLink-recent.txt"

build_fixture_zip () {
    # $1 = executable (or non-executable) to place in the relaunch slot;
    # builds $SERVE_DIR/release.zip plus the MEASURED-format hashes file
    # (%%%% headers, one data line, field 0 = size, field 3 = sha256).
    local src_exe="$1" zsize zsha
    rm -rf "$SCRATCH/zipstage"
    mkdir -p "$SCRATCH/zipstage/wsusoffline/client"
    cp "$src_exe" "$SCRATCH/zipstage/wsusoffline/$APP_SLOT"
    printf 'placeholder-installer' > "$SCRATCH/zipstage/wsusoffline/client/UpdateInstallerModern.exe"
    printf 'placeholder-updater' > "$SCRATCH/zipstage/wsusoffline/WsusOfflineUpdater.exe"
    rm -f "$SERVE_DIR/release.zip"
    # Directory argument (NOT explicit files): the zipfile CLI stores
    # basename-only arcnames for file arguments - the wsusoffline/ prefix
    # the guarded extraction and staging-completeness checks rely on only
    # survives via the recursive directory walk.
    ( cd "$SCRATCH/zipstage" && python -m zipfile -c \
        "$(native_path "$SERVE_DIR/release.zip")" wsusoffline )
    if [ $? -ne 0 ] || [ ! -s "$SERVE_DIR/release.zip" ]; then
        echo "FAIL: fixture zip creation failed"
        exit 1
    fi
    zsize=$(wc -c < "$SERVE_DIR/release.zip" | tr -d '[:space:]')
    zsha=$(sha256sum "$SERVE_DIR/release.zip" | cut -d' ' -f1)
    printf '%b' "%%%% v1.0\r\n%%%%\r\n$zsize,md5x,sha1x,$zsha,wsusofflineCE-9.9.9.zip\r\n" \
        > "$SERVE_DIR/release_hashes.txt"
}

assemble_install () {
    # $1 = install root; the OLD app is the real published generator.
    local inst="$1"
    rm -rf "$inst"
    mkdir -p "$inst/client/w100"
    cp "$SCRATCH/pub-old/UpdateGenerator.exe" "$inst/$APP_SLOT"
    cp -r "$SCRATCH/pub-old/wwwroot" "$inst/wwwroot" 2>/dev/null || true
    cp "$SCRATCH/pub-updater/WsusOfflineUpdater.exe" "$inst/WsusOfflineUpdater.exe"
    printf '%b' '[Control]\r\nSkipSelfUpdate=Disabled\r\n' > "$inst/client/UpdateInstaller.ini"
    printf 'cycle-payload' > "$inst/client/w100/payload.dat"
}

launch_app () {
    # $1 = install root. All test hooks + TEMP isolation ride the env; the
    # updater and the relaunched app inherit everything they need.
    WSON_UPDATE_CHANNEL_URL="http://127.0.0.1:$FAKE_PORT/SelfUpdateVersion-recent.txt" \
    WSON_UPDATE_LINKS_URL="http://127.0.0.1:$FAKE_PORT/StaticDownloadLink-recent.txt" \
    WSON_UPDATE_LOCAL_VERSION="1.0.0" \
    WSON_UPDATE_AUTO_ACCEPT="1" \
    WSON_UPDATE_ALLOW_HTTP="1" \
    TEMP="$(native_path "$UPDATER_TEMP")" TMP="$(native_path "$UPDATER_TEMP")" \
    "$1/$APP_SLOT" > /dev/null 2>&1 &
}

( cd "$SERVE_DIR" && python -m http.server "$FAKE_PORT" --bind 127.0.0.1 \
    > "$SCRATCH/httpd.log" 2>&1 & )

SERVER_READY=1
for (( i = 0; i < 20; i++ )); do
    if python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:$FAKE_PORT/SelfUpdateVersion-recent.txt', timeout=2).status == 200 else 1)" 2>/dev/null; then
        SERVER_READY=0
        break
    fi
    sleep 0.5
done
if [ "$SERVER_READY" -ne 0 ]; then
    echo "FAIL: fake channel server never became ready on port $FAKE_PORT"
    exit 1
fi

# --------------------------------------------- scenario: HEALTHY cycle

echo "--- scenario HEALTHY: accept -> updater -> swap -> healthy relaunch"
SCENARIO_EVENTS=0
pass_h () { echo "PASS: H $1"; SCENARIO_EVENTS=$((SCENARIO_EVENTS + 1)); return 0; }

INST_H="$SCRATCH/instH"
assemble_install "$INST_H"
build_fixture_zip "$SCRATCH/pub-new/UpdateGenerator.exe"

clear_state
SINCE_H=$(log_lines)
launch_app "$INST_H"

if wait_for_segment_marker "marker-received" "$SINCE_H" 150; then
    pass_h "updater reached marker-received"
else
    fail_case "HEALTHY: marker-received never appeared (last log: $(tail -5 "$UPDATE_LOG" 2>/dev/null | tr '\n' ' '))"
fi
sleep 3   # let the updater finish staging cleanup and backup pruning

for ev in update-offered update-accepted hash-verified staged updater-launched wait-exit relaunch-start marker-written; do
    if segment_has "$ev" "$SINCE_H"; then
        pass_h "$ev logged"
    else
        fail_case "HEALTHY: $ev missing from the log segment"
    fi
done

ACCEPTED_H=$(segment_count "update-accepted" "$SINCE_H")
if [ "$ACCEPTED_H" -eq 1 ]; then
    pass_h "update-accepted exactly once (no re-offer loop)"
else
    fail_case "HEALTHY: update-accepted count=$ACCEPTED_H - the relaunched app re-offered"
fi
if segment_has "check-skip-cache" "$SINCE_H"; then
    pass_h "relaunched app logged check-skip-cache (daily cache loop guard)"
else
    fail_case "HEALTHY: check-skip-cache missing - the relaunched app re-checked the network"
fi
if segment_has "marker-timeout" "$SINCE_H" || segment_has "rollback-complete" "$SINCE_H"; then
    fail_case "HEALTHY: rollback events present in a healthy cycle"
else
    pass_h "no rollback events (exit-0 branch by construction)"
fi

SLOT_SHA_H=$(sha256sum "$INST_H/$APP_SLOT" 2>/dev/null | cut -d' ' -f1)
if [ "$SLOT_SHA_H" = "$NEW_SHA" ]; then
    pass_h "relaunch slot now carries the NEW exe (sha-distinct from the old)"
else
    fail_case "HEALTHY: relaunch slot does not carry the NEW exe"
fi
BACKUP_H=$(ls -d "$INST_H".bak-* 2>/dev/null | head -1)
if [ -n "$BACKUP_H" ] && [ "$(sha256sum "$BACKUP_H/$APP_SLOT" 2>/dev/null | cut -d' ' -f1)" = "$OLD_SHA" ]; then
    pass_h "backup folder exists and carries the OLD exe (manual-restore path)"
else
    fail_case "HEALTHY: backup missing or not carrying the OLD exe (backup=${BACKUP_H:-<none>})"
fi
MARKER_FILE=$(ls "$STATE_DIR/"launch-*.ok 2>/dev/null | head -1)
if [ -n "$MARKER_FILE" ]; then
    pass_h "healthy-launch marker file exists"
else
    fail_case "HEALTHY: marker file missing"
fi
MARKER_VER=$(head -1 "$MARKER_FILE" 2>/dev/null | tr -d '\r\n ')
if [ "$MARKER_VER" = "9.0.0" ]; then
    pass_h "marker written by the NEW version (first line 9.0.0)"
else
    fail_case "HEALTHY: marker first line is '${MARKER_VER:-<empty>}', expected 9.0.0"
fi
if ls -d "$UPDATER_TEMP/WsusOfflineNext-Update/"stage-* >/dev/null 2>&1; then
    fail_case "HEALTHY: staging tree not cleaned after the healthy update"
else
    pass_h "staging tree cleaned (exit-0-only effect)"
fi
if [ "$(cat "$INST_H/client/w100/payload.dat" 2>/dev/null)" = "cycle-payload" ]; then
    pass_h "user payload untouched through the whole cycle"
else
    fail_case "HEALTHY: user payload modified by the cycle"
fi
sleep 1
RUNNING_H=$(count_by_path "$INST_H/$APP_SLOT")
if [ "${RUNNING_H:-0}" -ge 1 ]; then
    pass_h "relaunched NEW app proven running"
else
    fail_case "HEALTHY: relaunched app is not running (census=0)"
fi
kill_by_path "$INST_H/$APP_SLOT"
sleep 2
RUNNING_H2=$(count_by_path "$INST_H/$APP_SLOT")
if [ "${RUNNING_H2:-1}" -eq 0 ]; then
    pass_h "survivor killed (no leaked GUI instance)"
else
    fail_case "HEALTHY: leaked a running instance (census=$RUNNING_H2)"
fi

echo "scenario HEALTHY asserted events: $SCENARIO_EVENTS"
if [ "$SCENARIO_EVENTS" -lt 15 ]; then
    fail_case "HEALTHY asserted only $SCENARIO_EVENTS events - vacuous-pass guard"
fi

# --------------------------------------------- scenario: BROKEN cycle

echo "--- scenario BROKEN: broken new exe -> automatic rollback, old app back"
SCENARIO_EVENTS=0
pass_b () { echo "PASS: B $1"; SCENARIO_EVENTS=$((SCENARIO_EVENTS + 1)); return 0; }

INST_B="$SCRATCH/instB"
assemble_install "$INST_B"
printf 'THIS-IS-NOT-A-WINDOWS-EXECUTABLE-0123456789' > "$SCRATCH/broken-new.exe"
build_fixture_zip "$SCRATCH/broken-new.exe"

clear_state
SINCE_B=$(log_lines)
launch_app "$INST_B"

if wait_for_segment_marker "rollback-complete" "$SINCE_B" 150; then
    pass_b "updater reached rollback-complete"
else
    fail_case "BROKEN: rollback-complete never appeared (last log: $(tail -5 "$UPDATE_LOG" 2>/dev/null | tr '\n' ' '))"
fi
sleep 3

for ev in update-offered update-accepted hash-verified staged updater-launched wait-exit relaunch-failed rollback-complete; do
    if segment_has "$ev" "$SINCE_B"; then
        pass_b "$ev logged"
    else
        fail_case "BROKEN: $ev missing from the log segment"
    fi
done

ACCEPTED_B=$(segment_count "update-accepted" "$SINCE_B")
if [ "$ACCEPTED_B" -eq 1 ]; then
    pass_b "update-accepted exactly once (no re-offer loop)"
else
    fail_case "BROKEN: update-accepted count=$ACCEPTED_B - the old app re-offered"
fi
SLOT_SHA_B=$(sha256sum "$INST_B/$APP_SLOT" 2>/dev/null | cut -d' ' -f1)
if [ "$SLOT_SHA_B" = "$OLD_SHA" ]; then
    pass_b "relaunch slot restored to the OLD exe"
else
    fail_case "BROKEN: relaunch slot not restored to the OLD exe"
fi
BACKUP_B=$(ls -d "$INST_B".bak-* 2>/dev/null | head -1)
if [ -n "$BACKUP_B" ]; then
    pass_b "backup folder kept after the rollback"
else
    fail_case "BROKEN: backup folder missing after the rollback"
fi
if ls "$STATE_DIR/"launch-*.ok >/dev/null 2>&1; then
    fail_case "BROKEN: a marker file exists despite the broken launch"
else
    pass_b "no marker written"
fi
sleep 1
RUNNING_B=$(count_by_path "$INST_B/$APP_SLOT")
if [ "${RUNNING_B:-0}" -ge 1 ]; then
    pass_b "OLD app proven running again after the rollback"
else
    fail_case "BROKEN: the old app is not running after the rollback (census=0)"
fi
kill_by_path "$INST_B/$APP_SLOT"
sleep 2
RUNNING_B2=$(count_by_path "$INST_B/$APP_SLOT")
if [ "${RUNNING_B2:-1}" -eq 0 ]; then
    pass_b "survivor killed (no leaked GUI instance)"
else
    fail_case "BROKEN: leaked a running instance (census=$RUNNING_B2)"
fi

echo "scenario BROKEN asserted events: $SCENARIO_EVENTS"
if [ "$SCENARIO_EVENTS" -lt 12 ]; then
    fail_case "BROKEN asserted only $SCENARIO_EVENTS events - vacuous-pass guard"
fi

# ------------------------------------------------- native cycle scenarios
#
# Gates (named skip marker, exit stays with the .NET verdict): lazbuild
# under WO_LAZARUS_ROOT, python (fixture zip + server), and an ELEVATED
# shell - the shipped UpdateInstallerLegacy.exe is requireAdministrator
# and the asInvoker updater must inherit REAL elevation from it (SC4:
# no new UAC prompt through the whole cycle).

NATIVE_GATES_OK=1
WO_LAZARUS_ROOT="${WO_LAZARUS_ROOT:-D:/tools/wson-lazarus}"
NATIVE_SKIP_WHY=""
if [ ! -f "$WO_LAZARUS_ROOT/lazbuild.exe" ]; then
    NATIVE_GATES_OK=0
    NATIVE_SKIP_WHY="lazbuild.exe not found under WO_LAZARUS_ROOT ($WO_LAZARUS_ROOT)"
fi
if ! net session >/dev/null 2>&1; then
    NATIVE_GATES_OK=0
    NATIVE_SKIP_WHY="shell not elevated - requireAdministrator UpdateInstallerLegacy.exe cannot launch (SC4 needs real elevation)"
fi

if [ "$NATIVE_GATES_OK" -eq 1 ]; then

echo "--- native fixtures: OLD + byte-distinct NEW UpdateInstallerLegacy builds"

# A leaked instance from an earlier crashed battery holds the repo-tree
# build output (6020 convention): kill by name before building.
powershell -NoProfile -Command \
    "Get-Process -Name 'UpdateInstallerLegacy' -ErrorAction SilentlyContinue | Stop-Process -Force" \
    >/dev/null 2>&1
sleep 1
rm -f src-native/installer/bin/installer-i386.exe

# OLD: the unmodified project, built in the repo tree (29-01 lane).
"$WO_LAZARUS_ROOT/lazbuild.exe" --build-mode=Release-i386 \
    "$(cygpath -w src-native/installer/installer.lpi)" \
    > "$SCRATCH/native-old-build.log" 2>&1
if [ $? -ne 0 ] || [ ! -f src-native/installer/bin/installer-i386.exe ]; then
    echo "FAIL: OLD native build failed"
    tail -5 "$SCRATCH/native-old-build.log"
    FAILED_CASES=$((FAILED_CASES + 1))
    NATIVE_GATES_OK=0
fi

if [ "$NATIVE_GATES_OK" -eq 1 ]; then
# NEW: the whole project copied aside, ONLY the copied .lpi's
# StringTable ProductVersion value replaced by the channel version - a
# byte-distinct second build whose EngOwnProductVersion reads
# 9.0.0+2099.01 (the marker then carries 9.0.0). The copy is byte-level
# and CRLF-preserving (MSYS sed strips CRLF; the replacement strings
# carry regex-active dots and pluses - python, not sed). The current
# ProductVersion VALUE is matched dynamically (release trains bump it -
# the 6.0.3+2026.11 train landed mid-phase), only the single
# StringTable occurrence is replaced, and the old value must differ
# from the target or the byte-distinctness assert would be vacuous.
rm -rf "$SCRATCH/native-src"
mkdir -p "$SCRATCH/native-src"
( cd src-native/installer && tar cf - --exclude='bin' --exclude='lib' . ) \
    | ( cd "$SCRATCH/native-src" && tar xf - )
if ! python - "$SCRATCH/native-src/installer.lpi" <<'PYEOF'
import re, sys
p = sys.argv[1]
d = open(p, 'rb').read()
matches = re.findall(rb'ProductVersion="([^"]*)"', d)
if len(matches) != 1:
    print('FAIL: expected exactly one ProductVersion literal, found %d' % len(matches))
    sys.exit(1)
old = b'ProductVersion="' + matches[0] + b'"'
new = b'ProductVersion="9.0.0+2099.01"'
if matches[0] == b'9.0.0+2099.01':
    print('FAIL: the shipped ProductVersion already equals the target - bump would be vacuous')
    sys.exit(1)
open(p, 'wb').write(d.replace(old, new))
print('lpi bumped %s -> 9.0.0+2099.01, CRLF preserved: %s'
      % (matches[0].decode(), b'\r\n' in d))
PYEOF
then
    echo "FAIL: NEW native lpi bump failed"
    FAILED_CASES=$((FAILED_CASES + 1))
    NATIVE_GATES_OK=0
fi
fi

if [ "$NATIVE_GATES_OK" -eq 1 ]; then
"$WO_LAZARUS_ROOT/lazbuild.exe" --build-mode=Release-i386 \
    "$(cygpath -w "$SCRATCH/native-src/installer.lpi")" \
    > "$SCRATCH/native-new-build.log" 2>&1
if [ $? -ne 0 ] || [ ! -f "$SCRATCH/native-src/bin/installer-i386.exe" ]; then
    echo "FAIL: NEW native build failed"
    tail -5 "$SCRATCH/native-new-build.log"
    FAILED_CASES=$((FAILED_CASES + 1))
    NATIVE_GATES_OK=0
fi
fi

if [ "$NATIVE_GATES_OK" -eq 1 ]; then
OLD_NATIVE_SHA=$(sha256sum src-native/installer/bin/installer-i386.exe | cut -d' ' -f1)
NEW_NATIVE_SHA=$(sha256sum "$SCRATCH/native-src/bin/installer-i386.exe" | cut -d' ' -f1)
if [ "$OLD_NATIVE_SHA" = "$NEW_NATIVE_SHA" ]; then
    echo "FAIL: OLD and NEW native builds are byte-identical - the swap asserts would be vacuous"
    FAILED_CASES=$((FAILED_CASES + 1))
    NATIVE_GATES_OK=0
fi
# Defender warm-up (fixture hygiene, documented): the fresh build's hash
# has no real-time-scan verdict yet, and the updater's relaunch is a
# SINGLE CreateProcess attempt (no retry - the swap copies retry, the
# launch does not). Two elevated runs lost exactly that race on
# brand-new hashes (relaunch-failed -> rollback cascade) while a direct
# elevated launch of the same file started fine. In production the
# published hash is days old before the updater must execute it; give
# the fresh hash its first scan explicitly so the scenario tests the
# swap/relaunch contract, not the scanner.
if [ "$NATIVE_GATES_OK" -eq 1 ]; then
    powershell -NoProfile -Command \
        "try { \$p = Start-Process -FilePath '$(ps_path "$SCRATCH/native-src/bin/installer-i386.exe")' -PassThru -ErrorAction Stop; Start-Sleep -Seconds 2; if (-not \$p.HasExited) { Stop-Process -Id \$p.Id -Force } } catch { }" \
        >/dev/null 2>&1
    sleep 1
fi
fi

if [ "$NATIVE_GATES_OK" -eq 1 ]; then

NATIVE_FAKE_PORT=$(( (RANDOM % 2000) + 52000 ))
NATIVE_SERVE_DIR="$SCRATCH/native-channel"
mkdir -p "$NATIVE_SERVE_DIR"

build_native_fixture_zip () {
    # $1 = executable (or non-executable) for the relaunch slot
    # wsusoffline/client/UpdateInstallerLegacy.exe; the three remaining
    # staging slots follow the .NET battery's placeholder convention
    # (the completeness assert needs existence, the manifest-driven swap
    # copies what the zip carries). Builds $NATIVE_SERVE_DIR/release.zip
    # plus the MEASURED-format hashes file from the actual zip bytes.
    local src="$1" zsize zsha
    rm -rf "$SCRATCH/native-zipstage"
    mkdir -p "$SCRATCH/native-zipstage/wsusoffline/client"
    cp "$src" "$SCRATCH/native-zipstage/wsusoffline/client/UpdateInstallerLegacy.exe"
    printf 'placeholder-generator' > "$SCRATCH/native-zipstage/wsusoffline/UpdateGeneratorModern.exe"
    printf 'placeholder-installer' > "$SCRATCH/native-zipstage/wsusoffline/client/UpdateInstallerModern.exe"
    printf 'placeholder-updater' > "$SCRATCH/native-zipstage/wsusoffline/WsusOfflineUpdater.exe"
    rm -f "$NATIVE_SERVE_DIR/release.zip"
    # Directory form (NOT explicit files): basename-only arcnames would
    # lose the wsusoffline/ prefix (28-03 arcname lesson).
    ( cd "$SCRATCH/native-zipstage" && python -m zipfile -c \
        "$(native_path "$NATIVE_SERVE_DIR/release.zip")" wsusoffline )
    if [ $? -ne 0 ] || [ ! -s "$NATIVE_SERVE_DIR/release.zip" ]; then
        echo "FAIL: native fixture zip creation failed"
        exit 1
    fi
    zsize=$(wc -c < "$NATIVE_SERVE_DIR/release.zip" | tr -d '[:space:]')
    zsha=$(sha256sum "$NATIVE_SERVE_DIR/release.zip" | cut -d' ' -f1)
    printf '%b' "%%%% v1.0\r\n%%%%\r\n$zsize,md5x,sha1x,$zsha,wsusofflineCE-9.9.9.zip\r\n" \
        > "$NATIVE_SERVE_DIR/release_hashes.txt"
}

assemble_native_install () {
    # $1 = native install root; OLD native build in the client slot,
    # the real published updater at the root, kill-switch NOT enabled.
    local inst="$1"
    rm -rf "$inst"
    mkdir -p "$inst/client"
    cp src-native/installer/bin/installer-i386.exe "$inst/client/UpdateInstallerLegacy.exe"
    cp "$SCRATCH/pub-updater/WsusOfflineUpdater.exe" "$inst/WsusOfflineUpdater.exe"
    printf '%b' '[Control]\r\nSkipSelfUpdate=Disabled\r\n' > "$inst/client/UpdateInstaller.ini"
}

launch_native_app () {
    # $1 = native install root. All test hooks + TEMP isolation ride the
    # env; the updater and the relaunched app inherit everything.
    WSON_UPDATE_CHANNEL_URL="http://127.0.0.1:$NATIVE_FAKE_PORT/SelfUpdateVersion-recent.txt" \
    WSON_UPDATE_LINKS_URL="http://127.0.0.1:$NATIVE_FAKE_PORT/StaticDownloadLink-recent.txt" \
    WSON_UPDATE_LOCAL_VERSION="1.0.0" \
    WSON_UPDATE_AUTO_ACCEPT="1" \
    WSON_UPDATE_ALLOW_HTTP="1" \
    TEMP="$(native_path "$UPDATER_TEMP")" TMP="$(native_path "$UPDATER_TEMP")" \
    "$1/client/UpdateInstallerLegacy.exe" > /dev/null 2>&1 &
}

( cd "$NATIVE_SERVE_DIR" && printf '9.0.0+2099.01,release\r\n' > SelfUpdateVersion-recent.txt )
( cd "$NATIVE_SERVE_DIR" && printf 'http://127.0.0.1:%s/release.zip\r\nhttp://127.0.0.1:%s/release_hashes.txt\r\n' \
    "$NATIVE_FAKE_PORT" "$NATIVE_FAKE_PORT" > StaticDownloadLink-recent.txt )

( cd "$NATIVE_SERVE_DIR" && python -m http.server "$NATIVE_FAKE_PORT" --bind 127.0.0.1 \
    > "$SCRATCH/native-httpd.log" 2>&1 & )

SERVER_READY=1
for (( i = 0; i < 20; i++ )); do
    if python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:$NATIVE_FAKE_PORT/SelfUpdateVersion-recent.txt', timeout=2).status == 200 else 1)" 2>/dev/null; then
        SERVER_READY=0
        break
    fi
    sleep 0.5
done
if [ "$SERVER_READY" -ne 0 ]; then
    echo "FAIL: native fake channel server never became ready on port $NATIVE_FAKE_PORT"
    FAILED_CASES=$((FAILED_CASES + 1))
    NATIVE_GATES_OK=0
fi
fi

# --------------------------------------- scenario: NATIVE-HEALTHY cycle

echo "--- scenario NATIVE-HEALTHY: native accept -> updater -> swap -> healthy relaunch"
SCENARIO_EVENTS=0
NH_FAIL_BASE=$FAILED_CASES
pass_nh () { echo "PASS: NH $1"; SCENARIO_EVENTS=$((SCENARIO_EVENTS + 1)); return 0; }

NINST="$SCRATCH/native-install"
assemble_native_install "$NINST"
build_native_fixture_zip "$SCRATCH/native-src/bin/installer-i386.exe"

# Stage-dir snapshot BEFORE the cycle: the .NET BROKEN scenario (which ran
# before this one) legitimately leaves its stage dir behind - the rollback
# path cleans nothing - so the cleanup assert below must be scoped to NEW
# stage dirs, not to the unscoped stage-* glob.
STAGE_BEFORE_NH=$(ls -d "$UPDATER_TEMP/WsusOfflineNext-Update/"stage-* 2>/dev/null | sort)

clear_state
SINCE_NH=$(log_lines)
launch_native_app "$NINST"

if wait_for_segment_marker "updater-launched" "$SINCE_NH" 120; then
    pass_nh "updater-launched logged (accept path reached the handoff)"
else
    fail_case "NATIVE-HEALTHY: updater-launched never appeared (last log: $(tail -5 "$UPDATE_LOG" 2>/dev/null | tr '\n' ' '))"
fi

# The app exits by itself (auto-accept closes the form): census death
# poll at 0.25s - the updater's wait-exit + swap window is seconds wide.
NATIVE_DEATH_SEEN=0
for (( i = 0; i < 80; i++ )); do
    if [ "$(count_by_path "$NINST/client/UpdateInstallerLegacy.exe")" = "0" ]; then
        NATIVE_DEATH_SEEN=1
        break
    fi
    sleep 0.25
done
if [ "$NATIVE_DEATH_SEEN" -eq 1 ]; then
    pass_nh "app exited by itself after the accept (census 0)"
else
    fail_case "NATIVE-HEALTHY: app never exited (census=$(count_by_path "$NINST/client/UpdateInstallerLegacy.exe")) - auto-accept close failed"
fi

if wait_for_segment_marker "marker-received" "$SINCE_NH" 150; then
    pass_nh "updater reached marker-received"
else
    fail_case "NATIVE-HEALTHY: marker-received never appeared (last log: $(tail -5 "$UPDATE_LOG" 2>/dev/null | tr '\n' ' '))"
fi
sleep 3   # let the updater finish staging cleanup and backup pruning

for ev in update-offered update-accepted hash-verified staged updater-launched wait-exit relaunch-start marker-written; do
    if segment_has "$ev" "$SINCE_NH"; then
        pass_nh "$ev logged"
    else
        fail_case "NATIVE-HEALTHY: $ev missing from the log segment"
    fi
done

ACCEPTED_NH=$(segment_count "update-accepted" "$SINCE_NH")
if [ "$ACCEPTED_NH" -eq 1 ]; then
    pass_nh "update-accepted exactly once (the relaunched instance cache-skipped)"
else
    fail_case "NATIVE-HEALTHY: update-accepted count=$ACCEPTED_NH - the relaunched app re-offered"
fi
if segment_has "check-skip-cache" "$SINCE_NH"; then
    pass_nh "relaunched NEW app logged check-skip-cache (daily cache loop guard)"
else
    fail_case "NATIVE-HEALTHY: check-skip-cache missing - the relaunched app re-checked the network"
fi
if segment_has "rollback-complete" "$SINCE_NH"; then
    fail_case "NATIVE-HEALTHY: rollback events present in a healthy native cycle"
else
    pass_nh "no rollback events (kept-healthy by construction)"
fi

SLOT_SHA_NH=$(sha256sum "$NINST/client/UpdateInstallerLegacy.exe" 2>/dev/null | cut -d' ' -f1)
if [ "$SLOT_SHA_NH" = "$NEW_NATIVE_SHA" ]; then
    pass_nh "client slot now carries the NEW native exe (sha-distinct from the old)"
else
    fail_case "NATIVE-HEALTHY: client slot does not carry the NEW native exe"
fi
BACKUP_NH=$(ls -d "$NINST".bak-* 2>/dev/null | head -1)
if [ -n "$BACKUP_NH" ] && [ "$(sha256sum "$BACKUP_NH/client/UpdateInstallerLegacy.exe" 2>/dev/null | cut -d' ' -f1)" = "$OLD_NATIVE_SHA" ]; then
    pass_nh "backup folder exists and carries the OLD native exe"
else
    fail_case "NATIVE-HEALTHY: backup missing or not carrying the OLD native exe (backup=${BACKUP_NH:-<none>})"
fi
MARKER_FILE_NH=$(ls "$STATE_DIR/"launch-*.ok 2>/dev/null | head -1)
if [ -n "$MARKER_FILE_NH" ]; then
    pass_nh "healthy-launch marker file exists"
else
    fail_case "NATIVE-HEALTHY: marker file missing"
fi
MARKER_VER_NH=$(head -1 "$MARKER_FILE_NH" 2>/dev/null | tr -d '\r\n ')
if [ "$MARKER_VER_NH" = "9.0.0" ]; then
    pass_nh "marker written by the NEW native version (first line 9.0.0)"
else
    fail_case "NATIVE-HEALTHY: marker first line is '${MARKER_VER_NH:-<empty>}', expected 9.0.0"
fi
STAGE_AFTER_NH=$(ls -d "$UPDATER_TEMP/WsusOfflineNext-Update/"stage-* 2>/dev/null | sort)
if [ "$STAGE_AFTER_NH" = "$STAGE_BEFORE_NH" ]; then
    pass_nh "staging tree cleaned (exit-0-only effect; no new stage dir survived)"
else
    fail_case "NATIVE-HEALTHY: a NEW stage dir survived the healthy update ($(printf '%s\n' "$STAGE_AFTER_NH" | grep -vxF "$STAGE_BEFORE_NH" | head -2 | tr '\n' ' '))"
fi
sleep 1
RUNNING_NH=$(count_by_path "$NINST/client/UpdateInstallerLegacy.exe")
if [ "${RUNNING_NH:-0}" -ge 1 ]; then
    pass_nh "relaunched NEW native app proven running"
else
    fail_case "NATIVE-HEALTHY: relaunched app is not running (census=0)"
fi
kill_by_path "$NINST/client/UpdateInstallerLegacy.exe"
sleep 2
RUNNING_NH2=$(count_by_path "$NINST/client/UpdateInstallerLegacy.exe")
if [ "${RUNNING_NH2:-1}" -eq 0 ]; then
    pass_nh "survivor killed (no leaked native instance)"
else
    fail_case "NATIVE-HEALTHY: leaked a running native instance (census=$RUNNING_NH2)"
fi

echo "scenario NATIVE-HEALTHY asserted events: $SCENARIO_EVENTS"
if [ "$SCENARIO_EVENTS" -lt 15 ]; then
    fail_case "NATIVE-HEALTHY asserted only $SCENARIO_EVENTS events - vacuous-pass guard"
fi
if [ "$FAILED_CASES" -eq "$NH_FAIL_BASE" ]; then
    echo "PASS: NATIVE-HEALTHY full cycle kept"
else
    echo "FAIL: NATIVE-HEALTHY full cycle"
fi

# ---------------------------------------- scenario: NATIVE-BROKEN cycle

echo "--- scenario NATIVE-BROKEN: broken new exe -> automatic rollback, old app back"
SCENARIO_EVENTS=0
NB_FAIL_BASE=$FAILED_CASES
pass_nb () { echo "PASS: NB $1"; SCENARIO_EVENTS=$((SCENARIO_EVENTS + 1)); return 0; }

NINST_B="$SCRATCH/native-install-b"
assemble_native_install "$NINST_B"
printf 'THIS-IS-NOT-A-WINDOWS-EXECUTABLE-0123456789' > "$SCRATCH/native-broken.exe"
build_native_fixture_zip "$SCRATCH/native-broken.exe"

clear_state
SINCE_NB=$(log_lines)
launch_native_app "$NINST_B"

if wait_for_segment_marker "rollback-complete" "$SINCE_NB" 150; then
    pass_nb "updater reached rollback-complete"
else
    fail_case "NATIVE-BROKEN: rollback-complete never appeared (last log: $(tail -5 "$UPDATE_LOG" 2>/dev/null | tr '\n' ' '))"
fi
sleep 3

for ev in update-offered update-accepted hash-verified staged updater-launched wait-exit relaunch-failed rollback-complete; do
    if segment_has "$ev" "$SINCE_NB"; then
        pass_nb "$ev logged"
    else
        fail_case "NATIVE-BROKEN: $ev missing from the log segment"
    fi
done

ACCEPTED_NB=$(segment_count "update-accepted" "$SINCE_NB")
if [ "$ACCEPTED_NB" -eq 1 ]; then
    pass_nb "update-accepted exactly once (no re-offer loop)"
else
    fail_case "NATIVE-BROKEN: update-accepted count=$ACCEPTED_NB - the old app re-offered"
fi
SLOT_SHA_NB=$(sha256sum "$NINST_B/client/UpdateInstallerLegacy.exe" 2>/dev/null | cut -d' ' -f1)
if [ "$SLOT_SHA_NB" = "$OLD_NATIVE_SHA" ]; then
    pass_nb "client slot restored to the OLD native exe"
else
    fail_case "NATIVE-BROKEN: client slot not restored to the OLD native exe"
fi
BACKUP_NB=$(ls -d "$NINST_B".bak-* 2>/dev/null | head -1)
if [ -n "$BACKUP_NB" ]; then
    pass_nb "backup folder kept after the rollback"
else
    fail_case "NATIVE-BROKEN: backup folder missing after the rollback"
fi
if ls "$STATE_DIR/"launch-*.ok >/dev/null 2>&1; then
    fail_case "NATIVE-BROKEN: a marker file exists despite the broken launch"
else
    pass_nb "no marker written"
fi
sleep 1
RUNNING_NB=$(count_by_path "$NINST_B/client/UpdateInstallerLegacy.exe")
if [ "${RUNNING_NB:-0}" -ge 1 ]; then
    pass_nb "OLD native app proven running again after the rollback"
else
    fail_case "NATIVE-BROKEN: the old app is not running after the rollback (census=0)"
fi
kill_by_path "$NINST_B/client/UpdateInstallerLegacy.exe"
sleep 2
RUNNING_NB2=$(count_by_path "$NINST_B/client/UpdateInstallerLegacy.exe")
if [ "${RUNNING_NB2:-1}" -eq 0 ]; then
    pass_nb "survivor killed (no leaked native instance)"
else
    fail_case "NATIVE-BROKEN: leaked a running native instance (census=$RUNNING_NB2)"
fi

echo "scenario NATIVE-BROKEN asserted events: $SCENARIO_EVENTS"
if [ "$SCENARIO_EVENTS" -lt 12 ]; then
    fail_case "NATIVE-BROKEN asserted only $SCENARIO_EVENTS events - vacuous-pass guard"
fi
if [ "$FAILED_CASES" -eq "$NB_FAIL_BASE" ]; then
    echo "PASS: NATIVE-BROKEN rollback restored old app"
else
    echo "FAIL: NATIVE-BROKEN rollback cycle"
fi

else
    echo "SELFUPDATE-CYCLE-NATIVE-SKIP: $NATIVE_SKIP_WHY"
fi

# ------------------------------------------------------------- verdict
if [ "$FAILED_CASES" -ne 0 ]; then
    echo "SELFUPDATE-CYCLE: RED ($FAILED_CASES failing case(s))"
    exit 1
fi
echo "SELFUPDATE-CYCLE: GREEN"
exit 0
