#!/usr/bin/env bash
# Battery for the self-update CHECK slice (Phase 28 plan 01) - run from
# repo root.
#
# Section (a) drives the REAL shared engine (src-modern/common/selfupdate)
# through the ci/tests/selfupdate-probe console project: channel version
# parsing (newer / equal / older / equal-core-with-metadata / CRLF+spaces /
# empty / garbage / multi-comma), links parsing (missing second line /
# http URL / wrong suffixes), daily cache (today / yesterday / garbage /
# empty) and the kill-switch INI reader (mixed-case Enabled + CRLF +
# comment lines / key absent / other section). The section prints its
# fixture count; a run enumerating zero fixtures is a FAIL (vacuous-pass
# guard).
#
# Section (b) is the LIVE APP PROBE: the real generator exe is published
# to a scratch dir, a fake channel is served from 127.0.0.1 by python,
# and four runs assert the live log sequence - offer + auto-decline with
# the app left alive, same-day cache skip, kill-switch skip before any
# network event, and offline silent failure with NO cache write.
#
# Section (c) is the NATIVE APP PROBE: the real lazbuild-built
# UpdateInstallerLegacy.exe (i386, the shipped lane) runs the same fake
# channel matrix as section (b) - offer + auto-decline with the app left
# alive and the cache written (N1), same-day cache skip (N2), kill-switch
# skip before any network event (N3), and offline check-error with NO
# cache write (N4). Self-sufficient: it builds its own app copy and
# serves its own fake channel on its own port, never depending on
# section (b)'s server or WebView2 gate. Named skip markers (each skips
# ONLY section (c), exit 0 on skip, following the repo skip-guard
# convention):
#   - WO_LAZARUS_ROOT unset -> SELFUPDATE-CHECK-NATIVE-SKIP-NO-LAZARUS
#   - python absent         -> SELFUPDATE-CHECK-NATIVE-SKIP-PYTHON
#   - 'net session' nonzero -> SELFUPDATE-CHECK-NATIVE-SKIP-NOT-ELEVATED
#     (the shipped manifest is requireAdministrator; a non-elevated shell
#     would need a UAC click a headless battery cannot make)
#
# Section (d) is the MODERN INSTALLER PROBE (Phase 30): the real
# dotnet-published installer host (requireAdministrator manifest) runs
# the same check matrix as section (b) - offer + auto-decline with the
# app left alive and the cache written (D1), same-day cache skip (D2),
# kill-switch skip before any network event (D3), offline check-error
# with NO cache write (D4) and corrupt-channel check-error with NO cache
# write (D5). Self-sufficient: own app copy (published single-file into
# a scratch install with the exe at client\UpdateInstallerModern.exe and
# the INI beside it, wwwroot copied best-effort), own fake server
# (port 52000+), own corrupt server (54000+). Named skip markers (each
# skips ONLY section (d), exit 0 on skip):
#   - WebView2 runtime absent -> SELFUPDATE-CHECK-INSTALLER-SKIP-WEBVIEW2
#   - python absent           -> SELFUPDATE-CHECK-INSTALLER-SKIP-PYTHON
#   - 'net session' nonzero  -> SELFUPDATE-CHECK-INSTALLER-SKIP-NOT-ELEVATED
#
# Phase 30 behavior matrix (ROADMAP criterion 1): every check-slice cell
# is RECORDED per case and per app as a "MATRIX: app=<app> case=<case>
# PASS" line and counted - 15 check cells across the generator
# (section b), the native installer (section c) and the modern installer
# (section d): offered, declined, kill-switch, offline-silent,
# corrupt-channel. A section that ran but recorded zero MATRIX cells
# fails the vacuous-pass guard, and the verdict block prints
# "MATRIX SUMMARY: N check cases recorded".
#
# Corrupt-channel cells (run 5 / N5 / D5): a channel file carrying a
# non-parseable line must log check-error, leave the app alive and write
# NO daily cache (the engine writes the cache only after a completed
# channel read+parse). Can-fail contract (CORRUPT-CELL-CAN-FAIL):
# rewriting either corrupt-channel fixture with a valid newer channel
# flips run 5 / N5 / D5 from check-error to an offered offer - the
# check-error wait times out and the battery goes red.
#
# Teardown: every fake-channel server the battery started (section b
# main + corrupt, native main + corrupt, installer main + corrupt) is
# tracked in BATTERY_PORTS and stopped by netstat LISTENING pid lookup
# on exit; every probe app is killed with a death assertion; the scratch
# tree is removed. No loopback-external listener survives the run.
#
# Environment gates (named markers, exit 0 on skip, following the repo
# skip-guard convention):
#   - not Windows, or dotnet absent -> SELFUPDATE-CHECK-SKIP-ENV, the
#     whole battery skips (the ubuntu CI fixture-tests runner has no
#     dotnet and cannot run a WinForms exe anyway)
#   - WebView2 runtime absent       -> SELFUPDATE-CHECK-PROBE-SKIP-WEBVIEW2,
#     section (b) skips, section (a) stays binding
#   - python absent                 -> SELFUPDATE-CHECK-PROBE-SKIP-PYTHON,
#     section (b) skips, section (a) stays binding
#
# The battery can fail: mutating one section (a) fixture - the "newer
# core" row local version 6.0.2 changed to 9.0.0 so the channel is no
# longer newer - flips that row from OFFER to NO-OFFER and the battery
# red. This was demonstrated once on a sandbox copy of the battery at
# commit time (see the 28-01 SUMMARY); the proof lives here as the
# documented can-fail contract.
set -u

PROBE_DIR="ci/tests/selfupdate-probe"
GEN_CSproj="src-modern/generator/host/UpdateGenerator.csproj"
APP_NAME="UpdateGenerator"

FAILED_CASES=0
FIXTURE_COUNT=0
MATRIX_TOTAL=0
MATRIX_B=0
MATRIX_C=0
MATRIX_D=0
B_RAN=0
C_RAN=0
D_RAN=0

fail_case () {
    echo "FAIL: $1"
    FAILED_CASES=$((FAILED_CASES + 1))
    return 0
}

matrix_record () {
    # Per-case record line for the Phase 30 behavior matrix (15 check
    # cells + per-section counters; a section that ran but recorded zero
    # cells fails its vacuous-pass guard).
    echo "MATRIX: app=$1 case=$2 PASS"
    MATRIX_TOTAL=$((MATRIX_TOTAL + 1))
    case "$1" in
        generator)        MATRIX_B=$((MATRIX_B + 1)) ;;
        native)           MATRIX_C=$((MATRIX_C + 1)) ;;
        installer-modern) MATRIX_D=$((MATRIX_D + 1)) ;;
    esac
}

# ---------------------------------------------------------------- helpers

