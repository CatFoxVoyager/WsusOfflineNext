#!/usr/bin/env bash
# =======================================================================
# WSUS Offline Update - Upgrade Contract Twin (Linux / Bash)
# File: sh/tests/verify-upgrade-contracts.bash
#
# Plan 31-04: cross-tier parity for the frozen upgrade path-deduction
# layer (PATH-01/PATH-02/PATH-03). Three sections:
#   A. Verdict evaluator parity: re-implements the frozen UpgResolvePath
#      rules (src-native/installer/upgradespredicates.pas) as a bash
#      evaluator and asserts every case of the canonical golden matrix
#      over the IDENTICAL GOLDEN_UPGRADES fixture the FPC testrunner
#      freezes (src-native/installer/tests/testrunner.lpr). Same rows,
#      same rule order R0-R12, same reason tokens, same expected
#      verdict/NeedsBaselineCU/reason triples.
#   B. Generated contracts: both generation twins' --check drift gates
#      plus the live generated data files' frozen shape (upgrades.txt,
#      builds.txt, StaticUpdateIds-BuildUpgrades.txt). Read-only.
#   C. Consent contracts: the frozen engine/GUI/host literals
#      (25/25 counts, /upgradeos token, template default, engine
#      refusal/acceptance literals, write-back absence, gitignore).
#   D. Bash shield-filter pipeline contracts (plan 32-02): the selection
#      reader library (read_upgrade_selection, CR strip, all-or-nothing
#      void), the hop walk's field-4 binding + library reference in
#      50-superseded-updates.bash, and the unchanged statu-quo printf
#      line - fail-closed pins on the bash mirror of the CMD
#      chosen-target slice (DEC-32-05/08/09).
#   E. Engine-literal pins (plan 32-04): the Phase-32 chosen-target
#      engine contract in client/cmd/DoUpdate.cmd fail-closed - the five
#      DEC-32-07 message literals (each on exactly its two echo/:Log
#      channels), the WOU_ROW_ALLOWED chosen-target guard in both row
#      loops, the consent-composition branch (DEC-32-03), the attempts
#      write-back format (DEC-32-06), the frozen 31-02 parse refusal at
#      exactly 4 physical lines, and the DEC-32-01 CSV-only absence pin
#      (zero selection-file references in the engine).
#
# Fixtures are self-created in a temp sandbox - no test reads the repo's
# gitignored runtime-state INI files (research Pitfall 7). Every failure
# prints a FAIL: line and exits 1; success prints UPGRADE-CONTRACTS-PASS.
# =======================================================================

set -e
set -u
export LC_ALL=C

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
cd "$repo_root"

echo "======================================================================="
echo "WSUS Offline Update - Upgrade Contract Twin (Linux / Bash)"
echo "======================================================================="

# Isolated sandbox for the section-A fixture (never the repo's runtime state)
tmp_dir="$(mktemp -d 2>/dev/null || mktemp -d -t 'wou_upgrade_contracts')"
trap 'rm -rf "$tmp_dir"' EXIT

# -----------------------------------------------------------------------
# The canonical GOLDEN_UPGRADES fixture - rows byte-identical to the
# GOLDEN_UPGRADES constant in src-native/installer/tests/testrunner.lpr
# (plan 31-03 shipped matrix; 8 valid rows + 1 malformed 11-field row,
# skipped by the exactly-12 gate).
# -----------------------------------------------------------------------
fixture_file="${tmp_dir}/upgrades-golden.txt"
cat > "$fixture_file" <<'GOLDEN_UPGRADES_EOF'
# comment line - ignored

26200|x64|glb|win11|26100|active|26100|kb5054156|5074|kb5064081|0|
26300|x64|glb|win11|26100|active|26100|kb5054156|||0|
28000|x64|glb|win11|28000|ineligible|||||0|new-devices-only
19045|x64|glb|win10|19041|active|19041|kb5015684|1865|kb5021233|0|
19045|x86|glb|win10|19041|active|19041|kb5015684|1865|kb5021233|0|
19044|x64|glb|win10|19041|eol|19041|kb5003791|1237|kb5008212|0|
20348|x64|glb|win10|20348|active|||||1|
25398|x64|glb|win10|25398|active|||||0|
this|row|is|malformed|nine|fields|x|x|x|x|x
GOLDEN_UPGRADES_EOF

