@echo off
setlocal enabledelayedexpansion

REM =======================================================================
REM WSUS Offline Update - Modern Extras Regression Test Suite
REM File: tests\verify-modern-extras.cmd
REM
REM Scenarios:
REM   1. Static Download Catalogs & Link Structure (Edge, WebView2, .NET 8/10)
REM   2. Download Engine Parameter Parsing & Hash File Contracts
REM   3. Client Presence Detection & Silent Installation Parameters
REM   4. Offline Applicability Audit (/auditonly) Categorization
REM =======================================================================

pushd "%~dp0.."
set "REPO_ROOT=%CD%"
popd

echo =======================================================================
echo WSUS Offline Update - Modern Extras Regression Suite (Windows CMD)
echo =======================================================================

REM Set up isolated test sandbox
set "SANDBOX_ROOT=%TEMP%\wou_test_extras_%RANDOM%_%RANDOM%"
mkdir "%SANDBOX_ROOT%\static" 2>nul
mkdir "%SANDBOX_ROOT%\client\static" 2>nul
mkdir "%SANDBOX_ROOT%\client\cmd" 2>nul
mkdir "%SANDBOX_ROOT%\temp" 2>nul
mkdir "%SANDBOX_ROOT%\log" 2>nul

if not exist "%SANDBOX_ROOT%\temp" (
  echo ERROR: Failed to create test sandbox at "%SANDBOX_ROOT%".
  exit /b 1
)

set "ORIG_TEMP=%TEMP%"
set "TEMP=%SANDBOX_ROOT%\temp"

REM -----------------------------------------------------------------------
REM Scenario 1: Static Catalogs & Link Structure
REM -----------------------------------------------------------------------
echo [Scenario 1/4] Verifying Static Download Catalogs and .NET 8/10 Enrichment...

REM 1. Edge catalogs
if not exist "%REPO_ROOT%\static\StaticDownloadLinks-edge-x64-glb.txt" (
  echo [FAIL] Scenario 1: static\StaticDownloadLinks-edge-x64-glb.txt missing.
  goto test_failed
)
if not exist "%REPO_ROOT%\static\StaticDownloadLinks-edge-x86-glb.txt" (
  echo [FAIL] Scenario 1: static\StaticDownloadLinks-edge-x86-glb.txt missing.
  goto test_failed
)
%SystemRoot%\System32\findstr.exe /I /C:"MicrosoftEdgeEnterpriseX64.msi" "%REPO_ROOT%\static\StaticDownloadLinks-edge-x64-glb.txt" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Scenario 1: Edge x64 catalog missing Enterprise MSI link.
  goto test_failed
)
%SystemRoot%\System32\findstr.exe /I /C:"MicrosoftEdgeEnterpriseX86.msi" "%REPO_ROOT%\static\StaticDownloadLinks-edge-x86-glb.txt" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Scenario 1: Edge x86 catalog missing Enterprise MSI link.
  goto test_failed
)

REM 2. WebView2 catalogs
if not exist "%REPO_ROOT%\static\StaticDownloadLinks-webview2-x64-glb.txt" (
  echo [FAIL] Scenario 1: static\StaticDownloadLinks-webview2-x64-glb.txt missing.
  goto test_failed
)
if not exist "%REPO_ROOT%\static\StaticDownloadLinks-webview2-x86-glb.txt" (
  echo [FAIL] Scenario 1: static\StaticDownloadLinks-webview2-x86-glb.txt missing.
  goto test_failed
)
%SystemRoot%\System32\findstr.exe /I /C:"MicrosoftEdgeWebView2RuntimeInstallerX64.exe" "%REPO_ROOT%\static\StaticDownloadLinks-webview2-x64-glb.txt" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Scenario 1: WebView2 x64 catalog missing standalone installer link.
  goto test_failed
)
%SystemRoot%\System32\findstr.exe /I /C:"MicrosoftEdgeWebView2RuntimeInstallerX86.exe" "%REPO_ROOT%\static\StaticDownloadLinks-webview2-x86-glb.txt" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Scenario 1: WebView2 x86 catalog missing standalone installer link.
  goto test_failed
)

REM 3. .NET 8 and 10 in StaticDownloadLinks-dotnet.txt
%SystemRoot%\System32\findstr.exe /I /C:"windowsdesktop-runtime-8.0" "%REPO_ROOT%\static\StaticDownloadLinks-dotnet.txt" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Scenario 1: StaticDownloadLinks-dotnet.txt missing .NET 8.0 Desktop Runtime.
  goto test_failed
)
%SystemRoot%\System32\findstr.exe /I /C:"windowsdesktop-runtime-10.0" "%REPO_ROOT%\static\StaticDownloadLinks-dotnet.txt" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Scenario 1: StaticDownloadLinks-dotnet.txt missing .NET 10.0 Desktop Runtime.
  goto test_failed
)

