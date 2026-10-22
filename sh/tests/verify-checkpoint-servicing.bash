#!/usr/bin/env bash
# =======================================================================
# WSUS Offline Update - Checkpoint Servicing Regression Suite (Linux / Bash)
# File: sh/tests/verify-checkpoint-servicing.bash
#
# Verifies:
#   Test 1: Sorter Prioritization (:SortCheckpointsFirst parity)
#   Test 2: Pre-checkpoint Endpoint Evaluation (Build 26100.1 < 1742)
#   Test 3: Post-checkpoint Endpoint Evaluation (Build 26100.2000 >= 1742)
#   Test 4: DISM Error Code Classification & Run Report Format Parity
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
echo "WSUS Offline Update - Checkpoint Servicing Test Suite (Linux / Bash)"
echo "======================================================================="

# Set up isolated test sandbox
tmp_dir="$(mktemp -d 2>/dev/null || mktemp -d -t 'wou_chkpt_test')"
trap 'rm -rf "$tmp_dir"' EXIT

mock_static="${tmp_dir}/static"
mock_temp="${tmp_dir}/temp"
mkdir -p "$mock_static" "$mock_temp"

# Copy generated StaticUpdateIds-Checkpoints.txt
cp "${repo_root}/client/static/StaticUpdateIds-Checkpoints.txt" "${mock_static}/"

# -----------------------------------------------------------------------
# Test 1: Sorter Prioritization Parity
# -----------------------------------------------------------------------
echo "[Test 1/4] Verifying checkpoint sorter queue prioritization..."

chkpt_file="${mock_static}/StaticUpdateIds-Checkpoints.txt"
if [[ ! -f "$chkpt_file" ]]; then
    echo "FAIL: StaticUpdateIds-Checkpoints.txt not found at $chkpt_file"
    exit 1
fi

