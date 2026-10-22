#!/usr/bin/env bash
# =======================================================================
# WSUS Offline Update - Windows 11 26H1 (Build 28000) Regression Suite (Linux / Bash)
# File: sh/tests/verify-win11-26h1.bash
#
# Verifies:
#   Test 1: builds.ini & AutoIt Registry Table Contracts
#   Test 2: Dedicated Static Manifests & Zero Checkpoint (KB5043080) Leakage
#   Test 3: Client Environment Variables & .NET 4.8.1 Target Resolution
#   Test 4: Feature Upgrade Ineligibility & Update Queue Isolation
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
echo "WSUS Offline Update - Windows 11 26H1 Test Suite (Linux / Bash)"
echo "======================================================================="

tmp_dir="$(mktemp -d 2>/dev/null || mktemp -d -t 'wou_26h1_test')"
trap 'rm -rf "$tmp_dir"' EXIT

# -----------------------------------------------------------------------
# Test 1: builds.ini & Registry Table Contracts
# -----------------------------------------------------------------------
echo "[Test 1/4] Verifying builds.ini and AutoIt Registry Table Contracts..."

builds_ini="${repo_root}/static/builds.ini"
if ! grep -q "\[w100-x64-28000\]" "$builds_ini"; then
    echo "FAIL: static/builds.ini missing [w100-x64-28000] section."
    exit 1
fi
if ! grep -A 10 "\[w100-x64-28000\]" "$builds_ini" | grep -q "servicing_branch=28000"; then
    echo "FAIL: static/builds.ini [w100-x64-28000] missing servicing_branch=28000."
    exit 1
fi
if ! grep -A 10 "\[w100-x64-28000\]" "$builds_ini" | grep -q "status=ineligible"; then
    echo "FAIL: static/builds.ini [w100-x64-28000] status is not ineligible."
    exit 1
fi

installer_au3="${repo_root}/client/UpdateInstaller.au3"
if ! grep -q '\["28000", "x64", "win11", "28000", "ineligible"' "$installer_au3"; then
    echo "FAIL: client/UpdateInstaller.au3 table missing build 28000 ineligible entry."
    exit 1
fi
if ! grep -q "IsBuildIneligible" "$installer_au3"; then
    echo "FAIL: client/UpdateInstaller.au3 missing IsBuildIneligible handler."
    exit 1
fi

echo "PASS: builds.ini and AutoIt registry table contracts verified."

# -----------------------------------------------------------------------
# Test 2: Static Manifests & Zero Checkpoint Leakage
# -----------------------------------------------------------------------
echo ""
echo "[Test 2/4] Verifying Static Manifests and Servicing Branch Isolation..."

client_static="${repo_root}/client/static"
for f in "StaticUpdateIds-w100-28000-x64.txt" \
         "StaticUpdateIds-w100-28000.txt" \
         "StaticUpdateIds-w100-28000-dotnet.txt" \
         "StaticUpdateIds-servicing-w100-28000.txt" \
         "StaticUpdateIds-wupre-w100-28000.txt"; do
    if [[ ! -f "${client_static}/${f}" ]]; then
        echo "FAIL: Dedicated static manifest ${f} missing."
        exit 1
    fi
done

# Verify zero KB5043080 checkpoint leakage into any 28000 files
if grep -q "5043080" "${client_static}"/*28000*.txt; then
    echo "FAIL: Checkpoint KB5043080 leaked into 28000 static manifests!"
    exit 1
fi

# Verify StaticUpdateIds-Checkpoints.txt does not contain 28000
chkpt_file="${client_static}/StaticUpdateIds-Checkpoints.txt"
if grep -q "28000" "$chkpt_file"; then
    echo "FAIL: StaticUpdateIds-Checkpoints.txt contains invalid 28000 checkpoint definition!"
    exit 1
fi

echo "PASS: Dedicated static manifests and branch isolation verified."

# -----------------------------------------------------------------------
# Test 3: Client Environment & .NET Target Resolution
# -----------------------------------------------------------------------
echo ""
echo "[Test 3/4] Verifying Client Environment Variables and .NET Target Resolution..."

settarget_cmd="${repo_root}/client/cmd/SetTargetEnvVars.cmd"
if ! grep -q "10.0.28000" "$settarget_cmd"; then
    echo "FAIL: SetTargetEnvVars.cmd missing 10.0.28000 target mapping."
    exit 1
fi
if ! grep -A 1 "10.0.28000" "$settarget_cmd" | grep -q "533320"; then
    echo "FAIL: SetTargetEnvVars.cmd 10.0.28000 does not set DOTNET4_RELEASE_TARGET=533320."
    exit 1
fi

# Verify UpdateInstaller.au3 maps 28000 to .NET 4.8.1 (533320)
if ! grep -A 8 'Case "WIN_11"' "$installer_au3" | grep -q '28000'; then
    echo "FAIL: UpdateInstaller.au3 DotNet4TargetRelease missing 28000 mapping."
    exit 1
fi

echo "PASS: Client environment variables and .NET target resolution verified."

# -----------------------------------------------------------------------
# Test 4: Feature Upgrade Ineligibility & Update Queue Isolation
# -----------------------------------------------------------------------
echo ""
echo "[Test 4/4] Verifying Feature Upgrade Ineligibility and Queue Isolation..."

buildupg_file="${client_static}/StaticUpdateIds-BuildUpgrades.txt"
if grep -q "^28000," "$buildupg_file"; then
    echo "FAIL: StaticUpdateIds-BuildUpgrades.txt offers an invalid feature upgrade from 28000!"
    exit 1
fi

# Verify that build 28000 is marked as status=ineligible
status_28000=$(awk -F',' '$1 ~ /"28000"/ { gsub(/[" ]/, "", $5); print $5 }' "$installer_au3")
if [[ "$status_28000" != "ineligible" ]]; then
    echo "FAIL: Build 28000 status in UpdateInstaller table is not ineligible: '$status_28000'."
    exit 1
fi

echo "PASS: Feature upgrade ineligibility and update queue isolation verified."

echo ""
echo "======================================================================="
echo "SUCCESS: All 4 Windows 11 26H1 Linux / Bash regression tests passed!"
echo "======================================================================="
exit 0
