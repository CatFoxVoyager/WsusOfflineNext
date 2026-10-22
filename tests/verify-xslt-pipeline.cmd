@echo off
setlocal enabledelayedexpansion

REM =======================================================================
REM WSUS Offline Update - XSLT Pipeline Validation Runner (Windows CMD)
REM File: tests\verify-xslt-pipeline.cmd
REM
REM Modes:
REM   verify-xslt-pipeline.cmd          Offline synthetic fixture regression suite
REM   verify-xslt-pipeline.cmd --live   Live Microsoft catalog (wsusscn2.cab) validation
REM =======================================================================

pushd "%~dp0.."
set "REPO_ROOT=%CD%"
popd

set "MODE=fixture"
if /i "%~1"=="--live" set "MODE=live"
if /i "%~1"=="-live" set "MODE=live"

REM Locate cscript.exe
set "CSCRIPT_PATH=%SystemRoot%\System32\cscript.exe"
if not exist "%CSCRIPT_PATH%" (
  echo ERROR: VBScript interpreter not found at "%CSCRIPT_PATH%".
  exit /b 1
)

REM Locate gsort.exe or fallback to system sort
if exist "%REPO_ROOT%\bin\gsort.exe" (
  set "GSORT_PATH=%REPO_ROOT%\bin\gsort.exe"
) else (
  set "GSORT_PATH=sort"
)

REM Locate XSLT.vbs
set "XSLT_VBS=%REPO_ROOT%\cmd\XSLT.vbs"
if not exist "%XSLT_VBS%" (
  echo ERROR: XSLT transformation script not found at "%XSLT_VBS%".
  exit /b 1
)

REM Setup temporary working directory
set "WORK_DIR=%TEMP%\wou_xslt_test_%RANDOM%_%RANDOM%"
mkdir "%WORK_DIR%" 2>nul
if not exist "%WORK_DIR%" (
  echo ERROR: Failed to create temporary directory "%WORK_DIR%".
  exit /b 1
)

if "%MODE%"=="live" goto RunLiveMode
goto RunFixtureMode

REM =======================================================================
REM Offline Synthetic Fixture Suite
REM =======================================================================
:RunFixtureMode
set "FIXTURES_DIR=%REPO_ROOT%\tests\fixtures\xslt"
set "SAMPLE_XML=%FIXTURES_DIR%\sample-package.xml"

if not exist "%SAMPLE_XML%" (
  echo ERROR: Synthetic fixture XML not found at "%SAMPLE_XML%".
  goto Fail
)

echo =======================================================================
echo WSUS Offline Update - XSLT Fixture Regression Suite
echo =======================================================================
echo Testing 6 core transforms against %SAMPLE_XML%...
echo.

call :TestTransform "extract-revision-and-update-ids-w100.xsl" "expected-revision-and-update-ids-w100.txt" "1/6"
if errorlevel 1 goto Fail

call :TestTransform "extract-revision-and-update-ids-o2k16.xsl" "expected-revision-and-update-ids-o2k16.txt" "2/6"
if errorlevel 1 goto Fail

call :TestTransform "extract-update-revision-and-file-ids.xsl" "expected-update-revision-and-file-ids.txt" "3/6"
if errorlevel 1 goto Fail

call :TestTransform "extract-update-cab-exe-ids-and-locations.xsl" "expected-update-cab-exe-ids-and-locations.txt" "4/6"
if errorlevel 1 goto Fail

call :TestTransform "extract-existing-bundle-revision-ids.xsl" "expected-existing-bundle-revision-ids.txt" "5/6"
if errorlevel 1 goto Fail

call :TestTransform "extract-superseding-and-superseded-revision-ids.xsl" "expected-superseding-and-superseded-revision-ids.txt" "6/6"
if errorlevel 1 goto Fail

echo.
echo SUCCESS: All 6 XSLT fixture transforms matched expected output.
call :Cleanup
exit /b 0

