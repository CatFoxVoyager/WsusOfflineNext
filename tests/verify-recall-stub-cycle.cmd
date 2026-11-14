@echo off
setlocal enabledelayedexpansion

REM =======================================================================
REM WSUS Offline Update - Recall Stub Cycle Test Suite (real caller, CMD)
REM File: tests\verify-recall-stub-cycle.cmd
REM
REM The dedicated real-caller battery for the upgrade-in-progress marker
REM short-circuit (Phase 35, RECALL-01; DEC-35-08): every case drives a
REM SANDBOX COPY of the REAL client\cmd\RecallStub.cmd - never a stand-in.
REM
REM Instrument contract:
REM   - The single scripted transform (:MakeSandboxStub): the terminal
REM     shutdown line becomes `echo SANDBOX-SHUTDOWN-MOCKED`; every other
REM     line passes through in order. The destructive branch can therefore
REM     never reboot or tear down the host (Pitfall 4, T-35-06).
REM   - Canary carriage (RecallUpdate.cmd writes relaunch.canary) and canary
REM     cleanup (CleanupRecall.cmd writes cleanup.canary) beside each copy.
REM     The REAL CleanupRecall.cmd of the repo is never invoked - it is
REM     never on the case PATH and never in the case cwd.
REM   - Marker seeding: the stub's probe is the VERBATIM shape
REM     %SystemRoot%\Temp\wou_upgrade_in_progress.txt. The battery points
REM     the stub process's SystemRoot at a per-case sandbox sysroot and
REM     seeds exactly there, with a pre-flight absence assert and per-case
REM     cleanup. (35-01 deviation from the DEC-35-08 letter: this host's
REM     sandbox lets cmd WRITE %SystemRoot%\Temp but its cmd instruments
REM     cannot SEE files there, so real-path seeding is unrunnable; the
REM     real-path proof across a real upgrade stays the Phase 37 VM lane.)
REM   - The battery NEVER runs from %SystemRoot%\Temp\WOURecall: the cwd
REM     stays this script's directory for the whole run.
REM   - bcdedit note (DEC-35-08): under the sandbox sysroot the
REM     `%SystemRoot%\System32\bcdedit.exe` guard resolves to the case
REM     sysroot, where no System32 exists - the destructive branch's
REM     bcdedit write is structurally unreachable, not merely mocked.
REM   - Fail-closed: any disagreeing assert prints a named FAIL and exits 1
REM     through :Cleanup. The pass sentinel is RECALL-STUB-CYCLE-PASS.
REM
REM Cases:
REM   C1 stay-out: marker seeded + canary carriage present -> the sandbox
REM      stub logs the stay-out Info literal, neither canary exists, exit 0
REM   C2 relaunch (negative control): marker absent + carriage present ->
REM      relaunch.canary exists - the guard discriminates on marker presence
REM   C3 marker-beats-missing-carriage: marker seeded + carriage ABSENT ->
REM      stay-out (the guard sits before the missing-carriage check):
REM      cleanup.canary absent, mock echo absent, exit 0
REM   C4 destructive path (mocked): marker absent + carriage ABSENT ->
REM      cleanup.canary EXISTS and SANDBOX-SHUTDOWN-MOCKED IS in the
REM      captured run output (terminal mocked; only the sandbox canary runs)
REM   C5 counter freeze (the RECALL-01 burn pin): wourecall.1 and both
REM      attempts files seeded with known bytes stay byte-identical across
REM      the C1 stay-out shape
REM   C6 repo integrity: the repo stub carries the guard literal exactly
REM      once and the shutdown motif exactly once; the sandbox copy carries
REM      the mock exactly once and the motif zero times
REM   C7 can-fail (recorded, replayable): a %TEMP% scratch copy of THIS
REM      battery with C1's expected Info literal flipped must exit non-zero
REM      with a named C1 red; the scratch is deleted afterwards
REM =======================================================================

if not defined REPO_ROOT (
  pushd "%~dp0.."
  REM delayed form: %CD% inside a block would expand at parse time,
  REM before pushd executes
  set "REPO_ROOT=!CD!"
  popd
)

