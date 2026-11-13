#!/usr/bin/env bash
# =======================================================================
# WSUS Offline Update - UUP Upgrade Payload Acquisition Battery (Bash)
# File: sh/tests/verify-upgrade-payloads.bash
#
# Plan 33-03 task 2 battery (ACQ-02 + the sha256 half of ACQ-04): the
# download-side extensions of sh/libraries/upgrade-payloads.bash and the
# section logic of sh/download-updates-tasks/62-upgrade-payloads.bash.
# Sandbox only - NO network, NO API calls, NO real downloader: the
# downloaders are sandbox no-op stubs and the payload bytes are locally
# generated fixture files. Every case is a can-fail bite.
#
#   A. Classification boundaries (uup_classify_size): 104857600 -> aria2
#      (exactly at), 104857599 -> wget (one below), 10902883408 -> aria2
#      (the 11-digit value that would wrap 32-bit arithmetic), invalid
#      size refused.
#   B. The real task 62 sourced with no selection file: byte-invisible
#      no-op (empty output, zero side effects, no spool).
#   C. fu_media gate over the real committed upgrades.txt (sandbox copy):
#      a fu_media=0 selection and a missing-row selection both no-op
#      silently; the fu_media=1 selection gets as far as the budget line
#      over the golden fixture seam (DEC-33-12) - the budget figure is
#      the manifest's own total_mib (10397, the DEC-33-02 formula value),
#      the manifest lands in the spool, and the section aborts at the
#      join (a fixture resolve emits no url map) with the error counted.
#   D. Hash-gate positive / corrupt-byte / truncated cases (fixture spool
#      + manifest derived from the placed bytes).
#   E. Orchestrated download over fixture url map + stub downloaders:
#      budget line precedes the first stub call, the hash gate runs, the
#      spool files stay in place, and the token-bearing artifacts (url
#      map + downloader lists) are deleted afterwards.
#   F. DEC-33-15 https-first/http-fallback: an https-refusing stub still
#      ends green through the bounded http retry.
#   G. Loud abort + cleanup when both schemes fail.
#   H. aria2 unavailable: the section refuses to download a multi-GiB
#      payload non-resumably (loud signal, error counted; environment-
#      gated by a named marker when aria2c IS on PATH).
#
# Plan 33-04 sections (staging + purge), appended, existing sections
# untouched:
#   I. Staging the verified raw set (real create_integrity_database):
#      set/ + manifest + integrity class + the loud Windows-only note
#   J. Replacement-deletion timing: old revision aside in the spool and
#      deleted only after the new set reads back (delete-after-success)
#   K. Purge trio with the kept-set assertion: sole revision 0 removals /
#      stale pair removed exactly while the staged-uuid keep set survives /
#      failed-staging simulation removes nothing
#   L. The no-image-tool source pin: the task file never names the image
#      tooling (case-insensitive zero)
#
# Success sentinel: UPG-PAYLOADS-BASH-PASS. Every failure prints a FAIL:
# line and exits 1.
# =======================================================================

set -e
set -u
export LC_ALL=C
# The messages library folds log lines at ${COLUMNS} - a narrow default
# would wrap the asserted lines mid-needle in this non-tty subshell
export COLUMNS=200

if [ -d "/usr/bin" ] && [[ ":$PATH:" != *":/usr/bin:"* ]]; then
    export PATH="/usr/bin:$PATH"
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
cd "$repo_root"

echo "======================================================================="
echo "WSUS Offline Update - UUP Upgrade Payload Acquisition Battery (Bash)"
echo "======================================================================="

tmp_dir="$(mktemp -d 2>/dev/null || mktemp -d -t 'wou_upg_test')"
trap 'rm -rf "$tmp_dir"' EXIT

# Sandbox hygiene: a previous battery run (or a real engine run) may have
# left the default DEC-33-14 spool root behind - Section B asserts its
# absence, so start from the known state
rm -rf "${TMPDIR:-/tmp}/wou-upgrade-spool" /tmp/wou-upgrade-spool

sb_sh="${tmp_dir}/sh"
sb_fix="${tmp_dir}/fixtures"
sb_stubs="${tmp_dir}/stubs"
mkdir -p "${sb_sh}" "${sb_fix}" "${sb_stubs}"

library_file="${repo_root}/sh/libraries/upgrade-payloads.bash"
task_file="${repo_root}/sh/download-updates-tasks/62-upgrade-payloads.bash"
golden_fixture="${repo_root}/tests/fixtures/uup-get-26200-en-us-multiedition.json"
hashdeep_bin="${repo_root}/client/bin/hashdeep64.exe"

for required in "${library_file}" "${task_file}" "${golden_fixture}"; do
    if [[ ! -f "${required}" ]]; then
        printf 'FAIL: required file missing: %s\n' "${required}"
        exit 1
    fi
done

# Library + engine-adjacent functions (the battery never sources the
# downloaders common task: its Commands section probes the network; the
# two real UUP arrays are extracted from the file instead)
# shellcheck source=/dev/null
source "${library_file}"
# shellcheck source=/dev/null
source "${repo_root}/sh/libraries/upgrade-selection.bash"
# shellcheck source=/dev/null
source "${repo_root}/sh/libraries/messages.bash"
# shellcheck source=/dev/null
source "${repo_root}/sh/libraries/error-counter.bash"
# The staging tail (plan 33-04) calls the REAL create_integrity_database -
# source it and its two dependencies (unix_to_dos, require_directory)
# shellcheck source=/dev/null
source "${repo_root}/sh/libraries/dos-files.bash"
# shellcheck source=/dev/null
source "${repo_root}/sh/libraries/files-and-folders.bash"
# shellcheck source=/dev/null
source "${repo_root}/sh/libraries/integrity-database.bash"
logfile="${tmp_dir}/battery.log"
debug="disabled"
fast_mode="disabled"
use_integrity_database="enabled"

