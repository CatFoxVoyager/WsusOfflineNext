@echo off
setlocal enabledelayedexpansion

REM =======================================================================
REM WSUS Offline Update - Upgrade Contract Twin (Windows CMD)
REM File: tests\verify-upgrade-contracts.cmd
REM
REM Plan 31-04 CMD-side contract assertions (PATH-01/PATH-02/PATH-03):
REM   1. Frozen consent literals over the real sources: enginecontracts
REM      25/25 counts, the /upgradeos token, the INI template default,
REM      the engine refusal + acceptance literals + the WOU_UPGRADE_TARGET
REM      carriage, the mainform write-back absence comment, the host
REM      [OS Upgrades] section literals, the gitignored bash twin file.
REM   2. Battery invocation: the /upgradeos argv acceptance battery,
REM      the Phase-32 shield-filter sandbox battery and the bash contract
REM      twin (cross-tier parity) must all exit 0.
REM   3. Phase-32 chosen-target pins (section D, plan 32-01): the CMD
REM      os-upgrades reader + shield-feed filter literals, the host
REM      multi-EKB grammar marker, the 6-row hop census and the
REM      unmodified exemption echo lines.
REM
REM No DoUpdate sandbox of its own - the acceptance sandbox lives in
REM tests\verify-upgrade-argv.cmd, which is invoked, not duplicated.
REM Success sentinel: UPGRADE-CONTRACTS-CMD-PASS. Any miss prints FAIL
REM and exits 1.
REM =======================================================================

pushd "%~dp0.."
set "REPO_ROOT=%CD%"
popd

echo =======================================================================
echo WSUS Offline Update - Upgrade Contract Twin (Windows CMD)
echo =======================================================================

REM -----------------------------------------------------------------------
REM 1. Source assertions - frozen literals over the real files
REM -----------------------------------------------------------------------
set "CONTRACTS_PAS=%REPO_ROOT%\src-native\installer\enginecontracts.pas"
set "TEMPLATE_INI=%REPO_ROOT%\client\UpdateInstaller.ini"
set "ENGINE_CMD=%REPO_ROOT%\client\cmd\DoUpdate.cmd"
set "MAINFORM_PAS=%REPO_ROOT%\src-native\installer\mainform.pas"
set "HOST_CS=%REPO_ROOT%\src-modern\generator\host\Program.cs"
set "GITIGNORE=%REPO_ROOT%\.gitignore"

if not exist "%CONTRACTS_PAS%" (
  echo FAIL: missing enginecontracts.pas at "%CONTRACTS_PAS%"
  goto Fail
)

findstr /C:"ENG_SWITCH_COUNT = 25" "%CONTRACTS_PAS%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: enginecontracts.pas is missing the frozen ENG_SWITCH_COUNT = 25 literal
  goto Fail
)
echo [PASS] enginecontracts.pas: ENG_SWITCH_COUNT = 25

findstr /C:"ENG_INI_DEFAULT_COUNT = 25" "%CONTRACTS_PAS%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: enginecontracts.pas is missing the frozen ENG_INI_DEFAULT_COUNT = 25 literal
  goto Fail
)
echo [PASS] enginecontracts.pas: ENG_INI_DEFAULT_COUNT = 25

if not exist "%TEMPLATE_INI%" (
  echo FAIL: missing UpdateInstaller.ini at "%TEMPLATE_INI%"
  goto Fail
)
findstr /C:"upgradeos=Disabled" "%TEMPLATE_INI%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: UpdateInstaller.ini template is missing the upgradeos=Disabled default
  goto Fail
)
echo [PASS] UpdateInstaller.ini: upgradeos=Disabled template default

if not exist "%ENGINE_CMD%" (
  echo FAIL: missing DoUpdate.cmd at "%ENGINE_CMD%"
  goto Fail
)
findstr /C:"ERROR: /upgradeos target must be a build number" "%ENGINE_CMD%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: DoUpdate.cmd is missing the loud refusal literal
  goto Fail
)
echo [PASS] DoUpdate.cmd: refusal literal pinned

findstr /C:"Info: Upgrade target build" "%ENGINE_CMD%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: DoUpdate.cmd is missing the acceptance literal
  goto Fail
)
echo [PASS] DoUpdate.cmd: acceptance literal pinned

findstr /C:"%%WOU_UPGRADE_TARGET%%" "%ENGINE_CMD%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: DoUpdate.cmd is missing the WOU_UPGRADE_TARGET carriage variable
  goto Fail
)
echo [PASS] DoUpdate.cmd: WOU_UPGRADE_TARGET carriage pinned

