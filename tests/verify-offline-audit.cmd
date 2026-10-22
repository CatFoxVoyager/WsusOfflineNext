@echo off
setlocal enabledelayedexpansion

REM =======================================================================
REM WSUS Offline Update - Offline Applicability & Missing Updates Report Test Suite
REM File: tests\verify-offline-audit.cmd
REM
REM Scenarios:
REM   1. Mixed Update Queue Categorization & Report Generation
REM      (LCU, SSU, Office, Defender, Runtimes)
REM   2. Clean Endpoint Simulation (0 Missing Updates, Up-to-date Result)
REM   3. Non-destructive Verification (Zero System State Mutations)
REM   4. Office Click-to-Run (C2R) Staged Manifest Classification
REM   5. Write-Protected Log Directory Fallback to SystemRoot
REM =======================================================================

pushd "%~dp0.."
set "REPO_ROOT=%CD%"
popd

echo =======================================================================
echo WSUS Offline Update - Offline Audit Regression Suite (Windows CMD)
echo =======================================================================

REM Set up isolated test sandbox
set "SANDBOX_ROOT=%TEMP%\wou_test_audit_%RANDOM%_%RANDOM%"
mkdir "%SANDBOX_ROOT%\client\cmd" 2>nul
mkdir "%SANDBOX_ROOT%\log" 2>nul
mkdir "%SANDBOX_ROOT%\temp" 2>nul
mkdir "%SANDBOX_ROOT%\mock_win" 2>nul

if not exist "%SANDBOX_ROOT%\client\cmd" (
  echo ERROR: Failed to create test sandbox at "%SANDBOX_ROOT%".
  exit /b 1
)

copy /y "%REPO_ROOT%\client\cmd\DoUpdate.cmd" "%SANDBOX_ROOT%\client\cmd\" >nul

set "ORIG_TEMP=%TEMP%"
set "ORIG_SYSROOT=%SystemRoot%"
set "TEMP=%SANDBOX_ROOT%\temp"
set "UPDATE_LOGFILE=%SANDBOX_ROOT%\log\test_audit.log"
set "OS_NAME=w100"
set "OS_VER_MAJOR=10"
set "OS_VER_MINOR=0"
set "OS_VER_BUILD=26100"
set "OS_VER_REVIS=1"
set "OS_ARCH=x64"

REM -----------------------------------------------------------------------
REM Scenario 1: Mixed Update Queue Categorization & Missing Updates Report
REM -----------------------------------------------------------------------
echo [Scenario 1/5] Verifying mixed queue categorization and report generation...

(
  echo ..\w100-x64\glb\windows11.0-kb5054156-x64.msu
  echo ..\w100-x64\glb\windows11.0-kb5043080-x64.msu
  echo ..\w100-x64\glb\windows10.0-kb5005112-x64-ssu.cab
  echo ..\o2k16\glb\excel2016-kb5002165-fullfile-x64-glb.exe
  echo ..\wddefs\x64-glb\mpam-fe.exe
  echo ..\dotnet\ndp481-x86-x64-allos-enu.exe
  echo ..\cpp\vcredist2022_x64.exe
) > "%TEMP%\UpdatesToInstall.txt"

pushd "%SANDBOX_ROOT%\client\cmd"
call .\DoUpdate.cmd :WriteMissingUpdatesReport > "%SANDBOX_ROOT%\log\scen1_stdout.log" 2>&1
popd

set "REPORT_FILE=%SANDBOX_ROOT%\log\MissingUpdates.txt"
if not exist "%REPORT_FILE%" (
  echo FAIL Scenario 1: MissingUpdates.txt was not created at "%REPORT_FILE%".
  goto Fail
)

%ORIG_SYSROOT%\System32\findstr.exe /I /C:"Total Missing Items:     7" "%REPORT_FILE%" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 1: Total Missing Items is not 7.
  type "%REPORT_FILE%"
  goto Fail
)

%ORIG_SYSROOT%\System32\findstr.exe /I /C:"[Windows Cumulative & Checkpoint Updates] [Count: 2]" "%REPORT_FILE%" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 1: LCU/CCU count mismatch.
  goto Fail
)

%ORIG_SYSROOT%\System32\findstr.exe /I /C:"[Integrated Servicing Stack Updates] [Count: 1]" "%REPORT_FILE%" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 1: SSU count mismatch.
  goto Fail
)

%ORIG_SYSROOT%\System32\findstr.exe /I /C:"[Windows Defender Security Intelligence] [Count: 1]" "%REPORT_FILE%" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 1: Defender count mismatch.
  goto Fail
)

%ORIG_SYSROOT%\System32\findstr.exe /I /C:"[Microsoft Office Updates] [Count: 1]" "%REPORT_FILE%" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 1: Office count mismatch.
  goto Fail
)

