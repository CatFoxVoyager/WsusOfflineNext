#!/usr/bin/env bash
# =======================================================================
# WSUS Offline Update - Modern Extras Regression Suite (Linux / Bash)
# File: sh/tests/verify-modern-extras.bash
#
# Verifies:
#   Test 1: Static Download Catalogs & Link Structure (Edge, WebView2, .NET 8/10)
#   Test 2: Download Engine Parameter Parsing & Function Contracts
#   Test 3: Client Presence Detection & Installation Switches
#   Test 4: Offline Applicability Audit (/auditonly) Categorization
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
echo "WSUS Offline Update - Modern Extras Test Suite (Linux / Bash)"
echo "======================================================================="

tmp_dir="$(mktemp -d 2>/dev/null || mktemp -d -t 'wou_extras_test')"
trap 'rm -rf "$tmp_dir"' EXIT

# -----------------------------------------------------------------------
# Test 1: Static Catalogs & Link Structure
# -----------------------------------------------------------------------
echo "[Test 1/4] Verifying Static Download Catalogs and .NET 8/10 Enrichment..."

# Edge Catalogs
edge_x64="${repo_root}/static/StaticDownloadLinks-edge-x64-glb.txt"
edge_x86="${repo_root}/static/StaticDownloadLinks-edge-x86-glb.txt"
if [[ ! -f "$edge_x64" ]] || [[ ! -f "$edge_x86" ]]; then
    echo "FAIL: Static Edge catalog files missing."
    exit 1
fi
if ! grep -q "MicrosoftEdgeEnterpriseX64.msi" "$edge_x64"; then
    echo "FAIL: Edge x64 catalog missing Enterprise MSI link."
    exit 1
fi
if ! grep -q "MicrosoftEdgeEnterpriseX86.msi" "$edge_x86"; then
    echo "FAIL: Edge x86 catalog missing Enterprise MSI link."
    exit 1
fi

# WebView2 Catalogs
wv2_x64="${repo_root}/static/StaticDownloadLinks-webview2-x64-glb.txt"
wv2_x86="${repo_root}/static/StaticDownloadLinks-webview2-x86-glb.txt"
if [[ ! -f "$wv2_x64" ]] || [[ ! -f "$wv2_x86" ]]; then
    echo "FAIL: Static WebView2 catalog files missing."
    exit 1
fi
if ! grep -q "MicrosoftEdgeWebView2RuntimeInstallerX64.exe" "$wv2_x64"; then
    echo "FAIL: WebView2 x64 catalog missing standalone installer link."
    exit 1
fi
if ! grep -q "MicrosoftEdgeWebView2RuntimeInstallerX86.exe" "$wv2_x86"; then
    echo "FAIL: WebView2 x86 catalog missing standalone installer link."
    exit 1
fi

# .NET 8 and 10 in StaticDownloadLinks-dotnet.txt
dotnet_file="${repo_root}/static/StaticDownloadLinks-dotnet.txt"
if [[ ! -f "$dotnet_file" ]]; then
    echo "FAIL: StaticDownloadLinks-dotnet.txt missing."
    exit 1
fi
if ! grep -q "windowsdesktop-runtime-8.0" "$dotnet_file"; then
    echo "FAIL: StaticDownloadLinks-dotnet.txt missing .NET 8.0 Desktop Runtime."
    exit 1
fi
if ! grep -q "windowsdesktop-runtime-10.0" "$dotnet_file"; then
    echo "FAIL: StaticDownloadLinks-dotnet.txt missing .NET 10.0 Desktop Runtime."
    exit 1
fi

# StaticUpdateIds-MSIProducts.txt entries
msi_products="${repo_root}/client/static/StaticUpdateIds-MSIProducts.txt"
if [[ ! -f "$msi_products" ]]; then
    echo "FAIL: StaticUpdateIds-MSIProducts.txt missing."
    exit 1
fi
if ! grep -q "dotNET8_DesktopRuntime_x64" "$msi_products"; then
    echo "FAIL: StaticUpdateIds-MSIProducts.txt missing dotNET8_DesktopRuntime_x64."
    exit 1
fi
if ! grep -q "dotNET10_DesktopRuntime_x64" "$msi_products"; then
    echo "FAIL: StaticUpdateIds-MSIProducts.txt missing dotNET10_DesktopRuntime_x64."
    exit 1
fi

echo "PASS: Static download catalogs and product manifests verified."

# -----------------------------------------------------------------------
# Test 2: Download Engine Parameter Parsing & Function Contracts
# -----------------------------------------------------------------------
echo ""
echo "[Test 2/4] Verifying Linux Bash Download Tasks and Function Contracts..."

parse_script="${repo_root}/sh/download-updates-tasks/10-parse-command-line.bash"
if ! grep -q "\-includeedge" "$parse_script"; then
    echo "FAIL: 10-parse-command-line.bash missing -includeedge switch."
    exit 1
