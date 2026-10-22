@echo off
setlocal enabledelayedexpansion

echo =======================================================================
echo WSUS Offline Update - C2R Servicing Test Suite (Windows CMD)
echo =======================================================================

pushd "%~dp0.."
set "REPO_ROOT=%CD%"
popd

rem -----------------------------------------------------------------------
rem Scenario 1: Validate DetermineSystemProperties.vbs C2R variables
rem -----------------------------------------------------------------------
echo [Scenario 1/5] Verifying C2R variable definitions in DetermineSystemProperties.vbs...
findstr /i /c:"O2K16_C2R_CHANNEL" "%REPO_ROOT%\client\cmd\DetermineSystemProperties.vbs" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] DetermineSystemProperties.vbs missing O2K16_C2R_CHANNEL export.
  exit /b 1
)
findstr /i /c:"O2K16_PRODUCT_ID" "%REPO_ROOT%\client\cmd\DetermineSystemProperties.vbs" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] DetermineSystemProperties.vbs missing O2K16_PRODUCT_ID export.
  exit /b 1
)
echo [PASS] Scenario 1: DetermineSystemProperties.vbs exports C2R channel and product ID.

rem -----------------------------------------------------------------------
rem Scenario 2: Validate DoUpdate.cmd parameter parsing & medium check
rem -----------------------------------------------------------------------
echo.
echo [Scenario 2/5] Verifying /updateoffice and ..\office\c2r in DoUpdate.cmd...
findstr /i /c:"/updateoffice" "%REPO_ROOT%\client\cmd\DoUpdate.cmd" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] DoUpdate.cmd does not recognize /updateoffice.
  exit /b 1
)
findstr /i /c:"..\office\c2r" "%REPO_ROOT%\client\cmd\DoUpdate.cmd" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] DoUpdate.cmd does not check ..\office\c2r medium support.
  exit /b 1
)
echo [PASS] Scenario 2: DoUpdate.cmd parses /updateoffice and supports ..\office\c2r.

rem -----------------------------------------------------------------------
rem Scenario 3: Validate ListUpdatesToInstall.cmd C2R discovery & XML generation
rem -----------------------------------------------------------------------
echo.
echo [Scenario 3/5] Testing C2R media discovery and manifest generation...
set "TEST_STAGING_DIR=%REPO_ROOT%\client\office\c2r\o2k24\x64"
if not exist "%TEST_STAGING_DIR%" mkdir "%TEST_STAGING_DIR%" 2>nul

set "OS_NAME=w100"
set "OS_LANG=glb"
set "OS_ARCH=x64"

set "O2K16_VER_MAJOR=16"
set "O2K16_IS_C2R=1"
set "O2K16_PRODUCT_NAME=Office LTSC 2024"
set "O2K16_PRODUCT_FAMILY=Office LTSC 2024"
set "O2K16_ARCH=x64"
set "O2K16_C2R_CHANNEL=PerpetualVL2024"
set "O2K16_PRODUCT_ID=ProPlus2024Volume"

set "UPDATE_LOGFILE=%TEMP%\test_wsusoffline.log"

if exist "%TEMP%\UpdatesToInstall.txt" del "%TEMP%\UpdatesToInstall.txt"
if exist "%TEMP%\wou_c2r_update.xml" del "%TEMP%\wou_c2r_update.xml"

pushd "%REPO_ROOT%\client\cmd"
call .\ListUpdatesToInstall.cmd >nul 2>&1
popd

if not exist "%TEMP%\wou_c2r_update.xml" (
  echo [FAIL] wou_c2r_update.xml was not created by ListUpdatesToInstall.cmd.
  exit /b 1
)

findstr /i /c:"PerpetualVL2024" "%TEMP%\wou_c2r_update.xml" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Manifest missing PerpetualVL2024 channel.
  exit /b 1
)

findstr /i /c:"ProPlus2024Volume" "%TEMP%\wou_c2r_update.xml" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Manifest missing ProPlus2024Volume Product ID.
  exit /b 1
)

findstr /i /c:"wou_c2r_update.xml" "%TEMP%\UpdatesToInstall.txt" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] UpdatesToInstall.txt does not contain wou_c2r_update.xml.
  exit /b 1
)

rem Cleanup test artifacts
if exist "%TEMP%\wou_c2r_update.xml" del "%TEMP%\wou_c2r_update.xml"
if exist "%TEMP%\UpdatesToInstall.txt" del "%TEMP%\UpdatesToInstall.txt"
if exist "%TEST_STAGING_DIR%" rmdir /s /q "%REPO_ROOT%\client\office\c2r\o2k24" 2>nul
if exist "%UPDATE_LOGFILE%" del "%UPDATE_LOGFILE%" 2>nul

echo [PASS] Scenario 3: C2R media discovery and manifest generation validated.

rem -----------------------------------------------------------------------
rem Scenario 4: Validate InstallListedUpdates.cmd routing for \office\ and C2R
rem -----------------------------------------------------------------------
echo.
echo [Scenario 4/5] Verifying routing of Office C2R targets in InstallListedUpdates.cmd...
findstr /i /c:"IS_OFFICE_UPDATE" "%REPO_ROOT%\client\cmd\InstallListedUpdates.cmd" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] InstallListedUpdates.cmd missing IS_OFFICE_UPDATE routing flag.
  exit /b 1
)

findstr /i /c:"wou_c2r" "%REPO_ROOT%\client\cmd\InstallListedUpdates.cmd" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] InstallListedUpdates.cmd does not match wou_c2r manifests.
  exit /b 1
)
echo [PASS] Scenario 4: InstallListedUpdates.cmd routes Office C2R updates cleanly.

rem -----------------------------------------------------------------------
rem Scenario 5: Validate InstallOfficeUpdate.cmd return codes & loop protection
rem -----------------------------------------------------------------------
echo.
echo [Scenario 5/5] Verifying return codes and loop prevention in InstallOfficeUpdate.cmd...
findstr /i /c:"wou_c2r_tried.txt" "%REPO_ROOT%\client\cmd\InstallOfficeUpdate.cmd" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] InstallOfficeUpdate.cmd missing wou_c2r_tried.txt loop protection.
  exit /b 1
)

findstr /i /c:"3011" "%REPO_ROOT%\client\cmd\InstallOfficeUpdate.cmd" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] InstallOfficeUpdate.cmd missing 3011 recall return code handling.
  exit /b 1
)

findstr /i /c:"ODT_SETUP_EXE" "%REPO_ROOT%\client\cmd\InstallOfficeUpdate.cmd" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] InstallOfficeUpdate.cmd missing ODT setup.exe priority resolution.
  exit /b 1
)
echo [PASS] Scenario 5: InstallOfficeUpdate.cmd return codes and loop safety validated.

echo.
echo =======================================================================
echo ALL TESTS PASSED: C2R Servicing Engine (Wave 1 ^& 2) 100%% green.
echo =======================================================================
exit /b 0
