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
    fi
    if [ -n "${FAKE_PORT:-}" ]; then
        local listener
        listener=$(netstat -ano 2>/dev/null | grep ":${FAKE_PORT}" | grep -i LISTENING \
            | awk '{print $NF}' | head -1)
        if [ -n "$listener" ]; then
            powershell -NoProfile -Command "Stop-Process -Id $listener -Force" \
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

# ------------------------------------------------------------- verdict

if [ "$FAILED_CASES" -ne 0 ]; then
    echo "SELFUPDATE-CYCLE: RED ($FAILED_CASES failing case(s))"
    exit 1
fi
echo "SELFUPDATE-CYCLE: GREEN"
exit 0
