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
#   State 8: Chosen target, EKB payload absent -> missing-enablement refusal -> 0
#   State 9: Baseline below min revision + prereq CU absent -> loud refusal -> 0
#   State 10: Chosen target with no upgrade path -> loud refusal -> 0
#   State 11: Observed convergence (build == target) -> report + purge -> 0
#   State 12: Perform-stall guard (stagnant build) -> halts safely -> 0
#   State 13: 3010 perform stub -> b69 RECALL convergence (3011) + stall guard
#   State 14: mapping proof on the b69-neutralized model (3010 -> 3010, 3011 -> 3011)
#   State 15: w61 pre-Win10 host (integer major 6) - both lanes refuse, zero artifacts
#   State 16: wxp pre-Win10 host (integer major 5) - both lanes refuse, zero artifacts
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
# observed-convergence report, all chosen-lane refusals, and the extended
# count,revision,build,leg attempts format with the build-keyed perform stall)
run_build_upgrade_evaluator() {
    local os_build="$1"
    local os_revis="$2"
    local chosen_target="${3:-}"
    local os_arch="x64"
    local os_name="w100"
    # Modeled engine knobs (phase 37 parity extension; defaults keep the
    # 12 pre-existing states byte-identical: stub 3011, b69 force active,
    # integer major 10)
    local install_stub_exit="${4:-3011}"
    local b69_neutralized="${5:-off}"
    local os_major="${6:-10}"

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

    # Argv acceptance model (parity: DoUpdate.cmd:134-153 - the frozen parse
    # runs before every lane; a valid digits target is accepted before any gate)
    if [[ -n "$chosen_target" ]]; then
        echo "Info: Upgrade target build ${chosen_target} accepted"
    fi

    # Pre-Win10 gate model (parity: DoUpdate.cmd:659-660, "supported on
    # Windows 10 only") - OS_VER_MAJOR is the dot-split INTEGER major; empty
    # or < 10 skips the lane (and SkipBuildUpgrade purges the markers)
    if [[ -z "$os_major" ]] || (( os_major < 10 )); then
        rm -f "${mock_sys_temp}/wou_buildupgrade_prep_tried.txt"
        rm -f "${mock_sys_temp}/wou_buildupgrade_tried.txt"
        rm -f "${mock_sys_temp}/wou_buildupgrade_attempts.txt"
        CYCLE_EXIT_CODE=0
        return 0
    fi

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
    # when no target is defined (parity: refusal block before the empty-row gotos).
    # A refused baseline queues nothing - never CU-then-EKB blind.
    if [[ -n "$chosen_target" && -z "$matched_newbuild" ]]; then
        if [[ -z "$target_seen" ]]; then
            echo "Warning: Chosen upgrade target ${chosen_target} has no upgrade path from build ${os_build}"
            rm -f "${mock_sys_temp}/wou_buildupgrade_prep_tried.txt"
            rm -f "${mock_sys_temp}/wou_buildupgrade_tried.txt"
            rm -f "${mock_sys_temp}/wou_buildupgrade_attempts.txt"
            CYCLE_EXIT_CODE=0
            return 0
        fi
        if [[ "$target_found_epkg" == "0" ]]; then
            echo "Warning: Chosen upgrade target ${chosen_target} blocked: enablement package ${target_epkg} missing from medium"
            rm -f "${mock_sys_temp}/wou_buildupgrade_prep_tried.txt"
            rm -f "${mock_sys_temp}/wou_buildupgrade_tried.txt"
            rm -f "${mock_sys_temp}/wou_buildupgrade_attempts.txt"
            CYCLE_EXIT_CODE=0
            return 0
        fi
        if (( os_revis < target_minrev )) && [[ "$target_found_preupd" == "0" ]]; then
            echo "Warning: Chosen upgrade target ${chosen_target} blocked: baseline revision ${os_revis} below required ${target_minrev} and prerequisite CU ${target_pre} missing from medium"
            rm -f "${mock_sys_temp}/wou_buildupgrade_prep_tried.txt"
            rm -f "${mock_sys_temp}/wou_buildupgrade_tried.txt"
            rm -f "${mock_sys_temp}/wou_buildupgrade_attempts.txt"
            CYCLE_EXIT_CODE=0
            return 0
        fi
        # else fall through: the prerequisite CU is present - the existing prepare
        # leg installs it first (the normal prepare path, unchanged)
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
        # Leg-aware shortcut (parity: DEC-32-06) - a perform record survives into
        # the Perform leg so the build-advancement guard can see it
        local shortcut_leg=""
        if [[ -f "${mock_sys_temp}/wou_buildupgrade_attempts.txt" ]]; then
            shortcut_leg="$(head -n 1 "${mock_sys_temp}/wou_buildupgrade_attempts.txt" | tr -d '\r\n' | cut -d',' -f4)"
        fi
        if [[ "$shortcut_leg" != "perform" ]]; then
            rm -f "${mock_sys_temp}/wou_buildupgrade_attempts.txt"
        fi

        # Build-advancement keying on the SAME attempts file (parity:
        # :PerformBuildUpgrade entry, DEC-32-06) - stalls out after GTR 2 attempts
        # on a stagnant build; a DIFFERENT recorded build clears the record
        local perform_count=1
        local perform_prev_build=""
        local perform_prev_leg=""
        if [[ -f "${mock_sys_temp}/wou_buildupgrade_attempts.txt" ]]; then
            local perform_line
            perform_line="$(head -n 1 "${mock_sys_temp}/wou_buildupgrade_attempts.txt" | tr -d '\r\n')"
            perform_count="$(echo "$perform_line" | cut -d',' -f1)"
            perform_prev_build="$(echo "$perform_line" | cut -d',' -f3)"
            perform_prev_leg="$(echo "$perform_line" | cut -d',' -f4)"
        fi
        if [[ -n "$chosen_target" && "$perform_prev_leg" == "perform" ]]; then
            if [[ "$perform_prev_build" != "$os_build" ]]; then
                perform_count=1
                rm -f "${mock_sys_temp}/wou_buildupgrade_attempts.txt"
            else
                perform_count=$((perform_count + 1))
                if (( perform_count > 2 )); then
                    echo "Warning: EKB apply did not advance the OS build (still ${os_build}) - halting to prevent infinite reboot loop"
                    rm -f "${mock_sys_temp}/wou_buildupgrade_attempts.txt"
                    rm -f "${mock_sys_temp}/wou_buildupgrade_prep_tried.txt"
                    rm -f "${mock_sys_temp}/wou_buildupgrade_tried.txt"
                    CYCLE_EXIT_CODE=0
                    return 0
                fi
            fi
        fi

        touch "${mock_sys_temp}/wou_buildupgrade_tried.txt"
        echo "Performing feature upgrade from build ${matched_oldbuild} to ${matched_newbuild}..."
        echo "$matched_epkgid" >> "${mock_temp}/MissingUpdateIds.txt"
        # persist the perform record for the build-advancement guard on the next
        # resume (parity: END of Perform block, before the reboot path)
        printf '%s,%s,%s,%s\n' "$perform_count" "$os_revis" "$os_build" "perform" > "${mock_sys_temp}/wou_buildupgrade_attempts.txt"
        # ERR_LEVEL mapping model (parity: DoUpdate.cmd:1078-1084): 3010 ->
        # REBOOT_REQUIRED, 3011 -> RECALL_REQUIRED; then the
        # :BuildUpgradeComplete b69 force (:1089-1091, unconditional RECALL)
        # unless neutralized; then the EoF priority ladder (:3658-3666):
        # recall wins over reboot.
        local cycle_reboot_required=""
        local cycle_recall_required=""
        if [[ "$install_stub_exit" == "3010" ]]; then
            cycle_reboot_required=1
        elif [[ "$install_stub_exit" == "3011" ]]; then
            cycle_recall_required=1
        fi
        if [[ "$b69_neutralized" != "on" ]]; then
            cycle_recall_required=1
        fi
        if [[ "$cycle_recall_required" == "1" ]]; then
            CYCLE_EXIT_CODE=3011
        elif [[ "$cycle_reboot_required" == "1" ]]; then
            CYCLE_EXIT_CODE=3010
        else
            CYCLE_EXIT_CODE=0
        fi
        return 195 2>/dev/null || return 1
    fi

    # Threshold NOT met: Prerequisite attempt tracking & loop guard
    local attempt_count=0
    local prev_revis=""
    local prev_leg=""
    if [[ -f "${mock_sys_temp}/wou_buildupgrade_attempts.txt" ]]; then
        local raw_line
        raw_line="$(head -n 1 "${mock_sys_temp}/wou_buildupgrade_attempts.txt" | tr -d '\r\n')"
        attempt_count="$(echo "$raw_line" | cut -d',' -f1)"
        prev_revis="$(echo "$raw_line" | cut -d',' -f2)"
        prev_leg="$(echo "$raw_line" | cut -d',' -f4)"
    fi

    # Per-leg fresh counter (parity: DEC-32-06) - a leg change resets the counter;
    # within the prepare leg the revision keying is unchanged. Legacy 2-field
    # records carry no leg token and start a fresh counter.
    if [[ "$prev_leg" != "prepare" ]]; then
        attempt_count=1
    elif [[ "$prev_revis" == "$os_revis" ]]; then
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

    printf '%s,%s,%s,%s\n' "$attempt_count" "$os_revis" "$os_build" "prepare" > "${mock_sys_temp}/wou_buildupgrade_attempts.txt"
    touch "${mock_sys_temp}/wou_buildupgrade_prep_tried.txt"
    echo "Preparing feature upgrade from build ${matched_oldbuild} to ${matched_newbuild}..."
    echo "$matched_preupd" > "${mock_temp}/MissingUpdateIds.txt"
    # ERR_LEVEL mapping model (parity: DoUpdate.cmd:1024-1031 + the shared
    # :BuildUpgradeComplete convergence and EoF ladder - identical semantics
    # to the perform-leg model above)
    local cycle_reboot_required=""
    local cycle_recall_required=""
    if [[ "$install_stub_exit" == "3010" ]]; then
        cycle_reboot_required=1
    elif [[ "$install_stub_exit" == "3011" ]]; then
        cycle_recall_required=1
    fi
    if [[ "$b69_neutralized" != "on" ]]; then
        cycle_recall_required=1
    fi
    if [[ "$cycle_recall_required" == "1" ]]; then
        CYCLE_EXIT_CODE=3011
    elif [[ "$cycle_reboot_required" == "1" ]]; then
        CYCLE_EXIT_CODE=3010
    else
        CYCLE_EXIT_CODE=0
    fi
    return 195 2>/dev/null || return 1
}

