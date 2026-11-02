#!/usr/bin/env bash
# ci/tests/test-office-c2r-failclosed.sh - bite battery for the ODT staging engine
#
# Run from repo root. Offline by construction: the staging engine runs inside
# a SANDBOX tree (its own REPO_ROOT, resolved by the engine itself from its
# own path), with bin/odt/setup.exe replaced by a non-PE text stub, so the
# real ODT binary of the working tree is never executed and never touched.
# TEMP/TMP are pinned inside the sandbox for the CMD invocations, so the
# generated config manifest never lands in the user temp either.
#
# Covered behaviors:
#   A (bite): a real run (no /dry-run) whose ODT is a non-PE stub FAILS with
#      a non-zero rc and writes NO integrity file. Pre-fix the same stub
#      produced "Warning: ODT /download exited..." plus rc 0 (soft-fail) - a
#      zero rc here means that soft-fail is still alive.
#   B (flagged lenience): the same run WITH /dry-run exits 0 and STILL writes
#      no integrity file (no ghost hash file in dry runs).
#   C (structure): the hashes write is atomic (temp + Move-Item) with
#      client/office/c2r/ slice filtering, the fail-closed branch exists, the
#      historical AppendAllLines call is GONE (count 0 - the pre-fix bytes
#      count 1, proven by the instrument self-test below), the /dry-run flag
#      is parsed AND documented, and the pinned ODT URL literal still appears
#      exactly once (byte-identity coupling with ci/fetch-release-helpers.bash).
#
# Windows-side bash host required (cmd.exe + powershell): elsewhere the
# battery takes a documented capability skip, like the Authenticode case of
# test-fetch-release-helpers.sh.
set -u
export LC_ALL=C

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CMD_REL="cmd/DownloadOfficeC2R.cmd"
HASHES_NAME="hashes-office-c2r.txt"

function fail ()
{
    echo "FAIL: $1"
    if [ -n "${SB_DIR:-}" ] && [ -f "${SB_DIR}/run.log" ]; then
        echo "--- sandbox run log ---"
        cat "${SB_DIR}/run.log"
    fi
    [ -n "${SB_DIR:-}" ] && rm -rf "${SB_DIR}"
    exit 1
}

# host gate: cmd.exe + powershell + cygpath required (documented skip elsewhere)
if [ -z "${WINDIR:-}" ] || ! command -v cmd >/dev/null 2>&1 \
   || ! command -v powershell >/dev/null 2>&1 || ! command -v cygpath >/dev/null 2>&1; then
    echo "SKIP office-c2r failclosed battery: needs a Windows-side bash host (cmd.exe + powershell + cygpath) - documented host skip"
    exit 0
fi

# ---- instrument self-test: the AppendAllLines grep must be live ----
# (morsure contre les octets pre-fix, ou le comptage vaut 1 : une batterie qui
# verifierait un pattern muet lirait vert a tort - atterrissage avant verdict)
canary="[System.IO.File]::AppendAllLines('%HASHES_FILE%', \$lines); "
[ "$(printf '%s\n' "${canary}" | grep -c 'AppendAllLines')" -eq 1 ] \
    || fail "instrument self-test: the AppendAllLines grep is mute (would read green on pre-fix bytes)"

# ---- scenario C: structure, on the working-tree bytes under test ----
n_append="$(grep -c 'AppendAllLines' "${REPO}/${CMD_REL}")"
[ "${n_append}" -eq 0 ] \
    || fail "AppendAllLines still present in ${CMD_REL} (count ${n_append} - pre-fix soft-write still alive)"
grep -q 'Move-Item' "${REPO}/${CMD_REL}" \
    || fail "no atomic move (Move-Item) in the hashes block"
grep -q 'HASHES_FILE%.tmp' "${REPO}/${CMD_REL}" \
    || fail "no temp write next to the integrity file (atomic temp + move missing)"
grep -q 'client/office/c2r/' "${REPO}/${CMD_REL}" \
    || fail "no client/office/c2r/ slice filtering in the hashes block (siblings would be dropped or appended)"
