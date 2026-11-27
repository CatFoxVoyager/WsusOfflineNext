#!/usr/bin/env bash
# ci/tests/test-language-invocation.sh - offline engine battery for the %2
# language grammar of cmd/DownloadUpdates.cmd (plan 38-01, phase 38).
#
# Run from repo root on a Windows-side bash host. Zero network: the engine
# runs against a SANDBOX TREE (never the live repo - engine runs delete
# files, DownloadUpdates.cmd del-block near the top) and every external
# binary the exercised paths invoke is replaced by a recording stub compiled
# with the OS-bundled csc (wget64/wget, hashdeep64/hashdeep, sigcheck64/
# sigcheck). Probes are log lines, the stub record and files the stubs
# write - no download ever leaves the machine. Records are UTF-8 without
# BOM so pristine/working comparisons stay byte-clean.
#
# Covered behaviors (plan 38-01 task cases):
#   REFUSE       non-vocab %2 token exits via InvalidParams (per target class)
#   SC4          the glb w100-x64 invocation (run.log + download.log + stub
#                record) is byte-identical between the PRISTINE engine
#                (pinned git blob below, captured before any 38-01 edit) and
#                the working-tree engine - the central zero-change pin
#   ACCEPT       w100-x64 chs passes the gate, its dotnet NLP list is
#                composed into the run's valid list (E3), the NLP files land
#                in client/dotnet, and the dynamic determination is skipped
#                for the Windows target (E2 - the skip line names the
#                language-neutral rule)
#   NO-DUP       the same chs run records NO URL of the w100-x64 glb static
#                family and downloads nothing into client/w100-x64/chs
#   O2K16-ACCEPT o2k16 chs passes the gate (token membership only; the
#                Office content axis is deferred LANGV2-01)
#   MARKER-WRITE / SAME-DAY-SKIP / GLB-NO-MARKER   per-language same-day
#                keying of the dotnet block (task 2)
#
# Same-day provenance (task 2, dated 2026-11-27): the engine's glb-keyed
# same-day skip (hashes-dotnet-%TARGET_ARCH%-glb.txt) was measured INERT at
# planning - no writer for its key file existed anywhere in the engine, so
# it never fired. The non-glb per-language marker mechanism introduced by
# task 2 is the live implementation of the per-language same-day keying;
# any future writer for the glb key is a deliberate SC4-breaking decision
# and must be recorded as such.
#   IE11-LPS / W100-NOOP / REFUSAL-SWEEP / ISO-USB-ZERO  ie11-w62-x64
#                composition + refusal sweep + ISO/USB zero-diff (task 3)
#
# Dynamic-determination scoping: every case runs with the existing
# /skipdynamic switch (the dynamic determination needs the real wsusscn2.cab
# - out of scope, network) and /skiptz (the TZ vbs probe is engine ambient,
# not language grammar). The E2 guard sits BEFORE the on-demand skip check
# inside DownloadCore, so its own log line (distinct from the on-demand
# skip line) fires on every non-glb Windows run, /skipdynamic included:
# that line is the battery's E2 observable.
#
# SC4 pin: PRISTINE_SHA is the cmd/DownloadUpdates.cmd git blob at the start
# of plan 38-01 (HEAD 6f66ae0, pinned 2026-11-27). The battery materializes
# that blob with git cat-file and compares the full glb invocation artifacts
# line-for-line (timestamps normalized). Refreshing the pin is a deliberate
# SC4-breaking decision and must be recorded as such.
#
# Sandbox excludes (justified): exclude/ExcludeList-superseded.txt and
# exclude/ExcludeList-superseded-seconly.txt are NOT copied. The engine
# deletes ExcludeList-superseded.txt when the -seconly variant is absent
# (superseded block) and never reads either list in any flow this battery
# exercises; carrying the -seconly file would additionally flip the engine
# into seconly mode. bin/ is copied selectively (unzip gsort join cut - the
# tools the exercised paths invoke); the recording stubs overwrite the
# engine-resolved downloader/integrity/signature names inside the sandbox.
#
# Windows host conventions (repo lessons 32-01/30-02/35-01): the engine is
# invoked as ONE quoted string behind cmd //c with MSYS2_ARG_CONV_EXCL
# scoped empty for that invocation only; TEMP/TMP are pinned inside the
# sandbox in Windows form; the injection-shaped refusal token travels
# quoted inside the invocation string so the caret reaches %2 literally.
#
# Can-fail controls (bite modes): the battery can be run with one argument
#   bite-refuse  the ACCEPT case's token is pointed at a non-vocab token
#                (the refusal path must fire - ACCEPT must fail)
#   bite-nolist  the sandbox static copy lacks
#                StaticDownloadLinks-dotnet-chs.txt (ACCEPT must fail)
#   bite-sc4     the pristine engine copy is corrupted by one glb-visible
#                edit (SC4 must fail)
# In bite mode the battery expects the targeted case to fail and exits 0
# with BITE-CONFIRMED only when that exact case bit.
set -u
export LC_ALL=C

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENGINE_REL="cmd/DownloadUpdates.cmd"
# engine blob at plan 38-01 start (HEAD 6f66ae0, pinned 2026-11-27)
PRISTINE_SHA="d88870299f00314091c1316d9791d1bb1ad141ee"
E2_LINE="Skipped determination of dynamic update urls for"
E2_LINE_FULL="the Windows dynamic set is language neutral"
MARKER_SKIP_LINE="Skipped download/validation of .NET Frameworks' language files for"
BITE_MODE="${1:-}"
BITE_HIT=0

