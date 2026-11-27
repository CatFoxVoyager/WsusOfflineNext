#!/usr/bin/env bash
# ci/tests/test-e2e-language-parity.sh - Phase 40 cross-pipeline parity &
# end-to-end #51 validation battery (PAR-01 + E2E SEL/DL/INST).
#
# Section A (cross-platform: runs on Linux CI ubuntu-latest AND Windows):
#   1. Parity doc presence & anchor verification (sh/comparison-linux-windows/language-selection-parity.md)
#   2. 24-token vocabulary set equality across bash dialog (10-show-selection-dialogs-with-dialog.bash),
#      bash select menu (updates-and-languages.bash), CMD labels (:Lang_*), and CreateISOImage.cmd:55
#   3. Real bash downloader function execution:
#      - calculate_static_downloads_dotnet (40-included-downloads.bash): chs emits all 3 chs NLPs,
#        enu default emits 0 chs NLPs
#      - calculate_static_updates w62 branch (60-main-updates.bash): chs emits ie11-w62-x64-chs LP,
#        enu default emits 0 chs IE11 LPs
#   4. bash -n syntax check over all sh/**/*.bash scripts
#   5. Can-fail control A1 (mutated bash language_keys bites vocab parity)
#
# Section B (Windows Git Bash only; documented skip on non-Windows hosts):
#   Real Generator -> Medium -> Installer (#51) end-to-end handoffs using
#   real cmd/DownloadUpdates.cmd (with offline recording wget stub, default
#   cleanup enabled - NO /nocleanup) handed directly to real client/cmd/DoUpdate.cmd:
#   1. E2E-51-CMD-CHS: CMD w100-x64 glb + chs -> DoUpdate.cmd (chs) reports chs .NET NLPs carried,
#      zero glb-only fallback warning
#   2. E2E-51-CMD-GLB-FALLBACK: CMD w100-x64 glb only -> DoUpdate.cmd (chs) emits console + log
#      glb-only notice; DoUpdate.cmd (enu) stays silent (SC4)
#   3. E2E-51-W62-BOTH-LAYOUTS: CMD w62-x64 chs (w62-x64/chs/) AND bash w62-x64 chs (w62-x64/glb/)
#      both resolve cleanly via DoUpdate.cmd :ResolveIEw62LangPack
#   4. E2E-51-BASH-TO-INSTALLER: real bash calculate_static_downloads_dotnet (chs) URLs materialized
#      into client/dotnet/ -> DoUpdate.cmd (chs) reports chs .NET NLPs carried, zero fallback warning
#   5. Can-fail control B1: removing chs NLPs from generated medium flips DoUpdate.cmd to glb-only notice
set -u
export LC_ALL=C

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PARITY_DOC="${REPO}/sh/comparison-linux-windows/language-selection-parity.md"
BASH_DIALOG="${REPO}/sh/update-generator-tasks/10-show-selection-dialogs-with-dialog.bash"
BASH_MENU="${REPO}/sh/libraries/updates-and-languages.bash"
BASH_DOTNET="${REPO}/sh/download-updates-tasks/40-included-downloads.bash"
BASH_MAIN="${REPO}/sh/download-updates-tasks/60-main-updates.bash"
BASH_DOS="${REPO}/sh/libraries/dos-files.bash"
CMD_DL="${REPO}/cmd/DownloadUpdates.cmd"
CMD_ISO="${REPO}/cmd/CreateISOImage.cmd"
CMD_DOUPDATE="${REPO}/client/cmd/DoUpdate.cmd"

FAILED_CASES=0
fail_case () {
    echo "FAIL: $1"
    FAILED_CASES=$((FAILED_CASES + 1))
    return 0
}

for req in "${PARITY_DOC}" "${BASH_DIALOG}" "${BASH_MENU}" "${BASH_DOTNET}" "${BASH_MAIN}" "${BASH_DOS}" "${CMD_DL}" "${CMD_ISO}" "${CMD_DOUPDATE}"; do
    [ -f "${req}" ] || { echo "FAIL: missing required file: ${req}"; exit 1; }
done

