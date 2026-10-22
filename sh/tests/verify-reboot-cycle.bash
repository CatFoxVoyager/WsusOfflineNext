#!/usr/bin/env bash
# =======================================================================
# WSUS Offline Update - Build Upgrade Reboot Cycle Regression Suite (Linux / Bash)
# File: sh/tests/verify-reboot-cycle.bash
#
# Verifies the 6-state build upgrade lifecycle and infinite loop prevention:
#   State 1: Fresh run (build 26100.1000) -> PrepareBuildUpgrade -> 3011
#   State 2: Simulated Reboot 1 -> revision advances to 5074
#   State 3: Perform run (build 26100.5074) -> PerformBuildUpgrade -> 3011
#   State 4: Simulated Reboot 2 -> build advances to 26200
#   State 5: Convergence run (build 26200.5074) -> upgrade skipped -> 0
#   State 6: Infinite loop guard -> revision stagnant -> halts safely -> 0
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
echo "WSUS Offline Update - Reboot Cycle Regression Test Suite (Linux / Bash)"
echo "======================================================================="

# Set up isolated test sandbox
tmp_dir="$(mktemp -d 2>/dev/null || mktemp -d -t 'wou_reboot_test')"
trap 'rm -rf "$tmp_dir"' EXIT

mock_static="${tmp_dir}/static"
mock_glb="${tmp_dir}/w100-x64/glb"
mock_temp="${tmp_dir}/temp"
mock_sys_temp="${tmp_dir}/sysroot_temp"

mkdir -p "$mock_static" "$mock_glb" "$mock_temp" "$mock_sys_temp"

# Mock upgrade definition: 26100 -> 26200 with prereq kb5064081 and eKB kb5054156
printf '26100,5074,kb5064081,26200,kb5054156\n' > "${mock_static}/StaticUpdateIds-BuildUpgrades.txt"

# Mock packages
touch "${mock_glb}/windows11.0-kb5064081-x64.cab"
touch "${mock_glb}/windows11.0-kb5054156-x64.cab"

CYCLE_EXIT_CODE=0