if not exist "%MAINFORM_PAS%" (
  echo FAIL: missing mainform.pas at "%MAINFORM_PAS%"
  goto Fail
)
findstr /C:"SECOND never-written key" "%MAINFORM_PAS%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: mainform.pas is missing the SECOND never-written key comment - write-back absence undocumented
  goto Fail
)
echo [PASS] mainform.pas: SECOND never-written key comment pinned

if not exist "%HOST_CS%" (
  echo FAIL: missing Program.cs at "%HOST_CS%"
  goto Fail
)
findstr /C:"[OS Upgrades]" "%HOST_CS%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: Program.cs is missing the [OS Upgrades] section literal
  goto Fail
)
echo [PASS] Program.cs: [OS Upgrades] section pinned

findstr /C:"os-upgrades.ini" "%HOST_CS%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: Program.cs is missing the flat bash twin file name
  goto Fail
)
echo [PASS] Program.cs: os-upgrades.ini flat twin pinned

findstr /C:"sh/os-upgrades.ini" "%GITIGNORE%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: .gitignore is missing the sh/os-upgrades.ini twin line
  goto Fail
)
echo [PASS] .gitignore: sh/os-upgrades.ini excluded

REM -----------------------------------------------------------------------
REM 3. Phase-32 chosen-target pins (section D, plan 32-01): CMD reader,
REM    feed filter, and host multi-EKB grammar literals fail-closed.
REM    Full path on find.exe: this twin is launched from POSIX-spawned
REM    cmd.exe sessions (MSYS PATH), where plain `find` resolves to GNU
REM    find and turns census walks into whole-drive scans.
REM -----------------------------------------------------------------------
if not exist "%REPO_ROOT%\cmd\DownloadUpdates.cmd" (
  echo FAIL: missing DownloadUpdates.cmd at "%REPO_ROOT%\cmd\DownloadUpdates.cmd"
  goto Fail
)
set "PIPELINE_CMD=%REPO_ROOT%\cmd\DownloadUpdates.cmd"

findstr /C:"TMP_UPG_TARGETS" "%PIPELINE_CMD%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: DownloadUpdates.cmd is missing the os-upgrades reader literal TMP_UPG_TARGETS
  goto Fail
)
echo [PASS] DownloadUpdates.cmd: TMP_UPG_TARGETS reader literal pinned

set PIPELINE_TARGETS_COUNT=0
for /F %%c in ('%SystemRoot%\System32\findstr.exe /C:"TMP_UPG_TARGETS" "%PIPELINE_CMD%" ^| %SystemRoot%\System32\find.exe /c /v ""') do set PIPELINE_TARGETS_COUNT=%%c
if %PIPELINE_TARGETS_COUNT% LSS 6 (
  echo FAIL: DownloadUpdates.cmd carries only %PIPELINE_TARGETS_COUNT% TMP_UPG_TARGETS sites ^(reader + both loop guards expect 6 or more^)
  goto Fail
)
echo [PASS] DownloadUpdates.cmd: TMP_UPG_TARGETS site count = %PIPELINE_TARGETS_COUNT% (expected 6 or more)

findstr /C:"TMP_UPG_SEL_BAD" "%PIPELINE_CMD%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: DownloadUpdates.cmd is missing the all-or-nothing bad flag TMP_UPG_SEL_BAD
  goto Fail
)
echo [PASS] DownloadUpdates.cmd: TMP_UPG_SEL_BAD bad flag pinned

findstr /C:"^[0-9][0-9]*_[A-Za-z0-9][A-Za-z0-9]*=on$" "%PIPELINE_CMD%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: DownloadUpdates.cmd is missing the frozen selection grammar literal

  goto Fail
)
echo [PASS] DownloadUpdates.cmd: selection grammar literal pinned

set READER_LINE=
set STEP5_LINE=
for /F "delims=: tokens=1" %%a in ('%SystemRoot%\System32\findstr.exe /N /B /C:"set TMP_UPG_TARGETS=" "%PIPELINE_CMD%"') do if not defined READER_LINE set "READER_LINE=%%a"
for /F "delims=: tokens=1" %%a in ('%SystemRoot%\System32\findstr.exe /N /B /C:"rem *** Step 5" "%PIPELINE_CMD%"') do if not defined STEP5_LINE set "STEP5_LINE=%%a"
if not defined READER_LINE (
  echo FAIL: DownloadUpdates.cmd reader block start line not found
  goto Fail
)
if not defined STEP5_LINE (
  echo FAIL: DownloadUpdates.cmd Step 5 header line not found
  goto Fail
)
if !READER_LINE! GEQ !STEP5_LINE! (
  echo FAIL: the os-upgrades reader ^(line !READER_LINE!^) must sit BEFORE the Step 5 header ^(line !STEP5_LINE!^) - DEC-32-04 placement
  goto Fail
)
echo [PASS] DownloadUpdates.cmd: reader at line !READER_LINE! precedes Step 5 at line !STEP5_LINE!

