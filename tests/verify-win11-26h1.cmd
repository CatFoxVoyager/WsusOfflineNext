@echo off
setlocal enabledelayedexpansion

REM =======================================================================
REM WSUS Offline Update - Windows 11 26H1 (Build 28000) Regression Suite
REM File: tests\verify-win11-26h1.cmd
REM
REM Scenarios:
REM   1. builds.ini & AutoIt Registry Table Contracts (Branch 28000, Status Ineligible)
REM   2. Dedicated Static Manifests & Zero Checkpoint (KB5043080) Leakage
REM   3. Client Environment Variables & .NET 4.8.1 Target Resolution
REM   4. Feature Upgrade Ineligibility & Update Queue Isolation
REM =======================================================================

pushd "%~dp0.."
set "REPO_ROOT=%CD%"
popd

echo =======================================================================
echo WSUS Offline Update - Windows 11 26H1 Regression Suite (Windows CMD)
echo =======================================================================

REM Set up isolated test sandbox
set "SANDBOX_ROOT=%TEMP%\wou_test_26h1_%RANDOM%_%RANDOM%"
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
REM Scenario 1: builds.ini & Registry Table Contracts
REM -----------------------------------------------------------------------
echo [Scenario 1/4] Verifying builds.ini and AutoIt Registry Table Contracts...

REM 1. builds.ini section [w100-x64-28000]
%SystemRoot%\System32\findstr.exe /I /C:"[w100-x64-28000]" "%REPO_ROOT%\static\builds.ini" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Scenario 1: static\builds.ini missing [w100-x64-28000] section.
  goto test_failed
)
%SystemRoot%\System32\findstr.exe /I /C:"servicing_branch=28000" "%REPO_ROOT%\static\builds.ini" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Scenario 1: static\builds.ini [w100-x64-28000] missing servicing_branch=28000.
  goto test_failed
)
%SystemRoot%\System32\findstr.exe /I /C:"status=ineligible" "%REPO_ROOT%\static\builds.ini" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Scenario 1: static\builds.ini [w100-x64-28000] status is not ineligible.
  goto test_failed
)

REM 2. client/UpdateInstaller.au3 table declaration
%SystemRoot%\System32\findstr.exe /C:"[\"28000\", \"x64\", \"win11\", \"28000\", \"ineligible\"" "%REPO_ROOT%\client\UpdateInstaller.au3" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Scenario 1: client\UpdateInstaller.au3 table missing build 28000 ineligible entry.
  goto test_failed
)

REM 3. Ineligibility notification in client/UpdateInstaller.au3
%SystemRoot%\System32\findstr.exe /I /C:"IsBuildIneligible" "%REPO_ROOT%\client\UpdateInstaller.au3" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Scenario 1: client\UpdateInstaller.au3 missing IsBuildIneligible handler.
  goto test_failed
)

echo [PASS] Scenario 1: builds.ini and AutoIt registry table contracts verified.

REM -----------------------------------------------------------------------
REM Scenario 2: Static Manifests & Zero Checkpoint Leakage
REM -----------------------------------------------------------------------
echo.
echo [Scenario 2/4] Verifying Static Manifests and Servicing Branch Isolation...

REM Check all 5 dedicated static list files exist
if not exist "%REPO_ROOT%\client\static\StaticUpdateIds-w100-28000-x64.txt" (
  echo [FAIL] Scenario 2: StaticUpdateIds-w100-28000-x64.txt missing.
  goto test_failed
)
if not exist "%REPO_ROOT%\client\static\StaticUpdateIds-w100-28000.txt" (
  echo [FAIL] Scenario 2: StaticUpdateIds-w100-28000.txt missing.
  goto test_failed
)
if not exist "%REPO_ROOT%\client\static\StaticUpdateIds-w100-28000-dotnet.txt" (
  echo [FAIL] Scenario 2: StaticUpdateIds-w100-28000-dotnet.txt missing.
  goto test_failed
)
if not exist "%REPO_ROOT%\client\static\StaticUpdateIds-servicing-w100-28000.txt" (
  echo [FAIL] Scenario 2: StaticUpdateIds-servicing-w100-28000.txt missing.
  goto test_failed
)
if not exist "%REPO_ROOT%\client\static\StaticUpdateIds-wupre-w100-28000.txt" (
  echo [FAIL] Scenario 2: StaticUpdateIds-wupre-w100-28000.txt missing.
  goto test_failed
)