# ===== Global variables =================================================
# Parsed fixture rows (parallel arrays; order preserved - the first
# matching row decides, exactly like the FPC table).
UP_TARGET=()   # field 1
UP_ARCH=()     # field 2
UP_LANG=()     # field 3
UP_FAMILY=()   # field 4
UP_STATUS=()   # field 6
UP_EKBSRC=()   # field 7
UP_EKBKB=()    # field 8
UP_MINREV=()   # field 9
UP_PREREQ=()   # field 10
UP_FUMEDIA=()  # field 11
UP_BLOCKED=()  # field 12
# Evaluator answer triple (set by upg_resolve)
UP_V="upgBlocked"
UP_B="false"
UP_R=""
# Per-section pass counter
SECTION_PASS=0

# Tolerant 12-field parser (parity with UpgParseUpgradesFile): comments,
# blank lines and rows whose field count is not exactly 12 are skipped;
# fields are whitespace-trimmed.
upg_parse() {
    local raw_line="" line="" field="" i
    local -i n_fields
    UP_TARGET=()
    UP_ARCH=()
    UP_LANG=()
    UP_FAMILY=()
    UP_STATUS=()
    UP_EKBSRC=()
    UP_EKBKB=()
    UP_MINREV=()
    UP_PREREQ=()
    UP_FUMEDIA=()
    UP_BLOCKED=()
    while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
        line="${raw_line%$'\r'}"
        line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        if [[ -z "$line" ]]; then
            continue
        fi
        case "$line" in
            '#'*)
                continue
                ;;
        esac
        # Split on '|' with a delimiter walk (parity with the FPC
        # Pos('|') loop): the walk continues while a pipe remains and
        # appends the WHOLE remainder - even when empty - as the final
        # field, so a trailing pipe yields an EMPTY 12th field (bash's
        # IFS-based `read -a` would silently drop it).
        local fields=()
        local rest="$line"
        while :; do
            if [[ "$rest" == *"|"* ]]; then
                fields+=("${rest%%|*}")
                rest="${rest#*|}"
            else
                fields+=("$rest")
                break
            fi
        done
        n_fields=${#fields[@]}
        if [[ "$n_fields" -ne 12 ]]; then
            continue
        fi
        for i in "${!fields[@]}"; do
            field="${fields[$i]}"
            field="$(printf '%s' "$field" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
            fields[$i]="$field"
        done
        UP_TARGET+=("${fields[0]}")
        UP_ARCH+=("${fields[1]}")
        UP_LANG+=("${fields[2]}")
        UP_FAMILY+=("${fields[3]}")
        UP_STATUS+=("${fields[5]}")
        UP_EKBSRC+=("${fields[6]}")
        UP_EKBKB+=("${fields[7]}")
        UP_MINREV+=("${fields[8]}")
        UP_PREREQ+=("${fields[9]}")
        UP_FUMEDIA+=("${fields[10]}")
        UP_BLOCKED+=("${fields[11]}")
    done < "$fixture_file"
}

# StrToIntDef equivalent for every reachable verdict input: a digits-only
# string converts base-10 (leading zeros stripped so arithmetic never
# goes octal), anything else - including empty - answers 0, mirroring the
# FPC default. The verdict rules only branch on <= 0 vs > 0 afterwards,
# so the positive-integer shape check carries the same outcome for the
# whole matrix (negative input answers 0 here and would read <= 0 in
# Pascal too).
upg_str_to_int() {
    local s="$1" t
    if [[ ! "$s" =~ ^[0-9]+$ ]]; then
        printf '0\n'
        return
    fi
    t="${s#"${s%%[!0]*}"}"
    if [[ -z "$t" ]]; then
        printf '0\n'
    else
        printf '%s\n' "$t"
    fi
}

