@echo off
setlocal enabledelayedexpansion

REM =======================================================================
REM WSUS Offline Update - /upgradeos argv Acceptance Battery (Windows CMD)
REM File: tests\verify-upgrade-argv.cmd
REM
REM Drives the REAL :EvalParams parse path of client\cmd\DoUpdate.cmd with
REM the engine's first value-carrying switch (/upgradeos:<build>, DEC-11):
REM   Case 1: /upgradeos:26200  -> accepted, Info literal logged, run ends 0
REM   Case 2: /upgradeos:26x00  -> refused loudly (non-digit), exit 1
REM   Case 3: /upgradeos:       -> refused loudly (empty value), exit 1
REM   Case 4: /upgradeos:26200:999 -> refused loudly (colon-truncated
REM           remainder), exit 1 - a second colon segment must not be
REM           silently dropped by the value split (review WR-02)
REM   Case 5: /upgradeos (bare token, no colon/value) -> refused loudly,
REM           exit 1 - the frozen table's own token spelling must not be
REM           silently ignored like an unknown arg (review IN-01)
REM The refusal happens during parse - before any install step. The sandbox
REM never reaches an install step: without ..\bin\IfAdmin.exe the engine
REM terminates deterministically right after the parse (accept case ends 0
REM through the error-path EoF), and a refusal exits 1 inside the parse.
REM =======================================================================

pushd "%~dp0.."
set "REPO_ROOT=%CD%"
popd

echo =======================================================================
echo WSUS Offline Update - /upgradeos argv Acceptance Battery (Windows CMD)
echo =======================================================================

REM Set up isolated test sandbox (recipe: tests\verify-reboot-cycle.cmd)
set "SANDBOX_ROOT=%TEMP%\wou_test_argv_%RANDOM%_%RANDOM%"
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

REM Copy the engine under test
copy /y "%REPO_ROOT%\client\cmd\DoUpdate.cmd" "%MOCK_CMD%\DoUpdate.cmd" >nul 2>&1
if not exist "%MOCK_CMD%\DoUpdate.cmd" (
  echo ERROR: Failed to copy DoUpdate.cmd to test sandbox.
  goto Fail
)

REM Mock helper scripts (never reached - the parse gates everything here)
(
  echo @echo off
  echo exit /b 0
) >"%MOCK_CMD%\ListUpdatesToInstall.cmd"

(
  echo @echo off
  echo exit /b 3011
) >"%MOCK_CMD%\InstallListedUpdates.cmd"

REM Base environment configuration
set "OS_NAME=w100"
set "OS_ARCH=x64"
set "OS_VER_BUILD=26100"
set "OS_VER_BUILD_INTERNAL=26100"
set "OS_VER_REVIS=5074"
set "TEMP=%MOCK_TEMP%"
set "TMP=%MOCK_TEMP%"
set "WOU_TEMP_DIR=%MOCK_SYS_TEMP%"
set "PATH=%MOCK_CMD%;%PATH%"

REM -----------------------------------------------------------------------
REM Case 1: valid digits - accepted, Info literal logged, run ends 0
REM -----------------------------------------------------------------------
echo [Test 1/5] Case 1: /upgradeos:26200 accepted...
set "UPDATE_LOGFILE=%MOCK_TEMP%\argv_case1.log"
call "%MOCK_CMD%\DoUpdate.cmd" /upgradeos:26200 /auditonly >nul 2>&1
set "CASE1_EXIT=!errorlevel!"

if "!CASE1_EXIT!" NEQ "0" (
  echo FAIL: Case 1 expected exit code 0 ^(parse accepted^), got !CASE1_EXIT!.
  goto Fail
)
findstr /C:"Info: Upgrade target build 26200 accepted" "%UPDATE_LOGFILE%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: Case 1 expected the acceptance literal in the engine log.
  goto Fail
)
findstr /C:"ERROR: /upgradeos target must be a build number" "%UPDATE_LOGFILE%" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: Case 1 must NOT log the refusal literal.
  goto Fail
)
echo [PASS] Case 1: target accepted, Info literal logged, exit 0.

REM -----------------------------------------------------------------------
REM Case 2: non-digit value - refused loudly, exit 1
REM -----------------------------------------------------------------------
echo [Test 2/5] Case 2: /upgradeos:26x00 refused...
set "UPDATE_LOGFILE=%MOCK_TEMP%\argv_case2.log"
call "%MOCK_CMD%\DoUpdate.cmd" /upgradeos:26x00 /auditonly >nul 2>&1
set "CASE2_EXIT=!errorlevel!"

