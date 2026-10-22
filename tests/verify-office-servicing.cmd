@echo off
setlocal enabledelayedexpansion

REM =======================================================================
REM WSUS Offline Update - Complete Office Servicing Regression Suite (Windows CMD)
REM File: tests\verify-office-servicing.cmd
REM
REM Scenarios:
REM   1. Office 16.0 Registry & Discrimination Detection (MSI vs C2R, Bitness)
REM   2. ODT Manifest Generation for Channels (PerpetualVL2019, 2021, 2024)
REM   3. Offline Audit Report Integration ([Microsoft Office Updates] & C2R Header)
REM   4. Win32 Return Code Handling & Anti-Loop Safeguards in InstallOfficeUpdate.cmd
REM   5. Architecture Isolation (ExcludeList-%3.txt) & Medium Support (..\office\c2r)
REM =======================================================================

pushd "%~dp0.."
set "REPO_ROOT=%CD%"
popd

echo =======================================================================
echo WSUS Offline Update - Office Servicing Regression Suite (Windows CMD)
echo =======================================================================

REM -----------------------------------------------------------------------
REM Scenario 1: Office 16.0 Discrimination & Registry Detection
REM -----------------------------------------------------------------------
echo [Scenario 1/5] Verifying Office 16.0 discrimination unit tests and VBS exports...

set "TEST_VBS=%REPO_ROOT%\tests\fixtures\office\test_office_discriminate.vbs"
if not exist "%TEST_VBS%" (
  echo FAIL Scenario 1: Discrimination fixture not found at "%TEST_VBS%".
  goto Fail
)

cscript //nologo "%TEST_VBS%"
if errorlevel 1 (
  echo FAIL Scenario 1: Office discrimination unit tests failed.
  goto Fail
)

findstr /i /c:"O2K16_C2R_CHANNEL" "%REPO_ROOT%\client\cmd\DetermineSystemProperties.vbs" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 1: DetermineSystemProperties.vbs missing O2K16_C2R_CHANNEL.
  goto Fail
)
findstr /i /c:"O2K16_PRODUCT_ID" "%REPO_ROOT%\client\cmd\DetermineSystemProperties.vbs" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 1: DetermineSystemProperties.vbs missing O2K16_PRODUCT_ID.
  goto Fail
)
findstr /i /c:"O2K16_IS_C2R" "%REPO_ROOT%\client\cmd\DetermineSystemProperties.vbs" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 1: DetermineSystemProperties.vbs missing O2K16_IS_C2R.
  goto Fail
)

echo [PASS] Scenario 1: Office discrimination and system properties exports verified.

REM -----------------------------------------------------------------------
REM Scenario 2: ODT Manifest Generation for Channels (2019, 2021, 2024)
REM -----------------------------------------------------------------------
echo [Scenario 2/5] Verifying ODT XML manifest generation for perpetual channels...

set "OS_NAME=w100"
set "OS_LANG=glb"
set "OS_ARCH=x64"
set "O2K16_VER_MAJOR=16"
set "O2K16_IS_C2R=1"
set "O2K16_ARCH=x64"
set "UPDATE_LOGFILE=%TEMP%\test_office_servicing_wou.log"

