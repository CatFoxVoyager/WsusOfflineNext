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

fail_case () {
    echo "FAIL: $1"
    FAILED_CASES=$((FAILED_CASES + 1))
    return 0
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

cleanup () {
    # Guarded cleanup: kill the app with an explicit death assertion
    # (a leaked GUI instance locks the next build), then the fake
    # channel server by its listening port, then remove the scratch.
    if command -v powershell >/dev/null 2>&1; then
        powershell -NoProfile -Command \
            "Get-Process -Name '$APP_NAME' -ErrorAction SilentlyContinue | Stop-Process -Force" \
            >/dev/null 2>&1
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
    tasklist 2>/dev/null | grep -qi "$APP_NAME"
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

dotnet build "$PROBE_DIR/SelfUpdateProbe.csproj" -v q > "$SCRATCH/probe-build.log" 2>&1
if [ $? -ne 0 ]; then
    echo "FAIL: probe project did not build (see scratch probe-build.log)"
    cat "$SCRATCH/probe-build.log"
    exit 1
fi
PROBE_EXE="$PROBE_DIR/bin/Debug/net8.0-windows/SelfUpdateProbe.exe"
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
            kill_app_and_assert_death || fail_case "run 3: app could not be stopped"
            printf '[Control]\r\nverify=Enabled\r\nautoreboot=Disabled\r\n' > "$INI_PATH"

            # ---- run 4: offline silent failure, NO cache write ----
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
            kill_app_and_assert_death || fail_case "run 4: app could not be stopped"
        fi
    fi
fi

# ------------------------------------------------------------- verdict

if [ "$FAILED_CASES" -ne 0 ]; then
    echo "SELFUPDATE-CHECK: RED ($FAILED_CASES failing case(s))"
    exit 1
fi
echo "SELFUPDATE-CHECK: GREEN"
exit 0
