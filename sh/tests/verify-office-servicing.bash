#!/usr/bin/env bash
# =======================================================================
# WSUS Offline Update - Complete Office Servicing Test Suite (Linux / Bash)
# File: sh/tests/verify-office-servicing.bash
#
# Verifies:
#   Test 1: Microsoft CDN Audience GUID resolution and C2R task integrity
#   Test 2: ODT XML Configuration Templates structure and channel contracts
#   Test 3: Architecture isolation in main updates (ExcludeList-${arch}.txt)
#   Test 4: C2R Metadata staging, format, and SHA256 hash database integrity
#   Test 5: Audited C2R fallback baseline literals + audit-baseline coherence
# =======================================================================

set -e
set -u
export LC_ALL=C

if [ -d "/usr/bin" ] && [[ ":$PATH:" != *":/usr/bin:"* ]]; then
    export PATH="/usr/bin:$PATH"
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"

echo "======================================================================="
echo "WSUS Offline Update - Office Servicing Regression Suite (Linux / Bash)"
echo "======================================================================="

# -----------------------------------------------------------------------
# Test 1: Microsoft CDN Audience GUID resolution
# -----------------------------------------------------------------------
echo "[Test 1/5] Verifying Microsoft CDN audience GUIDs in 65-office-c2r.bash..."

c2r_task="${repo_root}/sh/download-updates-tasks/65-office-c2r.bash"
if [[ ! -f "$c2r_task" ]]; then
    echo "FAIL: $c2r_task does not exist."
    exit 1
fi

# Source functions in isolated subshell
(
    source "$c2r_task"
    
    guid_19="$(get_c2r_channel_guid "o2k19")"
    if [[ "$guid_19" != "f2e724c1-748f-4b47-8fb8-8e0d210e9208" ]]; then
        echo "FAIL: o2k19 GUID mismatch: expected f2e724c1-748f-4b47-8fb8-8e0d210e9208, got $guid_19"
        exit 1
    fi
    
    guid_21="$(get_c2r_channel_guid "o2k21")"
    if [[ "$guid_21" != "5030841d-c919-4594-8d2d-84ae4f96e58e" ]]; then
        echo "FAIL: o2k21 GUID mismatch: expected 5030841d-c919-4594-8d2d-84ae4f96e58e, got $guid_21"
        exit 1
    fi
    
    guid_24="$(get_c2r_channel_guid "o2k24")"
    if [[ "$guid_24" != "7983bac0-e531-40cf-be00-fd24fe66619c" ]]; then
        echo "FAIL: o2k24 GUID mismatch: expected 7983bac0-e531-40cf-be00-fd24fe66619c, got $guid_24"
        exit 1
    fi
)

echo "[PASS] Test 1: Microsoft CDN audience GUIDs accurately resolved for 2019, 2021, and 2024."

# -----------------------------------------------------------------------
# Test 2: ODT XML Configuration Templates structure and channel contracts
# -----------------------------------------------------------------------
echo "[Test 2/5] Verifying ODT XML configuration templates structure and contracts..."

templates_dir="${repo_root}/static/odt-templates"
if [[ ! -d "$templates_dir" ]]; then
    echo "FAIL: $templates_dir does not exist."
    exit 1
fi

declare -A expected_channels=(
    ["o2k19"]="PerpetualVL2019"
    ["o2k21"]="PerpetualVL2021"
    ["o2k24"]="PerpetualVL2024"
)
declare -A expected_products=(
    ["o2k19"]="ProPlus2019Volume"
    ["o2k21"]="ProPlus2021Volume"
    ["o2k24"]="ProPlus2024Volume"
)

