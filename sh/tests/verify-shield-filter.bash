#!/usr/bin/env bash
# =======================================================================
# WSUS Offline Update - Shield-Feed Chosen-Target Filter Battery (Bash)
# File: sh/tests/verify-shield-filter.bash
#
# Sandbox battery for the Phase-32 bash chosen-target mirror (plan 32-02,
# DEC-32-05 / DEC-32-08 / DEC-32-09): the reader cases execute the REAL
# library function read_upgrade_selection from
# sh/libraries/upgrade-selection.bash, and the feed cases mirror the
# production hop-walk membership semantics of
# sh/download-updates-tasks/50-superseded-updates.bash in a battery-side
# parity evaluator. The frozen expectations are identical to the CMD
# battery tests/verify-shield-filter.cmd (cross-tier parity):
#
#   Reader case 1: absent selection file               -> empty output
#   Reader case 2: 26200_x64=on                        -> exactly 26200_x64
#   Reader case 3: 19045_x64=on + 26200_x64=on         -> both keys in order
#   Reader case 4: one valid key + one bad line        -> EMPTY output
#                                                     (all-or-nothing)
#   Reader case 5: CRLF fixture + blank tail line      -> case 2 result
#                                                     unchanged (CR stripped)
#   Feed case 6:   selection 26200_x64                 -> exactly
#                                                     windows10.0-kb5064081
#   Feed case 7:   selection 26200_x64 + 19045_x64     -> windows10.0-kb5021233
#                                                     (3 rows) + kb5064081
#   Feed case 8:   no selection                        -> full statu-quo
#                                                     golden feed
#
# Fixture hop files are copies of the committed census data (6 optional
# + 2 forced rows - committed data, not runtime state). Every selection
# fixture lives in the sandbox - the battery NEVER reads or writes the
# repo's gitignored runtime-state files (sh/os-upgrades.ini,
# sh/windows-10-versions.ini; 31-04 prohibition carried forward).
#
# Success sentinel: SHIELD-FILTER-BASH-PASS. Every failure prints a
# named FAIL: line and exits 1.
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
echo "WSUS Offline Update - Shield-Feed Filter Battery (Bash)"
echo "======================================================================="

# Isolated sandbox: fixture tree mirroring sh/ + client/static
tmp_dir="$(mktemp -d 2>/dev/null || mktemp -d -t 'wou_shield_test')"
trap 'rm -rf "$tmp_dir"' EXIT

sb_static="${tmp_dir}/client/static"
sb_sh="${tmp_dir}/sh"
sb_feed="${tmp_dir}/feed"
mkdir -p "${sb_static}" "${sb_sh}" "${sb_feed}"

# Fixture hop files: copies of the committed census data (the battery
# consumes copies under its sandbox - the committed files are frozen)
cp "${repo_root}/client/static/StaticUpdateIds-BuildUpgrades.txt" \
   "${sb_static}/StaticUpdateIds-BuildUpgrades.txt"
cp "${repo_root}/client/static/StaticUpdateIds-BuildUpgradesForced.txt" \
   "${sb_static}/StaticUpdateIds-BuildUpgradesForced.txt"

# Census pin: the goldens below are frozen against 6 optional + 2 forced
# rows - upstream drift must fail loudly instead of validating stale
# goldens (same gate as the CMD battery).
hop_rows="$(grep -c '^[0-9]' "${sb_static}/StaticUpdateIds-BuildUpgrades.txt" || true)"
forced_rows="$(grep -c '^[0-9]' "${sb_static}/StaticUpdateIds-BuildUpgradesForced.txt" || true)"
if [[ "${hop_rows}" != "6" ]]
then
    printf 'FAIL: hop census drifted - fixture StaticUpdateIds-BuildUpgrades.txt carries %s rows, golden expects 6; re-freeze the battery goldens.\n' "${hop_rows}"
    exit 1
fi
if [[ "${forced_rows}" != "2" ]]
then
    printf 'FAIL: forced census drifted - fixture StaticUpdateIds-BuildUpgradesForced.txt carries %s rows, golden expects 2; re-freeze the battery goldens.\n' "${forced_rows}"
    exit 1
fi

# The reader cases execute the REAL library (DEC-32-09: the library is
# functions-only, so sourcing it has no side effects on the sandbox)
library_file="${repo_root}/sh/libraries/upgrade-selection.bash"
if [[ ! -f "${library_file}" ]]
then
    printf 'FAIL: library not found at %s\n' "${library_file}"
    exit 1
fi
# shellcheck disable=SC1090
source "${library_file}"
if ! declare -F read_upgrade_selection > /dev/null
then
    printf 'FAIL: %s does not define read_upgrade_selection - the battery must execute the real library reader\n' "${library_file}"
    exit 1
fi

# -----------------------------------------------------------------------
# Battery-side parity evaluator for the feed cases: mirrors the
# chosen-target membership semantics of the production walk in
# sh/download-updates-tasks/50-superseded-updates.bash (build-part list,
# whole-token equality over field 4, empty list = statu quo). The
# production walk itself needs the wsusscn2 catalog; parity with the
# CMD battery comes from the identical frozen expectations.
# UPGB_TARGETS is the caller-visible build-part list (empty = no
# selection).
# -----------------------------------------------------------------------
UPGB_TARGETS=()