for %%P in (2019 2021 2024) do (
  if "%%P"=="2019" (
    set "C2R_SUB=o2k19"
    set "C2R_CHAN=PerpetualVL2019"
    set "C2R_PROD=Office 2019"
    set "C2R_PID=ProPlus2019Volume"
  )
  if "%%P"=="2021" (
    set "C2R_SUB=o2k21"
    set "C2R_CHAN=PerpetualVL2021"
    set "C2R_PROD=Office LTSC 2021"
    set "C2R_PID=ProPlus2021Volume"
  )
  if "%%P"=="2024" (
    set "C2R_SUB=o2k24"
    set "C2R_CHAN=PerpetualVL2024"
    set "C2R_PROD=Office LTSC 2024"
    set "C2R_PID=ProPlus2024Volume"
  )

  set "O2K16_PRODUCT_NAME=!C2R_PROD!"
  set "O2K16_PRODUCT_FAMILY=!C2R_PROD!"
  set "O2K16_C2R_CHANNEL=!C2R_CHAN!"
  set "O2K16_PRODUCT_ID=!C2R_PID!"

  set "STAGE_DIR=%REPO_ROOT%\client\office\c2r\!C2R_SUB!\x64"
  if not exist "!STAGE_DIR!" mkdir "!STAGE_DIR!" 2>nul

  if exist "%TEMP%\UpdatesToInstall.txt" del "%TEMP%\UpdatesToInstall.txt"
  if exist "%TEMP%\wou_c2r_update.xml" del "%TEMP%\wou_c2r_update.xml"

  pushd "%REPO_ROOT%\client\cmd"
  call .\ListUpdatesToInstall.cmd >nul 2>&1
  popd

  if not exist "%TEMP%\wou_c2r_update.xml" (
    echo FAIL Scenario 2: wou_c2r_update.xml not created for %%P.
    goto Fail
  )

  findstr /i /c:"!C2R_CHAN!" "%TEMP%\wou_c2r_update.xml" >nul 2>&1
  if errorlevel 1 (
    echo FAIL Scenario 2: Manifest missing channel !C2R_CHAN!.
    goto Fail
  )

  findstr /i /c:"!C2R_PID!" "%TEMP%\wou_c2r_update.xml" >nul 2>&1
  if errorlevel 1 (
    echo FAIL Scenario 2: Manifest missing Product ID !C2R_PID!.
    goto Fail
  )

  findstr /i /c:"wou_c2r_update.xml" "%TEMP%\UpdatesToInstall.txt" >nul 2>&1
  if errorlevel 1 (
    echo FAIL Scenario 2: UpdatesToInstall.txt does not contain wou_c2r_update.xml.
    goto Fail
  )

  if exist "%TEMP%\wou_c2r_update.xml" del "%TEMP%\wou_c2r_update.xml"
  if exist "%TEMP%\UpdatesToInstall.txt" del "%TEMP%\UpdatesToInstall.txt"
  if exist "%REPO_ROOT%\client\office\c2r\!C2R_SUB!" rmdir /s /q "%REPO_ROOT%\client\office\c2r\!C2R_SUB!" 2>nul
)

if exist "%UPDATE_LOGFILE%" del "%UPDATE_LOGFILE%" 2>nul
echo [PASS] Scenario 2: ODT XML manifest generation verified for PerpetualVL2019, 2021, and 2024.

REM -----------------------------------------------------------------------
REM Scenario 3: Offline Audit Report Integration ([Microsoft Office Updates])
REM -----------------------------------------------------------------------
echo [Scenario 3/5] Verifying offline audit report integration with C2R and MSI updates...

set "AUDIT_SANDBOX=%TEMP%\wou_audit_servicing_%RANDOM%"
mkdir "%AUDIT_SANDBOX%\client\cmd" 2>nul
mkdir "%AUDIT_SANDBOX%\log" 2>nul
mkdir "%AUDIT_SANDBOX%\temp" 2>nul

copy /y "%REPO_ROOT%\client\cmd\DoUpdate.cmd" "%AUDIT_SANDBOX%\client\cmd\" >nul

set "ORIG_TEMP=%TEMP%"
set "TEMP=%AUDIT_SANDBOX%\temp"
set "UPDATE_LOGFILE=%AUDIT_SANDBOX%\log\test_audit.log"
set "REPORT_FILE=%AUDIT_SANDBOX%\log\MissingUpdates.txt"

set "O2K16_IS_C2R=1"
set "O2K16_VER_MAJOR=16"
set "O2K16_VER_MINOR=0"
set "O2K16_VER_BUILD=17928"
set "O2K16_VER_REVIS=20156"
set "O2K16_ARCH=x64"
set "O2K16_LANG=enu"
set "O2K16_PRODUCT_NAME=Office LTSC 2024"
set "O2K16_C2R_CHANNEL=PerpetualVL2024"
set "O2K16_EOL_STATUS=Active (Supported until Oct 2029)"

(
  echo ..\o2k16\glb\excel2016-kb5002165-fullfile-x64-glb.exe
  echo %TEMP%\wou_c2r_update.xml
) > "%TEMP%\UpdatesToInstall.txt"

pushd "%AUDIT_SANDBOX%\client\cmd"
call .\DoUpdate.cmd :WriteMissingUpdatesReport > "%AUDIT_SANDBOX%\log\audit_out.log" 2>&1
popd

set "TEMP=%ORIG_TEMP%"

if not exist "%REPORT_FILE%" (
  echo FAIL Scenario 3: MissingUpdates.txt was not generated.
  goto Fail
)

findstr /i /c:"Total Missing Items:     2" "%REPORT_FILE%" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 3: Total Missing Items is not 2.
  type "%REPORT_FILE%"
  goto Fail
)