grep -q 'OdtDownloadFailed' "${REPO}/${CMD_REL}" \
    || fail "no fail-closed branch (OdtDownloadFailed) in the staging engine"
n_dry="$(grep -ci 'dry-run' "${REPO}/${CMD_REL}")"
[ "${n_dry}" -ge 3 ] \
    || fail "/dry-run flag not parsed AND documented (case-insensitive lines: ${n_dry}, need >= 3)"
n_url="$(grep -c 'officedeploymenttool_20430-20146\.exe' "${REPO}/${CMD_REL}")"
[ "${n_url}" -eq 1 ] \
    || fail "pinned ODT URL literal count is ${n_url}, expected exactly 1 (byte-identity with ci/fetch-release-helpers.bash)"
echo "scenario C PASS: structure (append gone / temp+move atomic / slice filter / fail-closed branch / dry-run flag / pinned URL unique)"

# ---- sandbox scaffold (scenarios A and B) ----
function scaffold ()
{
    SB_DIR="$(mktemp -d)"
    mkdir -p "${SB_DIR}/cmd" "${SB_DIR}/static/odt-templates" "${SB_DIR}/bin/odt" "${SB_DIR}/client/md" "${SB_DIR}/tmp"
    cp "${REPO}/${CMD_REL}" "${SB_DIR}/cmd/"
    cp "${REPO}/static/odt-templates/o2k24-template.xml" "${SB_DIR}/static/odt-templates/"
    # the non-PE stub: plain text named setup.exe - cmd.exe refuses to execute
    # it with a non-zero errorlevel (the silent rc=0 no-op is an MSYS-bash
    # artifact; here cmd.exe is the executor, per the phase 16 probe)
    printf 'this is not a PE binary - ODT stub for the fail-closed battery\n' > "${SB_DIR}/bin/odt/setup.exe"
    # no bin/wget*.exe in the sandbox: the ODT freshness check (warn-only)
    # takes its documented offline skip line instead of probing the network
    SB_WIN="$(cygpath -w "${SB_DIR}")"
    [ -n "${SB_WIN}" ] || fail "cygpath could not translate the sandbox path"
    TEMP_WIN="${SB_WIN}\\tmp"
}

# integrity guard: the battery must never write outside its sandbox - the
# working-tree bytes it reads (staging engine, template, vendored ODT, real
# integrity file if present) must be byte-identical after the run
function guard_before ()
{
    GUARD_CMD="$(sha256sum "${REPO}/${CMD_REL}" | cut -d' ' -f1)"
    GUARD_TPL="$(sha256sum "${REPO}/static/odt-templates/o2k24-template.xml" | cut -d' ' -f1)"
    GUARD_ODT=""
    [ -f "${REPO}/bin/odt/setup.exe" ] && GUARD_ODT="$(sha256sum "${REPO}/bin/odt/setup.exe" | cut -d' ' -f1)"
    GUARD_HASHES=""
    [ -f "${REPO}/client/md/${HASHES_NAME}" ] && GUARD_HASHES="$(sha256sum "${REPO}/client/md/${HASHES_NAME}" | cut -d' ' -f1)"
}

function guard_after ()
{
    [ "$(sha256sum "${REPO}/${CMD_REL}" | cut -d' ' -f1)" = "${GUARD_CMD}" ] \
        || fail "battery modified the working-tree staging engine (sandbox escape)"
    [ "$(sha256sum "${REPO}/static/odt-templates/o2k24-template.xml" | cut -d' ' -f1)" = "${GUARD_TPL}" ] \
        || fail "battery modified the working-tree ODT template (sandbox escape)"
    now_odt=""
    [ -f "${REPO}/bin/odt/setup.exe" ] && now_odt="$(sha256sum "${REPO}/bin/odt/setup.exe" | cut -d' ' -f1)"
    [ "${now_odt}" = "${GUARD_ODT}" ] \
        || fail "battery modified the working-tree bin/odt/setup.exe (sandbox escape)"
    now_hashes=""
    [ -f "${REPO}/client/md/${HASHES_NAME}" ] && now_hashes="$(sha256sum "${REPO}/client/md/${HASHES_NAME}" | cut -d' ' -f1)"
    [ "${now_hashes}" = "${GUARD_HASHES}" ] \
        || fail "battery modified the working-tree integrity file (sandbox escape)"
}