FAILED_CASES=0

fail_case () {
    echo "FAIL: $1"
    FAILED_CASES=$((FAILED_CASES + 1))
    return 0
}

# host gate: cmd.exe + cygpath required (documented skip elsewhere)
if [ -z "${WINDIR:-}" ] || ! command -v cmd >/dev/null 2>&1 \
   || ! command -v cygpath >/dev/null 2>&1; then
    echo "SKIP language-invocation battery: needs a Windows-side bash host (cmd.exe + cygpath) - documented host skip"
    exit 0
fi
command -v git >/dev/null 2>&1 \
    || { echo "FAIL: git unavailable - the SC4 pristine engine blob cannot be materialized"; exit 1; }

# pre-flight: the files the battery's asserts are built on
[ -f "${REPO}/${ENGINE_REL}" ] || { echo "FAIL: engine missing: ${ENGINE_REL}"; exit 1; }
[ -f "${REPO}/static/StaticDownloadLinks-dotnet-chs.txt" ] \
    || { echo "FAIL: static/StaticDownloadLinks-dotnet-chs.txt missing - the ACCEPT probe has no list"; exit 1; }
[ -f "${REPO}/static/StaticDownloadLinks-ie11-w62-x64-chs.txt" ] \
    || { echo "FAIL: static/StaticDownloadLinks-ie11-w62-x64-chs.txt missing - the IE11 probe has no list"; exit 1; }
grep -qF "for %%j in (glb enu fra esn jpn kor rus ptg ptb deu nld ita chs cht plk hun csy sve trk ell ara heb dan nor fin)" \
    "${REPO}/cmd/CreateISOImage.cmd" \
    || { echo "FAIL: the 24-token vocabulary anchor moved in cmd/CreateISOImage.cmd - re-pin the battery"; exit 1; }

# stub compiler: the OS-bundled csc (repo precedent: office-c2r scenario D)
CSC=""
for c in /c/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe \
         /c/Windows/Microsoft.NET/Framework/v4.0.30319/csc.exe; do
    [ -f "${c}" ] && CSC="${c}" && break
done
[ -n "${CSC}" ] \
    || { echo "FAIL: no OS-bundled csc.exe found - the offline recorder stubs cannot be compiled"; exit 1; }

case "${PROCESSOR_ARCHITECTURE:-}" in
    AMD64) WGET_NAME=wget64.exe; SIG_NAME=sigcheck64.exe; HASH_NAME=hashdeep64.exe ;;
    x86)   WGET_NAME=wget.exe;   SIG_NAME=sigcheck.exe;   HASH_NAME=hashdeep.exe ;;
    *) echo "FAIL: unexpected PROCESSOR_ARCHITECTURE '${PROCESSOR_ARCHITECTURE:-}' - stub names unknown"; exit 1 ;;
esac

# scratch root: the repo's gitignored planning tmp (dispatch convention),
# NOT the platform temp - engine-written files inside %TEMP% vanished
# between runs on this host (only 2 of 8 integrity dbs survived; cause
# unattributed - likely real-time AV policing the temp volume), which
# broke the same-day marker leg. On the repo scratch every engine-written
# file survives run-to-run.
SCRATCH_ROOT="${REPO}/.planning/tmp/38-01"
mkdir -p "${SCRATCH_ROOT}" || { echo "FAIL: cannot create ${SCRATCH_ROOT}"; exit 1; }
STUB_DIR="$(mktemp -d "${SCRATCH_ROOT}/stub.XXXXXX")"
PRISTINE_DIR="$(mktemp -d "${SCRATCH_ROOT}/pristine.XXXXXX")"
SB_DIR=""
SB_DIR_A=""
SB_DIR_B=""
# WOU_LANG_KEEP=1 keeps the sandboxes on disk for post-run inspection
# (debugging aid; prints each sandbox path beside its case marker)
cleanup () { [ -n "${WOU_LANG_KEEP:-}" ] && return 0; for d in "${SB_DIR}" "${SB_DIR_A}" "${SB_DIR_B}" "${STUB_DIR}" "${PRISTINE_DIR}"; do
    [ -n "${d}" ] && [ -d "${d}" ] && rm -rf "${d}"; done; }
trap cleanup EXIT

# ---- recording stubs: record argv to WOU_LANG_BATTERY_RECORD, exit 0 ----
cat > "${STUB_DIR}/wget.cs" <<'CSEOF'
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