SCRATCH_ROOT="${REPO}/.planning/tmp/40-01"
mkdir -p "${SCRATCH_ROOT}" || { echo "FAIL: cannot create ${SCRATCH_ROOT}"; exit 1; }
RUN_ROOT="$(mktemp -d "${SCRATCH_ROOT}/run.XXXXXX")" || { echo "FAIL: cannot create run dir under ${SCRATCH_ROOT}"; exit 1; }
cleanup () {
    [ -n "${WOU_E2E_KEEP:-}" ] && return 0
    [ -n "${RUN_ROOT:-}" ] && [ -d "${RUN_ROOT}" ] && rm -rf "${RUN_ROOT}"
}
trap cleanup EXIT

make_tmp () {
    mktemp -d "${RUN_ROOT}/sb.XXXXXX"
}

# =====================================================================
# SECTION A: Cross-platform bash/CMD parity (runs on Linux CI & Windows)
# =====================================================================
echo "=== Section A: Cross-platform bash/CMD parity ==="

# A1: Parity doc presence & anchor coverage
FAILS_BEFORE="${FAILED_CASES}"
for anchor in "10-show-selection-dialogs-with-dialog.bash" "40-included-downloads.bash" "60-main-updates.bash" "DownloadUpdates.cmd" "DoUpdate.cmd" "ResolveIEw62LangPack"; do
    grep -qF "${anchor}" "${PARITY_DOC}" \
        || fail_case "A1: parity doc missing anchor '${anchor}'"
done
if [ "${FAILED_CASES}" -eq "${FAILS_BEFORE}" ]; then
    echo "  ok: A1 parity documentation carries all pipeline anchors"
fi

# A2: 24-token non-glb vocabulary set equality across bash dialog, bash menu, CMD :Lang_*, CreateISOImage.cmd
FAILS_BEFORE="${FAILED_CASES}"
extract_bash_dialog_langs () {
    awk '/^language_keys=\(/,/^\)/ { if ($0 !~ /^language_keys=/ && $0 !~ /^\)/) print }' "$1" \
        | tr -d '\r' | tr ' \t' '\n' | grep -E '^[a-z]{3}$' | sort -u
}
extract_bash_menu_langs () {
    awk '/^languages_menu=\(/,/^\)/ { if ($0 ~ /"/) print }' "$1" \
        | tr -d '\r' | sed -E 's/^[[:space:]]*"([a-z]{3})[[:space:]].*/\1/' | grep -E '^[a-z]{3}$' | sort -u
}
extract_cmd_labels () {
    tr -d '\r' < "$1" | sed -nE 's/^:Lang_([a-z]{3})$/\1/p' | sort -u
}
extract_iso_non_glb () {
    tr -d '\r' < "$1" | sed -nE 's/.*for %%j in \(([^)]+)\).*/\1/p' | head -n1 \
        | tr ' ' '\n' | grep -E '^[a-z]{3}$' | grep -vx 'glb' | sort -u
}

V_DIALOG="$(extract_bash_dialog_langs "${BASH_DIALOG}")"
V_MENU="$(extract_bash_menu_langs "${BASH_MENU}")"
V_CMD="$(extract_cmd_labels "${CMD_DL}")"
V_ISO="$(extract_iso_non_glb "${CMD_ISO}")"

for pair in "dialog:${V_DIALOG}" "menu:${V_MENU}" "cmd-labels:${V_CMD}" "iso-vocab:${V_ISO}"; do
    lbl="${pair%%:*}"
    val="${pair#*:}"
    cnt="$(printf '%s\n' "${val}" | grep -c .)"
    [ "${cnt}" -eq 24 ] || fail_case "A2: ${lbl} expected 24 non-glb tokens, got ${cnt}"
done
[ "${V_DIALOG}" = "${V_CMD}" ] || fail_case "A2: bash dialog language_keys diverges from DownloadUpdates.cmd :Lang_*"
[ "${V_MENU}" = "${V_CMD}" ] || fail_case "A2: bash languages_menu diverges from DownloadUpdates.cmd :Lang_*"
[ "${V_ISO}" = "${V_CMD}" ] || fail_case "A2: CreateISOImage.cmd vocab diverges from DownloadUpdates.cmd :Lang_*"
if [ "${FAILED_CASES}" -eq "${FAILS_BEFORE}" ]; then
    echo "  ok: A2 24-token vocabulary identical across bash dialog, bash menu, DownloadUpdates.cmd, CreateISOImage.cmd"
fi