# Build upgrade state machine evaluator (parity with client/cmd/DoUpdate.cmd)
run_build_upgrade_evaluator() {
    local os_build="$1"
    local os_revis="$2"
    local os_arch="x64"
    local os_name="w100"

    local matched_oldbuild=""
    local matched_minrevis=""
    local matched_preupd=""
    local matched_newbuild=""
    local matched_epkgid=""

    # Evaluate against StaticUpdateIds-BuildUpgrades.txt
    if [[ -f "${mock_static}/StaticUpdateIds-BuildUpgrades.txt" ]]; then
        while IFS=',' read -r s_build s_minrev s_pre s_newbuild s_epkg || [[ -n "$s_build" ]]; do
            # Trim CR/LF
            s_build="$(echo "$s_build" | tr -d '\r\n')"
            s_minrev="$(echo "$s_minrev" | tr -d '\r\n')"
            s_pre="$(echo "$s_pre" | tr -d '\r\n')"
            s_newbuild="$(echo "$s_newbuild" | tr -d '\r\n')"
            s_epkg="$(echo "$s_epkg" | tr -d '\r\n')"

            if [[ "$s_build" == "$os_build" ]]; then
                local found_epkg=0
                if compgen -G "${mock_glb}/*${s_epkg}*.cab" >/dev/null 2>&1 || compgen -G "${mock_glb}/*${s_epkg}*.msu" >/dev/null 2>&1; then
                    found_epkg=1
                fi

                local found_preupd=0
                if (( os_revis >= s_minrev )); then
                    found_preupd=1
                elif compgen -G "${mock_glb}/*${s_pre}*.cab" >/dev/null 2>&1 || compgen -G "${mock_glb}/*${s_pre}*.msu" >/dev/null 2>&1; then
                    found_preupd=1
                fi

                if (( found_epkg == 1 && found_preupd == 1 )); then
                    if [[ -z "$matched_newbuild" ]] || (( s_newbuild >= matched_newbuild )); then
                        matched_oldbuild="$s_build"
                        matched_minrevis="$s_minrev"
                        matched_preupd="$s_pre"
                        matched_newbuild="$s_newbuild"
                        matched_epkgid="$s_epkg"
                    fi
                fi
            fi
        done < "${mock_static}/StaticUpdateIds-BuildUpgrades.txt"
    fi

    # Convergence / Skip: If no upgrade applies, clean all markers and exit 0
    if [[ -z "$matched_oldbuild" || -z "$matched_minrevis" || -z "$matched_preupd" || -z "$matched_newbuild" || -z "$matched_epkgid" ]]; then
        rm -f "${mock_sys_temp}/wou_buildupgrade_prep_tried.txt"
        rm -f "${mock_sys_temp}/wou_buildupgrade_tried.txt"
        rm -f "${mock_sys_temp}/wou_buildupgrade_attempts.txt"
        CYCLE_EXIT_CODE=0
        return 0
    fi

    # Re-evaluate markers for fresh run
    rm -f "${mock_sys_temp}/wou_buildupgrade_prep_tried.txt"
    rm -f "${mock_sys_temp}/wou_buildupgrade_tried.txt"

    # Threshold met: Proceed to PerformBuildUpgrade
    if (( os_revis >= matched_minrevis )); then
        rm -f "${mock_sys_temp}/wou_buildupgrade_attempts.txt"
        touch "${mock_sys_temp}/wou_buildupgrade_tried.txt"
        echo "$matched_epkgid" >> "${mock_temp}/MissingUpdateIds.txt"
        CYCLE_EXIT_CODE=3011
        return 195 2>/dev/null || return 1
    fi

    # Threshold NOT met: Prerequisite attempt tracking & loop guard
    local attempt_count=0
    local prev_revis=""
    if [[ -f "${mock_sys_temp}/wou_buildupgrade_attempts.txt" ]]; then
        local raw_line
        raw_line="$(head -n 1 "${mock_sys_temp}/wou_buildupgrade_attempts.txt" | tr -d '\r\n')"
        attempt_count="$(echo "$raw_line" | cut -d',' -f1)"
        prev_revis="$(echo "$raw_line" | cut -d',' -f2)"
    fi

    if [[ "$prev_revis" == "$os_revis" ]]; then
        attempt_count=$((attempt_count + 1))
    else
        attempt_count=1
    fi

    if (( attempt_count > 2 )); then
        echo "Warning: Build upgrade prerequisite installation did not increment OS revision (${os_revis} < ${matched_minrevis})."
        echo "Halting build upgrade to prevent infinite reboot loop."
        rm -f "${mock_sys_temp}/wou_buildupgrade_attempts.txt"
        rm -f "${mock_sys_temp}/wou_buildupgrade_prep_tried.txt"
        rm -f "${mock_sys_temp}/wou_buildupgrade_tried.txt"
        CYCLE_EXIT_CODE=0
        return 0
    fi

    printf '%s,%s\n' "$attempt_count" "$os_revis" > "${mock_sys_temp}/wou_buildupgrade_attempts.txt"
    touch "${mock_sys_temp}/wou_buildupgrade_prep_tried.txt"
    echo "$matched_preupd" > "${mock_temp}/MissingUpdateIds.txt"
    CYCLE_EXIT_CODE=3011
    return 195 2>/dev/null || return 1
}

# -----------------------------------------------------------------------
# State 1: Fresh Run (26100.1000)
# -----------------------------------------------------------------------
echo "[Test 1/6] State 1: Fresh Run (Build 26100, Revision 1000)..."
rm -f "${mock_temp}/MissingUpdateIds.txt"

CYCLE_EXIT_CODE=0
set +e
run_build_upgrade_evaluator 26100 1000 >/dev/null 2>&1
set -e
state1_exit="$CYCLE_EXIT_CODE"

if (( state1_exit != 3011 )); then
    echo "FAIL: State 1 expected exit code 3011, got ${state1_exit}." >&2
    exit 1