# create_integrity_database invokes plain `hashdeep` from PATH - the
# sandbox prepends a wrapper resolving to the repo's vendored binary
sb_bin="${tmp_dir}/bin"
mkdir -p "${sb_bin}"
cat > "${sb_bin}/hashdeep" <<WRAPPER
#!/usr/bin/env bash
exec "${repo_root}/client/bin/hashdeep64.exe" "\$@"
WRAPPER
chmod +x "${sb_bin}/hashdeep"
export PATH="${sb_bin}:${PATH}"

if ! declare -F read_upgrade_selection > /dev/null; then
    printf 'FAIL: upgrade-selection.bash does not provide read_upgrade_selection\n'
    exit 1
fi
if ! declare -F increment_error_count > /dev/null; then
    printf 'FAIL: error-counter.bash does not provide increment_error_count\n'
    exit 1
fi

# Source the real task file in the battery shell (cwd = repo root, no
# selection file): the section's own no-selection run must be
# byte-invisible (Section B) and its functions become callable below.
source "${task_file}" > "${tmp_dir}/task-setup.log" 2>&1
if ! declare -F uup_download_and_verify > /dev/null; then
    printf 'FAIL: task 62 does not define uup_download_and_verify\n'
    exit 1
fi

# The real UUP option arrays, evaluated from the common task file (array
# blocks only - never its Commands)
array_source="$(sed -n '/^aria2c_uup_options=($/,/^)$/p; /^wget_uup_options=($/,/^)$/p' \
    "${repo_root}/sh/common-tasks/40-configure-downloaders.bash")"
eval "${array_source}"
aria2c_uup_options_count="${#aria2c_uup_options[@]}"
wget_uup_options_count="${#wget_uup_options[@]}"
if (( aria2c_uup_options_count < 5 )) || (( wget_uup_options_count < 2 )); then
    printf 'FAIL: the UUP option arrays did not evaluate from 40-configure-downloaders.bash\n'
    exit 1
fi

battery_pass=0
assert_eq() {
    local actual="$1" expected="$2" desc="$3"
    if [[ "${actual}" != "${expected}" ]]; then
        printf 'FAIL: %s (expected "%s", got "%s")\n' "${desc}" "${expected}" "${actual}"
        exit 1
    fi
    battery_pass=$(( battery_pass + 1 ))
}

expect_contains() {
    local haystack_file="$1" needle="$2" desc="$3"
    if ! grep -qF -- "${needle}" "${haystack_file}"; then
        printf 'FAIL: %s - "%s" not found in %s\n' "${desc}" "${needle}" "${haystack_file}"
        exit 1
    fi
    battery_pass=$(( battery_pass + 1 ))
}

expect_absent() {
    local haystack_file="$1" needle="$2" desc="$3"
    if grep -qF -- "${needle}" "${haystack_file}"; then
        printf 'FAIL: %s - "%s" must not appear in %s\n' "${desc}" "${needle}" "${haystack_file}"
        exit 1
    fi
    battery_pass=$(( battery_pass + 1 ))
}

# -----------------------------------------------------------------------
# Fixture payloads: the manifest is DERIVED from the placed bytes
# -----------------------------------------------------------------------

big_file="${sb_fix}/big.esd"
small_file="${sb_fix}/small.cab"
head -c 104857600 /dev/zero > "${big_file}"
printf 'B%.0s' $(seq 1 100) > "${small_file}"
big_size="$(stat -c %s "${big_file}")"
small_size="$(stat -c %s "${small_file}")"
assert_eq "${big_size}" "104857600" "big.esd fixture size"
big_hash="$(sha256sum "${big_file}" | cut -d' ' -f1)"
small_hash="$(sha256sum "${small_file}" | cut -d' ' -f1)"

# Manifest + url map builders (the url map is a TEMP runtime artifact in
# the sandbox - never committed)

build_manifest() {
    local out="$1"
    {
        printf '%s\n' '# fixture acquisition manifest for the plan 33-03 battery'
        printf '%s\n' 'updateName|Battery Test Set'
        printf '%s\n' 'uuid|00000000-0000-0000-0000-000000000000'
        printf '%s\n' 'arch|amd64'
        printf '%s\n' 'lang|en-us'
        printf '%s\n' 'build|26200.9974'
        printf 'total_bytes|%s\n' "$(( big_size + small_size ))"
        total_mib=$(( (big_size + small_size) / 1048576 ))
        printf 'total_mib|%s\n' "${total_mib}"
        printf 'small.cab|%s|%s\n' "${small_hash}" "${small_size}"
        printf 'big.esd|%s|%s\n' "${big_hash}" "${big_size}"
    } > "${out}"
}

build_urlmap() {
    local out="$1"
    printf 'small.cab\thttps://tlu.dl.delivery.mp.microsoft.com/filestreamingservice/files/11111111-1111-1111-1111-111111111111?P1=1794420000&P2=404&P3=2&P4=sigsmall\n' > "${out}"
    printf 'big.esd\thttps://tlu.dl.delivery.mp.microsoft.com/filestreamingservice/files/22222222-2222-2222-2222-222222222222?P1=1794420000&P2=404&P3=2&P4=sigbig\n' >> "${out}"
}