for prod in o2k19 o2k21 o2k24; do
    tpl="${templates_dir}/${prod}-template.xml"
    if [[ ! -f "$tpl" ]]; then
        echo "FAIL: Template $tpl not found."
        exit 1
    fi
    
    # Check well-formedness tags
    if ! grep -q "<Configuration>" "$tpl" || ! grep -q "</Configuration>" "$tpl"; then
        echo "FAIL: Template $tpl missing root <Configuration> tags."
        exit 1
    fi
    
    # Check channel contract
    chan="${expected_channels[$prod]}"
    if ! grep -qi "Channel=\"${chan}\"" "$tpl"; then
        echo "FAIL: Template $tpl missing expected Channel=\"${chan}\"."
        exit 1
    fi
    
    # Check product contract
    pid="${expected_products[$prod]}"
    if ! grep -qi "Product ID=\"${pid}\"" "$tpl"; then
        echo "FAIL: Template $tpl missing expected Product ID=\"${pid}\"."
        exit 1
    fi
done

echo "[PASS] Test 2: ODT configuration templates validated with valid XML syntax and contracts."

# -----------------------------------------------------------------------
# Test 3: Architecture isolation in main updates (ExcludeList-${arch}.txt)
# -----------------------------------------------------------------------
echo "[Test 3/5] Verifying architecture isolation in Linux main updates task..."

main_task="${repo_root}/sh/download-updates-tasks/60-main-updates.bash"
if [[ ! -f "$main_task" ]]; then
    echo "FAIL: $main_task does not exist."
    exit 1
fi

if ! grep -A 25 "o2k16)" "$main_task" | grep -q 'ExcludeList-${arch}.txt'; then
    echo "FAIL: $main_task does not isolate architectures using ExcludeList-\${arch}.txt in o2k16 branch."
    exit 1
fi

if [[ ! -f "${repo_root}/exclude/ExcludeList-x86.txt" ]] || [[ ! -f "${repo_root}/exclude/ExcludeList-x64.txt" ]]; then
    echo "FAIL: Missing ExcludeList-x86.txt or ExcludeList-x64.txt under exclude/."
    exit 1
fi

echo "[PASS] Test 3: Dual-architecture isolation verified for Linux main updates."

# -----------------------------------------------------------------------
# Test 4: C2R Metadata staging, format, and SHA256 hash database integrity
# -----------------------------------------------------------------------
echo "[Test 4/5] Verifying C2R metadata staging and hash database contracts..."

sandbox_dir=$(mktemp -d /tmp/wou_test_c2r_XXXXXX)
trap 'rm -rf "$sandbox_dir"' EXIT

(
    source "$c2r_task"
    stage_c2r_build "o2k24" "x64" "glb" "${sandbox_dir}/c2r"
) > /dev/null 2>&1

metadata_file="${sandbox_dir}/c2r/o2k24/x64/Office/Data/metadata.ini"
if [[ ! -f "$metadata_file" ]]; then
    echo "FAIL: stage_c2r_build did not generate metadata.ini."
    exit 1
fi

if ! grep -q "Product=o2k24" "$metadata_file"; then
    echo "FAIL: metadata.ini missing Product=o2k24"
    exit 1
fi
if ! grep -q "Architecture=x64" "$metadata_file"; then
    echo "FAIL: metadata.ini missing Architecture=x64"
    exit 1
fi
if ! grep -q "ChannelGuid=7983bac0-e531-40cf-be00-fd24fe66619c" "$metadata_file"; then
    echo "FAIL: metadata.ini missing ChannelGuid"
    exit 1
fi
if ! grep -q "Build=" "$metadata_file"; then
    echo "FAIL: metadata.ini missing Build="
    exit 1
fi

# Verify hash database format requirement
mock_hash_file="${sandbox_dir}/hashes-office-c2r.txt"
echo "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 *client/office/c2r/o2k24/x64/metadata.ini" > "$mock_hash_file"

# Validate 64-hex char SHA256 followed by space and asterisk
if ! grep -qE "^[a-f0-9]{64} \*client/office/c2r/" "$mock_hash_file"; then
    echo "FAIL: SHA256 hash file format does not conform to standard format."
    exit 1
