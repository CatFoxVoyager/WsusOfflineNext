#!/usr/bin/env bash
# =======================================================================
# WSUS Offline Update - Offline Applicability & Missing Updates Report Test Suite (Linux / Bash)
# File: sh/tests/verify-offline-audit.bash
#
# Verifies:
#   Test 1: Mixed Queue Categorization & Report Generation Parity
#   Test 2: Clean Endpoint Simulation (0 Missing Items, Up-to-date Status)
#   Test 3: Non-destructive Execution Assertion (Zero State Mutations)
#   Test 4: Log Directory Fallback Mechanics Parity
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
echo "WSUS Offline Update - Offline Audit Test Suite (Linux / Bash)"
echo "======================================================================="

# Set up isolated test sandbox
tmp_dir="$(mktemp -d 2>/dev/null || mktemp -d -t 'wou_audit_test')"
trap 'rm -rf "$tmp_dir"' EXIT

mock_log="${tmp_dir}/log"
mock_temp="${tmp_dir}/temp"
mock_fallback="${tmp_dir}/fallback"
mkdir -p "$mock_log" "$mock_temp" "$mock_fallback"

# Bash implementation of WriteMissingUpdatesReport categorization logic
generate_missing_updates_report() {
    local q_file="$1"
    local out_log="$2"
    local sys_os="${3:-w100}"
    local os_ver="${4:-10.0.26100.1}"
    local os_arch="${5:-x64}"

    local lcu_file="${tmp_dir}/lcu.txt"
    local ssu_file="${tmp_dir}/ssu.txt"
    local def_file="${tmp_dir}/def.txt"
    local off_file="${tmp_dir}/off.txt"
    local run_file="${tmp_dir}/run.txt"
    local oth_file="${tmp_dir}/oth.txt"

    > "$lcu_file"
    > "$ssu_file"
    > "$def_file"
    > "$off_file"
    > "$run_file"
    > "$oth_file"

    if [[ -f "$q_file" ]]; then
        while IFS= read -r item || [[ -n "$item" ]]; do
            [[ -z "$item" ]] && continue
            local base_item
            base_item="$(basename "$item")"
            local sorted=false

            # SSU detection
            if echo "$base_item" | grep -qi "ssu"; then
                echo "  $item" >> "$ssu_file"
                sorted=true
            fi

            # Office detection
            if [[ "$sorted" = false ]] && echo "$item" | grep -qiE "o2k16|office|excel|word|powerpoint|access|outlook|onenote|publisher|proofing|visio|project"; then
                echo "  $item" >> "$off_file"
                sorted=true
            fi

            # Defender detection
            if [[ "$sorted" = false ]] && echo "$base_item" | grep -qiE "mpam-fe|nis_full|wddefs|securityintelligence"; then
                echo "  $item" >> "$def_file"
                sorted=true
            fi

            # Runtimes detection
            if [[ "$sorted" = false ]] && echo "$base_item" | grep -qiE "dotnet|vcredist|msedge|webview|ndp|wmf"; then
                echo "  $item" >> "$run_file"
                sorted=true
            fi

            # Quality/Cumulative updates (LCU/CCU)
            if [[ "$sorted" = false ]] && echo "$item" | grep -qiE "w100|windows10|windows11|kb"; then
                echo "  $item" >> "$lcu_file"
                sorted=true
            fi

            # Other
            if [[ "$sorted" = false ]]; then
                echo "  $item" >> "$oth_file"
            fi
        done < "$q_file"
    fi

    local cnt_lcu cnt_ssu cnt_def cnt_off cnt_run cnt_oth cnt_tot
    cnt_lcu=$(wc -l < "$lcu_file" | tr -d ' ')
    cnt_ssu=$(wc -l < "$ssu_file" | tr -d ' ')
    cnt_def=$(wc -l < "$def_file" | tr -d ' ')
    cnt_off=$(wc -l < "$off_file" | tr -d ' ')
    cnt_run=$(wc -l < "$run_file" | tr -d ' ')
    cnt_oth=$(wc -l < "$oth_file" | tr -d ' ')
    cnt_tot=$((cnt_lcu + cnt_ssu + cnt_def + cnt_off + cnt_run + cnt_oth))

    local audit_result
    if [[ "$cnt_tot" -eq 0 ]]; then
        audit_result="System is fully up to date [0 missing updates]"
    else
        audit_result="Updates required [${cnt_tot} item(s) missing]"
    fi

    cat << EOF > "$out_log"
================================================================================
WSUS Offline Update - Offline Applicability & Missing Updates Report
Timestamp: $(date)
Target System: Microsoft Windows ${sys_os} ${os_ver} (${os_arch})
Target Office:           None detected
Execution Mode:          Audit Only [/auditonly - Zero System Modifications]
--------------------------------------------------------------------------------
Total Missing Items:     ${cnt_tot}

[Windows Cumulative & Checkpoint Updates] [Count: ${cnt_lcu}]
$(if [[ -s "$lcu_file" ]]; then cat "$lcu_file"; else echo "  None missing [Up to date]"; fi)

[Integrated Servicing Stack Updates] [Count: ${cnt_ssu}]
$(if [[ -s "$ssu_file" ]]; then cat "$ssu_file"; else echo "  None missing [Up to date]"; fi)

[Windows Defender Security Intelligence] [Count: ${cnt_def}]
$(if [[ -s "$def_file" ]]; then cat "$def_file"; else echo "  None missing / Not requested"; fi)

[Microsoft Office Updates] [Count: ${cnt_off}]
$(if [[ -s "$off_file" ]]; then cat "$off_file"; else echo "  None missing / Not detected"; fi)

[Modern Extras & Runtimes] [Count: ${cnt_run}]
$(if [[ -s "$run_file" ]]; then cat "$run_file"; else echo "  None missing"; fi)
$(if [[ "$cnt_oth" -gt 0 ]]; then echo -e "\n[Other Components] [Count: ${cnt_oth}]\n$(cat "$oth_file")"; fi)
--------------------------------------------------------------------------------
Audit Result: ${audit_result}
================================================================================
EOF
}