native_path () {
    # Hand a path to a native Windows tool (dotnet -o): use the mixed
    # Windows form so both shell and native sides resolve it the same.
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

SCRATCH="$(pwd)/.selfupdate-battery-scratch.$$"
UPDATE_LOG="$(localappdata_posix)/WsusOfflineNext/selfupdate/update.log"
CACHE_FILE="$(localappdata_posix)/WsusOfflineNext/selfupdate/last-check.txt"
SERVER_PID=""
# Every fake-channel port the battery starts is tracked here; the EXIT
# trap stops each by netstat LISTENING pid lookup (T-30-01: no
# loopback-external listener survives the run).
BATTERY_PORTS=""

stop_server_on_port () {
    # $1 = port; netstat LISTENING pid lookup + Stop-Process (the cycle
    # battery's teardown pattern).
    local port="$1" listener
    [ -n "$port" ] || return 0
    listener=$(netstat -ano 2>/dev/null | grep ":${port}" | grep -i LISTENING \
        | awk '{print $NF}' | head -1)
    if [ -n "$listener" ]; then
        powershell -NoProfile -Command "Stop-Process -Id $listener -Force" \
            >/dev/null 2>&1
    fi
}

cleanup () {
    # Guarded cleanup: kill every probe app with an explicit death
    # assertion (a leaked GUI instance locks the next build), then the
    # fake channel servers by their listening ports, then remove the
    # scratch. Probe targets: the section (b) generator, the section (c)
    # native installer and the section (d) modern installer.
    if command -v powershell >/dev/null 2>&1; then
        powershell -NoProfile -Command \
            "Get-Process -Name '$APP_NAME' -ErrorAction SilentlyContinue | Stop-Process -Force" \
            >/dev/null 2>&1
        powershell -NoProfile -Command \
            "Get-Process -Name 'UpdateInstallerLegacy' -ErrorAction SilentlyContinue | Stop-Process -Force" \
            >/dev/null 2>&1
        powershell -NoProfile -Command \
            "Get-Process -Name 'UpdateInstallerModern' -ErrorAction SilentlyContinue | Stop-Process -Force" \
            >/dev/null 2>&1
    fi
    local p
    for p in $BATTERY_PORTS; do
        stop_server_on_port "$p"
    done
    rm -rf "$SCRATCH"
}
trap cleanup EXIT

clear_probe_state () {
    rm -rf "$(localappdata_posix)/WsusOfflineNext/selfupdate"
}

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

wait_for_segment_marker () {
    local marker="$1" since="$2" rounds="${3:-40}"
    local i
    for (( i = 0; i < rounds; i++ )); do
        segment_has "$marker" "$since" && return 0
        sleep 0.5
    done
    return 1
}

app_alive () {
    # $1 = process image name; default = the section-b generator name.
    # Section c MUST pass NATIVE_APP_NAME - the generator is not running
    # there, and the default name silently matched an UNRELATED live
    # generator process in the 29-01 elevated run (false pass) and
    # nothing at all in the 29-02 runs (false app-died failures).
    tasklist 2>/dev/null | grep -qi "${1:-$APP_NAME}"
}

kill_app_and_assert_death () {
    powershell -NoProfile -Command \
        "Get-Process -Name '$APP_NAME' -ErrorAction SilentlyContinue | Stop-Process -Force" \
        >/dev/null 2>&1
    local i
    for (( i = 0; i < 10; i++ )); do
        if powershell -NoProfile -Command \
            "if (Get-Process -Name '$APP_NAME' -ErrorAction SilentlyContinue) { exit 1 }" \
            >/dev/null 2>&1
        then
            echo "info: $APP_NAME stopped"
            return 0
        fi
        sleep 1
    done
    echo "info: $APP_NAME STILL ALIVE after kill attempt"
    return 1
}

# ------------------------------------------------- environment gating

IS_WINDOWS=0
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*|Windows*) IS_WINDOWS=1 ;;
esac

if [ "$IS_WINDOWS" -ne 1 ] || ! command -v dotnet >/dev/null 2>&1; then
    echo "SELFUPDATE-CHECK-SKIP-ENV: requires Windows + dotnet (section a probe and section b live app)"
    echo "SKIP: self-update check battery skipped on this environment"
    exit 0
fi

# ---------------------------------------------------------- scratch

mkdir -p "$SCRATCH" || { echo "FAIL: cannot create scratch"; exit 1; }
FIX_DIR="$SCRATCH/fixtures"
mkdir -p "$FIX_DIR"

# ================================================== section (a): pure decisions

echo "--- section a: pure decisions via the probe project"

# Single-file publish (the same shape as every shipped wson binary): this
# machine enforces Smart App Control, which blocks the unsigned dll-shaped
# Debug build at assembly load (0x800711C7) - the single-file bundle embeds
# the managed dll so no on-disk dll is left for the policy to block.
dotnet publish "$PROBE_DIR/SelfUpdateProbe.csproj" -c Release -r win-x64 \
    -p:PublishSingleFile=true -p:SelfContained=false \
    -o "$(native_path "$SCRATCH/probe")" > "$SCRATCH/probe-build.log" 2>&1
if [ $? -ne 0 ]; then
    echo "FAIL: probe project did not publish (see scratch probe-build.log)"
    cat "$SCRATCH/probe-build.log"
    exit 1
fi
PROBE_EXE="$SCRATCH/probe/SelfUpdateProbe.exe"
if [ ! -f "$PROBE_EXE" ]; then
    echo "FAIL: probe exe not found at $PROBE_EXE after build"
    exit 1
fi
run_probe () {
    "$PROBE_EXE" "$@"
}

GOOD_LINKS="$FIX_DIR/links-good.txt"
printf 'https://example.com/WsusOfflineNext-9.0.0.zip\r\nhttps://example.com/WsusOfflineNext-9.0.0_hashes.txt\r\n' > "$GOOD_LINKS"

check_decide () {
    # $1 case name, $2 channel content (printf format), $3 links file,
    # $4 local version, $5 expected verdict prefix
    FIXTURE_COUNT=$((FIXTURE_COUNT + 1))
    local chan="$FIX_DIR/channel-$FIXTURE_COUNT.txt"
    printf '%b' "$2" > "$chan"
    local verdict
    verdict=$(run_probe decide "$chan" "$3" "$4" 2>/dev/null | tr -d '\r')
    case "$verdict" in
        "$5"*) echo "PASS: decide $1 -> $verdict" ;;
        *) fail_case "decide $1: expected $5*, got '${verdict:-<none>}'" ;;
    esac
}

check_cache () {
    # $1 case name, $2 cache kind, $3 expected verdict
    FIXTURE_COUNT=$((FIXTURE_COUNT + 1))
    local verdict
    verdict=$(run_probe cache "$2" "$FIX_DIR/cache-$FIXTURE_COUNT.txt" 2>/dev/null | tr -d '\r')
    if [ "$verdict" = "$3" ]; then
        echo "PASS: cache $1 -> $verdict"
    else
        fail_case "cache $1: expected $3, got '${verdict:-<none>}'"
    fi
}

check_ini () {
    # $1 case name, $2 ini content (printf format), $3 expected verdict
    FIXTURE_COUNT=$((FIXTURE_COUNT + 1))
    local ini="$FIX_DIR/ini-$FIXTURE_COUNT.ini"
    printf '%b' "$2" > "$ini"
    local verdict
    verdict=$(run_probe ini "$ini" 2>/dev/null | tr -d '\r')
    if [ "$verdict" = "$3" ]; then
        echo "PASS: ini $1 -> $verdict"
    else
        fail_case "ini $1: expected $3, got '${verdict:-<none>}'"
    fi
}

# Channel version decisions (links always valid unless under test).
check_decide "newer core offers"            '9.0.0+2099.01,release\r\n' "$GOOD_LINKS" "6.0.2" "OFFER"
check_decide "equal version no offer"       '6.0.2+2026.11,release\r\n' "$GOOD_LINKS" "6.0.2" "NO-OFFER"
check_decide "older channel no offer"       '5.9.9,release\r\n'         "$GOOD_LINKS" "6.0.2" "NO-OFFER"
check_decide "metadata-equal no offer (strictness pin)" '6.0.2+9999.99,release\r\n' "$GOOD_LINKS" "6.0.2" "NO-OFFER"
check_decide "CRLF and trailing spaces parse" '  9.0.1+2099.01,release  \r\n' "$GOOD_LINKS" "6.0.2" "OFFER"
check_decide "empty channel no offer"       ''                          "$GOOD_LINKS" "6.0.2" "NO-OFFER"
check_decide "garbage channel no offer"     'not-a-channel-file\r\n'    "$GOOD_LINKS" "6.0.2" "NO-OFFER"
check_decide "multi-comma channel no offer" '1.0.0,a,b\r\n'             "$GOOD_LINKS" "6.0.2" "NO-OFFER"