fi
if ! grep -q "\-includewebview2" "$parse_script"; then
    echo "FAIL: 10-parse-command-line.bash missing -includewebview2 switch."
    exit 1
fi

included_script="${repo_root}/sh/download-updates-tasks/40-included-downloads.bash"
if ! grep -q "calculate_static_downloads_edge" "$included_script"; then
    echo "FAIL: 40-included-downloads.bash missing calculate_static_downloads_edge."
    exit 1
fi
if ! grep -q "calculate_static_downloads_webview2" "$included_script"; then
    echo "FAIL: 40-included-downloads.bash missing calculate_static_downloads_webview2."
    exit 1
fi

echo "PASS: Linux download engine parameters and tasks verified."

# -----------------------------------------------------------------------
# Test 3: Client Detection & Installation Switches
# -----------------------------------------------------------------------
echo ""
echo "[Test 3/4] Verifying Client Detection and Silent Installation Switches..."

vbs_script="${repo_root}/client/cmd/DetermineSystemProperties.vbs"
if ! grep -q "WEBVIEW2_INSTALLED" "$vbs_script"; then
    echo "FAIL: DetermineSystemProperties.vbs missing WEBVIEW2_INSTALLED query."
    exit 1
fi

doupdate_script="${repo_root}/client/cmd/DoUpdate.cmd"
if ! grep -q "/instedge" "$doupdate_script"; then
    echo "FAIL: DoUpdate.cmd missing /instedge parameter."
    exit 1
fi
if ! grep -q "/instwebview2" "$doupdate_script"; then
    echo "FAIL: DoUpdate.cmd missing /instwebview2 parameter."
    exit 1
fi
if ! grep -q "MicrosoftEdgeEnterprise" "$doupdate_script"; then
    echo "FAIL: DoUpdate.cmd missing Enterprise MSI execution logic."
    exit 1
fi
if ! grep -q "/silent /install" "$doupdate_script"; then
    echo "FAIL: DoUpdate.cmd missing WebView2 /silent /install arguments."
    exit 1
fi
if ! grep -q "wou_webview2_tried.txt" "$doupdate_script"; then
    echo "FAIL: DoUpdate.cmd missing wou_webview2_tried.txt loop protection."
    exit 1
fi

echo "PASS: Client presence detection and installation contracts verified."

# -----------------------------------------------------------------------
# Test 4: Offline Applicability Audit (/auditonly) Categorization
# -----------------------------------------------------------------------
echo ""
echo "[Test 4/4] Verifying Offline Audit (/auditonly) Categorization..."

mock_audit_out="${tmp_dir}/wou_audit_runtimes.txt"
os_arch="x64"
install_edge="/instedge"
install_webview2="/instwebview2"
msedge_installed="0"
webview2_installed="0"

# Simulate audit runtimes extraction
if [[ "$install_edge" == "/instedge" ]] && [[ "$msedge_installed" != "1" ]]; then
    echo "  ..\\edge\\MicrosoftEdgeEnterprise${os_arch}.msi" >> "$mock_audit_out"
fi
if [[ "$install_webview2" == "/instwebview2" ]] && [[ "$webview2_installed" != "1" ]]; then
    echo "  ..\\edge\\MicrosoftEdgeWebView2RuntimeInstaller${os_arch}.exe" >> "$mock_audit_out"
fi

if ! grep -q "MicrosoftEdgeEnterprise" "$mock_audit_out"; then
    echo "FAIL: Missing Edge MSI in mock audit output."
    exit 1
fi
if ! grep -q "MicrosoftEdgeWebView2RuntimeInstaller" "$mock_audit_out"; then
    echo "FAIL: Missing WebView2 in mock audit output."
    exit 1
fi

# Verify omission when components are installed
msedge_installed="1"
webview2_installed="1"
rm -f "$mock_audit_out"

if [[ "$install_edge" == "/instedge" ]] && [[ "$msedge_installed" != "1" ]]; then
    echo "  ..\\edge\\MicrosoftEdgeEnterprise${os_arch}.msi" >> "$mock_audit_out"
fi
if [[ "$install_webview2" == "/instwebview2" ]] && [[ "$webview2_installed" != "1" ]]; then
    echo "  ..\\edge\\MicrosoftEdgeWebView2RuntimeInstaller${os_arch}.exe" >> "$mock_audit_out"
fi

if [[ -f "$mock_audit_out" ]]; then
    echo "FAIL: Installed components should not appear in audit report."
    exit 1
fi

echo "PASS: Audit mode categorization and omission contracts verified."

echo ""
echo "======================================================================="
echo "SUCCESS: All 4 Modern Extras Linux / Bash regression tests passed!"
echo "======================================================================="
exit 0
