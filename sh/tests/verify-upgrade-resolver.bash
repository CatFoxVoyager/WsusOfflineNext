#!/usr/bin/env bash
# =======================================================================
# WSUS Offline Update - UUP Payload Resolver Twin (Linux / Bash)
# File: sh/tests/verify-upgrade-resolver.bash
#
# Plan 33-02 task 1 battery (ACQ-01): the bash resolver library
# (sh/libraries/upgrade-payloads.bash) against the committed golden
# get.php fixture and the five negative fixtures. Sandbox only - no
# network, no API calls (the resolver is one-shot per run: the API
# rate-limits rapid calls, so the battery NEVER exercises the live
# chain; the fixtures ARE the bites - golden + 5 negatives).
#
#   A. Positive emission pins: extract + validate + emit over the
#      golden fixture (196 entries, total_bytes 10902883408, total_mib
#      10397 = int(total_bytes/1048576) per the DEC-33-02 formula -
#      the plan text's 10399 literal was an arithmetic slip, probe
#      evidence in the plan 33-02 SUMMARY), LC_ALL=C row order, CRLF
#      line endings, 3-field pipe row grammar, zero token-URL material
#      (no "http" anywhere in the emitted bytes, no url/expire field in
#      the committed fixture).
#   B. Negative refusals: the five failure shapes (USER_RATE_LIMITED,
#      UNSUPPORTED_LANG, empty files map, hostile names, malformed
#      JSON) each exit nonzero and leave NO output file (fail-closed
#      all-or-nothing, T-33-04/T-33-05).
#   C. Idempotency: the same fixture emits byte-identical manifests
#      across runs (sha256 digest equality).
#   D. End-to-end fixture seam (DEC-33-12): uup_resolve --fixture over
#      the golden fixture - the same manifest the raw chain emits, with
#      envelope metadata (updateName/uuid/arch/build) carried into the
#      meta rows.
#   E. Known-bad can-fail proof: a scratch-mutated copy of the golden
#      fixture (one corrupted sha256) must fail the resolve and leave
#      no output - proving the battery can actually go red.
#
# Every failure prints a FAIL: line and exits 1; success prints
# UPG-RESOLVER-BASH-PASS.
# =======================================================================

set -e
set -u
export LC_ALL=C

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
cd "$repo_root"

echo "======================================================================="
echo "WSUS Offline Update - UUP Payload Resolver Twin (Linux / Bash)"
echo "======================================================================="

# Isolated sandbox - never the repo tree
tmp_dir="$(mktemp -d 2>/dev/null || mktemp -d -t 'wou_uup_resolver')"
trap 'rm -rf "$tmp_dir"' EXIT

library_file="${repo_root}/sh/libraries/upgrade-payloads.bash"
golden_fixture="${repo_root}/tests/fixtures/uup-get-26200-en-us-multiedition.json"

if [[ ! -f "${library_file}" ]]; then
    printf 'FAIL: missing library sh/libraries/upgrade-payloads.bash\n'
    exit 1
fi
if [[ ! -f "${golden_fixture}" ]]; then
    printf 'FAIL: missing golden fixture tests/fixtures/uup-get-26200-en-us-multiedition.json\n'
    exit 1
fi

# shellcheck source=/dev/null
source "${library_file}"

BATTERY_PASS=0
assert_eq() {
    local actual="$1" expected="$2" desc="$3"
    if [[ "${actual}" != "${expected}" ]]; then
        printf 'FAIL: %s (expected "%s", got "%s")\n' "${desc}" "${expected}" "${actual}"
        exit 1
    fi
    BATTERY_PASS=$((BATTERY_PASS + 1))
}

# -----------------------------------------------------------------------
# A. Positive emission pins over the golden fixture
# -----------------------------------------------------------------------
echo "--- Section A: positive emission pins (golden fixture) ---"

manifest_a="${tmp_dir}/manifest-a.txt"
if ! uup_resolve 26200 x64 en-us "${manifest_a}" --fixture "${golden_fixture}" > /dev/null 2> "${tmp_dir}/resolve-a.err"; then
    printf 'FAIL: golden fixture resolve exited nonzero: %s\n' "$(cat "${tmp_dir}/resolve-a.err")"
    exit 1
fi
BATTERY_PASS=$((BATTERY_PASS + 1))
echo "[A] golden resolve exit 0 (fixture seam, zero network)"

# Entry census: manifest rows == fixture census == the live 196
# (row patterns carry the CR as an ANSI-C escape - grep does not
# expand \r inside a plain regex string)
fixture_census="$(grep -o '"sha1":' "${golden_fixture}" | wc -l | tr -d '[:space:]')"
row_census="$(grep -cE $'^[A-Za-z0-9._-]+\\|[0-9a-f]{64}\\|[0-9]+\r$' "${manifest_a}" || true)"
assert_eq "${row_census}" "196" "manifest carries exactly 196 name|sha256|size rows"
assert_eq "${fixture_census}" "196" "golden fixture carries exactly 196 entries"
assert_eq "${row_census}" "${fixture_census}" "manifest row census equals the fixture entry census"