# Links decisions (channel always valid and newer - fixture channel-1.txt
# written by the first decide row above).
printf 'https://example.com/WsusOfflineNext-9.0.0.zip\r\n' > "$FIX_DIR/links-missing.txt"
FIXTURE_COUNT=$((FIXTURE_COUNT + 1))
v=$(run_probe decide "$FIX_DIR/channel-1.txt" "$FIX_DIR/links-missing.txt" "6.0.2" 2>/dev/null | tr -d '\r')
[ "$v" = "NO-OFFER" ] && echo "PASS: decide links-missing-second-line -> $v" \
    || fail_case "decide links-missing-second-line: expected NO-OFFER, got '${v:-<none>}'"

printf 'http://example.com/WsusOfflineNext-9.0.0.zip\r\nhttps://example.com/WsusOfflineNext-9.0.0_hashes.txt\r\n' > "$FIX_DIR/links-http.txt"
FIXTURE_COUNT=$((FIXTURE_COUNT + 1))
v=$(run_probe decide "$FIX_DIR/channel-1.txt" "$FIX_DIR/links-http.txt" "6.0.2" 2>/dev/null | tr -d '\r')
[ "$v" = "NO-OFFER" ] && echo "PASS: decide links-http-not-https -> $v" \
    || fail_case "decide links-http-not-https: expected NO-OFFER, got '${v:-<none>}'"

printf 'https://example.com/WsusOfflineNext-9.0.0.rar\r\nhttps://example.com/WsusOfflineNext-9.0.0_files.txt\r\n' > "$FIX_DIR/links-suffix.txt"
FIXTURE_COUNT=$((FIXTURE_COUNT + 1))
v=$(run_probe decide "$FIX_DIR/channel-1.txt" "$FIX_DIR/links-suffix.txt" "6.0.2" 2>/dev/null | tr -d '\r')
[ "$v" = "NO-OFFER" ] && echo "PASS: decide links-wrong-suffixes -> $v" \
    || fail_case "decide links-wrong-suffixes: expected NO-OFFER, got '${v:-<none>}'"

# Daily cache.
check_cache "today short-circuits"    "today"     "CHECK-TODAY"
check_cache "yesterday re-checks"     "yesterday" "CHECK-NEEDED"
check_cache "garbage re-checks"       "garbage"   "CHECK-NEEDED"
check_cache "empty re-checks"         "empty"     "CHECK-NEEDED"

# Kill-switch INI.
check_ini "control skip enabled mixed case" '[Misc]\r\nw96=Enabled\r\n[Control]\r\n; a comment\r\n# another comment\r\nSkipSelfUpdate=eNaBlEd\r\nverify=Enabled\r\n' "DISABLED"
check_ini "key absent stays enabled"   '[Control]\r\nverify=Enabled\r\nautoreboot=Disabled\r\n' "ENABLED"
check_ini "other section stays enabled" '[Other]\r\nSkipSelfUpdate=Enabled\r\n' "ENABLED"

echo "section a fixtures: $FIXTURE_COUNT"
if [ "$FIXTURE_COUNT" -eq 0 ]; then
    fail_case "section a enumerated zero fixtures (vacuous pass guard)"
fi

# ============================================ section (b): live app probe

echo "--- section b: live app probe"

WEBVIEW2_PRESENT="no"
if command -v powershell >/dev/null 2>&1; then
    WEBVIEW2_PRESENT=$(powershell -NoProfile -Command \
        "if (Get-ItemProperty 'HKLM:\\SOFTWARE\\WOW6432Node\\Microsoft\\EdgeUpdate\\Clients\\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}' -ErrorAction SilentlyContinue) { 'yes' } elseif (Get-ItemProperty 'HKCU:\\Software\\Microsoft\\EdgeUpdate\\Clients\\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}' -ErrorAction SilentlyContinue) { 'yes' } else { 'no' }" \
        2>/dev/null | tr -d '\r')
fi

if [ "$WEBVIEW2_PRESENT" != "yes" ]; then
    echo "SELFUPDATE-CHECK-PROBE-SKIP-WEBVIEW2: no WebView2 runtime, the published app would take the Evergreen fallback"
elif ! command -v python >/dev/null 2>&1; then
    echo "SELFUPDATE-CHECK-PROBE-SKIP-PYTHON: python is needed to serve the fake channel"
