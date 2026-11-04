#!/usr/bin/env bash
# Battery for the in-host WebView2 startup gate (issue #21 round 3) — run
# from repo root.
#
# Portable by construction: no WebView2 runtime, no dotnet, no Windows.
# The comparator semantics are verified against a bash mirror carrying the
# same contract as the C# WebView2Compat.IsVersionAtLeast helper (strip any
# '+'/'-' suffix, then 4-part numeric compare with missing or non-numeric
# parts counting as 0). The REAL compiled helper is exercised separately on
# a Windows host by the round-3 scratch probe.
#
# Since Phase 24 plan 01, the double-click entry points are the two pure
# .cmd launchers; the .au3 launcher sources are superseded (deleted in
# Phase 25/26) and the battery no longer reads them.
#
# Sections:
#   a. comparator semantics: absent -> gate, older -> gate, equal -> pass,
#      newer -> pass, '+'/'-' suffix -> pass, boundary one-below -> gate,
#      unparsable / partial / leading-zero forms
#   b. sync: the C# const in BOTH hosts equals the .cmd launcher floor in
#      BOTH launcher files (four-way), each declaration and the raw literal
#      appearing exactly once per file (comments and dialogs must not
#      recopy)
#   c. structure: each host registers ThreadException + the AppDomain net +
#      SetUnhandledExceptionMode, probes GetAvailableBrowserVersionString
#      exactly once, and wraps the whole SendToWeb body in try/catch
#   d. the battery can fail: the floor-sync gate goes red on a mutated
#      sandbox copy (both a C# const mutation and a .cmd launcher floor
#      mutation), the probe-parity gate goes red on a corrupted probe GUID,
#      and the mirror control rejects an older runtime
#   e. per-launcher .cmd routing structure: probe parity (3+3 GUID views),
#      view pinning (exactly 5 /reg:64 query flags), parse shape (the
#      REG_SZ findstr filter on every probe read and the build probe,
#      exactly one CompareVersions.vbs invocation), contract atoms
#      (override tokens, INI key, pause, extension probe, endlocal-coupled
#      exits), the bilingual [launcher] message contract, bans (no delayed
#      expansion, no window-spawning shell verb as a command word, no echo
#      of registry-derived values) and the generator/installer elevation
#      asymmetry (elevation only in the installer)
#
# Counting rule for every section e occurrence gate: lines whose first
# token is rem/REM or :: are stripped before counting — code lines only.
# The launchers carry mandated English comments (plan 01's floor and
# deviations blocks), so raw-line counts would false-fail on plan-required
# prose.
set -u

GEN_CS="src-modern/generator/host/Program.cs"
INS_CS="src-modern/installer/host/Program.cs"
GEN_CMD="UpdateGenerator.cmd"
INS_CMD="client/UpdateInstaller.cmd"

FAILED_CASES=0

fail_case () {
    echo "FAIL: $1"
    FAILED_CASES=$((FAILED_CASES + 1))
    return 0
}