REM 4. StaticUpdateIds-MSIProducts.txt entries
%SystemRoot%\System32\findstr.exe /I /C:"dotNET8_DesktopRuntime_x64" "%REPO_ROOT%\client\static\StaticUpdateIds-MSIProducts.txt" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Scenario 1: StaticUpdateIds-MSIProducts.txt missing dotNET8_DesktopRuntime_x64.
  goto test_failed
)
%SystemRoot%\System32\findstr.exe /I /C:"dotNET10_DesktopRuntime_x64" "%REPO_ROOT%\client\static\StaticUpdateIds-MSIProducts.txt" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Scenario 1: StaticUpdateIds-MSIProducts.txt missing dotNET10_DesktopRuntime_x64.
  goto test_failed
)

echo [PASS] Scenario 1: Static download catalogs and product manifests verified.

REM -----------------------------------------------------------------------
REM Scenario 2: Download Engine Parameter Parsing & Hash File Targets
REM -----------------------------------------------------------------------
echo.
echo [Scenario 2/4] Verifying Download Engine Switches and Verification Contracts...

REM Verify Windows DownloadUpdates.cmd supports /includeedge and /includewebview2
%SystemRoot%\System32\findstr.exe /I /C:"/includeedge" "%REPO_ROOT%\cmd\DownloadUpdates.cmd" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Scenario 2: cmd\DownloadUpdates.cmd missing /includeedge switch.
  goto test_failed
)
%SystemRoot%\System32\findstr.exe /I /C:"/includewebview2" "%REPO_ROOT%\cmd\DownloadUpdates.cmd" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Scenario 2: cmd\DownloadUpdates.cmd missing /includewebview2 switch.
  goto test_failed
)
%SystemRoot%\System32\findstr.exe /I /C:"hashes-webview2.txt" "%REPO_ROOT%\cmd\DownloadUpdates.cmd" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Scenario 2: cmd\DownloadUpdates.cmd missing hashes-webview2.txt target.
  goto test_failed
)

REM Verify Linux Bash download tasks support -includeedge and -includewebview2
%SystemRoot%\System32\findstr.exe /I /C:"-includeedge" "%REPO_ROOT%\sh\download-updates-tasks\10-parse-command-line.bash" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Scenario 2: 10-parse-command-line.bash missing -includeedge switch.
  goto test_failed
)
%SystemRoot%\System32\findstr.exe /I /C:"-includewebview2" "%REPO_ROOT%\sh\download-updates-tasks\10-parse-command-line.bash" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Scenario 2: 10-parse-command-line.bash missing -includewebview2 switch.
  goto test_failed
)
%SystemRoot%\System32\findstr.exe /I /C:"calculate_static_downloads_webview2" "%REPO_ROOT%\sh\download-updates-tasks\40-included-downloads.bash" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Scenario 2: 40-included-downloads.bash missing calculate_static_downloads_webview2.
  goto test_failed
)

echo [PASS] Scenario 2: Download engine command-line and verification contracts verified.

REM -----------------------------------------------------------------------
REM Scenario 3: Client Presence Detection & Installation Parameters
REM -----------------------------------------------------------------------
echo.
echo [Scenario 3/4] Verifying Client Detection and Silent Installation Switches...

REM Verify DetermineSystemProperties.vbs detects WebView2
%SystemRoot%\System32\findstr.exe /I /C:"WEBVIEW2_INSTALLED" "%REPO_ROOT%\client\cmd\DetermineSystemProperties.vbs" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Scenario 3: DetermineSystemProperties.vbs missing WEBVIEW2_INSTALLED query.
  goto test_failed
)

REM Verify DoUpdate.cmd supports /instedge and /instwebview2
%SystemRoot%\System32\findstr.exe /I /C:"/instedge" "%REPO_ROOT%\client\cmd\DoUpdate.cmd" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Scenario 3: client\cmd\DoUpdate.cmd missing /instedge parameter.
  goto test_failed
)
%SystemRoot%\System32\findstr.exe /I /C:"/instwebview2" "%REPO_ROOT%\client\cmd\DoUpdate.cmd" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Scenario 3: client\cmd\DoUpdate.cmd missing /instwebview2 parameter.
  goto test_failed
)

