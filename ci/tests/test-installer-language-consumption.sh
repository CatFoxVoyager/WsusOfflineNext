#!/usr/bin/env bash
# ci/tests/test-installer-language-consumption.sh - offline verification battery
# for Phase 39 (INST-01, INST-02): client installer medium language derivation,
# explicit glb-only fallback notice (console + log), IE11 w62-x64 %OS_LANG%
# resolution, ListUpdatesToInstall.cmd %OS_LANG% consumption, and
# ListMissingUpdateIds.vbs language-directory awareness.
#
# Runs offline in scratch sandboxes under .planning/tmp/39-01 (zero admin,
# zero system mutations, zero network, zero leaked temp directories).
# Documented host skip on non-Windows hosts (needs cmd.exe + cygpath + cscript).
set -u
export LC_ALL=C

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOUPDATE_REL="client/cmd/DoUpdate.cmd"
LIST_CMD_REL="client/cmd/ListUpdatesToInstall.cmd"
LIST_FILE_REL="client/cmd/ListUpdateFile.cmd"
VBS_REL="client/cmd/ListMissingUpdateIds.vbs"

FAILED_CASES=0
fail_case () {
    echo "FAIL: $1"
    FAILED_CASES=$((FAILED_CASES + 1))
    return 0
}

# Host gate: Windows-side bash (cmd.exe + cygpath + cscript)
if [ -z "${WINDIR:-}" ] || ! command -v cmd >/dev/null 2>&1 \
   || ! command -v cygpath >/dev/null 2>&1 || ! command -v cscript >/dev/null 2>&1; then
    echo "SKIP installer-language-consumption battery: needs a Windows-side bash host (cmd.exe + cygpath + cscript) - documented host skip"
    exit 0
fi

for rel in "${DOUPDATE_REL}" "${LIST_CMD_REL}" "${LIST_FILE_REL}" "${VBS_REL}"; do
    [ -f "${REPO}/${rel}" ] || { echo "FAIL: missing required file: ${rel}"; exit 1; }
done

SCRATCH_ROOT="${REPO}/.planning/tmp/39-01"
mkdir -p "${SCRATCH_ROOT}" || { echo "FAIL: cannot create ${SCRATCH_ROOT}"; exit 1; }
SANDBOXES=()
cleanup () {
    [ -n "${WOU_INST_KEEP:-}" ] && return 0
    for d in "${SANDBOXES[@]}"; do
        [ -n "${d}" ] && [ -d "${d}" ] && rm -rf "${d}"
    done
}
trap cleanup EXIT

make_sandbox () {
    SB_DIR="$(mktemp -d "${SCRATCH_ROOT}/sb.XXXXXX")"
    SANDBOXES+=("${SB_DIR}")
    mkdir -p "${SB_DIR}/client/cmd" "${SB_DIR}/client/static" "${SB_DIR}/client/exclude" \
             "${SB_DIR}/client/UpdateTable" "${SB_DIR}/client/dotnet" "${SB_DIR}/tmp" "${SB_DIR}/log"
    cp "${REPO}/${DOUPDATE_REL}" "${SB_DIR}/client/cmd/DoUpdate.cmd"
    cp "${REPO}/${LIST_CMD_REL}" "${SB_DIR}/client/cmd/ListUpdatesToInstall.cmd"
    cp "${REPO}/${LIST_FILE_REL}" "${SB_DIR}/client/cmd/ListUpdateFile.cmd"
    cp "${REPO}/${VBS_REL}" "${SB_DIR}/client/cmd/ListMissingUpdateIds.vbs"
}