set PIPELINE_ECHO_COUNT=0
for /F %%c in ('%SystemRoot%\System32\findstr.exe /C:"echo windows10.0-%%%%c>>" "%PIPELINE_CMD%" ^| %SystemRoot%\System32\find.exe /c /v ""') do set PIPELINE_ECHO_COUNT=%%c
if %PIPELINE_ECHO_COUNT% LSS 4 (
  echo FAIL: DownloadUpdates.cmd carries only %PIPELINE_ECHO_COUNT% unmodified echo windows10.0-%%%%c>> exemption lines ^(4 expected across both feed loops^)
  goto Fail
)
echo [PASS] DownloadUpdates.cmd: exemption echo lines unmodified (count = %PIPELINE_ECHO_COUNT%)

set "HOP_FILE=%REPO_ROOT%\client\static\StaticUpdateIds-BuildUpgrades.txt"
set HOP_ROWS=0
for /F %%c in ('type "%HOP_FILE%" ^| %SystemRoot%\System32\find.exe /c /v ""') do set HOP_ROWS=%%c
if not "%HOP_ROWS%"=="6" (
  echo FAIL: hop census drifted - StaticUpdateIds-BuildUpgrades.txt carries %HOP_ROWS% rows, the frozen contract is 6 ^(T-32-02^)
  goto Fail
)
echo [PASS] StaticUpdateIds-BuildUpgrades.txt: hop census = 6 rows

findstr /C:"multi-EKB grammar (DEC-32-02)" "%HOST_CS%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: Program.cs is missing the multi-EKB grammar ^(DEC-32-02^) marker comment
  goto Fail
)
echo [PASS] Program.cs: multi-EKB grammar (DEC-32-02) marker pinned

findstr /C:"File.WriteAllLines(upgradeFlat" "%HOST_CS%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: Program.cs is missing the flat-twin File.WriteAllLines^(upgradeFlat call - the twin must write the full N-line list
  goto Fail
)
echo [PASS] Program.cs: flat-twin N-line write pinned

REM -----------------------------------------------------------------------
REM 2. Battery invocation - argv acceptance + bash contract twin
REM -----------------------------------------------------------------------
echo [RUN ] invoking tests\verify-upgrade-argv.cmd ...
call "%REPO_ROOT%\tests\verify-upgrade-argv.cmd"
if errorlevel 1 (
  echo FAIL: the /upgradeos argv acceptance battery did not exit 0
  goto Fail
)
echo [PASS] argv acceptance battery exit 0

echo [RUN ] invoking tests\verify-shield-filter.cmd ...
call "%REPO_ROOT%\tests\verify-shield-filter.cmd"
if errorlevel 1 (
  echo FAIL: the shield-filter sandbox battery did not exit 0 - the CMD chosen-target vertical slice is broken
  goto Fail
)
echo [PASS] shield-filter battery exit 0

REM Resolve a bash interpreter: bare PATH first, Git for Windows fallback
set "BASH_EXE=bash"
where bash >nul 2>&1
if errorlevel 1 (
  if exist "%ProgramFiles%\Git\bin\bash.exe" (
    set "BASH_EXE=%ProgramFiles%\Git\bin\bash.exe"
  )
)
set "BASH_SCRIPT=%REPO_ROOT:\=/%\sh\tests\verify-upgrade-contracts.bash"
echo [RUN ] invoking the bash contract twin via "%BASH_EXE%" ...
"%BASH_EXE%" "%BASH_SCRIPT%"
if errorlevel 1 (
  echo FAIL: the bash contract twin did not exit 0 - cross-tier parity broken
  goto Fail
)
echo [PASS] bash contract twin exit 0 - cross-tier parity holds

REM -----------------------------------------------------------------------
REM All Passed
REM -----------------------------------------------------------------------
echo.
echo =======================================================================
echo UPGRADE-CONTRACTS-CMD-PASS: all source assertions and both batteries green.
echo =======================================================================
exit /b 0

:Fail
echo.
echo =======================================================================
echo FAILURE: Upgrade contract twin failed.
echo =======================================================================
exit /b 1