# Downloader stubs (sandbox no-ops)

cat > "${sb_stubs}/aria2-stub.bash" <<'STUB'
#!/usr/bin/env bash
mode="${STUB_MODE:-OK}"
list=""
prev=""
for a in "$@"
do
    if [[ "${prev}" == "-i" ]]
    then
        list="${a}"
    fi
    prev="${a}"
done
if [[ -n "${list}" ]] && grep -q 'https://' "${list}" 2> /dev/null && [[ "${mode}" == "HTTPS-FAILS" ]]
then
    exit 1
fi
if [[ "${mode}" == "ALWAYS-FAILS" ]]
then
    exit 1
fi
if [[ -n "${STUB_CAPTURE:-}" && -n "${list}" ]]
then
    cp "${list}" "${STUB_CAPTURE}"
fi
echo "ARIA2-STUB-DOWNLOAD"
exit 0
STUB
cat > "${sb_stubs}/wget-stub.bash" <<'STUB'
#!/usr/bin/env bash
mode="${STUB_MODE:-OK}"
has_https=0
for a in "$@"
do
    case "${a}" in
        https://*) has_https=1 ;;
    esac
done
if [[ "${has_https}" == "1" ]] && [[ "${mode}" == "HTTPS-FAILS" ]]
then
    exit 1
fi
if [[ "${mode}" == "ALWAYS-FAILS" ]]
then
    exit 1
fi
echo "WGET-STUB-DOWNLOAD"
exit 0
STUB
chmod +x "${sb_stubs}/aria2-stub.bash" "${sb_stubs}/wget-stub.bash"

# The committed upgrades.txt copy for the fu_media gate (real frozen data,
# read through the sandbox copy only)
cp "${repo_root}/client/UpdateTable/upgrades.txt" "${sb_fix}/upgrades.txt"

# -----------------------------------------------------------------------
# A. Classification boundaries
# -----------------------------------------------------------------------
echo "--- Section A: classification boundaries (native 64-bit) ---"
assert_eq "$(uup_classify_size 104857600)" "aria2" "104857600 classifies aria2 (exactly at the threshold)"
assert_eq "$(uup_classify_size 104857599)" "wget" "104857599 classifies wget (one below the threshold)"
assert_eq "$(uup_classify_size 10902883408)" "aria2" "the 11-digit 10902883408 total classifies aria2"
if uup_classify_size abc > /dev/null 2>&1; then
    printf 'FAIL: a non-numeric size must be refused\n'
    exit 1
fi
battery_pass=$(( battery_pass + 1 ))
echo "[A] classification boundaries green, invalid size refused."

# -----------------------------------------------------------------------
# B. The real task sourced with NO selection file - byte-invisible no-op
# -----------------------------------------------------------------------
echo "--- Section B: no-selection no-op (real task 62 sourced) ---"
assert_eq "$(cat "${tmp_dir}/task-setup.log")" "" "task 62 with no selection file produces zero output"
assert_eq "${runtime_errors}" "0" "the no-op increments no errors"
if [[ -d "${HOME}/wou-upgrade-spool" || -d "/tmp/wou-upgrade-spool" ]]; then
    printf 'FAIL: the no-selection run must not create the default spool\n'
    exit 1
fi
battery_pass=$(( battery_pass + 1 ))
echo "[B] no selection = byte-invisible no-op, no spool."

# -----------------------------------------------------------------------
# C. fu_media gate over the real committed upgrades.txt (sandbox copy)
# -----------------------------------------------------------------------
echo "--- Section C: fu_media gate (1 / 0 / missing row) ---"

run_section() {
    # $1 = selection content. The fixture seam is pinned for EVERY
    # section invocation: no battery path may ever reach the live API.
    # The section runs in a command-substitution subshell (to capture
    # its output), so the error counter is persisted to files from
    # INSIDE the subshell - parent-side variables would be lost.
    local selection_content="$1"
    printf '%s\n' "${selection_content}" > "${sb_sh}/os-upgrades.ini"
    local out_file="${tmp_dir}/section-out-$$.log"
    local rc=0
    (
        cd "${sb_sh}" || exit 9
        UUP_UPGRADES_TABLE="${sb_fix}/upgrades.txt"
        WOU_UPGRADE_SPOOL="${tmp_dir}/spool-c"
        WOU_UUP_FIXTURE="${golden_fixture}"
        export UUP_UPGRADES_TABLE WOU_UPGRADE_SPOOL WOU_UUP_FIXTURE
        printf '%s' "${runtime_errors}" > "${tmp_dir}/errors-before.txt"
        source "${task_file}"
        printf '%s' "${runtime_errors}" > "${tmp_dir}/errors-after.txt"
    ) > "${out_file}" 2>&1 || rc=$?
    printf '%s' "${rc}"
}

rc="$(run_section "19045_x64=on")"
assert_eq "${rc}" "0" "the fu_media=0 selection ends green"
assert_eq "$(cat "${tmp_dir}/section-out-$$.log")" "" "the fu_media=0 selection is a silent no-op"
if [[ -d "${tmp_dir}/spool-c" ]]; then
    printf 'FAIL: the fu_media=0 selection must not create the spool\n'
    exit 1
fi
battery_pass=$(( battery_pass + 1 ))
echo "[C] fu_media=0 row answers the no-op path."

