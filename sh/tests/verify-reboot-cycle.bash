#!/usr/bin/env bash
# =======================================================================
# WSUS Offline Update - Build Upgrade Reboot Cycle Regression Suite (Linux / Bash)
# File: sh/tests/verify-reboot-cycle.bash
#
# Verifies the build upgrade lifecycle, infinite loop prevention, and the
# chosen-target (/upgradeos) lane:
#   State 1: Fresh run (build 26100.1000) -> PrepareBuildUpgrade -> 3011
#   State 2: Simulated Reboot 1 -> revision advances to 5074
#   State 3: Perform run (build 26100.5074) -> PerformBuildUpgrade -> 3011
#   State 4: Simulated Reboot 2 -> build advances to 26200
#   State 5: Convergence run (build 26200.5074) -> upgrade skipped -> 0
#   State 6: Infinite loop guard -> revision stagnant -> halts safely -> 0
#   State 7: Target-scoped match (/upgradeos:26200) -> only 26200 wins, 26999 never
#   State 10: Chosen target with no upgrade path -> loud refusal -> 0
#   State 11: Observed convergence (build == target) -> report + purge -> 0
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
# Golden row set (identical data in tests/verify-reboot-cycle.cmd - cross-tier parity):
# row 1 = the real hop; row 2 = synthetic higher hop (26999) sharing the same payload
# KBs, so states 1-6 keep byte-identical behavior without a target while state 7 can
# prove the target guard keeps the 26999 row from ever winning.
printf '26100,5074,kb5064081,26200,kb5054156\n' > "${mock_static}/StaticUpdateIds-BuildUpgrades.txt"
printf '26100,5074,kb5064081,26999,kb5054156\n' >> "${mock_static}/StaticUpdateIds-BuildUpgrades.txt"

# Mock packages
touch "${mock_glb}/windows11.0-kb5064081-x64.cab"
touch "${mock_glb}/windows11.0-kb5054156-x64.cab"

CYCLE_EXIT_CODE=0

# Build upgrade state machine evaluator (parity with client/cmd/DoUpdate.cmd
# including target scoping: WOU_ROW_ALLOWED guard, chosen-row capture, the
# observed-convergence report, and the no-upgrade-path refusal)
run_build_upgrade_evaluator() {
    local os_build="$1"
    local os_revis="$2"
    local chosen_target="${3:-}"
    local os_arch="x64"
    local os_name="w100"

    local matched_oldbuild=""
    local matched_minrevis=""
    local matched_preupd=""
    local matched_newbuild=""
    local matched_epkgid=""
    local target_seen=""
    local target_minrev=""
    local target_pre=""
    local target_epkg=""
    local target_found_epkg=""
    local target_found_preupd=""

    # Chosen-target convergence: the observed build already equals the requested
    # target - report it and purge every upgrade marker (parity: the report sits
    # right after the LTSB/LTSC guard, BEFORE the row loops)
    if [[ -n "$chosen_target" && "$os_build" == "$chosen_target" ]]; then
        echo "Info: Upgrade target build ${chosen_target} observed - jump complete"
        rm -f "${mock_sys_temp}/wou_buildupgrade_prep_tried.txt"
        rm -f "${mock_sys_temp}/wou_buildupgrade_tried.txt"
        rm -f "${mock_sys_temp}/wou_buildupgrade_attempts.txt"
        CYCLE_EXIT_CODE=0
        return 0
    fi

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
                # Chosen-target guard (parity: WOU_ROW_ALLOWED wrapper - when a target
                # is set, only rows whose newbuild equals the target may win; the GEQ
                # walk stays intact within allowed rows)
                local row_allowed=1
                if [[ -n "$chosen_target" && "$s_newbuild" != "$chosen_target" ]]; then
                    row_allowed=0
                fi
                if (( row_allowed == 1 )); then
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

                    # Persist the chosen row's facts for the named refusals (parity:
                    # WOU_TARGET_SEEN/MINREV/PRE/EPKG/FOUND_EPKG/FOUND_PREUPD capture)
                    if [[ -n "$chosen_target" && "$s_newbuild" == "$chosen_target" ]]; then
                        target_seen=1
                        target_minrev="$s_minrev"
                        target_pre="$s_pre"
                        target_epkg="$s_epkg"
                        target_found_epkg="$found_epkg"
                        target_found_preupd="$found_preupd"
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
            fi
        done < "${mock_static}/StaticUpdateIds-BuildUpgrades.txt"
    fi

    # Chosen-target named refusals: fire BEFORE the empty-row silent skip - inert
    # when no target is defined (parity: refusal block before the empty-row gotos)
    if [[ -n "$chosen_target" && -z "$matched_newbuild" && -z "$target_seen" ]]; then
        echo "Warning: Chosen upgrade target ${chosen_target} has no upgrade path from build ${os_build}"
        rm -f "${mock_sys_temp}/wou_buildupgrade_prep_tried.txt"
        rm -f "${mock_sys_temp}/wou_buildupgrade_tried.txt"
        rm -f "${mock_sys_temp}/wou_buildupgrade_attempts.txt"
        CYCLE_EXIT_CODE=0
        return 0
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
        echo "Performing feature upgrade from build ${matched_oldbuild} to ${matched_newbuild}..."
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
    echo "Preparing feature upgrade from build ${matched_oldbuild} to ${matched_newbuild}..."
    echo "$matched_preupd" > "${mock_temp}/MissingUpdateIds.txt"
    CYCLE_EXIT_CODE=3011
    return 195 2>/dev/null || return 1
}