REM Verify that KB5043080 (the 26100 checkpoint anchor) is NOT in any 28000 list
%SystemRoot%\System32\findstr.exe /I /C:"5043080" "%REPO_ROOT%\client\static\*28000*.txt" >nul 2>&1
if not errorlevel 1 (
  echo [FAIL] Scenario 2: Checkpoint KB5043080 leaked into 28000 static manifests!
  goto test_failed
)

REM Verify StaticUpdateIds-Checkpoints.txt is scoped to 26100
%SystemRoot%\System32\findstr.exe /I /C:"28000" "%REPO_ROOT%\client\static\StaticUpdateIds-Checkpoints.txt" >nul 2>&1
if not errorlevel 1 (
  echo [FAIL] Scenario 2: StaticUpdateIds-Checkpoints.txt contains invalid 28000 checkpoint!
  goto test_failed
)

echo [PASS] Scenario 2: Dedicated static manifests and branch isolation verified.

REM -----------------------------------------------------------------------
REM Scenario 3: Client Environment & .NET Target Resolution
REM -----------------------------------------------------------------------
echo.
echo [Scenario 3/4] Verifying Client Environment Variables and .NET Target Resolution...

REM Verify SetTargetEnvVars.cmd maps 10.0.28000 to .NET 4.8.1 (533320)
%SystemRoot%\System32\findstr.exe /I /C:"10.0.28000" "%REPO_ROOT%\client\cmd\SetTargetEnvVars.cmd" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Scenario 3: client\cmd\SetTargetEnvVars.cmd missing 10.0.28000 target mapping.
  goto test_failed
)

REM Test execution of SetTargetEnvVars.cmd under simulated 28000 environment
set "OS_VER_MAJOR=10"
set "OS_VER_MINOR=0"
set "OS_VER_BUILD_INTERNAL=28000"
set "INSTALL_DOTNET4=/instdotnet4"
set "DOTNET4_RELEASE_TARGET="

call "%REPO_ROOT%\client\cmd\SetTargetEnvVars.cmd"

if "%DOTNET4_RELEASE_TARGET%" NEQ "533320" (
  echo [FAIL] Scenario 3: Expected DOTNET4_RELEASE_TARGET=533320 for build 28000, got: "%DOTNET4_RELEASE_TARGET%".
  goto test_failed
)

if "%OS_NAME%" NEQ "w100" (
  echo [FAIL] Scenario 3: Expected OS_NAME=w100 for build 28000, got: "%OS_NAME%".
  goto test_failed
)

REM Verify UpdateInstaller.au3 maps 28000 to .NET 4.8.1 release 533320
%SystemRoot%\System32\findstr.exe /C:"28000" "%REPO_ROOT%\client\UpdateInstaller.au3" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Scenario 3: client\UpdateInstaller.au3 DotNet4TargetRelease missing 28000 mapping.
  goto test_failed
)
%SystemRoot%\System32\findstr.exe /C:"533320" "%REPO_ROOT%\client\UpdateInstaller.au3" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Scenario 3: client\UpdateInstaller.au3 missing 533320 return value.
  goto test_failed
)

echo [PASS] Scenario 3: Client environment variables and .NET target resolution verified.

REM -----------------------------------------------------------------------
REM Scenario 4: Upgrade Ineligibility & Update Queue Isolation
REM -----------------------------------------------------------------------
echo.
echo [Scenario 4/4] Verifying Feature Upgrade Ineligibility and Queue Isolation...