rc="$(run_section "99999_x64=on")"
assert_eq "${rc}" "0" "the missing-row selection ends green"
assert_eq "$(cat "${tmp_dir}/section-out-$$.log")" "" "the missing-row selection is a silent no-op"
battery_pass=$(( battery_pass + 1 ))
echo "[C] missing row answers the no-op path."

rc="$(run_section "26200_x64=on")"
assert_eq "${rc}" "0" "the fu_media=1 selection ends green (fixture-mode abort is counted, not fatal)"
section_c_log="${tmp_dir}/section-out-$$.log"
expect_contains "${section_c_log}" "BUDGET: 196 files, 10902883408 bytes, 10397 MiB" "the budget line names the manifest totals (DEC-33-02 formula value)"
if [[ ! -f "${tmp_dir}/spool-c/manifest.txt" ]]; then
    printf 'FAIL: the fu_media=1 run must land the resolved manifest in the spool\n'
    exit 1
fi
battery_pass=$(( battery_pass + 1 ))
errors_c=$(( $(cat "${tmp_dir}/errors-after.txt") - $(cat "${tmp_dir}/errors-before.txt") ))
assert_eq "${errors_c}" "1" "the fixture-mode join abort increments exactly one error"
echo "[C] fu_media=1 reaches the budget line over the golden fixture seam."

# -----------------------------------------------------------------------
# D. Hash-gate positive / corrupt / truncated
# -----------------------------------------------------------------------
echo "--- Section D: hash gate (positive / corrupt / truncated) ---"

manifest_d="${sb_fix}/manifest.txt"
build_manifest "${manifest_d}"

spool_d="${tmp_dir}/spool-d"
mkdir -p "${spool_d}"
cp "${big_file}" "${spool_d}/big.esd"
cp "${small_file}" "${spool_d}/small.cab"
if UUP_HASHDEEP_BIN="${hashdeep_bin}" uup_hash_gate "${manifest_d}" "${spool_d}" > "${tmp_dir}/hg-pos.log" 2>&1
then
    battery_pass=$(( battery_pass + 1 ))
else
    printf 'FAIL: the matching spool must pass the hash gate:\n'
    cat "${tmp_dir}/hg-pos.log"
    exit 1
fi
echo "[D] hash gate positive."

spool_d2="${tmp_dir}/spool-d2"
mkdir -p "${spool_d2}"
cp "${big_file}" "${spool_d2}/big.esd"
printf 'B%.0sC' $(seq 1 99) > "${spool_d2}/small.cab"
if UUP_HASHDEEP_BIN="${hashdeep_bin}" uup_hash_gate "${manifest_d}" "${spool_d2}" > /dev/null 2>&1
then
    printf 'FAIL: a corrupted payload must be refused\n'
    exit 1
fi
if [[ ! -f "${spool_d2}/small.cab" ]]; then
    printf 'FAIL: the corrupt case must not move or delete spool files\n'
    exit 1
fi
battery_pass=$(( battery_pass + 1 ))
echo "[D] corrupt spool refused, nothing moved."

spool_d3="${tmp_dir}/spool-d3"
mkdir -p "${spool_d3}"
cp "${big_file}" "${spool_d3}/big.esd"
printf 'B%.0s' $(seq 1 50) > "${spool_d3}/small.cab"
if UUP_HASHDEEP_BIN="${hashdeep_bin}" uup_hash_gate "${manifest_d}" "${spool_d3}" > /dev/null 2>&1
then
    printf 'FAIL: a truncated payload must be refused even though a resume succeeded\n'
    exit 1
fi
battery_pass=$(( battery_pass + 1 ))
echo "[D] truncated spool refused."

# -----------------------------------------------------------------------
# E. Orchestrated download over fixture url map + stubs
# -----------------------------------------------------------------------
echo "--- Section E: orchestrated download (budget first, cleanup) ---"

spool_e="${tmp_dir}/spool-e"
files_e="${spool_e}/files"
mkdir -p "${files_e}"
cp "${big_file}" "${files_e}/big.esd"
cp "${small_file}" "${files_e}/small.cab"
urlmap_e="${spool_e}/url-map.tmp"
build_urlmap "${urlmap_e}"

export STUB_MODE="OK"
export UUP_ARIA2_BIN="${sb_stubs}/aria2-stub.bash"
export UUP_WGET_BIN="${sb_stubs}/wget-stub.bash"
export UUP_HASHDEEP_BIN="${hashdeep_bin}"
if uup_download_and_verify "${manifest_d}" "${urlmap_e}" "${files_e}" > "${tmp_dir}/orch.log" 2>&1
then
    battery_pass=$(( battery_pass + 1 ))
else
    printf 'FAIL: the orchestrated case must end green over matching stubs:\n'
    cat "${tmp_dir}/orch.log"
    exit 1
fi
budget_line="$(grep -n 'BUDGET:' "${tmp_dir}/orch.log" | head -1 | cut -d: -f1)"
stub_line="$(grep -n 'resume-tuned via aria2' "${tmp_dir}/orch.log" | head -1 | cut -d: -f1)"
if [[ -z "${budget_line}" || -z "${stub_line}" ]] || (( budget_line >= stub_line )); then
    printf 'FAIL: the budget line must precede the first downloader invocation\n'
    cat "${tmp_dir}/orch.log"
    exit 1
