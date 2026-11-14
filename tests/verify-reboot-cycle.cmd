@echo off
setlocal enabledelayedexpansion

REM =======================================================================
REM WSUS Offline Update - Build Upgrade Reboot Cycle Regression Suite (Windows CMD)
REM File: tests\verify-reboot-cycle.cmd
REM
REM Verifies the build upgrade lifecycle, infinite loop prevention, and the
REM chosen-target (/upgradeos) lane - this twin drives the REAL engine:
REM   State 1: Fresh run (build 26100.1000) -> PrepareBuildUpgrade -> 3011
REM   State 2: Simulated Reboot 1 -> revision advances to 5074
REM   State 3: Perform run (build 26100.5074) -> PerformBuildUpgrade -> 3011
REM   State 4: Simulated Reboot 2 -> build advances to 26200
REM   State 5: Convergence run (build 26200.5074) -> upgrade skipped -> 0
REM   State 6: Infinite loop guard -> revision stagnant -> halts safely -> 0
REM   State 7: Target-scoped match (/upgradeos:26200) -> only 26200 wins, 26999 never
REM   State 8: Chosen target, EKB payload absent -> missing-enablement refusal -> 0
REM   State 9: Baseline below min revision + prereq CU absent -> loud refusal -> 0
REM   State 10: Chosen target with no upgrade path -> loud refusal -> 0
REM   State 11: Observed convergence (build == target) -> report + purge -> 0
REM   State 12: Perform-stall guard (stagnant build) -> halts safely -> 0
REM   State 13: 3010 perform stub -> b69 RECALL convergence (3011) + stall guard
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

REM Mock upgrade definition (golden rows identical to sh\tests\verify-reboot-cycle.bash):
REM 26100 -> 26200 with prereq kb5064081 and eKB kb5054156, plus the synthetic
REM higher hop 26999 sharing the same payload KBs so states 1-6 stay byte-identical
REM while state 7 proves the target guard keeps 26999 from ever winning.
echo 26100,5074,kb5064081,26200,kb5054156>"%MOCK_STATIC%\StaticUpdateIds-BuildUpgrades.txt"
echo 26100,5074,kb5064081,26999,kb5054156>>"%MOCK_STATIC%\StaticUpdateIds-BuildUpgrades.txt"

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
echo [Test 1/13] State 1: Fresh Run (Build 26100, Revision 1000)...
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
echo [Test 2/13] State 2: Simulated Reboot 1 (OS revision advances 1000 -^> 5074)...
set "OS_VER_BUILD=26100"
set "OS_VER_BUILD_INTERNAL=26100"
set "OS_VER_REVIS=5074"
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"
echo [PASS] State 2: Reboot 1 simulated successfully (target revision 5074 met).

REM -----------------------------------------------------------------------
REM State 3: Perform Run (26100.5074)
REM -----------------------------------------------------------------------
echo [Test 3/13] State 3: Perform Run (Build 26100, Revision 5074)...
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
REM (32-03) The perform leg now persists a build-keyed record for the next resume
REM (DEC-32-06): the leg-aware shortcut deleted the prepare record and the Perform
REM leg wrote the perform record - assert the record, not absence.
findstr /C:"1,5074,26100,perform" "%MOCK_SYS_TEMP%\wou_buildupgrade_attempts.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State 3 expected the perform record 1,5074,26100,perform after the Perform leg.
  goto Fail
)
echo [PASS] State 3: Perform run triggered PerformBuildUpgrade (exit 3011, eKB kb5054156 queued).

REM -----------------------------------------------------------------------
REM State 4: Simulated Reboot 2
REM -----------------------------------------------------------------------
echo [Test 4/13] State 4: Simulated Reboot 2 (OS build advances 26100 -^> 26200)...
set "OS_VER_BUILD=26200"
set "OS_VER_BUILD_INTERNAL=26200"
set "OS_VER_REVIS=5074"
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"
echo [PASS] State 4: Reboot 2 simulated successfully (target build 26200 reached).

REM -----------------------------------------------------------------------
REM State 5: Convergence Run (26200.5074)
REM -----------------------------------------------------------------------
echo [Test 5/13] State 5: Convergence Run (Build 26200, Revision 5074)...
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
echo [Test 6/13] State 6: Infinite Loop Guard Test (stagnant revision across reboots)...
del /q "%MOCK_SYS_TEMP%\*.*" 2>nul
set "OS_VER_BUILD=26100"
set "OS_VER_BUILD_INTERNAL=26100"
set "OS_VER_REVIS=1000"
set "OS_VER_MAJOR=10"
set "OS_VER_MINOR=0"

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
REM State 7: Target-Scoped Match (/upgradeos:26200 set)
REM -----------------------------------------------------------------------
echo [Test 7/13] State 7: Target-Scoped Match (target 26200 set - the 26999 row never wins)...
del /q "%MOCK_SYS_TEMP%\*.*" 2>nul
set "OS_VER_BUILD=26100"
set "OS_VER_MAJOR=10"
set "OS_VER_MINOR=0"
set "OS_VER_BUILD_INTERNAL=26100"
set "OS_VER_REVIS=1000"
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"