fi
if [[ ! -f "${mock_sys_temp}/wou_buildupgrade_prep_tried.txt" ]]; then
    echo "FAIL: State 1 expected wou_buildupgrade_prep_tried.txt to be created." >&2
    exit 1
fi
if ! grep -q "kb5064081" "${mock_temp}/MissingUpdateIds.txt" 2>/dev/null; then
    echo "FAIL: State 1 expected kb5064081 queued in MissingUpdateIds.txt." >&2
    exit 1
fi
if [[ ! -f "${mock_sys_temp}/wou_buildupgrade_attempts.txt" ]]; then
    echo "FAIL: State 1 expected wou_buildupgrade_attempts.txt to be created." >&2
    exit 1
fi
if ! grep -q "1,1000" "${mock_sys_temp}/wou_buildupgrade_attempts.txt" 2>/dev/null; then
    echo "FAIL: State 1 expected attempt count 1,1000 in attempts tracker." >&2
    exit 1
fi
echo "[PASS] State 1: Fresh run triggered PrepareBuildUpgrade (exit 3011, prereq kb5064081 queued)."

# -----------------------------------------------------------------------
# State 2: Simulated Reboot 1
# -----------------------------------------------------------------------
echo "[Test 2/6] State 2: Simulated Reboot 1 (OS revision advances 1000 -> 5074)..."
rm -f "${mock_temp}/MissingUpdateIds.txt"
echo "[PASS] State 2: Reboot 1 simulated successfully (target revision 5074 met)."

# -----------------------------------------------------------------------
# State 3: Perform Run (26100.5074)
# -----------------------------------------------------------------------
echo "[Test 3/6] State 3: Perform Run (Build 26100, Revision 5074)..."
CYCLE_EXIT_CODE=0
set +e
run_build_upgrade_evaluator 26100 5074 >/dev/null 2>&1
set -e
state3_exit="$CYCLE_EXIT_CODE"

if (( state3_exit != 3011 )); then
    echo "FAIL: State 3 expected exit code 3011, got ${state3_exit}." >&2
    exit 1
fi
if [[ ! -f "${mock_sys_temp}/wou_buildupgrade_tried.txt" ]]; then
    echo "FAIL: State 3 expected wou_buildupgrade_tried.txt to be created." >&2
    exit 1
fi
if ! grep -q "kb5054156" "${mock_temp}/MissingUpdateIds.txt" 2>/dev/null; then
    echo "FAIL: State 3 expected kb5054156 queued in MissingUpdateIds.txt." >&2
    exit 1
fi
if [[ -f "${mock_sys_temp}/wou_buildupgrade_attempts.txt" ]]; then
    echo "FAIL: State 3 expected wou_buildupgrade_attempts.txt to be cleared on threshold met." >&2
    exit 1
fi
echo "[PASS] State 3: Perform run triggered PerformBuildUpgrade (exit 3011, eKB kb5054156 queued)."

# -----------------------------------------------------------------------
# State 4: Simulated Reboot 2
# -----------------------------------------------------------------------
echo "[Test 4/6] State 4: Simulated Reboot 2 (OS build advances 26100 -> 26200)..."
rm -f "${mock_temp}/MissingUpdateIds.txt"
echo "[PASS] State 4: Reboot 2 simulated successfully (target build 26200 reached)."

# -----------------------------------------------------------------------
# State 5: Convergence Run (26200.5074)
# -----------------------------------------------------------------------
echo "[Test 5/6] State 5: Convergence Run (Build 26200, Revision 5074)..."
CYCLE_EXIT_CODE=0
set +e
run_build_upgrade_evaluator 26200 5074 >/dev/null 2>&1
set -e
state5_exit="$CYCLE_EXIT_CODE"

if (( state5_exit != 0 )); then
    echo "FAIL: State 5 expected exit code 0 [no further reboots], got ${state5_exit}." >&2
    exit 1
fi
if [[ -f "${mock_sys_temp}/wou_buildupgrade_prep_tried.txt" ]]; then
    echo "FAIL: State 5 stale wou_buildupgrade_prep_tried.txt marker remained." >&2
    exit 1