# The frozen verdict rules R0-R12 (upgradespredicates.pas), evaluated in
# this exact order. Sets UP_V/UP_B/UP_R.
upg_resolve() {
    local curr_build="$1" curr_rev="$2" curr_arch="$3" curr_lang="$4"
    local curr_family="$5" target="$6"
    local curr_num target_num src_num rev_num min_rev_num
    local -i i t2 t ineligible
    UP_V="upgBlocked"
    UP_B="false"
    UP_R=""
    # R0 current build not a positive number
    curr_num="$(upg_str_to_int "$curr_build")"
    if [[ "$curr_num" -le 0 ]]; then
        UP_R="unknown-current"
        return
    fi
    # R1 target build not a positive number
    target_num="$(upg_str_to_int "$target")"
    if [[ "$target_num" -le 0 ]]; then
        UP_R="bad-target"
        return
    fi
    # R2 numeric target = numeric current
    if [[ "$target_num" -eq "$curr_num" ]]; then
        UP_R="already-on-target"
        return
    fi
    # R3 numeric target < numeric current
    if [[ "$target_num" -lt "$curr_num" ]]; then
        UP_R="downgrade"
        return
    fi
    # R4 current OS family is neither win10 nor win11 (legacy floor)
    if [[ "$curr_family" != "win10" ]] && [[ "$curr_family" != "win11" ]]; then
        UP_R="legacy-os"
        return
    fi
    # R5 + R6 over the target's rows: the first ineligible row decides
    # (R6 before the matrix gate); R5 answers no-media only when no row
    # carries the target at all.
    t2=-1
    ineligible=0
    for i in "${!UP_TARGET[@]}"; do
        if [[ "${UP_TARGET[$i]}" == "$target" ]]; then
            if [[ "$t2" -lt 0 ]]; then
                t2="$i"
            fi
            if [[ "${UP_STATUS[$i]}" == "ineligible" ]]; then
                if [[ -n "${UP_BLOCKED[$i]}" ]]; then
                    UP_R="${UP_BLOCKED[$i]}"
                else
                    UP_R="ineligible"
                fi
                ineligible=1
                break
            fi
        fi
    done
    if [[ "$ineligible" -eq 1 ]]; then
        return
    fi
    if [[ "$t2" -lt 0 ]]; then
        UP_R="no-media"
        return
    fi
    # R7 matrix gate on the first target row: x86 never sees a win11
    # target, arm64 never a win10 one.
    if [[ "$curr_arch" == "x86" && "${UP_FAMILY[$t2]}" == "win11" ]] || \
       [[ "$curr_arch" == "arm64" && "${UP_FAMILY[$t2]}" == "win10" ]]; then
        UP_R="arch-unsupported"
        return
    fi
    # T = the caller's (target, arch, lang) row
    t=-1
    for i in "${!UP_TARGET[@]}"; do
        if [[ "${UP_TARGET[$i]}" == "$target" && "${UP_ARCH[$i]}" == "$curr_arch" && "${UP_LANG[$i]}" == "$curr_lang" ]]; then
            t="$i"
            break
        fi
    done
    if [[ "$t" -ge 0 ]]; then
        # R8 EKB: exact ekb_source_build match OR the servicing-window
        # rule (source <= current < target) that keeps the 19041-branch
        # family answering EKB like the incumbent lane; an incomplete
        # EKB triple or a non-positive current revision answers
        # baseline-unknown - never a guessed baseline.
        src_num="$(upg_str_to_int "${UP_EKBSRC[$t]}")"
        if [[ "${UP_EKBSRC[$t]}" == "$curr_build" ]] || \
           [[ "$src_num" -gt 0 && "$src_num" -le "$curr_num" && "$curr_num" -lt "$target_num" ]]; then
            if [[ -n "${UP_EKBKB[$t]}" ]]; then
                if [[ -z "${UP_MINREV[$t]}" ]] || [[ -z "${UP_PREREQ[$t]}" ]]; then
                    UP_R="baseline-unknown"
                    return
                fi
                rev_num="$(upg_str_to_int "$curr_rev")"
                if [[ "$rev_num" -le 0 ]]; then
                    UP_R="baseline-unknown"
                    return
                fi
                min_rev_num="$(upg_str_to_int "${UP_MINREV[$t]}")"
                UP_V="upgEKB"
                if [[ "$rev_num" -lt "$min_rev_num" ]]; then
                    UP_B="true"
                else
                    UP_B="false"
                fi
                return
            fi
        fi
        # R9 full feature update: same family + staged media
        if [[ "${UP_FAMILY[$t]}" == "$curr_family" && "${UP_FUMEDIA[$t]}" == "1" ]]; then
            UP_V="upgFullFU"
            return
        fi
        # R11 the row exists but carries no FU media
        UP_R="no-media"
        return
    fi
    # R10 the arch is carried but not this language - never substitute
    for i in "${!UP_TARGET[@]}"; do
        if [[ "${UP_TARGET[$i]}" == "$target" && "${UP_ARCH[$i]}" == "$curr_arch" ]]; then
            UP_R="language-not-carried"
            return
        fi
    done
    # R12 no (target, arch) row at all
    UP_R="no-media"
}

# Shared assert: green increments the section counter, red prints the
# FAIL line and exits 1.
assert_eq() {
    local actual="$1" expected="$2" desc="$3"
    if [[ "$actual" != "$expected" ]]; then
        printf 'FAIL: %s (expected "%s", got "%s")\n' "$desc" "$expected" "$actual"
        exit 1
    fi
    SECTION_PASS=$((SECTION_PASS + 1))
}

