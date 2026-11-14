#!/usr/bin/env bash
# =======================================================================
# WSUS Offline Update - Full Upgrade Cycle Regression Suite (Linux / Bash)
# File: sh/tests/verify-fullupgrade-cycle.bash
#
# Evaluator twin of the CMD battery (tests\verify-fullupgrade-cycle.cmd),
# per the 31-04 cross-tier parity rule: identical embedded data + twin
# evaluators. This twin does NOT drive the CMD engine - it mirrors every
# block rule of client/cmd/DoUpdate.cmd :FullUpgrade (including the
# attempts guard, per DEC-34-04/05/06, and the upgrade-in-progress marker
# lifecycle, per DEC-35-01/02/03/06) as bash functions over the SAME
# golden rows and asserts the SAME expected literals - now over the full
# S1-S21 state set.
#
# The real-caller stub lane (RecallStub.cmd sandbox cases) is OUT OF SCOPE
# for this twin by DEC-35-08/09: the stub is a CMD-only real caller and the
# bash twin mirrors ENGINE rules only - the stub lane is gated by the phase
# gate's GATE 27 (tests\verify-recall-stub-cycle.cmd) instead.
#
#   Census: source-census block greps the REAL engine for every pinned
#           literal (the cross-check that keeps the evaluator honest
#           against engine drift) + a pinned list count
#   State S1:  no /upgradeos target -> the full-FU lane is a silent no-op
#              (zero FULLUPGRADE- lines in the evaluator output)
#   State S2:  LTSB/LTSC edition -> named skip + FULLUPGRADE-SKIP-LTSC
#   State S3:  convergence (observed build == target) -> already-observed
#              literal + record purge + NO media probe
#   State S4:  media missing (target 26999, no staged tree) ->
#              FULLUPGRADE-MEDIA-MISSING; a pre-seeded record SURVIVES
#   State S5:  media incomplete (sources\install.esd absent) ->
#              FULLUPGRADE-MEDIA-INCOMPLETE naming the file; record survives
#   State S6:  media ambiguous (en-us + fr-fr trees) ->
#              FULLUPGRADE-MEDIA-AMBIGUOUS; record survives
#   State S7:  language mismatch (en-us media vs fr-fr system) ->
#              FULLUPGRADE-LANG-REFUSED naming BOTH tokens; record survives
#   State S8:  scan refusals: 0xC1900200 -> REFUSED-SYSREQ;
#              0xC190020E -> REFUSED-DISKSPACE; no launch, no record write
#   State S9:  staged termination: SCAN 0xC1900210 + LAUNCH 3010 ->
#              SCAN-PASS then FULLUPGRADE-STAGED, RECALL_REQUIRED set,
#              record written BEFORE the launch (count 1)
#   State S10: suspect: LAUNCH 0 -> FULLUPGRADE-SUSPECT with the
#              never-reported-as-success wording, no STAGED
#   State S11: rollback: LAUNCH 0xC1900101 -> FULLUPGRADE-ROLLBACK
#   State S12: undecoded: LAUNCH 0xC1900199 -> "failed with undecoded exit
#              code 0xC1900199" + FULLUPGRADE-FAIL
#   State S13: normalization: SCAN -1047526912 (signed-decimal twin of
#              0xC1900200) -> the SAME TPM/CPU refusal as state S8a
#   State S14: attempts stall: seeded count 1 at build 26100 -> run 1
#              advances the record to 2 -> run 2 reads 2, computes 3, HALTS
#              with the stall literal + sentinel, purges the record from
#              BOTH temp paths, never reaches the launch site
#   State S15: advancement clear (a): record at build 26100, run at 26200
#              with target 26999 -> guard cleared, record rewritten fresh
#              (count 1), launch proceeds; (b) convergence fires FIRST:
#              record purged by the converged delete lines, no launch
#   State S16: audit inert: audit mode never reaches the lane (the 445-gate
#              mirror) - zero FULLUPGRADE- lines, the record is untouched
#   State S17: EKB fall-through (DEC-34-05): the EKB lane refuses the chosen
#              target for payload absence (its own frozen literal) and the
#              full-FU lane then runs the media probe and stages the same
#              target - both lanes observable in ONE run
#   State S18: marker pose (RECALL-01, DEC-35-01): a staged-pass row emits the
#              FULLUPGRADE-MARKER-POSED sentinel, a marker record exists with
#              the target build in field 2 of line 1, the attempts record
#              coexists
#   State S19: converged clear (RECALL-02 pivot): marker present + observed
#              build == target gives FULLUPGRADE-CONVERGED with BOTH records
#              gone and no media-probe rule reached
#   State S20: stall restore (RECALL-02 tail): marker present + a leg=full
#              record at the same build counting past 2 gives
#              FULLUPGRADE-STALL-HALT + RECALL-RESTORED with both records
#              gone and the armed-restore rule NOT reached when the
#              armed-state probe is false (the w100 shape)
#   State S21: refusal survival (DEC-35-09): refusal rows never emit the pose
#              sentinel and never touch a seeded marker; the marker never
#              appears in a mirrored :Cleanup rule set (the twin mirrors no
#              :Cleanup deletion rule for it - the engine-side zero-census
#              ratchet is gated by the phase gate's GATE 29)
#
# Golden rows (byte-identical with the CMD twin, tests/verify-fullupgrade-cycle.cmd):
#   StaticUpdateIds-BuildUpgrades:
#     26100,5074,kb5064081,26200,kb5054156
#     26100,5074,kb5064081,26999,kb5054156
#   Decode table (12 frozen rows - class | cause | sentinel):
#     0xC1900210 | scan-pass      | Info: Full upgrade compatibility scan found no concerns - eligible          | FULLUPGRADE-SCAN-PASS
#     0xC1900208 | refuse         | Warning: Full upgrade refused: actionable compatibility issue (app/driver)  | FULLUPGRADE-REFUSED-COMPAT
#     0xC1900204 | refuse         | Warning: Full upgrade refused: migration choice not available               | FULLUPGRADE-REFUSED-MIGCHOICE
#     0xC1900200 | refuse         | Warning: Full upgrade refused: system requirements not met (TPM/CPU)        | FULLUPGRADE-REFUSED-SYSREQ
#     0xC190020E | refuse         | Warning: Full upgrade refused: not enough free disk space                   | FULLUPGRADE-REFUSED-DISKSPACE
#     0xC190010E | refuse         | Warning: Full upgrade refused: EULA acceptance required                     | FULLUPGRADE-REFUSED-EULA
#     0xC1900215 | refuse         | Warning: Full upgrade refused: no matching install image (quiet mode)       | FULLUPGRADE-REFUSED-IMAGE
#     0xC1900132 | refuse         | Warning: Full upgrade refused: finalize resume failure                      | FULLUPGRADE-REFUSED-FINALIZE
#     0xC1900101 | fail-rollback  | Warning: Full upgrade rolled back (driver compatibility)                    | FULLUPGRADE-ROLLBACK
#     3010       | staged         | Info: Full upgrade staged - reboot required                                 | FULLUPGRADE-STAGED
#     0          | suspect        | Warning: Full upgrade exited 0 without an observed build change             | FULLUPGRADE-SUSPECT
#     other      | fail           | Warning: Full upgrade failed with undecoded exit code <code>                | FULLUPGRADE-FAIL
#
# The EKB payload cabs never exist in this twin's mock glb tree - the EKB
# lane mirror refuses deterministically in every state (the same stash
# discipline the CMD battery applies to its states S4-S17).
# =======================================================================

set -e
set -u
export LC_ALL=C

if [ -d "/usr/bin" ] && [[ ":$PATH:" != *":/usr/bin:"* ]]; then
    export PATH="/usr/bin:$PATH"
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
engine_file="${repo_root}/client/cmd/DoUpdate.cmd"

echo "======================================================================="
echo "WSUS Offline Update - Full Upgrade Cycle Regression Suite (Linux / Bash)"
echo "======================================================================="

# Set up isolated test sandbox
tmp_dir="$(mktemp -d 2>/dev/null || mktemp -d -t 'wou_fullupgrade_test')"
trap 'rm -rf "$tmp_dir"' EXIT

mock_static="${tmp_dir}/static"
mock_glb="${tmp_dir}/w100-x64/glb"
mock_temp="${tmp_dir}/temp"
mock_sys_temp="${tmp_dir}/sysroot_temp"
mock_upgrade="${tmp_dir}/upgrade"
fu_temp="${mock_sys_temp}"
fu_fallback="${tmp_dir}/systemroot_temp"

mkdir -p "$mock_static" "$mock_glb" "$mock_temp" "$mock_sys_temp" "$fu_fallback"

# Mock upgrade definition - golden rows byte-identical with the CMD twin
printf '26100,5074,kb5064081,26200,kb5054156\n' > "${mock_static}/StaticUpdateIds-BuildUpgrades.txt"
printf '26100,5074,kb5064081,26999,kb5054156\n' >> "${mock_static}/StaticUpdateIds-BuildUpgrades.txt"

# Mock staged media tree (stubs - never the real media)
mkdir -p "${mock_upgrade}/26200-x64/en-us/sources"
touch "${mock_upgrade}/26200-x64/en-us/setup.exe"
touch "${mock_upgrade}/26200-x64/en-us/sources/install.esd"

FU_EXIT_CODE=0
FU_REBOOT_REQUIRED=""
FU_RECALL_REQUIRED=""
FU_CLASS=""