fi
battery_pass=$(( battery_pass + 1 ))
expect_contains "${tmp_dir}/orch.log" "Audit passed" "the hash gate runs over the orchestrated spool"
# The downloader console markers land in the SPOOL SCRATCH run logs
# (live-UAT 33 finding #5 token confinement), not in the engine stdout
expect_contains "${spool_e}/aria2-run.log" "ARIA2-STUB-DOWNLOAD" "the aria2 console output lands in the spool scratch aria2-run.log"
expect_contains "${spool_e}/wget-run.log" "WGET-STUB-DOWNLOAD" "the small payload list goes through wget (output in the scratch run log)"
if [[ ! -f "${files_e}/big.esd" || ! -f "${files_e}/small.cab" ]]; then
    printf 'FAIL: the orchestration must not move spool files\n'
    exit 1
fi
if [[ -f "${urlmap_e}" || -f "${spool_e}/join.tmp" || -f "${spool_e}/aria2-list.tmp" || -f "${spool_e}/wget-list.tmp" ]]; then
    printf 'FAIL: token-bearing artifacts must be deleted after the run\n'
    exit 1
fi
battery_pass=$(( battery_pass + 1 ))
echo "[E] budget-first order, hash gate ran, spool intact, temp artifacts deleted."

# -----------------------------------------------------------------------
# F. https-first / http-fallback (DEC-33-15)
# -----------------------------------------------------------------------
echo "--- Section F: https-first / http-fallback ---"

export STUB_MODE="HTTPS-FAILS"
spool_f="${tmp_dir}/spool-f"
files_f="${spool_f}/files"
mkdir -p "${files_f}"
cp "${big_file}" "${files_f}/big.esd"
cp "${small_file}" "${files_f}/small.cab"
build_urlmap "${spool_f}/url-map.tmp"
if uup_download_and_verify "${manifest_d}" "${spool_f}/url-map.tmp" "${files_f}" > "${tmp_dir}/orch-f.log" 2>&1
then
    battery_pass=$(( battery_pass + 1 ))
else
    printf 'FAIL: the https-refusing stub must still end green through the http fallback:\n'
    cat "${tmp_dir}/orch-f.log"
    exit 1
fi
expect_contains "${tmp_dir}/orch-f.log" "falling back to the original http URLs" "the aria2 http fallback fires"
expect_contains "${tmp_dir}/orch-f.log" "http fallback" "the wget http fallback fires"
echo "[F] bounded https-first, http-fallback transport proven."

# -----------------------------------------------------------------------
# G. Loud abort + cleanup when both schemes fail
# -----------------------------------------------------------------------
echo "--- Section G: loud abort on both-schemes failure ---"

export STUB_MODE="ALWAYS-FAILS"
spool_g="${tmp_dir}/spool-g"
files_g="${spool_g}/files"
mkdir -p "${files_g}"
cp "${big_file}" "${files_g}/big.esd"
cp "${small_file}" "${files_g}/small.cab"
build_urlmap "${spool_g}/url-map.tmp"
errors_before_g="${runtime_errors}"
if uup_download_and_verify "${manifest_d}" "${spool_g}/url-map.tmp" "${files_g}" > "${tmp_dir}/orch-g.log" 2>&1
then
    printf 'FAIL: a downloader that fails both schemes must abort loudly\n'
    exit 1
fi
battery_pass=$(( battery_pass + 1 ))
expect_contains "${tmp_dir}/orch-g.log" "failed on both schemes" "the loud both-schemes line fires"
if [[ -f "${spool_g}/url-map.tmp" ]]; then
    printf 'FAIL: the failure path must delete the url map too\n'
    exit 1
fi
errors_g=$(( runtime_errors - errors_before_g ))
assert_eq "${errors_g}" "1" "the both-schemes failure increments exactly one error"
echo "[G] loud abort, url map deleted on the failure path."

# -----------------------------------------------------------------------
# G2. Downloader list shape pin can-fail (live-UAT 33 finding #5): a
#     glued multi-token URL (local paths riding the URI line) must refuse
#     the acquisition BEFORE any downloader runs, on both list sides.
# -----------------------------------------------------------------------
echo "--- Section G2: downloader list shape pin can-fail (aria + wget sides) ---"

export STUB_MODE="OK"
build_urlmap_hostile_aria() {
    local out="$1"
    printf 'small.cab\thttps://tlu.dl.delivery.mp.microsoft.com/filestreamingservice/files/11111111-1111-1111-1111-111111111111?P1=1794420000&P2=404&P3=2&P4=sigsmall\n' > "${out}"
    printf 'big.esd\thttps://tlu.dl.delivery.mp.microsoft.com/filestreamingservice/files/22222222-2222-2222-2222-222222222222?P1=1794420000&P2=404&P3=2&P4=sigbig C:\\Users\\x\\AppData\\Local\\Temp\\wou-upgrade-spool\\url-map.tmp C:\\Users\\x\\AppData\\Local\\Temp\\wou-upgrade-spool\\filesd:\n' >> "${out}"
}
build_urlmap_hostile_wget() {
    local out="$1"
    printf 'small.cab\thttps://tlu.dl.delivery.mp.microsoft.com/filestreamingservice/files/11111111-1111-1111-1111-111111111111?P1=1794420000&P2=404&P3=2&P4=sigsmall C:\\Users\\x\\AppData\\Local\\Temp\\wou-upgrade-spool\\filesd:\n' > "${out}"
    printf 'big.esd\thttps://tlu.dl.delivery.mp.microsoft.com/filestreamingservice/files/22222222-2222-2222-2222-222222222222?P1=1794420000&P2=404&P3=2&P4=sigbig\n' >> "${out}"
}