feed_evaluator ()
{
    local out_file="$1"
    local field_1="" field_2="" kb_number="" field_4="" skip_rest=""
    local upg_target="" upg_emit=0

    : > "${out_file}"
    cat "${sb_static}/StaticUpdateIds-BuildUpgrades.txt"        \
        "${sb_static}/StaticUpdateIds-BuildUpgradesForced.txt"  \
    | while IFS=$',\r\n' read -r field_1 field_2 kb_number field_4 skip_rest
    do
        upg_emit=0

        if (( "${#UPGB_TARGETS[@]}" == 0 ))
        then
            upg_emit=1
        else
            for upg_target in "${UPGB_TARGETS[@]}"
            do
                if [[ "${field_4}" == "${upg_target}" ]]
                then
                    upg_emit=1
                fi
            done
        fi

        if [[ -n "${kb_number}" ]] && (( "${upg_emit}" == 1 ))
        then
            printf '%s\n' "windows10.0-${kb_number}"
        fi
    done > "${out_file}"
    return 0
}

# Byte-frozen statu-quo golden feed: 6 optional rows then 2 forced rows
# in file order (identical to :BuildGolden in the CMD battery)
build_golden_feed ()
{
    local out_file="$1"
    printf '%s\n' windows10.0-kb5008212 windows10.0-kb5008212 \
                  windows10.0-kb5021233 windows10.0-kb5021233 \
                  windows10.0-kb5021233 windows10.0-kb5064081 \
                  windows10.0-kb5008212 windows10.0-kb5008212 \
    > "${out_file}"
    return 0
}

expect_file ()
{
    local desc="$1" expected_file="$2" actual_file="$3"
    if ! diff -u "${expected_file}" "${actual_file}" > /dev/null
    then
        printf 'FAIL: %s - output does not match the frozen expectation:\n' "${desc}"
        diff -u "${expected_file}" "${actual_file}" || true
        exit 1
    fi
    return 0
}

expect_output ()
{
    local desc="$1" expected="$2" actual="$3"
    if [[ "${actual}" != "${expected}" ]]
    then
        printf 'FAIL: %s (expected [%s], got [%s])\n' "${desc}" "${expected}" "${actual}"
        exit 1
    fi
    return 0
}

echo "--- Reader case 1: absent selection file - no selection ---"
out="$(read_upgrade_selection "${sb_sh}/absent-os-upgrades.ini")"
expect_output "case 1 (absent file)" "" "${out}"
echo "PASS: case 1 - absent file reads as no selection (empty output)."

echo "--- Reader case 2: 26200_x64=on - exactly 26200_x64 ---"
printf '26200_x64=on\n' > "${sb_sh}/os-upgrades-case2.ini"
out="$(read_upgrade_selection "${sb_sh}/os-upgrades-case2.ini")"
expect_output "case 2 (single valid key)" "26200_x64" "${out}"
echo "PASS: case 2 - single valid key printed verbatim."

echo "--- Reader case 3: 19045_x64=on + 26200_x64=on - both keys in order ---"
printf '19045_x64=on\n26200_x64=on\n' > "${sb_sh}/os-upgrades-case3.ini"
out="$(read_upgrade_selection "${sb_sh}/os-upgrades-case3.ini")"
expect_output "case 3 (two valid keys, file order)" "19045_x64
26200_x64" "${out}"
echo "PASS: case 3 - both keys printed in file order."

echo "--- Reader case 4: one valid key + one bad line - all-or-nothing void ---"
printf '26200_x64=on\nbad_line\n' > "${sb_sh}/os-upgrades-case4.ini"
out="$(read_upgrade_selection "${sb_sh}/os-upgrades-case4.ini")"
expect_output "case 4 (valid key + bad line)" "" "${out}"
echo "PASS: case 4 - a grammar-violating line voids the ENTIRE selection."

echo "--- Reader case 5: CRLF fixture + blank tail line - case 2 result unchanged ---"
printf '26200_x64=on\r\n' > "${sb_sh}/os-upgrades-case5.ini"
printf '\r\n' >> "${sb_sh}/os-upgrades-case5.ini"
out="$(read_upgrade_selection "${sb_sh}/os-upgrades-case5.ini")"
expect_output "case 5 (CRLF fixture + blank tail)" "26200_x64" "${out}"
echo "PASS: case 5 - trailing CR stripped, CRLF selection reads valid."

echo "--- Feed case 6: selection 26200_x64 - exactly windows10.0-kb5064081 ---"
UPGB_TARGETS=( "26200" )
feed_evaluator "${sb_feed}/feed6.txt"
printf '%s\n' windows10.0-kb5064081 > "${sb_feed}/expected6.txt"
expect_file "case 6 (feed, single chosen target)" "${sb_feed}/expected6.txt" "${sb_feed}/feed6.txt"
echo "PASS: case 6 - single chosen target narrows the feed."

echo "--- Feed case 7: selection 26200_x64 + 19045_x64 - all chosen targets emitted ---"
UPGB_TARGETS=( "26200" "19045" )
feed_evaluator "${sb_feed}/feed7.txt"
printf '%s\n' windows10.0-kb5021233 windows10.0-kb5021233 \
              windows10.0-kb5021233 windows10.0-kb5064081 \
    > "${sb_feed}/expected7.txt"
expect_file "case 7 (feed, multi-EKB selection)" "${sb_feed}/expected7.txt" "${sb_feed}/feed7.txt"
echo "PASS: case 7 - multi-EKB selection emits every chosen target."

echo "--- Feed case 8: no selection - full statu-quo golden feed ---"
UPGB_TARGETS=()
feed_evaluator "${sb_feed}/feed8.txt"
build_golden_feed "${sb_feed}/expected8.txt"
expect_file "case 8 (feed, statu quo)" "${sb_feed}/expected8.txt" "${sb_feed}/feed8.txt"
echo "PASS: case 8 - feed byte-identical without selection."

echo ""
echo "======================================================================="
echo "SHIELD-FILTER-BASH-PASS: all 8 shield-filter cases green."
echo "======================================================================="
exit 0