%ORIG_SYSROOT%\System32\findstr.exe /I /C:"[Modern Extras & Runtimes] [Count: 2]" "%REPORT_FILE%" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 1: Runtimes count mismatch.
  goto Fail
)

%ORIG_SYSROOT%\System32\findstr.exe /I /C:"Audit Result: Updates required [7 item(s) missing]" "%REPORT_FILE%" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 1: Audit Result mismatch.
  goto Fail
)

echo [PASS] Scenario 1: Mixed update queue correctly categorized across all 5 buckets (7 items).

REM -----------------------------------------------------------------------
REM Scenario 2: Clean Endpoint Simulation (0 Missing Updates)
REM -----------------------------------------------------------------------
echo [Scenario 2/5] Verifying clean endpoint simulation (0 missing updates)...

if exist "%TEMP%\UpdatesToInstall.txt" del "%TEMP%\UpdatesToInstall.txt"
if exist "%REPORT_FILE%" del "%REPORT_FILE%"

pushd "%SANDBOX_ROOT%\client\cmd"
call .\DoUpdate.cmd :WriteMissingUpdatesReport > "%SANDBOX_ROOT%\log\scen2_stdout.log" 2>&1
popd

if not exist "%REPORT_FILE%" (
  echo FAIL Scenario 2: MissingUpdates.txt not created for clean endpoint.
  goto Fail
)

%ORIG_SYSROOT%\System32\findstr.exe /I /C:"Total Missing Items:     0" "%REPORT_FILE%" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 2: Clean machine did not report 0 missing items.
  type "%REPORT_FILE%"
  goto Fail
)

%ORIG_SYSROOT%\System32\findstr.exe /I /C:"Audit Result: System is fully up to date [0 missing updates]" "%REPORT_FILE%" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 2: Clean machine audit result text mismatch.
  goto Fail
)

%ORIG_SYSROOT%\System32\findstr.exe /I /C:"None missing [Up to date]" "%REPORT_FILE%" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 2: Clean machine placeholder text missing.
  goto Fail
)

echo [PASS] Scenario 2: Clean endpoint correctly reported 0 missing updates and up to date status.

REM -----------------------------------------------------------------------
REM Scenario 3: Non-destructive Verification (Zero System State Mutations)
REM -----------------------------------------------------------------------
echo [Scenario 3/5] Verifying non-destructive execution guarantees...

REM Check that no recall, reboot, or autologon state markers exist in TEMP
if exist "%TEMP%\wou_recall.cmd" (
  echo FAIL Scenario 3: wou_recall.cmd found in temp directory.
  goto Fail
)
if exist "%TEMP%\wou_reboot.cmd" (
  echo FAIL Scenario 3: wou_reboot.cmd found in temp directory.
  goto Fail
)
if exist "%TEMP%\rebootinfo.txt" (
  echo FAIL Scenario 3: rebootinfo.txt found in temp directory.
  goto Fail
)
if exist "%TEMP%\wou_wuvars.cmd" (
  echo FAIL Scenario 3: wou_wuvars.cmd found in temp directory.
  goto Fail
)

REM Verify that /auditonly report header explicitly declares zero modifications
%ORIG_SYSROOT%\System32\findstr.exe /I /C:"Audit Only [/auditonly - Zero System Modifications]" "%REPORT_FILE%" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 3: Report missing zero system modifications declaration.
  goto Fail
)

echo [PASS] Scenario 3: Non-destructive audit execution verified [no state mutation markers].

REM -----------------------------------------------------------------------
REM Scenario 4: Office Click-to-Run (C2R) Staged Manifest Classification
REM -----------------------------------------------------------------------
echo [Scenario 4/5] Verifying Office C2R staged manifest categorization and metadata...

if exist "%TEMP%\UpdatesToInstall.txt" del "%TEMP%\UpdatesToInstall.txt"
if exist "%REPORT_FILE%" del "%REPORT_FILE%"

set "O2K16_IS_C2R=1"
set "O2K16_VER_MAJOR=16"
set "O2K16_VER_MINOR=0"
set "O2K16_VER_BUILD=17928"
set "O2K16_VER_REVIS=20156"
set "O2K16_ARCH=x64"
set "O2K16_LANG=enu"
set "O2K16_PRODUCT_NAME=Office ProPlus 2021"
set "O2K16_C2R_CHANNEL=PerpetualVL2021"
set "O2K16_EOL_STATUS=Supported"

(
  echo %TEMP%\wou_c2r_update.xml
) > "%TEMP%\UpdatesToInstall.txt"

pushd "%SANDBOX_ROOT%\client\cmd"
call .\DoUpdate.cmd :WriteMissingUpdatesReport > "%SANDBOX_ROOT%\log\scen4_c2r_stdout.log" 2>&1
popd