echo =======================================================================
echo WSUS Offline Update - Recall Stub Cycle Test Suite (Windows CMD)
echo =======================================================================

set "STUB_SRC=%REPO_ROOT%\client\cmd\RecallStub.cmd"
set "BATTERY_ROOT=%TEMP%\wou_test_recallstub"
set "FIND_EXE=%SystemRoot%\System32\find.exe"
set "FC_EXE=%SystemRoot%\System32\fc.exe"

if not exist "%STUB_SRC%" (
  echo FAIL: pre-flight - the repo stub is missing at "%STUB_SRC%".
  exit /b 1
)
REM never auto-delete real recall state found standing - a named error, no run
if exist "%SystemRoot%\Temp\WOURecall" (
  echo ERROR: armed recall state exists at %SystemRoot%\Temp\WOURecall - restore the machine before running this battery ^(no auto-delete^).
  exit /b 1
)
if exist "%BATTERY_ROOT%" rmdir /s /q "%BATTERY_ROOT%"
mkdir "%BATTERY_ROOT%" 2>nul
if not exist "%BATTERY_ROOT%" (
  echo FAIL: pre-flight - could not create the battery root "%BATTERY_ROOT%".
  exit /b 1
)

REM -----------------------------------------------------------------------
REM C1: stay-out - marker seeded, canary carriage present
REM -----------------------------------------------------------------------
echo [Test 1/7] C1: standing marker keeps the real stub out...
call :NewCase 1
if exist "%CASE_SYSROOT%\Temp\wou_upgrade_in_progress.txt" (
  echo FAIL: C1 pre-flight - the sysroot marker already exists ^(never auto-deleted^).
  goto Fail
)
echo full,26200,1000>"%CASE_SYSROOT%\Temp\wou_upgrade_in_progress.txt"
if not exist "%CASE_SYSROOT%\Temp\wou_upgrade_in_progress.txt" (
  echo FAIL: C1 - the marker seed did not land.
  goto Fail
)
call :RunStub
if "!STUB_RC!" NEQ "0" (
  echo FAIL: C1 expected exit code 0, got !STUB_RC!.
  type "%CASE_OUT%"
  goto Fail
)
findstr /C:"Info: Upgrade in progress - automatic recall suppressed" "%CASE_LOG%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: C1 expected the stay-out Info literal in the sandbox log.
  type "%CASE_LOG%" 2>nul
  type "%CASE_OUT%"
  goto Fail
)
if exist "%CASE_DIR%\relaunch.canary" (
  echo FAIL: C1 expected NO relaunch while the marker stands.
  goto Fail
)
if exist "%CASE_DIR%\cleanup.canary" (
  echo FAIL: C1 expected NO cleanup while the marker stands.
  goto Fail
)
findstr /C:"SANDBOX-SHUTDOWN-MOCKED" "%CASE_OUT%" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: C1 reached the destructive branch behind a standing marker.
  type "%CASE_OUT%"
  goto Fail
)
call :CleanMarker
echo [PASS] C1: stay-out proven - Info literal logged, no canaries, exit 0.

REM -----------------------------------------------------------------------
REM C2: relaunch negative control - marker absent, carriage present
REM -----------------------------------------------------------------------
echo [Test 2/7] C2: marker absent - the relaunch canary fires...
call :NewCase 2
call :RunStub
if "!STUB_RC!" NEQ "0" (
  echo FAIL: C2 expected exit code 0, got !STUB_RC!.
  type "%CASE_OUT%"
  goto Fail
)
if not exist "%CASE_DIR%\relaunch.canary" (
  echo FAIL: C2 expected the relaunch canary ^(the guard discriminates on marker presence^).
  type "%CASE_OUT%"
  goto Fail
)
if exist "%CASE_DIR%\cleanup.canary" (
  echo FAIL: C2 - the carriage existed, the cleanup fallback must stay out.
  goto Fail
)
findstr /C:"SANDBOX-SHUTDOWN-MOCKED" "%CASE_OUT%" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: C2 reached the destructive branch with the carriage present.
  type "%CASE_OUT%"
  goto Fail
)
call :CleanMarker
echo [PASS] C2: the guard discriminates - relaunch fired with the marker absent.