:TestTransform
set "XSL_FILE=%REPO_ROOT%\xslt\%~1"
set "EXPECTED_FILE=%FIXTURES_DIR%\%~2"
set "STEP=%~3"
set "TMP_RAW=%WORK_DIR%\raw_%~n1.txt"
set "TMP_SORTED=%WORK_DIR%\sorted_%~n1.txt"

echo [%STEP%] Testing %~1 ...
if not exist "%XSL_FILE%" (
  echo ERROR: Stylesheet "%XSL_FILE%" does not exist.
  exit /b 1
)
if not exist "%EXPECTED_FILE%" (
  echo ERROR: Expected fixture "%EXPECTED_FILE%" does not exist.
  exit /b 1
)

"%CSCRIPT_PATH%" //Nologo //B //E:vbs "%XSLT_VBS%" "%SAMPLE_XML%" "%XSL_FILE%" "%TMP_RAW%"
if errorlevel 1 (
  echo ERROR: XSLT execution failed for %~1.
  exit /b 1
)
if not exist "%TMP_RAW%" (
  echo ERROR: Output file was not created for %~1.
  exit /b 1
)

for %%F in ("%TMP_RAW%") do (
  if %%~zF equ 0 (
    echo ERROR: Raw transform output is empty for %~1.
    exit /b 1
  )
)

"%GSORT_PATH%" -u -T "%TEMP%" "%TMP_RAW%" > "%TMP_SORTED%"
if errorlevel 1 (
  echo ERROR: Sort failed for %~1.
  exit /b 1
)

%SystemRoot%\System32\fc.exe /b "%TMP_SORTED%" "%EXPECTED_FILE%" >nul
if errorlevel 1 (
  echo ERROR: Transformed output for %~1 did NOT match expected fixture %~2!
  echo Diff details:
  %SystemRoot%\System32\fc.exe "%TMP_SORTED%" "%EXPECTED_FILE%"
  exit /b 1
)

echo   PASS: Transformed output matched %~2 byte-for-byte.
exit /b 0

REM =======================================================================
REM Live Catalog Verification Mode (--live)
REM =======================================================================
:RunLiveMode
echo =======================================================================
echo WSUS Offline Update - Live Catalog Verification (--live)
echo =======================================================================

set "WSUS_DIR=%REPO_ROOT%\client\wsus"
set "WSUS_CAB=%WSUS_DIR%\wsusscn2.cab"
if not exist "%WSUS_DIR%" mkdir "%WSUS_DIR%"

if exist "%WSUS_CAB%" goto HaveCatalog

echo wsusscn2.cab not found in cache: %WSUS_CAB%
set "DOWNLOAD_URL="
if exist "%REPO_ROOT%\static\StaticDownloadLinks-wsus.txt" (
  for /f "usebackq delims=" %%u in ("%REPO_ROOT%\static\StaticDownloadLinks-wsus.txt") do (
    if not defined DOWNLOAD_URL set "DOWNLOAD_URL=%%u"
  )
)
if not defined DOWNLOAD_URL (
  set "DOWNLOAD_URL=http://download.windowsupdate.com/microsoftupdate/v6/wsusscan/wsusscn2.cab"
)
echo Downloading wsusscn2.cab from !DOWNLOAD_URL! ...
curl.exe -f -L -C - "!DOWNLOAD_URL!" -o "%WSUS_CAB%"
if errorlevel 1 (
  echo ERROR: Failed to download wsusscn2.cab.
  goto Fail
)

:HaveCatalog
echo Using cached catalog: %WSUS_CAB%
if not exist "%WSUS_CAB%" (
  echo ERROR: Catalog file "%WSUS_CAB%" does not exist.
  goto Fail
)
for %%F in ("%WSUS_CAB%") do (
  if %%~zF equ 0 (
    echo ERROR: Catalog file "%WSUS_CAB%" is empty.
    goto Fail
  )
  echo Catalog size: %%~zF bytes
)

echo Extracting package.cab from wsusscn2.cab...
%SystemRoot%\System32\expand.exe "%WSUS_CAB%" -F:package.cab "%WORK_DIR%" >nul
if errorlevel 1 (
  echo ERROR: Failed to expand package.cab from wsusscn2.cab.
  goto Fail
)
if not exist "%WORK_DIR%\package.cab" (
  echo ERROR: package.cab was not produced by expand.
  goto Fail
)