class WgetStub
{
    static int Main(string[] args)
    {
        string rec = Environment.GetEnvironmentVariable("WOU_LANG_BATTERY_RECORD");
        string dest = null;
        string listFile = null;
        string outFile = null;
        List<string> urls = new List<string>();
        for (int i = 0; i < args.Length; i++)
        {
            string a = args[i];
            if (a == "-P" && i + 1 < args.Length) { dest = args[++i]; continue; }
            if (a == "-i" && i + 1 < args.Length) { listFile = args[++i]; continue; }
            if (a == "-O" && i + 1 < args.Length) { outFile = args[++i]; continue; }
            if (a.StartsWith("-")) { continue; }
            urls.Add(a);
        }
        if (listFile != null && File.Exists(listFile))
        {
            foreach (string raw in File.ReadAllLines(listFile))
            {
                string line = raw.Trim();
                if (line.Length > 0 && !line.StartsWith("#")) { urls.Add(line); }
            }
        }
        if (rec != null)
        {
            StringBuilder sb = new StringBuilder("WGET");
            foreach (string a in args) { sb.Append(" "); sb.Append(a); }
            File.AppendAllText(rec, sb.ToString() + Environment.NewLine, new UTF8Encoding(false));
        }
        foreach (string u in urls)
        {
            string name = string.Empty;
            try { name = Path.GetFileName(new Uri(u).LocalPath); }
            catch (Exception) { name = u; }
            if (name.Length == 0) { continue; }
            string target = (outFile != null) ? outFile : ((dest != null) ? Path.Combine(dest, name) : name);
            try
            {
                string dir = Path.GetDirectoryName(target);
                if (dir != null && dir.Length > 0 && !Directory.Exists(dir)) { Directory.CreateDirectory(dir); }
                File.WriteAllText(target, u + Environment.NewLine, new UTF8Encoding(false));
            }
            catch (Exception) { }
        }
        return 0;
    }
}
CSEOF
cat > "${STUB_DIR}/hashdeep.cs" <<'CSEOF'
using System;
using System.IO;
using System.Text;

class HashdeepStub
{
    static int Main(string[] args)
    {
        string rec = Environment.GetEnvironmentVariable("WOU_LANG_BATTERY_RECORD");
        if (rec != null)
        {
            StringBuilder sb = new StringBuilder("HASHDEEP");
            foreach (string a in args) { sb.Append(" "); sb.Append(a); }
            File.AppendAllText(rec, sb.ToString() + Environment.NewLine, new UTF8Encoding(false));
        }
        // The engine's legacy-db cleanup (DownloadUpdates.cmd, "delete
        // old-style hashes" block) deletes any client/md/hashes-*.txt whose
        // content lacks the real hashdeep command-line signature - a bare
        // fake line got every stub-written db erased at the next run start
        // (measured live, 2026-11-27). Emit the hashdeep header shape.
        Console.WriteLine("%%%% HASHDEEP-1.0");
        Console.WriteLine("%%%% %# -c md5,sha1,sha256 -b battery-stub");
        Console.WriteLine("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb,cccccccccccccccccccccccccccccccccccccccc  0,0,0, files,hashes,battery-stub");
        return 0;
    }
}
CSEOF
cat > "${STUB_DIR}/sigcheck.cs" <<'CSEOF'
using System;
using System.IO;
using System.Text;

class SigcheckStub
{
    static int Main(string[] args)
    {
        string rec = Environment.GetEnvironmentVariable("WOU_LANG_BATTERY_RECORD");
        if (rec != null)
        {
            StringBuilder sb = new StringBuilder("SIGCHECK");
            foreach (string a in args) { sb.Append(" "); sb.Append(a); }
            File.AppendAllText(rec, sb.ToString() + Environment.NewLine, new UTF8Encoding(false));
        }
        return 0;
    }
}
CSEOF
STUB_WIN="$(cygpath -w "${STUB_DIR}")"
[ -n "${STUB_WIN}" ] || { echo "FAIL: cygpath could not translate the stub dir"; exit 1; }
"${CSC}" -nologo "-out:${STUB_WIN}\\wget-stub.exe" "${STUB_WIN}\\wget.cs" > "${STUB_DIR}/csc-wget.log" 2>&1 \
    || { echo "FAIL: wget stub compile failed"; sed 's/^/    /' "${STUB_DIR}/csc-wget.log"; exit 1; }
"${CSC}" -nologo "-out:${STUB_WIN}\\hashdeep-stub.exe" "${STUB_WIN}\\hashdeep.cs" > "${STUB_DIR}/csc-hashdeep.log" 2>&1 \
    || { echo "FAIL: hashdeep stub compile failed"; sed 's/^/    /' "${STUB_DIR}/csc-hashdeep.log"; exit 1; }
"${CSC}" -nologo "-out:${STUB_WIN}\\sigcheck-stub.exe" "${STUB_WIN}\\sigcheck.cs" > "${STUB_DIR}/csc-sigcheck.log" 2>&1 \
    || { echo "FAIL: sigcheck stub compile failed"; sed 's/^/    /' "${STUB_DIR}/csc-sigcheck.log"; exit 1; }

# ---- pristine engine for the SC4 pin ----
# The stored blob is LF-normalized (working tree is CRLF); cmd misparses
# LF-only .cmd files (goto/label scanning), so materialize to the working
# tree's CRLF convention with an idempotent force.
git -C "${REPO}" cat-file blob "${PRISTINE_SHA}" 2>/dev/null | sed -e 's/\r$//' -e 's/$/\r/' > "${PRISTINE_DIR}/DownloadUpdates.cmd"
[ -s "${PRISTINE_DIR}/DownloadUpdates.cmd" ] \
    || { echo "FAIL: SC4 pristine engine blob ${PRISTINE_SHA} not materializable from the object database"; exit 1; }