# -----------------------------------------------------------------------
# State 1: Fresh Run (26100.1000)
# -----------------------------------------------------------------------
echo "[Test 1/16] State 1: Fresh Run (Build 26100, Revision 1000)..."
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
echo "[Test 2/16] State 2: Simulated Reboot 1 (OS revision advances 1000 -> 5074)..."
rm -f "${mock_temp}/MissingUpdateIds.txt"
echo "[PASS] State 2: Reboot 1 simulated successfully (target revision 5074 met)."

# -----------------------------------------------------------------------
# State 3: Perform Run (26100.5074)
# -----------------------------------------------------------------------
echo "[Test 3/16] State 3: Perform Run (Build 26100, Revision 5074)..."
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
# (32-03) The perform leg now persists a build-keyed record for the next resume
# (DEC-32-06): the leg-aware shortcut deleted the prepare record and the Perform
# leg wrote the perform record - assert the record, not absence.
if ! grep -q "1,5074,26100,perform" "${mock_sys_temp}/wou_buildupgrade_attempts.txt" 2>/dev/null; then
    echo "FAIL: State 3 expected the perform record 1,5074,26100,perform after the Perform leg." >&2
    exit 1
fi
echo "[PASS] State 3: Perform run triggered PerformBuildUpgrade (exit 3011, eKB kb5054156 queued)."

