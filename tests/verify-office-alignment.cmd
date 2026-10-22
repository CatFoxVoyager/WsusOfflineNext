@echo off
setlocal enabledelayedexpansion

REM =======================================================================
REM WSUS Offline Update - Office Alignment & Discrimination Regression Suite (Windows CMD)
REM File: tests\verify-office-alignment.cmd
REM
REM Verifies:
REM   Scenario 1: Zero o2k13 leakage across files, trees, and active code paths
REM   Scenario 2: VBScript Office 16.0 product discrimination unit tests (fixtures)
REM   Scenario 3: Run Report Target Office formatting (LTSC 2024 & None detected)
REM   Scenario 4: XSLT pipeline fixture regression (6/6 transforms)
REM =======================================================================

pushd "%~dp0.."
set "REPO_ROOT=%CD%"
popd

echo =======================================================================
echo WSUS Offline Update - Office Alignment Test Suite (Windows CMD)
echo =======================================================================

REM Set up isolated test sandbox
set "SANDBOX_ROOT=%TEMP%\wou_test_office_%RANDOM%_%RANDOM%"
mkdir "%SANDBOX_ROOT%" 2>nul
if not exist "%SANDBOX_ROOT%" (
  echo ERROR: Failed to create test sandbox at "%SANDBOX_ROOT%".
  exit /b 1
)

REM -----------------------------------------------------------------------
REM Scenario 1: Zero o2k13 Leakage
REM -----------------------------------------------------------------------
echo [Scenario 1/4] Verifying zero o2k13 leakage...

REM 1.1 Assert retired files do not exist
if exist "%REPO_ROOT%\xslt\extract-revision-and-update-ids-o2k13.xsl" (
  echo FAIL: xslt\extract-revision-and-update-ids-o2k13.xsl still exists.
  goto Fail
)
if exist "%REPO_ROOT%\client\static\StaticUpdateIds-o2k13.txt" (
  echo FAIL: client\static\StaticUpdateIds-o2k13.txt still exists.
  goto Fail
)
if exist "%REPO_ROOT%\sh\exclude\ExcludeListISO-o2k13.txt" (
  echo FAIL: sh\exclude\ExcludeListISO-o2k13.txt still exists.
  goto Fail
)

for %%f in ("%REPO_ROOT%\static\*o2k13*") do (
  echo FAIL: Obsolete static download file exists: %%f
  goto Fail
)
for %%f in ("%REPO_ROOT%\exclude\*o2k13*") do (
  echo FAIL: Obsolete exclude file exists: %%f
  goto Fail
)

REM 1.2 Scan UpdateGenerator.au3 for o2k13 references
findstr /i /c:"o2k13" "%REPO_ROOT%\UpdateGenerator.au3" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: UpdateGenerator.au3 contains references to o2k13.
  goto Fail
)
findstr /i /c:"Office 2013" "%REPO_ROOT%\UpdateGenerator.au3" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: UpdateGenerator.au3 contains references to 'Office 2013'.
  goto Fail
)

REM 1.3 Scan client/cmd/ for o2k13 references
for %%f in ("%REPO_ROOT%\client\cmd\*.cmd" "%REPO_ROOT%\client\cmd\*.vbs") do (
  findstr /i /c:"o2k13" "%%f" >nul 2>&1
  if not errorlevel 1 (
    echo FAIL: Active client script %%~nxf contains references to o2k13.
    goto Fail
  )
)

REM 1.4 Scan sh/ bash scripts for o2k13 references
powershell -NoProfile -Command "if (Get-ChildItem -Path '%REPO_ROOT%\sh' -Filter '*.bash' -Recurse | Where-Object { $_.FullName -notmatch '[\\/]tests[\\/]' } | Select-String 'o2k13') { exit 1 } else { exit 0 }"
if errorlevel 1 (
  echo FAIL: Linux bash scripts under sh/ contain references to o2k13.
  goto Fail
)

REM 1.5 Scan cmd/DownloadUpdates.cmd active target options
findstr /i /c:"PLATFORM_OFFICE=o2k16" "%REPO_ROOT%\cmd\DownloadUpdates.cmd" >nul 2>&1
if errorlevel 1 (
  echo FAIL: cmd\DownloadUpdates.cmd does not set PLATFORM_OFFICE=o2k16.
  goto Fail
)