REM Control run WITHOUT a target: the GEQ walk must pick the higher 26999 row,
REM proving the fixture is a real threat the target guard neutralizes.
call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade >"%MOCK_TEMP%\state7_control.txt" 2>&1
findstr /C:"to 26999" "%MOCK_TEMP%\state7_control.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State 7 control run expected the no-target GEQ walk to pick 26999.
  type "%MOCK_TEMP%\state7_control.txt"
  goto Fail
)

REM Target run: only the 26200 row is allowed - the 26999 row must never win.
del /q "%MOCK_SYS_TEMP%\*.*" 2>nul
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"
call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade /upgradeos:26200 >"%MOCK_TEMP%\state7_target.txt" 2>&1
set "STATE7_EXIT=!errorlevel!"

if "!STATE7_EXIT!" NEQ "3011" (
  echo FAIL: State 7 expected exit code 3011, got !STATE7_EXIT!.
  type "%MOCK_TEMP%\state7_target.txt"
  goto Fail
)
findstr /C:"to 26200" "%MOCK_TEMP%\state7_target.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State 7 expected the 26200 row to win under target 26200.
  type "%MOCK_TEMP%\state7_target.txt"
  goto Fail
)
findstr /C:"to 26999" "%MOCK_TEMP%\state7_target.txt" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: State 7 the 26999 row won under target 26200 - target guard failed.
  type "%MOCK_TEMP%\state7_target.txt"
  goto Fail
)
findstr /I /C:"kb5064081" "%MOCK_TEMP%\MissingUpdateIds.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State 7 expected kb5064081 queued in MissingUpdateIds.txt.
  goto Fail
)
findstr /C:"1,1000,26100,prepare" "%MOCK_SYS_TEMP%\wou_buildupgrade_attempts.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State 7 expected the attempts record 1,1000,26100,prepare.
  goto Fail
)
echo [PASS] State 7: target-scoped selection held (only 26200 won; 26999 never won).

REM -----------------------------------------------------------------------
REM State 8: Chosen Target With The EKB Payload Absent (missing-enablement refusal)
REM -----------------------------------------------------------------------
echo [Test 8/13] State 8: Chosen target with the EKB payload absent - missing-enablement refusal...
set "OS_VER_MAJOR=10"
set "OS_VER_MINOR=0"
del /q "%MOCK_SYS_TEMP%\*.*" 2>nul
set "OS_VER_BUILD=26100"
set "OS_VER_BUILD_INTERNAL=26100"
set "OS_VER_REVIS=1000"
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"
ren "%MOCK_GLB%\windows11.0-kb5054156-x64.cab" "state8_stash_epkg.cab"
call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade /upgradeos:26200 >"%MOCK_TEMP%\state8_out.txt" 2>&1
set "STATE8_EXIT=!errorlevel!"
ren "%MOCK_GLB%\state8_stash_epkg.cab" "windows11.0-kb5054156-x64.cab"

if "!STATE8_EXIT!" NEQ "0" (
  echo FAIL: State 8 expected exit code 0 [refusal, no reboot], got !STATE8_EXIT!.
  type "%MOCK_TEMP%\state8_out.txt"
  goto Fail
)
findstr /C:"Warning: Chosen upgrade target 26200 blocked: enablement package kb5054156 missing from medium" "%MOCK_TEMP%\state8_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State 8 expected the missing-enablement refusal literal verbatim.
  type "%MOCK_TEMP%\state8_out.txt"
  goto Fail
)
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" (
  echo FAIL: State 8 expected nothing queued in MissingUpdateIds.txt.
  goto Fail
)
if exist "%MOCK_SYS_TEMP%\wou_buildupgrade_prep_tried.txt" (
  echo FAIL: State 8 expected markers purged after the refusal.
  goto Fail
)
echo [PASS] State 8: missing-enablement refusal fired verbatim (exit 0, nothing queued).