REM -----------------------------------------------------------------------
REM C3: marker beats missing carriage (guard sits BEFORE the carriage check)
REM -----------------------------------------------------------------------
echo [Test 3/7] C3: standing marker beats a missing carriage...
call :NewCase 3
REM the carriage is deliberately absent in this case: the guard must still
REM stay out BEFORE the missing-carriage Cleanup fallback can fire
if exist "%CASE_DIR%\RecallUpdate.cmd" del "%CASE_DIR%\RecallUpdate.cmd" >nul 2>&1
echo full,26200,1000>"%CASE_SYSROOT%\Temp\wou_upgrade_in_progress.txt"
if not exist "%CASE_SYSROOT%\Temp\wou_upgrade_in_progress.txt" (
  echo FAIL: C3 - the marker seed did not land.
  goto Fail
)
call :RunStub
if "!STUB_RC!" NEQ "0" (
  echo FAIL: C3 expected exit code 0, got !STUB_RC!.
  type "%CASE_OUT%"
  goto Fail
)
if exist "%CASE_DIR%\cleanup.canary" (
  echo FAIL: C3 expected NO cleanup behind a standing marker ^(even with the carriage missing^).
  goto Fail
)
findstr /C:"SANDBOX-SHUTDOWN-MOCKED" "%CASE_OUT%" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: C3 reached the destructive branch behind a standing marker.
  type "%CASE_OUT%"
  goto Fail
)
findstr /C:"Info: Upgrade in progress - automatic recall suppressed" "%CASE_LOG%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: C3 expected the stay-out Info literal in the sandbox log.
  type "%CASE_LOG%" 2>nul
  type "%CASE_OUT%"
  goto Fail
)
call :CleanMarker
echo [PASS] C3: the guard precedes the missing-carriage check - stay-out held.

REM -----------------------------------------------------------------------
REM C4: destructive path behind the mock (marker absent + carriage ABSENT)
REM -----------------------------------------------------------------------
echo [Test 4/7] C4: marker-absent missing-carriage machine reaches the mocked destructive branch...
call :NewCase 4
if exist "%CASE_DIR%\RecallUpdate.cmd" del "%CASE_DIR%\RecallUpdate.cmd" >nul 2>&1
call :RunStub
if "!STUB_RC!" NEQ "0" (
  echo FAIL: C4 expected exit code 0, got !STUB_RC!.
  type "%CASE_OUT%"
  goto Fail
)
if not exist "%CASE_DIR%\cleanup.canary" (
  echo FAIL: C4 expected the cleanup canary ^(the destructive branch taken^).
  type "%CASE_OUT%"
  goto Fail
)
findstr /C:"SANDBOX-SHUTDOWN-MOCKED" "%CASE_OUT%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: C4 expected the terminal shutdown mock in the captured run output.
  type "%CASE_OUT%"
  goto Fail
)
if exist "%CASE_DIR%\relaunch.canary" (
  echo FAIL: C4 - the carriage was absent, no relaunch canary may exist.
  goto Fail
)
call :CleanMarker
echo [PASS] C4: destructive branch taken behind the mock - cleanup canary, no reboot.