has_literal() {
    local desc="$1" file="$2" literal="$3"
    if ! grep -qF -- "$literal" "$file"; then
        printf 'FAIL: %s (literal "%s" not found in %s)\n' "$desc" "$literal" "$file"
        exit 1
    fi
    SECTION_PASS=$((SECTION_PASS + 1))
}

has_min_count() {
    local desc="$1" file="$2" min="$3" literal="$4"
    local n
    n="$(grep -cF -- "$literal" "$file" || true)"
    if [[ "$n" -lt "$min" ]]; then
        printf 'FAIL: %s (expected >= %s hits for "%s", got %s)\n' "$desc" "$min" "$literal" "$n"
        exit 1
    fi
    SECTION_PASS=$((SECTION_PASS + 1))
}

# Exact-count assert: a literal must appear EXACTLY n times in the file
# (used for the engine pins, where the count itself is the contract -
# e.g. a refusal literal on exactly its two echo/:Log channels). The
# count is captured with a tolerant fallback so a genuine zero is a
# measured 0, never a suppressed grep exit code.
assert_count() {
    local desc="$1" file="$2" expected="$3" literal="$4"
    local n
    n="$(grep -cF -- "$literal" "$file" || true)"
    if [[ "$n" != "$expected" ]]; then
        printf 'FAIL: %s (expected exactly %s hits for "%s", got %s)\n' "$desc" "$expected" "$literal" "$n"
        exit 1
    fi
    SECTION_PASS=$((SECTION_PASS + 1))
}

# -----------------------------------------------------------------------
# Section A: verdict evaluator parity over the canonical golden matrix
# -----------------------------------------------------------------------
echo "--- Section A: verdict evaluator parity (golden matrix) ---"
SECTION_PASS=0

upg_parse

assert_eq "${#UP_TARGET[@]}" "8" "upg-parse-1: 9 candidate fixture lines yield 8 rows (comment, blank, malformed skipped)"

malformed_in=0
for i in "${!UP_TARGET[@]}"; do
    if [[ "${UP_TARGET[$i]}" == "this" ]]; then
        malformed_in=1
    fi
done
assert_eq "$malformed_in" "0" "upg-parse-2: the 11-field malformed row is not in the parsed table"

assert_eq "${UP_TARGET[0]}" "26200" "upg-parse-3: comment and blank lines skipped (first parsed row is 26200)"

# Golden matrix: verdict/NeedsBaselineCU/reason triples, same order and
# tokens as testrunner.lpr TestUpgradesVerdict (cases 01-20).
check_case() {
    local num="$1" curr="$2" rev="$3" arch="$4" lang="$5" fam="$6" target="$7"
    local exp_v="$8" exp_b="$9" exp_r="${10}"
    upg_resolve "$curr" "$rev" "$arch" "$lang" "$fam" "$target"
    if [[ "$UP_V" == "$exp_v" && "$UP_B" == "$exp_b" && "$UP_R" == "$exp_r" ]]; then
        SECTION_PASS=$((SECTION_PASS + 1))
    else
        printf 'FAIL: case %s expected %s/%s/%s got %s/%s/%s\n' \
            "$num" "$exp_v" "$exp_b" "$exp_r" "$UP_V" "$UP_B" "$UP_R"
        exit 1
    fi
}

check_case 01 '26100' '1000' 'x64' 'glb' 'win11' '26200' upgEKB true ''
check_case 02 '26100' '5074' 'x64' 'glb' 'win11' '26200' upgEKB false ''
check_case 03 '26100' '6000' 'x64' 'glb' 'win11' '26200' upgEKB false ''
check_case 04 '26100' '5074' 'x64' 'glb' 'win11' '26300' upgBlocked false baseline-unknown
check_case 05 '26100' '' 'x64' 'glb' 'win11' '26200' upgBlocked false baseline-unknown
check_case 06 '26100' '5074' 'x64' 'glb' 'win11' '26100' upgBlocked false already-on-target
check_case 07 '26200' '5074' 'x64' 'glb' 'win11' '26100' upgBlocked false downgrade
check_case 08 '26100' '5074' 'x64' 'glb' 'win11' 'abc' upgBlocked false bad-target
check_case 09 '' '5074' 'x64' 'glb' 'win11' '26200' upgBlocked false unknown-current
check_case 10 '26100' '5074' 'x64' 'glb' 'win11' '28000' upgBlocked false new-devices-only
check_case 11 '19045' '1865' 'x86' 'glb' 'win10' '26200' upgBlocked false arch-unsupported
check_case 12 '19045' '1865' 'arm64' 'glb' 'win11' '20348' upgBlocked false arch-unsupported
check_case 13 '26100' '5074' 'arm64' 'glb' 'win11' '26200' upgBlocked false no-media
check_case 14 '7601' '1' 'x86' 'glb' 'win7' '19045' upgBlocked false legacy-os
check_case 15 '19042' '1237' 'x64' 'glb' 'win10' '19044' upgEKB false ''
check_case 16 '19045' '1865' 'x64' 'glb' 'win10' '20348' upgFullFU false ''
check_case 17 '19045' '1865' 'x64' 'glb' 'win10' '25398' upgBlocked false no-media
check_case 18 '26100' '5074' 'x64' 'deu' 'win11' '26200' upgBlocked false language-not-carried
check_case 19 '19045' '1865' 'x86' 'glb' 'win10' '28000' upgBlocked false new-devices-only
check_case 20 '19044' '1000' 'x64' 'glb' 'win10' '19045' upgEKB true ''