else
    B_RAN=1
    APP_DIR="$SCRATCH/app"
    SERVE_DIR="$SCRATCH/channel"
    mkdir -p "$SERVE_DIR"

    # Fake channel: a much newer core version so the strict-newer decision
    # must fire regardless of the exe's own version metadata.
    printf '9.0.0+2099.01,release\r\n' > "$SERVE_DIR/SelfUpdateVersion-recent.txt"
    printf 'https://example.com/WsusOfflineNext-9.0.0.zip\r\nhttps://example.com/WsusOfflineNext-9.0.0_hashes.txt\r\n' \
        > "$SERVE_DIR/StaticDownloadLink-recent.txt"

    # Scratch install root: exe at the root, fixture client INI below it.
    dotnet publish "$GEN_CSproj" -c Release -r win-x64 \
        -o "$(native_path "$APP_DIR")" > "$SCRATCH/publish.log" 2>&1
    if [ $? -ne 0 ] || [ ! -f "$APP_DIR/$APP_NAME.exe" ]; then
        fail_case "generator publish failed or exe missing (see scratch publish.log)"
    else
        APP_EXE="$APP_DIR/$APP_NAME.exe"
        INI_PATH="$APP_DIR/client/UpdateInstaller.ini"
        mkdir -p "$APP_DIR/client"
        printf '[Control]\r\nverify=Enabled\r\nautoreboot=Disabled\r\n' > "$INI_PATH"

        FAKE_PORT=$(( (RANDOM % 2000) + 48000 ))
        BATTERY_PORTS="$BATTERY_PORTS $FAKE_PORT"
        ( cd "$SERVE_DIR" && python -m http.server "$FAKE_PORT" --bind 127.0.0.1 \
            > "$SCRATCH/httpd.log" 2>&1 & )

        # Server readiness probe (instrument, not hope).
        SERVER_READY=1
        for (( i = 0; i < 20; i++ )); do
            if python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:$FAKE_PORT/SelfUpdateVersion-recent.txt', timeout=2).status == 200 else 1)" 2>/dev/null; then
                SERVER_READY=0
                break
            fi
            sleep 0.5
        done
        if [ "$SERVER_READY" -ne 0 ]; then
            fail_case "fake channel server never became ready on port $FAKE_PORT"
        else
            export WSON_UPDATE_CHANNEL_URL="http://127.0.0.1:$FAKE_PORT/SelfUpdateVersion-recent.txt"
            export WSON_UPDATE_LINKS_URL="http://127.0.0.1:$FAKE_PORT/StaticDownloadLink-recent.txt"
            export WSON_UPDATE_LOCAL_VERSION="1.0.0"

            # ---- run 1: offer + auto-decline, app left alive ----
            RUN1_FAIL_BASE=$FAILED_CASES
            clear_probe_state
            SINCE=$(log_lines)
            WSON_UPDATE_AUTO_DECLINE=1 "$APP_EXE" &
            if wait_for_segment_marker "update-declined" "$SINCE"; then
                echo "PASS: run 1 log has update-declined"
            else
                fail_case "run 1: update-declined never appeared in the log"
            fi
            if segment_has "update-offered" "$SINCE"; then
                echo "PASS: run 1 log has update-offered"
            else
                fail_case "run 1: update-offered missing before decline"
            fi
            OFFER_LINE=$(tail -n +"$(( SINCE + 1 ))" "$UPDATE_LOG" | grep -n "update-offered" | head -1 | cut -d: -f1)
            DECLINE_LINE=$(tail -n +"$(( SINCE + 1 ))" "$UPDATE_LOG" | grep -n "update-declined" | head -1 | cut -d: -f1)
            if [ -n "$OFFER_LINE" ] && [ -n "$DECLINE_LINE" ] && [ "$OFFER_LINE" -lt "$DECLINE_LINE" ]; then
                echo "PASS: run 1 order update-offered before update-declined"
            else
                fail_case "run 1: offered/declined order wrong (offer=$OFFER_LINE decline=$DECLINE_LINE)"
            fi
            if app_alive; then
                echo "PASS: run 1 app still alive after decline"
            else
                fail_case "run 1: app died after decline"
            fi
            if [ -f "$CACHE_FILE" ]; then
                echo "PASS: run 1 wrote the daily cache (write-on-success)"
            else
                fail_case "run 1: cache file missing after a successful check"
            fi
            if [ "$FAILED_CASES" -eq "$RUN1_FAIL_BASE" ]; then
                matrix_record generator offered
                matrix_record generator declined
            fi
            kill_app_and_assert_death || fail_case "run 1: app could not be stopped"

            # ---- run 2 (same day): cache skip, no new offer ----
            SINCE=$(log_lines)
            WSON_UPDATE_AUTO_DECLINE=1 "$APP_EXE" &
            if wait_for_segment_marker "check-skip-cache" "$SINCE"; then
                echo "PASS: run 2 log has check-skip-cache"
            else
                fail_case "run 2: check-skip-cache never appeared"
            fi
            if segment_has "update-offered" "$SINCE"; then
                fail_case "run 2: update-offered reappeared despite same-day cache"
            else
                echo "PASS: run 2 no second offer"
            fi
            kill_app_and_assert_death || fail_case "run 2: app could not be stopped"

            # ---- run 3: kill-switch outranks everything ----
            RUN3_FAIL_BASE=$FAILED_CASES
            clear_probe_state
            printf '[Misc]\r\nw96=Enabled\r\n[Control]\r\n; comment\r\nSkipSelfUpdate=Enabled\r\nverify=Enabled\r\n' > "$INI_PATH"
            SINCE=$(log_lines)
            WSON_UPDATE_AUTO_DECLINE=1 "$APP_EXE" &
            if wait_for_segment_marker "check-skip-disabled" "$SINCE"; then
                echo "PASS: run 3 log has check-skip-disabled"
            else
                fail_case "run 3: check-skip-disabled never appeared"
            fi
            if segment_has "check-start" "$SINCE"; then
                fail_case "run 3: check-start fired despite the kill-switch"
            else
                echo "PASS: run 3 no network event"
            fi
            if [ "$FAILED_CASES" -eq "$RUN3_FAIL_BASE" ]; then
                matrix_record generator kill-switch
            fi
            kill_app_and_assert_death || fail_case "run 3: app could not be stopped"
            printf '[Control]\r\nverify=Enabled\r\nautoreboot=Disabled\r\n' > "$INI_PATH"

            # ---- run 4: offline silent failure, NO cache write ----
            RUN4_FAIL_BASE=$FAILED_CASES
            clear_probe_state
            SINCE=$(log_lines)
            WSON_UPDATE_CHANNEL_URL="http://127.0.0.1:9/SelfUpdateVersion-recent.txt" \
                WSON_UPDATE_AUTO_DECLINE=1 "$APP_EXE" &
            if wait_for_segment_marker "check-error" "$SINCE" 60; then
                echo "PASS: run 4 log has check-error"
            else
                fail_case "run 4: check-error never appeared (offline must be logged, silently)"
            fi
            if app_alive; then
                echo "PASS: run 4 app still alive after channel failure"
            else
                fail_case "run 4: app died on the unreachable channel"
            fi
            if [ -f "$CACHE_FILE" ]; then
                fail_case "run 4: cache written despite a failed channel read"
            else
                echo "PASS: run 4 cache not written on failure"
            fi
            if [ "$FAILED_CASES" -eq "$RUN4_FAIL_BASE" ]; then
                matrix_record generator offline-silent
            fi
            kill_app_and_assert_death || fail_case "run 4: app could not be stopped"

            # ---- run 5: corrupt-channel silent failure, NO cache write ----
            # A non-parseable channel line must log check-error, leave the
            # app alive and write NO daily cache (the cache is written only
            # after a completed channel read+parse). Own serve dir + own
            # server: port band 50000-50099, disjoint from the section b
            # 48000-49999 main server and section c's 51000+ range.
            RUN5_FAIL_BASE=$FAILED_CASES
            B_CORRUPT_PORT=$(( (RANDOM % 100) + 50000 ))
            BATTERY_PORTS="$BATTERY_PORTS $B_CORRUPT_PORT"
            B_CORRUPT_DIR="$SCRATCH/channel-corrupt"
            mkdir -p "$B_CORRUPT_DIR"
            printf 'not-a-channel-file\r\n' > "$B_CORRUPT_DIR/SelfUpdateVersion-recent.txt"
            printf 'https://example.com/WsusOfflineNext-9.0.0.zip\r\nhttps://example.com/WsusOfflineNext-9.0.0_hashes.txt\r\n' \
                > "$B_CORRUPT_DIR/StaticDownloadLink-recent.txt"
            ( cd "$B_CORRUPT_DIR" && python -m http.server "$B_CORRUPT_PORT" --bind 127.0.0.1 \
                > "$SCRATCH/httpd-corrupt.log" 2>&1 & )
            SERVER_READY=1
            for (( i = 0; i < 20; i++ )); do
                if python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:$B_CORRUPT_PORT/SelfUpdateVersion-recent.txt', timeout=2).status == 200 else 1)" 2>/dev/null; then
                    SERVER_READY=0
                    break
                fi
                sleep 0.5
            done
            if [ "$SERVER_READY" -ne 0 ]; then
                fail_case "run 5 corrupt-channel server never became ready on port $B_CORRUPT_PORT"
            else
                clear_probe_state
                SINCE=$(log_lines)
                WSON_UPDATE_CHANNEL_URL="http://127.0.0.1:$B_CORRUPT_PORT/SelfUpdateVersion-recent.txt" \
                    WSON_UPDATE_LINKS_URL="http://127.0.0.1:$B_CORRUPT_PORT/StaticDownloadLink-recent.txt" \
                    WSON_UPDATE_AUTO_DECLINE=1 "$APP_EXE" &
                if wait_for_segment_marker "check-error" "$SINCE" 60; then
                    echo "PASS: run 5 log has check-error (corrupt channel)"
                else
                    fail_case "run 5: check-error never appeared (a corrupt channel must fail silently)"
                fi
                if app_alive; then
                    echo "PASS: run 5 app still alive after corrupt channel"
                else
                    fail_case "run 5: app died on the corrupt channel"
                fi
                if [ -f "$CACHE_FILE" ]; then
                    fail_case "run 5: cache written despite an unparseable channel"
                else
                    echo "PASS: run 5 cache not written on parse failure"
                fi
                if [ "$FAILED_CASES" -eq "$RUN5_FAIL_BASE" ]; then
                    matrix_record generator corrupt-channel
                fi
                kill_app_and_assert_death || fail_case "run 5: app could not be stopped"
                # Corrupt server dies here (main b server dies at the EXIT
                # teardown, per the port list).
                stop_server_on_port "$B_CORRUPT_PORT"
            fi
        fi
    fi
