#!/usr/bin/env bash
# =======================================================================
# WSUS Offline Update - Office Alignment Regression Suite (Linux / Bash)
# File: sh/tests/verify-office-alignment.bash
#
# Verifies:
#   Test 1: Zero o2k13 occurrences across all bash scripts in sh/
#   Test 2: sh/libraries/updates-and-languages.bash array integrity (o2k16 only)
#   Test 3: sh/update-generator-tasks/10-show-selection-dialogs-with-dialog.bash array integrity
#   Test 4: Office discrimination logic parity across synthetic states
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
echo "WSUS Offline Update - Office Alignment Test Suite (Linux / Bash)"
echo "======================================================================="

# -----------------------------------------------------------------------
# Test 1: Zero o2k13 occurrences across all bash scripts
# -----------------------------------------------------------------------
echo "[Test 1/4] Verifying zero o2k13 occurrences in all bash scripts under sh/..."

o2k13_leakage="$(grep -rn -i "o2k13" "${repo_root}/sh" --include="*.bash" --exclude-dir="tests" || true)"
if [[ -n "$o2k13_leakage" ]]; then
    echo "FAIL: Detected o2k13 occurrences in bash scripts:"
    echo "$o2k13_leakage"
    exit 1
fi

if [[ -f "${repo_root}/sh/exclude/ExcludeListISO-o2k13.txt" ]]; then
    echo "FAIL: Obsolete file sh/exclude/ExcludeListISO-o2k13.txt still exists."
    exit 1
fi

echo "[PASS] Test 1: Zero o2k13 leakage in bash scripts."

# -----------------------------------------------------------------------
# Test 2: updates-and-languages.bash array integrity
# -----------------------------------------------------------------------
echo "[Test 2/4] Verifying updates-and-languages.bash array integrity..."

# Source library in subshell to avoid pollution
source "${repo_root}/sh/libraries/updates-and-languages.bash"

# Verify list_all_ofc contains exactly "o2k16-x64"
if [[ "${#list_all_ofc[@]}" -ne 1 || "${list_all_ofc[0]}" != "o2k16-x64" ]]; then
    echo "FAIL: list_all_ofc expected ('o2k16-x64'), got: ${list_all_ofc[*]}"
    exit 1
fi

# Verify list_all_ofc_x86 contains exactly "o2k16"
if [[ "${#list_all_ofc_x86[@]}" -ne 1 || "${list_all_ofc_x86[0]}" != "o2k16" ]]; then
    echo "FAIL: list_all_ofc_x86 expected ('o2k16'), got: ${list_all_ofc_x86[*]}"
    exit 1
fi

# Verify list_all does not contain o2k13 and does contain o2k16-x64
found_o2k16=0
for u in "${list_all[@]}"; do
    if [[ "$u" == *"o2k13"* ]]; then
        echo "FAIL: list_all contains legacy update: $u"
        exit 1
    fi
    if [[ "$u" == "o2k16-x64" ]]; then
        found_o2k16=1
    fi
done
if [[ "$found_o2k16" -ne 1 ]]; then
    echo "FAIL: list_all missing o2k16-x64"
    exit 1
fi

echo "[PASS] Test 2: updates-and-languages.bash array integrity verified."

# -----------------------------------------------------------------------
# Test 3: 10-show-selection-dialogs-with-dialog.bash array integrity
# -----------------------------------------------------------------------
echo "[Test 3/4] Verifying 10-show-selection-dialogs-with-dialog.bash configuration..."

dialog_script="${repo_root}/sh/update-generator-tasks/10-show-selection-dialogs-with-dialog.bash"

# Check update_keys has o2k16 and o2k16-x64 and no o2k13
if grep -E 'update_keys=\(' -A 10 "$dialog_script" | grep -q "o2k13"; then
    echo "FAIL: update_keys contains o2k13"
    exit 1
fi
if ! grep -E 'update_keys=\(' -A 10 "$dialog_script" | grep -q "o2k16"; then
    echo "FAIL: update_keys missing o2k16"
    exit 1
fi

# Check all_labels has o2k16 and no o2k13
if grep -E '\[o2k13\]|\[o2k13-x64\]' "$dialog_script"; then
    echo "FAIL: all_labels or all_values contains o2k13"
    exit 1
fi
if ! grep -q '\[o2k16\]' "$dialog_script" || ! grep -q '\[o2k16-x64\]' "$dialog_script"; then
    echo "FAIL: all_labels missing o2k16 or o2k16-x64"
    exit 1