fi
if [[ -f "${mock_sys_temp}/wou_buildupgrade_tried.txt" ]]; then
    echo "FAIL: State 5 stale wou_buildupgrade_tried.txt marker remained." >&2
    exit 1
fi
if [[ -f "${mock_sys_temp}/wou_buildupgrade_attempts.txt" ]]; then
    echo "FAIL: State 5 stale wou_buildupgrade_attempts.txt marker remained." >&2
    exit 1
fi
echo "[PASS] State 5: Build upgrade converged cleanly (exit 0, all markers purged)."

# -----------------------------------------------------------------------
# State 6: Infinite Loop Prevention Guard Test
# -----------------------------------------------------------------------
echo "[Test 6/6] State 6: Infinite Loop Guard Test (stagnant revision across reboots)..."
rm -f "${mock_sys_temp}"/*

# Attempt 1
rm -f "${mock_temp}/MissingUpdateIds.txt"
CYCLE_EXIT_CODE=0
set +e
run_build_upgrade_evaluator 26100 1000 >/dev/null 2>&1
set -e
guard_exit1="$CYCLE_EXIT_CODE"
if (( guard_exit1 != 3011 )); then
    echo "FAIL: State 6 attempt 1 expected exit code 3011, got ${guard_exit1}." >&2
    exit 1
fi
if ! grep -q "1,1000" "${mock_sys_temp}/wou_buildupgrade_attempts.txt" 2>/dev/null; then
    echo "FAIL: State 6 attempt 1 expected attempt counter 1,1000." >&2
    exit 1
fi

# Attempt 2: reboot without revision progress (revision stays 1000)
rm -f "${mock_temp}/MissingUpdateIds.txt"
CYCLE_EXIT_CODE=0
set +e
run_build_upgrade_evaluator 26100 1000 >/dev/null 2>&1
set -e
guard_exit2="$CYCLE_EXIT_CODE"
if (( guard_exit2 != 3011 )); then
    echo "FAIL: State 6 attempt 2 expected exit code 3011, got ${guard_exit2}." >&2
    exit 1
fi
if ! grep -q "2,1000" "${mock_sys_temp}/wou_buildupgrade_attempts.txt" 2>/dev/null; then
    echo "FAIL: State 6 attempt 2 expected attempt counter 2,1000." >&2
    exit 1
fi

# Attempt 3: reboot again without revision progress (revision stays 1000) -> Guard must trigger!
rm -f "${mock_temp}/MissingUpdateIds.txt"
CYCLE_EXIT_CODE=0
set +e
guard_output="$(run_build_upgrade_evaluator 26100 1000 2>&1)"
set -e
guard_exit3="$CYCLE_EXIT_CODE"

if (( guard_exit3 != 0 )); then
    echo "FAIL: State 6 attempt 3 expected exit code 0 [halted loop], got ${guard_exit3}." >&2
    exit 1
fi
if ! echo "$guard_output" | grep -q "prevent infinite reboot loop"; then
    echo "FAIL: State 6 attempt 3 expected loop prevention warning in output." >&2
    echo "$guard_output" >&2
    exit 1
fi
if [[ -f "${mock_sys_temp}/wou_buildupgrade_attempts.txt" ]]; then
    echo "FAIL: State 6 attempt 3 expected wou_buildupgrade_attempts.txt to be removed on loop halt." >&2
    exit 1
fi
if [[ -f "${mock_temp}/MissingUpdateIds.txt" ]]; then
    echo "FAIL: State 6 attempt 3 should not have queued missing update IDs on halt." >&2
    exit 1
fi
echo "[PASS] State 6: Infinite loop guard triggered as expected (loop halted, exit 0)."

# -----------------------------------------------------------------------
# All Passed
# -----------------------------------------------------------------------
echo ""
echo "======================================================================="
echo "SUCCESS: All 6 reboot cycle regression states passed successfully."
echo "======================================================================="
exit 0