function reset_fu_state () {
    rm -f "${fu_temp}/wou_fullupgrade_attempts.txt" "${fu_fallback}/wou_fullupgrade_attempts.txt"
    rm -f "${fu_temp}/wou_buildupgrade_prep_tried.txt" "${fu_temp}/wou_buildupgrade_tried.txt" "${fu_temp}/wou_buildupgrade_attempts.txt"
    rm -f "${fu_temp}/wou_upgrade_in_progress.txt" "${fu_fallback}/wou_upgrade_in_progress.txt"
    rm -f "${mock_temp}/MissingUpdateIds.txt"
    FU_EXIT_CODE=0
    FU_REBOOT_REQUIRED=""
    FU_RECALL_REQUIRED=""
    FU_CLASS=""
}

function normalize_fu_rc () {
    # Mirrors :NormalizeFuRc - the 9 frozen signed-decimal pairs (node-verified
    # 2026-11-13); passthrough for everything else.
    local raw="$1"
    case "$raw" in
        -1047526896) printf '%s' "0xC1900210" ;;
        -1047526904) printf '%s' "0xC1900208" ;;
        -1047526908) printf '%s' "0xC1900204" ;;
        -1047526912) printf '%s' "0xC1900200" ;;
        -1047526898) printf '%s' "0xC190020E" ;;
        -1047527154) printf '%s' "0xC190010E" ;;
        -1047526891) printf '%s' "0xC1900215" ;;
        -1047527118) printf '%s' "0xC1900132" ;;
        -1047527167) printf '%s' "0xC1900101" ;;
        *) printf '%s' "$raw" ;;
    esac
}

function decode_full_upgrade_exit () {
    # Mirrors :DecodeFullUpgradeExit - 12 frozen rows, no row claims success.
    # The engine emits each cause and sentinel twice (echo + :Log); the twin
    # emits once (presence is what the states assert, same as the 32 twins).
    local code="$1"
    FU_CLASS="fail"
    case "$code" in
        0xC1900210)
            FU_CLASS="scan-pass"
            printf '%s\n' "Info: Full upgrade compatibility scan found no concerns - eligible"
            printf '%s\n' "FULLUPGRADE-SCAN-PASS"
            ;;
        0xC1900208)
            FU_CLASS="refuse"
            printf '%s\n' "Warning: Full upgrade refused: actionable compatibility issue (app or driver) - see \$Windows.~BT\Sources\Panther"
            printf '%s\n' "FULLUPGRADE-REFUSED-COMPAT"
            ;;
        0xC1900204)
            FU_CLASS="refuse"
            printf '%s\n' "Warning: Full upgrade refused: migration choice not available (edition crossing not supported by setup)"
            printf '%s\n' "FULLUPGRADE-REFUSED-MIGCHOICE"
            ;;
        0xC1900200)
            FU_CLASS="refuse"
            printf '%s\n' "Warning: Full upgrade refused: system requirements not met (TPM/CPU eligibility)"
            printf '%s\n' "FULLUPGRADE-REFUSED-SYSREQ"
            ;;
        0xC190020E)
            FU_CLASS="refuse"
            printf '%s\n' "Warning: Full upgrade refused: not enough free disk space"
            printf '%s\n' "FULLUPGRADE-REFUSED-DISKSPACE"
            ;;
        0xC190010E)
            FU_CLASS="refuse"
            printf '%s\n' "Warning: Full upgrade refused: EULA acceptance required - flag-set invariant, /eula accept must always be present"
            printf '%s\n' "FULLUPGRADE-REFUSED-EULA"
            ;;
        0xC1900215)
            FU_CLASS="refuse"
            printf '%s\n' "Warning: Full upgrade refused: no matching install image for this edition (quiet mode)"
            printf '%s\n' "FULLUPGRADE-REFUSED-IMAGE"
            ;;
        0xC1900132)
            FU_CLASS="refuse"
            printf '%s\n' "Warning: Full upgrade refused: finalize resume failure - state machine invariant, must never fire in the v1 flag-set"
            printf '%s\n' "FULLUPGRADE-REFUSED-FINALIZE"
            ;;
        0xC1900101)
            FU_CLASS="fail-rollback"
            printf '%s\n' "Warning: Full upgrade rolled back (driver compatibility in most cases) - rollback logs under \$Windows.~BT\Sources\Rollback"
            printf '%s\n' "FULLUPGRADE-ROLLBACK"
            ;;
        3010)
            FU_CLASS="staged"
            printf '%s\n' "Info: Full upgrade staged - reboot required; success is decided on the next pass by the observed build"
            printf '%s\n' "FULLUPGRADE-STAGED"
            ;;
        0)
            FU_CLASS="suspect"
            printf '%s\n' "Warning: Full upgrade exited 0 without an observed build change - never reported as success; verify Panther logs"
            printf '%s\n' "FULLUPGRADE-SUSPECT"
            ;;
        *)
            FU_CLASS="fail"
            printf '%s\n' "Warning: Full upgrade failed with undecoded exit code ${code}"
            printf '%s\n' "FULLUPGRADE-FAIL"
            ;;
    esac
}

