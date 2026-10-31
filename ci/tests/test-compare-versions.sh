#!/usr/bin/env bash
# Fixture test for the dual self-update comparators — run from repo root.
#
# Three sections:
#   a. bash comparator (all hosts): version_string_to_number is extracted
#      from the shipped task file and probed on synthetic versions —
#      build metadata must never leak into the numeric conversion.
#   b. VBS comparator (Windows only): the real CompareVersions.vbs runs
#      under cscript and its 0/1/2/3 errorlevel protocol is pinned in all
#      four directions, including the metadata-only-equal case.
#   c. marker field-1 reader parity: the comma pair "5.0.0+2026.11,release"
#      must read identically on the bash reader (IFS=$',\r\n') and the CMD
#      reader (for /f "tokens=1,2 delims=,") — field 1 = the full form.
#
# The battery never downloads anything and never writes outside its
# mktemp sandbox (except reading the shipped source files).
set -u
SANDBOX="$(mktemp -d)"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FAILED_CASES=0

fail_case () {
    echo "FAIL: $1"
    FAILED_CASES=$((FAILED_CASES + 1))
    return 0
}

# ---- section a: bash comparator (all hosts) --------------------------------
sed -n '/^function version_string_to_number/,/^}/p' \
        "${REPO_ROOT}/sh/common-tasks/50-check-wsusoffline-version.bash" \
    | tr -d '\r' > "${SANDBOX}/version_string_to_number.sh"
# shellcheck disable=SC1091  # sourced on purpose: the function under test
. "${SANDBOX}/version_string_to_number.sh"

[ "$(version_string_to_number "5.0.0+2026.11")" = "50000" ] \
    || fail_case "a — 5.0.0+2026.11 doit convertir en 50000"
[ "$(version_string_to_number "5.0.0")" = "50000" ] \
    || fail_case "a — 5.0.0 doit convertir en 50000"
[ "$(version_string_to_number "5.0.1+2026.12")" = "50001" ] \
    || fail_case "a — 5.0.1+2026.12 doit convertir en 50001"
[ "$(version_string_to_number "5.0.0+2026.12")" = "50000" ] \
    || fail_case "a — différence de metadata seule doit comparer ÉGALE (50000)"
[ "$(version_string_to_number "12.6.1")" = "120601" ] \
    || fail_case "a — les versions legacy doivent toujours convertir (120601)"

# Direction pins — both directions of SEM-03 ("pin test des deux directions").
# The pinned operands are the conversions computed above (50000 vs 50001):
# a metadata leak that corrupted either side breaks both directions at once.
CORE_EQ="$(version_string_to_number "5.0.0+2026.11")"
CORE_GT="$(version_string_to_number "5.0.1+2026.12")"
(("${CORE_EQ}" < "${CORE_GT}")) \
    || fail_case "a — direction inférieure attendue (50000 < 50001)"
(("${CORE_GT}" > "${CORE_EQ}")) \
    || fail_case "a — direction supérieure attendue (50001 > 50000)"

# ---- section b: VBS comparator (Windows host with cscript) -----------------
VBS_COMPARATOR="${REPO_ROOT}/client/cmd/CompareVersions.vbs"
if command -v cscript >/dev/null 2>&1
then
    vbs_section_failures=0
    run_vbs_case ()
    {
        local expected="$1"
        local v1="$2"
        local v2="$3"
        local label="$4"
        local actual="0"
        cscript //Nologo //B //E:vbs "${VBS_COMPARATOR}" "${v1}" "${v2}" >/dev/null 2>&1
        actual="$?"
        if [[ "${actual}" != "${expected}" ]]
        then
            echo "FAIL: b — cscript (${v1}, ${v2}) a rendu ${actual}, attendu ${expected} (${label})"
            vbs_section_failures=$((vbs_section_failures + 1))
        fi
        return 0
    }

    run_vbs_case 0 "5.0.0+2026.11" "5.0.0"     "metadata égale au cœur nu (0)"
    run_vbs_case 3 "5.0.0+2026.11" "5.0.1+2026.12" "inférieur (3)"
    run_vbs_case 2 "5.0.1+2026.12" "5.0.0+2026.11" "supérieur (2)"
    run_vbs_case 0 "5.0.0+2026.11" "5.0.0+2026.12" "metadata seule = ÉGALE (0)"
    run_vbs_case 3 "5.0.0"         "12.6.1"    "relation legacy documentée (3)"
    run_vbs_case 1 "garbage+2026.11" "5.0.0"   "erreur d'analyse (1)"
    FAILED_CASES=$((FAILED_CASES + vbs_section_failures))
else
    echo "SKIP (6 cas): cscript absent (ubuntu fixture-tests) — windows section runs on the wson-windows release job"
fi

# ---- section c: marker field-1 reader parity -------------------------------
printf '5.0.0+2026.11,release\n' > "${SANDBOX}/marker.txt"

# bash reader — the exact read shape of get_installed_version /
# get_available_version in 50-check-wsusoffline-version.bash
f1=""
f2=""
rest=""
IFS=$',\r\n' read -r f1 f2 rest < "${SANDBOX}/marker.txt"
[[ "${f1}" = "5.0.0+2026.11" ]] \
    || fail_case "c (bash) — le champ 1 doit porter la forme complète (lu: '${f1}')"
[[ "${f2}" = "release" ]] \
    || fail_case "c (bash) — le champ 2 doit être 'release' (lu: '${f2}')"

# CMD reader — the exact loop of cmd/CheckOUVersion.cmd, in a scratch .cmd
# with CRLF line endings (same windows gate as section b)
if command -v cscript >/dev/null 2>&1
then
    printf '@echo off\r\nfor /f "tokens=1,2 delims=," %%%%a in (marker.txt) do (\r\n  echo %%%%a^|%%%%b\r\n)\r\n' \
        > "${SANDBOX}/marker-probe.cmd"
    marker_output="$(cd "${SANDBOX}" && cmd //c '.\marker-probe.cmd' | tr -d '\r')"
    [[ "${marker_output}" = "5.0.0+2026.11|release" ]] \
        || fail_case "c (cmd) — sortie '${marker_output}', attendu '5.0.0+2026.11|release' (champ 1 tronqué à '+' ?)"
else
    echo "SKIP (1 cas): cscript absent (ubuntu fixture-tests) — windows section runs on the wson-windows release job"
fi

rm -rf "${SANDBOX}"
if [[ "${FAILED_CASES}" -gt 0 ]]
then
    echo "FAIL compare-versions: ${FAILED_CASES} cas en échec"
    exit "${FAILED_CASES}"
fi
echo "PASS compare-versions (bash + VBS + CMD: protocole 0/1/2/3 intact, metadata sans effet d'ordre, champ 1 = forme complète)"
exit 0