REM -----------------------------------------------------------------------
REM C5: counter freeze - the stay-out burns nothing (the RECALL-01 burn pin)
REM -----------------------------------------------------------------------
echo [Test 5/7] C5: counter freeze - wourecall.N and attempts stay byte-identical...
call :NewCase 5
mkdir "%CASE_SYSROOT%\Temp\WOURecall" 2>nul
echo counter-one-seed>"%CASE_SYSROOT%\Temp\WOURecall\wourecall.1"
echo 4,1000,26100,full>"%CASE_SYSROOT%\Temp\wou_fullupgrade_attempts.txt"
echo 2,5074,26100,ekb>"%CASE_SYSROOT%\Temp\wou_buildupgrade_attempts.txt"
copy /y "%CASE_SYSROOT%\Temp\WOURecall\wourecall.1" "%CASE_DIR%\wourecall.1.seedbak" >nul 2>&1
copy /y "%CASE_SYSROOT%\Temp\wou_fullupgrade_attempts.txt" "%CASE_DIR%\fu.seedbak" >nul 2>&1
copy /y "%CASE_SYSROOT%\Temp\wou_buildupgrade_attempts.txt" "%CASE_DIR%\ekb.seedbak" >nul 2>&1
echo full,26200,1000>"%CASE_SYSROOT%\Temp\wou_upgrade_in_progress.txt"
call :RunStub
if "!STUB_RC!" NEQ "0" (
  echo FAIL: C5 expected exit code 0, got !STUB_RC!.
  type "%CASE_OUT%"
  goto Fail
)
"%FC_EXE%" /b "%CASE_SYSROOT%\Temp\WOURecall\wourecall.1" "%CASE_DIR%\wourecall.1.seedbak" >nul 2>&1
if errorlevel 1 (
  echo FAIL: C5 - the wourecall.1 rotation counter was burned by the stay-out.
  goto Fail
)
"%FC_EXE%" /b "%CASE_SYSROOT%\Temp\wou_fullupgrade_attempts.txt" "%CASE_DIR%\fu.seedbak" >nul 2>&1
if errorlevel 1 (
  echo FAIL: C5 - the full-FU attempts file changed across the stay-out.
  goto Fail
)
"%FC_EXE%" /b "%CASE_SYSROOT%\Temp\wou_buildupgrade_attempts.txt" "%CASE_DIR%\ekb.seedbak" >nul 2>&1
if errorlevel 1 (
  echo FAIL: C5 - the EKB attempts file changed across the stay-out.
  goto Fail
)
findstr /C:"Info: Upgrade in progress - automatic recall suppressed" "%CASE_LOG%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: C5 expected the stay-out shape ^(Info literal^) in the sandbox log.
  type "%CASE_LOG%" 2>nul
  goto Fail
)
call :CleanMarker
echo [PASS] C5: wourecall.1 and both attempts files byte-identical across the stay-out.

REM -----------------------------------------------------------------------
REM C6: repo integrity - the repo stub intact, the sandbox copy transformed
REM -----------------------------------------------------------------------
echo [Test 6/7] C6: repo stub integrity vs sandbox transform...
set "C6_GUARD="
for /f %%a in ('findstr /C:"Upgrade in progress - automatic recall suppressed" "%STUB_SRC%" ^| "%FIND_EXE%" /c /v ""') do set "C6_GUARD=%%a"
if not "!C6_GUARD!"=="1" (
  echo FAIL: C6 - the repo stub expected the guard literal exactly once, got !C6_GUARD!.
  goto Fail
)
set "C6_MOTIF="
for /f %%a in ('findstr /C:"shutdown.exe /r /f /t 1" "%STUB_SRC%" ^| "%FIND_EXE%" /c /v ""') do set "C6_MOTIF=%%a"
if not "!C6_MOTIF!"=="1" (
  echo FAIL: C6 - the repo stub expected the shutdown motif exactly once, got !C6_MOTIF!.
  goto Fail
)
set "C6_MOCK="
for /f %%a in ('findstr /C:"SANDBOX-SHUTDOWN-MOCKED" "%CASE_DIR%\RecallStub.cmd" ^| "%FIND_EXE%" /c /v ""') do set "C6_MOCK=%%a"
if not "!C6_MOCK!"=="1" (
  echo FAIL: C6 - the sandbox copy expected the shutdown mock exactly once, got !C6_MOCK!.
  goto Fail
)
findstr /C:"shutdown.exe /r /f /t 1" "%CASE_DIR%\RecallStub.cmd" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: C6 - the sandbox copy still carries the real shutdown motif.
  goto Fail
)
echo [PASS] C6: repo stub carries guard+motif once each; sandbox copy carries the mock only.