echo Extracting package.xml from package.cab...
%SystemRoot%\System32\expand.exe "%WORK_DIR%\package.cab" "%WORK_DIR%\package.xml" >nul
if errorlevel 1 (
  echo ERROR: Failed to expand package.xml from package.cab.
  goto Fail
)
if not exist "%WORK_DIR%\package.xml" (
  echo ERROR: package.xml was not produced by expand.
  goto Fail
)
for %%F in ("%WORK_DIR%\package.xml") do (
  if %%~zF equ 0 (
    echo ERROR: Extracted package.xml is empty.
    goto Fail
  )
  echo Extracted package.xml size: %%~zF bytes
)
del "%WORK_DIR%\package.cab" 2>nul

set "LIVE_XML=%WORK_DIR%\package.xml"

echo.
echo Running XSLT transforms on live package.xml...

REM Transform 1: Windows 10 / 11 update IDs
echo [1/3] Transforming xslt\extract-revision-and-update-ids-w100.xsl ...
"%CSCRIPT_PATH%" //Nologo //B //E:vbs "%XSLT_VBS%" "%LIVE_XML%" "%REPO_ROOT%\xslt\extract-revision-and-update-ids-w100.xsl" "%WORK_DIR%\live_w100.txt"
if errorlevel 1 (
  echo ERROR: Transform failed for extract-revision-and-update-ids-w100.xsl.
  goto Fail
)
if not exist "%WORK_DIR%\live_w100.txt" (
  echo ERROR: Output live_w100.txt was not created.
  goto Fail
)
for %%F in ("%WORK_DIR%\live_w100.txt") do (
  if %%~zF equ 0 (
    echo ERROR: Output live_w100.txt is empty.
    goto Fail
  )
  echo   Generated live_w100.txt: %%~zF bytes
)

REM Transform 2: Office update IDs
echo [2/3] Transforming xslt\extract-revision-and-update-ids-ofc.xsl ...
"%CSCRIPT_PATH%" //Nologo //B //E:vbs "%XSLT_VBS%" "%LIVE_XML%" "%REPO_ROOT%\xslt\extract-revision-and-update-ids-ofc.xsl" "%WORK_DIR%\live_ofc.txt"
if errorlevel 1 (
  echo ERROR: Transform failed for extract-revision-and-update-ids-ofc.xsl.
  goto Fail
)
if not exist "%WORK_DIR%\live_ofc.txt" (
  echo ERROR: Output live_ofc.txt was not created.
  goto Fail
)
for %%F in ("%WORK_DIR%\live_ofc.txt") do (
  if %%~zF equ 0 (
    echo ERROR: Output live_ofc.txt is empty.
    goto Fail
  )
  echo   Generated live_ofc.txt: %%~zF bytes
)

REM Transform 3: Update Cab/Exe locations
echo [3/3] Transforming xslt\extract-update-cab-exe-ids-and-locations.xsl ...
"%CSCRIPT_PATH%" //Nologo //B //E:vbs "%XSLT_VBS%" "%LIVE_XML%" "%REPO_ROOT%\xslt\extract-update-cab-exe-ids-and-locations.xsl" "%WORK_DIR%\live_locs.txt"
if errorlevel 1 (
  echo ERROR: Transform failed for extract-update-cab-exe-ids-and-locations.xsl.
  goto Fail
)
if not exist "%WORK_DIR%\live_locs.txt" (
  echo ERROR: Output live_locs.txt was not created.
  goto Fail
)
for %%F in ("%WORK_DIR%\live_locs.txt") do (
  if %%~zF equ 0 (
    echo ERROR: Output live_locs.txt is empty.
    goto Fail
  )
  echo   Generated live_locs.txt: %%~zF bytes
)

echo.
echo Validating output schemas and patterns...