fi

echo "section b matrix cases: $MATRIX_B"
if [ "$B_RAN" -eq 1 ] && [ "$MATRIX_B" -eq 0 ]; then
    fail_case "section b recorded zero matrix cases (vacuous pass guard)"
fi

# ============================================ section (c): native app probe

echo "--- section c: native app probe"

NATIVE_APP_NAME="UpdateInstallerLegacy"
NATIVE_CASES=0
NATIVE_FAKE_PORT=""

native_pass () {
    NATIVE_CASES=$((NATIVE_CASES + 1))
    echo "PASS: $1"
}

kill_native_app_and_assert_death () {
    powershell -NoProfile -Command \
        "Get-Process -Name '$NATIVE_APP_NAME' -ErrorAction SilentlyContinue | Stop-Process -Force" \
        >/dev/null 2>&1
    local i
    for (( i = 0; i < 10; i++ )); do
        if powershell -NoProfile -Command \
            "if (Get-Process -Name '$NATIVE_APP_NAME' -ErrorAction SilentlyContinue) { exit 1 }" \
            >/dev/null 2>&1
        then
            echo "info: $NATIVE_APP_NAME stopped"
            return 0
        fi
        sleep 1
    done
    echo "info: $NATIVE_APP_NAME STILL ALIVE after kill attempt"
    return 1
}

if [ -z "${WO_LAZARUS_ROOT:-}" ]; then
    echo "SELFUPDATE-CHECK-NATIVE-SKIP-NO-LAZARUS: WO_LAZARUS_ROOT unset, the native probe cannot build"
elif ! command -v python >/dev/null 2>&1; then
    echo "SELFUPDATE-CHECK-NATIVE-SKIP-PYTHON: python is needed to serve the fake channel"
elif ! net session >/dev/null 2>&1; then
    echo "SELFUPDATE-CHECK-NATIVE-SKIP-NOT-ELEVATED: the shipped manifest is requireAdministrator; a non-elevated shell would need a UAC click a headless battery cannot make"