# Totals (DEC-33-02): bytes pinned to the live measured sum, MiB pinned
# to the frozen formula int(total_bytes / 1048576) - computed in awk
# double arithmetic twin-side, never re-summed downstream. The CRLF
# presence is pinned separately by the CR line count below; the value
# comparisons strip CRs because MSYS grep drops them on output while
# still matching them in patterns.
total_bytes_line="$(grep -E $'^total_bytes\\|[0-9]+\r$' "${manifest_a}" | tr -d '\r')"
total_mib_line="$(grep -E $'^total_mib\\|[0-9]+\r$' "${manifest_a}" | tr -d '\r')"
assert_eq "${total_bytes_line}" "total_bytes|10902883408" "total_bytes meta row pinned to the measured live sum"
assert_eq "${total_mib_line}" "total_mib|10397" "total_mib meta row = int(10902883408/1048576) per DEC-33-02"

# Meta rows: the DEC-33-02 key set, contiguous, before the first row
meta_keys="$(grep -E '^(updateName|uuid|arch|lang|build|total_bytes|total_mib)\|' "${manifest_a}" | tr -d '\r' | LC_ALL=C sort | md5sum | cut -d' ' -f1)"
assert_eq "${meta_keys}" "$(printf '%s\n' \
    "arch|amd64" "build|26200.9974" "lang|en-us" \
    "total_bytes|10902883408" "total_mib|10397" \
    "updateName|Windows 11, version 25H2 (26200.9974)" \
    "uuid|fb0a90c6-cc17-4a55-832d-f23495f93aa3" \
    | LC_ALL=C sort | md5sum | cut -d' ' -f1)" \
    "the seven DEC-33-02 meta rows are present with pinned values"

# LC_ALL=C row order: the emitted row sequence equals the sorted
# sequence of the same rows
if ! diff <(grep -E $'^[A-Za-z0-9._-]+\\|[0-9a-f]{64}\\|[0-9]+\r$' "${manifest_a}") \
          <(grep -E $'^[A-Za-z0-9._-]+\\|[0-9a-f]{64}\\|[0-9]+\r$' "${manifest_a}" | LC_ALL=C sort) > /dev/null; then
    printf 'FAIL: manifest rows are not in LC_ALL=C order\n'
    exit 1
fi
BATTERY_PASS=$((BATTERY_PASS + 1))
echo "[A] rows are in LC_ALL=C order"

# CRLF: every line (3 header + 7 meta + 196 rows = 206) ends with CR
cr_lines="$(grep -c $'\r' "${manifest_a}" || true)"
total_lines="$(grep -c '' "${manifest_a}")"
assert_eq "${cr_lines}" "${total_lines}" "every manifest line carries CR (CRLF endings)"
assert_eq "${total_lines}" "206" "manifest line census: 3 header + 7 meta + 196 rows"

# Token-URL material: zero "http" occurrences in the emitted bytes;
# the committed fixture itself carries no url/expire field
if grep -qi 'http' "${manifest_a}"; then
    printf 'FAIL: token-URL material (http) found in the emitted manifest\n'
    exit 1
fi
BATTERY_PASS=$((BATTERY_PASS + 1))
echo "[A] zero http occurrences in the emitted manifest"

url_fields="$(grep -c '"url"' "${golden_fixture}" || true)"
expire_fields="$(grep -c '"expire"' "${golden_fixture}" || true)"
assert_eq "${url_fields}" "0" "golden fixture carries zero url fields (token material stripped at authoring)"
assert_eq "${expire_fields}" "0" "golden fixture carries zero expire fields"

A_PASS=${BATTERY_PASS}
printf '[A] positive emission pins: %s checks green\n' "${A_PASS}"

# -----------------------------------------------------------------------
# B. Negative refusals - fail-closed all-or-nothing
# -----------------------------------------------------------------------
echo "--- Section B: negative refusals (five failure shapes) ---"

negative_fixtures=(
    uup-error-ratelimited.json
    uup-error-unsupported-lang.json
    uup-error-empty-files.json
    uup-error-hostile-name.json
    uup-error-malformed.json
)

for neg in "${negative_fixtures[@]}"; do
    neg_path="${repo_root}/tests/fixtures/${neg}"
    neg_out="${tmp_dir}/neg-${neg}.manifest"
    rm -f "${neg_out}"
    if uup_resolve 26200 x64 en-us "${neg_out}" --fixture "${neg_path}" > /dev/null 2> /dev/null; then
        printf 'FAIL: negative fixture %s exited 0 - the refusal did not fire\n' "${neg}"
        exit 1
    fi
    if [[ -f "${neg_out}" ]]; then
        printf 'FAIL: negative fixture %s left an output file behind - not all-or-nothing\n' "${neg}"
        exit 1
    fi
    BATTERY_PASS=$((BATTERY_PASS + 1))
    echo "[B] ${neg}: exit nonzero, no output file"