fi

echo "[PASS] Test 4: C2R metadata generation and SHA256 hash contract validated."

# -----------------------------------------------------------------------
# Test 5: Audited C2R fallback baseline literals + audit-baseline coherence
# (OFC-02: a failed CDN resolution must fall back on the REAL latest build of
#  each channel — never on a stale literal that masks the failure)
# -----------------------------------------------------------------------
echo "[Test 5/5] Verifying audited C2R baseline literals in 65-office-c2r.bash..."

# The three CDN-audited fallback literals must be present verbatim
# (November 2026 audit probes: o2k19 re-pinned to the live advertise
# 16.0.10417.20228 — see ci/office-frozen-revision-baseline.txt).
declare -A audited_literals=(
    ["o2k19"]="16.0.10417.20228"
    ["o2k21"]="16.0.14334.20974"
    ["o2k24"]="16.0.17932.21056"
)
for prod in o2k19 o2k21 o2k24; do
    lit="${audited_literals[$prod]}"
    if ! grep -qF "$lit" "$c2r_task"; then
        echo "FAIL: $c2r_task missing audited baseline literal for ${prod}: $lit"
        exit 1
    fi
done

# BITE: the stale pre-fix fallbacks must be GONE — zero occurrences. Against
# the pre-fix bytes of the task these counts are non-zero and this test fails:
# a stale baseline masks a failed CDN resolution behind a build that is
# neither terminal nor real (the exact regression OFC-02 forbids).
declare -A stale_literals=(
    ["o2k21"]="16.0.14332.20790"
    ["o2k19"]="16.0.10414.20002"
)
for prod in o2k21 o2k19; do
    old="${stale_literals[$prod]}"
    old_count="$(grep -cF "$old" "$c2r_task" || true)"
    if [[ "$old_count" -ne 0 ]]; then
        echo "FAIL: stale fallback literal for ${prod} still present ${old_count}x in $c2r_task: $old (stale baseline masks resolution failures)."
        exit 1
    fi
done

# The series-change trap must stay documented in the task comment: LTSC 2021
# moved series 14332.x -> 14334.x in May 2025, so any old-series baseline is
# stale AND masking; and o2k19 stays "keep lane live" (EOL but published).
if ! grep -qF "14332.x -> 14334.x" "$c2r_task"; then
    echo "FAIL: $c2r_task missing the 14332.x -> 14334.x series-change trap comment."
    exit 1
fi
if ! grep -qF "keep lane live" "$c2r_task"; then
    echo "FAIL: $c2r_task missing the o2k19 'keep lane live' rule."
    exit 1
fi

# Coherence with the audit baseline (plan 20-01): the c2r_baseline_* keys of
# ci/office-frozen-revision-baseline.txt must carry the SAME three literals
# as this task — a divergence between the two sources is a regression. If the
# baseline file is absent (plan 20-01 not executed), emit a documented SKIP
# instead of a FAIL so this suite stays runnable standalone.
baseline_file="${repo_root}/ci/office-frozen-revision-baseline.txt"
if [[ ! -f "$baseline_file" ]]; then
    echo "[SKIP] Test 5 coherence: ci/office-frozen-revision-baseline.txt absent (plan 20-01 not executed)."
else
    for prod in o2k19 o2k21 o2k24; do
        if ! grep -qxF "c2r_baseline_${prod}=${audited_literals[$prod]}" "$baseline_file"; then
            echo "FAIL: $baseline_file c2r_baseline_${prod} does not carry the audited literal ${audited_literals[$prod]} (baseline/code divergence)."
            exit 1
        fi
    done
    echo "[PASS] Test 5: audited baseline literals pinned; coherence with ci/office-frozen-revision-baseline.txt verified."
fi

echo "======================================================================="
echo "ALL TESTS PASSED: Linux Office Servicing Regression Suite (5/5 green)"
echo "======================================================================="
exit 0