# ---- sandbox scaffolds ----
# full: the subtrees the engine reads/writes (cmd/ static/ exclude/ xslt/,
# selective bin/, client skeleton with bin+md, log/). Mini: gate-refusal
# runs only (engine + log dir - the run exits at the gate).
function scaffold_mini () {
    SB_DIR="$(mktemp -d "${SCRATCH_ROOT}/sb.XXXXXX")"
    mkdir -p "${SB_DIR}/cmd" "${SB_DIR}/log" "${SB_DIR}/tmp" "${SB_DIR}/client/bin" "${SB_DIR}/client/md"
    cp "${REPO}/${ENGINE_REL}" "${SB_DIR}/cmd/"
}
function scaffold_full () { # $1 = optional "nolist"
    scaffold_mini
    mkdir -p "${SB_DIR}/static" "${SB_DIR}/exclude" "${SB_DIR}/xslt" "${SB_DIR}/bin"
    cp -r "${REPO}/cmd/." "${SB_DIR}/cmd/"
    cp -r "${REPO}/static/." "${SB_DIR}/static/"
    # exclude/ WITHOUT the two multi-MB superseded lists (justified in the
    # header); robocopy excludes at copy time - per-file MSYS cp spawns cost
    # ~300 ms each on this host and turned the scaffold into the battery's
    # dominant cost (11 s measured)
    mkdir -p "${SB_DIR}/exclude"
    MSYS2_ARG_CONV_EXCL='' robocopy \
        "$(cygpath -w "${REPO}/exclude")" "$(cygpath -w "${SB_DIR}/exclude")" \
        //E //XF ExcludeList-superseded.txt ExcludeList-superseded-seconly.txt \
        //NFL //NDL //NJH //NJS > /dev/null 2>&1
    RC_ROBO=$?
    [ "${RC_ROBO}" -ge 8 ] && fail_case "scaffold: robocopy exclude/ failed (rc=${RC_ROBO})"
    cp -r "${REPO}/xslt/." "${SB_DIR}/xslt/"
    for t in unzip gsort join cut; do
        [ -f "${REPO}/bin/${t}.exe" ] && cp "${REPO}/bin/${t}.exe" "${SB_DIR}/bin/"
    done
    # ---- offline-budget fixtures (identical for both engines) ----
    # Build sampling: with no builds ini the engine enables ALL w100 builds
    # and the DoDownload routing spawns find.exe per URL per build (minutes
    # of spawn cost). The sandbox pins ONE enabled build.
    printf '[Windows 11]\r\n26100_x64=Enabled\r\n' > "${SB_DIR}/Windows10Versions.ini"
    # List sampling: keep a bounded sample of the big download families so
    # the whole battery stays under its 60 s budget (stub spawns dominate;
    # every kept line is still a real engine invocation). The SC4 pin is
    # engine-bytes-driven - both sides see the identical sampled inputs.
    # NOT sampled: StaticDownloadLinks-dotnet-chs.txt (the E3 deliverable,
    # 3 URLs) and the ie11 family (the task-3 deliverable).
    for f in "${SB_DIR}"/static/StaticDownloadLinks-w100-x64-glb.txt \
             "${SB_DIR}"/static/StaticDownloadLinks-w100-*-x64-glb.txt \
             "${SB_DIR}"/static/StaticDownloadLinks-win-glb.txt \
             "${SB_DIR}"/static/StaticDownloadLinks-cpp-x64-glb.txt \
             "${SB_DIR}"/static/StaticDownloadLinks-cpp-x86-glb.txt; do
        [ -f "${f}" ] || continue
        head -1 "${f}" > "${f}.sampled" && mv "${f}.sampled" "${f}"
    done
    head -6 "${SB_DIR}/static/StaticDownloadLinks-dotnet.txt" \
        > "${SB_DIR}/static/StaticDownloadLinks-dotnet.txt.sampled" \
        && mv "${SB_DIR}/static/StaticDownloadLinks-dotnet.txt.sampled" \
              "${SB_DIR}/static/StaticDownloadLinks-dotnet.txt"
    if [ "${1:-}" = "nolist" ]; then
        rm -f "${SB_DIR}/static/StaticDownloadLinks-dotnet-chs.txt"
    fi
    cp "${STUB_DIR}/wget-stub.exe" "${SB_DIR}/bin/${WGET_NAME}"
    cp "${STUB_DIR}/sigcheck-stub.exe" "${SB_DIR}/bin/${SIG_NAME}"
    cp "${STUB_DIR}/hashdeep-stub.exe" "${SB_DIR}/client/bin/${HASH_NAME}"
}

function begin_case () {
    REC="${SB_DIR}/record.log"
    REC_WIN="$(cygpath -m "${REC}")"
    : > "${REC}"
}