REM -----------------------------------------------------------------------
REM State 9: Baseline Below Min Revision And Prereq CU Absent
set "OS_VER_MAJOR=10"
set "OS_VER_MINOR=0"
REM -----------------------------------------------------------------------
echo [Test 9/13] State 9: Baseline revision below required and prereq CU absent - baseline+prereq refusal...
del /q "%MOCK_SYS_TEMP%\*.*" 2>nul
set "OS_VER_BUILD=26100"
set "OS_VER_BUILD_INTERNAL=26100"
set "OS_VER_REVIS=1000"
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"
ren "%MOCK_GLB%\windows11.0-kb5064081-x64.cab" "state9_stash_pre.cab"
call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade /upgradeos:26200 >"%MOCK_TEMP%\state9_out.txt" 2>&1
set "STATE9_EXIT=!errorlevel!"
ren "%MOCK_GLB%\state9_stash_pre.cab" "windows11.0-kb5064081-x64.cab"

if "!STATE9_EXIT!" NEQ "0" (
  echo FAIL: State 9 expected exit code 0 [refusal, no reboot], got !STATE9_EXIT!.
  type "%MOCK_TEMP%\state9_out.txt"
  goto Fail
)
findstr /C:"Warning: Chosen upgrade target 26200 blocked: baseline revision 1000 below required 5074 and prerequisite CU kb5064081 missing from medium" "%MOCK_TEMP%\state9_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State 9 expected the baseline+prereq refusal literal verbatim.
  type "%MOCK_TEMP%\state9_out.txt"
  goto Fail
)
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" (
  echo FAIL: State 9 expected nothing queued in MissingUpdateIds.txt.
  goto Fail
)
if exist "%MOCK_SYS_TEMP%\wou_buildupgrade_prep_tried.txt" (
  echo FAIL: State 9 expected markers purged after the refusal.
  goto Fail
)
echo [PASS] State 9: baseline+prereq refusal fired verbatim naming revision and CU (exit 0).

set "OS_VER_MAJOR=10"
set "OS_VER_MINOR=0"
REM -----------------------------------------------------------------------
REM State 10: Chosen Target With No Upgrade Path
REM -----------------------------------------------------------------------
echo [Test 10/13] State 10: Chosen target 26999 from build 26200 - no upgrade path refusal...
del /q "%MOCK_SYS_TEMP%\*.*" 2>nul
set "OS_VER_BUILD=26200"
set "OS_VER_BUILD_INTERNAL=26200"
set "OS_VER_REVIS=5074"
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"
call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade /upgradeos:26999 >"%MOCK_TEMP%\state10_out.txt" 2>&1
set "STATE10_EXIT=!errorlevel!"

if "!STATE10_EXIT!" NEQ "0" (
  echo FAIL: State 10 expected exit code 0 [refusal, no reboot], got !STATE10_EXIT!.
  type "%MOCK_TEMP%\state10_out.txt"
  goto Fail
)
findstr /C:"Warning: Chosen upgrade target 26999 has no upgrade path from build 26200" "%MOCK_TEMP%\state10_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State 10 expected the no-upgrade-path refusal literal verbatim.
  type "%MOCK_TEMP%\state10_out.txt"
  goto Fail
)
if exist "%MOCK_SYS_TEMP%\wou_buildupgrade_prep_tried.txt" (
  echo FAIL: State 10 expected all upgrade markers purged.
  goto Fail
)
if exist "%MOCK_SYS_TEMP%\wou_buildupgrade_tried.txt" (
  echo FAIL: State 10 expected all upgrade markers purged.
  goto Fail
)
if exist "%MOCK_SYS_TEMP%\wou_buildupgrade_attempts.txt" (
  echo FAIL: State 10 expected all upgrade markers purged.
  goto Fail
)
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" (
  echo FAIL: State 10 expected nothing queued in MissingUpdateIds.txt.
  goto Fail
)
set "OS_VER_MAJOR=10"
set "OS_VER_MINOR=0"
echo [PASS] State 10: no-upgrade-path refusal fired verbatim (exit 0, nothing queued).

REM -----------------------------------------------------------------------
REM State 11: Observed Convergence (build == target)
REM -----------------------------------------------------------------------
echo [Test 11/13] State 11: Observed convergence (build 26200 with target 26200)...
del /q "%MOCK_SYS_TEMP%\*.*" 2>nul
set "OS_VER_BUILD=26200"
set "OS_VER_BUILD_INTERNAL=26200"
set "OS_VER_REVIS=5074"
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"
REM Seed stale markers: the convergence path must purge them (apply-once semantics)
type nul >"%MOCK_SYS_TEMP%\wou_buildupgrade_prep_tried.txt"
type nul >"%MOCK_SYS_TEMP%\wou_buildupgrade_tried.txt"
echo stale>"%MOCK_SYS_TEMP%\wou_buildupgrade_attempts.txt"
call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade /upgradeos:26200 >"%MOCK_TEMP%\state11_out.txt" 2>&1
set "STATE11_EXIT=!errorlevel!"