# Live-UAT 33 finding #6: the wget-normalized glue shape - %5C rides the
# frozen URI charset (% is a legal URL byte), so the grammar alone misses
# it; the pin refuses the sequence on its own terms.
build_urlmap_hostile_wget_5c() {
    local out="$1"
    printf 'small.cab\thttps://tlu.dl.delivery.mp.microsoft.com/filestreamingservice/files/11111111-1111-1111-1111-111111111111?P1=1794420000&P2=404&P3=2&P4=sigsmall%%5CUsers%%5Cx%%5Curl-map.tmpbGZGr8GQ9bEd7\n' > "${out}"
    printf 'big.esd\thttps://tlu.dl.delivery.mp.microsoft.com/filestreamingservice/files/22222222-2222-2222-2222-222222222222?P1=1794420000&P2=404&P3=2&P4=sigbig\n' >> "${out}"
}

for hostile_case in aria wget wget-pct5c
do
    spool_p="${tmp_dir}/spool-pin-${hostile_case}"
    files_p="${spool_p}/files"
    mkdir -p "${files_p}"
    cp "${big_file}" "${files_p}/big.esd"
    cp "${small_file}" "${files_p}/small.cab"
    if [[ "${hostile_case}" == "aria" ]]
    then
        build_urlmap_hostile_aria "${spool_p}/url-map.tmp"
    elif [[ "${hostile_case}" == "wget-pct5c" ]]
    then
        build_urlmap_hostile_wget_5c "${spool_p}/url-map.tmp"
    else
        build_urlmap_hostile_wget "${spool_p}/url-map.tmp"
    fi
    errors_before_p="${runtime_errors}"
    if uup_download_and_verify "${manifest_d}" "${spool_p}/url-map.tmp" "${files_p}" > "${tmp_dir}/orch-pin-${hostile_case}.log" 2>&1
    then
        printf 'FAIL: the glued %s-side URL must be refused by the shape pin\n' "${hostile_case}"
        cat "${tmp_dir}/orch-pin-${hostile_case}.log"
        exit 1
    fi
    battery_pass=$(( battery_pass + 1 ))
    expect_contains "${tmp_dir}/orch-pin-${hostile_case}.log" "shape pin refused" "the ${hostile_case}-side refusal names the shape pin"
    expect_absent "${tmp_dir}/orch-pin-${hostile_case}.log" "STUB-DOWNLOAD" "the ${hostile_case}-side pin refuses BEFORE any downloader runs"
    if [[ -f "${spool_p}/url-map.tmp" ]]; then
        printf 'FAIL: the pin refusal path must delete the url map too\n'
        exit 1
    fi
    errors_p=$(( runtime_errors - errors_before_p ))
    assert_eq "${errors_p}" "1" "the ${hostile_case}-side pin refusal increments exactly one error"
done
echo "[G2] glued aria-side, wget-side and %5C-encoded wget URLs refused fail-closed before any downloader ran."

# -----------------------------------------------------------------------
# G3. Downloader output confined to the spool scratch + the mandated
#     list shape (live-UAT 33 finding #5 token hygiene)
# -----------------------------------------------------------------------
echo "--- Section G3: downloader output confinement + list shape ---"

spool_t="${tmp_dir}/spool-hygiene"
files_t="${spool_t}/files"
mkdir -p "${files_t}"
cp "${big_file}" "${files_t}/big.esd"
cp "${small_file}" "${files_t}/small.cab"
build_urlmap "${spool_t}/url-map.tmp"
export STUB_CAPTURE="${tmp_dir}/aria-list-capture.txt"
if uup_download_and_verify "${manifest_d}" "${spool_t}/url-map.tmp" "${files_t}" > "${tmp_dir}/orch-hy.log" 2>&1
then
    battery_pass=$(( battery_pass + 1 ))
else
    printf 'FAIL: the hygiene case must end green over matching stubs:\n'
    cat "${tmp_dir}/orch-hy.log"
    exit 1
fi
expect_contains "${spool_t}/aria2-run.log" "ARIA2-STUB-DOWNLOAD" "the aria2 console output lands in the spool scratch aria2-run.log"
expect_contains "${spool_t}/wget-run.log" "WGET-STUB-DOWNLOAD" "the wget console output lands in the spool scratch wget-run.log"
expect_absent "${tmp_dir}/orch-hy.log" "P1=" "no token URL material reaches the engine log"
expect_absent "${tmp_dir}/orch-hy.log" "STUB-DOWNLOAD" "no downloader console output reaches the engine log"
# The written aria list: URI line + indented out= continuation (the
# mandated aria2 -i shape, byte-checked here)
if grep -qE '^https?://[A-Za-z0-9._~:/?&=%+-]+$' "${STUB_CAPTURE}"; then
    battery_pass=$(( battery_pass + 1 ))
else
    printf 'FAIL: the aria list URI line must match the frozen grammar\n'
    cat "${STUB_CAPTURE}"
    exit 1
fi
expect_contains "${STUB_CAPTURE}" "  out=big.esd" "the aria list carries the indented out= continuation"
unset STUB_CAPTURE || true
echo "[G3] downloader output confined to the spool scratch, mandated list shape pinned."

# -----------------------------------------------------------------------
# H. aria2 unavailable - never a silent downgrade of a multi-GiB payload
# -----------------------------------------------------------------------
echo "--- Section H: aria2 unavailable - loud refusal ---"

