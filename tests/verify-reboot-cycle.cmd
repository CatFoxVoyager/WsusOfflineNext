@echo off
setlocal enabledelayedexpansion

REM =======================================================================
REM WSUS Offline Update - Build Upgrade Reboot Cycle Regression Suite (Windows CMD)
REM File: tests\verify-reboot-cycle.cmd
REM
REM Verifies the 6-state build upgrade lifecycle and infinite loop prevention:
REM   State 1: Fresh run (build 26100.1000) -> PrepareBuildUpgrade -> 3011
REM   State 2: Simulated Reboot 1 -> revision advances to 5074
REM   State 3: Perform run (build 26100.5074) -> PerformBuildUpgrade -> 3011
REM   State 4: Simulated Reboot 2 -> build advances to 26200
REM   State 5: Convergence run (build 26200.5074) -> upgrade skipped -> 0
REM   State 6: Infinite loop guard -> revision stagnant -> halts safely -> 0
REM =======================================================================

pushd "%~dp0.."
set "REPO_ROOT=%CD%"
popd

echo =======================================================================
echo WSUS Offline Update - Reboot Cycle Regression Test Suite (Windows CMD)
echo =======================================================================

REM Set up isolated test sandbox
set "SANDBOX_ROOT=%TEMP%\wou_test_reboot_%RANDOM%_%RANDOM%"
set "MOCK_CMD=%SANDBOX_ROOT%\cmd"
set "MOCK_STATIC=%SANDBOX_ROOT%\static"
set "MOCK_GLB=%SANDBOX_ROOT%\w100-x64\glb"
set "MOCK_TEMP=%SANDBOX_ROOT%\temp"
set "MOCK_SYS_TEMP=%SANDBOX_ROOT%\sysroot_temp"

mkdir "%MOCK_CMD%" 2>nul
mkdir "%MOCK_STATIC%" 2>nul
mkdir "%MOCK_GLB%" 2>nul
mkdir "%MOCK_TEMP%" 2>nul
mkdir "%MOCK_SYS_TEMP%" 2>nul

if not exist "%MOCK_SYS_TEMP%" (
  echo ERROR: Failed to create test sandbox at "%SANDBOX_ROOT%".
  exit /b 1
)

REM Populate mock environment
copy /y "%REPO_ROOT%\client\cmd\DoUpdate.cmd" "%MOCK_CMD%\DoUpdate.cmd" >nul 2>&1
if not exist "%MOCK_CMD%\DoUpdate.cmd" (
  echo ERROR: Failed to copy DoUpdate.cmd to test sandbox.
  goto Fail
)

REM Mock upgrade definition: 26100 -> 26200 with prereq kb5064081 and eKB kb5054156
echo 26100,5074,kb5064081,26200,kb5054156>"%MOCK_STATIC%\StaticUpdateIds-BuildUpgrades.txt"

REM Mock packages
type nul >"%MOCK_GLB%\windows11.0-kb5064081-x64.cab"
type nul >"%MOCK_GLB%\windows11.0-kb5054156-x64.cab"

REM Mock helper scripts
(
  echo @echo off
  echo exit /b 0
) >"%MOCK_CMD%\ListUpdatesToInstall.cmd"

(
  echo @echo off
  echo rem Simulate package installation requiring reboot
  echo exit /b 3011
) >"%MOCK_CMD%\InstallListedUpdates.cmd"

REM Base environment configuration
set "OS_NAME=w100"
set "OS_ARCH=x64"
set "TEMP=%MOCK_TEMP%"
set "TMP=%MOCK_TEMP%"
set "WOU_TEMP_DIR=%MOCK_SYS_TEMP%"
set "UPDATE_LOGFILE=%MOCK_TEMP%\wou_update.log"
set "PATH=%MOCK_CMD%;%PATH%"
set "VERIFY_MODE="
set "DISM_MODE="