A_PASS=$SECTION_PASS
printf '[A] verdict evaluator parity: %s checks green (3 parser facts + 20 matrix cases)\n' "$A_PASS"

# -----------------------------------------------------------------------
# Section B: generated contracts (read-only over the live tree)
# -----------------------------------------------------------------------
echo "--- Section B: generated contracts (--check twins + data census) ---"
SECTION_PASS=0

# -----------------------------------------------------------------------
# Phase-37 family census (plan 37-02, VAL-02b): zero pre-Win10 upgrade
# rows at the data layer. Field-4 awk walk over the live roster plus the
# generator source of truth (LC_ALL=C is exported at the twin top) -
# counts captured into variables and compared numerically. The upgrade
# entries the GUIs surface come ONLY from this roster, so a w61/wxp
# family can never reach the picker; the FPC resolver's R4 refusal is
# exercised by the TAP negative (upg-case-21-wxp-family-r4) instead.
# -----------------------------------------------------------------------
upg_file="${repo_root}/client/UpdateTable/upgrades.txt"
if [[ ! -f "$upg_file" ]]; then
    printf 'FAIL: missing generated file client/UpdateTable/upgrades.txt\n'
    exit 1
fi
census_out="$(awk -F'|' '
    $0 !~ /^[[:space:]]*#/ && $0 !~ /^[[:space:]]*$/ && NF==12 {
        total++
        fam=$4; sub(/\r$/, "", fam)
        if (fam=="win10") w10++
        else if (fam=="win11") w11++
        else { other++; if (other_first=="") other_first=fam }
    }
    END { printf "%d %d %d %d %s\n", total+0, w10+0, w11+0, other+0, other_first }
' "$upg_file")"
read -r census_total census_win10 census_win11 census_other census_other_first <<< "$census_out"
if [[ "$census_total" -lt 1 ]]; then
    printf 'FAIL: the roster family census read 0 data rows - vacuous census (population proof failed)\n'
    exit 1
fi
if [[ "$census_other" -ne 0 ]]; then
    printf 'FAIL: upgrades.txt carries %s pre-Win10 os_family row(s) (first: %s; expected zero)\n' \
        "$census_other" "$census_other_first"
    exit 1
fi
assert_eq "$((census_win10 + census_win11))" "$census_total" \
    "upgrades.txt family census: win10+win11 = all ${census_total} data rows"
SECTION_PASS=$((SECTION_PASS + 1))
echo "[B] upgrades.txt: zero pre-Win10 os_family rows (census ${census_total}/${census_total} win10+win11, 0 other)"

builds_ini_file="${repo_root}/static/builds.ini"
if [[ ! -f "$builds_ini_file" ]]; then
    printf 'FAIL: missing builds registry static/builds.ini\n'
    exit 1
fi
b_census_out="$(awk -F= '
    /^os_family=/ {
        total++
        fam=$2; sub(/\r$/, "", fam)
        if (fam=="win10") w10++
        else if (fam=="win11") w11++
        else { other++; if (other_first=="") other_first=fam }
    }
    END { printf "%d %d %d %d %s\n", total+0, w10+0, w11+0, other+0, other_first }
' "$builds_ini_file")"
read -r b_total b_win10 b_win11 b_other b_other_first <<< "$b_census_out"
if [[ "$b_total" -lt 1 ]]; then
    printf 'FAIL: the builds.ini family census read 0 os_family values - vacuous census (population proof failed)\n'
    exit 1