if type -P aria2c > /dev/null; then
    printf 'SKIP-ENV: aria2c is on PATH - the missing-binary case cannot run on this host\n'
else
    unset UUP_ARIA2_BIN || true
    spool_h="${tmp_dir}/spool-h"
    files_h="${spool_h}/files"
    mkdir -p "${files_h}"
    cp "${big_file}" "${files_h}/big.esd"
    cp "${small_file}" "${files_h}/small.cab"
    build_urlmap "${spool_h}/url-map.tmp"
    if uup_download_and_verify "${manifest_d}" "${spool_h}/url-map.tmp" "${files_h}" > "${tmp_dir}/orch-h.log" 2>&1
    then
        printf 'FAIL: the section must refuse to run big payloads without aria2\n'
        exit 1
    fi
    battery_pass=$(( battery_pass + 1 ))
    expect_contains "${tmp_dir}/orch-h.log" "refusing to download a multi-GiB payload non-resumably" "the no-wget-downgrade refusal fires"
    expect_absent "${tmp_dir}/orch-h.log" "ARIA2-STUB-DOWNLOAD" "no downloader ran in the aria2-missing case"
    echo "[H] aria2-missing loud refusal proven."
fi
export UUP_ARIA2_BIN="${sb_stubs}/aria2-stub.bash"
export UUP_WGET_BIN="${sb_stubs}/wget-stub.bash"
unset STUB_MODE || true

# -----------------------------------------------------------------------
# I. Staging the verified raw set (plan 33-04, DEC-33-05): set/ + manifest
#    + integrity class + the loud Windows-generator-only note
# -----------------------------------------------------------------------
echo "--- Section I: staging the verified raw set (real create_integrity_database) ---"

sb_client="${tmp_dir}/client"
mkdir -p "${sb_client}/md"
# The purge inside the staging tail resolves its spool root from this env -
# pin it to the sandbox so the default spool root is never created
export WOU_UPGRADE_SPOOL="${tmp_dir}/spool-i-root"
mkdir -p "${WOU_UPGRADE_SPOOL}"
spool_i="${tmp_dir}/spool-i"
files_i="${spool_i}/files"
mkdir -p "${files_i}"
cp "${big_file}" "${files_i}/big.esd"
cp "${small_file}" "${files_i}/small.cab"
build_manifest "${spool_i}/manifest.txt"

export UUP_CLIENT_ROOT="${sb_client}"
if uup_stage_raw_set 26200 x64 en-us "${spool_i}/manifest.txt" > "${tmp_dir}/stage-i.log" 2>&1
then
    battery_pass=$(( battery_pass + 1 ))
else
    printf 'FAIL: the staging of the verified raw set must end green:\n'
    cat "${tmp_dir}/stage-i.log"
    exit 1
fi
target_i="${sb_client}/upgrade/26200-x64/en-us"
assert_eq "$(ls "${target_i}/set")" "$(printf 'big.esd\nsmall.cab')" "the verified raw set is staged under set/"
if [[ ! -s "${target_i}/manifest.txt" ]]; then
    printf 'FAIL: the acquisition manifest must be staged beside the set\n'
    exit 1
fi
battery_pass=$(( battery_pass + 1 ))
db_i="${sb_client}/md/hashes-upgrade-26200-x64-en-us.txt"
if [[ ! -s "${db_i}" ]]; then
    printf 'FAIL: the media integrity class is missing: %s\n' "${db_i}"
    exit 1
fi
head -1 "${db_i}" | grep -q 'HASHDEEP-1.0' || {
    printf 'FAIL: the db file must carry the hashdeep header\n'
    exit 1
}
battery_pass=$(( battery_pass + 1 ))
expect_contains "${tmp_dir}/stage-i.log" "Assembly is Windows-generator-only" "the loud Windows-generator-only note fires"
expect_contains "${tmp_dir}/stage-i.log" "PURGE:" "the post-success purge runs last"
echo "[I] staging positive: set/ + manifest + integrity class + note."

# -----------------------------------------------------------------------
# J. Replacement-deletion timing: the old revision dies only after the
#    new one reads back (delete-after-success)
# -----------------------------------------------------------------------
echo "--- Section J: replacement-deletion timing ---"

target_j="${sb_client}/upgrade/26200-x64/en-us"
printf 'uuid|aaaaaaaa-0000-0000-0000-000000000000\n' > "${target_j}/manifest.txt"
printf 'OLD-REVISION\n' > "${target_j}/old-media.bin"
spool_j="${tmp_dir}/spool-j"
files_j="${spool_j}/files"
mkdir -p "${files_j}"
cp "${big_file}" "${files_j}/big.esd"
cp "${small_file}" "${files_j}/small.cab"
build_manifest "${spool_j}/manifest.txt"
export WOU_UPGRADE_SPOOL="${tmp_dir}/spool-root-j"
mkdir -p "${WOU_UPGRADE_SPOOL}"
if uup_stage_raw_set 26200 x64 en-us "${spool_j}/manifest.txt" > "${tmp_dir}/stage-j.log" 2>&1
then
    battery_pass=$(( battery_pass + 1 ))
else
    printf 'FAIL: the replacement staging must end green:\n'
    cat "${tmp_dir}/stage-j.log"
    exit 1
fi
grep -q 'uuid|bbbbbbbb' "${target_j}/manifest.txt" 2> /dev/null || true
if ! grep -qF 'uuid|' "${target_j}/manifest.txt"; then
    printf 'FAIL: the staged manifest must be present\n'
    exit 1