function assert_no_residue ()
{
    local scen="$1"
    set -- "${SB_DIR}/tmp/"odt-config-*
    [ -f "$1" ] && fail "scenario ${scen}: the generated config manifest was not cleaned up in the pinned temp"
    echo "scenario ${scen}: no config manifest residue in the pinned sandbox temp"
}

# NOTE: the command line is passed to cmd //c as ONE string. Passing the args
# separately makes MSYS convert the flag-shaped argument "/dry-run" into a
# Windows path ("C:/Program Files/Git/dry-run") before cmd ever sees it.
# ---- scenario A: fail-closed bite (real run, dead ODT stub) ----
scaffold
guard_before
( cd "${SB_DIR}" && TEMP="${TEMP_WIN}" TMP="${TEMP_WIN}" \
    cmd //c 'cmd\DownloadOfficeC2R.cmd o2k24 x64 en-us' > run.log 2>&1 )
rc=$?
[ "${rc}" -ne 0 ] \
    || fail "scenario A: the real run EXITED 0 with a dead ODT stub - the pre-fix soft-fail is still alive"
[ ! -f "${SB_DIR}/client/md/${HASHES_NAME}" ] \
    || fail "scenario A: the failed run still wrote the integrity file"
grep -qi 'exited with code' "${SB_DIR}/run.log" \
    || fail "scenario A: no structured ODT exit-code error in the run log"
grep -qi 'fail-closed' "${SB_DIR}/run.log" \
    || fail "scenario A: the failure is not announced as fail-closed in the run log"
echo "scenario A PASS: dead ODT stub -> rc ${rc} (non-zero), no integrity file (pre-fix: Warning + rc 0)"
assert_no_residue A

# ---- scenario B: /dry-run lenience, rc 0, STILL no integrity file ----
scaffold
( cd "${SB_DIR}" && TEMP="${TEMP_WIN}" TMP="${TEMP_WIN}" \
    cmd //c 'cmd\DownloadOfficeC2R.cmd o2k24 x64 en-us /dry-run' > run.log 2>&1 )
rc=$?
[ "${rc}" -eq 0 ] || fail "scenario B: the /dry-run run exited ${rc}, expected 0"
[ ! -f "${SB_DIR}/client/md/${HASHES_NAME}" ] \
    || fail "scenario B: the dry-run wrote a ghost integrity file"
grep -qi 'dry-run' "${SB_DIR}/run.log" \
    || fail "scenario B: the dry-run lenience is not announced in the run log"
echo "scenario B PASS: /dry-run -> rc 0, no integrity file (no ghost hash file)"
assert_no_residue B

# ---- scenario D: live atomic slice rewrite on an ODT success ----
# A stand-in that EXITS 0 drives the engine through the real success path
# (no stock System32 PE exits 0 with "/download" arguments, so the stand-in
# is compiled offline with the OS-bundled .NET Framework csc). The payload
# and a pre-seeded integrity file with sibling entries prove the rewrite
# semantics: the stale product/arch slice entry is replaced, entries of other
# products AND of the other architecture of the same product survive, the
# line format stays "hash *path" lowercase hex, and no temp file is left.
CSC=""
for c in /c/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe \
         /c/Windows/Microsoft.NET/Framework/v4.0.30319/csc.exe; do
    [ -f "${c}" ] && CSC="${c}" && break
done
if [ -z "${CSC}" ]; then
    echo "SKIP scenario D: no OS-bundled csc.exe found - atomic rewrite not exercised live on this host"
else
    scaffold
    STANDIN_DIR="$(mktemp -d)"
    printf 'class OdtStandIn { static int Main() { return 0; } }\n' > "${STANDIN_DIR}/odt.cs"
    STANDIN_WIN="$(cygpath -w "${STANDIN_DIR}")"
    if ! "${CSC}" -nologo "-out:${STANDIN_WIN}\\standin.exe" "${STANDIN_WIN}\\odt.cs" > "${STANDIN_DIR}/csc.log" 2>&1; then
        echo "SKIP scenario D: stand-in compilation failed - $(head -1 "${STANDIN_DIR}/csc.log")"
        rm -rf "${STANDIN_DIR}" "${SB_DIR}"
    else
        cp "${STANDIN_DIR}/standin.exe" "${SB_DIR}/bin/odt/setup.exe"
        mkdir -p "${SB_DIR}/client/office/c2r/o2k24/x64/Office"
        printf 'fake C2R payload marker\n' > "${SB_DIR}/client/office/c2r/o2k24/x64/metadata.ini"
        printf 'fake nested payload\n' > "${SB_DIR}/client/office/c2r/o2k24/x64/Office/Data.v64"
        h_a="$(printf 'a%.0s' {1..64})"
        h_b="$(printf 'b%.0s' {1..64})"
        h_c="$(printf 'c%.0s' {1..64})"
        {
            printf '%s *client/office/c2r/o2k21/x64/metadata.ini\n' "${h_a}"
            printf '%s *client/office/c2r/o2k24/x64/old-payload.ini\n' "${h_b}"
            printf '\n'
            printf '%s *client/office/c2r/o2k24/x86/metadata.ini\n' "${h_c}"
        } > "${SB_DIR}/client/md/${HASHES_NAME}"
        ( cd "${SB_DIR}" && TEMP="${TEMP_WIN}" TMP="${TEMP_WIN}" \
            cmd //c 'cmd\DownloadOfficeC2R.cmd o2k24 x64 en-us' > run.log 2>&1 )
        rc=$?
        [ "${rc}" -eq 0 ] || fail "scenario D: the success run exited ${rc}, expected 0"
        [ -f "${SB_DIR}/client/md/${HASHES_NAME}" ] \
            || fail "scenario D: the success run wrote no integrity file"
        [ "$(grep -c "${h_b} \*client/office/c2r/o2k24/x64/" "${SB_DIR}/client/md/${HASHES_NAME}")" -eq 0 ] \
            || fail "scenario D: the STALE o2k24/x64 slice entry survived the rewrite (append semantics still alive)"
        grep -qF "${h_a} *client/office/c2r/o2k21/x64/metadata.ini" "${SB_DIR}/client/md/${HASHES_NAME}" \
            || fail "scenario D: the o2k21 sibling entry was dropped (slice filter too wide)"
        grep -qF "${h_c} *client/office/c2r/o2k24/x86/metadata.ini" "${SB_DIR}/client/md/${HASHES_NAME}" \
            || fail "scenario D: the o2k24/x86 sibling entry was dropped (slice filter is product-wide, not product/arch)"
        n_new="$(grep -cE "^[a-f0-9]{64} \*client/office/c2r/o2k24/x64/" "${SB_DIR}/client/md/${HASHES_NAME}")"
        [ "${n_new}" -eq 2 ] \
            || fail "scenario D: expected 2 lowercase-hex slice entries (metadata.ini + nested Office/Data.v64), got ${n_new}"
        [ ! -f "${SB_DIR}/client/md/${HASHES_NAME}.tmp" ] \
            || fail "scenario D: atomic temp file left behind (move never happened)"
        echo "scenario D PASS: live atomic rewrite - stale slice replaced, 2 sibling entries (o2k21 + o2k24/x86) survived, no temp residue"
        rm -rf "${STANDIN_DIR}" "${SB_DIR}"
    fi
fi

guard_after
rm -rf "${SB_DIR}"
unset SB_DIR
echo "PASS office-c2r failclosed battery (A fail-closed bite with a non-PE stub / B /dry-run lenience without ghost file / C atomic slice rewrite structure / D live atomic rewrite with sibling survival, offline, sandboxed)"