# A3: Real bash downloader functions (calculate_static_downloads_dotnet & calculate_static_updates w62)
FAILS_BEFORE="${FAILED_CASES}"
BASH_SB="$(make_tmp)"
BASH_DOTNET_OUT_CHS="${BASH_SB}/dotnet-chs.txt"
BASH_DOTNET_OUT_ENU="${BASH_SB}/dotnet-enu.txt"
BASH_IE11_OUT_CHS="${BASH_SB}/ie11-chs.txt"
BASH_IE11_OUT_ENU="${BASH_SB}/ie11-enu.txt"

run_bash_dotnet_calc () { # $1=lang $2=out_file
    local lang="$1" out_file="$2"
    (
        cd "${REPO}/sh" || exit 1
        temp_dir="${BASH_SB}/tmp_${lang}"
        mkdir -p "${temp_dir}"
        : > "${temp_dir}/ExcludeListForce-all.txt"
        language_parameter="${lang}"
        languages_list=( "${lang}" )
        # shellcheck disable=SC1090
        source "${BASH_DOS}"
        apply_exclude_lists () { cp "$1" "$2"; }
        eval "$(awk '/^function calculate_static_downloads_dotnet/,/^}/' "${BASH_DOTNET}")"
        calculate_static_downloads_dotnet "x64" "${out_file}"
    )
}

run_bash_dotnet_calc "chs" "${BASH_DOTNET_OUT_CHS}"
run_bash_dotnet_calc "enu" "${BASH_DOTNET_OUT_ENU}"

n_bash_chs=0
while IFS= read -r u; do
    u="${u%$'\r'}"
    [ -n "${u}" ] || continue
    grep -qF "${u}" "${BASH_DOTNET_OUT_CHS}" \
        || fail_case "A3: bash calculate_static_downloads_dotnet(chs) missed URL: ${u}"
    ! grep -qF "${u}" "${BASH_DOTNET_OUT_ENU}" \
        || fail_case "A3: bash calculate_static_downloads_dotnet(enu) leaked chs URL: ${u}"
    n_bash_chs=$((n_bash_chs + 1))
done < "${REPO}/static/StaticDownloadLinks-dotnet-chs.txt"
[ "${n_bash_chs}" -eq 3 ] || fail_case "A3: expected 3 chs dotnet URLs, checked ${n_bash_chs}"

# Real bash w62 IE11 composition via real calculate_static_updates from 60-main-updates.bash
run_bash_w62_ie11 () { # $1=lang $2=out_file
    local req_lang="$1" out_file="$2"
    (
        cd "${REPO}/sh" || exit 1
        temp_dir="${BASH_SB}/tmp_ie11_${req_lang}"
        mkdir -p "${temp_dir}"
        language_parameter="${req_lang}"
        languages_list=( "${req_lang}" )
        include_service_packs="enabled"
        service_packs=()
        # shellcheck disable=SC1090
        source "${BASH_DOS}"
        log_info_message () { :; }
        filter_default_languages () { cat_dos "$1"; }
        sort_in_place () { LC_ALL=C sort -u "$1" -o "$1"; }
        apply_exclude_lists () { cp "$1" "$2"; }
        ensure_non_empty_file () { [[ -s "$1" ]]; }
        eval "$(awk '/^function calculate_static_updates/,/^}/' "${BASH_MAIN}")"
        calculate_static_updates "w62" "x64" "glb" "${out_file}"
    )
}

run_bash_w62_ie11 "chs" "${BASH_IE11_OUT_CHS}"
run_bash_w62_ie11 "enu" "${BASH_IE11_OUT_ENU}"

n_bash_ie11=0
while IFS= read -r u; do
    u="${u%$'\r'}"
    [ -n "${u}" ] || continue
    grep -qF "${u}" "${BASH_IE11_OUT_CHS}" \
        || fail_case "A3: bash w62 calculate_static_updates(chs) missed IE11 LP URL: ${u}"
    ! grep -qF "${u}" "${BASH_IE11_OUT_ENU}" \
        || fail_case "A3: bash w62 calculate_static_updates(enu) leaked chs IE11 LP URL: ${u}"
    n_bash_ie11=$((n_bash_ie11 + 1))
done < "${REPO}/static/StaticDownloadLinks-ie11-w62-x64-chs.txt"
[ "${n_bash_ie11}" -gt 0 ] || fail_case "A3: expected >0 chs IE11 LP URLs, checked ${n_bash_ie11}"

