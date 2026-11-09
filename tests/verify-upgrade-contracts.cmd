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
REM   2. Battery invocation: the /upgradeos argv acceptance battery and
REM      the bash contract twin (cross-tier parity) must both exit 0.
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
REM 2. Battery invocation - argv acceptance + bash contract twin
REM -----------------------------------------------------------------------
echo [RUN ] invoking tests\verify-upgrade-argv.cmd ...
call "%REPO_ROOT%\tests\verify-upgrade-argv.cmd"
if errorlevel 1 (
  echo FAIL: the /upgradeos argv acceptance battery did not exit 0
  goto Fail
)
echo [PASS] argv acceptance battery exit 0

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