REM Validate format of Windows updates: #\d+#,[0-9a-fA-F-]+
%SystemRoot%\System32\findstr.exe /R "^#[0-9][0-9]*#,[0-9a-fA-F-][0-9a-fA-F-]*" "%WORK_DIR%\live_w100.txt" > "%WORK_DIR%\w100_valid.txt"
if errorlevel 1 (
  echo ERROR: No valid #RevId#,<UpdateId> entries found in Windows output.
  goto Fail
)
for /f %%A in ('type "%WORK_DIR%\w100_valid.txt" ^| %SystemRoot%\System32\find.exe /c /v ""') do set "W100_COUNT=%%A"
if %W100_COUNT% equ 0 (
  echo ERROR: Zero valid Windows update entries found.
  goto Fail
)
echo   PASS: Found %W100_COUNT% valid Windows update entries.

REM Validate format of Office updates: #\d+#,[0-9a-fA-F-]+
%SystemRoot%\System32\findstr.exe /R "^#[0-9][0-9]*#,[0-9a-fA-F-][0-9a-fA-F-]*" "%WORK_DIR%\live_ofc.txt" > "%WORK_DIR%\ofc_valid.txt"
if errorlevel 1 (
  echo ERROR: No valid #RevId#,<UpdateId> entries found in Office output.
  goto Fail
)
for /f %%A in ('type "%WORK_DIR%\ofc_valid.txt" ^| %SystemRoot%\System32\find.exe /c /v ""') do set "OFC_COUNT=%%A"
if %OFC_COUNT% equ 0 (
  echo ERROR: Zero valid Office update entries found.
  goto Fail
)
echo   PASS: Found %OFC_COUNT% valid Office update entries.

REM Validate format of File Locations: ,http://
%SystemRoot%\System32\findstr.exe /C:",http://" "%WORK_DIR%\live_locs.txt" > "%WORK_DIR%\locs_valid.txt"
if errorlevel 1 (
  echo ERROR: No valid FileId,Url entries found in locations output.
  goto Fail
)
for /f %%A in ('type "%WORK_DIR%\locs_valid.txt" ^| %SystemRoot%\System32\find.exe /c /v ""') do set "LOCS_COUNT=%%A"
if %LOCS_COUNT% equ 0 (
  echo ERROR: Zero valid file location entries found.
  goto Fail
)
echo   PASS: Found %LOCS_COUNT% valid file location URLs.

REM Validate Windows 11 Product ID entries specifically (72e7624a-5b00-45d2-b92f-e561c0a6a160)
echo Validating presence of Windows 11 Product ID entries...
set "WIN11_XSL=%REPO_ROOT%\tests\fixtures\xslt\extract-win11-only.xsl"
if not exist "%WIN11_XSL%" (
  echo ERROR: "%WIN11_XSL%" does not exist.
  goto Fail
)
"%CSCRIPT_PATH%" //Nologo //B //E:vbs "%XSLT_VBS%" "%LIVE_XML%" "%WIN11_XSL%" "%WORK_DIR%\live_win11_only.txt"
if errorlevel 1 (
  echo ERROR: Extraction of Windows 11 Product ID entries failed.
  goto Fail
)
for %%F in ("%WORK_DIR%\live_win11_only.txt") do (
  if %%~zF equ 0 (
    echo ERROR: Zero Windows 11 Product ID entries found in live catalog!
    goto Fail
  )
)
for /f %%A in ('type "%WORK_DIR%\live_win11_only.txt" ^| %SystemRoot%\System32\find.exe /c /v ""') do set "WIN11_COUNT=%%A"
if %WIN11_COUNT% equ 0 (
  echo ERROR: Zero Windows 11 update entries found.
  goto Fail
)
echo   PASS: Verified presence of %WIN11_COUNT% Windows 11 Product ID entries.

echo.
echo SUCCESS: Live catalog validation completed successfully.
call :Cleanup
exit /b 0

REM =======================================================================
REM Cleanup and Fail Handlers
REM =======================================================================
:Cleanup
if exist "%WORK_DIR%" (
  rmdir /s /q "%WORK_DIR%" 2>nul
)
exit /b 0

:Fail
echo.
echo FAILED: XSLT pipeline verification failed.
call :Cleanup
exit /b 1