else
    C_RAN=1
    NATIVE_SRC_EXE="src-native/installer/bin/installer-i386.exe"
    # Pre-build hygiene: a leaked instance from an earlier crashed battery
    # must never hold the build output as a confusing linker error.
    kill_native_app_and_assert_death || true
    rm -f "$NATIVE_SRC_EXE"
    "$WO_LAZARUS_ROOT/lazbuild.exe" --build-mode=Release-i386 \
        "$(cygpath -w src-native/installer/installer.lpi)" \
        > "$SCRATCH/native-build.log" 2>&1
    if [ $? -ne 0 ] || [ ! -f "$NATIVE_SRC_EXE" ]; then
        fail_case "native installer build failed (see scratch native-build.log)"
        tail -n 20 "$SCRATCH/native-build.log" 2>/dev/null
    else
        NATIVE_APP_DIR="$SCRATCH/native-app"
        mkdir -p "$NATIVE_APP_DIR/client"
        cp "$NATIVE_SRC_EXE" "$NATIVE_APP_DIR/client/UpdateInstallerLegacy.exe"
        NATIVE_INI_PATH="$NATIVE_APP_DIR/client/UpdateInstaller.ini"
        printf '[Control]\r\nverify=Enabled\r\nautoreboot=Disabled\r\n' > "$NATIVE_INI_PATH"

        NATIVE_SERVE_DIR="$SCRATCH/native-channel"
        mkdir -p "$NATIVE_SERVE_DIR"
        printf '9.0.0+2099.01,release\r\n' > "$NATIVE_SERVE_DIR/SelfUpdateVersion-recent.txt"
        printf 'https://example.com/WsusOfflineNext-9.0.0.zip\r\nhttps://example.com/WsusOfflineNext-9.0.0_hashes.txt\r\n' \
            > "$NATIVE_SERVE_DIR/StaticDownloadLink-recent.txt"

        # The fake server is plain HTTP: WSON_UPDATE_ALLOW_HTTP=1 lets the
        # links parser accept the http:// URLs (without the hook every case
        # would log check-error; section a's links-http reject fixture
        # proves the hook-unset shipped default stays enforced). The port
        # range 51000+ stays clear of section b's 48000+ server.
        NATIVE_FAKE_PORT=$(( (RANDOM % 2000) + 51000 ))
        BATTERY_PORTS="$BATTERY_PORTS $NATIVE_FAKE_PORT"
        ( cd "$NATIVE_SERVE_DIR" && python -m http.server "$NATIVE_FAKE_PORT" --bind 127.0.0.1 \
            > "$SCRATCH/native-httpd.log" 2>&1 & )

        # Server readiness probe (instrument, not hope).
        SERVER_READY=1
        for (( i = 0; i < 20; i++ )); do
            if python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:$NATIVE_FAKE_PORT/SelfUpdateVersion-recent.txt', timeout=2).status == 200 else 1)" 2>/dev/null; then
                SERVER_READY=0
                break
            fi
            sleep 0.5
        done
        if [ "$SERVER_READY" -ne 0 ]; then
            fail_case "native fake channel server never became ready on port $NATIVE_FAKE_PORT"
        else
            export WSON_UPDATE_CHANNEL_URL="http://127.0.0.1:$NATIVE_FAKE_PORT/SelfUpdateVersion-recent.txt"
            export WSON_UPDATE_LINKS_URL="http://127.0.0.1:$NATIVE_FAKE_PORT/StaticDownloadLink-recent.txt"
            export WSON_UPDATE_LOCAL_VERSION="1.0.0"
            export WSON_UPDATE_ALLOW_HTTP=1
            NATIVE_EXE="$NATIVE_APP_DIR/client/UpdateInstallerLegacy.exe"

            # ---- N1: offer + auto-decline, app alive, cache written ----
            N1_FAIL_BASE=$FAILED_CASES
            clear_probe_state
            SINCE=$(log_lines)
            WSON_UPDATE_AUTO_DECLINE=1 "$NATIVE_EXE" &
            if wait_for_segment_marker "update-declined" "$SINCE" 60; then
                native_pass "N1 native log has update-declined"
            else
                fail_case "N1: update-declined never appeared in the log"
            fi
            OFFER_LINE=$(tail -n +"$(( SINCE + 1 ))" "$UPDATE_LOG" | grep -n "update-offered" | head -1 | cut -d: -f1)
            DECLINE_LINE=$(tail -n +"$(( SINCE + 1 ))" "$UPDATE_LOG" | grep -n "update-declined" | head -1 | cut -d: -f1)
            if [ -n "$OFFER_LINE" ] && [ -n "$DECLINE_LINE" ] && [ "$OFFER_LINE" -lt "$DECLINE_LINE" ]; then
                native_pass "N1 order update-offered before update-declined"
            else
                fail_case "N1: offered/declined order wrong (offer=$OFFER_LINE decline=$DECLINE_LINE)"
            fi
            if app_alive "$NATIVE_APP_NAME"; then
                native_pass "N1 app still alive after decline"
            else
                fail_case "N1: app died after decline"
            fi
            if [ -f "$CACHE_FILE" ]; then
                native_pass "N1 wrote the daily cache (write-on-success)"
            else
                fail_case "N1: cache file missing after a successful check"
            fi
            if [ "$FAILED_CASES" -eq "$N1_FAIL_BASE" ]; then
                matrix_record native offered
                matrix_record native declined
            fi
            kill_native_app_and_assert_death || fail_case "N1: app could not be stopped"

            # ---- N2 (same day, no clear): cache skip, no second offer ----
            SINCE=$(log_lines)
            WSON_UPDATE_AUTO_DECLINE=1 "$NATIVE_EXE" &
            if wait_for_segment_marker "check-skip-cache" "$SINCE" 60; then
                native_pass "N2 native log has check-skip-cache"
            else
                fail_case "N2: check-skip-cache never appeared"
            fi
            if segment_has "update-offered" "$SINCE"; then
                fail_case "N2: update-offered reappeared despite same-day cache"
            else
                native_pass "N2 no second offer"
            fi
            kill_native_app_and_assert_death || fail_case "N2: app could not be stopped"

            # ---- N3: kill-switch outranks everything ----
            N3_FAIL_BASE=$FAILED_CASES
            clear_probe_state
            printf '[Misc]\r\nw96=Enabled\r\n[Control]\r\n; comment\r\nSkipSelfUpdate=Enabled\r\nverify=Enabled\r\n' > "$NATIVE_INI_PATH"
            SINCE=$(log_lines)
            WSON_UPDATE_AUTO_DECLINE=1 "$NATIVE_EXE" &
            if wait_for_segment_marker "check-skip-disabled" "$SINCE" 60; then
                native_pass "N3 native log has check-skip-disabled"
            else
                fail_case "N3: check-skip-disabled never appeared"
            fi
            if segment_has "check-start" "$SINCE"; then
                fail_case "N3: check-start fired despite the kill-switch"
            else
                native_pass "N3 no network event (kill-switch outranks everything)"
            fi
            if [ "$FAILED_CASES" -eq "$N3_FAIL_BASE" ]; then
                matrix_record native kill-switch
            fi
            kill_native_app_and_assert_death || fail_case "N3: app could not be stopped"
            printf '[Control]\r\nverify=Enabled\r\nautoreboot=Disabled\r\n' > "$NATIVE_INI_PATH"

            # ---- N4: offline silent failure, NO cache write ----
            N4_FAIL_BASE=$FAILED_CASES
            clear_probe_state
            SINCE=$(log_lines)
            WSON_UPDATE_CHANNEL_URL="http://127.0.0.1:9/SelfUpdateVersion-recent.txt" \
                WSON_UPDATE_AUTO_DECLINE=1 "$NATIVE_EXE" &
            if wait_for_segment_marker "check-error" "$SINCE" 60; then
                native_pass "N4 native log has check-error"
            else
                fail_case "N4: check-error never appeared (offline must be logged, silently)"
            fi
            if app_alive "$NATIVE_APP_NAME"; then
                native_pass "N4 app still alive after channel failure"
            else
                fail_case "N4: app died on the unreachable channel"
            fi
            if [ -f "$CACHE_FILE" ]; then
                fail_case "N4: cache written despite a failed channel read"
            else
                native_pass "N4 cache not written on failure"
            fi
            if [ "$FAILED_CASES" -eq "$N4_FAIL_BASE" ]; then
                matrix_record native offline-silent
            fi
            kill_native_app_and_assert_death || fail_case "N4: app could not be stopped"

            # ---- N5: corrupt-channel silent failure, NO cache write ----
            # Same mechanics as run 5 against a corrupt variant of the
            # native serve tree: port band 53000-53099 (disjoint from the
            # native main server's 51000+ range).
            N5_FAIL_BASE=$FAILED_CASES
            NATIVE_CORRUPT_PORT=$(( (RANDOM % 100) + 53000 ))
            BATTERY_PORTS="$BATTERY_PORTS $NATIVE_CORRUPT_PORT"
            NATIVE_CORRUPT_DIR="$SCRATCH/native-channel-corrupt"
            mkdir -p "$NATIVE_CORRUPT_DIR"
            printf 'not-a-channel-file\r\n' > "$NATIVE_CORRUPT_DIR/SelfUpdateVersion-recent.txt"
            printf 'https://example.com/WsusOfflineNext-9.0.0.zip\r\nhttps://example.com/WsusOfflineNext-9.0.0_hashes.txt\r\n' \
                > "$NATIVE_CORRUPT_DIR/StaticDownloadLink-recent.txt"
            ( cd "$NATIVE_CORRUPT_DIR" && python -m http.server "$NATIVE_CORRUPT_PORT" --bind 127.0.0.1 \
                > "$SCRATCH/native-httpd-corrupt.log" 2>&1 & )
            SERVER_READY=1
            for (( i = 0; i < 20; i++ )); do
                if python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:$NATIVE_CORRUPT_PORT/SelfUpdateVersion-recent.txt', timeout=2).status == 200 else 1)" 2>/dev/null; then
                    SERVER_READY=0
                    break
                fi
                sleep 0.5
            done
            if [ "$SERVER_READY" -ne 0 ]; then
                fail_case "N5 corrupt-channel server never became ready on port $NATIVE_CORRUPT_PORT"
            else
                clear_probe_state
                SINCE=$(log_lines)
                WSON_UPDATE_CHANNEL_URL="http://127.0.0.1:$NATIVE_CORRUPT_PORT/SelfUpdateVersion-recent.txt" \
                    WSON_UPDATE_LINKS_URL="http://127.0.0.1:$NATIVE_CORRUPT_PORT/StaticDownloadLink-recent.txt" \
                    WSON_UPDATE_AUTO_DECLINE=1 "$NATIVE_EXE" &
                if wait_for_segment_marker "check-error" "$SINCE" 60; then
                    native_pass "N5 native log has check-error (corrupt channel)"
                else
                    fail_case "N5: check-error never appeared (a corrupt channel must fail silently)"
                fi
                if app_alive "$NATIVE_APP_NAME"; then
                    native_pass "N5 app still alive after corrupt channel"
                else
                    fail_case "N5: app died on the corrupt channel"
                fi
                if [ -f "$CACHE_FILE" ]; then
                    fail_case "N5: cache written despite an unparseable channel"
                else
                    native_pass "N5 cache not written on parse failure"
                fi
                if [ "$FAILED_CASES" -eq "$N5_FAIL_BASE" ]; then
                    matrix_record native corrupt-channel
                fi
                kill_native_app_and_assert_death || fail_case "N5: app could not be stopped"
                stop_server_on_port "$NATIVE_CORRUPT_PORT"
            fi
        fi
    fi
fi

# Section d reuses the 52000+ band: free section c's servers now so the
# bands stay disjoint in TIME as well (the EXIT port list is the backstop).
stop_server_on_port "${NATIVE_FAKE_PORT:-}"
stop_server_on_port "${NATIVE_CORRUPT_PORT:-}"

echo "section c native cases: $NATIVE_CASES"
if [ "$NATIVE_CASES" -eq 0 ]; then
    fail_case "section c enumerated zero native cases (vacuous pass guard)"
fi
echo "section c matrix cases: $MATRIX_C"
if [ "$C_RAN" -eq 1 ] && [ "$MATRIX_C" -eq 0 ]; then
    fail_case "section c recorded zero matrix cases (vacuous pass guard)"