if "!CASE2_EXIT!" NEQ "1" (
  echo FAIL: Case 2 expected exit code 1 ^(refusal^), got !CASE2_EXIT!.
  goto Fail
)
findstr /C:"ERROR: /upgradeos target must be a build number" "%UPDATE_LOGFILE%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: Case 2 expected the refusal literal in the engine log.
  goto Fail
)
findstr /C:"Info: Upgrade target build" "%UPDATE_LOGFILE%" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: Case 2 must NOT log an acceptance literal for an invalid value.
  goto Fail
)
echo [PASS] Case 2: non-digit value refused loudly (exit 1).

REM -----------------------------------------------------------------------
REM Case 3: empty value - refused loudly, exit 1
REM -----------------------------------------------------------------------
echo [Test 3/5] Case 3: /upgradeos: ^(empty^) refused...
set "UPDATE_LOGFILE=%MOCK_TEMP%\argv_case3.log"
call "%MOCK_CMD%\DoUpdate.cmd" /upgradeos: /auditonly >nul 2>&1
set "CASE3_EXIT=!errorlevel!"

if "!CASE3_EXIT!" NEQ "1" (
  echo FAIL: Case 3 expected exit code 1 ^(refusal^), got !CASE3_EXIT!.
  goto Fail
)
findstr /C:"ERROR: /upgradeos target must be a build number" "%UPDATE_LOGFILE%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: Case 3 expected the refusal literal in the engine log.
  goto Fail
)
findstr /C:"Info: Upgrade target build" "%UPDATE_LOGFILE%" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: Case 3 must NOT log an acceptance literal for an empty value.
  goto Fail
)
echo [PASS] Case 3: empty value refused loudly (exit 1).

REM -----------------------------------------------------------------------
REM Case 4: colon-truncated value - refused loudly, exit 1
REM (review WR-02: for /f "tokens=2 delims=:" silently drops everything
REM after the next colon; the remainder past /upgradeos: must equal the
REM tokenized value or the value is refused)
REM -----------------------------------------------------------------------
echo [Test 4/5] Case 4: /upgradeos:26200:999 refused...
set "UPDATE_LOGFILE=%MOCK_TEMP%\argv_case4.log"
call "%MOCK_CMD%\DoUpdate.cmd" /upgradeos:26200:999 /auditonly >nul 2>&1
set "CASE4_EXIT=!errorlevel!"

if "!CASE4_EXIT!" NEQ "1" (
  echo FAIL: Case 4 expected exit code 1 ^(colon-truncation refusal^), got !CASE4_EXIT!.
  goto Fail
)
findstr /C:"ERROR: /upgradeos target must be a build number" "%UPDATE_LOGFILE%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: Case 4 expected the refusal literal in the engine log.
  goto Fail
)
findstr /C:"Info: Upgrade target build" "%UPDATE_LOGFILE%" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: Case 4 must NOT log an acceptance literal for a truncated value.
  goto Fail
)
echo [PASS] Case 4: colon-truncated value refused loudly (exit 1).

REM -----------------------------------------------------------------------
REM Case 5: bare token (no colon/value) - refused loudly, exit 1
REM (review IN-01: /upgradeos is the frozen table's own token spelling;
REM the bare form must not fall through unknown-arg handling silently -
REM it routes to the same refusal literal as a bad value)
REM -----------------------------------------------------------------------
echo [Test 5/5] Case 5: /upgradeos ^(bare^) refused...
set "UPDATE_LOGFILE=%MOCK_TEMP%\argv_case5.log"
call "%MOCK_CMD%\DoUpdate.cmd" /upgradeos /auditonly >nul 2>&1
set "CASE5_EXIT=!errorlevel!"

if "!CASE5_EXIT!" NEQ "1" (
  echo FAIL: Case 5 expected exit code 1 ^(bare-token refusal^), got !CASE5_EXIT!.
  goto Fail
)
findstr /C:"ERROR: /upgradeos target must be a build number" "%UPDATE_LOGFILE%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: Case 5 expected the refusal literal in the engine log.
  goto Fail
)
findstr /C:"Info: Upgrade target build" "%UPDATE_LOGFILE%" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: Case 5 must NOT log an acceptance literal for the bare token.
  goto Fail
)
echo [PASS] Case 5: bare token refused loudly (exit 1).

REM -----------------------------------------------------------------------
REM All Passed
REM -----------------------------------------------------------------------
echo.
echo =======================================================================
echo UPGRADE-ARGV-PASS: All 5 /upgradeos acceptance cases passed.
echo =======================================================================
call :Cleanup
exit /b 0

:Fail
echo.
echo =======================================================================
echo FAILURE: /upgradeos argv acceptance battery failed.
echo =======================================================================
call :Cleanup
exit /b 1

:Cleanup
if exist "%SANDBOX_ROOT%" (
  rmdir /s /q "%SANDBOX_ROOT%" 2>nul
)
goto :eof