REM -----------------------------------------------------------------------
REM State 1: Fresh Run (26100.1000)
REM -----------------------------------------------------------------------
echo [Test 1/6] State 1: Fresh Run (Build 26100, Revision 1000)...
set "OS_VER_BUILD=26100"
set "OS_VER_BUILD_INTERNAL=26100"
set "OS_VER_REVIS=1000"
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"

call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade >nul 2>&1
set "STATE1_EXIT=!errorlevel!"

if "!STATE1_EXIT!" NEQ "3011" (
  echo FAIL: State 1 expected exit code 3011, got !STATE1_EXIT!.
  goto Fail
)
if not exist "%MOCK_SYS_TEMP%\wou_buildupgrade_prep_tried.txt" (
  echo FAIL: State 1 expected wou_buildupgrade_prep_tried.txt to be created.
  goto Fail
)
findstr /I /C:"kb5064081" "%MOCK_TEMP%\MissingUpdateIds.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State 1 expected kb5064081 queued in MissingUpdateIds.txt.
  goto Fail
)
if not exist "%MOCK_SYS_TEMP%\wou_buildupgrade_attempts.txt" (
  echo FAIL: State 1 expected wou_buildupgrade_attempts.txt to be created.
  goto Fail
)
findstr /C:"1,1000" "%MOCK_SYS_TEMP%\wou_buildupgrade_attempts.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State 1 expected attempt count 1,1000 in attempts tracker.
  goto Fail
)
echo [PASS] State 1: Fresh run triggered PrepareBuildUpgrade (exit 3011, prereq kb5064081 queued).

REM -----------------------------------------------------------------------
REM State 2: Simulated Reboot 1
REM -----------------------------------------------------------------------
echo [Test 2/6] State 2: Simulated Reboot 1 (OS revision advances 1000 -^> 5074)...
set "OS_VER_BUILD=26100"
set "OS_VER_BUILD_INTERNAL=26100"
set "OS_VER_REVIS=5074"
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"
echo [PASS] State 2: Reboot 1 simulated successfully (target revision 5074 met).

REM -----------------------------------------------------------------------
REM State 3: Perform Run (26100.5074)
REM -----------------------------------------------------------------------
echo [Test 3/6] State 3: Perform Run (Build 26100, Revision 5074)...
call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade >nul 2>&1
set "STATE3_EXIT=!errorlevel!"

if "!STATE3_EXIT!" NEQ "3011" (
  echo FAIL: State 3 expected exit code 3011, got !STATE3_EXIT!.
  goto Fail
)
if not exist "%MOCK_SYS_TEMP%\wou_buildupgrade_tried.txt" (
  echo FAIL: State 3 expected wou_buildupgrade_tried.txt to be created.
  goto Fail
)
findstr /I /C:"kb5054156" "%MOCK_TEMP%\MissingUpdateIds.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State 3 expected kb5054156 queued in MissingUpdateIds.txt.
  goto Fail
)
if exist "%MOCK_SYS_TEMP%\wou_buildupgrade_attempts.txt" (
  echo FAIL: State 3 expected wou_buildupgrade_attempts.txt to be cleared on threshold met.
  goto Fail
)
echo [PASS] State 3: Perform run triggered PerformBuildUpgrade (exit 3011, eKB kb5054156 queued).

REM -----------------------------------------------------------------------
REM State 4: Simulated Reboot 2
REM -----------------------------------------------------------------------
echo [Test 4/6] State 4: Simulated Reboot 2 (OS build advances 26100 -^> 26200)...
set "OS_VER_BUILD=26200"
set "OS_VER_BUILD_INTERNAL=26200"
set "OS_VER_REVIS=5074"
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"
echo [PASS] State 4: Reboot 2 simulated successfully (target build 26200 reached).

REM -----------------------------------------------------------------------
REM State 5: Convergence Run (26200.5074)
REM -----------------------------------------------------------------------
echo [Test 5/6] State 5: Convergence Run (Build 26200, Revision 5074)...
call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade >nul 2>&1
set "STATE5_EXIT=!errorlevel!"