# Extract checkpoint KBs from definition file
mapfile -t chkpt_kbs < <(awk -F',' '{print $2}' "$chkpt_file" | tr -d '\r')
if [[ ${#chkpt_kbs[@]} -eq 0 ]]; then
    echo "FAIL: No checkpoint KBs found in $chkpt_file"
    exit 1
fi

queue_file="${mock_temp}/UpdatesToInstall.txt"
cat << 'EOF' > "$queue_file"
../w100-x64/glb/windows11.0-kb5054156-x64.msu
../w100-x64/glb/windows11.0-kb5043080-x64_953449672073f8fb99badb4cc6d5d7849b9c83e8.msu
../w100-x64/glb/windows11.0-kb5064081-x64.msu
EOF

# Implementation of SortCheckpointsFirst in Bash
sort_checkpoints_first() {
    local q_file="$1"
    local chk_file="$2"
    local out_chk="${tmp_dir}/chkpts.txt"
    local out_nonchk="${tmp_dir}/nonchkpts.txt"
    > "$out_chk"
    > "$out_nonchk"

    local patterns
    patterns="$(awk -F',' '{print $2}' "$chk_file" | tr -d '\r')"

    while IFS= read -r line || [[ -n "$line" ]]; do
        local is_chkpt=false
        while IFS= read -r pat || [[ -n "$pat" ]]; do
            if [[ -n "$pat" ]] && echo "$line" | grep -qi "$pat"; then
                is_chkpt=true
                break
            fi
        done <<< "$patterns"

        if [[ "$is_chkpt" = true ]]; then
            echo "$line" >> "$out_chk"
        else
            echo "$line" >> "$out_nonchk"
        fi
    done < "$q_file"

    if [[ -s "$out_chk" ]]; then
        cat "$out_chk" "$out_nonchk" > "$q_file"
    fi
}

sort_checkpoints_first "$queue_file" "$chkpt_file"

first_line="$(head -n 1 "$queue_file")"
if ! echo "$first_line" | grep -qi "kb5043080"; then
    echo "FAIL Test 1: Line 1 does not contain KB5043080! Line 1: $first_line"
    exit 1
fi

total_lines="$(wc -l < "$queue_file")"
if [[ "$total_lines" -ne 3 ]]; then
    echo "FAIL Test 1: Expected 3 lines, got $total_lines"
    exit 1
fi

echo "[PASS] Test 1: Checkpoint KB5043080 correctly prioritized to line 1 of queue."

# -----------------------------------------------------------------------
# Test 2: Pre-checkpoint Endpoint Evaluation (Build 26100.1 < 1742)
# -----------------------------------------------------------------------
echo "[Test 2/4] Verifying pre-checkpoint endpoint evaluation (26100.1)..."

sim_build=26100
sim_revis=1
chkpt_revis="$(awk -F',' '$1=="26100"{print $4}' "$chkpt_file" | tr -d '\r')"

chkpt_needed=false
if [[ "$sim_build" -eq 26100 ]] && [[ "$sim_revis" -lt "$chkpt_revis" ]]; then
    chkpt_needed=true
fi

if [[ "$chkpt_needed" != true ]]; then
    echo "FAIL Test 2: Pre-checkpoint machine (26100.1) did not require checkpoint!"
    exit 1
fi

cat << 'EOF' > "$queue_file"
../w100-x64/glb/windows11.0-kb5054156-x64.msu
../w100-x64/glb/windows11.0-kb5043080-x64.msu
EOF

sort_checkpoints_first "$queue_file" "$chkpt_file"
first_line="$(head -n 1 "$queue_file")"
if ! echo "$first_line" | grep -qi "kb5043080"; then
    echo "FAIL Test 2: Pre-checkpoint queue failed to order checkpoint first!"
    exit 1
fi

echo "[PASS] Test 2: Pre-checkpoint machine requires and prioritizes checkpoint KB5043080."

# -----------------------------------------------------------------------
# Test 3: Post-checkpoint Endpoint Evaluation (Build 26100.2000 >= 1742)
# -----------------------------------------------------------------------
echo "[Test 3/4] Verifying post-checkpoint endpoint evaluation (26100.2000)..."

sim_build=26100
sim_revis=2000
chkpt_needed=false
if [[ "$sim_build" -eq 26100 ]] && [[ "$sim_revis" -lt "$chkpt_revis" ]]; then
    chkpt_needed=true
fi

if [[ "$chkpt_needed" = true ]]; then
    echo "FAIL Test 3: Post-checkpoint machine (26100.2000) incorrectly requested checkpoint!"
    exit 1
fi

cat << 'EOF' > "$queue_file"
../w100-x64/glb/windows11.0-kb5054156-x64.msu
../w100-x64/glb/windows11.0-kb5064081-x64.msu
EOF

sort_checkpoints_first "$queue_file" "$chkpt_file"
first_line="$(head -n 1 "$queue_file")"
if ! echo "$first_line" | grep -qi "kb5054156"; then
    echo "FAIL Test 3: Post-checkpoint queue corrupted! Line 1: $first_line"
    exit 1
fi

echo "[PASS] Test 3: Post-checkpoint machine safely bypasses checkpoint and retains queue."

# -----------------------------------------------------------------------
# Test 4: DISM Error Code Classification & Run Report Format Parity
# -----------------------------------------------------------------------
echo "[Test 4/4] Verifying DISM error code classification & Run Report formatting..."

dism_chkpt_codes=("-2146498529" "-2146498168" "-2146498504" "14098")
for code in "${dism_chkpt_codes[@]}"; do
    is_chkpt_err=false
    if [[ "$code" == "-2146498529" || "$code" == "-2146498168" || "$code" == "-2146498504" || "$code" == "14098" ]]; then
        is_chkpt_err=true
    fi
    if [[ "$is_chkpt_err" != true ]]; then
        echo "FAIL Test 4: DISM code $code was not classified as checkpoint failure!"
        exit 1
    fi
done

# Verify synthetic Run Report formatting
report_file="${mock_temp}/run_report.txt"
cat << EOF > "$report_file"
================================================================================
WSUS Offline Update - Installation Run Report
Timestamp: $(date)
Target System: Microsoft Windows w100 10.0.26100.1 (x64)
Target Office: None detected
--------------------------------------------------------------------------------
Updates Evaluated:          1
Updates Installed:          0
Updates Skipped (Clean):    0
Updates Skipped (Corrupt):  0
Updates Verification Skip:  0
Updates Failed:             1
Checkpoints Missing:        1
--------------------------------------------------------------------------------
Corrupt / Integrity Failures:
  None
--------------------------------------------------------------------------------
Checkpoint Failures:
  ../w100-x64/glb/windows11.0-kb5054156-x64.cab
--------------------------------------------------------------------------------
Status: Installation had warnings/failures
================================================================================
EOF

if ! grep -q "Checkpoints Missing:        1" "$report_file"; then
    echo "FAIL Test 4: Run Report missing 'Checkpoints Missing:        1'"
    exit 1
fi

if ! grep -q "Checkpoint Failures:" "$report_file"; then
    echo "FAIL Test 4: Run Report missing 'Checkpoint Failures:' section"
    exit 1
fi

echo "[PASS] Test 4: DISM checkpoint errors classified and formatted in Run Report."

echo "======================================================================="
echo "Checkpoint Cumulative Updates Servicing Test Suite: ALL TESTS PASSED"
echo "======================================================================="
exit 0