# Full-FU cycle evaluator (parity with client/cmd/DoUpdate.cmd enginespine:
# the EKB lane mirror runs first - DEC-34-05 fall-through - then the
# :FullUpgrade lane mirror: guards, observed-build convergence, physical
# media probe, language pre-flight, decode dispatch, the DEC-34-06 attempts
# guard with write-before-launch, and the launch handshake).
function run_fullupgrade_cycle_evaluator () {
    local os_build="$1"
    local os_revis="$2"
    local os_lang_ext="$3"
    local os_editionid="$4"
    local chosen_target="${5:-}"
    local test_scan_rc="${6:-}"
    local test_launch_rc="${7:-}"
    local audit_only="${8:-0}"
    local os_major="${9:-10}"

    # ---- audit gate mirror (engine line 445): audit mode bypasses BOTH lanes
    # before any install machinery - zero full-FU output, zero state writes
    if [[ "$audit_only" == "1" ]]; then
        FU_EXIT_CODE=0
        return 0
    fi

    # ---- EKB lane mirror (enginespine order; refusal producer for the fall-through)
    local matched_newbuild=""
    local target_seen=""
    local target_minrev=""
    local target_pre=""
    local target_epkg=""
    local target_found_epkg=""
    local target_found_preupd=""
    if [[ -f "${mock_static}/StaticUpdateIds-BuildUpgrades.txt" ]]; then
        local s_build s_minrev s_pre s_newbuild s_epkg row_allowed found_epkg found_preupd
        while IFS=',' read -r s_build s_minrev s_pre s_newbuild s_epkg || [[ -n "$s_build" ]]; do
            s_build="$(printf '%s' "$s_build" | tr -d '\r\n')"
            s_minrev="$(printf '%s' "$s_minrev" | tr -d '\r\n')"
            s_pre="$(printf '%s' "$s_pre" | tr -d '\r\n')"
            s_newbuild="$(printf '%s' "$s_newbuild" | tr -d '\r\n')"
            s_epkg="$(printf '%s' "$s_epkg" | tr -d '\r\n')"
            if [[ "$s_build" == "$os_build" ]]; then
                row_allowed=1
                if [[ -n "$chosen_target" && "$s_newbuild" != "$chosen_target" ]]; then
                    row_allowed=0
                fi
                if (( row_allowed == 1 )); then
                    found_epkg=0
                    if compgen -G "${mock_glb}/*${s_epkg}*.cab" >/dev/null 2>&1 || compgen -G "${mock_glb}/*${s_epkg}*.msu" >/dev/null 2>&1; then
                        found_epkg=1
                    fi
                    found_preupd=0
                    if (( os_revis >= s_minrev )); then
                        found_preupd=1
                    elif compgen -G "${mock_glb}/*${s_pre}*.cab" >/dev/null 2>&1 || compgen -G "${mock_glb}/*${s_pre}*.msu" >/dev/null 2>&1; then
                        found_preupd=1
                    fi
                    if [[ -n "$chosen_target" && "$s_newbuild" == "$chosen_target" ]]; then
                        target_seen=1
                        target_minrev="$s_minrev"
                        target_pre="$s_pre"
                        target_epkg="$s_epkg"
                        target_found_epkg="$found_epkg"
                        target_found_preupd="$found_preupd"
                    fi
                    if (( found_epkg == 1 && found_preupd == 1 )); then
                        matched_newbuild="$s_newbuild"
                    fi
                fi
            fi
        done < "${mock_static}/StaticUpdateIds-BuildUpgrades.txt"
    fi
    if [[ -n "$chosen_target" && -z "$matched_newbuild" ]]; then
        # A refusal is a pass-through producer, not a terminator: the enginespine
        # falls through into :FullUpgrade (DEC-34-05) - emit, purge the EKB
        # family, and CONTINUE to the full-FU mirror below.
        if [[ -z "$target_seen" ]]; then
            printf '%s\n' "Warning: Chosen upgrade target ${chosen_target} has no upgrade path from build ${os_build}"
            rm -f "${fu_temp}/wou_buildupgrade_prep_tried.txt" "${fu_temp}/wou_buildupgrade_tried.txt" "${fu_temp}/wou_buildupgrade_attempts.txt"
        elif [[ "$target_found_epkg" == "0" ]]; then
            printf '%s\n' "Warning: Chosen upgrade target ${chosen_target} blocked: enablement package ${target_epkg} missing from medium"
            rm -f "${fu_temp}/wou_buildupgrade_prep_tried.txt" "${fu_temp}/wou_buildupgrade_tried.txt" "${fu_temp}/wou_buildupgrade_attempts.txt"
        elif (( os_revis < target_minrev )) && [[ "$target_found_preupd" == "0" ]]; then
            printf '%s\n' "Warning: Chosen upgrade target ${chosen_target} blocked: baseline revision ${os_revis} below required ${target_minrev} and prerequisite CU ${target_pre} missing from medium"
            rm -f "${fu_temp}/wou_buildupgrade_prep_tried.txt" "${fu_temp}/wou_buildupgrade_tried.txt" "${fu_temp}/wou_buildupgrade_attempts.txt"
        fi
    fi

    # ---- :FullUpgrade mirror ----
    # no chosen target: the lane is a silent no-op
    if [[ -z "$chosen_target" ]]; then
        FU_EXIT_CODE=0
        return 0
    fi
    if (( os_major < 10 )); then
        FU_EXIT_CODE=0
        return 0
    fi
    if [[ "${os_editionid:0:11}" == "EnterpriseS" ]]; then
        printf '%s\n' "Info: Skipping full upgrade as a LTSB-/LTSC-SKU has been detected"
        printf '%s\n' "FULLUPGRADE-SKIP-LTSC"
        FU_EXIT_CODE=0
        return 0
    fi
    # Chosen-target convergence on the OBSERVED build - the only success claim
    if [[ "$os_build" == "$chosen_target" ]]; then
        printf '%s\n' "Info: Full upgrade target build ${chosen_target} already observed - jump complete"
        printf '%s\n' "FULLUPGRADE-CONVERGED"
        rm -f "${fu_temp}/wou_fullupgrade_attempts.txt" "${fu_fallback}/wou_fullupgrade_attempts.txt"
        # Mirror of call :FullUpgradeClearMarker (DEC-35-02): the converged
        # routing is one of the marker's only two legitimate deaths
        rm -f "${fu_temp}/wou_upgrade_in_progress.txt" "${fu_fallback}/wou_upgrade_in_progress.txt"
        FU_EXIT_CODE=0
        return 0
    fi
    # Physical media probe (DEC-34-02/03): zero is missing, several is
    # ambiguous, the one must carry launcher and image
    local media_base="${mock_upgrade}/${chosen_target}-x64"
    local media_count=0
    local media_lang=""
    local d
    for d in "${media_base}"/*/; do
        [[ -d "$d" ]] || continue
        media_count=$((media_count + 1))
        media_lang="$(basename "$d")"
    done
    if (( media_count == 0 )); then
        printf '%s\n' "Warning: Chosen upgrade target ${chosen_target} blocked: no full upgrade media staged for x64"
        printf '%s\n' "FULLUPGRADE-MEDIA-MISSING"
        FU_EXIT_CODE=0
        return 0
    fi
    if (( media_count > 1 )); then
        printf '%s\n' "Warning: Chosen upgrade target ${chosen_target} blocked: multiple media language directories staged for x64"
        printf '%s\n' "FULLUPGRADE-MEDIA-AMBIGUOUS"
        FU_EXIT_CODE=0
        return 0
    fi
    local fu_media="${media_base}/${media_lang}"
    local missing_file=""
    if [[ ! -f "${fu_media}/setup.exe" ]]; then
        missing_file="setup.exe"
    fi
    if [[ ! -f "${fu_media}/sources/install.esd" ]]; then
        missing_file="sources\install.esd"
    fi
    if [[ -n "$missing_file" ]]; then
        printf '%s\n' "Warning: Chosen upgrade target ${chosen_target} blocked: full upgrade media incomplete - ${missing_file} missing"
        printf '%s\n' "FULLUPGRADE-MEDIA-INCOMPLETE"
        FU_EXIT_CODE=0
        return 0
    fi
    # Language pre-flight (DEC-34-03): case-insensitive /i comparison
    if [[ "${media_lang,,}" != "${os_lang_ext,,}" ]]; then
        printf '%s\n' "Warning: Chosen upgrade target ${chosen_target} blocked: media language ${media_lang} differs from system language ${os_lang_ext}"
        printf '%s\n' "FULLUPGRADE-LANG-REFUSED"
        FU_EXIT_CODE=0
        return 0
    fi
    # Eligibility scan (APPLY-02): normalize + decode; a refused scan never
    # reaches the launch site
    local fu_rc
    fu_rc="$(normalize_fu_rc "${test_scan_rc:-0}")"
    decode_full_upgrade_exit "$fu_rc"
    if [[ "$FU_CLASS" != "scan-pass" ]]; then
        FU_EXIT_CODE=0
        return 0
    fi
    # Full-FU attempts guard (DEC-34-06): dual-path read, per-leg freshness,
    # build-keyed stall halt after count 2, advancement clear, write-before-launch
    local fu_count=1
    local fu_prev_count=""
    local fu_prev_build=""
    local fu_prev_leg=""
    local raw_line=""
    if [[ -f "${fu_temp}/wou_fullupgrade_attempts.txt" ]]; then
        raw_line="$(head -n 1 "${fu_temp}/wou_fullupgrade_attempts.txt" | tr -d '\r\n')"
        fu_prev_count="$(printf '%s' "$raw_line" | cut -d',' -f1)"
        fu_prev_build="$(printf '%s' "$raw_line" | cut -d',' -f3)"
        fu_prev_leg="$(printf '%s' "$raw_line" | cut -d',' -f4)"
    elif [[ -f "${fu_fallback}/wou_fullupgrade_attempts.txt" ]]; then
        raw_line="$(head -n 1 "${fu_fallback}/wou_fullupgrade_attempts.txt" | tr -d '\r\n')"
        fu_prev_count="$(printf '%s' "$raw_line" | cut -d',' -f1)"
        fu_prev_build="$(printf '%s' "$raw_line" | cut -d',' -f3)"
        fu_prev_leg="$(printf '%s' "$raw_line" | cut -d',' -f4)"
    fi
    if [[ -n "$fu_prev_count" && "$fu_prev_leg" == "full" && "$fu_prev_build" == "$os_build" ]]; then
        fu_count=$((fu_prev_count + 1))
        if (( fu_count > 2 )); then
            printf '%s\n' "Warning: Full upgrade did not advance the OS build (still ${os_build}) - halting to prevent infinite reboot loop"
            printf '%s\n' "FULLUPGRADE-STALL-HALT"
            rm -f "${fu_temp}/wou_fullupgrade_attempts.txt" "${fu_fallback}/wou_fullupgrade_attempts.txt"
            # Mirror of call :FullUpgradeClearMarker + the safe restore
            # (RECALL-02 tail, DEC-35-06): RECALL-RESTORED is emitted
            # unconditionally; only the armed-restore Info line (and the
            # engine's CleanupRecall call) are gated behind the armed-state
            # probe - the twin's "${fu_fallback}/WOURecall" mirror stays
            # absent in the w100-shaped sandbox, so the gate stays shut.
            rm -f "${fu_temp}/wou_upgrade_in_progress.txt" "${fu_fallback}/wou_upgrade_in_progress.txt"
            printf '%s\n' "RECALL-RESTORED"
            if [[ -d "${fu_fallback}/WOURecall" ]]; then
                printf '%s\n' "Info: Armed recall state found - restoring safe state after failed upgrade"
            fi
            FU_EXIT_CODE=0
            return 0
        fi
    fi
    # Write the attempt record BEFORE the launch - a reboot during the setup
    # invocation must not lose the count
    printf '%s,%s,%s,%s\n' "$fu_count" "$os_revis" "$os_build" "full" > "${fu_temp}/wou_fullupgrade_attempts.txt"
    # Pose the upgrade-in-progress marker beside the launch record (RECALL-01,
    # DEC-35-01) - under test mode and real mode alike; its only legitimate
    # deaths are the converged routing and the stall halt above (never
    # :Cleanup, never a refusal pass). Line 1 CSV full,<target>,<revision>,
    # line 2 the timestamp.
    printf 'full,%s,%s\n' "$chosen_target" "$os_revis" > "${fu_temp}/wou_upgrade_in_progress.txt"
    printf '%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" >> "${fu_temp}/wou_upgrade_in_progress.txt"
    printf '%s\n' "FULLUPGRADE-MARKER-POSED"
    # Launch handshake: the pass terminates unconditionally whatever setup reports
    fu_rc="$(normalize_fu_rc "${test_launch_rc:-0}")"
    decode_full_upgrade_exit "$fu_rc"
    if [[ "$fu_rc" == "3010" ]]; then
        FU_REBOOT_REQUIRED=1
    fi
    if [[ "$FU_REBOOT_REQUIRED" == "1" && "$FU_RECALL_REQUIRED" != "1" ]]; then
        FU_RECALL_REQUIRED=1
    fi
    # The Installed ladder's exit vocabulary: a staged pass (RECALL_REQUIRED=1)
    # reports "Updates pending" (3011); suspect/rollback/undecoded flows end
    # through the Cleanup path with exit 0 (parity with the CMD battery asserts)
    if [[ "$FU_RECALL_REQUIRED" == "1" ]]; then
        FU_EXIT_CODE=3011
    else
        FU_EXIT_CODE=0
    fi
    return 0
}

# -----------------------------------------------------------------------
# Census: source-census over the REAL engine - every pinned literal must
# exist in client/cmd/DoUpdate.cmd (or, for the one stub-side literal, in
# client/cmd/RecallStub.cmd) or the evaluator drifted from the engine.
# The list is byte-identical with the CMD twin's PARITY_LIT_* list (the
# 31-04 parity lock, extended 24 to 30 in the SAME commit per DEC-35-11);
# the pinned count assert keeps the lists in lockstep.
# -----------------------------------------------------------------------
echo "[Test 1/22] Census: source-census of the pinned literals over the REAL engine..."
census_literals=(
    "Skipping full upgrade as a LTSB-/LTSC-SKU has been detected"
    "already observed - jump complete"
    "blocked: no full upgrade media staged for"
    "blocked: multiple media language directories staged for"
    "blocked: full upgrade media incomplete -"
    "blocked: media language"
    "differs from system language"
    "Full upgrade compatibility scan found no concerns - eligible"
    "Full upgrade refused: actionable compatibility issue (app or driver) - see \$Windows.~BT\Sources\Panther"
    "Full upgrade refused: migration choice not available (edition crossing not supported by setup)"
    "Full upgrade refused: system requirements not met (TPM/CPU eligibility)"
    "Full upgrade refused: not enough free disk space"
    "Full upgrade refused: EULA acceptance required - flag-set invariant, /eula accept must always be present"
    "Full upgrade refused: no matching install image for this edition (quiet mode)"
    "Full upgrade refused: finalize resume failure - state machine invariant, must never fire in the v1 flag-set"
    "Full upgrade rolled back (driver compatibility in most cases) - rollback logs under \$Windows.~BT\Sources\Rollback"
    "Full upgrade staged - reboot required; success is decided on the next pass by the observed build"
    "Full upgrade exited 0 without an observed build change - never reported as success; verify Panther logs"
    "Full upgrade failed with undecoded exit code"
    "Full upgrade did not advance the OS build"
    "blocked: enablement package"
    "FULLUPGRADE-STALL-HALT"
    "FULLUPGRADE-SCAN-PASS"
    "FULLUPGRADE-STAGED"
    "wou_upgrade_in_progress.txt"
    "FullUpgradeClearMarker"
    "FULLUPGRADE-MARKER-POSED"
    "RECALL-RESTORED"
    "restoring safe state after failed upgrade"
    "Upgrade in progress - automatic recall suppressed"
)
if (( ${#census_literals[@]} != 30 )); then
    echo "FAIL: the parity census list drifted - expected 30 literals, got ${#census_literals[@]}." >&2
    exit 1
fi
stub_file="${repo_root}/client/cmd/RecallStub.cmd"
for census_lit in "${census_literals[@]}"; do
    # The stub guard Info literal (DEC-35-04) lives in RecallStub.cmd, not in
    # the engine - grep the real stub for it; everything else greps the engine.
    if [[ "$census_lit" == "Upgrade in progress - automatic recall suppressed" ]]; then
        census_target="$stub_file"
    else
        census_target="$engine_file"
    fi
    if ! grep -qF -- "$census_lit" "$census_target"; then
        echo "FAIL: source-census literal missing from the real surface: ${census_lit}" >&2
        exit 1
    fi
done
echo "[PASS] Census: all 30 pinned literals present (29 in client/cmd/DoUpdate.cmd, 1 in client/cmd/RecallStub.cmd)."

# -----------------------------------------------------------------------
# State S1: No Target - the full-FU lane is a silent no-op
# -----------------------------------------------------------------------
echo "[Test 2/22] State S1: no /upgradeos target - zero FULLUPGRADE- lines..."
reset_fu_state
set +e
run_fullupgrade_cycle_evaluator 26100 1000 en-us Professional "" "" "" 0 10 > "${tmp_dir}/s1.out" 2>&1
set -e
s1_exit="$FU_EXIT_CODE"
if [[ -s "${tmp_dir}/s1.out" ]]; then
    echo "FAIL: State S1 expected ZERO output lines (silent no-op), found:" >&2
    cat "${tmp_dir}/s1.out" >&2
    exit 1
fi
if (( s1_exit != 0 )); then
    echo "FAIL: State S1 expected exit 0, got ${s1_exit}." >&2
    exit 1
fi
echo "[PASS] State S1: no-target run emitted no full-FU line (silent no-op)."

# -----------------------------------------------------------------------
# State S2: LTSB/LTSC skip
# -----------------------------------------------------------------------
echo "[Test 3/22] State S2: LTSB/LTSC edition detected - named skip..."
reset_fu_state
set +e
run_fullupgrade_cycle_evaluator 26100 1000 en-us EnterpriseS 26200 "" "" 0 10 > "${tmp_dir}/s2.out" 2>&1
set -e
s2_exit="$FU_EXIT_CODE"
if (( s2_exit != 0 )); then
    echo "FAIL: State S2 expected exit code 0, got ${s2_exit}." >&2
    cat "${tmp_dir}/s2.out" >&2
    exit 1
fi
if ! grep -qF "Info: Skipping full upgrade as a LTSB-/LTSC-SKU has been detected" "${tmp_dir}/s2.out"; then
    echo "FAIL: State S2 expected the LTSB/LTSC skip literal verbatim." >&2
    cat "${tmp_dir}/s2.out" >&2
    exit 1
fi
if ! grep -qF "FULLUPGRADE-SKIP-LTSC" "${tmp_dir}/s2.out"; then
    echo "FAIL: State S2 expected the FULLUPGRADE-SKIP-LTSC sentinel." >&2
    cat "${tmp_dir}/s2.out" >&2
    exit 1
fi
if grep -qF "FULLUPGRADE-STAGED" "${tmp_dir}/s2.out"; then
    echo "FAIL: State S2 must not stage anything." >&2
    cat "${tmp_dir}/s2.out" >&2
    exit 1
fi
echo "[PASS] State S2: LTSC skip reported verbatim with sentinel (exit 0)."

# -----------------------------------------------------------------------
# State S3: Convergence (observed build == target)
# -----------------------------------------------------------------------
echo "[Test 4/22] State S3: observed convergence - jump complete + purge..."
reset_fu_state
printf 'stale\n' > "${fu_temp}/wou_fullupgrade_attempts.txt"
printf 'stale\n' > "${fu_temp}/wou_buildupgrade_attempts.txt"
set +e
run_fullupgrade_cycle_evaluator 26200 5074 en-us Professional 26200 "" "" 0 10 > "${tmp_dir}/s3.out" 2>&1
set -e
s3_exit="$FU_EXIT_CODE"
if (( s3_exit != 0 )); then
    echo "FAIL: State S3 expected exit code 0, got ${s3_exit}." >&2
    cat "${tmp_dir}/s3.out" >&2
    exit 1
fi
if ! grep -qF "Info: Full upgrade target build 26200 already observed - jump complete" "${tmp_dir}/s3.out"; then
    echo "FAIL: State S3 expected the full-FU convergence literal verbatim." >&2
    cat "${tmp_dir}/s3.out" >&2
    exit 1
fi
if ! grep -qF "FULLUPGRADE-CONVERGED" "${tmp_dir}/s3.out"; then
    echo "FAIL: State S3 expected the FULLUPGRADE-CONVERGED sentinel." >&2
    cat "${tmp_dir}/s3.out" >&2
    exit 1
fi
if grep -qF "no full upgrade media staged for" "${tmp_dir}/s3.out"; then
    echo "FAIL: State S3 convergence must precede the media pre-flight." >&2
    cat "${tmp_dir}/s3.out" >&2
    exit 1
fi
if [[ -f "${fu_temp}/wou_fullupgrade_attempts.txt" ]]; then
    echo "FAIL: State S3 expected the stale full-FU attempts record purged by the convergence path." >&2
    exit 1
fi
if [[ -f "${fu_temp}/wou_buildupgrade_attempts.txt" ]]; then
    echo "FAIL: State S3 expected the stale EKB attempts record purged." >&2
    exit 1
fi
echo "[PASS] State S3: convergence reported, full-FU attempts record purged, no media probe."

# -----------------------------------------------------------------------
# State S4: Media missing (target 26999 has no staged tree) - record survives
# -----------------------------------------------------------------------
echo "[Test 5/22] State S4: no media staged for the target - named refusal..."
reset_fu_state
printf '1,1000,26100,full\n' > "${fu_temp}/wou_fullupgrade_attempts.txt"
set +e
run_fullupgrade_cycle_evaluator 26100 1000 en-us Professional 26999 "" "" 0 10 > "${tmp_dir}/s4.out" 2>&1
set -e
s4_exit="$FU_EXIT_CODE"
if (( s4_exit != 0 )); then
    echo "FAIL: State S4 expected exit code 0, got ${s4_exit}." >&2
    cat "${tmp_dir}/s4.out" >&2
    exit 1
fi
if ! grep -qF "Warning: Chosen upgrade target 26999 blocked: no full upgrade media staged for x64" "${tmp_dir}/s4.out"; then
    echo "FAIL: State S4 expected the media-missing refusal literal verbatim." >&2
    cat "${tmp_dir}/s4.out" >&2
    exit 1
fi
if ! grep -qF "FULLUPGRADE-MEDIA-MISSING" "${tmp_dir}/s4.out"; then
    echo "FAIL: State S4 expected the FULLUPGRADE-MEDIA-MISSING sentinel." >&2
    cat "${tmp_dir}/s4.out" >&2
    exit 1
fi
if ! grep -qF "1,1000,26100,full" "${fu_temp}/wou_fullupgrade_attempts.txt" 2>/dev/null; then
    echo "FAIL: State S4 expected the pre-seeded attempts record to SURVIVE the refusal pass." >&2
    exit 1
fi
echo "[PASS] State S4: media-missing refusal fired verbatim, pre-seeded record survived (exit 0)."

# -----------------------------------------------------------------------
# State S5: Media incomplete (sources\install.esd absent) - record survives
# -----------------------------------------------------------------------
echo "[Test 6/22] State S5: media incomplete - names the missing file..."
reset_fu_state
printf '1,1000,26100,full\n' > "${fu_temp}/wou_fullupgrade_attempts.txt"
mv "${mock_upgrade}/26200-x64/en-us/sources/install.esd" "${tmp_dir}/s5_stash.esd"
set +e
run_fullupgrade_cycle_evaluator 26100 1000 en-us Professional 26200 "" "" 0 10 > "${tmp_dir}/s5.out" 2>&1
set -e
s5_exit="$FU_EXIT_CODE"
mv "${tmp_dir}/s5_stash.esd" "${mock_upgrade}/26200-x64/en-us/sources/install.esd"
if (( s5_exit != 0 )); then
    echo "FAIL: State S5 expected exit code 0, got ${s5_exit}." >&2
    cat "${tmp_dir}/s5.out" >&2
    exit 1
fi
if ! grep -qF "Warning: Chosen upgrade target 26200 blocked: full upgrade media incomplete - sources\install.esd missing" "${tmp_dir}/s5.out"; then
    echo "FAIL: State S5 expected the media-incomplete refusal naming sources\install.esd." >&2
    cat "${tmp_dir}/s5.out" >&2
    exit 1
fi
if ! grep -qF "FULLUPGRADE-MEDIA-INCOMPLETE" "${tmp_dir}/s5.out"; then
    echo "FAIL: State S5 expected the FULLUPGRADE-MEDIA-INCOMPLETE sentinel." >&2
    cat "${tmp_dir}/s5.out" >&2
    exit 1
fi
if ! grep -qF "1,1000,26100,full" "${fu_temp}/wou_fullupgrade_attempts.txt" 2>/dev/null; then
    echo "FAIL: State S5 expected the pre-seeded attempts record to SURVIVE the refusal pass." >&2
    exit 1
fi
echo "[PASS] State S5: media-incomplete refusal fired naming sources\install.esd, record survived (exit 0)."

# -----------------------------------------------------------------------
# State S6: Media ambiguous (two language directories staged) - record survives
# -----------------------------------------------------------------------
echo "[Test 7/22] State S6: ambiguous multi-language media tree..."
reset_fu_state
printf '1,1000,26100,full\n' > "${fu_temp}/wou_fullupgrade_attempts.txt"
mkdir -p "${mock_upgrade}/26200-x64/fr-fr"
touch "${mock_upgrade}/26200-x64/fr-fr/setup.exe"
set +e
run_fullupgrade_cycle_evaluator 26100 1000 en-us Professional 26200 "" "" 0 10 > "${tmp_dir}/s6.out" 2>&1
set -e
s6_exit="$FU_EXIT_CODE"
rm -rf "${mock_upgrade}/26200-x64/fr-fr"
if (( s6_exit != 0 )); then
    echo "FAIL: State S6 expected exit code 0, got ${s6_exit}." >&2
    cat "${tmp_dir}/s6.out" >&2
    exit 1
fi
if ! grep -qF "Warning: Chosen upgrade target 26200 blocked: multiple media language directories staged for x64" "${tmp_dir}/s6.out"; then
    echo "FAIL: State S6 expected the media-ambiguous refusal literal verbatim." >&2
    cat "${tmp_dir}/s6.out" >&2
    exit 1
fi
if ! grep -qF "FULLUPGRADE-MEDIA-AMBIGUOUS" "${tmp_dir}/s6.out"; then
    echo "FAIL: State S6 expected the FULLUPGRADE-MEDIA-AMBIGUOUS sentinel." >&2
    cat "${tmp_dir}/s6.out" >&2
    exit 1
fi
if ! grep -qF "1,1000,26100,full" "${fu_temp}/wou_fullupgrade_attempts.txt" 2>/dev/null; then
    echo "FAIL: State S6 expected the pre-seeded attempts record to SURVIVE the refusal pass." >&2
    exit 1
fi
echo "[PASS] State S6: media-ambiguous refusal fired verbatim, record survived (exit 0)."

# -----------------------------------------------------------------------
# State S7: Language mismatch (en-us media vs fr-fr system) - record survives
# -----------------------------------------------------------------------
echo "[Test 8/22] State S7: media language differs from system language..."
reset_fu_state
printf '1,1000,26100,full\n' > "${fu_temp}/wou_fullupgrade_attempts.txt"
set +e
run_fullupgrade_cycle_evaluator 26100 1000 fr-fr Professional 26200 "" "" 0 10 > "${tmp_dir}/s7.out" 2>&1
set -e
s7_exit="$FU_EXIT_CODE"
if (( s7_exit != 0 )); then
    echo "FAIL: State S7 expected exit code 0, got ${s7_exit}." >&2
    cat "${tmp_dir}/s7.out" >&2
    exit 1
fi
if ! grep -qF "Warning: Chosen upgrade target 26200 blocked: media language en-us differs from system language fr-fr" "${tmp_dir}/s7.out"; then
    echo "FAIL: State S7 expected the language refusal naming BOTH tokens verbatim." >&2
    cat "${tmp_dir}/s7.out" >&2
    exit 1
fi
if ! grep -qF "FULLUPGRADE-LANG-REFUSED" "${tmp_dir}/s7.out"; then
    echo "FAIL: State S7 expected the FULLUPGRADE-LANG-REFUSED sentinel." >&2
    cat "${tmp_dir}/s7.out" >&2
    exit 1
fi
if grep -qF "FULLUPGRADE-STAGED" "${tmp_dir}/s7.out"; then
    echo "FAIL: State S7 found a FULLUPGRADE-STAGED sentinel - a language-refused pass must never reach a launch." >&2
    cat "${tmp_dir}/s7.out" >&2
    exit 1
fi
if ! grep -qF "1,1000,26100,full" "${fu_temp}/wou_fullupgrade_attempts.txt" 2>/dev/null; then
    echo "FAIL: State S7 expected the pre-seeded attempts record to SURVIVE the refusal pass." >&2
    exit 1
fi
echo "[PASS] State S7: language refusal fired naming both tokens, record survived (exit 0)."

# -----------------------------------------------------------------------
# State S8: Scan refusals via the mock-RC hooks (hex forms)
# -----------------------------------------------------------------------
echo "[Test 9/22] State S8a: scan refusal 0xC1900200 - TPM/CPU eligibility..."
reset_fu_state
set +e
run_fullupgrade_cycle_evaluator 26100 1000 en-us Professional 26200 0xC1900200 "" 0 10 > "${tmp_dir}/s8a.out" 2>&1
set -e
s8a_exit="$FU_EXIT_CODE"
if (( s8a_exit != 0 )); then
    echo "FAIL: State S8a expected exit code 0, got ${s8a_exit}." >&2
    cat "${tmp_dir}/s8a.out" >&2
    exit 1
fi
if ! grep -qF "Warning: Full upgrade refused: system requirements not met (TPM/CPU eligibility)" "${tmp_dir}/s8a.out"; then
    echo "FAIL: State S8a expected the TPM/CPU refusal literal verbatim." >&2
    cat "${tmp_dir}/s8a.out" >&2
    exit 1
fi
if ! grep -qF "FULLUPGRADE-REFUSED-SYSREQ" "${tmp_dir}/s8a.out"; then
    echo "FAIL: State S8a expected the FULLUPGRADE-REFUSED-SYSREQ sentinel." >&2
    cat "${tmp_dir}/s8a.out" >&2
    exit 1
fi
if grep -qF "FULLUPGRADE-STAGED" "${tmp_dir}/s8a.out"; then
    echo "FAIL: State S8a must never reach the launch site past a refused scan." >&2
    cat "${tmp_dir}/s8a.out" >&2
    exit 1
fi
if [[ -f "${fu_temp}/wou_fullupgrade_attempts.txt" ]]; then
    echo "FAIL: State S8a expected NO attempts record - the guard sits past the refusal." >&2
    exit 1
fi
echo "[PASS] State S8a: scan refusal 0xC1900200 decoded to the TPM/CPU cause (exit 0, no launch, no record)."

echo "[Test 10/22] State S8b: scan refusal 0xC190020E - disk space..."
reset_fu_state
set +e
run_fullupgrade_cycle_evaluator 26100 1000 en-us Professional 26200 0xC190020E "" 0 10 > "${tmp_dir}/s8b.out" 2>&1
set -e
s8b_exit="$FU_EXIT_CODE"
if (( s8b_exit != 0 )); then
    echo "FAIL: State S8b expected exit code 0, got ${s8b_exit}." >&2
    cat "${tmp_dir}/s8b.out" >&2
    exit 1
fi
if ! grep -qF "Warning: Full upgrade refused: not enough free disk space" "${tmp_dir}/s8b.out"; then
    echo "FAIL: State S8b expected the disk-space refusal literal verbatim." >&2
    cat "${tmp_dir}/s8b.out" >&2
    exit 1
fi
if ! grep -qF "FULLUPGRADE-REFUSED-DISKSPACE" "${tmp_dir}/s8b.out"; then
    echo "FAIL: State S8b expected the FULLUPGRADE-REFUSED-DISKSPACE sentinel." >&2
    cat "${tmp_dir}/s8b.out" >&2
    exit 1
fi
echo "[PASS] State S8b: scan refusal 0xC190020E decoded to the disk-space cause (exit 0)."

# -----------------------------------------------------------------------
# State S9: Staged termination (scan passes, launch reports 3010) -
# write-before-launch observable
# -----------------------------------------------------------------------
echo "[Test 11/22] State S9: staged upgrade, record written BEFORE the launch..."
reset_fu_state
set +e
run_fullupgrade_cycle_evaluator 26100 1000 en-us Professional 26200 0xC1900210 3010 0 10 > "${tmp_dir}/s9.out" 2>&1
set -e
s9_exit="$FU_EXIT_CODE"
if (( s9_exit != 3011 )); then
    echo "FAIL: State S9 expected exit code 3011 [Updates pending], got ${s9_exit}." >&2
    cat "${tmp_dir}/s9.out" >&2
    exit 1
fi
if ! grep -qF "FULLUPGRADE-SCAN-PASS" "${tmp_dir}/s9.out"; then
    echo "FAIL: State S9 expected the FULLUPGRADE-SCAN-PASS sentinel." >&2
    cat "${tmp_dir}/s9.out" >&2
    exit 1
fi
if ! grep -qF "FULLUPGRADE-STAGED" "${tmp_dir}/s9.out"; then
    echo "FAIL: State S9 expected the FULLUPGRADE-STAGED sentinel." >&2
    cat "${tmp_dir}/s9.out" >&2
    exit 1
fi
if [[ "$FU_RECALL_REQUIRED" != "1" ]]; then
    echo "FAIL: State S9 expected RECALL_REQUIRED=1 from the staged handshake." >&2
    exit 1
fi
if ! grep -qF "1,1000,26100,full" "${fu_temp}/wou_fullupgrade_attempts.txt" 2>/dev/null; then
    echo "FAIL: State S9 expected the attempt record 1,1000,26100,full written BEFORE the launch." >&2
    exit 1
fi
echo "[PASS] State S9: staged termination proven, record written before the launch (exit 3011)."

# -----------------------------------------------------------------------
# State S10: Suspect - exit 0 without an observed build change
# -----------------------------------------------------------------------
echo "[Test 12/22] State S10: launch exit 0 without build change is the suspect row..."
reset_fu_state
set +e
run_fullupgrade_cycle_evaluator 26100 1000 en-us Professional 26200 0xC1900210 0 0 10 > "${tmp_dir}/s10.out" 2>&1
set -e
s10_exit="$FU_EXIT_CODE"
if (( s10_exit != 0 )); then
    echo "FAIL: State S10 expected exit code 0, got ${s10_exit}." >&2
    cat "${tmp_dir}/s10.out" >&2
    exit 1
fi
if ! grep -qF "Warning: Full upgrade exited 0 without an observed build change - never reported as success; verify Panther logs" "${tmp_dir}/s10.out"; then
    echo "FAIL: State S10 expected the suspect row with the never-reported-as-success wording." >&2
    cat "${tmp_dir}/s10.out" >&2
    exit 1
fi
if ! grep -qF "FULLUPGRADE-SUSPECT" "${tmp_dir}/s10.out"; then
    echo "FAIL: State S10 expected the FULLUPGRADE-SUSPECT sentinel." >&2
    cat "${tmp_dir}/s10.out" >&2
    exit 1
fi
if grep -qF "FULLUPGRADE-STAGED" "${tmp_dir}/s10.out"; then
    echo "FAIL: State S10 exit 0 must not map to the staged outcome." >&2
    cat "${tmp_dir}/s10.out" >&2
    exit 1
fi
echo "[PASS] State S10: suspect row fired with the never-success wording (exit 0)."

# -----------------------------------------------------------------------
# State S11: Rollback (0xC1900101)
# -----------------------------------------------------------------------
echo "[Test 13/22] State S11: launch exit 0xC1900101 - rollback row..."
reset_fu_state
set +e
run_fullupgrade_cycle_evaluator 26100 1000 en-us Professional 26200 0xC1900210 0xC1900101 0 10 > "${tmp_dir}/s11.out" 2>&1
set -e
s11_exit="$FU_EXIT_CODE"
if (( s11_exit != 0 )); then
    echo "FAIL: State S11 expected exit code 0, got ${s11_exit}." >&2
    cat "${tmp_dir}/s11.out" >&2
    exit 1
fi
if ! grep -qF "Warning: Full upgrade rolled back (driver compatibility in most cases) - rollback logs under \$Windows.~BT\Sources\Rollback" "${tmp_dir}/s11.out"; then
    echo "FAIL: State S11 expected the rollback literal verbatim." >&2
    cat "${tmp_dir}/s11.out" >&2
    exit 1
fi
if ! grep -qF "FULLUPGRADE-ROLLBACK" "${tmp_dir}/s11.out"; then
    echo "FAIL: State S11 expected the FULLUPGRADE-ROLLBACK sentinel." >&2
    cat "${tmp_dir}/s11.out" >&2
    exit 1
fi
echo "[PASS] State S11: rollback row fired verbatim (exit 0)."

# -----------------------------------------------------------------------
# State S12: Undecoded code (0xC1900199 -> catch-all row)
# -----------------------------------------------------------------------
echo "[Test 14/22] State S12 and S13: undecoded code + signed-decimal normalization..."
reset_fu_state
set +e
run_fullupgrade_cycle_evaluator 26100 1000 en-us Professional 26200 0xC1900210 0xC1900199 0 10 > "${tmp_dir}/s12.out" 2>&1
set -e
s12_exit="$FU_EXIT_CODE"
if (( s12_exit != 0 )); then
    echo "FAIL: State S12 expected exit code 0, got ${s12_exit}." >&2
    cat "${tmp_dir}/s12.out" >&2
    exit 1
fi
if ! grep -qF "Warning: Full upgrade failed with undecoded exit code 0xC1900199" "${tmp_dir}/s12.out"; then
    echo "FAIL: State S12 expected the catch-all row naming the code." >&2
    cat "${tmp_dir}/s12.out" >&2
    exit 1
fi
if ! grep -qF "FULLUPGRADE-FAIL" "${tmp_dir}/s12.out"; then
    echo "FAIL: State S12 expected the FULLUPGRADE-FAIL sentinel." >&2
    cat "${tmp_dir}/s12.out" >&2
    exit 1
fi
echo "[PASS] State S12: undecoded code named by the catch-all row (exit 0)."

# -----------------------------------------------------------------------
# State S13: Signed-decimal normalization (twin of state S8a)
# -----------------------------------------------------------------------
echo "    State S13: SCAN_RC=-1047526912 must decode to the same TPM/CPU refusal..."
reset_fu_state
set +e
run_fullupgrade_cycle_evaluator 26100 1000 en-us Professional 26200 -1047526912 "" 0 10 > "${tmp_dir}/s13.out" 2>&1
set -e
s13_exit="$FU_EXIT_CODE"
if (( s13_exit != 0 )); then
    echo "FAIL: State S13 expected exit code 0, got ${s13_exit}." >&2
    cat "${tmp_dir}/s13.out" >&2
    exit 1
fi
if ! grep -qF "Warning: Full upgrade refused: system requirements not met (TPM/CPU eligibility)" "${tmp_dir}/s13.out"; then
    echo "FAIL: State S13 expected the SAME TPM/CPU refusal as state S8a via the decimal twin." >&2
    cat "${tmp_dir}/s13.out" >&2
    exit 1
fi
if ! grep -qF "FULLUPGRADE-REFUSED-SYSREQ" "${tmp_dir}/s13.out"; then
    echo "FAIL: State S13 expected the FULLUPGRADE-REFUSED-SYSREQ sentinel." >&2
    cat "${tmp_dir}/s13.out" >&2
    exit 1
fi
echo "[PASS] State S13: signed-decimal -1047526912 normalized to the 0xC1900200 row (exit 0)."

# -----------------------------------------------------------------------
# State S14: Attempts stall (three stagnant launches at build 26100)
# -----------------------------------------------------------------------
echo "[Test 15/22] State S14: attempts stall - the third stagnant attempt halts..."
reset_fu_state
printf '1,1000,26100,full\n' > "${fu_temp}/wou_fullupgrade_attempts.txt"
printf 'stale-fallback\n' > "${fu_fallback}/wou_fullupgrade_attempts.txt"
# Run 1: seeded count 1 at the same build -> counter advances to 2, launch proceeds
set +e
run_fullupgrade_cycle_evaluator 26100 1000 en-us Professional 26200 0xC1900210 3010 0 10 > "${tmp_dir}/s14_run1.out" 2>&1
set -e
s14a_exit="$FU_EXIT_CODE"
if (( s14a_exit != 3011 )); then
    echo "FAIL: State S14 run 1 expected exit code 3011 (stall not yet reached), got ${s14a_exit}." >&2
    cat "${tmp_dir}/s14_run1.out" >&2
    exit 1
fi
if ! grep -qF "2,1000,26100,full" "${fu_temp}/wou_fullupgrade_attempts.txt" 2>/dev/null; then
    echo "FAIL: State S14 run 1 expected the record to advance to 2,1000,26100,full." >&2
    exit 1
fi
# Run 2 at the same stagnant build -> reads 2, computes 3, GTR 2 -> halt
set +e
run_fullupgrade_cycle_evaluator 26100 1000 en-us Professional 26200 0xC1900210 3010 0 10 > "${tmp_dir}/s14_run2.out" 2>&1
set -e
s14b_exit="$FU_EXIT_CODE"
if (( s14b_exit != 0 )); then
    echo "FAIL: State S14 run 2 expected exit code 0 [halted loop], got ${s14b_exit}." >&2
    cat "${tmp_dir}/s14_run2.out" >&2
    exit 1
fi
if ! grep -qF "Warning: Full upgrade did not advance the OS build (still 26100) - halting to prevent infinite reboot loop" "${tmp_dir}/s14_run2.out"; then
    echo "FAIL: State S14 run 2 expected the full-FU stall literal verbatim." >&2
    cat "${tmp_dir}/s14_run2.out" >&2
    exit 1
fi
if ! grep -qF "FULLUPGRADE-STALL-HALT" "${tmp_dir}/s14_run2.out"; then
    echo "FAIL: State S14 run 2 expected the FULLUPGRADE-STALL-HALT sentinel." >&2
    cat "${tmp_dir}/s14_run2.out" >&2
    exit 1
fi
if grep -qF "FULLUPGRADE-STAGED" "${tmp_dir}/s14_run2.out"; then
    echo "FAIL: State S14 run 2 must never reach the launch site past the stall halt." >&2
    cat "${tmp_dir}/s14_run2.out" >&2
    exit 1
fi
if [[ -f "${fu_temp}/wou_fullupgrade_attempts.txt" || -f "${fu_fallback}/wou_fullupgrade_attempts.txt" ]]; then
    echo "FAIL: State S14 run 2 expected the record purged from BOTH temp paths (dual-path delete)." >&2
    exit 1
fi
echo "[PASS] State S14: third stagnant attempt halted verbatim, record purged from both paths (exit 0)."

# -----------------------------------------------------------------------
# State S15: Advancement clear + convergence-first purge
# -----------------------------------------------------------------------
echo "[Test 16/22] State S15: advancement clears the guard; convergence purges first..."
# (a) record at build 26100, run at 26200 with target 26999 (media staged):
# the guard clears (in-memory), the record is rewritten fresh, launch proceeds
reset_fu_state
printf '1,1000,26100,full\n' > "${fu_temp}/wou_fullupgrade_attempts.txt"
mkdir -p "${mock_upgrade}/26999-x64/en-us/sources"
touch "${mock_upgrade}/26999-x64/en-us/setup.exe"
touch "${mock_upgrade}/26999-x64/en-us/sources/install.esd"
set +e
run_fullupgrade_cycle_evaluator 26200 5074 en-us Professional 26999 0xC1900210 3010 0 10 > "${tmp_dir}/s15a.out" 2>&1
set -e
s15a_exit="$FU_EXIT_CODE"
if (( s15a_exit != 3011 )); then
    echo "FAIL: State S15a expected exit code 3011 (advancement must proceed), got ${s15a_exit}." >&2
    cat "${tmp_dir}/s15a.out" >&2
    exit 1
fi
if ! grep -qF "FULLUPGRADE-STAGED" "${tmp_dir}/s15a.out"; then
    echo "FAIL: State S15a expected the launch to proceed after the advancement clear." >&2
    cat "${tmp_dir}/s15a.out" >&2
    exit 1
fi
if ! grep -qF "1,5074,26200,full" "${fu_temp}/wou_fullupgrade_attempts.txt" 2>/dev/null; then
    echo "FAIL: State S15a expected the record rewritten fresh at the new build (count 1)." >&2
    exit 1
fi
if ! grep -qF "has no upgrade path from build 26200" "${tmp_dir}/s15a.out"; then
    echo "FAIL: State S15a expected the EKB lane mirror to refuse the unmatchable target first." >&2
    cat "${tmp_dir}/s15a.out" >&2
    exit 1
fi
rm -rf "${mock_upgrade}/26999-x64"
# (b) convergence fires FIRST: a pre-existing record is purged, no launch
reset_fu_state
printf '1,1000,26100,full\n' > "${fu_temp}/wou_fullupgrade_attempts.txt"
set +e
run_fullupgrade_cycle_evaluator 26200 5074 en-us Professional 26200 "" "" 0 10 > "${tmp_dir}/s15b.out" 2>&1
set -e
s15b_exit="$FU_EXIT_CODE"
if (( s15b_exit != 0 )); then
    echo "FAIL: State S15b expected exit code 0, got ${s15b_exit}." >&2
    cat "${tmp_dir}/s15b.out" >&2
    exit 1
fi
if [[ -f "${fu_temp}/wou_fullupgrade_attempts.txt" ]]; then
    echo "FAIL: State S15b expected the pre-existing record purged by the converged delete lines." >&2
    exit 1
fi
if grep -qF "FULLUPGRADE-STAGED" "${tmp_dir}/s15b.out"; then
    echo "FAIL: State S15b must not launch - convergence precedes any launch consideration." >&2
    cat "${tmp_dir}/s15b.out" >&2
    exit 1
fi
echo "[PASS] State S15: advancement cleared and relaunched fresh; convergence purged before any launch."

# -----------------------------------------------------------------------
# State S16: Audit inert (audit mode never reaches the lane)
# -----------------------------------------------------------------------
echo "[Test 17/22] State S16: audit mode with a chosen target never reaches the lane..."
reset_fu_state
printf '1,1000,26100,full\n' > "${fu_temp}/wou_fullupgrade_attempts.txt"
set +e
run_fullupgrade_cycle_evaluator 26100 1000 en-us Professional 26200 "" "" 1 10 > "${tmp_dir}/s16.out" 2>&1
set -e
s16_exit="$FU_EXIT_CODE"
if (( s16_exit != 0 )); then
    echo "FAIL: State S16 expected exit code 0, got ${s16_exit}." >&2
    cat "${tmp_dir}/s16.out" >&2
    exit 1
fi
if [[ -s "${tmp_dir}/s16.out" ]]; then
    echo "FAIL: State S16 expected ZERO FULLUPGRADE- lines (and zero output) in audit mode, found:" >&2
    cat "${tmp_dir}/s16.out" >&2
    exit 1
fi
if ! grep -qF "1,1000,26100,full" "${fu_temp}/wou_fullupgrade_attempts.txt" 2>/dev/null; then
    echo "FAIL: State S16 expected the attempts record untouched by the audit drive." >&2
    exit 1
fi
echo "[PASS] State S16: audit drive emitted zero full-FU lines, record untouched (exit 0)."

# -----------------------------------------------------------------------
# State S17: EKB fall-through (DEC-34-05) - both lanes in ONE run
# -----------------------------------------------------------------------
echo "[Test 18/22] State S17: EKB refusal falls through to the full-FU media probe..."
reset_fu_state
set +e
run_fullupgrade_cycle_evaluator 26100 1000 en-us Professional 26200 0xC1900210 3010 0 10 > "${tmp_dir}/s17.out" 2>&1
set -e
s17_exit="$FU_EXIT_CODE"
if (( s17_exit != 3011 )); then
    echo "FAIL: State S17 expected exit code 3011 (the full-FU lane staged the target), got ${s17_exit}." >&2
    cat "${tmp_dir}/s17.out" >&2
    exit 1
fi
if ! grep -qF "Warning: Chosen upgrade target 26200 blocked: enablement package kb5054156 missing from medium" "${tmp_dir}/s17.out"; then
    echo "FAIL: State S17 expected the EKB lane's own missing-enablement refusal literal verbatim." >&2
    cat "${tmp_dir}/s17.out" >&2
    exit 1
fi
if ! grep -qF "FULLUPGRADE-SCAN-PASS" "${tmp_dir}/s17.out"; then
    echo "FAIL: State S17 expected the full-FU lane to run the media probe (SCAN-PASS missing)." >&2
    cat "${tmp_dir}/s17.out" >&2
    exit 1
fi
if ! grep -qF "FULLUPGRADE-STAGED" "${tmp_dir}/s17.out"; then
    echo "FAIL: State S17 expected the full-FU lane to stage the same target (STAGED missing)." >&2
    cat "${tmp_dir}/s17.out" >&2
    exit 1
fi
echo "[PASS] State S17: EKB enablement refusal AND full-FU SCAN-PASS + STAGED in one run (fall-through proven)."

# -----------------------------------------------------------------------
# State S18: Marker pose (RECALL-01, DEC-35-01) - a staged-pass row emits the
# pose sentinel, a marker record exists with the target in field 2 of line 1,
# the attempts record coexists (golden rows byte-identical with the CMD twin)
# -----------------------------------------------------------------------
echo "[Test 19/22] State S18: staged pass poses the upgrade-in-progress marker..."
reset_fu_state
set +e
run_fullupgrade_cycle_evaluator 26100 1000 en-us Professional 26200 0xC1900210 3010 0 10 > "${tmp_dir}/s18.out" 2>&1
set -e
s18_exit="$FU_EXIT_CODE"
if (( s18_exit != 3011 )); then
    echo "FAIL: State S18 expected exit code 3011 (staged pass), got ${s18_exit}." >&2
    cat "${tmp_dir}/s18.out" >&2
    exit 1
fi
if ! grep -qF "FULLUPGRADE-MARKER-POSED" "${tmp_dir}/s18.out"; then
    echo "FAIL: State S18 expected the FULLUPGRADE-MARKER-POSED sentinel." >&2
    cat "${tmp_dir}/s18.out" >&2
    exit 1
fi
if [[ ! -f "${fu_temp}/wou_upgrade_in_progress.txt" ]]; then
    echo "FAIL: State S18 expected the marker file in the mock engine temp dir." >&2
    exit 1
fi
if ! head -n 1 "${fu_temp}/wou_upgrade_in_progress.txt" | grep -q '^full,26200,'; then
    echo "FAIL: State S18 expected marker line 1 to begin with the target (full,26200,...)." >&2
    cat "${fu_temp}/wou_upgrade_in_progress.txt" >&2
    exit 1
fi
if ! grep -qF "1,1000,26100,full" "${fu_temp}/wou_fullupgrade_attempts.txt" 2>/dev/null; then
    echo "FAIL: State S18 expected the attempts record to coexist with the marker." >&2
    exit 1
fi
echo "[PASS] State S18: marker posed beside the launch record, target build on line 1 (exit 3011)."

# -----------------------------------------------------------------------
# State S19: Converged clear (RECALL-02 pivot) - marker present + observed
# build == target gives FULLUPGRADE-CONVERGED with BOTH records gone and no
# media-probe rule reached
# -----------------------------------------------------------------------
echo "[Test 20/22] State S19: convergence clears the marker and the attempts record..."
reset_fu_state
# Seed both state files with bytes a pose would never write, so the delete is
# observable as a delete of THE SEED
printf '1,1000,26100,full\n' > "${fu_temp}/wou_fullupgrade_attempts.txt"
printf 'full,26200,9999\n' > "${fu_temp}/wou_upgrade_in_progress.txt"
set +e
run_fullupgrade_cycle_evaluator 26200 5074 en-us Professional 26200 "" "" 0 10 > "${tmp_dir}/s19.out" 2>&1
set -e
s19_exit="$FU_EXIT_CODE"
if (( s19_exit != 0 )); then
    echo "FAIL: State S19 expected exit code 0, got ${s19_exit}." >&2
    cat "${tmp_dir}/s19.out" >&2
    exit 1
fi
if ! grep -qF "Info: Full upgrade target build 26200 already observed - jump complete" "${tmp_dir}/s19.out"; then
    echo "FAIL: State S19 expected the convergence literal verbatim." >&2
    cat "${tmp_dir}/s19.out" >&2
    exit 1
fi
if ! grep -qF "FULLUPGRADE-CONVERGED" "${tmp_dir}/s19.out"; then
    echo "FAIL: State S19 expected the FULLUPGRADE-CONVERGED sentinel." >&2
    cat "${tmp_dir}/s19.out" >&2
    exit 1
fi
if grep -qF "no full upgrade media staged for" "${tmp_dir}/s19.out"; then
    echo "FAIL: State S19 convergence must precede the media probe." >&2
    cat "${tmp_dir}/s19.out" >&2
    exit 1
fi
if [[ -f "${fu_temp}/wou_upgrade_in_progress.txt" ]]; then
    echo "FAIL: State S19 expected the seeded marker DELETED by the converged clear." >&2
    exit 1
fi
if [[ -f "${fu_temp}/wou_fullupgrade_attempts.txt" ]]; then
    echo "FAIL: State S19 expected the seeded attempts record DELETED by the convergence branch." >&2
    exit 1
fi
echo "[PASS] State S19: convergence cleared BOTH state files before any media probe (exit 0)."

# -----------------------------------------------------------------------
# State S20: Stall restore (RECALL-02 tail) - marker present + a leg=full
# record at the same build counting past 2 gives FULLUPGRADE-STALL-HALT +
# RECALL-RESTORED with both records gone and the armed-restore rule NOT
# reached when the armed-state probe is false (the w100 shape)
# -----------------------------------------------------------------------
echo "[Test 21/22] State S20: stall halt restores safe state behind the closed gate..."
reset_fu_state
# Seed the marker AND the attempts record at the current build (count 1)
printf '1,1000,26100,full\n' > "${fu_temp}/wou_fullupgrade_attempts.txt"
printf 'full,26200,1000\n' > "${fu_temp}/wou_upgrade_in_progress.txt"
# Run 1: the guard advances to count 2 and the pose overwrites the seed
set +e
run_fullupgrade_cycle_evaluator 26100 1000 en-us Professional 26200 0xC1900210 3010 0 10 > "${tmp_dir}/s20a.out" 2>&1
set -e
s20a_exit="$FU_EXIT_CODE"
if (( s20a_exit != 3011 )); then
    echo "FAIL: State S20 run 1 expected exit code 3011 (halt not yet reached), got ${s20a_exit}." >&2
    cat "${tmp_dir}/s20a.out" >&2
    exit 1
fi
# Run 2: reads count 2 at the same build, computes 3, GTR 2 - the halt
set +e
run_fullupgrade_cycle_evaluator 26100 1000 en-us Professional 26200 0xC1900210 3010 0 10 > "${tmp_dir}/s20b.out" 2>&1
set -e
s20b_exit="$FU_EXIT_CODE"
if (( s20b_exit != 0 )); then
    echo "FAIL: State S20 run 2 expected exit code 0 [halted], got ${s20b_exit}." >&2
    cat "${tmp_dir}/s20b.out" >&2
    exit 1
fi
if ! grep -qF "FULLUPGRADE-STALL-HALT" "${tmp_dir}/s20b.out"; then
    echo "FAIL: State S20 run 2 expected the FULLUPGRADE-STALL-HALT sentinel." >&2
    cat "${tmp_dir}/s20b.out" >&2
    exit 1
fi
if ! grep -qF "RECALL-RESTORED" "${tmp_dir}/s20b.out"; then
    echo "FAIL: State S20 run 2 expected the RECALL-RESTORED sentinel." >&2
    cat "${tmp_dir}/s20b.out" >&2
    exit 1
fi
if grep -qF "restoring safe state after failed upgrade" "${tmp_dir}/s20b.out"; then
    echo "FAIL: State S20 run 2 expected the armed-state gate SHUT (no restore Info line in the w100-shaped sandbox)." >&2
    cat "${tmp_dir}/s20b.out" >&2
    exit 1
fi
if grep -qF "FULLUPGRADE-STAGED" "${tmp_dir}/s20b.out"; then
    echo "FAIL: State S20 run 2 must never reach the launch site past the halt." >&2
    cat "${tmp_dir}/s20b.out" >&2
    exit 1
fi
if [[ -f "${fu_temp}/wou_upgrade_in_progress.txt" ]]; then
    echo "FAIL: State S20 run 2 expected the marker cleared by the halt." >&2
    exit 1
fi
if [[ -f "${fu_temp}/wou_fullupgrade_attempts.txt" ]]; then
    echo "FAIL: State S20 run 2 expected the attempts record deleted by the halt." >&2
    exit 1
fi
echo "[PASS] State S20: halt cleared both files, RECALL-RESTORED emitted, gate stayed shut (exit 0)."

# -----------------------------------------------------------------------
# State S21: Refusal survival (DEC-35-09) - refusal rows never emit the pose
# sentinel and never touch a seeded marker; the marker never appears in a
# mirrored :Cleanup rule set
# -----------------------------------------------------------------------
echo "[Test 22/22] State S21: refusals never pose; a seeded marker survives..."
# (a) never-pose: fresh machine, media-missing refusal shape (target 26999)
reset_fu_state
set +e
run_fullupgrade_cycle_evaluator 26100 1000 en-us Professional 26999 "" "" 0 10 > "${tmp_dir}/s21a.out" 2>&1
set -e
s21a_exit="$FU_EXIT_CODE"
if (( s21a_exit != 0 )); then
    echo "FAIL: State S21a expected exit code 0, got ${s21a_exit}." >&2
    cat "${tmp_dir}/s21a.out" >&2
    exit 1
fi
if ! grep -qF "FULLUPGRADE-MEDIA-MISSING" "${tmp_dir}/s21a.out"; then
    echo "FAIL: State S21a expected the media-missing refusal sentinel." >&2
    cat "${tmp_dir}/s21a.out" >&2
    exit 1
fi
if grep -qF "FULLUPGRADE-MARKER-POSED" "${tmp_dir}/s21a.out"; then
    echo "FAIL: State S21a a refusal pass emitted FULLUPGRADE-MARKER-POSED - the pose must only fire beside the launch." >&2
    cat "${tmp_dir}/s21a.out" >&2
    exit 1
fi
if [[ -f "${fu_temp}/wou_upgrade_in_progress.txt" ]]; then
    echo "FAIL: State S21a expected NO marker after a refusal pass." >&2
    exit 1
fi
# (b) survival: seed the marker, run the SAME refusal shape
printf 'full,26999,424242\n' > "${fu_temp}/wou_upgrade_in_progress.txt"
set +e
run_fullupgrade_cycle_evaluator 26100 1000 en-us Professional 26999 "" "" 0 10 > "${tmp_dir}/s21b.out" 2>&1
set -e
s21b_exit="$FU_EXIT_CODE"
if (( s21b_exit != 0 )); then
    echo "FAIL: State S21b expected exit code 0, got ${s21b_exit}." >&2
    cat "${tmp_dir}/s21b.out" >&2
    exit 1
fi
if grep -qF "FULLUPGRADE-MARKER-POSED" "${tmp_dir}/s21b.out"; then
    echo "FAIL: State S21b the seeded-machine refusal must still never pose." >&2
    cat "${tmp_dir}/s21b.out" >&2
    exit 1
fi
if [[ "$(cat "${fu_temp}/wou_upgrade_in_progress.txt")" != "full,26999,424242" ]]; then
    echo "FAIL: State S21b expected the seeded marker to survive byte-identically." >&2
    cat "${fu_temp}/wou_upgrade_in_progress.txt" >&2
    exit 1
fi
rm -f "${fu_temp}/wou_upgrade_in_progress.txt"
echo "[PASS] State S21: refusal passes never pose; the seeded marker survived byte-identically."

# -----------------------------------------------------------------------
# All Passed
# -----------------------------------------------------------------------
echo ""
echo "======================================================================="
echo "SUCCESS: All full upgrade cycle regression states passed (S1-S21)."
echo "======================================================================="
echo "FULLUPGRADE-CYCLE-PASS"
exit 0
