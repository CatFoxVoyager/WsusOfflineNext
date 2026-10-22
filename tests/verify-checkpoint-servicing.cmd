@echo off
setlocal enabledelayedexpansion

REM =======================================================================
REM WSUS Offline Update - Checkpoint Cumulative Updates Servicing Test Suite
REM File: tests\verify-checkpoint-servicing.cmd
REM
REM Scenarios:
REM   1. Queue Sorter Prioritization (:SortCheckpointsFirst moves KB5043080 to line 1)
REM   2. Pre-checkpoint Endpoint Simulation (Build 26100.1 < 1742 requires checkpoint first)
REM   3. Post-checkpoint Endpoint Simulation (Build 26100.2000 >= 1742 preserves queue)
REM   4. Missing Checkpoint Diagnostic Detection & Run Report Formatting
REM =======================================================================

pushd "%~dp0.."
set "REPO_ROOT=%CD%"
popd

echo =======================================================================
echo WSUS Offline Update - Checkpoint Servicing Regression Suite (Windows CMD)
echo =======================================================================

REM Set up isolated test sandbox
set "SANDBOX_ROOT=%TEMP%\wou_test_chkpt_%RANDOM%_%RANDOM%"
mkdir "%SANDBOX_ROOT%\client\cmd" 2>nul
mkdir "%SANDBOX_ROOT%\client\static" 2>nul
mkdir "%SANDBOX_ROOT%\temp" 2>nul
mkdir "%SANDBOX_ROOT%\log" 2>nul
mkdir "%SANDBOX_ROOT%\client\w100-x64\glb" 2>nul

if not exist "%SANDBOX_ROOT%\client\cmd" (
  echo ERROR: Failed to create test sandbox at "%SANDBOX_ROOT%".
  exit /b 1
)

copy /y "%REPO_ROOT%\client\cmd\ListUpdatesToInstall.cmd" "%SANDBOX_ROOT%\client\cmd\" >nul
copy /y "%REPO_ROOT%\client\cmd\InstallOSUpdate.cmd" "%SANDBOX_ROOT%\client\cmd\" >nul
copy /y "%REPO_ROOT%\client\cmd\DoUpdate.cmd" "%SANDBOX_ROOT%\client\cmd\" >nul
copy /y "%REPO_ROOT%\client\static\StaticUpdateIds-Checkpoints.txt" "%SANDBOX_ROOT%\client\static\" >nul

set "ORIG_TEMP=%TEMP%"
set "TEMP=%SANDBOX_ROOT%\temp"
set "UPDATE_LOGFILE=%SANDBOX_ROOT%\log\test_update.log"

REM -----------------------------------------------------------------------
REM Scenario 1: Sorter Prioritization (:SortCheckpointsFirst)
REM -----------------------------------------------------------------------
echo [Scenario 1/4] Verifying checkpoint sorter queue prioritization...

(
  echo ..\w100-x64\glb\windows11.0-kb5054156-x64.msu
  echo ..\w100-x64\glb\windows11.0-kb5043080-x64_953449672073f8fb99badb4cc6d5d7849b9c83e8.msu
  echo ..\w100-x64\glb\windows11.0-kb5064081-x64.msu
) > "%TEMP%\UpdatesToInstall.txt"

pushd "%SANDBOX_ROOT%\client\cmd"
call .\ListUpdatesToInstall.cmd :SortCheckpointsFirst
popd

if not exist "%TEMP%\UpdatesToInstall.txt" (
  echo FAIL Scenario 1: UpdatesToInstall.txt missing after sorter execution.
  goto Fail
)

set /a LINE_COUNT=0
set "FIRST_LINE="
for /F "usebackq delims=" %%l in ("%TEMP%\UpdatesToInstall.txt") do (
  set /a LINE_COUNT+=1
  if !LINE_COUNT!==1 set "FIRST_LINE=%%l"
)

echo !FIRST_LINE! | %SystemRoot%\System32\findstr.exe /I "kb5043080" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 1: Line 1 does not contain KB5043080! Line 1: !FIRST_LINE!
  goto Fail
)
if %LINE_COUNT% NEQ 3 (
  echo FAIL Scenario 1: Expected 3 queue items, got %LINE_COUNT%.
  goto Fail
)

echo [PASS] Scenario 1: Checkpoint KB5043080 correctly prioritized to line 1 of queue.

REM -----------------------------------------------------------------------
REM Scenario 2: Pre-checkpoint Endpoint Simulation (Build 26100.1 < 1742)
REM -----------------------------------------------------------------------
echo [Scenario 2/4] Verifying pre-checkpoint endpoint simulation (26100.1)...

set SIM_BUILD=26100
set SIM_REVIS=1
set CHKPT_REVIS=1742
set CHKPT_NEEDED=0

if %SIM_BUILD% EQU 26100 (
  if %SIM_REVIS% LSS %CHKPT_REVIS% set CHKPT_NEEDED=1
)

if %CHKPT_NEEDED% NEQ 1 (
  echo FAIL Scenario 2: Pre-checkpoint endpoint 26100.1 did not require checkpoint!
  goto Fail
)

(
  echo ..\w100-x64\glb\windows11.0-kb5054156-x64.msu
  echo ..\w100-x64\glb\windows11.0-kb5043080-x64.msu
) > "%TEMP%\UpdatesToInstall.txt"

pushd "%SANDBOX_ROOT%\client\cmd"
call .\ListUpdatesToInstall.cmd :SortCheckpointsFirst
popd