fi

# ============================================ section (d): installer probe

echo "--- section d: modern installer live probe"

INSTALLER_APP_NAME="UpdateInstallerModern"
INSTALLER_CSproj="src-modern/installer/host/UpdateInstaller.csproj"
INSTALLER_CASES=0
INSTALLER_FAKE_PORT=""
INSTALLER_CORRUPT_PORT=""

installer_pass () {
    INSTALLER_CASES=$((INSTALLER_CASES + 1))
    echo "PASS: $1"
}

kill_installer_app_and_assert_death () {
    powershell -NoProfile -Command \
        "Get-Process -Name '$INSTALLER_APP_NAME' -ErrorAction SilentlyContinue | Stop-Process -Force" \
        >/dev/null 2>&1
    local i
    for (( i = 0; i < 10; i++ )); do
        if powershell -NoProfile -Command \
            "if (Get-Process -Name '$INSTALLER_APP_NAME' -ErrorAction SilentlyContinue) { exit 1 }" \
            >/dev/null 2>&1
        then
            echo "info: $INSTALLER_APP_NAME stopped"
            return 0
        fi
        sleep 1
    done
    echo "info: $INSTALLER_APP_NAME STILL ALIVE after kill attempt"
    return 1
}

if [ "$WEBVIEW2_PRESENT" != "yes" ]; then
    echo "SELFUPDATE-CHECK-INSTALLER-SKIP-WEBVIEW2: no WebView2 runtime, the installer host would take the fallback shell"
elif ! command -v python >/dev/null 2>&1; then
    echo "SELFUPDATE-CHECK-INSTALLER-SKIP-PYTHON: python is needed to serve the fake channel"
elif ! net session >/dev/null 2>&1; then
    echo "SELFUPDATE-CHECK-INSTALLER-SKIP-NOT-ELEVATED: the shipped manifest is requireAdministrator; a non-elevated shell would need a UAC click a headless battery cannot make"