function run_engine () { # $1 = full argument string for the engine
    ( cd "${SB_DIR}" && TEMP="${TEMP_WIN}" TMP="${TEMP_WIN}" WOU_LANG_BATTERY_RECORD="${REC_WIN}" \
        MSYS2_ARG_CONV_EXCL='' cmd //c "cmd\\DownloadUpdates.cmd $1" > run.log 2>&1 )
    ENGINE_RC=$?
}
TEMP_WIN=""

function normalize () { # $1 in, $2 out - strip leading date/time log prefixes
    sed -E -e 's/^.*[0-9]{1,2}:[0-9]{2}:[0-9]{2}([.,][0-9]+)? - //' "$1" > "$2" 2>/dev/null
}

# =====================================================================
# Case REFUSE: a non-vocab token exits via InvalidParams
# =====================================================================
FAILS_BEFORE="${FAILED_CASES}"
echo "--- case REFUSE: non-vocab token refused on w100-x64"
scaffold_mini
begin_case
TEMP_WIN="$(cygpath -w "${SB_DIR}")\\tmp"
run_engine "w100-x64 zzz /includedotnet /nocleanup /skipdynamic"
# pinned at RED time (2026-11-27, unmodified engine): the InvalidParams path
# exits rc=0 on this host (the :Error verify-other idiom does not yield a
# failing exit code) - the marker text is the pinned observable, not the rc.
grep -qF "ERROR: Invalid command line" "${SB_DIR}/run.log" \
    || fail_case "REFUSE: no 'ERROR: Invalid command line' marker in run.log (observed rc=${ENGINE_RC})"
grep -qF "Usage:" "${SB_DIR}/run.log" \
    || fail_case "REFUSE: the usage line is missing from the InvalidParams output"
if [ "${FAILED_CASES}" -eq "${FAILS_BEFORE}" ]; then
echo "case REFUSE: rc=${ENGINE_RC} - non-vocab token refused via InvalidParams marker"
fi

# =====================================================================
# Case SC4: glb invocation artifacts identical pristine vs working engine
# =====================================================================
FAILS_BEFORE="${FAILED_CASES}"
echo "--- case SC4: glb w100-x64 run byte-identical to the pristine engine"
scaffold_full
SB_DIR_A="${SB_DIR}"
cp "${PRISTINE_DIR}/DownloadUpdates.cmd" "${SB_DIR_A}/cmd/DownloadUpdates.cmd"
scaffold_full
SB_DIR_B="${SB_DIR}"
if [ "${BITE_MODE}" = "bite-sc4" ]; then
    # one glb-visible byte flip; sed is CRLF-UNSAFE on this host (text-mode
    # read strips CR, the -i rewrite lands LF-only and cmd misparses the
    # copy into a wedged run - measured twice), so re-force CRLF after
    sed 's/echo Downloading\/validating installation files for .NET Frameworks 3.5 SP1 and 4.x.../echo Downloading\/validating installation files for NET Frameworks 3.5 SP1 and 4.x.../' \
        "${SB_DIR_A}/cmd/DownloadUpdates.cmd" \
        | sed -e 's/\r$//' -e 's/$/\r/' \
        > "${SB_DIR_A}/cmd/DownloadUpdates.cmd.new" \
        && mv "${SB_DIR_A}/cmd/DownloadUpdates.cmd.new" "${SB_DIR_A}/cmd/DownloadUpdates.cmd"
    CR_COUNT="$(tr -dc '\r' < "${SB_DIR_A}/cmd/DownloadUpdates.cmd" | wc -c)"
    LN_COUNT="$(wc -l < "${SB_DIR_A}/cmd/DownloadUpdates.cmd")"
    [ "${CR_COUNT}" -eq "${LN_COUNT}" ] \
        || { echo "FAIL: bite-sc4 sabotage broke CRLF (${CR_COUNT} CRs / ${LN_COUNT} lines)"; exit 1; }
fi
ART_A="${SB_DIR_A}/artifacts"; mkdir -p "${ART_A}"
ART_B="${SB_DIR_B}/artifacts"; mkdir -p "${ART_B}"

# The two glb runs are independent sandboxes - launch them CONCURRENTLY so
# the two engine executions overlap (each is ~24 s of process-spawn cost on
# this host). Both rcs land in files inside their own sandbox; the wait is
# bounded by this same bash call (no orphaned background gate).
run_sc4 () { # $1 = sandbox dir
    local sb="$1" tw rc_file
    tw="$(cygpath -w "${sb}")\\tmp"
    rc_file="${sb}/engine.rc"
    ( cd "${sb}" && TEMP="${tw}" TMP="${tw}" \
        WOU_LANG_BATTERY_RECORD="$(cygpath -m "${sb}")\\record.log" \
        MSYS2_ARG_CONV_EXCL='' \
        cmd //c "cmd\\DownloadUpdates.cmd w100-x64 glb /includedotnet /nocleanup /skipdynamic /skiptz" \
        > run.log 2>&1; echo $? > "${rc_file}" )
}
: > "${SB_DIR_A}/record.log"; : > "${SB_DIR_B}/record.log"
run_sc4 "${SB_DIR_A}" & RUN_A=$!
run_sc4 "${SB_DIR_B}" & RUN_B=$!
# bounded join: a wedged engine leg (e.g. a foreign GUI process joining the
# console pipe set of a for /F pipeline - observed once on this host,
# 2026-11-27, resolved externally) must convert into a loud verdict, never
# an infinite battery hang. 120 s per leg, then the leg is failed loud.
wait_bound () { # $1 = job pid
    local n=0
    while kill -0 "$1" 2>/dev/null; do
        n=$((n + 1))
        if [ "${n}" -gt 240 ]; then
            kill "$1" 2>/dev/null
            return 124
        fi
        sleep 0.5
    done
    wait "$1" 2>/dev/null
    return 0
}
if wait_bound "${RUN_A}"; then
    RC_A="$(cat "${SB_DIR_A}/engine.rc" 2>/dev/null || echo 999)"
else
    RC_A=124
    fail_case "SC4: the pristine leg exceeded the 120 s bound (environment wedge)"
fi
if wait_bound "${RUN_B}"; then
    RC_B="$(cat "${SB_DIR_B}/engine.rc" 2>/dev/null || echo 999)"
else
    RC_B=124
    fail_case "SC4: the working-tree leg exceeded the 120 s bound (environment wedge)"
fi

normalize "${SB_DIR_A}/run.log" "${ART_A}/run.log"
normalize "${SB_DIR_A}/log/download.log" "${ART_A}/download.log" 2>/dev/null || : > "${ART_A}/download.log"
SBX_W="$(cygpath -w "${SB_DIR_A}")"; SBX_M="$(cygpath -m "${SB_DIR_A}")"
while IFS= read -r rec_ln; do
    rec_ln="${rec_ln//"$SBX_W"/SBX}"; rec_ln="${rec_ln//"$SBX_M"/SBX}"
    printf '%s\n' "${rec_ln}"
done < "${SB_DIR_A}/record.log" > "${ART_A}/record.log"

normalize "${SB_DIR_B}/run.log" "${ART_B}/run.log"
normalize "${SB_DIR_B}/log/download.log" "${ART_B}/download.log" 2>/dev/null || : > "${ART_B}/download.log"
SBX_W="$(cygpath -w "${SB_DIR_B}")"; SBX_M="$(cygpath -m "${SB_DIR_B}")"
while IFS= read -r rec_ln; do
    rec_ln="${rec_ln//"$SBX_W"/SBX}"; rec_ln="${rec_ln//"$SBX_M"/SBX}"
    printf '%s\n' "${rec_ln}"
done < "${SB_DIR_B}/record.log" > "${ART_B}/record.log"

[ "${RC_A}" -eq "${RC_B}" ] && [ "${RC_A}" -eq 0 ] \
    || fail_case "SC4: glb run exit codes pristine=${RC_A} working=${RC_B} - expected 0 and equal"
for f in run.log download.log record.log; do
    [ -s "${ART_A}/${f}" ] || fail_case "SC4: pristine artifact ${f} is empty or missing - the baseline was never captured"
    [ -s "${ART_B}/${f}" ] || fail_case "SC4: working-tree artifact ${f} is empty or missing"
    if ! diff -q "${ART_A}/${f}" "${ART_B}/${f}" > /dev/null 2>&1; then
        fail_case "SC4: glb ${f} differs between the pristine and working-tree engine (glb path not byte-preserved)"
        diff "${ART_A}/${f}" "${ART_B}/${f}" | head -10 | sed 's/^/    /'
    fi
done
if [ "${BITE_MODE}" = "bite-sc4" ] && [ "${FAILED_CASES}" -gt 0 ]; then
    BITE_HIT=1
fi
if [ "${FAILED_CASES}" -eq "${FAILS_BEFORE}" ]; then
echo "case SC4: rc=${RC_A} - run.log + download.log + record.log identical (pristine ${PRISTINE_SHA} vs working tree)"
fi

# =====================================================================
# Case ACCEPT: w100-x64 chs passes the gate and lands its dotnet NLP list
# =====================================================================
FAILS_BEFORE="${FAILED_CASES}"
echo "--- case ACCEPT: w100-x64 chs gate dispatch + E3 dotnet composition + E2 skip"
if [ "${BITE_MODE}" = "bite-nolist" ]; then
    scaffold_full nolist
else
    scaffold_full
fi
begin_case
TEMP_WIN="$(cygpath -w "${SB_DIR}")\\tmp"
ACCEPT_TOKEN="chs"
if [ "${BITE_MODE}" = "bite-refuse" ]; then
    ACCEPT_TOKEN="zzz"
fi
run_engine "w100-x64 ${ACCEPT_TOKEN} /includedotnet /nocleanup /skipdynamic /skiptz"

if [ "${BITE_MODE}" = "" ]; then
    [ "${ENGINE_RC}" -eq 0 ] \
        || fail_case "ACCEPT: the chs run exited ${ENGINE_RC}, expected 0 (gate refusal alive?)"
    ! grep -qF "ERROR: Invalid command line" "${SB_DIR}/run.log" \
        || fail_case "ACCEPT: the chs run was refused at the gate (InvalidParams reached)"
    grep -qF "${E2_LINE} w100-x64 chs - ${E2_LINE_FULL}" "${SB_DIR}/log/download.log" \
        || fail_case "ACCEPT: the E2 non-glb dynamic-skip line is missing from download.log"
    n_dotnet_base=0
    while IFS= read -r u; do
        u="${u%$'\r'}"
        [ -n "${u}" ] || continue
        grep -qF "${u}" "${REC}" || fail_case "ACCEPT: base dotnet URL not downloaded: ${u}"
        n_dotnet_base=$((n_dotnet_base + 1))
    done < "${SB_DIR}/static/StaticDownloadLinks-dotnet.txt"
    [ "${n_dotnet_base}" -gt 0 ] \
        || fail_case "ACCEPT: no base dotnet URLs read from static/StaticDownloadLinks-dotnet.txt (probe vacuous)"
    n_chs=0
    while IFS= read -r u; do
        u="${u%$'\r'}"
        [ -n "${u}" ] || continue
        grep -qF "${u}" "${REC}" || fail_case "ACCEPT: chs NLP URL missing from the stub record: ${u}"
        n_chs=$((n_chs + 1))
    done < "${REPO}/static/StaticDownloadLinks-dotnet-chs.txt"
    [ "${n_chs}" -eq 3 ] \
        || fail_case "ACCEPT: expected 3 chs NLP URLs checked, got ${n_chs} (list shape changed - re-pin)"
    for f in ndp462-kb3151800-x86-x64-allos-chs.exe ndp48-x86-x64-allos-chs.exe ndp481-x86-x64-allos-chs.exe; do
        [ -f "${SB_DIR}/client/dotnet/${f}" ] \
            || fail_case "ACCEPT: the chs NLP file did not land in client/dotnet: ${f}"
    done
    grep -qF "client\\dotnet" "${REC}" \
        || fail_case "ACCEPT: no download into client/dotnet recorded (probe vacuous)"
    [ "$(grep -cF "client\\w100-x64\\chs" "${REC}")" -eq 0 ] \
        || fail_case "ACCEPT: a download targeted client/w100-x64/chs (language dir received payload)"
    if [ "${FAILED_CASES}" -eq "${FAILS_BEFORE}" ]; then
    echo "case ACCEPT: rc=0 - chs dispatched, 3 NLP URLs recorded + files in client/dotnet, E2 skip line present"
    fi
elif [ "${BITE_MODE}" = "bite-refuse" ]; then
    if ! grep -qF "ERROR: Invalid command line" "${SB_DIR}/run.log"; then
        fail_case "bite-refuse: the non-vocab token was NOT refused - refusal instrument blind"
    else
        BITE_HIT=1
    fi
elif [ "${BITE_MODE}" = "bite-nolist" ]; then
    # the chs URLs must be absent from the record now (nothing composed them)
    bite_bit=0
    while IFS= read -r u; do
        u="${u%$'\r'}"
        [ -n "${u}" ] || continue
        grep -qF "${u}" "${REC}" && bite_bit=1
    done < "${REPO}/static/StaticDownloadLinks-dotnet-chs.txt"
    if [ "${bite_bit}" -eq 1 ]; then
        fail_case "bite-nolist: chs NLP URLs were still downloaded without their list - instrument blind"
    else
        BITE_HIT=1
    fi
fi

# =====================================================================
# Case NO-DUP: zero glb-family URLs in the chs run (reuses ACCEPT run)
# =====================================================================
FAILS_BEFORE="${FAILED_CASES}"
echo "--- case NO-DUP: no language-agnostic w100-x64 glb payload in the chs run"
if [ "${BITE_MODE}" = "" ]; then
    n_glb_urls=0
    n_hits=0
    for f in "${REPO}"/static/StaticDownloadLinks-w100-x64-glb.txt \
             "${REPO}"/static/StaticDownloadLinks-w100-*-x64-glb.txt; do
        [ -f "${f}" ] || continue
        while IFS= read -r u; do
            u="${u%$'\r'}"
            [ -n "${u}" ] || continue
            n_glb_urls=$((n_glb_urls + 1))
            grep -qF "${u}" "${REC}" && n_hits=$((n_hits + 1))
        done < "${f}"
    done
    [ "${n_glb_urls}" -gt 0 ] \
        || fail_case "NO-DUP: no glb-family URLs read from static/ (probe vacuous - the w100-x64 glb family vanished?)"
    [ "${n_hits}" -eq 0 ] \
        || fail_case "NO-DUP: ${n_hits} glb-family URL(s) downloaded by the chs run (language-agnostic duplication)"
    if [ -d "${SB_DIR}/client/w100-x64/chs" ]; then
        n_files="$(find "${SB_DIR}/client/w100-x64/chs" -type f 2>/dev/null | wc -l)"
        [ "${n_files}" -eq 0 ] \
            || fail_case "NO-DUP: ${n_files} file(s) landed in client/w100-x64/chs (language dir received agnostic payload)"
    fi
    if [ "${FAILED_CASES}" -eq "${FAILS_BEFORE}" ]; then
    echo "case NO-DUP: 0/${n_glb_urls} glb-family URLs in the chs record, no files in client/w100-x64/chs"
    fi
fi

# =====================================================================
# Case O2K16-ACCEPT: o2k16 chs passes the gate (content out of scope)
# =====================================================================
FAILS_BEFORE="${FAILED_CASES}"
echo "--- case O2K16-ACCEPT: o2k16 chs token membership"
scaffold_full
begin_case
TEMP_WIN="$(cygpath -w "${SB_DIR}")\\tmp"
run_engine "o2k16 chs /nocleanup /skipdynamic /skiptz"
if [ "${BITE_MODE}" = "" ]; then
    [ "${ENGINE_RC}" -eq 0 ] \
        || fail_case "O2K16-ACCEPT: the o2k16 chs run exited ${ENGINE_RC}, expected 0"
    ! grep -qF "ERROR: Invalid command line" "${SB_DIR}/run.log" \
        || fail_case "O2K16-ACCEPT: o2k16 chs refused at the gate"
    grep -qF "for o2k16 chs" "${SB_DIR}/log/download.log" \
        || fail_case "O2K16-ACCEPT: the run start log does not name 'for o2k16 chs' (%2 did not flow)"
    if [ "${FAILED_CASES}" -eq "${FAILS_BEFORE}" ]; then
    echo "case O2K16-ACCEPT: rc=0 - o2k16 chs dispatched, start log names the target+language"
    fi
fi

# =====================================================================
# Case MARKER-WRITE + SAME-DAY-SKIP: per-language dotnet same-day keying
# (task 2). Both runs share ONE sandbox - the second must hit the marker.
# =====================================================================
FAILS_BEFORE="${FAILED_CASES}"
echo "--- case MARKER-WRITE + SAME-DAY-SKIP: chs /verify keys its own marker"
scaffold_full
[ -n "${WOU_LANG_KEEP:-}" ] && echo "KEEP: marker sandbox ${SB_DIR}"
begin_case
TEMP_WIN="$(cygpath -w "${SB_DIR}")\\tmp"
case "w100-x64" in *x64*) BATTERY_ARCH=x64 ;; *) BATTERY_ARCH=x86 ;; esac
run_engine "w100-x64 chs /includedotnet /verify /nocleanup /skipdynamic /skiptz"
if [ "${BITE_MODE}" = "" ]; then
    [ "${ENGINE_RC}" -eq 0 ] \
        || fail_case "MARKER-WRITE: the chs /verify run exited ${ENGINE_RC}, expected 0"
    [ -f "${SB_DIR}/client/md/hashes-dotnet-${BATTERY_ARCH}-chs.txt" ] \
        || fail_case "MARKER-WRITE: no per-language marker hashes-dotnet-${BATTERY_ARCH}-chs.txt after the chs /verify run"
    [ ! -f "${SB_DIR}/client/md/hashes-dotnet-${BATTERY_ARCH}-glb.txt" ] \
        || fail_case "MARKER-WRITE: a -glb marker was written by a chs run"
    if [ "${FAILED_CASES}" -eq "${FAILS_BEFORE}" ]; then
    echo "case MARKER-WRITE: per-language marker present, no -glb marker"
    fi
    FAILS_BEFORE="${FAILED_CASES}"
    run_engine "w100-x64 chs /includedotnet /verify /nocleanup /skipdynamic /skiptz"
    [ "${ENGINE_RC}" -eq 0 ] \
        || fail_case "SAME-DAY-SKIP: the second chs /verify run exited ${ENGINE_RC}, expected 0"
    grep -qF "Skipped download/validation of .NET Frameworks' language files for chs due to 'same day' rule" "${SB_DIR}/log/download.log" \
        || fail_case "SAME-DAY-SKIP: the same-day skip line naming chs is missing from download.log"
    [ -f "${SB_DIR}/client/dotnet/ndp481-x86-x64-allos-chs.exe" ] \
        || fail_case "SAME-DAY-SKIP: the chs NLP vanished after the second run (re-download or cleanup)"
    if [ "${FAILED_CASES}" -eq "${FAILS_BEFORE}" ]; then
    echo "case SAME-DAY-SKIP: second same-day run skipped with the chs line, NLP still on disk"
    fi