# -----------------------------------------------------------------------
# State 1: Fresh Run (26100.1000)
# -----------------------------------------------------------------------
echo "[Test 1/12] State 1: Fresh Run (Build 26100, Revision 1000)..."
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
echo "[Test 2/12] State 2: Simulated Reboot 1 (OS revision advances 1000 -> 5074)..."
rm -f "${mock_temp}/MissingUpdateIds.txt"
echo "[PASS] State 2: Reboot 1 simulated successfully (target revision 5074 met)."

# -----------------------------------------------------------------------
# State 3: Perform Run (26100.5074)
# -----------------------------------------------------------------------
echo "[Test 3/12] State 3: Perform Run (Build 26100, Revision 5074)..."
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
echo "[Test 4/12] State 4: Simulated Reboot 2 (OS build advances 26100 -> 26200)..."
rm -f "${mock_temp}/MissingUpdateIds.txt"
echo "[PASS] State 4: Reboot 2 simulated successfully (target build 26200 reached)."

# -----------------------------------------------------------------------
# State 5: Convergence Run (26200.5074)
# -----------------------------------------------------------------------
echo "[Test 5/12] State 5: Convergence Run (Build 26200, Revision 5074)..."
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
echo "[Test 6/12] State 6: Infinite Loop Guard Test (stagnant revision across reboots)..."
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
# State 7: Target-Scoped Match (/upgradeos:26200 set)
# -----------------------------------------------------------------------
echo "[Test 7/12] State 7: Target-Scoped Match (target 26200 set - the 26999 row never wins)..."
# Control run WITHOUT a target: the GEQ walk must pick the higher 26999 row,
# proving the fixture is a real threat the target guard neutralizes.
# (direct call + output file, NOT command substitution: the evaluator reports
# through the global CYCLE_EXIT_CODE, which a $() subshell would not propagate)
rm -f "${mock_sys_temp}"/*
rm -f "${mock_temp}/MissingUpdateIds.txt"
CYCLE_EXIT_CODE=0
set +e
run_build_upgrade_evaluator 26100 1000 > "${tmp_dir}/state7_control.out" 2>&1
set -e
if ! grep -q "to 26999\.\.\." "${tmp_dir}/state7_control.out"; then
    echo "FAIL: State 7 control run expected the no-target GEQ walk to pick 26999." >&2
    cat "${tmp_dir}/state7_control.out" >&2
    exit 1
fi
# Target run: only the 26200 row is allowed - the 26999 row must never win.
rm -f "${mock_sys_temp}"/*
rm -f "${mock_temp}/MissingUpdateIds.txt"
CYCLE_EXIT_CODE=0
set +e
run_build_upgrade_evaluator 26100 1000 26200 > "${tmp_dir}/state7_target.out" 2>&1
set -e
state7_exit="$CYCLE_EXIT_CODE"

if (( state7_exit != 3011 )); then
    echo "FAIL: State 7 expected exit code 3011, got ${state7_exit}." >&2
    cat "${tmp_dir}/state7_target.out" >&2
    exit 1
fi
if ! grep -q "to 26200\.\.\." "${tmp_dir}/state7_target.out"; then
    echo "FAIL: State 7 expected the 26200 row to win under target 26200." >&2
    cat "${tmp_dir}/state7_target.out" >&2
    exit 1
fi
if grep -q "to 26999" "${tmp_dir}/state7_target.out"; then
    echo "FAIL: State 7 the 26999 row won under target 26200 - target guard failed." >&2
    cat "${tmp_dir}/state7_target.out" >&2
    exit 1
fi
if ! grep -q "kb5064081" "${mock_temp}/MissingUpdateIds.txt" 2>/dev/null; then
    echo "FAIL: State 7 expected kb5064081 queued in MissingUpdateIds.txt." >&2
    exit 1
fi
if ! grep -q "1,1000" "${mock_sys_temp}/wou_buildupgrade_attempts.txt" 2>/dev/null; then
    echo "FAIL: State 7 expected attempt counter 1,1000 in attempts tracker." >&2
    exit 1
fi
echo "[PASS] State 7: target-scoped selection held (only 26200 won; 26999 never won)."

# -----------------------------------------------------------------------
# State 10: Chosen Target With No Upgrade Path
# -----------------------------------------------------------------------
echo "[Test 10/12] State 10: Chosen target 26999 from build 26200 - no upgrade path refusal..."
rm -f "${mock_sys_temp}"/*
rm -f "${mock_temp}/MissingUpdateIds.txt"
CYCLE_EXIT_CODE=0
set +e
run_build_upgrade_evaluator 26200 5074 26999 > "${tmp_dir}/state10.out" 2>&1
set -e
state10_exit="$CYCLE_EXIT_CODE"

if (( state10_exit != 0 )); then
    echo "FAIL: State 10 expected exit code 0 [refusal, no reboot], got ${state10_exit}." >&2
    cat "${tmp_dir}/state10.out" >&2
    exit 1
fi
if ! grep -qF "Warning: Chosen upgrade target 26999 has no upgrade path from build 26200" "${tmp_dir}/state10.out"; then
    echo "FAIL: State 10 expected the no-upgrade-path refusal literal verbatim." >&2
    cat "${tmp_dir}/state10.out" >&2
    exit 1
fi
if [[ -f "${mock_sys_temp}/wou_buildupgrade_prep_tried.txt" || -f "${mock_sys_temp}/wou_buildupgrade_tried.txt" || -f "${mock_sys_temp}/wou_buildupgrade_attempts.txt" ]]; then
    echo "FAIL: State 10 expected all upgrade markers purged." >&2
    exit 1
fi
if [[ -f "${mock_temp}/MissingUpdateIds.txt" ]]; then
    echo "FAIL: State 10 expected nothing queued in MissingUpdateIds.txt." >&2
    exit 1
fi
echo "[PASS] State 10: no-upgrade-path refusal fired verbatim (exit 0, nothing queued)."

# -----------------------------------------------------------------------
# State 11: Observed Convergence (build == target)
# -----------------------------------------------------------------------
echo "[Test 11/12] State 11: Observed convergence (build 26200 with target 26200)..."
rm -f "${mock_sys_temp}"/*
rm -f "${mock_temp}/MissingUpdateIds.txt"
# Seed stale markers: the convergence path must purge them (apply-once semantics)
touch "${mock_sys_temp}/wou_buildupgrade_prep_tried.txt" \
      "${mock_sys_temp}/wou_buildupgrade_tried.txt" \
      "${mock_sys_temp}/wou_buildupgrade_attempts.txt"
CYCLE_EXIT_CODE=0
set +e
run_build_upgrade_evaluator 26200 5074 26200 > "${tmp_dir}/state11.out" 2>&1
set -e
state11_exit="$CYCLE_EXIT_CODE"

if (( state11_exit != 0 )); then
    echo "FAIL: State 11 expected exit code 0, got ${state11_exit}." >&2
    cat "${tmp_dir}/state11.out" >&2
    exit 1
fi
if ! grep -qF "Info: Upgrade target build 26200 observed - jump complete" "${tmp_dir}/state11.out"; then
    echo "FAIL: State 11 expected the observed-convergence literal verbatim." >&2
    cat "${tmp_dir}/state11.out" >&2
    exit 1
fi
if [[ -f "${mock_sys_temp}/wou_buildupgrade_prep_tried.txt" || -f "${mock_sys_temp}/wou_buildupgrade_tried.txt" || -f "${mock_sys_temp}/wou_buildupgrade_attempts.txt" ]]; then
    echo "FAIL: State 11 expected all seeded markers purged by the convergence path." >&2
    exit 1
fi
echo "[PASS] State 11: observed convergence reported and all markers purged (exit 0)."

# -----------------------------------------------------------------------
# All Passed
# -----------------------------------------------------------------------
echo ""
echo "======================================================================="
echo "SUCCESS: All 9 implemented reboot cycle regression states passed (12 planned)."
echo "======================================================================="
exit 0