else
    D_RAN=1
    dotnet publish "$INSTALLER_CSproj" -c Release -r win-x64 \
        -p:PublishSingleFile=true -p:SelfContained=false \
        -o "$(native_path "$SCRATCH/installer-app")" > "$SCRATCH/installer-publish.log" 2>&1
    if [ $? -ne 0 ] || [ ! -f "$SCRATCH/installer-app/UpdateInstaller.exe" ]; then
        fail_case "installer host publish failed (see scratch installer-publish.log)"
        tail -n 20 "$SCRATCH/installer-publish.log" 2>/dev/null
    else
        # Scratch install: the host ships inside client\, so the exe is
        # renamed into the distribution slot under client\, the INI sits
        # beside it (InstallRoot = parent of the exe directory) and the
        # published wwwroot tree is copied next to the exe (best-effort -
        # the exe carries the embedded-resource fallback).
        INST_D="$SCRATCH/installer-app/install"
        mkdir -p "$INST_D/client"
        cp "$SCRATCH/installer-app/UpdateInstaller.exe" "$INST_D/client/UpdateInstallerModern.exe"
        INSTALLER_INI_PATH="$INST_D/client/UpdateInstaller.ini"
        printf '[Control]\r\nverify=Enabled\r\nautoreboot=Disabled\r\n' > "$INSTALLER_INI_PATH"
        cp -r "$SCRATCH/installer-app/wwwroot" "$INST_D/client/wwwroot" 2>/dev/null || true

        INSTALLER_SERVE_DIR="$SCRATCH/installer-channel"
        mkdir -p "$INSTALLER_SERVE_DIR"
        printf '9.0.0+2099.01,release\r\n' > "$INSTALLER_SERVE_DIR/SelfUpdateVersion-recent.txt"
        printf 'https://example.com/WsusOfflineNext-9.0.0.zip\r\nhttps://example.com/WsusOfflineNext-9.0.0_hashes.txt\r\n' \
            > "$INSTALLER_SERVE_DIR/StaticDownloadLink-recent.txt"

        # Port band 52000-52099: section c's servers are stopped before
        # this section starts, so the bands stay disjoint in time.
        INSTALLER_FAKE_PORT=$(( (RANDOM % 100) + 52000 ))
        BATTERY_PORTS="$BATTERY_PORTS $INSTALLER_FAKE_PORT"
        ( cd "$INSTALLER_SERVE_DIR" && python -m http.server "$INSTALLER_FAKE_PORT" --bind 127.0.0.1 \
            > "$SCRATCH/installer-httpd.log" 2>&1 & )

        # Server readiness probe (instrument, not hope).
        SERVER_READY=1
        for (( i = 0; i < 20; i++ )); do
            if python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:$INSTALLER_FAKE_PORT/SelfUpdateVersion-recent.txt', timeout=2).status == 200 else 1)" 2>/dev/null; then
                SERVER_READY=0
                break
            fi
            sleep 0.5
        done
        if [ "$SERVER_READY" -ne 0 ]; then
            fail_case "installer fake channel server never became ready on port $INSTALLER_FAKE_PORT"
        else
            export WSON_UPDATE_CHANNEL_URL="http://127.0.0.1:$INSTALLER_FAKE_PORT/SelfUpdateVersion-recent.txt"
            export WSON_UPDATE_LINKS_URL="http://127.0.0.1:$INSTALLER_FAKE_PORT/StaticDownloadLink-recent.txt"
            export WSON_UPDATE_LOCAL_VERSION="1.0.0"
            export WSON_UPDATE_ALLOW_HTTP=1
            INSTALLER_EXE="$INST_D/client/UpdateInstallerModern.exe"

            # Pre-run hygiene: a leaked instance from an earlier crashed
            # battery must never survive into the runs (6020 convention).
            kill_installer_app_and_assert_death || true

            # ---- D1: offer + auto-decline, app alive, cache written ----
            D1_FAIL_BASE=$FAILED_CASES
            clear_probe_state
            SINCE=$(log_lines)
            WSON_UPDATE_AUTO_DECLINE=1 "$INSTALLER_EXE" &
            if wait_for_segment_marker "update-declined" "$SINCE" 60; then
                installer_pass "D1 installer log has update-declined"
            else
                fail_case "D1: update-declined never appeared in the log"
            fi
            OFFER_LINE=$(tail -n +"$(( SINCE + 1 ))" "$UPDATE_LOG" | grep -n "update-offered" | head -1 | cut -d: -f1)
            DECLINE_LINE=$(tail -n +"$(( SINCE + 1 ))" "$UPDATE_LOG" | grep -n "update-declined" | head -1 | cut -d: -f1)
            if [ -n "$OFFER_LINE" ] && [ -n "$DECLINE_LINE" ] && [ "$OFFER_LINE" -lt "$DECLINE_LINE" ]; then
                installer_pass "D1 order update-offered before update-declined"
            else
                fail_case "D1: offered/declined order wrong (offer=$OFFER_LINE decline=$DECLINE_LINE)"
            fi
            if app_alive "$INSTALLER_APP_NAME"; then
                installer_pass "D1 app still alive after decline"
            else
                fail_case "D1: app died after decline"
            fi
            if [ -f "$CACHE_FILE" ]; then
                installer_pass "D1 wrote the daily cache (write-on-success)"
            else
                fail_case "D1: cache file missing after a successful check"
            fi
            if [ "$FAILED_CASES" -eq "$D1_FAIL_BASE" ]; then
                matrix_record installer-modern offered
                matrix_record installer-modern declined
            fi
            kill_installer_app_and_assert_death || fail_case "D1: app could not be stopped"

            # ---- D2 (same day, no clear): cache skip, no second offer ----
            SINCE=$(log_lines)
            WSON_UPDATE_AUTO_DECLINE=1 "$INSTALLER_EXE" &
            if wait_for_segment_marker "check-skip-cache" "$SINCE" 60; then
                installer_pass "D2 installer log has check-skip-cache"
            else
                fail_case "D2: check-skip-cache never appeared"
            fi
            if segment_has "update-offered" "$SINCE"; then
                fail_case "D2: update-offered reappeared despite same-day cache"
            else
                installer_pass "D2 no second offer"
            fi
            kill_installer_app_and_assert_death || fail_case "D2: app could not be stopped"

            # ---- D3: kill-switch outranks everything ----
            D3_FAIL_BASE=$FAILED_CASES
            clear_probe_state
            printf '[Misc]\r\nw96=Enabled\r\n[Control]\r\n; comment\r\nSkipSelfUpdate=Enabled\r\nverify=Enabled\r\n' > "$INSTALLER_INI_PATH"
            SINCE=$(log_lines)
            WSON_UPDATE_AUTO_DECLINE=1 "$INSTALLER_EXE" &
            if wait_for_segment_marker "check-skip-disabled" "$SINCE" 60; then
                installer_pass "D3 installer log has check-skip-disabled"
            else
                fail_case "D3: check-skip-disabled never appeared"
            fi
            if segment_has "check-start" "$SINCE"; then
                fail_case "D3: check-start fired despite the kill-switch"
            else
                installer_pass "D3 no network event (kill-switch outranks everything)"
            fi
            if [ "$FAILED_CASES" -eq "$D3_FAIL_BASE" ]; then
                matrix_record installer-modern kill-switch
            fi
            kill_installer_app_and_assert_death || fail_case "D3: app could not be stopped"
            printf '[Control]\r\nverify=Enabled\r\nautoreboot=Disabled\r\n' > "$INSTALLER_INI_PATH"

            # ---- D4: offline silent failure, NO cache write ----
            D4_FAIL_BASE=$FAILED_CASES
            clear_probe_state
            SINCE=$(log_lines)
            WSON_UPDATE_CHANNEL_URL="http://127.0.0.1:9/SelfUpdateVersion-recent.txt" \
                WSON_UPDATE_AUTO_DECLINE=1 "$INSTALLER_EXE" &
            if wait_for_segment_marker "check-error" "$SINCE" 60; then
                installer_pass "D4 installer log has check-error"
            else
                fail_case "D4: check-error never appeared (offline must be logged, silently)"
            fi
            if app_alive "$INSTALLER_APP_NAME"; then
                installer_pass "D4 app still alive after channel failure"
            else
                fail_case "D4: app died on the unreachable channel"
            fi
            if [ -f "$CACHE_FILE" ]; then
                fail_case "D4: cache written despite a failed channel read"
            else
                installer_pass "D4 cache not written on failure"
            fi
            if [ "$FAILED_CASES" -eq "$D4_FAIL_BASE" ]; then
                matrix_record installer-modern offline-silent
            fi
            kill_installer_app_and_assert_death || fail_case "D4: app could not be stopped"

            # ---- D5: corrupt-channel silent failure, NO cache write ----
            # Own corrupt serve dir, port band 54000-54099.
            D5_FAIL_BASE=$FAILED_CASES
            INSTALLER_CORRUPT_PORT=$(( (RANDOM % 100) + 54000 ))
            BATTERY_PORTS="$BATTERY_PORTS $INSTALLER_CORRUPT_PORT"
            INSTALLER_CORRUPT_DIR="$SCRATCH/installer-channel-corrupt"
            mkdir -p "$INSTALLER_CORRUPT_DIR"
            printf 'not-a-channel-file\r\n' > "$INSTALLER_CORRUPT_DIR/SelfUpdateVersion-recent.txt"
            printf 'https://example.com/WsusOfflineNext-9.0.0.zip\r\nhttps://example.com/WsusOfflineNext-9.0.0_hashes.txt\r\n' \
                > "$INSTALLER_CORRUPT_DIR/StaticDownloadLink-recent.txt"
            ( cd "$INSTALLER_CORRUPT_DIR" && python -m http.server "$INSTALLER_CORRUPT_PORT" --bind 127.0.0.1 \
                > "$SCRATCH/installer-httpd-corrupt.log" 2>&1 & )
            SERVER_READY=1
            for (( i = 0; i < 20; i++ )); do
                if python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:$INSTALLER_CORRUPT_PORT/SelfUpdateVersion-recent.txt', timeout=2).status == 200 else 1)" 2>/dev/null; then
                    SERVER_READY=0
                    break
                fi
                sleep 0.5
            done
            if [ "$SERVER_READY" -ne 0 ]; then
                fail_case "D5 corrupt-channel server never became ready on port $INSTALLER_CORRUPT_PORT"
            else
                clear_probe_state
                SINCE=$(log_lines)
                WSON_UPDATE_CHANNEL_URL="http://127.0.0.1:$INSTALLER_CORRUPT_PORT/SelfUpdateVersion-recent.txt" \
                    WSON_UPDATE_LINKS_URL="http://127.0.0.1:$INSTALLER_CORRUPT_PORT/StaticDownloadLink-recent.txt" \
                    WSON_UPDATE_AUTO_DECLINE=1 "$INSTALLER_EXE" &
                if wait_for_segment_marker "check-error" "$SINCE" 60; then
                    installer_pass "D5 installer log has check-error (corrupt channel)"
                else
                    fail_case "D5: check-error never appeared (a corrupt channel must fail silently)"
                fi
                if app_alive "$INSTALLER_APP_NAME"; then
                    installer_pass "D5 app still alive after corrupt channel"
                else
                    fail_case "D5: app died on the corrupt channel"
                fi
                if [ -f "$CACHE_FILE" ]; then
                    fail_case "D5: cache written despite an unparseable channel"
                else
                    installer_pass "D5 cache not written on parse failure"
                fi
                if [ "$FAILED_CASES" -eq "$D5_FAIL_BASE" ]; then
                    matrix_record installer-modern corrupt-channel
                fi
                kill_installer_app_and_assert_death || fail_case "D5: app could not be stopped"
            fi

            # Both installer servers die here; the EXIT port list is the
            # backstop.
            stop_server_on_port "$INSTALLER_FAKE_PORT"
            stop_server_on_port "$INSTALLER_CORRUPT_PORT"
        fi
    fi
fi

echo "section d installer cases: $INSTALLER_CASES"
if [ "$D_RAN" -eq 1 ] && [ "$INSTALLER_CASES" -eq 0 ]; then
    fail_case "section d enumerated zero installer cases (vacuous pass guard)"
fi
echo "section d matrix cases: $MATRIX_D"
if [ "$D_RAN" -eq 1 ] && [ "$MATRIX_D" -eq 0 ]; then
    fail_case "section d recorded zero matrix cases (vacuous pass guard)"
fi

# ------------------------------------------------------------- verdict

if [ "$MATRIX_TOTAL" -eq 0 ]; then
    fail_case "battery recorded zero MATRIX cases (vacuous pass guard)"
fi
echo "MATRIX SUMMARY: $MATRIX_TOTAL check cases recorded"

if [ "$FAILED_CASES" -ne 0 ]; then
    echo "SELFUPDATE-CHECK: RED ($FAILED_CASES failing case(s))"
    exit 1
fi
echo "SELFUPDATE-CHECK: GREEN"
exit 0