echo [PASS] Scenario 1: Zero o2k13 leakage verified across all trees.

REM -----------------------------------------------------------------------
REM Scenario 2: VBScript Product Discrimination Unit Tests (Fixtures)
REM -----------------------------------------------------------------------
echo.
echo [Scenario 2/4] Testing VBScript Office 16.0 discrimination unit tests...

set "TEST_VBS=%REPO_ROOT%\tests\fixtures\office\test_office_discriminate.vbs"
if not exist "%TEST_VBS%" (
  echo ERROR: Discrimination fixture not found at "%TEST_VBS%".
  goto Fail
)

cscript //nologo "%TEST_VBS%"
if errorlevel 1 (
  echo FAIL: Office discrimination unit tests failed.
  goto Fail
)
echo [PASS] Scenario 2: Office 16.0 discrimination validated across all states.

REM -----------------------------------------------------------------------
REM Scenario 3: Run Report Formatting
REM -----------------------------------------------------------------------
echo.
echo [Scenario 3/4] Testing Run Report Target Office formatting...

set "REPORT_OUT_LTSC=%SANDBOX_ROOT%\report_ltsc.txt"
set "REPORT_OUT_NONE=%SANDBOX_ROOT%\report_none.txt"

REM Test 3a: Target Office LTSC 2024
(
  set "O2K16_VER_MAJOR=16"
  set "O2K16_VER_MINOR=0"
  set "O2K16_VER_BUILD=17932"
  set "O2K16_VER_REVIS=21056"
  set "O2K16_ARCH=x64"
  set "O2K16_LANG=glb"
  set "O2K16_PRODUCT_NAME=Office LTSC 2024"
  set "O2K16_EOL_STATUS=Active (Supported until Oct 2029)"
  call "%REPO_ROOT%\client\cmd\DoUpdate.cmd" /reportonly > "%REPORT_OUT_LTSC%" 2>&1
)

findstr /C:"Target Office:           Microsoft Office LTSC 2024 16.0.17932.21056 (x64 glb) [Status: Active (Supported until Oct 2029)]" "%REPORT_OUT_LTSC%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: Target Office line for LTSC 2024 not found or format mismatch. Output was:
  type "%REPORT_OUT_LTSC%"
  goto Fail
)
echo [PASS] Target Office line formatted correctly for Office LTSC 2024.

REM Test 3b: Target Office None detected
(
  set "O2K16_VER_MAJOR="
  set "O2K16_VER_MINOR="
  set "O2K16_VER_BUILD="
  set "O2K16_VER_REVIS="
  set "O2K16_ARCH="
  set "O2K16_LANG="
  set "O2K16_PRODUCT_NAME="
  set "O2K16_EOL_STATUS="
  call "%REPO_ROOT%\client\cmd\DoUpdate.cmd" /reportonly > "%REPORT_OUT_NONE%" 2>&1
)

findstr /C:"Target Office:           None detected" "%REPORT_OUT_NONE%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: Target Office line for None detected not found or format mismatch. Output was:
  type "%REPORT_OUT_NONE%"
  goto Fail
)
echo [PASS] Target Office line formatted correctly when no Office is detected.
echo [PASS] Scenario 3: Run Report Target Office formatting validated.

REM -----------------------------------------------------------------------
REM Scenario 4: XSLT Pipeline Fixtures Regression
REM -----------------------------------------------------------------------
echo.
echo [Scenario 4/4] Executing XSLT pipeline fixture regression suite...
call "%REPO_ROOT%\tests\verify-xslt-pipeline.cmd"
if errorlevel 1 (
  echo FAIL: XSLT pipeline fixture regression suite failed.
  goto Fail
)
echo [PASS] Scenario 4: 6/6 XSLT fixture transforms matched expected output.

REM -----------------------------------------------------------------------
REM Summary & Cleanup
REM -----------------------------------------------------------------------
echo.
echo =======================================================================
echo SUCCESS: All 4 Office alignment regression scenarios passed!
echo =======================================================================
call :Cleanup
exit /b 0

:Fail
echo.
echo =======================================================================
echo FAILURE: Office alignment regression test suite failed.
echo =======================================================================
call :Cleanup
exit /b 1

:Cleanup
if exist "%SANDBOX_ROOT%" (
  rmdir /s /q "%SANDBOX_ROOT%" 2>nul
)
goto :eof