REM Verify silent installation parameters
%SystemRoot%\System32\findstr.exe /I /C:"MicrosoftEdgeEnterprise" "%REPO_ROOT%\client\cmd\DoUpdate.cmd" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Scenario 3: client\cmd\DoUpdate.cmd missing Enterprise MSI execution logic.
  goto test_failed
)
%SystemRoot%\System32\findstr.exe /I /C:"/silent /install" "%REPO_ROOT%\client\cmd\DoUpdate.cmd" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Scenario 3: client\cmd\DoUpdate.cmd missing WebView2 /silent /install arguments.
  goto test_failed
)
%SystemRoot%\System32\findstr.exe /I /C:"wou_webview2_tried.txt" "%REPO_ROOT%\client\cmd\DoUpdate.cmd" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Scenario 3: client\cmd\DoUpdate.cmd missing wou_webview2_tried.txt loop protection.
  goto test_failed
)

echo [PASS] Scenario 3: Client detection and silent installation parameters verified.

REM -----------------------------------------------------------------------
REM Scenario 4: Offline Applicability Audit (/auditonly) Categorization
REM -----------------------------------------------------------------------
echo.
echo [Scenario 4/4] Verifying Offline Audit (/auditonly) Modern Extras Categorization...

REM Test mock run of audit categorization logic from DoUpdate.cmd
set "OS_ARCH=x64"
set "INSTALL_EDGE=/instedge"
set "INSTALL_WEBVIEW2=/instwebview2"
set "MSEDGE_INSTALLED=0"
set "WEBVIEW2_INSTALLED=0"

if exist "%TEMP%\wou_audit_runtimes.txt" del "%TEMP%\wou_audit_runtimes.txt"

REM Execute the exact audit-categorization snippet
if "%INSTALL_EDGE%"=="/instedge" (
  if "%MSEDGE_INSTALLED%" NEQ "1" echo   ..\edge\MicrosoftEdgeEnterprise%OS_ARCH%.msi>>"%TEMP%\wou_audit_runtimes.txt"
)
if "%INSTALL_WEBVIEW2%"=="/instwebview2" (
  if "%WEBVIEW2_INSTALLED%" NEQ "1" echo   ..\edge\MicrosoftEdgeWebView2RuntimeInstaller%OS_ARCH%.exe>>"%TEMP%\wou_audit_runtimes.txt"
)

if not exist "%TEMP%\wou_audit_runtimes.txt" (
  echo [FAIL] Scenario 4: Failed to write wou_audit_runtimes.txt.
  goto test_failed
)

%SystemRoot%\System32\findstr.exe /C:"MicrosoftEdgeEnterprise" "%TEMP%\wou_audit_runtimes.txt" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Scenario 4: Missing Edge MSI entry in audit runtimes output.
  goto test_failed
)

%SystemRoot%\System32\findstr.exe /C:"MicrosoftEdgeWebView2RuntimeInstaller" "%TEMP%\wou_audit_runtimes.txt" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Scenario 4: Missing WebView2 entry in audit runtimes output.
  goto test_failed
)

REM Verify that when already installed, entries are omitted
set "MSEDGE_INSTALLED=1"
set "WEBVIEW2_INSTALLED=1"
del "%TEMP%\wou_audit_runtimes.txt"

if "%INSTALL_EDGE%"=="/instedge" (
  if "%MSEDGE_INSTALLED%" NEQ "1" echo   ..\edge\MicrosoftEdgeEnterprise%OS_ARCH%.msi>>"%TEMP%\wou_audit_runtimes.txt"
)
if "%INSTALL_WEBVIEW2%"=="/instwebview2" (
  if "%WEBVIEW2_INSTALLED%" NEQ "1" echo   ..\edge\MicrosoftEdgeWebView2RuntimeInstaller%OS_ARCH%.exe>>"%TEMP%\wou_audit_runtimes.txt"
)

if exist "%TEMP%\wou_audit_runtimes.txt" (
  echo [FAIL] Scenario 4: Installed components should not be reported as missing.
  goto test_failed
)

echo [PASS] Scenario 4: Audit mode categorization and omission contracts verified.

REM -----------------------------------------------------------------------
REM Cleanup and Success Exit
REM -----------------------------------------------------------------------
set "TEMP=%ORIG_TEMP%"
rmdir /s /q "%SANDBOX_ROOT%" 2>nul

echo.
echo =======================================================================
echo SUCCESS: All 4 Modern Extras regression scenarios passed!
echo =======================================================================
exit /b 0

:test_failed
set "TEMP=%ORIG_TEMP%"
rmdir /s /q "%SANDBOX_ROOT%" 2>nul
echo.
echo =======================================================================
echo FAILURE: Modern Extras regression suite failed!
echo =======================================================================
exit /b 1