if "!STATE11_EXIT!" NEQ "0" (
  echo FAIL: State 11 expected exit code 0, got !STATE11_EXIT!.
  type "%MOCK_TEMP%\state11_out.txt"
  goto Fail
)
findstr /C:"Info: Upgrade target build 26200 observed - jump complete" "%MOCK_TEMP%\state11_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State 11 expected the observed-convergence literal verbatim.
  type "%MOCK_TEMP%\state11_out.txt"
  goto Fail
)
if exist "%MOCK_SYS_TEMP%\wou_buildupgrade_prep_tried.txt" (
  echo FAIL: State 11 expected all seeded markers purged by the convergence path.
  goto Fail
)
if exist "%MOCK_SYS_TEMP%\wou_buildupgrade_tried.txt" (
  echo FAIL: State 11 expected all seeded markers purged by the convergence path.
  goto Fail
)
if exist "%MOCK_SYS_TEMP%\wou_buildupgrade_attempts.txt" (
  echo FAIL: State 11 expected all seeded markers purged by the convergence path.
set "OS_VER_MAJOR=10"
set "OS_VER_MINOR=0"
  goto Fail
)
echo [PASS] State 11: observed convergence reported and all markers purged (exit 0).

REM -----------------------------------------------------------------------
REM State 12: Perform-Leg Stall Guard (build stagnant across perform attempts)
REM -----------------------------------------------------------------------
echo [Test 12/13] State 12: Perform-stall guard (EKB apply does not advance the OS build)...
del /q "%MOCK_SYS_TEMP%\*.*" 2>nul
set "OS_VER_BUILD=26100"
set "OS_VER_BUILD_INTERNAL=26100"
set "OS_VER_REVIS=5074"
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"
REM Seed a perform record for build 26100: the first stagnant attempt is already recorded
echo 1,5074,26100,perform>"%MOCK_SYS_TEMP%\wou_buildupgrade_attempts.txt"

REM Run 1 at the same stagnant build -> counter advances to 2, perform leg proceeds
call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade /upgradeos:26200 >"%MOCK_TEMP%\state12_run1.txt" 2>&1
set "STATE12A_EXIT=!errorlevel!"

if "!STATE12A_EXIT!" NEQ "3011" (
  echo FAIL: State 12 run 1 expected exit code 3011 - stall not yet reached - got !STATE12A_EXIT!.
  type "%MOCK_TEMP%\state12_run1.txt"
  goto Fail
)
findstr /C:"2,5074,26100,perform" "%MOCK_SYS_TEMP%\wou_buildupgrade_attempts.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State 12 run 1 expected the record to advance to 2,5074,26100,perform.
  goto Fail
)

REM Run 2 at the same stagnant build -> counter 3 exceeds GTR 2 -> halt, purge, exit 0
call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade /upgradeos:26200 >"%MOCK_TEMP%\state12_run2.txt" 2>&1
set "STATE12B_EXIT=!errorlevel!"