fi
assert_eq "$((b_win10 + b_win11))" "$b_total" \
    "builds.ini family census: win10+win11 = all ${b_total} declared families"
if [[ "$b_other" -ne 0 ]]; then
    printf 'FAIL: builds.ini carries %s pre-Win10 os_family value(s) (first: %s; expected zero)\n' \
        "$b_other" "$b_other_first"
    exit 1
fi
SECTION_PASS=$((SECTION_PASS + 1))
echo "[B] builds.ini: zero pre-Win10 os_family values (census ${b_total} win10+win11, 0 other)"

if ! bash_twin_out="$(bash sh/generate-build-sites.bash --check 2>&1)"; then
    printf 'FAIL: bash generation twin --check reported drift\n%s\n' "$bash_twin_out"
    exit 1
fi
SECTION_PASS=$((SECTION_PASS + 1))
echo "[B] bash generation twin --check exit 0 (all sites in sync)"

if command -v cscript > /dev/null 2>&1; then
    if ! vbs_twin_out="$(cscript //Nologo cmd/GenerateBuildSites.vbs --check 2>&1)"; then
        printf 'FAIL: VBS generation twin --check reported drift\n%s\n' "$vbs_twin_out"
        exit 1
    fi
    SECTION_PASS=$((SECTION_PASS + 1))
    echo "[B] VBS generation twin --check exit 0 (all sites in sync)"
else
    echo "SKIP-VBS: cscript unavailable - the VBS twin --check was not run"
fi

upg_file="${repo_root}/client/UpdateTable/upgrades.txt"
builds_file="${repo_root}/client/UpdateTable/builds.txt"
hop_file="${repo_root}/client/static/StaticUpdateIds-BuildUpgrades.txt"

if [[ ! -f "$upg_file" ]]; then
    printf 'FAIL: missing generated file client/UpdateTable/upgrades.txt\n'
    exit 1
fi
SECTION_PASS=$((SECTION_PASS + 1))

upg_lines="$(wc -l < "$upg_file" | tr -d '[:space:]')"
assert_eq "$upg_lines" "15" "upgrades.txt carries exactly 15 lines (3-line frozen header + 12 rows)"

upg_rows="$(awk -F'|' '$0 !~ /^[[:space:]]*#/ && $0 !~ /^[[:space:]]*$/ && NF==12 {c++} END{printf "%d", c+0}' "$upg_file")"
assert_eq "$upg_rows" "12" "upgrades.txt carries exactly 12 twelve-field data rows"

has_literal "upgrades.txt freezes the 12-field # Format: header" "$upg_file" \
    '# Format: target_build|arch|lang|os_family|servicing_branch|status|ekb_source_build|ekb_kb|ekb_min_revision|ekb_prereq_kb|fu_media|blocked_reason'

has_literal "upgrades.txt consumer line names no false runtime reader (WR-01 pin)" "$upg_file" \
    '# Decision data for the OS-upgrade path layer (upgradespredicates.pas); consumers wire in with Phases 32+ - no runtime reader yet'

upg_28000="$(awk -F'|' '{sub(/\r$/, "")} $1=="28000" && $12=="new-devices-only" {c++} END{printf "%d", c+0}' "$upg_file")"
assert_eq "$upg_28000" "1" "upgrades.txt 28000 row carries the new-devices-only blocked reason"

upg_26300="$(awk -F'|' '{sub(/\r$/, "")} $1=="26300" && $9=="" && $10=="" {c++} END{printf "%d", c+0}' "$upg_file")"
assert_eq "$upg_26300" "1" "upgrades.txt 26300 row carries empty ekb_min_revision/ekb_prereq_kb (baseline-unknown shape)"

if [[ ! -f "$builds_file" ]]; then
    printf 'FAIL: missing generated file client/UpdateTable/builds.txt\n'
    exit 1
fi
has_literal "builds.txt freezes the 10-field # Format: header (contract never extended)" "$builds_file" \
    '# Format: build|arch|os_family|servicing_branch|status|ekb_source_build|ekb_kb|ekb_prereq_kb|ekb_min_revision|is_enforced'

builds_rows="$(grep -c '^[0-9]' "$builds_file" || true)"
assert_eq "$builds_rows" "12" "builds.txt carries exactly 12 data rows (frozen census)"

if [[ ! -f "$hop_file" ]]; then
    printf 'FAIL: missing generated file client/static/StaticUpdateIds-BuildUpgrades.txt\n'
    exit 1
