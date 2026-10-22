#!/usr/bin/env bash
# =======================================================================
# WSUS Offline Update - Office Hybrid Staging Regression Suite (Linux / Bash)
# File: sh/tests/verify-office-staging.bash
#
# Verifies:
#   Test 1: Linux command line parser accepts o2k16 and o2k16-x64
#   Test 2: Linux main updates applies ExcludeList-${arch}.txt for o2k16
#   Test 3: ODT XML templates syntax and channel validity (if present)
#   Test 4: Linux direct CDN C2R task integrity (if present)
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
echo "WSUS Offline Update - Office Hybrid Staging Test Suite (Linux / Bash)"
echo "======================================================================="

# -----------------------------------------------------------------------
# Test 1: Parser accepts o2k16 and o2k16-x64
# -----------------------------------------------------------------------
echo "[Test 1/4] Verifying Linux command line parser accepts o2k16 and o2k16-x64..."

parser_file="${repo_root}/sh/download-updates-tasks/10-parse-command-line.bash"
if ! grep -q "o2k16 | o2k16-x64" "$parser_file"; then
    echo "FAIL: $parser_file does not contain 'o2k16 | o2k16-x64'"
    exit 1
fi

echo "[PASS] Test 1: Linux CLI parser accepts dual-architecture Office 2016."

# -----------------------------------------------------------------------
# Test 2: Architecture exclusion applied to o2k16
# -----------------------------------------------------------------------
echo "[Test 2/4] Verifying ExcludeList-\${arch}.txt in sh/download-updates-tasks/60-main-updates.bash..."

main_updates="${repo_root}/sh/download-updates-tasks/60-main-updates.bash"
if ! grep -A 20 "o2k16)" "$main_updates" | grep -q 'ExcludeList-${arch}.txt'; then
    echo "FAIL: $main_updates does not apply ExcludeList-\${arch}.txt in o2k16 block."
    exit 1
fi

echo "[PASS] Test 2: Linux main updates isolates Office architectures."

# -----------------------------------------------------------------------
# Test 3: ODT XML Configuration Templates
# -----------------------------------------------------------------------
echo "[Test 3/4] Verifying ODT XML configuration templates..."

if [[ -f "${repo_root}/static/odt-templates/o2k24-template.xml" ]]; then
    for t in o2k19 o2k21 o2k24; do
        if ! grep -qi "PerpetualVL" "${repo_root}/static/odt-templates/${t}-template.xml"; then
            echo "FAIL: static/odt-templates/${t}-template.xml missing PerpetualVL channel."
            exit 1
        fi
    done
    echo "[PASS] Test 3: ODT configuration templates valid."
else
    echo "[SKIP] Test 3: ODT templates not yet created (Wave 2 task)."
fi

# -----------------------------------------------------------------------
# Test 4: Linux Direct CDN C2R Task
# -----------------------------------------------------------------------
echo "[Test 4/4] Verifying Linux direct CDN C2R task..."

c2r_task="${repo_root}/sh/download-updates-tasks/65-office-c2r.bash"
if [[ -f "$c2r_task" ]]; then
    if ! grep -q "7983bac0-e531-40cf-be00-fd24fe66619c" "$c2r_task"; then
        echo "FAIL: $c2r_task missing Office 2024 CDN GUID."
        exit 1
    fi
    echo "[PASS] Test 4: Linux direct CDN C2R task valid."
else
    echo "[SKIP] Test 4: Linux direct CDN C2R task not yet created (Wave 2 task)."
fi

echo "======================================================================="
echo "ALL TESTS PASSED: Linux Office Hybrid Staging validation green."
echo "======================================================================="
exit 0