REM -----------------------------------------------------------------------
REM C7: can-fail (recorded, replayable) - a flipped expectation must go red
REM -----------------------------------------------------------------------
echo [Test 7/7] C7: can-fail - a flipped C1 expectation turns the battery red...
REM the scratch inherits REPO_ROOT (already defined), so the scratch's own
REM derivation guard is skipped and it targets the real repo stub.
REM The flip is a byte-exact VBScript Replace: this battery's own text
REM carries !delayed! sequences, and a CMD line-transform under delayed
REM expansion would corrupt them.
set "SCRATCH_BATTERY=%TEMP%\wou_recallstub_canfail_%RANDOM%.cmd"
copy /y "%~f0" "%SCRATCH_BATTERY%" >nul 2>&1
if not exist "%SCRATCH_BATTERY%" (
  echo FAIL: C7 - could not create the scratch battery copy.
  goto Fail
)
call :FlipLiteralVbs "%SCRATCH_BATTERY%" "Info: Upgrade in progress - automatic recall suppressed" "Info: WRONG-STRING-CANFAIL"
set "SAVED_SYSROOT=%SystemRoot%"
set "SAVED_PATH=%PATH%"
set "SAVED_LOG=%UPDATE_LOGFILE%"
set "SCRATCH_OUT=%TEMP%\wou_recallstub_canfail_%RANDOM%.log"
call "%SCRATCH_BATTERY%" >"%SCRATCH_OUT%" 2>&1
set "SCRATCH_RC=!errorlevel!"
set "SystemRoot=%SAVED_SYSROOT%"
set "PATH=%SAVED_PATH%"
set "UPDATE_LOGFILE=%SAVED_LOG%"
if "!SCRATCH_RC!"=="0" (
  echo FAIL: C7 - the flipped scratch battery exited 0; the battery cannot fail.
  type "%SCRATCH_OUT%"
  goto Fail
)
findstr /C:"FAIL: C1" "%SCRATCH_OUT%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: C7 - the red run did not name the flipped C1 assert.
  type "%SCRATCH_OUT%"
  goto Fail
)
del "%SCRATCH_BATTERY%" >nul 2>&1
del "%SCRATCH_OUT%" >nul 2>&1
del "%TEMP%\wou_flip_literal.vbs" >nul 2>&1
if exist "%SCRATCH_BATTERY%" (
  echo FAIL: C7 - the scratch battery copy could not be deleted.
  goto Fail
)
echo [PASS] C7: can-fail proven - flipped C1 expectation exits non-zero with a named red, scratch deleted.

REM -----------------------------------------------------------------------
REM All Passed
REM -----------------------------------------------------------------------
echo.
echo =======================================================================
echo SUCCESS: Recall stub cycle battery passed - C1-C7 over the real caller.
echo =======================================================================
echo RECALL-STUB-CYCLE-PASS
call :Cleanup
exit /b 0

:Fail
echo.
echo =======================================================================
echo FAILURE: Recall stub cycle test failed.
echo =======================================================================
call :Cleanup
exit /b 1

:NewCase
REM %1 = case number - a clean dir with the transformed stub, canaries, sysroot
set "CASE_NO=%~1"
set "CASE_DIR=%BATTERY_ROOT%\case%~1"
if exist "%CASE_DIR%" rmdir /s /q "%CASE_DIR%"
mkdir "%CASE_DIR%" 2>nul
mkdir "%CASE_DIR%\sysroot\Temp" 2>nul
if not exist "%CASE_DIR%\sysroot\Temp" (
  echo FAIL: case %~1 - could not create the case sysroot.
  goto Fail
)
call :MakeSandboxStub "%STUB_SRC%" "%CASE_DIR%\RecallStub.cmd"
if not exist "%CASE_DIR%\RecallStub.cmd" (
  echo FAIL: case %~1 - the sandbox stub copy was not created.
  goto Fail
)
(
  echo @echo off
  echo echo relaunched^>relaunch.canary
  echo exit /b 0
)>"%CASE_DIR%\RecallUpdate.cmd"
(
  echo @echo off
  echo echo cleaned^>cleanup.canary
  echo exit /b 0
)>"%CASE_DIR%\CleanupRecall.cmd"
set "CASE_SYSROOT=%CASE_DIR%\sysroot"
set "CASE_LOG=%CASE_DIR%\stub.log"
set "CASE_OUT=%CASE_DIR%\stub_out.txt"
goto :eof