fi
hop_rows="$(grep -c '^[0-9]' "$hop_file" || true)"
assert_eq "$hop_rows" "6" "StaticUpdateIds-BuildUpgrades.txt carries exactly 6 hop rows"

B_PASS=$SECTION_PASS
printf '[B] generated contracts: %s checks green\n' "$B_PASS"

# -----------------------------------------------------------------------
# Section C: consent contracts (frozen source literals)
# -----------------------------------------------------------------------
echo "--- Section C: consent contracts (frozen source literals) ---"
SECTION_PASS=0

contracts_file="${repo_root}/src-native/installer/enginecontracts.pas"
ini_file="${repo_root}/client/UpdateInstaller.ini"
engine_file="${repo_root}/client/cmd/DoUpdate.cmd"
mainform_file="${repo_root}/src-native/installer/mainform.pas"
host_file="${repo_root}/src-modern/generator/host/Program.cs"
gitignore_file="${repo_root}/.gitignore"

has_literal "enginecontracts freezes ENG_SWITCH_COUNT = 25" "$contracts_file" 'ENG_SWITCH_COUNT = 25'
has_literal "enginecontracts freezes ENG_INI_DEFAULT_COUNT = 25" "$contracts_file" 'ENG_INI_DEFAULT_COUNT = 25'
has_literal "enginecontracts carries the /upgradeos argv token" "$contracts_file" "'/upgradeos'"
has_literal "UpdateInstaller.ini template defaults upgradeos=Disabled" "$ini_file" 'upgradeos=Disabled'
has_literal "DoUpdate.cmd carries the loud refusal literal" "$engine_file" \
    'ERROR: /upgradeos target must be a build number'
has_literal "DoUpdate.cmd carries the acceptance literal" "$engine_file" 'Info: Upgrade target build'

if grep 'WriteString' "$mainform_file" | grep -qi 'upgradeos'; then
    printf 'FAIL: mainform.pas must not write the upgradeos key back (no WriteString line may carry it)\n'
    exit 1
fi
SECTION_PASS=$((SECTION_PASS + 1))
echo "[C] mainform.pas write-back absence: no WriteString line carries the upgradeos key"

has_min_count "Program.cs carries the [OS Upgrades] section contract (>= 2 sites)" "$host_file" 2 '[OS Upgrades]'
has_literal "Program.cs carries the flat bash twin file name" "$host_file" 'os-upgrades.ini'
has_literal "Program.cs carries the section reader" "$host_file" 'ReadOsUpgradesSelection'
has_literal ".gitignore excludes the bash twin runtime file" "$gitignore_file" 'sh/os-upgrades.ini'

C_PASS=$SECTION_PASS
printf '[C] consent contracts: %s checks green\n' "$C_PASS"

# -----------------------------------------------------------------------
# Section D: bash shield-filter pipeline contracts (plan 32-02)
# -----------------------------------------------------------------------
echo "--- Section D: bash shield-filter pipeline contracts (plan 32-02) ---"
SECTION_PASS=0

library_file="${repo_root}/sh/libraries/upgrade-selection.bash"
task_file="${repo_root}/sh/download-updates-tasks/50-superseded-updates.bash"

if [[ ! -f "$library_file" ]]; then
    printf 'FAIL: missing library file sh/libraries/upgrade-selection.bash\n'
    exit 1
fi
SECTION_PASS=$((SECTION_PASS + 1))

has_literal "library defines the read_upgrade_selection reader (DEC-32-09)" \
    "$library_file" 'read_upgrade_selection'
has_literal "library strips the trailing CR from the state token (DEC-32-08)" \
    "$library_file" 'state=${state%$'\''\r'\''}'
has_literal "library carries the all-or-nothing void marker (T-32-03)" \
    "$library_file" 'all-or-nothing'

has_literal "hop walk binds field 4 - the new build of the hop (DEC-32-05)" \
    "$task_file" 'field_4'
has_literal "task reads the selection through the library reader" \
    "$task_file" 'read_upgrade_selection'
has_literal "task resolves the flat twin os-upgrades.ini as a bare sibling name" \
    "$task_file" 'os-upgrades.ini'
has_literal "statu-quo printf line unchanged in the hop walk" \
    "$task_file" 'printf '\''%s\n'\'' "windows10.0-${kb_number}"'

D_PASS=$SECTION_PASS
printf '[D] bash shield-filter pipeline contracts: %s checks green\n' "$D_PASS"