done

# The error-field guard also echoes the API error values (Pitfall 2 +
# UNSUPPORTED_LANG) - the guards the VBS analog lacks
guard_value="$(uup_check_error_field "${repo_root}/tests/fixtures/uup-error-ratelimited.json" || true)"
assert_eq "${guard_value}" "USER_RATE_LIMITED" "rate-limit error value is echoed by the guard"
guard_value="$(uup_check_error_field "${repo_root}/tests/fixtures/uup-error-unsupported-lang.json" || true)"
assert_eq "${guard_value}" "UNSUPPORTED_LANG" "unsupported-language error value is echoed by the guard"

B_PASS=$((BATTERY_PASS - A_PASS))
printf '[B] negative refusals: %s checks green\n' "${B_PASS}"

# -----------------------------------------------------------------------
# C. Idempotency - same fixture, byte-identical manifests
# -----------------------------------------------------------------------
echo "--- Section C: idempotency ---"

manifest_b="${tmp_dir}/manifest-b.txt"
uup_resolve 26200 x64 en-us "${manifest_b}" --fixture "${golden_fixture}" > /dev/null 2>&1
digest_a="$(sha256sum "${manifest_a}" | cut -d' ' -f1)"
digest_b="$(sha256sum "${manifest_b}" | cut -d' ' -f1)"
assert_eq "${digest_a}" "${digest_b}" "re-running the resolve rewrites the manifest byte-identically"

C_PASS=$((BATTERY_PASS - A_PASS - B_PASS))
printf '[C] idempotency: %s checks green\n' "${C_PASS}"

# -----------------------------------------------------------------------
# D. End-to-end fixture seam already covered by A (uup_resolve with the
#    --fixture argument AND the WOU_UUP_FIXTURE env seam)
# -----------------------------------------------------------------------
echo "--- Section D: WOU_UUP_FIXTURE env seam (DEC-33-12) ---"

manifest_c="${tmp_dir}/manifest-c.txt"
WOU_UUP_FIXTURE="${golden_fixture}" uup_resolve 26200 x64 en-us "${manifest_c}" > /dev/null 2>&1
digest_c="$(sha256sum "${manifest_c}" | cut -d' ' -f1)"
assert_eq "${digest_c}" "${digest_a}" "the WOU_UUP_FIXTURE env seam emits the same manifest as --fixture"

D_PASS=$((BATTERY_PASS - A_PASS - B_PASS - C_PASS))
printf '[D] fixture seam: %s checks green\n' "${D_PASS}"

# -----------------------------------------------------------------------
# E. Known-bad can-fail proof - the battery can actually go red
# -----------------------------------------------------------------------
echo "--- Section E: can-fail proof (corrupted scratch fixture) ---"

mutated="${tmp_dir}/mutated-golden.json"
# Corrupt one sha256 (first byte -> z) in a SCRATCH copy - the
# committed fixture is never touched
sed 's/afb8c6529db4aa7a9e6ee967cc835e882a34c04bdc035b8f0c73055b899897f5/zzb8c6529db4aa7a9e6ee967cc835e882a34c04bdc035b8f0c73055b899897f5/' \
    "${golden_fixture}" > "${mutated}"
mut_out="${tmp_dir}/mutated.manifest"
rm -f "${mut_out}"
if uup_resolve 26200 x64 en-us "${mut_out}" --fixture "${mutated}" > /dev/null 2> /dev/null; then
    printf 'FAIL: the corrupted-fixture resolve exited 0 - the shape census is deaf\n'
    exit 1
fi
if [[ -f "${mut_out}" ]]; then
    printf 'FAIL: the corrupted-fixture resolve left an output file\n'
    exit 1
fi
BATTERY_PASS=$((BATTERY_PASS + 1))
echo "[E] corrupted sha256 in a scratch fixture: resolve refused, no output"

# Restore-proof: the committed fixture still emits the pinned digest
digest_committed="$(uup_resolve 26200 x64 en-us "${tmp_dir}/committed-again.manifest" --fixture "${golden_fixture}" > /dev/null 2>&1 && sha256sum "${tmp_dir}/committed-again.manifest" | cut -d' ' -f1)"
assert_eq "${digest_committed}" "${digest_a}" "the committed fixture still emits the pinned digest after the scratch mutation"

E_PASS=$((BATTERY_PASS - A_PASS - B_PASS - C_PASS - D_PASS))
printf '[E] can-fail proof: %s checks green\n' "${E_PASS}"

# -----------------------------------------------------------------------
# All green
# -----------------------------------------------------------------------
echo ""
echo "======================================================================="
echo "UUP payload resolver twin: A=${A_PASS} B=${B_PASS} C=${C_PASS} D=${D_PASS} E=${E_PASS} checks green."
echo "======================================================================="
echo "UPG-RESOLVER-BASH-PASS"
exit 0