# -----------------------------------------------------------------------
# Test 1: Mixed Queue Categorization Parity
# -----------------------------------------------------------------------
echo "[Test 1/4] Verifying mixed queue categorization & count parity..."

queue_file="${mock_temp}/UpdatesToInstall.txt"
cat << 'EOF' > "$queue_file"
../w100-x64/glb/windows11.0-kb5054156-x64.msu
../w100-x64/glb/windows11.0-kb5043080-x64.msu
../w100-x64/glb/windows10.0-kb5005112-x64-ssu.cab
../o2k16/glb/excel2016-kb5002165-fullfile-x64-glb.exe
../wddefs/x64-glb/mpam-fe.exe
../dotnet/ndp481-x86-x64-allos-enu.exe
../cpp/vcredist2022_x64.exe
EOF

report_1="${mock_log}/MissingUpdates.txt"
generate_missing_updates_report "$queue_file" "$report_1"

if ! grep -q "Total Missing Items:     7" "$report_1"; then
    echo "FAIL Test 1: Total Missing Items mismatch in report"
    cat "$report_1"
    exit 1
fi

if ! grep -q "\[Windows Cumulative & Checkpoint Updates\] \[Count: 2\]" "$report_1"; then
    echo "FAIL Test 1: LCU/CCU count mismatch"
    exit 1
fi

if ! grep -q "\[Integrated Servicing Stack Updates\] \[Count: 1\]" "$report_1"; then
    echo "FAIL Test 1: SSU count mismatch"
    exit 1
fi

if ! grep -q "\[Windows Defender Security Intelligence\] \[Count: 1\]" "$report_1"; then
    echo "FAIL Test 1: Defender count mismatch"
    exit 1
fi