if [ "${FAILED_CASES}" -eq "${FAILS_BEFORE}" ]; then
    echo "  ok: A3 real bash dotnet (3 chs NLPs / 0 on enu) and w62 IE11 LP (${n_bash_ie11} chs / 0 on enu) verified"
fi

# A4: bash -n syntax check over all sh/**/*.bash
FAILS_BEFORE="${FAILED_CASES}"
if ! find "${REPO}/sh" -type f -name "*.bash" -exec bash -n {} + 2>"${BASH_SB}/syntax.err"; then
    fail_case "A4: bash -n failed on sh/**/*.bash"
    sed 's/^/    /' "${BASH_SB}/syntax.err"
fi
if [ "${FAILED_CASES}" -eq "${FAILS_BEFORE}" ]; then
    echo "  ok: A4 bash -n clean across all sh/**/*.bash scripts"
fi

# Control A1: mutating bash language_keys must bite vocab parity
MUT_DIALOG="${BASH_SB}/dialog-mutated.bash"
sed 's/ chs / chz /' "${BASH_DIALOG}" > "${MUT_DIALOG}"
V_MUT="$(extract_bash_dialog_langs "${MUT_DIALOG}")"
if [ "${V_MUT}" != "${V_CMD}" ]; then
    echo "  control ok: A1 vocab parity bites on mutated bash language_keys"
else
    fail_case "control A1 does not bite: mutated language_keys still matched CMD vocab"
fi

# =====================================================================
# SECTION B: Windows E2E #51 (Generator -> Medium -> Installer handoff)
# =====================================================================
echo "=== Section B: End-to-End #51 Generator -> Medium -> Installer ==="
if [ -z "${WINDIR:-}" ] || ! command -v cmd >/dev/null 2>&1 || ! command -v cygpath >/dev/null 2>&1; then
    echo "SKIP Section B (Windows E2E handoff): needs a Windows-side bash host (cmd.exe + cygpath) - documented host skip"
else
    CSC=""
    for c in /c/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe \
             /c/Windows/Microsoft.NET/Framework/v4.0.30319/csc.exe; do
        [ -f "${c}" ] && CSC="${c}" && break
    done
    [ -n "${CSC}" ] || { echo "FAIL: csc.exe missing on Windows host"; exit 1; }
    case "${PROCESSOR_ARCHITECTURE:-}" in
        AMD64) WGET_NAME=wget64.exe; SIG_NAME=sigcheck64.exe; HASH_NAME=hashdeep64.exe ;;
        x86)   WGET_NAME=wget.exe;   SIG_NAME=sigcheck.exe;   HASH_NAME=hashdeep.exe ;;
        *) echo "FAIL: unexpected arch ${PROCESSOR_ARCHITECTURE:-}"; exit 1 ;;
    esac

    STUB_DIR="$(make_tmp)"
    cat > "${STUB_DIR}/wget.cs" <<'CSEOF'
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