if "!STATE5_EXIT!" NEQ "0" (
  echo FAIL: State 5 expected exit code 0 [no further reboots], got !STATE5_EXIT!.
  goto Fail
)
if exist "%MOCK_SYS_TEMP%\wou_buildupgrade_prep_tried.txt" (
  echo FAIL: State 5 stale wou_buildupgrade_prep_tried.txt marker remained.
  goto Fail
)
if exist "%MOCK_SYS_TEMP%\wou_buildupgrade_tried.txt" (
  echo FAIL: State 5 stale wou_buildupgrade_tried.txt marker remained.
  goto Fail
)
if exist "%MOCK_SYS_TEMP%\wou_buildupgrade_attempts.txt" (
  echo FAIL: State 5 stale wou_buildupgrade_attempts.txt marker remained.
  goto Fail
)
echo [PASS] State 5: Build upgrade converged cleanly (exit 0, all markers purged).

REM -----------------------------------------------------------------------
REM State 6: Infinite Loop Prevention Guard Test
REM -----------------------------------------------------------------------
echo [Test 6/6] State 6: Infinite Loop Guard Test (stagnant revision across reboots)...
del /q "%MOCK_SYS_TEMP%\*.*" 2>nul
set "OS_VER_BUILD=26100"
set "OS_VER_BUILD_INTERNAL=26100"
set "OS_VER_REVIS=1000"

REM Attempt 1
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"
call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade >nul 2>&1
set "GUARD_EXIT1=!errorlevel!"
if "!GUARD_EXIT1!" NEQ "3011" (
  echo FAIL: State 6 attempt 1 expected exit code 3011, got !GUARD_EXIT1!.
  goto Fail
)
findstr /C:"1,1000" "%MOCK_SYS_TEMP%\wou_buildupgrade_attempts.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State 6 attempt 1 expected attempt counter 1,1000.
  goto Fail
)

REM Attempt 2: reboot without revision progress (revision stays 1000)
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"
call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade >nul 2>&1
set "GUARD_EXIT2=!errorlevel!"
if "!GUARD_EXIT2!" NEQ "3011" (
  echo FAIL: State 6 attempt 2 expected exit code 3011, got !GUARD_EXIT2!.
  goto Fail
)
findstr /C:"2,1000" "%MOCK_SYS_TEMP%\wou_buildupgrade_attempts.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State 6 attempt 2 expected attempt counter 2,1000.
  goto Fail
)

REM Attempt 3: reboot again without revision progress (revision stays 1000) -> Guard must trigger!
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"
call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade >"%MOCK_TEMP%\guard_out.txt" 2>&1
set "GUARD_EXIT3=!errorlevel!"

if "!GUARD_EXIT3!" NEQ "0" (
  echo FAIL: State 6 attempt 3 expected exit code 0 [halted loop], got !GUARD_EXIT3!.
  goto Fail
)
findstr /I /C:"prevent infinite reboot loop" "%MOCK_TEMP%\guard_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State 6 attempt 3 expected loop prevention warning in output.
  type "%MOCK_TEMP%\guard_out.txt"
  goto Fail
)
if exist "%MOCK_SYS_TEMP%\wou_buildupgrade_attempts.txt" (
  echo FAIL: State 6 attempt 3 expected wou_buildupgrade_attempts.txt to be removed on loop halt.
  goto Fail
)
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" (
  echo FAIL: State 6 attempt 3 should not have queued missing update IDs on halt.
  goto Fail
)
echo [PASS] State 6: Infinite loop guard triggered as expected (loop halted, exit 0).

REM -----------------------------------------------------------------------
REM All Passed
REM -----------------------------------------------------------------------
echo.
echo =======================================================================
echo SUCCESS: All 6 reboot cycle regression states passed successfully.
echo =======================================================================
call :Cleanup
exit /b 0

:Fail
echo.
echo =======================================================================
echo FAILURE: Reboot cycle regression test failed.
echo =======================================================================
call :Cleanup
exit /b 1

:Cleanup
if exist "%SANDBOX_ROOT%" (
  rmdir /s /q "%SANDBOX_ROOT%" 2>nul
)
goto :eof