# -----------------------------------------------------------------------
# Section E: engine-literal pins (plan 32-04) - the Phase-32 chosen-target
# engine contract in client/cmd/DoUpdate.cmd, fail-closed
# -----------------------------------------------------------------------
echo "--- Section E: engine-literal pins (client/cmd/DoUpdate.cmd) ---"
SECTION_PASS=0

engine_file="${repo_root}/client/cmd/DoUpdate.cmd"

if [[ ! -f "$engine_file" ]]; then
    printf 'FAIL: missing engine file client/cmd/DoUpdate.cmd\n'
    exit 1
fi
SECTION_PASS=$((SECTION_PASS + 1))

# DEC-32-07 frozen literals: each message text must sit on EXACTLY its
# two emission channels (echo + :Log call), byte-verbatim.
assert_count "refusal literal: missing enablement package (echo + :Log)" \
    "$engine_file" 2 'blocked: enablement package'
assert_count "refusal literal: baseline revision below minimum (echo + :Log)" \
    "$engine_file" 2 'blocked: baseline revision'
assert_count "refusal literal: no upgrade path from build (echo + :Log)" \
    "$engine_file" 2 'has no upgrade path from build'
assert_count "convergence Info literal: jump observed complete (echo + :Log, both lanes)" \
    "$engine_file" 4 'observed - jump complete'
assert_count "full-FU convergence literal: already observed (echo + :Log)" \
    "$engine_file" 2 'already observed - jump complete'
assert_count "perform-stall Warning literal: build did not advance (echo + :Log, both lanes)" \
    "$engine_file" 4 'did not advance the OS build'
assert_count "full-FU stall literal: full upgrade did not advance (echo + :Log)" \
    "$engine_file" 2 'Full upgrade did not advance'

# Chosen-target guard: the additive wrapper lives in BOTH :BuildUpgrade
# row loops (DEC-32-03). The variable must be present throughout (reset,
# guard body, wrapper close in both loops - floor 4) and the
# target-mismatch clear line must exist exactly twice (once per loop).
has_min_count "guard variable WOU_ROW_ALLOWED present (both row loops)" \
    "$engine_file" 4 'WOU_ROW_ALLOWED'
assert_count "guard line: target mismatch clears WOU_ROW_ALLOWED (both row loops)" \
    "$engine_file" 2 'if defined WOU_UPGRADE_TARGET if not "%%d"=="!WOU_UPGRADE_TARGET!" set "WOU_ROW_ALLOWED="'

# Consent composition (DEC-32-03): a defined /upgradeos target routes the
# hop through the optional lane - exactly one such branch.
assert_count "consent composition: defined target routes to the optional lane" \
    "$engine_file" 1 'if defined WOU_UPGRADE_TARGET goto CheckBuildUpgradeOptional'

# Attempts contract (DEC-32-06): the count,revision,build,leg write-back
# - one prepare-leg record and one perform-leg record, sharing the
# count,revision,build prefix shape.
assert_count "perform-leg write-back (count,revision,build,perform record)" \
    "$engine_file" 1 ',%OS_VER_REVIS%,%OS_VER_BUILD%,perform>'
assert_count "prepare-leg write-back (count,revision,build,prepare record)" \
    "$engine_file" 1 ',%OS_VER_REVIS%,%OS_VER_BUILD%,prepare>'
assert_count "attempts format write prefix (count,revision,build,) on all three write-backs" \
    "$engine_file" 3 ',%OS_VER_REVIS%,%OS_VER_BUILD%,'
assert_count "full-FU leg write-back (count,revision,build,full record)" \
    "$engine_file" 1 ',%OS_VER_REVIS%,%OS_VER_BUILD%,full>'

# Frozen 31-02 parse contract: the loud parse refusal at exactly 4
# physical lines (echo + :Log at the parse site AND the bare-token site).
assert_count "frozen 31-02 parse refusal: exactly 4 lines (2 sites x 2 channels)" \
    "$engine_file" 4 'ERROR: /upgradeos target must be a build number'

# DEC-32-01: the engine stays CSV-only - zero selection-file references.
assert_count "engine carries zero selection-file references (DEC-32-01 CSV-only)" \
    "$engine_file" 0 'os-upgrades'

E_PASS=$SECTION_PASS
printf '[E] engine-literal pins: %s checks green\n' "$E_PASS"

# -----------------------------------------------------------------------
# All green
# -----------------------------------------------------------------------
echo ""
echo "======================================================================="
echo "Upgrade contract twin: A=${A_PASS} B=${B_PASS} C=${C_PASS} D=${D_PASS} E=${E_PASS} checks green."
echo "======================================================================="
echo "UPGRADE-CONTRACTS-PASS"
exit 0