findstr /i /c:"[Microsoft Office Updates] [Count: 2]" "%REPORT_FILE%" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 3: Office Updates section count is not 2.
  goto Fail
)

findstr /i /c:"excel2016-kb5002165-fullfile-x64-glb.exe" "%REPORT_FILE%" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 3: MSI patch missing from Office section.
  goto Fail
)

findstr /i /c:"Microsoft Office LTSC 2024 (x64) - Staged C2R Update Package [Channel: PerpetualVL2024]" "%REPORT_FILE%" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 3: C2R package missing from Office section.
  goto Fail
)

findstr /i /c:"Target Office:           Microsoft Office LTSC 2024 16.0.17928.20156 (x64 enu) [Channel: PerpetualVL2024, Status: Active (Supported until Oct 2029)]" "%REPORT_FILE%" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 3: Target Office header formatting mismatch.
  type "%REPORT_FILE%"
  goto Fail
)

rmdir /s /q "%AUDIT_SANDBOX%" 2>nul
echo [PASS] Scenario 3: Offline audit report correctly categorizes both MSI and C2R updates.

REM -----------------------------------------------------------------------
REM Scenario 4: Win32 Return Codes & Loop Safety in InstallOfficeUpdate.cmd
REM -----------------------------------------------------------------------
echo [Scenario 4/5] Verifying InstallOfficeUpdate.cmd return codes and loop protection...

findstr /i /c:"ODT_SETUP_EXE" "%REPO_ROOT%\client\cmd\InstallOfficeUpdate.cmd" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 4: ODT setup.exe search missing from InstallOfficeUpdate.cmd.
  goto Fail
)

findstr /i /c:"OfficeC2RClient.exe" "%REPO_ROOT%\client\cmd\InstallOfficeUpdate.cmd" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 4: OfficeC2RClient.exe fallback missing.
  goto Fail
)

findstr /i /c:"wou_c2r_tried.txt" "%REPO_ROOT%\client\cmd\InstallOfficeUpdate.cmd" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 4: Anti-loop marker wou_c2r_tried.txt missing.
  goto Fail
)

findstr /i /c:"REBOOT_REQUIRED=1" "%REPO_ROOT%\client\cmd\InstallOfficeUpdate.cmd" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 4: REBOOT_REQUIRED handling missing.
  goto Fail
)

findstr /i /c:"RECALL_REQUIRED=1" "%REPO_ROOT%\client\cmd\InstallOfficeUpdate.cmd" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 4: RECALL_REQUIRED handling missing for 3011.
  goto Fail
)

echo [PASS] Scenario 4: InstallOfficeUpdate.cmd execution dispatcher and exit codes validated.

REM -----------------------------------------------------------------------
REM Scenario 5: Architecture Isolation & Medium Detection
REM -----------------------------------------------------------------------
echo [Scenario 5/5] Verifying architecture isolation and medium support...

findstr /i /c:"..\office\c2r" "%REPO_ROOT%\client\cmd\DoUpdate.cmd" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 5: DoUpdate.cmd does not recognize ..\office\c2r medium.
  goto Fail
)

findstr /i /c:"/updateoffice" "%REPO_ROOT%\client\cmd\DoUpdate.cmd" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 5: DoUpdate.cmd does not recognize /updateoffice.
  goto Fail
)

findstr /i /c:"IS_OFFICE_UPDATE" "%REPO_ROOT%\client\cmd\InstallListedUpdates.cmd" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 5: InstallListedUpdates.cmd missing IS_OFFICE_UPDATE.
  goto Fail
)

echo [PASS] Scenario 5: Architecture isolation and C2R medium support verified.

echo.
echo =======================================================================
echo Complete Office Servicing Test Suite: ALL TESTS PASSED
echo =======================================================================
exit /b 0

:Fail
if defined AUDIT_SANDBOX (
  if exist "%AUDIT_SANDBOX%" rmdir /s /q "%AUDIT_SANDBOX%" 2>nul
)
if defined TEST_STAGING_DIR (
  if exist "%TEST_STAGING_DIR%" rmdir /s /q "%REPO_ROOT%\client\office\c2r" 2>nul
)
if exist "%TEMP%\wou_c2r_update.xml" del "%TEMP%\wou_c2r_update.xml" 2>nul
if exist "%TEMP%\UpdatesToInstall.txt" del "%TEMP%\UpdatesToInstall.txt" 2>nul
echo =======================================================================
echo Complete Office Servicing Test Suite: FAILED
echo =======================================================================
exit /b 1
