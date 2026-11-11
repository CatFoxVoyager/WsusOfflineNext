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
logfile="${tmp_dir}/battery.log"
debug="disabled"

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
stub_line="$(grep -n 'ARIA2-STUB-DOWNLOAD' "${tmp_dir}/orch.log" | head -1 | cut -d: -f1)"
if [[ -z "${budget_line}" || -z "${stub_line}" ]] || (( budget_line >= stub_line )); then
    printf 'FAIL: the budget line must precede the first downloader invocation\n'
    cat "${tmp_dir}/orch.log"
    exit 1
fi
battery_pass=$(( battery_pass + 1 ))
expect_contains "${tmp_dir}/orch.log" "Audit passed" "the hash gate runs over the orchestrated spool"
expect_contains "${tmp_dir}/orch.log" "WGET-STUB-DOWNLOAD" "the small payload list goes through wget"
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
# All green
# -----------------------------------------------------------------------
echo ""
echo "======================================================================="
echo "UUP payload acquisition: ${battery_pass} checks green."
echo "======================================================================="
echo "UPG-PAYLOADS-BASH-PASS"
exit 0