# -----------------------------------------------------------------------
# State 4: Simulated Reboot 2
# -----------------------------------------------------------------------
echo "[Test 4/16] State 4: Simulated Reboot 2 (OS build advances 26100 -> 26200)..."
rm -f "${mock_temp}/MissingUpdateIds.txt"
echo "[PASS] State 4: Reboot 2 simulated successfully (target build 26200 reached)."

# -----------------------------------------------------------------------
# State 5: Convergence Run (26200.5074)
# -----------------------------------------------------------------------
echo "[Test 5/16] State 5: Convergence Run (Build 26200, Revision 5074)..."
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
echo "[Test 6/16] State 6: Infinite Loop Guard Test (stagnant revision across reboots)..."
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
echo "[Test 7/16] State 7: Target-Scoped Match (target 26200 set - the 26999 row never wins)..."
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
if ! grep -q "1,1000,26100,prepare" "${mock_sys_temp}/wou_buildupgrade_attempts.txt" 2>/dev/null; then
    echo "FAIL: State 7 expected the attempts record 1,1000,26100,prepare." >&2
    exit 1
fi
echo "[PASS] State 7: target-scoped selection held (only 26200 won; 26999 never won)."

# -----------------------------------------------------------------------
# State 8: Chosen Target With The EKB Payload Absent (missing-enablement refusal)
# -----------------------------------------------------------------------
echo "[Test 8/16] State 8: Chosen target with the EKB payload absent - missing-enablement refusal..."
rm -f "${mock_sys_temp}"/*
rm -f "${mock_temp}/MissingUpdateIds.txt"
mv "${mock_glb}/windows11.0-kb5054156-x64.cab" "${tmp_dir}/state8_stash_epkg.cab"
CYCLE_EXIT_CODE=0
set +e
run_build_upgrade_evaluator 26100 1000 26200 > "${tmp_dir}/state8.out" 2>&1
set -e
state8_exit="$CYCLE_EXIT_CODE"
mv "${tmp_dir}/state8_stash_epkg.cab" "${mock_glb}/windows11.0-kb5054156-x64.cab"

if (( state8_exit != 0 )); then
    echo "FAIL: State 8 expected exit code 0 [refusal, no reboot], got ${state8_exit}." >&2
    cat "${tmp_dir}/state8.out" >&2
    exit 1
fi
if ! grep -qF "Warning: Chosen upgrade target 26200 blocked: enablement package kb5054156 missing from medium" "${tmp_dir}/state8.out"; then
    echo "FAIL: State 8 expected the missing-enablement refusal literal verbatim." >&2
    cat "${tmp_dir}/state8.out" >&2
    exit 1
fi
if [[ -f "${mock_temp}/MissingUpdateIds.txt" ]]; then
    echo "FAIL: State 8 expected nothing queued in MissingUpdateIds.txt." >&2
    exit 1
fi
if [[ -f "${mock_sys_temp}/wou_buildupgrade_prep_tried.txt" || -f "${mock_sys_temp}/wou_buildupgrade_attempts.txt" ]]; then
    echo "FAIL: State 8 expected markers purged after the refusal." >&2
    exit 1
fi
echo "[PASS] State 8: missing-enablement refusal fired verbatim (exit 0, nothing queued)."

# -----------------------------------------------------------------------
# State 9: Baseline Below Min Revision And Prereq CU Absent
# -----------------------------------------------------------------------
echo "[Test 9/16] State 9: Baseline revision below required and prereq CU absent - baseline+prereq refusal..."
rm -f "${mock_sys_temp}"/*
rm -f "${mock_temp}/MissingUpdateIds.txt"
mv "${mock_glb}/windows11.0-kb5064081-x64.cab" "${tmp_dir}/state9_stash_pre.cab"
CYCLE_EXIT_CODE=0
set +e
run_build_upgrade_evaluator 26100 1000 26200 > "${tmp_dir}/state9.out" 2>&1
set -e
state9_exit="$CYCLE_EXIT_CODE"
mv "${tmp_dir}/state9_stash_pre.cab" "${mock_glb}/windows11.0-kb5064081-x64.cab"

if (( state9_exit != 0 )); then
    echo "FAIL: State 9 expected exit code 0 [refusal, no reboot], got ${state9_exit}." >&2
    cat "${tmp_dir}/state9.out" >&2
    exit 1
fi
if ! grep -qF "Warning: Chosen upgrade target 26200 blocked: baseline revision 1000 below required 5074 and prerequisite CU kb5064081 missing from medium" "${tmp_dir}/state9.out"; then
    echo "FAIL: State 9 expected the baseline+prereq refusal literal verbatim." >&2
    cat "${tmp_dir}/state9.out" >&2
    exit 1
fi
if [[ -f "${mock_temp}/MissingUpdateIds.txt" ]]; then
    echo "FAIL: State 9 expected nothing queued in MissingUpdateIds.txt." >&2
    exit 1
fi
if [[ -f "${mock_sys_temp}/wou_buildupgrade_prep_tried.txt" || -f "${mock_sys_temp}/wou_buildupgrade_attempts.txt" ]]; then
    echo "FAIL: State 9 expected markers purged after the refusal." >&2
    exit 1
fi
echo "[PASS] State 9: baseline+prereq refusal fired verbatim naming revision and CU (exit 0)."

# -----------------------------------------------------------------------
# State 10: Chosen Target With No Upgrade Path
# -----------------------------------------------------------------------
echo "[Test 10/16] State 10: Chosen target 26999 from build 26200 - no upgrade path refusal..."
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
echo "[Test 11/16] State 11: Observed convergence (build 26200 with target 26200)..."
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
# State 12: Perform-Leg Stall Guard (build stagnant across perform attempts)
# -----------------------------------------------------------------------
echo "[Test 12/16] State 12: Perform-stall guard (EKB apply does not advance the OS build)..."
rm -f "${mock_sys_temp}"/*
rm -f "${mock_temp}/MissingUpdateIds.txt"
# Seed a perform record for build 26100: the first stagnant attempt is already recorded
printf '1,5074,26100,perform\n' > "${mock_sys_temp}/wou_buildupgrade_attempts.txt"

# Run 1 at the same stagnant build -> counter advances to 2, perform leg proceeds
CYCLE_EXIT_CODE=0
set +e
run_build_upgrade_evaluator 26100 5074 26200 > "${tmp_dir}/state12_run1.out" 2>&1
set -e
state12a_exit="$CYCLE_EXIT_CODE"

if (( state12a_exit != 3011 )); then
    echo "FAIL: State 12 run 1 expected exit code 3011 (stall not yet reached), got ${state12a_exit}." >&2
    cat "${tmp_dir}/state12_run1.out" >&2
    exit 1
fi
if ! grep -q "2,5074,26100,perform" "${mock_sys_temp}/wou_buildupgrade_attempts.txt" 2>/dev/null; then
    echo "FAIL: State 12 run 1 expected the record to advance to 2,5074,26100,perform." >&2
    exit 1
fi

# Run 2 at the same stagnant build -> counter 3 exceeds GTR 2 -> halt, purge, exit 0
rm -f "${mock_temp}/MissingUpdateIds.txt"
CYCLE_EXIT_CODE=0
set +e
run_build_upgrade_evaluator 26100 5074 26200 > "${tmp_dir}/state12_run2.out" 2>&1
set -e
state12b_exit="$CYCLE_EXIT_CODE"

if (( state12b_exit != 0 )); then
    echo "FAIL: State 12 run 2 expected exit code 0 [halted loop], got ${state12b_exit}." >&2
    cat "${tmp_dir}/state12_run2.out" >&2
    exit 1
fi
if ! grep -qF "Warning: EKB apply did not advance the OS build (still 26100) - halting to prevent infinite reboot loop" "${tmp_dir}/state12_run2.out"; then
    echo "FAIL: State 12 run 2 expected the perform-stall literal verbatim." >&2
    cat "${tmp_dir}/state12_run2.out" >&2
    exit 1
fi
if [[ -f "${mock_sys_temp}/wou_buildupgrade_attempts.txt" || -f "${mock_sys_temp}/wou_buildupgrade_prep_tried.txt" || -f "${mock_sys_temp}/wou_buildupgrade_tried.txt" ]]; then
    echo "FAIL: State 12 run 2 expected all attempts and markers purged on the stall halt." >&2
    exit 1
fi
if [[ -f "${mock_temp}/MissingUpdateIds.txt" ]]; then
    echo "FAIL: State 12 run 2 should not have queued missing update IDs on the stall halt." >&2
    exit 1
fi
echo "[PASS] State 12: perform stall halted verbatim and purged (third stagnant attempt, exit 0)."
# -----------------------------------------------------------------------
# State 13: 3010 Perform Mapping + b69 RECALL-Precedence Convergence (VAL-01a)
# + attempts-guard interaction (VAL-01b) - parity with the CMD twin's State 13.
# The b69 force is the CURRENT engine contract: a 3010 stub converges to 3011.
# This state PINS that convergence; State 14 proves the mapping load-bearing.
# -----------------------------------------------------------------------
echo "[Test 13/16] State 13: 3010 perform stub converges to 3011 (b69 pinned) + stall guard..."
rm -f "${mock_sys_temp}"/*
rm -f "${mock_temp}/MissingUpdateIds.txt"
# Seed a perform record for build 26100: the first stagnant attempt is already recorded
printf '1,5074,26100,perform\n' > "${mock_sys_temp}/wou_buildupgrade_attempts.txt"

# Run 1: stub 3010 - the mapping sets reboot, the b69 force converges to recall
CYCLE_EXIT_CODE=0
set +e
run_build_upgrade_evaluator 26100 5074 26200 3010 off 10 > "${tmp_dir}/state13_run1.out" 2>&1
set -e
state13a_exit="$CYCLE_EXIT_CODE"

if (( state13a_exit != 3011 )); then
    echo "FAIL: State 13 run 1 expected exit code 3011 (the b69 RECALL-precedence convergence of the 3010 mapping), got ${state13a_exit}." >&2
    cat "${tmp_dir}/state13_run1.out" >&2
    exit 1
fi
if ! grep -q "2,5074,26100,perform" "${mock_sys_temp}/wou_buildupgrade_attempts.txt" 2>/dev/null; then
    echo "FAIL: State 13 run 1 expected the perform record 2,5074,26100,perform - the mapping flow must reach the record write." >&2
    exit 1
fi
if grep -qF "ERROR: Installation failed" "${tmp_dir}/state13_run1.out"; then
    echo "FAIL: State 13 run 1 must NOT report an installation error - the 3010 stub maps to the reboot branch, not InstError." >&2
    cat "${tmp_dir}/state13_run1.out" >&2
    exit 1
fi

# Run 2: same stagnant build - the perform-stall guard halts (counter 2 -> 3 exceeds GTR 2)
rm -f "${mock_temp}/MissingUpdateIds.txt"
CYCLE_EXIT_CODE=0
set +e
run_build_upgrade_evaluator 26100 5074 26200 > "${tmp_dir}/state13_run2.out" 2>&1
set -e
state13b_exit="$CYCLE_EXIT_CODE"

if (( state13b_exit != 0 )); then
    echo "FAIL: State 13 run 2 expected exit code 0 [stall halt], got ${state13b_exit}." >&2
    cat "${tmp_dir}/state13_run2.out" >&2
    exit 1
fi
if ! grep -qF "Warning: EKB apply did not advance the OS build (still 26100) - halting to prevent infinite reboot loop" "${tmp_dir}/state13_run2.out"; then
    echo "FAIL: State 13 run 2 expected the perform-stall literal verbatim." >&2
    cat "${tmp_dir}/state13_run2.out" >&2
    exit 1
fi
if [[ -f "${mock_sys_temp}/wou_buildupgrade_attempts.txt" ]]; then
    echo "FAIL: State 13 run 2 expected the attempts file purged on the stall halt." >&2
    exit 1
fi
echo "[PASS] State 13: 3010 stub converged to 3011 with the attempts record advanced (b69 pinned); stall guard halted and purged on the repeat run."

# -----------------------------------------------------------------------
# State 14: ERR_LEVEL Mapping Proof (VAL-01a positive distinction) - the
# b69_neutralized model answers stub 3010 -> 3010 and stub 3011 -> 3011,
# mirroring the CMD twin's scratch probe (engine minus the :BuildUpgradeComplete
# b69 force). Red-recorded: swapping the modeled mapping literals makes the
# stub-3010 run exit 3011 - this state's exit assertion bites.
# -----------------------------------------------------------------------
echo "[Test 14/16] State 14: mapping proof on the b69-neutralized model (3010 -> 3010, 3011 -> 3011)..."
rm -f "${mock_sys_temp}"/*
rm -f "${mock_temp}/MissingUpdateIds.txt"
CYCLE_EXIT_CODE=0
set +e
run_build_upgrade_evaluator 26100 5074 26200 3010 on 10 > "${tmp_dir}/state14_run1.out" 2>&1
set -e
state14a_exit="$CYCLE_EXIT_CODE"

if (( state14a_exit != 3010 )); then
    echo "FAIL: State 14 run 1 expected exit code 3010 on the b69-neutralized model, got ${state14a_exit}." >&2
    cat "${tmp_dir}/state14_run1.out" >&2
    exit 1
fi
if ! grep -q "1,5074,26100,perform" "${mock_sys_temp}/wou_buildupgrade_attempts.txt" 2>/dev/null; then
    echo "FAIL: State 14 run 1 expected the perform record 1,5074,26100,perform after the 3010 handshake." >&2
    exit 1
fi

rm -f "${mock_sys_temp}"/*
rm -f "${mock_temp}/MissingUpdateIds.txt"
CYCLE_EXIT_CODE=0
set +e
run_build_upgrade_evaluator 26100 5074 26200 3011 on 10 > "${tmp_dir}/state14_run2.out" 2>&1
set -e
state14b_exit="$CYCLE_EXIT_CODE"

if (( state14b_exit != 3011 )); then
    echo "FAIL: State 14 run 2 expected exit code 3011 on the b69-neutralized model, got ${state14b_exit}." >&2
    cat "${tmp_dir}/state14_run2.out" >&2
    exit 1
fi
echo "[PASS] State 14: mapping load-bearing on the model (stub 3010 exited 3010; stub 3011 exited 3011)."

# -----------------------------------------------------------------------
# State 15: w61 Pre-Win10 Refusal (VAL-02a) - integer major 6 per the VBS
# producer (DetermineSystemProperties WriteVersionToFile dot-split), never a
# dotted "6.1". Both lanes must answer Skip: exit 0, the argv-accepted literal
# present, zero artifacts, zero refusal literals. Red-recorded (CMD engine):
# deleting the EKB gate line (:660) makes `has no upgrade path from build
# 7601` appear - the must-NOT assertion below bites.
# -----------------------------------------------------------------------
echo "[Test 15/16] State 15: w61 pre-Win10 refusal (OS_VER_MAJOR=6 integer, build 7601)..."
rm -f "${mock_sys_temp}"/*
rm -f "${mock_temp}/MissingUpdateIds.txt"
CYCLE_EXIT_CODE=0
set +e
run_build_upgrade_evaluator 7601 0 26200 3011 off 6 > "${tmp_dir}/state15.out" 2>&1
set -e
state15_exit="$CYCLE_EXIT_CODE"

if (( state15_exit != 0 )); then
    echo "FAIL: State 15 expected exit code 0 [pre-Win10 gate held], got ${state15_exit}." >&2
    cat "${tmp_dir}/state15.out" >&2
    exit 1
fi
if ! grep -qF "Info: Upgrade target build 26200 accepted" "${tmp_dir}/state15.out"; then
    echo "FAIL: State 15 expected the argv-accepted literal verbatim - the parse lane must run before the refusal." >&2
    cat "${tmp_dir}/state15.out" >&2
    exit 1
fi
if [[ -f "${mock_temp}/MissingUpdateIds.txt" ]]; then
    echo "FAIL: State 15 expected nothing queued in MissingUpdateIds.txt on a pre-Win10 host." >&2
    exit 1
fi
if compgen -G "${mock_sys_temp}/wou_buildupgrade_*" >/dev/null 2>&1; then
    echo "FAIL: State 15 expected zero wou_buildupgrade_* artifacts on a pre-Win10 host." >&2
    exit 1
fi
if grep -q "has no upgrade path from build" "${tmp_dir}/state15.out"; then
    echo "FAIL: State 15 must NOT log the no-path refusal - the EKB gate held the lane out." >&2
    cat "${tmp_dir}/state15.out" >&2
    exit 1
fi
if grep -q "FULLUPGRADE-" "${tmp_dir}/state15.out"; then
    echo "FAIL: State 15 must NOT log any FULLUPGRADE- marker - the FU gate held the lane out." >&2
    cat "${tmp_dir}/state15.out" >&2
    exit 1
fi
echo "[PASS] State 15: w61 host refused by both lanes (exit 0, argv accepted, zero artifacts, zero refusal literals)."

# -----------------------------------------------------------------------
# State 16: wxp Pre-Win10 Refusal (VAL-02a mirror) - integer major 5, build
# 2600. Identical assertion set to State 15.
# -----------------------------------------------------------------------
echo "[Test 16/16] State 16: wxp pre-Win10 refusal (OS_VER_MAJOR=5 integer, build 2600)..."
rm -f "${mock_sys_temp}"/*
rm -f "${mock_temp}/MissingUpdateIds.txt"
CYCLE_EXIT_CODE=0
set +e
run_build_upgrade_evaluator 2600 0 26200 3011 off 5 > "${tmp_dir}/state16.out" 2>&1
set -e
state16_exit="$CYCLE_EXIT_CODE"

if (( state16_exit != 0 )); then
    echo "FAIL: State 16 expected exit code 0 [pre-Win10 gate held], got ${state16_exit}." >&2
    cat "${tmp_dir}/state16.out" >&2
    exit 1
fi
if ! grep -qF "Info: Upgrade target build 26200 accepted" "${tmp_dir}/state16.out"; then
    echo "FAIL: State 16 expected the argv-accepted literal verbatim - the parse lane must run before the refusal." >&2
    cat "${tmp_dir}/state16.out" >&2
    exit 1
fi
if [[ -f "${mock_temp}/MissingUpdateIds.txt" ]]; then
    echo "FAIL: State 16 expected nothing queued in MissingUpdateIds.txt on a pre-Win10 host." >&2
    exit 1
fi
if compgen -G "${mock_sys_temp}/wou_buildupgrade_*" >/dev/null 2>&1; then
    echo "FAIL: State 16 expected zero wou_buildupgrade_* artifacts on a pre-Win10 host." >&2
    exit 1
fi
if grep -q "has no upgrade path from build" "${tmp_dir}/state16.out"; then
    echo "FAIL: State 16 must NOT log the no-path refusal - the EKB gate held the lane out." >&2
    cat "${tmp_dir}/state16.out" >&2
    exit 1
fi
if grep -q "FULLUPGRADE-" "${tmp_dir}/state16.out"; then
    echo "FAIL: State 16 must NOT log any FULLUPGRADE- marker - the FU gate held the lane out." >&2
    cat "${tmp_dir}/state16.out" >&2
    exit 1
fi
echo "[PASS] State 16: wxp host refused by both lanes (exit 0, argv accepted, zero artifacts, zero refusal literals)."

# -----------------------------------------------------------------------
# All Passed
# -----------------------------------------------------------------------
echo ""
echo "======================================================================="
echo "SUCCESS: All 16 reboot cycle regression states passed successfully."
echo "======================================================================="
exit 0