run_medium_check () {
    # $1=sb_dir $2=OS_NAME $3=OS_ARCH $4=OS_LANG $5=OS_LANG_EXT(optional) $6=mode(optional, e.g. ie11)
    local sb="$1" os_name="$2" os_arch="$3" os_lang="$4" os_lang_ext="${5:-}" mode="${6:-}"
    local tmp_w log_w
    tmp_w="$(cygpath -w "${sb}/tmp")"
    log_w="$(cygpath -w "${sb}/log/wsusofflineupdate.log")"
    : > "${sb}/log/wsusofflineupdate.log"
    ( cd "${sb}/client/cmd" && \
        OS_NAME="${os_name}" OS_ARCH="${os_arch}" OS_LANG="${os_lang}" OS_LANG_EXT="${os_lang_ext}" \
        OFC_INSTALLED="" TEMP="${tmp_w}" TMP="${tmp_w}" UPDATE_LOGFILE="${log_w}" \
        MSYS2_ARG_CONV_EXCL='' cmd //c ".\\DoUpdate.cmd /testmediumlang ${mode}" > "${sb}/console.log" 2>&1 )
    RUN_RC=$?
}

NOTICE_TEXT="language-specific updates will not be offered - medium is glb-only"

# =====================================================================
# Case 1: FALLBACK-NOTICE-CHS (INST-01) — chs system + glb-only medium
# =====================================================================
FAILS_BEFORE="${FAILED_CASES}"
echo "--- case FALLBACK-NOTICE-CHS: non-English system on glb-only medium emits console + log notice"
make_sandbox
mkdir -p "${SB_DIR}/client/w100-x64/glb"
run_medium_check "${SB_DIR}" w100 x64 chs zh-cn
[ "${RUN_RC}" -eq 0 ] || fail_case "FALLBACK-NOTICE-CHS: rc=${RUN_RC}, want 0"
grep -qF "Medium supports Microsoft Windows (w100 x64 glb)" "${SB_DIR}/console.log" \
    || fail_case "FALLBACK-NOTICE-CHS: standard glb support line missing from console"
grep -qF "${NOTICE_TEXT}" "${SB_DIR}/console.log" \
    || fail_case "FALLBACK-NOTICE-CHS: fallback notice missing from console"
grep -qF "${NOTICE_TEXT}" "${SB_DIR}/log/wsusofflineupdate.log" \
    || fail_case "FALLBACK-NOTICE-CHS: fallback notice missing from wsusofflineupdate.log"
grep -qF "chs" "${SB_DIR}/console.log" \
    || fail_case "FALLBACK-NOTICE-CHS: system language token 'chs' not named in console notice"
if [ "${FAILED_CASES}" -eq "${FAILS_BEFORE}" ]; then
    echo "  ok: FALLBACK-NOTICE-CHS emitted explicit notice in console and log"
fi

# =====================================================================
# Case 2: ENU-SILENT-SC4 — English system + glb-only medium (zero notice)
# =====================================================================
FAILS_BEFORE="${FAILED_CASES}"
echo "--- case ENU-SILENT-SC4: English system on glb-only medium stays silent (zero fallback notice)"
make_sandbox
mkdir -p "${SB_DIR}/client/w100-x64/glb"
run_medium_check "${SB_DIR}" w100 x64 enu en-us
[ "${RUN_RC}" -eq 0 ] || fail_case "ENU-SILENT-SC4: rc=${RUN_RC}, want 0"
grep -qF "Medium supports Microsoft Windows (w100 x64 glb)" "${SB_DIR}/console.log" \
    || fail_case "ENU-SILENT-SC4: standard glb support line missing"
! grep -qF "${NOTICE_TEXT}" "${SB_DIR}/console.log" \
    || fail_case "ENU-SILENT-SC4: spurious fallback notice emitted on enu console"
! grep -qF "${NOTICE_TEXT}" "${SB_DIR}/log/wsusofflineupdate.log" \
    || fail_case "ENU-SILENT-SC4: spurious fallback notice emitted on enu log"
if [ "${FAILED_CASES}" -eq "${FAILS_BEFORE}" ]; then
    echo "  ok: ENU-SILENT-SC4 produced zero fallback notice"
fi

# =====================================================================
# Case 3: DOTNET-NLP-CARRIED (Phase 38 D-02) — w100-x64 glb + dotnet chs NLP
# =====================================================================
FAILS_BEFORE="${FAILED_CASES}"
echo "--- case DOTNET-NLP-CARRIED: w100-x64 glb + dotnet chs NLP emits Info and no false glb-only notice"
make_sandbox
mkdir -p "${SB_DIR}/client/w100-x64/glb"
printf 'stub\n' > "${SB_DIR}/client/dotnet/ndp481-x86-x64-allos-chs.exe"
run_medium_check "${SB_DIR}" w100 x64 chs zh-cn
[ "${RUN_RC}" -eq 0 ] || fail_case "DOTNET-NLP-CARRIED: rc=${RUN_RC}, want 0"
! grep -qF "${NOTICE_TEXT}" "${SB_DIR}/console.log" \
    || fail_case "DOTNET-NLP-CARRIED: false glb-only notice emitted despite dotnet chs NLP present"
! grep -qF "${NOTICE_TEXT}" "${SB_DIR}/log/wsusofflineupdate.log" \
    || fail_case "DOTNET-NLP-CARRIED: false glb-only notice in log despite dotnet chs NLP present"
grep -qF "Medium carries chs language packs (.NET)" "${SB_DIR}/console.log" \
    || fail_case "DOTNET-NLP-CARRIED: expected dotnet language-pack Info line missing from console"
grep -qF "Medium carries chs language packs (.NET)" "${SB_DIR}/log/wsusofflineupdate.log" \
    || fail_case "DOTNET-NLP-CARRIED: expected dotnet language-pack Info line missing from log"
if [ "${FAILED_CASES}" -eq "${FAILS_BEFORE}" ]; then
    echo "  ok: DOTNET-NLP-CARRIED recognized chs .NET NLP without false glb-only notice"
fi

# =====================================================================
# Case 4: OS-LANG-DIR-CARRIED (INST-02) — w100-x64/chs dir present
# =====================================================================
FAILS_BEFORE="${FAILED_CASES}"
echo "--- case OS-LANG-DIR-CARRIED: medium with w100-x64/chs reports native language support"
make_sandbox
mkdir -p "${SB_DIR}/client/w100-x64/glb" "${SB_DIR}/client/w100-x64/chs"
run_medium_check "${SB_DIR}" w100 x64 chs zh-cn
[ "${RUN_RC}" -eq 0 ] || fail_case "OS-LANG-DIR-CARRIED: rc=${RUN_RC}, want 0"
grep -qF "Medium supports Microsoft Windows (w100 x64 chs)" "${SB_DIR}/console.log" \
    || fail_case "OS-LANG-DIR-CARRIED: expected native chs support line missing"
! grep -qF "${NOTICE_TEXT}" "${SB_DIR}/console.log" \
    || fail_case "OS-LANG-DIR-CARRIED: unexpected fallback notice when w100-x64/chs exists"
if [ "${FAILED_CASES}" -eq "${FAILS_BEFORE}" ]; then
    echo "  ok: OS-LANG-DIR-CARRIED reported native chs support"
fi

# =====================================================================
# Case 5: ARBITRARY-LANG-SC3 — dynamic derivation for fra / deu / jpn
# =====================================================================
FAILS_BEFORE="${FAILED_CASES}"
echo "--- case ARBITRARY-LANG-SC3: language availability derived purely from medium content"
make_sandbox
mkdir -p "${SB_DIR}/client/w100-x64/glb" "${SB_DIR}/client/w100-x64/fra"
printf 'stub\n' > "${SB_DIR}/client/dotnet/ndp481-x86-x64-allos-deu.exe"
run_medium_check "${SB_DIR}" w100 x64 fra fr-fr
grep -qF "Medium supports Microsoft Windows (w100 x64 fra)" "${SB_DIR}/console.log" \
    || fail_case "ARBITRARY-LANG-SC3: fra dir not recognized dynamically"
run_medium_check "${SB_DIR}" w100 x64 deu de-de
grep -qF "Medium carries deu language packs (.NET)" "${SB_DIR}/console.log" \
    || fail_case "ARBITRARY-LANG-SC3: deu dotnet NLP not recognized dynamically"
run_medium_check "${SB_DIR}" w100 x64 jpn ja-jp
grep -qF "${NOTICE_TEXT}" "${SB_DIR}/console.log" \
    || fail_case "ARBITRARY-LANG-SC3: missing jpn did not emit glb-only notice"
if [ "${FAILED_CASES}" -eq "${FAILS_BEFORE}" ]; then
    echo "  ok: ARBITRARY-LANG-SC3 dynamically handled fra (dir), deu (dotnet), jpn (fallback)"
fi

# =====================================================================
# Case 6: X86-PARITY — x86 target fallback notice + native lang dir
# =====================================================================
FAILS_BEFORE="${FAILED_CASES}"
echo "--- case X86-PARITY: x86 target glb-only emits notice; x86 lang dir stays clean"
make_sandbox
mkdir -p "${SB_DIR}/client/w100/glb"
run_medium_check "${SB_DIR}" w100 x86 chs zh-cn
grep -qF "${NOTICE_TEXT}" "${SB_DIR}/console.log" \
    || fail_case "X86-PARITY: x86 chs on glb-only missed fallback notice"
mkdir -p "${SB_DIR}/client/w100/chs"
run_medium_check "${SB_DIR}" w100 x86 chs zh-cn
grep -qF "Medium supports Microsoft Windows (w100 x86 chs)" "${SB_DIR}/console.log" \
    || fail_case "X86-PARITY: x86 chs dir not recognized"
! grep -qF "${NOTICE_TEXT}" "${SB_DIR}/console.log" \
    || fail_case "X86-PARITY: unexpected fallback notice when w100/chs exists"
if [ "${FAILED_CASES}" -eq "${FAILS_BEFORE}" ]; then
    echo "  ok: X86-PARITY passed both glb-only and native lang dir"
fi

# =====================================================================
# Case 7: IE11-W62-LANG-DIR (D-02) — :IEw62 resolves %OS_LANG% dir first, glb fallback
# =====================================================================
FAILS_BEFORE="${FAILED_CASES}"
echo "--- case IE11-W62-LANG-DIR: :IEw62 resolves w62-x64/<lang> before glb fallback"
make_sandbox
mkdir -p "${SB_DIR}/client/w62-x64/glb" "${SB_DIR}/client/w62-x64/chs"
printf 'lp-chs\n' > "${SB_DIR}/client/w62-x64/chs/ie11-windows6.2-languagepack-x64-zh-cn_abc.msu"
run_medium_check "${SB_DIR}" w62 x64 chs zh-cn ie11
grep -qF 'IE_LANG_DIR=..\w62-x64\chs' "${SB_DIR}/console.log" \
    || fail_case "IE11-W62-LANG-DIR: did not resolve ..\\w62-x64\\chs when chs LP exists"
rm -f "${SB_DIR}/client/w62-x64/chs/"*.msu
printf 'lp-glb\n' > "${SB_DIR}/client/w62-x64/glb/ie11-windows6.2-languagepack-x64-zh-cn_def.msu"
run_medium_check "${SB_DIR}" w62 x64 chs zh-cn ie11
grep -qF 'IE_LANG_DIR=..\w62-x64\glb' "${SB_DIR}/console.log" \
    || fail_case "IE11-W62-LANG-DIR: did not fall back to ..\\w62-x64\\glb when absent from chs"
if [ "${FAILED_CASES}" -eq "${FAILS_BEFORE}" ]; then
    echo "  ok: IE11-W62-LANG-DIR preferred w62-x64\\chs and fell back to w62-x64\\glb"
fi

# =====================================================================
# Case 8: LIST-UPDATES-CONSUMPTION (INST-02) — real ListUpdatesToInstall.cmd
# =====================================================================
FAILS_BEFORE="${FAILED_CASES}"
echo "--- case LIST-UPDATES-CONSUMPTION: ListUpdatesToInstall.cmd resolves w100-x64/chs with zero warnings"
make_sandbox
mkdir -p "${SB_DIR}/client/w100-x64/glb" "${SB_DIR}/client/w100-x64/chs"
printf 'cab-chs\n' > "${SB_DIR}/client/w100-x64/chs/windows10.0-kb9999999-x64-chs.cab"
printf '11111111-2222-3333-4444-555555555555,windows10.0-kb9999999-x64-chs.cab\r\n' > "${SB_DIR}/client/UpdateTable/UpdateTable-w100-chs.csv"
printf '9999999,11111111-2222-3333-4444-555555555555\r\n' > "${SB_DIR}/tmp/MissingUpdateIds.txt"
: > "${SB_DIR}/log/wsusofflineupdate.log"
TMP_W="$(cygpath -w "${SB_DIR}/tmp")"
LOG_W="$(cygpath -w "${SB_DIR}/log/wsusofflineupdate.log")"
( cd "${SB_DIR}/client/cmd" && \
    OS_NAME=w100 OS_ARCH=x64 OS_LANG=chs OS_VER_BUILD_INTERNAL=19045 IE_VER_MAJOR=11 IE_VER_MINOR=0 \
    O2K16_VER_MAJOR="" O2K16_IS_C2R="" TEMP="${TMP_W}" TMP="${TMP_W}" UPDATE_LOGFILE="${LOG_W}" \
    MSYS2_ARG_CONV_EXCL='' cmd //c ".\\ListUpdatesToInstall.cmd /excludestatics /ignoreblacklist" > "${SB_DIR}/list.log" 2>&1 )
LIST_RC=$?
[ "${LIST_RC}" -eq 0 ] || { fail_case "LIST-UPDATES-CONSUMPTION: ListUpdatesToInstall.cmd rc=${LIST_RC}"; sed 's/^/    /' "${SB_DIR}/list.log"; }
grep -qiF "windows10.0-kb9999999-x64-chs.cab" "${SB_DIR}/tmp/UpdatesToInstall.txt" 2>/dev/null \
    || fail_case "LIST-UPDATES-CONSUMPTION: chs cab missing from UpdatesToInstall.txt"
! grep -qiF "Warning: Update" "${SB_DIR}/list.log" \
    || fail_case "LIST-UPDATES-CONSUMPTION: spurious 'Warning: Update ... not found' in console"
! grep -qiF "Warning: Update" "${SB_DIR}/log/wsusofflineupdate.log" \
    || fail_case "LIST-UPDATES-CONSUMPTION: spurious 'Warning: Update ... not found' in log"
if [ "${FAILED_CASES}" -eq "${FAILS_BEFORE}" ]; then
    echo "  ok: LIST-UPDATES-CONSUMPTION resolved chs update with zero warnings"
fi

# =====================================================================
# Case 9: VBS-INCOMPLETE-LANG (D-03) — file-truth harness over real ListMissingUpdateIds.vbs
# =====================================================================
FAILS_BEFORE="${FAILED_CASES}"
echo "--- case VBS-INCOMPLETE-LANG: ListMissingUpdateIds.vbs recognizes <os>[-x64]/<lang> updates"
make_sandbox
mkdir -p "${SB_DIR}/client/w100-x64/glb" "${SB_DIR}/client/w100-x64/chs"
printf 'cab-chs\n' > "${SB_DIR}/client/w100-x64/chs/windows10.0-kb9999999-x64_chs.cab"
printf 'aaaa1111-0000-0000-0000-000000000001,windows10.0-kb9999999-x64_chs.cab\r\n' > "${SB_DIR}/client/UpdateTable/UpdateTable-w100-chs.csv"
printf 'aaaa1111-0000-0000-0000-000000000002,windows10.0-kb8888888-x64_missing.cab\r\n' > "${SB_DIR}/client/UpdateTable/UpdateTable-w100-glb.csv"

# Extract LoadUpdateTableFile + LoadUpdateTable + UpdateIsIncomplete verbatim from real ListMissingUpdateIds.vbs
run_vbs_probe () { # $1=vbs_source_file $2=sb_dir $3=lang_arg
    local src="$1" sb="$2" lang_arg="$3"
    local harness="${sb}/client/cmd/probe_incomplete.vbs"
    {
        echo "Option Explicit"
        echo "Dim objFSO, objTableDict, strOSName, strOSLang, strMissingFile"
        echo "Set objFSO = CreateObject(\"Scripting.FileSystemObject\")"
        echo "strOSName = \"w100\""
        echo "strOSLang = \"${lang_arg}\""
        awk '/^Private Sub LoadUpdateTableFile/,/^End Function/' "${src}"
        echo "If UpdateIsIncomplete(\"aaaa1111-0000-0000-0000-000000000001\", strMissingFile) Then WScript.Echo \"PRESENT=1\" Else WScript.Echo \"PRESENT=0\""
        echo "If UpdateIsIncomplete(\"aaaa1111-0000-0000-0000-000000000002\", strMissingFile) Then WScript.Echo \"ABSENT=1\" Else WScript.Echo \"ABSENT=0\""
    } > "${harness}"
    ( cd "${sb}/client/cmd" && MSYS2_ARG_CONV_EXCL='' cscript //Nologo //E:vbs probe_incomplete.vbs )
}

VBS_OUT="$(run_vbs_probe "${SB_DIR}/client/cmd/ListMissingUpdateIds.vbs" "${SB_DIR}" "chs" 2>&1)"
printf '%s\n' "${VBS_OUT}" | grep -qF "PRESENT=0" \
    || fail_case "VBS-INCOMPLETE-LANG: chs file on medium was marked incomplete (out=${VBS_OUT})"
printf '%s\n' "${VBS_OUT}" | grep -qF "ABSENT=1" \
    || fail_case "VBS-INCOMPLETE-LANG: missing file was not marked incomplete (out=${VBS_OUT})"
grep -qF 'ListMissingUpdateIds.vbs "%LIST_MODE_IDS%" %OS_NAME% %OS_LANG%' "${REPO}/${DOUPDATE_REL}" \
    || fail_case "VBS-INCOMPLETE-LANG: DoUpdate.cmd does not pass %OS_LANG% to ListMissingUpdateIds.vbs"
if [ "${FAILED_CASES}" -eq "${FAILS_BEFORE}" ]; then
    echo "  ok: VBS-INCOMPLETE-LANG passed (PRESENT=0, ABSENT=1, DoUpdate call pinned)"
fi

# =====================================================================
# Case 10: ASCII-CRLF-PIN + CAN-FAIL CONTROLS
# =====================================================================
FAILS_BEFORE="${FAILED_CASES}"
echo "--- case ASCII-CRLF-PIN + CAN-FAIL controls"
NON_ASCII="$(LC_ALL=C tr -d '\000-\177' < "${REPO}/${DOUPDATE_REL}" | wc -c)"
[ "${NON_ASCII}" -eq 0 ] || fail_case "ASCII-CRLF-PIN: DoUpdate.cmd contains ${NON_ASCII} non-ASCII byte(s)"
CR_CNT="$(tr -dc '\r' < "${REPO}/${DOUPDATE_REL}" | wc -c)"
LF_CNT="$(tr -dc '\n' < "${REPO}/${DOUPDATE_REL}" | wc -c)"
[ "${CR_CNT}" -eq "${LF_CNT}" ] || fail_case "ASCII-CRLF-PIN: DoUpdate.cmd CRLF broken (CR=${CR_CNT} LF=${LF_CNT})"

# Control 1: strip fallback notice from scratch DoUpdate.cmd -> FALLBACK check must bite
make_sandbox
mkdir -p "${SB_DIR}/client/w100-x64/glb"
sed 's/language-specific updates will not be offered - medium is glb-only/mutated-out/' "${SB_DIR}/client/cmd/DoUpdate.cmd" \
    | sed -e 's/\r$//' -e 's/$/\r/' > "${SB_DIR}/client/cmd/DoUpdate.cmd.new" \
    && mv "${SB_DIR}/client/cmd/DoUpdate.cmd.new" "${SB_DIR}/client/cmd/DoUpdate.cmd"
run_medium_check "${SB_DIR}" w100 x64 chs zh-cn
if grep -qF "${NOTICE_TEXT}" "${SB_DIR}/console.log"; then
    fail_case "control 1 does not bite: notice still found after mutation"
else
    echo "  control ok: fallback notice check bites on mutated DoUpdate.cmd"
fi

# Control 2: revert IE_LANG_DIR to glb-only -> IE11 check must bite
make_sandbox
mkdir -p "${SB_DIR}/client/w62-x64/glb" "${SB_DIR}/client/w62-x64/chs"
printf 'lp-chs\n' > "${SB_DIR}/client/w62-x64/chs/ie11-windows6.2-languagepack-x64-zh-cn_abc.msu"
sed 's/set IE_LANG_DIR=..\\%OS_NAME%-%OS_ARCH%\\%OS_LANG%/set IE_LANG_DIR=..\\%OS_NAME%-%OS_ARCH%\\glb/' "${SB_DIR}/client/cmd/DoUpdate.cmd" \
    | sed -e 's/\r$//' -e 's/$/\r/' > "${SB_DIR}/client/cmd/DoUpdate.cmd.new" \
    && mv "${SB_DIR}/client/cmd/DoUpdate.cmd.new" "${SB_DIR}/client/cmd/DoUpdate.cmd"
run_medium_check "${SB_DIR}" w62 x64 chs zh-cn ie11
if grep -qF 'IE_LANG_DIR=..\w62-x64\chs' "${SB_DIR}/console.log"; then
    fail_case "control 2 does not bite: IE_LANG_DIR still resolved chs after glb-only mutation"
else
    echo "  control ok: IE11 language-pack check bites on glb-only DoUpdate.cmd"
fi

# Control 3: strip strOSLang file check from scratch ListMissingUpdateIds.vbs -> VBS check must bite
make_sandbox
mkdir -p "${SB_DIR}/client/w100-x64/glb" "${SB_DIR}/client/w100-x64/chs"
printf 'cab-chs\n' > "${SB_DIR}/client/w100-x64/chs/windows10.0-kb9999999-x64_chs.cab"
printf 'aaaa1111-0000-0000-0000-000000000001,windows10.0-kb9999999-x64_chs.cab\r\n' > "${SB_DIR}/client/UpdateTable/UpdateTable-w100-chs.csv"
sed 's/objFSO\.FileExists(strArchDir & strOSLang/False And objFSO.FileExists(strArchDir \& strOSLang/' "${SB_DIR}/client/cmd/ListMissingUpdateIds.vbs" \
    > "${SB_DIR}/client/cmd/ListMissingUpdateIds.vbs.new" \
    && mv "${SB_DIR}/client/cmd/ListMissingUpdateIds.vbs.new" "${SB_DIR}/client/cmd/ListMissingUpdateIds.vbs"
VBS_BITE="$(run_vbs_probe "${SB_DIR}/client/cmd/ListMissingUpdateIds.vbs" "${SB_DIR}" "chs" 2>&1)"
if printf '%s\n' "${VBS_BITE}" | grep -qF "PRESENT=1"; then
    echo "  control ok: VBS language-dir check bites when strOSLang check is disabled"
else
    fail_case "control 3 does not bite: VBS probe returned '${VBS_BITE}'"
fi

if [ "${FAILED_CASES}" -eq 0 ]; then
    echo "INSTALLER-LANG-PASS"
    exit 0
fi
echo "INSTALLER-LANG-FAIL (${FAILED_CASES} failed case(s))"
exit 1