fi

# =====================================================================
# Case GLB-NO-MARKER: a glb /verify run writes no marker, never skips
# =====================================================================
FAILS_BEFORE="${FAILED_CASES}"
echo "--- case GLB-NO-MARKER: glb /verify run writes no marker and never skips"
scaffold_full
begin_case
TEMP_WIN="$(cygpath -w "${SB_DIR}")\\tmp"
run_engine "w100-x64 glb /includedotnet /verify /nocleanup /skipdynamic /skiptz"
if [ "${BITE_MODE}" = "" ]; then
    [ "${ENGINE_RC}" -eq 0 ] \
        || fail_case "GLB-NO-MARKER: the glb /verify run exited ${ENGINE_RC}, expected 0"
    [ ! -f "${SB_DIR}/client/md/hashes-dotnet-${BATTERY_ARCH}-glb.txt" ] \
        || fail_case "GLB-NO-MARKER: a per-arch -glb marker was written by a glb run"
    grep -qF "same day" "${SB_DIR}/log/download.log" \
        && fail_case "GLB-NO-MARKER: a same-day skip line appeared on a glb run"
    grep -qF "Created integrity database for .NET Frameworks' installation files" "${SB_DIR}/log/download.log" \
        || fail_case "GLB-NO-MARKER: the integrity db creation line is missing (the dotnet verify leg did not run)"
    if [ "${FAILED_CASES}" -eq "${FAILS_BEFORE}" ]; then
    echo "case GLB-NO-MARKER: no marker, no skip, integrity db created"
    fi
fi

# ---- verdict ----
if [ -n "${BITE_MODE}" ]; then
    if [ "${BITE_HIT}" -eq 1 ]; then
        echo "BITE-CONFIRMED: ${BITE_MODE} - the instrument bit as designed"
        exit 0
    fi
    echo "FAIL: bite mode ${BITE_MODE} did not bite (FAILED_CASES=${FAILED_CASES})"
    exit 1
fi
if [ "${FAILED_CASES}" -eq 0 ]; then
    echo "LANGUAGE-INVOCATION-PASS"
    exit 0
fi
echo "LANGUAGE-INVOCATION-FAIL (${FAILED_CASES} case(s) red)"
exit 1