fi
staged_j_uuid="$(awk -F'|' '$1 == "uuid" { print $2; exit }' "${target_j}/manifest.txt")"
expected_j_uuid="$(awk -F'|' '$1 == "uuid" { print $2; exit }' "${spool_j}/manifest.txt")"
assert_eq "${staged_j_uuid}" "${expected_j_uuid}" "the staged manifest reads back with the staged uuid"
if [[ -e "${target_j}/old-media.bin" ]]; then
    printf 'FAIL: the old revision media must be gone after success\n'
    exit 1
fi
battery_pass=$(( battery_pass + 1 ))
asides_j="$(find "${WOU_UPGRADE_SPOOL}" -maxdepth 1 -name 'replaced-*' | wc -l | tr -d ' ')"
assert_eq "${asides_j}" "0" "the moved-aside old revision is DELETED after the successful staging"
echo "[J] delete-after-success replacement proven."

# -----------------------------------------------------------------------
# K. The purge trio with the kept-set assertion (ACQ-06, Pitfall 6)
# -----------------------------------------------------------------------
echo "--- Section K: purge trio (sole / stale / failed-staging) ---"

export WOU_UPGRADE_SPOOL="${tmp_dir}/purge-spool"
sets_k="${WOU_UPGRADE_SPOOL}/26200-x64-en-us"
uuid_k="11111111-1111-1111-1111-111111111111"
staged_k="${tmp_dir}/pr-staged.txt"
printf 'uuid|%s\n' "${uuid_k}" > "${staged_k}"
mkdir -p "${sets_k}/${uuid_k}/files"
cp "${staged_k}" "${sets_k}/${uuid_k}/manifest.txt"
printf 'KEEP-ME\n' > "${sets_k}/${uuid_k}/files/keep.txt"

if uup_purge_revisions 26200 x64 en-us "${staged_k}" > "${tmp_dir}/purge-k1.log" 2>&1
then
    battery_pass=$(( battery_pass + 1 ))
else
    printf 'FAIL: the sole-revision purge must end green\n'
    cat "${tmp_dir}/purge-k1.log"
    exit 1
fi
expect_contains "${tmp_dir}/purge-k1.log" "PURGE: 0 removals" "a sole revision answers 0 removals"
if [[ ! -f "${sets_k}/${uuid_k}/files/keep.txt" ]]; then
    printf 'FAIL: the sole revision must be deleted-not\n'
    exit 1
fi
battery_pass=$(( battery_pass + 1 ))

stale1="${sets_k}/22222222-2222-2222-2222-222222222222"
stale2="${sets_k}/33333333-3333-3333-3333-333333333333"
mkdir -p "${stale1}/files" "${stale2}"
printf 'uuid|22222222-2222-2222-2222-222222222222\n' > "${stale1}/manifest.txt"
printf 'STALE\n' > "${stale1}/files/stale.txt"
printf 'uuid|33333333-3333-3333-3333-333333333333\n' > "${stale2}/manifest.txt"

if uup_purge_revisions 26200 x64 en-us "${staged_k}" > "${tmp_dir}/purge-k2.log" 2>&1
then
    battery_pass=$(( battery_pass + 1 ))
else
    printf 'FAIL: the stale-revision purge must end green\n'
    cat "${tmp_dir}/purge-k2.log"
    exit 1
fi
if [[ -e "${stale1}" || -e "${stale2}" ]]; then
    printf 'FAIL: both stale sets must be purged\n'
    exit 1
fi
battery_pass=$(( battery_pass + 1 ))
if [[ ! -f "${sets_k}/${uuid_k}/files/keep.txt" ]]; then
    printf 'FAIL: the staged-uuid keep set must still exist after the purge (the kept-set assertion)\n'
    exit 1
fi
battery_pass=$(( battery_pass + 1 ))
expect_contains "${tmp_dir}/purge-k2.log" "2 stale revision set(s) removed" "the purge counts exactly 2 removals"

if uup_purge_revisions 26200 x64 en-us "${tmp_dir}/nonexistent-staged-manifest.txt" > "${tmp_dir}/purge-k3.log" 2>&1
then
    printf 'FAIL: the purge must refuse without proof of successful staging\n'
    exit 1
fi
battery_pass=$(( battery_pass + 1 ))
if [[ ! -d "${sets_k}/${uuid_k}" ]]; then
    printf 'FAIL: the failed-staging simulation must remove NOTHING\n'
    exit 1
fi
battery_pass=$(( battery_pass + 1 ))
echo "[K] purge answers 0 / exact / nothing, kept set survives."

# -----------------------------------------------------------------------
# L. The no-image-tool source pin: the task file must not name the image
#    tooling at all (the Windows-tool refusal is total, DEC-33-05)
# -----------------------------------------------------------------------
echo "--- Section L: no-image-tool source pin on the task file ---"

tool_hits="$(grep -ci 'dism\|wimlib' "${task_file}" || true)"
assert_eq "${tool_hits}" "0" "the task file must not name the image tooling at all (case-insensitive)"
echo "[L] no-image-tool source pin green."

unset UUP_CLIENT_ROOT WOU_UPGRADE_SPOOL || true

# -----------------------------------------------------------------------
# All green
# -----------------------------------------------------------------------
echo ""
echo "======================================================================="
echo "UUP payload acquisition: ${battery_pass} checks green."
echo "======================================================================="
echo "UPG-PAYLOADS-BASH-PASS"
exit 0