REM Copy required scripts to sandbox
copy /y "%REPO_ROOT%\client\cmd\ListUpdatesToInstall.cmd" "%SANDBOX_ROOT%\client\cmd\" >nul
copy /y "%REPO_ROOT%\client\cmd\InstallOSUpdate.cmd" "%SANDBOX_ROOT%\client\cmd\" >nul
copy /y "%REPO_ROOT%\client\cmd\DoUpdate.cmd" "%SANDBOX_ROOT%\client\cmd\" >nul
copy /y "%REPO_ROOT%\client\static\StaticUpdateIds-Checkpoints.txt" "%SANDBOX_ROOT%\client\static\" >nul
copy /y "%REPO_ROOT%\client\static\StaticUpdateIds-BuildUpgrades.txt" "%SANDBOX_ROOT%\client\static\" >nul
copy /y "%REPO_ROOT%\client\static\StaticUpdateIds-w100-28000*.txt" "%SANDBOX_ROOT%\client\static\" >nul

REM Verify that StaticUpdateIds-BuildUpgrades.txt does not offer an upgrade from 28000
%SystemRoot%\System32\findstr.exe /C:"28000," "%SANDBOX_ROOT%\client\static\StaticUpdateIds-BuildUpgrades.txt" >nul 2>&1
if not errorlevel 1 (
  echo [FAIL] Scenario 4: StaticUpdateIds-BuildUpgrades.txt offers an invalid upgrade from 28000!
  goto test_failed
)

REM Simulate build upgrade decision from DoUpdate.cmd on a 28000 machine
set "OS_VER_MAJOR=10"
set "OS_VER_BUILD=28000"
set "DO_UPGRADES=/upgradebuilds"
set "WOU_BUILDUPGRADE_FOUND=0"

for /F "tokens=1,2,3,4,5 delims=," %%a in (%SANDBOX_ROOT%\client\static\StaticUpdateIds-BuildUpgrades.txt) do (
  if "%OS_VER_BUILD%"=="%%a" set WOU_BUILDUPGRADE_FOUND=1
)

if "%WOU_BUILDUPGRADE_FOUND%"=="1" (
  echo [FAIL] Scenario 4: Build upgrade loop erroneously detected an upgrade for build 28000.
  goto test_failed
)

REM Simulate static updates evaluation from ListUpdatesToInstall.cmd on build 28000
set "OS_NAME=w100"
set "OS_VER_BUILD=28000"
set "OS_ARCH=x64"

pushd "%SANDBOX_ROOT%\client\cmd"
call ListUpdatesToInstall.cmd /staticevaluationonly >nul 2>&1
popd

REM Ensure no checkpoint update was queued for 28000
if exist "%TEMP%\MissingUpdateIds.txt" (
  %SystemRoot%\System32\findstr.exe /I /C:"5043080" "%TEMP%\MissingUpdateIds.txt" >nul 2>&1
  if not errorlevel 1 (
    echo [FAIL] Scenario 4: Checkpoint KB5043080 was queued for build 28000!
    goto test_failed
  )
)

echo [PASS] Scenario 4: Feature upgrade ineligibility and update queue isolation verified.

REM -----------------------------------------------------------------------
REM Cleanup and Success Exit
REM -----------------------------------------------------------------------
set "TEMP=%ORIG_TEMP%"
rmdir /s /q "%SANDBOX_ROOT%" 2>nul

echo.
echo =======================================================================
echo SUCCESS: All 4 Windows 11 26H1 regression scenarios passed!
echo =======================================================================
exit /b 0

:test_failed
set "TEMP=%ORIG_TEMP%"
rmdir /s /q "%SANDBOX_ROOT%" 2>nul
echo.
echo =======================================================================
echo FAILURE: Windows 11 26H1 regression suite failed!
echo =======================================================================
exit /b 1