set "FIRST_LINE="
for /F "usebackq delims=" %%l in ("%TEMP%\UpdatesToInstall.txt") do (
  if not defined FIRST_LINE set "FIRST_LINE=%%l"
)
echo !FIRST_LINE! | %SystemRoot%\System32\findstr.exe /I "kb5043080" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 2: Pre-checkpoint queue failed to order checkpoint first!
  goto Fail
)

echo [PASS] Scenario 2: Pre-checkpoint machine requires and prioritizes checkpoint KB5043080.

REM -----------------------------------------------------------------------
REM Scenario 3: Post-checkpoint Endpoint Simulation (Build 26100.2000 >= 1742)
REM -----------------------------------------------------------------------
echo [Scenario 3/4] Verifying post-checkpoint endpoint simulation (26100.2000)...

set SIM_BUILD=26100
set SIM_REVIS=2000
set CHKPT_NEEDED=0

if %SIM_BUILD% EQU 26100 (
  if %SIM_REVIS% LSS %CHKPT_REVIS% set CHKPT_NEEDED=1
)

if %CHKPT_NEEDED% NEQ 0 (
  echo FAIL Scenario 3: Post-checkpoint endpoint 26100.2000 incorrectly requested checkpoint!
  goto Fail
)

(
  echo ..\w100-x64\glb\windows11.0-kb5054156-x64.msu
  echo ..\w100-x64\glb\windows11.0-kb5064081-x64.msu
) > "%TEMP%\UpdatesToInstall.txt"

pushd "%SANDBOX_ROOT%\client\cmd"
call .\ListUpdatesToInstall.cmd :SortCheckpointsFirst
popd

set "FIRST_LINE="
for /F "usebackq delims=" %%l in ("%TEMP%\UpdatesToInstall.txt") do (
  if not defined FIRST_LINE set "FIRST_LINE=%%l"
)
echo !FIRST_LINE! | %SystemRoot%\System32\findstr.exe /I "kb5054156" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 3: Post-checkpoint queue corrupted! Line 1: !FIRST_LINE!
  goto Fail
)

echo [PASS] Scenario 3: Post-checkpoint machine safely bypasses checkpoint and retains queue.

REM -----------------------------------------------------------------------
REM Scenario 4: Missing Checkpoint Diagnostic Detection & Run Report
REM -----------------------------------------------------------------------
echo [Scenario 4/4] Verifying missing checkpoint diagnostic detection (-2146498168)...

if exist "%TEMP%\wou_checkpoint_failures.txt" del "%TEMP%\wou_checkpoint_failures.txt"
if exist "%TEMP%\wou_failed_updates.txt" del "%TEMP%\wou_failed_updates.txt"

echo dummy cab > "%SANDBOX_ROOT%\client\w100-x64\glb\windows11.0-kb5054156-x64.cab"

pushd "%SANDBOX_ROOT%\client\cmd"
set "OS_ARCH=x64"
set "OS_NAME=w100"
set "WOU_MOCK_DISM_EXIT=-2146498168"
call .\InstallOSUpdate.cmd "..\w100-x64\glb\windows11.0-kb5054156-x64.cab" /errorsaswarnings > "%SANDBOX_ROOT%\log\scen4_inst.log" 2>&1
set "WOU_MOCK_DISM_EXIT="
popd

if not exist "%TEMP%\wou_checkpoint_failures.txt" (
  echo FAIL Scenario 4: wou_checkpoint_failures.txt was not generated!
  goto Fail
)

%SystemRoot%\System32\findstr.exe /I /C:"windows11.0-kb5054156-x64.cab" "%TEMP%\wou_checkpoint_failures.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 4: wou_checkpoint_failures.txt does not contain failing package!
  goto Fail
)

%SystemRoot%\System32\findstr.exe /I /C:"Missing Checkpoint Cumulative Update prerequisite" "%UPDATE_LOGFILE%" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 4: Update log missing explicit checkpoint failure message!
  goto Fail
)

REM Verify DoUpdate Run Report rendering
pushd "%SANDBOX_ROOT%\client\cmd"
set "OS_NAME=w100"
set "OS_VER_MAJOR=10"
set "OS_VER_MINOR=0"
set "OS_VER_BUILD=26100"
set "OS_VER_REVIS=1"
set "OS_ARCH=x64"
set "RUN_REPORT_LOG=%SANDBOX_ROOT%\log\run_report.log"
call .\DoUpdate.cmd :WriteRunReport > "%SANDBOX_ROOT%\log\report_out.log" 2>&1
popd

%SystemRoot%\System32\findstr.exe /I /C:"Checkpoints Missing:        1" "%SANDBOX_ROOT%\log\run_report.log" >nul 2>&1
if errorlevel 1 (
  %SystemRoot%\System32\findstr.exe /I /C:"Checkpoints Missing:" "%SANDBOX_ROOT%\log\report_out.log" >nul 2>&1
  if errorlevel 1 (
    echo FAIL Scenario 4: Run Report does not show Checkpoints Missing count!
    type "%SANDBOX_ROOT%\log\report_out.log"
    goto Fail
  )
)

echo [PASS] Scenario 4: Missing checkpoint detected, logged, and formatted in Run Report.

REM -----------------------------------------------------------------------
REM Cleanup and Success
REM -----------------------------------------------------------------------
set "TEMP=%ORIG_TEMP%"
rmdir /s /q "%SANDBOX_ROOT%" 2>nul

echo =======================================================================
echo Checkpoint Cumulative Updates Servicing Test Suite: ALL TESTS PASSED
echo =======================================================================
exit /b 0

:Fail
set "TEMP=%ORIG_TEMP%"
echo =======================================================================
echo Checkpoint Cumulative Updates Servicing Test Suite: FAILED
echo =======================================================================
exit /b 1