:RunStub
REM Provision the case env and drive the sandbox copy of the REAL stub:
REM SystemRoot at the case sysroot (the verbatim probe shape resolves into
REM the sandbox), PATH carries the case dir (bare-name resolution skips the
REM cwd on hosts with NoDefaultCurrentDirectoryInExePath), the logfile is
REM sandbox-local. Restores everything after the run.
set "SAVED_SYSROOT=%SystemRoot%"
set "SAVED_PATH=%PATH%"
set "SAVED_LOG=%UPDATE_LOGFILE%"
set "SystemRoot=%CASE_SYSROOT%"
set "PATH=%CASE_DIR%;%PATH%"
set "UPDATE_LOGFILE=%CASE_LOG%"
if exist "%CASE_LOG%" del "%CASE_LOG%" >nul 2>&1
if exist "%CASE_DIR%\relaunch.canary" del "%CASE_DIR%\relaunch.canary" >nul 2>&1
if exist "%CASE_DIR%\cleanup.canary" del "%CASE_DIR%\cleanup.canary" >nul 2>&1
call "%CASE_DIR%\RecallStub.cmd" >"%CASE_OUT%" 2>&1
set "STUB_RC=!errorlevel!"
set "SystemRoot=%SAVED_SYSROOT%"
set "PATH=%SAVED_PATH%"
set "UPDATE_LOGFILE=%SAVED_LOG%"
goto :eof

:CleanMarker
REM per-case cleanup of the seed (the DEC-35-08 contract)
if exist "%CASE_SYSROOT%\Temp\wou_upgrade_in_progress.txt" del "%CASE_SYSROOT%\Temp\wou_upgrade_in_progress.txt" >nul 2>&1
goto :eof

:MakeSandboxStub
REM The single scripted transform (DEC-35-08): the terminal shutdown line
REM becomes the mock echo; every other line passes through in order.
REM Delayed-expansion echo preserves %-content, and the repo stub carries no
REM exclamation marks, so !LINE! never eats a literal. Empty lines are not
REM carried (semantically inert to a batch file).
set "SBS_MOTIF=shutdown.exe /r /f /t 1"
(for /f "usebackq delims=" %%L in (`type "%~1"`) do (
  set "SBS_LINE=%%L"
  set "SBS_OUT=!SBS_LINE!"
  if not "!SBS_LINE:%SBS_MOTIF%=!"=="!SBS_LINE!" set "SBS_OUT=echo SANDBOX-SHUTDOWN-MOCKED"
  echo(!SBS_OUT!
))>"%~2"
set "SBS_MOTIF="
set "SBS_LINE="
set "SBS_OUT="
goto :eof

:FlipLiteralVbs
REM %1 = target file, %2 = literal to replace, %3 = replacement - the C7
REM can-fail flip over the scratch copy (never over the real battery).
REM A VBScript Replace is byte-exact: this battery's own lines carry
REM !delayed! sequences that a CMD line-transform under delayed expansion
REM would silently corrupt (caught live in the first C7 run).
set "CFL_FILE=%~1"
set "CFL_VBS=%TEMP%\wou_flip_literal.vbs"
echo Dim fso, content>"%CFL_VBS%"
echo Set fso = CreateObject("Scripting.FileSystemObject")>>"%CFL_VBS%"
echo content = fso.OpenTextFile(WScript.Arguments(0)).ReadAll>>"%CFL_VBS%"
echo content = Replace(content, WScript.Arguments(1), WScript.Arguments(2))>>"%CFL_VBS%"
echo fso.OpenTextFile(WScript.Arguments(0), 2).Write content>>"%CFL_VBS%"
cscript //nologo "%CFL_VBS%" "%CFL_FILE%" "%~2" "%~3" >nul 2>&1
if not exist "%CFL_VBS%" (
  echo FAIL: the C7 flip script could not be written.
  goto Fail
)
set "CFL_FILE="
set "CFL_VBS="
goto :eof

:Cleanup
REM remove the whole battery root - the machine is left clean
if exist "%BATTERY_ROOT%" rmdir /s /q "%BATTERY_ROOT%" 2>nul
goto :eof