class WgetStub
{
    static int Main(string[] args)
    {
        string dest = null, listFile = null, outFile = null;
        var urls = new List<string>();
        for (int i = 0; i < args.Length; i++)
        {
            string a = args[i];
            if (a == "-P" && i + 1 < args.Length) { dest = args[++i]; continue; }
            if (a == "-i" && i + 1 < args.Length) { listFile = args[++i]; continue; }
            if (a == "-O" && i + 1 < args.Length) { outFile = args[++i]; continue; }
            if (a.StartsWith("-")) continue;
            urls.Add(a);
        }
        if (listFile != null && File.Exists(listFile))
        {
            foreach (string raw in File.ReadAllLines(listFile))
            {
                string ln = raw.Trim();
                if (ln.Length > 0 && !ln.StartsWith("#")) urls.Add(ln);
            }
        }
        foreach (string u in urls)
        {
            string name = "";
            try { name = Path.GetFileName(new Uri(u).LocalPath); } catch { name = u; }
            if (name.Length == 0) continue;
            string target = outFile ?? (dest != null ? Path.Combine(dest, name) : name);
            try
            {
                string dir = Path.GetDirectoryName(target);
                if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir)) Directory.CreateDirectory(dir);
                File.WriteAllText(target, u + Environment.NewLine, new UTF8Encoding(false));
            }
            catch { }
        }
        return 0;
    }
}
CSEOF
    STUB_WIN="$(cygpath -w "${STUB_DIR}")"
    "${CSC}" -nologo "-out:${STUB_WIN}\\wget-stub.exe" "${STUB_WIN}\\wget.cs" > "${STUB_DIR}/csc.log" 2>&1 \
        || { echo "FAIL: wget stub compile failed"; sed 's/^/    /' "${STUB_DIR}/csc.log"; exit 1; }

    scaffold_e2e_medium () {
        local sb
        sb="$(make_tmp)"
        mkdir -p "${sb}/cmd" "${sb}/static" "${sb}/exclude" "${sb}/xslt" "${sb}/bin" "${sb}/log" "${sb}/tmp" \
                 "${sb}/client/cmd" "${sb}/client/bin" "${sb}/client/md"
        cp -r "${REPO}/cmd/." "${sb}/cmd/"
        cp -r "${REPO}/static/." "${sb}/static/"
        MSYS2_ARG_CONV_EXCL='' robocopy \
            "$(cygpath -w "${REPO}/exclude")" "$(cygpath -w "${sb}/exclude")" \
            //E //XF ExcludeList-superseded.txt ExcludeList-superseded-seconly.txt \
            //NFL //NDL //NJH //NJS > /dev/null 2>&1 || true
        cp -r "${REPO}/xslt/." "${sb}/xslt/"
        for t in unzip gsort join cut; do
            [ -f "${REPO}/bin/${t}.exe" ] && cp "${REPO}/bin/${t}.exe" "${sb}/bin/"
        done
        cp "${REPO}/client/cmd/DoUpdate.cmd" "${sb}/client/cmd/DoUpdate.cmd"
        printf '[Windows 11]\r\n26100_x64=Enabled\r\n' > "${sb}/Windows10Versions.ini"
        for f in "${sb}"/static/StaticDownloadLinks-w100-x64-glb.txt \
                 "${sb}"/static/StaticDownloadLinks-w100-*-x64-glb.txt \
                 "${sb}"/static/StaticDownloadLinks-win-glb.txt \
                 "${sb}"/static/StaticDownloadLinks-cpp-x64-glb.txt \
                 "${sb}"/static/StaticDownloadLinks-cpp-x86-glb.txt; do
            [ -f "${f}" ] || continue
            head -1 "${f}" > "${f}.s" && mv "${f}.s" "${f}"
        done
        head -3 "${sb}/static/StaticDownloadLinks-dotnet.txt" > "${sb}/static/StaticDownloadLinks-dotnet.txt.s" \
            && mv "${sb}/static/StaticDownloadLinks-dotnet.txt.s" "${sb}/static/StaticDownloadLinks-dotnet.txt"
        cp "${STUB_DIR}/wget-stub.exe" "${sb}/bin/${WGET_NAME}"
        printf '%s\n' "${sb}"
    }

    run_dl () { # $1=sb $2=args
        local sb="$1" args="$2" tw
        tw="$(cygpath -w "${sb}/tmp")"
        ( cd "${sb}" && TEMP="${tw}" TMP="${tw}" MSYS2_ARG_CONV_EXCL='' \
            cmd //c "cmd\\DownloadUpdates.cmd ${args}" > "${sb}/dl.log" 2>&1 )
        DL_RC=$?
    }

    run_inst () { # $1=sb $2=os_name $3=os_arch $4=os_lang $5=os_lang_ext $6=mode
        local sb="$1" osn="$2" osa="$3" osl="$4" osle="$5" mode="${6:-}" tw lw
        tw="$(cygpath -w "${sb}/tmp")"
        lw="$(cygpath -w "${sb}/log/wsusofflineupdate.log")"
        : > "${sb}/log/wsusofflineupdate.log"
        ( cd "${sb}/client/cmd" && \
            OS_NAME="${osn}" OS_ARCH="${osa}" OS_LANG="${osl}" OS_LANG_EXT="${osle}" \
            OFC_INSTALLED="" TEMP="${tw}" TMP="${tw}" UPDATE_LOGFILE="${lw}" \
            MSYS2_ARG_CONV_EXCL='' cmd //c ".\\DoUpdate.cmd /testmediumlang ${mode}" > "${sb}/inst.log" 2>&1 )
        INST_RC=$?
    }

    NOTICE_TEXT="language-specific updates will not be offered - medium is glb-only"

    # B1: E2E-51-CMD-CHS (real CMD glb + chs generation with default cleanup -> real DoUpdate.cmd chs)
    FAILS_BEFORE="${FAILED_CASES}"
    SB_CHS="$(scaffold_e2e_medium)"
    run_dl "${SB_CHS}" "w100-x64 glb /includedotnet /skipdynamic /skiptz"
    [ "${DL_RC}" -eq 0 ] || fail_case "E2E-51-CMD-CHS: glb download rc=${DL_RC}"
    run_dl "${SB_CHS}" "w100-x64 chs /includedotnet /skipdynamic /skiptz"
    [ "${DL_RC}" -eq 0 ] || fail_case "E2E-51-CMD-CHS: chs download rc=${DL_RC}"
    [ -f "${SB_CHS}/client/dotnet/ndp481-x86-x64-allos-chs.exe" ] \
        || fail_case "E2E-51-CMD-CHS: chs NLP did not land on generated medium"
    [ ! -d "${SB_CHS}/client/w100-x64/chs" ] \
        || fail_case "E2E-51-CMD-CHS: empty ghost dir client/w100-x64/chs leaked onto medium"
    run_inst "${SB_CHS}" w100 x64 chs zh-cn
    [ "${INST_RC}" -eq 0 ] || fail_case "E2E-51-CMD-CHS: DoUpdate.cmd rc=${INST_RC}"
    grep -qF "Medium carries chs language packs (.NET)" "${SB_CHS}/inst.log" \
        || fail_case "E2E-51-CMD-CHS: DoUpdate.cmd did not recognize chs .NET language packs on CMD-generated medium"
    ! grep -qF "${NOTICE_TEXT}" "${SB_CHS}/inst.log" \
        || fail_case "E2E-51-CMD-CHS: spurious glb-only notice on chs medium"
    if [ "${FAILED_CASES}" -eq "${FAILS_BEFORE}" ]; then
        echo "  ok: B1 E2E-51-CMD-CHS passed (CMD glb+chs -> DoUpdate.cmd recognized chs NLPs, 0 fallback notice)"
    fi

    # Control B1: stripping chs NLPs from that exact generated medium must flip DoUpdate.cmd to glb-only notice
    rm -f "${SB_CHS}"/client/dotnet/*-allos-chs.exe
    run_inst "${SB_CHS}" w100 x64 chs zh-cn
    if [ "${INST_RC}" -eq 0 ] && grep -qF "${NOTICE_TEXT}" "${SB_CHS}/inst.log" && grep -qF "${NOTICE_TEXT}" "${SB_CHS}/log/wsusofflineupdate.log"; then
        echo "  control ok: B1 stripping chs NLPs flips DoUpdate.cmd to explicit glb-only notice"
    else
        fail_case "control B1 did not flip after stripping chs NLPs (rc=${INST_RC})"
    fi

    # B2: E2E-51-CMD-GLB-FALLBACK & SC4 ENU (real CMD glb-only -> chs notice + enu silent)
    FAILS_BEFORE="${FAILED_CASES}"
    SB_GLB="$(scaffold_e2e_medium)"
    run_dl "${SB_GLB}" "w100-x64 glb /includedotnet /skipdynamic /skiptz"
    [ "${DL_RC}" -eq 0 ] || fail_case "E2E-51-CMD-GLB: glb download rc=${DL_RC}"
    run_inst "${SB_GLB}" w100 x64 chs zh-cn
    [ "${INST_RC}" -eq 0 ] || fail_case "E2E-51-CMD-GLB: DoUpdate(chs) rc=${INST_RC}"
    grep -qF "${NOTICE_TEXT}" "${SB_GLB}/inst.log" \
        || fail_case "E2E-51-CMD-GLB: missing glb-only notice on chs console"
    grep -qF "${NOTICE_TEXT}" "${SB_GLB}/log/wsusofflineupdate.log" \
        || fail_case "E2E-51-CMD-GLB: missing glb-only notice on chs log"
    run_inst "${SB_GLB}" w100 x64 enu en-us
    [ "${INST_RC}" -eq 0 ] || fail_case "E2E-51-CMD-GLB: DoUpdate(enu) rc=${INST_RC}"
    ! grep -qF "${NOTICE_TEXT}" "${SB_GLB}/inst.log" \
        || fail_case "E2E-51-CMD-GLB: spurious notice on enu SC4 run"
    if [ "${FAILED_CASES}" -eq "${FAILS_BEFORE}" ]; then
        echo "  ok: B2 E2E-51-CMD-GLB passed (chs received console+log fallback notice; enu stayed silent SC4)"
    fi

    # B3: E2E-51-W62-BOTH-LAYOUTS (CMD w62-x64/chs/ AND bash w62-x64/glb/ both work with DoUpdate.cmd)
    FAILS_BEFORE="${FAILED_CASES}"
    SB_W62="$(scaffold_e2e_medium)"
    run_dl "${SB_W62}" "w62-x64 chs /skipdynamic /skiptz"
    [ "${DL_RC}" -eq 0 ] || fail_case "E2E-51-W62: CMD w62-x64 chs download rc=${DL_RC}"
    run_inst "${SB_W62}" w62 x64 chs zh-cn ie11
    [ "${INST_RC}" -eq 0 ] || fail_case "E2E-51-W62: DoUpdate ie11 (CMD layout) rc=${INST_RC}"
    grep -qF 'IE_LANG_DIR=..\w62-x64\chs' "${SB_W62}/inst.log" \
        || fail_case "E2E-51-W62: CMD layout did not resolve ..\\w62-x64\\chs"
    # Bash layout: move IE11 LP to w62-x64/glb/ (exact bash 60-main-updates.bash destination)
    mkdir -p "${SB_W62}/client/w62-x64/glb"
    mv "${SB_W62}"/client/w62-x64/chs/*.msu "${SB_W62}/client/w62-x64/glb/"
    run_inst "${SB_W62}" w62 x64 chs zh-cn ie11
    [ "${INST_RC}" -eq 0 ] || fail_case "E2E-51-W62: DoUpdate ie11 (bash layout) rc=${INST_RC}"
    grep -qF 'IE_LANG_DIR=..\w62-x64\glb' "${SB_W62}/inst.log" \
        || fail_case "E2E-51-W62: bash layout did not resolve ..\\w62-x64\\glb"
    if [ "${FAILED_CASES}" -eq "${FAILS_BEFORE}" ]; then
        echo "  ok: B3 E2E-51-W62-BOTH-LAYOUTS passed (CMD w62-x64\\chs and bash w62-x64\\glb both resolved)"
    fi

    # B4: E2E-51-BASH-TO-INSTALLER (materialize real bash Section A dotnet-chs output -> DoUpdate.cmd)
    FAILS_BEFORE="${FAILED_CASES}"
    SB_B2I="$(make_tmp)"
    mkdir -p "${SB_B2I}/client/cmd" "${SB_B2I}/client/w100-x64/glb" "${SB_B2I}/client/dotnet" "${SB_B2I}/tmp" "${SB_B2I}/log"
    cp "${REPO}/client/cmd/DoUpdate.cmd" "${SB_B2I}/client/cmd/DoUpdate.cmd"
    while IFS= read -r u; do
        u="${u%$'\r'}"
        [ -n "${u}" ] || continue
        bn="${u##*/}"
        printf '%s\n' "${u}" > "${SB_B2I}/client/dotnet/${bn}"
    done < "${BASH_DOTNET_OUT_CHS}"
    run_inst "${SB_B2I}" w100 x64 chs zh-cn
    [ "${INST_RC}" -eq 0 ] || fail_case "E2E-51-BASH-TO-INSTALLER: DoUpdate(chs) rc=${INST_RC}"
    grep -qF "Medium carries chs language packs (.NET)" "${SB_B2I}/inst.log" \
        || fail_case "E2E-51-BASH-TO-INSTALLER: DoUpdate did not recognize bash-produced chs NLPs"
    ! grep -qF "${NOTICE_TEXT}" "${SB_B2I}/inst.log" \
        || fail_case "E2E-51-BASH-TO-INSTALLER: spurious glb-only notice on bash-produced chs medium"
    if [ "${FAILED_CASES}" -eq "${FAILS_BEFORE}" ]; then
        echo "  ok: B4 E2E-51-BASH-TO-INSTALLER passed (bash chs medium -> DoUpdate.cmd recognized chs NLPs)"
    fi
fi

if [ "${FAILED_CASES}" -eq 0 ]; then
    echo "E2E-LANGUAGE-PARITY-PASS"
    exit 0
fi
echo "E2E-LANGUAGE-PARITY-FAIL (${FAILED_CASES} failed case(s))"
exit 1
