#!/usr/bin/env bash
# Battery for the in-host WebView2 startup gate (issue #21 round 3) — run
# from repo root.
#
# Portable by construction: no WebView2 runtime, no dotnet, no Windows.
# The comparator semantics are verified against a bash mirror carrying the
# same contract as the C# WebView2Compat.IsVersionAtLeast helper (strip any
# '+'/'-' suffix, then 4-part numeric compare with missing or non-numeric
# parts counting as 0). The REAL compiled helper is exercised separately on
# a Windows host by the round-3 scratch probe; see the quick 261103-e8d
# SUMMARY for which tier each proof reaches.
#
# Sections:
#   a. comparator semantics: absent -> gate, older -> gate, equal -> pass,
#      newer -> pass, '+'/'-' suffix -> pass, boundary one-below -> gate,
#      unparsable / partial / leading-zero forms
#   b. sync: the C# const in BOTH hosts equals the launcher literal in
#      BOTH .au3 files, each appearing exactly once, and the raw literal
#      appears exactly once per file (comments and dialogs must not recopy)
#   c. structure: each host registers ThreadException + the AppDomain net +
#      SetUnhandledExceptionMode, probes GetAvailableBrowserVersionString
#      exactly once, and wraps the whole SendToWeb body in try/catch
#   d. the battery can fail: the sync gate goes red on a mutated sandbox
#      copy, and the mirror control rejects an older runtime
set -u

GEN_CS="src-modern/generator/host/Program.cs"
INS_CS="src-modern/installer/host/Program.cs"
GEN_AU3="UpdateGeneratorLauncher.au3"
INS_AU3="client/UpdateInstallerLauncher.au3"

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
echo "== Section b: C# const == launcher literal, exactly once per file =="

extract_min_from_cs () {
    grep -oE 'MinWebView2Version = "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' "$1" \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'
}

extract_min_from_au3 () {
    grep -oE 'Global Const \$MIN_WEBVIEW2_VERSION = "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' "$1" \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'
}

count_lines () {
    # $1 = fixed-string needle, $2 = file
    grep -cF "$1" "$2"
}

GEN_MIN="$(extract_min_from_cs "${GEN_CS}")"
INS_MIN="$(extract_min_from_cs "${INS_CS}")"
GEN_AU3_MIN="$(extract_min_from_au3 "${GEN_AU3}")"
INS_AU3_MIN="$(extract_min_from_au3 "${INS_AU3}")"

[ -n "${GEN_MIN}" ]     || fail_case "section b: no MinWebView2Version const in ${GEN_CS}"
[ -n "${INS_MIN}" ]     || fail_case "section b: no MinWebView2Version const in ${INS_CS}"
[ -n "${GEN_AU3_MIN}" ] || fail_case "section b: no \$MIN_WEBVIEW2_VERSION in ${GEN_AU3}"
[ -n "${INS_AU3_MIN}" ] || fail_case "section b: no \$MIN_WEBVIEW2_VERSION in ${INS_AU3}"

if [ -n "${GEN_MIN}" ] && [ -n "${INS_MIN}" ] && [ -n "${GEN_AU3_MIN}" ] && [ -n "${INS_AU3_MIN}" ]
then
    [ "${GEN_MIN}" = "${GEN_AU3_MIN}" ] \
        || fail_case "section b: generator const ${GEN_MIN} != launcher ${GEN_AU3_MIN}"
    [ "${INS_MIN}" = "${INS_AU3_MIN}" ] \
        || fail_case "section b: installer const ${INS_MIN} != launcher ${INS_AU3_MIN}"
    [ "${GEN_MIN}" = "${INS_MIN}" ] \
        || fail_case "section b: hosts diverge (${GEN_MIN} vs ${INS_MIN})"
fi

# The declared minimum in the battery must be what the hosts declare too.
[ "${GEN_MIN:-x}" = "${MIN_LITERAL}" ] \
    || fail_case "section b: generator const != battery spec literal"

# Exactly one declaration and one raw literal per file: a second raw
# occurrence means a comment or dialog recopied the value and would drift
# silently on the next SDK bump.
for f in "${GEN_CS}" "${INS_CS}"; do
    [ "$(count_lines 'MinWebView2Version = "' "${f}")" -eq 1 ] \
        || fail_case "section b: expected exactly one const declaration in ${f}"
    [ "$(count_lines "${GEN_MIN:-156.0.4314.35}" "${f}")" -eq 1 ] \
        || fail_case "section b: raw literal must appear exactly once in ${f}"
done
for f in "${GEN_AU3}" "${INS_AU3}"; do
    [ "$(count_lines 'Global Const $MIN_WEBVIEW2_VERSION = ' "${f}")" -eq 1 ] \
        || fail_case "section b: expected exactly one declaration in ${f}"
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
    [ "$(grep -c 'GetAvailableBrowserVersionString' "${f}")" -eq 1 ] \
        || fail_case "section c: expected exactly one runtime probe in ${f}"
    [ "$(grep -c 'HandleFatal' "${f}")" -ge 2 ] \
        || fail_case "section c: HandleFatal missing or unreferenced in ${f}"

    body_head="$(grep -A6 'private void SendToWeb' "${f}")"
    case "${body_head}" in
        *try*) ;;
        *) fail_case "section c: SendToWeb body is not wrapped in try in ${f}" ;;
    esac
    [ "$(sed -n '/private void SendToWeb/,/^        }$/p' "${f}" | grep -c 'catch')" -ge 2 ] \
        || fail_case "section c: SendToWeb needs outer + inner catch in ${f}"
done

# --- Section d: the battery can fail ---
echo "== Section d: can-fail controls =="

SANDBOX="$(mktemp -d)"
trap 'rm -rf "${SANDBOX}"' EXIT

if mirror_is_version_at_least "109.0.1518.78" "${MIN_LITERAL}"; then
    fail_case "section d: mirror accepted an older runtime — check function cannot fail"
else
    echo "  control ok: mirror rejects an older runtime"
fi

sed 's/MinWebView2Version = "[0-9.]*"/MinWebView2Version = "156.0.9999.99"/' \
    "${GEN_CS}" > "${SANDBOX}/Program.cs"
mutated_min="$(extract_min_from_cs "${SANDBOX}/Program.cs")"
if [ "${mutated_min}" = "${GEN_AU3_MIN}" ]; then
    fail_case "section d: sync gate did not detect the mutated const"
else
    echo "  control ok: sync gate rejects a drifted const (${mutated_min})"
fi
if [ -z "${mutated_min}" ]; then
    fail_case "section d: mutation sed no longer matches the const shape"
fi

# --- Verdict ---
if [ "${FAILED_CASES}" -eq 0 ]; then
    echo "WEBVIEW2-GATE-BATTERY-PASS"
    exit 0
fi
echo "WEBVIEW2-GATE-BATTERY-FAIL (${FAILED_CASES} failed case(s))"
exit 1