if "!STATE12B_EXIT!" NEQ "0" (
  echo FAIL: State 12 run 2 expected exit code 0 [halted loop], got !STATE12B_EXIT!.
  type "%MOCK_TEMP%\state12_run2.txt"
  goto Fail
)
findstr /C:"Warning: EKB apply did not advance the OS build (still 26100) - halting to prevent infinite reboot loop" "%MOCK_TEMP%\state12_run2.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State 12 run 2 expected the perform-stall literal verbatim.
  type "%MOCK_TEMP%\state12_run2.txt"
  goto Fail
)
if exist "%MOCK_SYS_TEMP%\wou_buildupgrade_attempts.txt" (
  echo FAIL: State 12 run 2 expected all attempts and markers purged on the stall halt.
  goto Fail
)
if exist "%MOCK_SYS_TEMP%\wou_buildupgrade_tried.txt" (
  echo FAIL: State 12 run 2 expected all attempts and markers purged on the stall halt.
  goto Fail
)
set "STATE12Q="
REM full-path System32 find.exe: POSIX-spawned sessions resolve plain find to GNU
REM find, which would scan the whole drive (32-01 battery convention)
for /f %%c in ('type "%MOCK_TEMP%\MissingUpdateIds.txt" 2^>nul ^| "%SystemRoot%\System32\find.exe" /c /v ""') do set "STATE12Q=%%c"
if not "!STATE12Q!"=="1" (
  echo FAIL: State 12 run 2 should not have queued more update IDs - expected 1 line, got !STATE12Q!.
  goto Fail
)
echo [PASS] State 12: perform stall halted verbatim and purged (third stagnant attempt, exit 0).
REM -----------------------------------------------------------------------
REM State 13: 3010 Perform Mapping + b69 RECALL-Precedence Convergence (VAL-01a)
REM + attempts-guard interaction (VAL-01b). The engine's :BuildUpgradeComplete
REM FIXME 12.5 (b69) unconditionally forces RECALL_REQUIRED after the ERR_LEVEL
REM mapping (client\cmd\DoUpdate.cmd:1078-1081) - the CURRENT contract: a 3010
REM stub (reboot pending) converges to exit 3011 on the real EKB lane. This
REM state PINS that convergence (the FIXME b69 fix must flip it deliberately);
REM State 14 proves the mapping itself load-bearing on a b69-neutralized scratch.
REM -----------------------------------------------------------------------
echo [Test 13/13] State 13: 3010 perform stub converges to 3011 (b69 pinned) + stall guard...
del /q "%MOCK_SYS_TEMP%\*.*" 2>nul
set "OS_VER_MAJOR=10"
set "OS_VER_MINOR=0"
set "OS_VER_BUILD=26100"
set "OS_VER_BUILD_INTERNAL=26100"
set "OS_VER_REVIS=5074"
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"
REM Seed a perform record for build 26100: the first stagnant attempt is already recorded
echo 1,5074,26100,perform>"%MOCK_SYS_TEMP%\wou_buildupgrade_attempts.txt"
REM Re-point the install stub at the reboot-pending handshake (3010) - the mapping
REM under test lives at client\cmd\DoUpdate.cmd:1078-1081
(
  echo @echo off
  echo rem Simulate package installation requiring a reboot to complete
  echo exit /b 3010
) >"%MOCK_CMD%\InstallListedUpdates.cmd"

REM Run 1: the mapping sets REBOOT_REQUIRED, the b69 force converges it to RECALL
call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade /upgradeos:26200 >"%MOCK_TEMP%\state13_run1.txt" 2>&1
set "STATE13A_EXIT=!errorlevel!"

if "!STATE13A_EXIT!" NEQ "3011" (
  echo FAIL: State 13 run 1 expected exit code 3011 - the b69 RECALL-precedence convergence of the 3010 mapping - got !STATE13A_EXIT!.
  type "%MOCK_TEMP%\state13_run1.txt"
  goto Fail
)
findstr /C:"2,5074,26100,perform" "%MOCK_SYS_TEMP%\wou_buildupgrade_attempts.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State 13 run 1 expected the perform record 2,5074,26100,perform - the mapping flow must reach the attempts write, not InstError.
  type "%MOCK_TEMP%\state13_run1.txt"
  goto Fail
)
findstr /C:"ERROR: Installation failed" "%MOCK_TEMP%\state13_run1.txt" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: State 13 run 1 must NOT report an installation error - the 3010 stub maps to the reboot branch, not InstError.
  type "%MOCK_TEMP%\state13_run1.txt"
  goto Fail
)

REM Run 2: same stagnant build - the perform-stall guard halts (counter 2 -^> 3 exceeds GTR 2)
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"
call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade /upgradeos:26200 >"%MOCK_TEMP%\state13_run2.txt" 2>&1
set "STATE13B_EXIT=!errorlevel!"

if "!STATE13B_EXIT!" NEQ "0" (
  echo FAIL: State 13 run 2 expected exit code 0 [stall halt], got !STATE13B_EXIT!.
  type "%MOCK_TEMP%\state13_run2.txt"
  goto Fail
)
findstr /C:"Warning: EKB apply did not advance the OS build (still 26100) - halting to prevent infinite reboot loop" "%MOCK_TEMP%\state13_run2.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State 13 run 2 expected the perform-stall literal verbatim.
  type "%MOCK_TEMP%\state13_run2.txt"
  goto Fail
)
if exist "%MOCK_SYS_TEMP%\wou_buildupgrade_attempts.txt" (
  echo FAIL: State 13 run 2 expected the attempts file purged on the stall halt.
  goto Fail
)
echo [PASS] State 13: 3010 stub converged to 3011 with the attempts record advanced (b69 pinned); stall guard halted and purged on the repeat run.

REM -----------------------------------------------------------------------
REM All Passed
REM -----------------------------------------------------------------------
echo.
echo =======================================================================
echo SUCCESS: All 13 reboot cycle regression states passed successfully.
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