# --- Bash mirror of WebView2Compat.IsVersionAtLeast (the semantic spec) ---
mirror_is_version_at_least () {
    # $1 = version (empty string stands for the C# null/absent case),
    # $2 = minimum. Returns 0 (true) when version >= minimum.
    local version="$1" minimum="$2"
    [ -n "${version}" ] || return 1
    [ -n "${minimum}" ] || return 1
    version="${version%%[+-]*}"
    minimum="${minimum%%[+-]*}"
    local IFS='.'
    # shellcheck disable=SC2206  # word splitting on the dots is the point
    local v_parts=(${version})
    # shellcheck disable=SC2206
    local m_parts=(${minimum})
    local count=$(( ${#v_parts[@]} > ${#m_parts[@]} ? ${#v_parts[@]} : ${#m_parts[@]} ))
    local i v m
    for (( i = 0; i < count; i++ )); do
        v=0
        m=0
        if (( i < ${#v_parts[@]} )) && [[ "${v_parts[i]}" =~ ^[0-9]+$ ]]; then
            v=$((10#${v_parts[i]}))
        fi
        if (( i < ${#m_parts[@]} )) && [[ "${m_parts[i]}" =~ ^[0-9]+$ ]]; then
            m=$((10#${m_parts[i]}))
        fi
        if (( v < m )); then return 1; fi
        if (( v > m )); then return 0; fi
    done
    return 0
}

# --- Shared helpers for the sync and probe-parity gates --------------------
# floor_sync_ok runs the section-b four-way equality chain over the four
# consumer files passed as arguments (gen_cs ins_cs gen_cmd ins_cmd) and
# returns 0 only when every floor literal matches the battery's own
# MIN_LITERAL. It is the single implementation the can-fail controls reuse.
floor_sync_ok () {
    local g_cs i_cs g_cmd i_cmd
    g_cs="$(extract_min_from_cs "$1")"
    i_cs="$(extract_min_from_cs "$2")"
    g_cmd="$(extract_min_from_cmd "$3")"
    i_cmd="$(extract_min_from_cmd "$4")"
    [ -n "${g_cs}" ]  || return 1
    [ -n "${i_cs}" ]  || return 1
    [ -n "${g_cmd}" ] || return 1
    [ -n "${i_cmd}" ] || return 1
    [ "${g_cs}" = "${i_cs}" ]  || return 1
    [ "${i_cs}" = "${g_cmd}" ] || return 1
    [ "${g_cmd}" = "${i_cmd}" ] || return 1
    [ "${i_cmd}" = "${MIN_LITERAL}" ] || return 1
    return 0
}

# probe_parity_ok returns 0 only when both EdgeUpdate probe GUIDs appear
# exactly 3 times in the launcher's code lines (WOW6432Node HKLM, native
# HKLM, HKCU — the three views of the incumbent's 8-probe contract).
probe_parity_ok () {
    local code
    code="$(grep -ivE '^[[:space:]]*(rem([[:space:]]|$)|::)' "$1")"
    [ "$(printf '%s\n' "${code}" | grep -cF 'F3017226-FE2A-4295-8BDF-00C3A9A7E4C5')" -eq 3 ] || return 1
    [ "$(printf '%s\n' "${code}" | grep -cF 'F3017226-F55F-4E40-8A2F-69DF4B838507')" -eq 3 ] || return 1
    return 0
}

# --- Section a: comparator semantics ---
MIN_LITERAL="156.0.4314.35"

check_semantics () {
    # $1 = version, $2 = expected (gate|pass), $3 = label
    mirror_is_version_at_least "$1" "${MIN_LITERAL}"
    local rc=$?
    if [ "$2" = "pass" ]; then
        [ "${rc}" -eq 0 ] || fail_case "section a: '$1' should pass ($3)"
    else
        [ "${rc}" -ne 0 ] || fail_case "section a: '$1' should gate ($3)"
    fi
}

echo "== Section a: comparator semantics (bash mirror of the C# helper) =="
check_semantics ""                     gate  "absent runtime"
check_semantics "109.0.1518.78"        gate  "older runtime (reporter case)"
check_semantics "156.0.4314.34"        gate  "one part below the minimum"
check_semantics "156.0.4314.35"        pass  "exactly the minimum"
check_semantics "156.0.4314.58"        pass  "newer runtime"
check_semantics "157.0.0.1"            pass  "next major"
check_semantics "156.0.4314.35-beta"   pass  "hyphen-suffix form"
check_semantics "156.0.4314.35+build"  pass  "plus-suffix form"
check_semantics "abc"                  gate  "unparsable (fail-safe)"
check_semantics "156.0"                gate  "missing parts count as 0"
check_semantics "0156.0.4314.35"       pass  "leading zeros are numeric"

# --- Section b: const/literal sync across both hosts and both launchers ---
echo "== Section b: C# const == .cmd launcher floor, four-way, exactly once per file =="

extract_min_from_cs () {
    grep -oE 'MinWebView2Version = "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' "$1" \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'
}

extract_min_from_cmd () {
    # The .cmd floor set-line shape: set "MIN_WEBVIEW2_VERSION=<4-part>".
    # Substring-anchored (never end-of-line anchored — the launcher files
    # are CRLF).
    grep -oE 'set "MIN_WEBVIEW2_VERSION=[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' "$1" \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'
}

count_lines () {
    # $1 = fixed-string needle, $2 = file
    grep -cF "$1" "$2"
}

GEN_MIN="$(extract_min_from_cs "${GEN_CS}")"
INS_MIN="$(extract_min_from_cs "${INS_CS}")"
GEN_CMD_MIN="$(extract_min_from_cmd "${GEN_CMD}")"
INS_CMD_MIN="$(extract_min_from_cmd "${INS_CMD}")"

[ -n "${GEN_MIN}" ]     || fail_case "section b: no MinWebView2Version const in ${GEN_CS}"
[ -n "${INS_MIN}" ]     || fail_case "section b: no MinWebView2Version const in ${INS_CS}"
[ -n "${GEN_CMD_MIN}" ] || fail_case "section b: no MIN_WEBVIEW2_VERSION set-line in ${GEN_CMD}"
[ -n "${INS_CMD_MIN}" ] || fail_case "section b: no MIN_WEBVIEW2_VERSION set-line in ${INS_CMD}"

if ! floor_sync_ok "${GEN_CS}" "${INS_CS}" "${GEN_CMD}" "${INS_CMD}"; then
    fail_case "section b: four-way floor sync broken (gen.cs=${GEN_MIN:-none} ins.cs=${INS_MIN:-none} gen.cmd=${GEN_CMD_MIN:-none} ins.cmd=${INS_CMD_MIN:-none})"
fi

# The declared minimum in the battery must be what the hosts declare too.
[ "${GEN_MIN:-x}" = "${MIN_LITERAL}" ] \
    || fail_case "section b: generator const != battery spec literal"

# Exactly one declaration and one raw literal per consumer file: a second
# raw occurrence means a comment or dialog recopied the value and would
# drift silently on the next SDK bump.
for f in "${GEN_CS}" "${INS_CS}"; do
    [ "$(count_lines 'MinWebView2Version = "' "${f}")" -eq 1 ] \
        || fail_case "section b: expected exactly one const declaration in ${f}"
    [ "$(count_lines "${GEN_MIN:-156.0.4314.35}" "${f}")" -eq 1 ] \
        || fail_case "section b: raw literal must appear exactly once in ${f}"
done
for f in "${GEN_CMD}" "${INS_CMD}"; do
    [ "$(count_lines 'set "MIN_WEBVIEW2_VERSION=' "${f}")" -eq 1 ] \
        || fail_case "section b: expected exactly one floor set-line in ${f}"
    [ "$(count_lines "${GEN_MIN:-156.0.4314.35}" "${f}")" -eq 1 ] \
        || fail_case "section b: raw literal must appear exactly once in ${f}"
done

# --- Section c: structural gates per host ---
echo "== Section c: net + gate + SendToWeb wrap present in both hosts =="

for f in "${GEN_CS}" "${INS_CS}"; do
    [ "$(grep -c 'Application.ThreadException' "${f}")" -ge 1 ] \
        || fail_case "section c: no Application.ThreadException in ${f}"
    [ "$(grep -c 'AppDomain.CurrentDomain.UnhandledException' "${f}")" -ge 1 ] \
        || fail_case "section c: no AppDomain.UnhandledException in ${f}"
    [ "$(grep -c 'SetUnhandledExceptionMode' "${f}")" -ge 1 ] \
        || fail_case "section c: no SetUnhandledExceptionMode in ${f}"
    # Exactly one runtime-probe CALL SITE per host: comment lines are
    # stripped first (the startup-diagnostics comment block cites the call
    # without making one; commit dec9a5f split the original probe's two
    # roles onto this single site: version gate + unconditional diagnostics).
    [ "$(grep -vE '^[[:space:]]*//' "${f}" | grep -c 'GetAvailableBrowserVersionString')" -eq 1 ] \
        || fail_case "section c: expected exactly one runtime probe call site in ${f}"
    [ "$(grep -c 'HandleFatal' "${f}")" -ge 2 ] \
        || fail_case "section c: HandleFatal missing or unreferenced in ${f}"

    # The SendToWeb body is wrapped in try (outer + inner), read over the
    # method region rather than a fixed 6-line head window — the marshal-
    # everything rewrite (commit da2ef4a) grew the lead comment block past
    # any fixed window.
    region="$(sed -n '/private void SendToWeb/,/^        }$/p' "${f}")"
    [ "$(printf '%s\n' "${region}" | grep -c 'try')" -ge 2 ] \
        || fail_case "section c: SendToWeb body is not wrapped in try (outer + inner) in ${f}"
    [ "$(printf '%s\n' "${region}" | grep -c 'catch')" -ge 2 ] \
        || fail_case "section c: SendToWeb needs outer + inner catch in ${f}"
done

# --- Section e: per-launcher .cmd routing structure (code lines only) ------
echo "== Section e: .cmd launcher structure (probes, pinning, atoms, bans, asymmetry) =="

# Lines whose first token is rem/REM (or the :: comment form) are stripped
# before counting. The launchers carry mandated English comments (plan 01's
# floor and deviations blocks); raw-line counts would false-fail on
# plan-required prose.
check_cmd_launcher_structure () {
    f="$1"
    code="$(grep -ivE '^[[:space:]]*(rem([[:space:]]|$)|::)' "${f}")"

    # Probe parity: both EdgeUpdate GUIDs exactly 3 views each.
    probe_parity_ok "${f}" \
        || fail_case "section e: probe parity broken in ${f} (expected 3 occurrences of each EdgeUpdate GUID over code lines)"

    # View pinning: exactly 5 /reg:64 flags (4 HKLM EdgeUpdate probes + the
    # OS build probe); the two HKCU probes carry none.
    reg64="$(printf '%s\n' "${code}" | grep -cF '/reg:64')"
    [ "${reg64}" -eq 5 ] \
        || fail_case "section e: expected exactly 5 /reg:64 view flags in ${f}, found ${reg64}"

    # Parse shape: every probe read applies the REG_SZ findstr filter. The
    # launchers share one probe subroutine, so this is 6 call sites x 1
    # shared filter line + 1 build-probe filter line = 7 filtered reads per
    # launch (2 code lines). Exactly one cscript invocation of the
    # client-side comparator.
    probe_calls="$(printf '%s\n' "${code}" | grep -cF 'call :ProbeWebView2Key')"
    [ "${probe_calls}" -eq 6 ] \
        || fail_case "section e: expected exactly 6 probe call sites in ${f}, found ${probe_calls}"
    reg_sz="$(printf '%s\n' "${code}" | grep -cF 'REG_SZ')"
    [ "${reg_sz}" -eq 2 ] \
        || fail_case "section e: expected exactly 2 REG_SZ filter lines (shared probe subroutine + build probe = 7 filtered reads) in ${f}, found ${reg_sz}"
    [ "$(printf '%s\n' "${code}" | grep -c 'CompareVersions.vbs')" -eq 1 ] \
        || fail_case "section e: expected exactly one CompareVersions.vbs invocation in ${f}"

    # Contract atoms: the four frozen override tokens, the INI key, at
    # least one pause, the extension-probe idiom, at least one
    # endlocal-coupled exit carrying a captured code.
    for tok in '/legacy' '/classic' '/modern' '/next'; do
        [ "$(printf '%s\n' "${code}" | grep -cF "${tok}")" -ge 1 ] \
            || fail_case "section e: override token ${tok} missing in ${f}"
    done
    [ "$(printf '%s\n' "${code}" | grep -cF 'ForceLegacyGUI')" -ge 1 ] \
        || fail_case "section e: INI key ForceLegacyGUI missing in ${f}"
    [ "$(printf '%s\n' "${code}" | grep -icE '^[[:space:]]*pause([[:space:]]|$)')" -ge 1 ] \
        || fail_case "section e: no pause in ${f}"
    [ "$(printf '%s\n' "${code}" | grep -icE '^verify other')" -ge 1 ] \
        || fail_case "section e: extension-probe idiom (verify other) missing in ${f}"
    [ "$(printf '%s\n' "${code}" | grep -icE 'endlocal.*exit /b')" -ge 1 ] \
        || fail_case "section e: no endlocal-coupled exit in ${f}"

    # Message contract: at least 4 bilingual [launcher] echo pairs; every
    # DE-led line must be immediately followed (in the [launcher] echo
    # sequence) by an EN-led line.
    de_led="$(printf '%s\n' "${code}" | grep -icE '^echo \[launcher\] (FEHLER|Starte|Vorgang)')"
    en_led="$(printf '%s\n' "${code}" | grep -icE '^echo \[launcher\] (ERROR|Launching|Operation)')"
    [ "${de_led}" -ge 4 ] \
        || fail_case "section e: fewer than 4 DE-led [launcher] echoes in ${f} (${de_led})"
    [ "${en_led}" -ge 4 ] \
        || fail_case "section e: fewer than 4 EN-led [launcher] echoes in ${f} (${en_led})"
    adj_bad="$(printf '%s\n' "${code}" | awk '
        /^echo \[launcher\] (FEHLER|Starte|Vorgang)/ { pending = 1; next }
        /^echo \[launcher\] / {
            if (pending) {
                if ($0 !~ /^echo \[launcher\] (ERROR|Launching|Operation)/) bad++
                pending = 0
            }
        }
        END { print bad + 0 }')"
    [ "${adj_bad}" -eq 0 ] \
        || fail_case "section e: ${adj_bad} DE-led [launcher] echo(s) without a following EN-led line in ${f}"

    # Bans, all exact zero counts over code lines: the delayed-expansion
    # mode string; the window-spawning shell verb as a command word
    # (statement-position anchored, not substring); any echo line
    # referencing the pv capture variable (registry-derived values are
    # never echoed).
    [ "$(printf '%s\n' "${code}" | grep -icF 'enableDelayedExpansion')" -eq 0 ] \
        || fail_case "section e: delayed expansion must not be enabled in ${f}"
    [ "$(printf '%s\n' "${code}" | grep -icE '^[[:space:]]*start([[:space:]]|$)')" -eq 0 ] \
        || fail_case "section e: window-spawning shell verb used as a command in ${f}"
    [ "$(printf '%s\n' "${code}" | grep -icE '^echo.*WEBVIEW2_PV')" -eq 0 ] \
        || fail_case "section e: registry-derived pv value echoed in ${f}"

    # Asymmetry (the single-prompt boundary made mechanical): the generator
    # carries zero elevation artifacts; the installer carries exactly one
    # of each (elevation probe, Shell.Application handoff, elevation verb).
    if [ "${f}" = "${GEN_CMD}" ]; then
        [ "$(printf '%s\n' "${code}" | grep -icE '(^|[[:space:]&|])net session([[:space:]]|$)')" -eq 0 ] \
            || fail_case "section e: generator must not probe elevation (net session) in ${f}"
        [ "$(printf '%s\n' "${code}" | grep -icF 'Shell.Application')" -eq 0 ] \
            || fail_case "section e: generator must not use Shell.Application in ${f}"
        [ "$(printf '%s\n' "${code}" | grep -icF 'runas')" -eq 0 ] \
            || fail_case "section e: generator must not carry the elevation verb in ${f}"
    else
        [ "$(printf '%s\n' "${code}" | grep -icE '(^|[[:space:]&|])net session([[:space:]]|$)')" -eq 1 ] \
            || fail_case "section e: installer must carry exactly one elevation probe in ${f}"
        [ "$(printf '%s\n' "${code}" | grep -icF 'Shell.Application')" -eq 1 ] \
            || fail_case "section e: installer must carry exactly one Shell.Application handoff in ${f}"
        [ "$(printf '%s\n' "${code}" | grep -icF 'runas')" -eq 1 ] \
            || fail_case "section e: installer must carry exactly one elevation verb in ${f}"
    fi
}

check_cmd_launcher_structure "${GEN_CMD}"
check_cmd_launcher_structure "${INS_CMD}"

# --- Section d: the battery can fail ---
echo "== Section d: can-fail controls =="

SANDBOX="$(mktemp -d)"
trap 'rm -rf "${SANDBOX}"' EXIT

if mirror_is_version_at_least "109.0.1518.78" "${MIN_LITERAL}"; then
    fail_case "section d: mirror accepted an older runtime — check function cannot fail"
else
    echo "  control ok: mirror rejects an older runtime"
fi

# Control 1: a mutated C# const must break the four-way floor sync.
sed 's/MinWebView2Version = "[0-9.]*"/MinWebView2Version = "156.0.9999.99"/' \
    "${GEN_CS}" > "${SANDBOX}/Program.cs"
mutated_min="$(extract_min_from_cs "${SANDBOX}/Program.cs")"
if [ -z "${mutated_min}" ]; then
    fail_case "section d: mutation sed no longer matches the const shape"
fi
if [ "$(count_lines '156.0.9999.99' "${SANDBOX}/Program.cs")" -lt 1 ]; then
    fail_case "section d: C# const mutation did not land in the sandbox copy"
fi
if floor_sync_ok "${SANDBOX}/Program.cs" "${INS_CS}" "${GEN_CMD}" "${INS_CMD}"; then
    fail_case "section d: sync gate did not detect the mutated C# const"
else
    echo "  control ok: sync gate rejects a drifted const (${mutated_min})"
fi

# Control 2: a mutated .cmd launcher floor must break the same gate.
sed 's/set "MIN_WEBVIEW2_VERSION=[0-9.]*"/set "MIN_WEBVIEW2_VERSION=156.0.8888.88"/' \
    "${GEN_CMD}" > "${SANDBOX}/UpdateGenerator.cmd"
if [ "$(count_lines '156.0.8888.88' "${SANDBOX}/UpdateGenerator.cmd")" -lt 1 ]; then
    fail_case "section d: launcher floor mutation did not land in the sandbox copy"
fi
if floor_sync_ok "${GEN_CS}" "${INS_CS}" "${SANDBOX}/UpdateGenerator.cmd" "${INS_CMD}"; then
    fail_case "section d: sync gate did not detect the mutated launcher floor"
else
    echo "  control ok: sync gate rejects a drifted launcher floor (156.0.8888.88)"
fi

# Control 3: a corrupted probe GUID must break the section e probe-parity
# gate. Only the FIRST occurrence is corrupted (GNU sed 0,/re/ address), so
# 2 originals must remain — the mutation is proven to have landed before the
# gate verdict is read.
sed '0,/F3017226-FE2A-4295-8BDF-00C3A9A7E4C5/s//F3017226-FE2A-4295-8BDF-00C3A9A7E4C0/' \
    "${GEN_CMD}" > "${SANDBOX}/GenCorrupt.cmd"
corrupt_fe2a="$(grep -ivE '^[[:space:]]*(rem([[:space:]]|$)|::)' "${SANDBOX}/GenCorrupt.cmd" | grep -cF 'F3017226-FE2A-4295-8BDF-00C3A9A7E4C5')"
[ "${corrupt_fe2a}" -eq 2 ] \
    || fail_case "section d: GUID corruption did not land in the sandbox copy (${corrupt_fe2a}/3 remaining)"
if probe_parity_ok "${SANDBOX}/GenCorrupt.cmd"; then
    fail_case "section d: probe-parity gate did not detect the corrupted GUID"
else
    echo "  control ok: probe-parity gate rejects a corrupted probe GUID"
fi

# --- Verdict ---
if [ "${FAILED_CASES}" -eq 0 ]; then
    echo "WEBVIEW2-GATE-BATTERY-PASS"
    exit 0
fi
echo "WEBVIEW2-GATE-BATTERY-FAIL (${FAILED_CASES} failed case(s))"
exit 1