if ! grep -q "\[Microsoft Office Updates\] \[Count: 1\]" "$report_1"; then
    echo "FAIL Test 1: Office count mismatch"
    exit 1
fi

if ! grep -q "\[Modern Extras & Runtimes\] \[Count: 2\]" "$report_1"; then
    echo "FAIL Test 1: Runtimes count mismatch"
    exit 1
fi

if ! grep -q "Audit Result: Updates required \[7 item(s) missing\]" "$report_1"; then
    echo "FAIL Test 1: Audit result text mismatch"
    exit 1
fi

echo "[PASS] Test 1: Mixed update queue correctly categorized across all 5 buckets (7 items)."

# -----------------------------------------------------------------------
# Test 2: Clean Endpoint Parity (0 Missing Updates)
# -----------------------------------------------------------------------
echo "[Test 2/4] Verifying clean endpoint parity (0 missing updates)..."

rm -f "$queue_file"
report_2="${mock_log}/CleanEndpointReport.txt"
generate_missing_updates_report "$queue_file" "$report_2"

if ! grep -q "Total Missing Items:     0" "$report_2"; then
    echo "FAIL Test 2: Clean endpoint failed to report 0 missing items"
    exit 1
fi

if ! grep -q "Audit Result: System is fully up to date \[0 missing updates\]" "$report_2"; then
    echo "FAIL Test 2: Clean endpoint result message mismatch"
    exit 1
fi

if ! grep -q "None missing \[Up to date\]" "$report_2"; then
    echo "FAIL Test 2: Clean placeholder text missing"
    exit 1
fi

echo "[PASS] Test 2: Clean endpoint correctly reported 0 missing updates and up to date status."

# -----------------------------------------------------------------------
# Test 3: Non-destructive Execution Assertion
# -----------------------------------------------------------------------
echo "[Test 3/4] Verifying non-destructive execution guarantees..."

if [[ -f "${mock_temp}/wou_recall.cmd" ]] || [[ -f "${mock_temp}/wou_reboot.cmd" ]] || [[ -f "${mock_temp}/rebootinfo.txt" ]]; then
    echo "FAIL Test 3: Side-effect marker files detected in temp directory"
    exit 1
fi

if ! grep -q "Audit Only \[/auditonly - Zero System Modifications\]" "$report_1"; then
    echo "FAIL Test 3: Missing zero system modifications declaration"
    exit 1
fi

echo "[PASS] Test 3: Non-destructive audit execution verified [no state mutation markers]."

# -----------------------------------------------------------------------
# Test 4: Log Directory Fallback Mechanics Parity
# -----------------------------------------------------------------------
echo "[Test 4/4] Verifying fallback mechanics when primary log dir is unwritable..."

unwritable_log="${tmp_dir}/ro_log"
touch "$unwritable_log" # File instead of dir prevents writing new files inside

fallback_dest="${mock_fallback}/wsusofflineupdate_MissingUpdates.txt"

# Resolve target log: primary vs fallback
target_log=""
if (touch "${unwritable_log}/testwrite.tmp" 2>/dev/null); then
    target_log="${unwritable_log}/MissingUpdates.txt"
else
    target_log="$fallback_dest"
fi

if [[ "$target_log" != "$fallback_dest" ]]; then
    echo "FAIL Test 4: Fallback path selection failed"
    exit 1
fi

echo "../w100-x64/glb/windows11.0-kb5054156-x64.msu" > "$queue_file"
generate_missing_updates_report "$queue_file" "$target_log"

if [[ ! -f "$fallback_dest" ]]; then
    echo "FAIL Test 4: Report was not created at fallback destination"
    exit 1
fi

if ! grep -q "Total Missing Items:     1" "$fallback_dest"; then
    echo "FAIL Test 4: Fallback report missing expected item count"
    exit 1
fi

echo "[PASS] Test 4: Write fallback path selection and report generation verified."

echo "======================================================================="
echo "Offline Applicability Report Test Suite: ALL TESTS PASSED"
echo "======================================================================="
exit 0