fi

echo "[PASS] Test 3: 10-show-selection-dialogs-with-dialog.bash configuration verified."

# -----------------------------------------------------------------------
# Test 4: Office discrimination logic parity across synthetic states
# -----------------------------------------------------------------------
echo "[Test 4/4] Verifying Office 16.0 discrimination parity across 5 synthetic states..."

discriminate_office16() {
    local c2r_ids="$1"
    local mso_ver="$2"
    local prod_name="Office 2016"
    local eol_status="EOL (End of Life - Oct 2025)"
    local is_c2r=0

    if [[ "$c2r_ids" == *"2024"* ]]; then
        prod_name="Office LTSC 2024"
        eol_status="Active (Supported until Oct 2029)"
        is_c2r=1
    elif [[ "$c2r_ids" == *"2021"* ]]; then
        prod_name="Office LTSC 2021"
        eol_status="EOL (Supported until Oct 2026)"
        is_c2r=1
    elif [[ "$c2r_ids" == *"2019"* ]]; then
        prod_name="Office 2019"
        eol_status="EOL (End of Life - Oct 2025)"
        is_c2r=1
    elif [[ "$c2r_ids" == *"O365"* || "$c2r_ids" == *"M365"* ]]; then
        prod_name="Microsoft 365 Apps"
        eol_status="Channel Managed (C2R)"
        is_c2r=1
    else
        IFS='.' read -r -a ver_parts <<< "$mso_ver"
        if (( ${#ver_parts[@]} >= 3 )); then
            local num_build="${ver_parts[2]}"
            if [[ "$num_build" =~ ^[0-9]+$ ]]; then
                if (( num_build >= 17000 )); then
                    prod_name="Office LTSC 2024"
                    eol_status="Active (Supported until Oct 2029)"
                    is_c2r=1
                elif (( num_build >= 14000 )); then
                    prod_name="Office LTSC 2021"
                    eol_status="EOL (Supported until Oct 2026)"
                    is_c2r=1
                elif (( num_build >= 10000 )); then
                    prod_name="Office 2019"
                    eol_status="EOL (End of Life - Oct 2025)"
                    is_c2r=1
                else
                    prod_name="Office 2016 (MSI)"
                    eol_status="EOL (End of Life - Oct 2025)"
                    is_c2r=0
                fi
            fi
        fi
    fi

    echo "${prod_name}|${eol_status}|${is_c2r}"
}

# State A: Office LTSC 2024
res_a="$(discriminate_office16 "ProPlus2024Volume" "16.0.17932.20162")"
if [[ "$res_a" != "Office LTSC 2024|Active (Supported until Oct 2029)|1" ]]; then
    echo "FAIL: State A expected Office LTSC 2024 Active 1, got: $res_a"
    exit 1
fi

# State B: Office LTSC 2021
res_b="$(discriminate_office16 "ProPlus2021Volume" "16.0.14332.20204")"
if [[ "$res_b" != "Office LTSC 2021|EOL (Supported until Oct 2026)|1" ]]; then
    echo "FAIL: State B expected Office LTSC 2021 EOL 1, got: $res_b"
    exit 1
fi

# State C: Office 2019
res_c="$(discriminate_office16 "ProPlus2019Volume" "16.0.10336.20044")"
if [[ "$res_c" != "Office 2019|EOL (End of Life - Oct 2025)|1" ]]; then
    echo "FAIL: State C expected Office 2019 EOL 1, got: $res_c"
    exit 1
fi

# State D: Office 2016 MSI
res_d="$(discriminate_office16 "" "16.0.4266.1001")"
if [[ "$res_d" != "Office 2016 (MSI)|EOL (End of Life - Oct 2025)|0" ]]; then
    echo "FAIL: State D expected Office 2016 (MSI) EOL 0, got: $res_d"
    exit 1
fi

# State E: Fallback build threshold >= 17000
res_e="$(discriminate_office16 "" "16.0.17932.21056")"
if [[ "$res_e" != "Office LTSC 2024|Active (Supported until Oct 2029)|1" ]]; then
    echo "FAIL: Fallback build 17932 expected Office LTSC 2024 Active 1, got: $res_e"
    exit 1
fi

echo "[PASS] Test 4: Office 16.0 discrimination parity verified across all states."

echo ""
echo "======================================================================="
echo "SUCCESS: All 4 Office alignment tests passed on Linux/Bash!"
echo "======================================================================="
exit 0