if not exist "%REPORT_FILE%" (
  echo FAIL Scenario 4: MissingUpdates.txt was not created for C2R test.
  goto Fail
)

%ORIG_SYSROOT%\System32\findstr.exe /I /C:"Total Missing Items:     1" "%REPORT_FILE%" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 4: Total Missing Items is not 1.
  type "%REPORT_FILE%"
  goto Fail
)

%ORIG_SYSROOT%\System32\findstr.exe /I /C:"[Microsoft Office Updates] [Count: 1]" "%REPORT_FILE%" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 4: Office C2R count mismatch.
  goto Fail
)

%ORIG_SYSROOT%\System32\findstr.exe /I /C:"Microsoft Office ProPlus 2021 (x64) - Staged C2R Update Package [Channel: PerpetualVL2021]" "%REPORT_FILE%" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 4: C2R manifest entry formatting mismatch.
  type "%REPORT_FILE%"
  goto Fail
)

%ORIG_SYSROOT%\System32\findstr.exe /I /C:"Target Office:           Microsoft Office ProPlus 2021 16.0.17928.20156 (x64 enu) [Channel: PerpetualVL2021, Status: Supported]" "%REPORT_FILE%" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 4: Target Office C2R header formatting mismatch.
  type "%REPORT_FILE%"
  goto Fail
)

set "O2K16_IS_C2R="
set "O2K16_VER_MAJOR="
set "O2K16_VER_MINOR="
set "O2K16_VER_BUILD="
set "O2K16_VER_REVIS="
set "O2K16_ARCH="
set "O2K16_LANG="
set "O2K16_PRODUCT_NAME="
set "O2K16_C2R_CHANNEL="
set "O2K16_EOL_STATUS="

echo [PASS] Scenario 4: Office C2R staged manifest correctly categorized with rich channel metadata.

REM -----------------------------------------------------------------------
REM Scenario 5: Write-Protected Log Directory Fallback to SystemRoot
REM -----------------------------------------------------------------------
echo [Scenario 5/5] Verifying fallback to SystemRoot when log dir is unwritable...

set "FALLBACK_TARGET=%SANDBOX_ROOT%\mock_win\wsusofflineupdate_MissingUpdates.txt"
set "WOU_MISSING_LOG_FALLBACK=%FALLBACK_TARGET%"

if exist "%SANDBOX_ROOT%\log" rmdir /s /q "%SANDBOX_ROOT%\log" 2>nul
echo read-only-log-blocker > "%SANDBOX_ROOT%\log"
attrib +r "%SANDBOX_ROOT%\log" 2>nul

(
  echo ..\w100-x64\glb\windows11.0-kb5054156-x64.msu
) > "%TEMP%\UpdatesToInstall.txt"

pushd "%SANDBOX_ROOT%\client\cmd"
call .\DoUpdate.cmd :WriteMissingUpdatesReport > "%SANDBOX_ROOT%\mock_win\scen4_stdout.log" 2>&1
popd

if not exist "%FALLBACK_TARGET%" (
  echo FAIL Scenario 5: Fallback file "%FALLBACK_TARGET%" was not created!
  if exist "%SANDBOX_ROOT%\mock_win\scen4_stdout.log" type "%SANDBOX_ROOT%\mock_win\scen4_stdout.log"
  goto Fail
)

%ORIG_SYSROOT%\System32\findstr.exe /I /C:"Total Missing Items:     1" "%FALLBACK_TARGET%" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 5: Fallback file does not contain expected item count.
  type "%FALLBACK_TARGET%"
  goto Fail
)

set "WOU_MISSING_LOG_FALLBACK="
echo [PASS] Scenario 5: Write-protected log fallback successfully verified.

REM -----------------------------------------------------------------------
REM Cleanup and Success
REM -----------------------------------------------------------------------
set "TEMP=%ORIG_TEMP%"
set "SystemRoot=%ORIG_SYSROOT%"
attrib -r "%SANDBOX_ROOT%\log" 2>nul
rmdir /s /q "%SANDBOX_ROOT%" 2>nul
del "%SANDBOX_ROOT%\log" 2>nul

echo =======================================================================
echo Offline Applicability Report Test Suite: ALL TESTS PASSED
echo =======================================================================
exit /b 0

:Fail
set "TEMP=%ORIG_TEMP%"
set "SystemRoot=%ORIG_SYSROOT%"
attrib -r "%SANDBOX_ROOT%\log" 2>nul
rmdir /s /q "%SANDBOX_ROOT%" 2>nul
del "%SANDBOX_ROOT%\log" 2>nul
echo =======================================================================
echo Offline Applicability Report Test Suite: FAILED
echo =======================================================================
exit /b 1
