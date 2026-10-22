@echo off
setlocal enabledelayedexpansion

REM =======================================================================
REM WSUS Offline Update - Integrity & Fail-Closed Verification Test Suite
REM File: tests\test-integrity-failclosed.cmd
REM
REM Scenarios:
REM   1. Core OS update with corrupted hash fails closed
REM   2. Core OS update with missing hash in hash file fails closed
REM   3. Standalone installer with missing hash bypasses verification with warning
REM   4. Standalone installer with corrupted hash fails closed
REM   5. DoUpdate Run Report formatting, counts, and tracking cleanup
REM =======================================================================

pushd "%~dp0.."
set "REPO_ROOT=%CD%"
popd

echo =======================================================================
echo WSUS Offline Update - Fail-Closed Integrity Verification Suite
echo =======================================================================

REM Set up isolated test sandbox
set "SANDBOX=%TEMP%\wou_test_integrity_%RANDOM%_%RANDOM%"
mkdir "%SANDBOX%\client\cmd" 2>nul
mkdir "%SANDBOX%\client\bin" 2>nul
mkdir "%SANDBOX%\client\md" 2>nul
mkdir "%SANDBOX%\client\w100-x64\glb" 2>nul
mkdir "%SANDBOX%\client\msedge" 2>nul
mkdir "%SANDBOX%\log" 2>nul

if not exist "%SANDBOX%\client\cmd" (
  echo ERROR: Failed to create test sandbox directory at "%SANDBOX%".
  exit /b 1
)

copy /y "%REPO_ROOT%\client\cmd\InstallOSUpdate.cmd" "%SANDBOX%\client\cmd\" >nul
copy /y "%REPO_ROOT%\client\cmd\DoUpdate.cmd" "%SANDBOX%\client\cmd\" >nul

if exist "%REPO_ROOT%\client\bin\hashdeep64.exe" (
  copy /y "%REPO_ROOT%\client\bin\hashdeep64.exe" "%SANDBOX%\client\bin\" >nul
  copy /y "%REPO_ROOT%\client\bin\hashdeep64.exe" "%SANDBOX%\client\bin\hashdeep.exe" >nul
) else if exist "%REPO_ROOT%\client\bin\hashdeep.exe" (
  copy /y "%REPO_ROOT%\client\bin\hashdeep.exe" "%SANDBOX%\client\bin\" >nul
  copy /y "%REPO_ROOT%\client\bin\hashdeep.exe" "%SANDBOX%\client\bin\hashdeep64.exe" >nul
) else (
  echo ERROR: Vendored hashdeep executable not found in "%REPO_ROOT%\client\bin".
  goto TestFailed
)

REM =======================================================================
REM Scenario 1: Core OS update with corrupted hash
REM =======================================================================
echo Running Scenario 1: Core OS update with corrupted hash...
call :CleanMarkers
echo dummy core payload > "%SANDBOX%\client\w100-x64\glb\windows11.0-kb5054156-x64.cab"
(
  echo %%%% HASHDEEP-1.0
  echo %%%% size,md5,sha256,filename
  echo ##
  echo 999,00000000000000000000000000000000,0000000000000000000000000000000000000000000000000000000000000000,windows11.0-kb5054156-x64.cab
) > "%SANDBOX%\client\md\hashes-w100-x64.txt"

pushd "%SANDBOX%\client\cmd"
set "OS_ARCH=x64"
set "UPDATE_LOGFILE=%SANDBOX%\test_update.log"
call .\InstallOSUpdate.cmd "..\w100-x64\glb\windows11.0-kb5054156-x64.cab" /verify /errorsaswarnings > "%SANDBOX%\scen1.log" 2>&1
popd

if not exist "%TEMP%\wou_corrupt_updates.txt" (
  echo FAIL Scenario 1: wou_corrupt_updates.txt was not created.
  goto TestFailed
)
%SystemRoot%\System32\findstr.exe /I /C:"windows11.0-kb5054156-x64.cab" "%TEMP%\wou_corrupt_updates.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 1: wou_corrupt_updates.txt does not contain corrupt update path.
  goto TestFailed
)
if exist "%TEMP%\wou_installed_updates.txt" (
  %SystemRoot%\System32\findstr.exe /I /C:"windows11.0-kb5054156-x64.cab" "%TEMP%\wou_installed_updates.txt" >nul 2>&1
  if not errorlevel 1 (
    echo FAIL Scenario 1: Corrupt update was marked installed!
    goto TestFailed
  )
)
%SystemRoot%\System32\findstr.exe /I /C:"Integrity verification failed" "%SANDBOX%\scen1.log" >nul 2>&1
if errorlevel 1 (
  %SystemRoot%\System32\findstr.exe /I /C:"Integrity verification failed" "%SANDBOX%\test_update.log" >nul 2>&1
  if errorlevel 1 (
    echo FAIL Scenario 1: Log output missing Integrity verification failed.
    goto TestFailed
  )
)
echo [PASS] Scenario 1: Core OS corrupted hash fails closed.

REM =======================================================================
REM Scenario 2: Core OS update with missing hash in hash file
REM =======================================================================
echo Running Scenario 2: Core OS update with missing hash in hash file...
call :CleanMarkers
echo dummy core payload 2 > "%SANDBOX%\client\w100-x64\glb\windows11.0-kb9999999-x64.cab"

pushd "%SANDBOX%\client\cmd"
set "OS_ARCH=x64"
set "UPDATE_LOGFILE=%SANDBOX%\test_update.log"
call .\InstallOSUpdate.cmd "..\w100-x64\glb\windows11.0-kb9999999-x64.cab" /verify /errorsaswarnings > "%SANDBOX%\scen2.log" 2>&1
popd

if not exist "%TEMP%\wou_corrupt_updates.txt" (
  echo FAIL Scenario 2: wou_corrupt_updates.txt was not created for missing hash.
  goto TestFailed
)
%SystemRoot%\System32\findstr.exe /I /C:"windows11.0-kb9999999-x64.cab" "%TEMP%\wou_corrupt_updates.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 2: Missing hash update not listed in wou_corrupt_updates.txt.
  goto TestFailed
)
if exist "%TEMP%\wou_installed_updates.txt" (
  %SystemRoot%\System32\findstr.exe /I /C:"windows11.0-kb9999999-x64.cab" "%TEMP%\wou_installed_updates.txt" >nul 2>&1
  if not errorlevel 1 (
    echo FAIL Scenario 2: Unverified core update was marked installed!
    goto TestFailed
  )
)
%SystemRoot%\System32\findstr.exe /I /C:"skipping installation (fail-closed)" "%SANDBOX%\scen2.log" >nul 2>&1
if errorlevel 1 (
  %SystemRoot%\System32\findstr.exe /I /C:"skipping installation (fail-closed)" "%SANDBOX%\test_update.log" >nul 2>&1
  if errorlevel 1 (
    echo FAIL Scenario 2: Log output missing skipping installation fail-closed message.
    goto TestFailed
  )
)
echo [PASS] Scenario 2: Core OS missing hash fails closed.

REM =======================================================================
REM Scenario 3: Standalone installer with missing hash in hash file
REM =======================================================================
echo Running Scenario 3: Standalone installer with missing hash in hash file...
call :CleanMarkers
echo dummy msi > "%SANDBOX%\client\msedge\MicrosoftEdgeEnterpriseX64.msi"
(
  echo %%%% HASHDEEP-1.0
  echo %%%% size,md5,sha256,filename
) > "%SANDBOX%\client\md\hashes-msedge.txt"

pushd "%SANDBOX%\client\cmd"
set "OS_ARCH=x64"
set "UPDATE_LOGFILE=%SANDBOX%\test_update.log"
call .\InstallOSUpdate.cmd "..\msedge\MicrosoftEdgeEnterpriseX64.msi" /verify /errorsaswarnings > "%SANDBOX%\scen3.log" 2>&1
popd

if not exist "%TEMP%\wou_verification_skipped.txt" (
  echo FAIL Scenario 3: wou_verification_skipped.txt was not created.
  goto TestFailed
)
%SystemRoot%\System32\findstr.exe /I /C:"MicrosoftEdgeEnterpriseX64.msi" "%TEMP%\wou_verification_skipped.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 3: wou_verification_skipped.txt missing standalone installer path.
  goto TestFailed
)
if exist "%TEMP%\wou_corrupt_updates.txt" (
  %SystemRoot%\System32\findstr.exe /I /C:"MicrosoftEdgeEnterpriseX64.msi" "%TEMP%\wou_corrupt_updates.txt" >nul 2>&1
  if not errorlevel 1 (
    echo FAIL Scenario 3: Standalone installer without hash was treated as corrupt!
    goto TestFailed
  )
)
%SystemRoot%\System32\findstr.exe /I /C:"skipping verification" "%SANDBOX%\scen3.log" >nul 2>&1
if errorlevel 1 (
  %SystemRoot%\System32\findstr.exe /I /C:"skipping verification" "%SANDBOX%\test_update.log" >nul 2>&1
  if errorlevel 1 (
    echo FAIL Scenario 3: Log output missing skipping verification.
    goto TestFailed
  )
)
echo [PASS] Scenario 3: Standalone installer missing hash bypasses verification with warning.

REM =======================================================================
REM Scenario 4: Standalone installer with corrupted hash
REM =======================================================================
echo Running Scenario 4: Standalone installer with corrupted hash...
call :CleanMarkers
(
  echo %%%% HASHDEEP-1.0
  echo %%%% size,md5,sha256,filename
  echo ##
  echo 999,00000000000000000000000000000000,0000000000000000000000000000000000000000000000000000000000000000,MicrosoftEdgeEnterpriseX64.msi
) > "%SANDBOX%\client\md\hashes-msedge.txt"

pushd "%SANDBOX%\client\cmd"
set "OS_ARCH=x64"
set "UPDATE_LOGFILE=%SANDBOX%\test_update.log"
call .\InstallOSUpdate.cmd "..\msedge\MicrosoftEdgeEnterpriseX64.msi" /verify /errorsaswarnings > "%SANDBOX%\scen4.log" 2>&1
popd

if not exist "%TEMP%\wou_corrupt_updates.txt" (
  echo FAIL Scenario 4: wou_corrupt_updates.txt was not created for corrupted standalone installer.
  goto TestFailed
)
%SystemRoot%\System32\findstr.exe /I /C:"MicrosoftEdgeEnterpriseX64.msi" "%TEMP%\wou_corrupt_updates.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 4: Corrupted standalone installer not listed in wou_corrupt_updates.txt.
  goto TestFailed
)
if exist "%TEMP%\wou_installed_updates.txt" (
  %SystemRoot%\System32\findstr.exe /I /C:"MicrosoftEdgeEnterpriseX64.msi" "%TEMP%\wou_installed_updates.txt" >nul 2>&1
  if not errorlevel 1 (
    echo FAIL Scenario 4: Corrupted standalone installer was marked installed!
    goto TestFailed
  )
)
echo [PASS] Scenario 4: Standalone installer corrupted hash fails closed.

REM =======================================================================
REM Scenario 5: DoUpdate Run Report generation
REM =======================================================================
echo Running Scenario 5: DoUpdate Run Report generation...
call :CleanMarkers
echo ..\w100-x64\glb\windows11.0-kb5054156-x64.cab>"%TEMP%\wou_corrupt_updates.txt"
echo ..\msedge\MicrosoftEdgeEnterpriseX64.msi>"%TEMP%\wou_verification_skipped.txt"
echo ..\w100-x64\glb\windows11.0-kb1234567-x64.cab>"%TEMP%\wou_installed_updates.txt"

pushd "%SANDBOX%\client\cmd"
call .\DoUpdate.cmd /reportonly > "%SANDBOX%\scen5.log" 2>&1
popd

%SystemRoot%\System32\findstr.exe /C:"WSUS Offline Update - Installation Run Report" "%SANDBOX%\scen5.log" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 5: Missing Run Report header.
  goto TestFailed
)
%SystemRoot%\System32\findstr.exe /C:"Updates Evaluated:          2" "%SANDBOX%\scen5.log" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 5: Updates Evaluated count mismatch.
  type "%SANDBOX%\scen5.log"
  goto TestFailed
)
%SystemRoot%\System32\findstr.exe /C:"Updates Installed:          1" "%SANDBOX%\scen5.log" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 5: Updates Installed count mismatch.
  goto TestFailed
)
%SystemRoot%\System32\findstr.exe /C:"Updates Skipped (Clean):    0" "%SANDBOX%\scen5.log" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 5: Updates Skipped Clean count mismatch.
  goto TestFailed
)
%SystemRoot%\System32\findstr.exe /C:"Updates Skipped (Corrupt):  1" "%SANDBOX%\scen5.log" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 5: Updates Skipped Corrupt count mismatch.
  goto TestFailed
)
%SystemRoot%\System32\findstr.exe /C:"Updates Verification Skip:  1" "%SANDBOX%\scen5.log" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 5: Updates Verification Skip count mismatch.
  goto TestFailed
)
%SystemRoot%\System32\findstr.exe /C:"windows11.0-kb5054156-x64.cab" "%SANDBOX%\scen5.log" >nul 2>&1
if errorlevel 1 (
  echo FAIL Scenario 5: Corrupt update filename not listed in report.
  goto TestFailed
)
if exist "%TEMP%\wou_corrupt_updates.txt" (
  echo FAIL Scenario 5: Temporary report tracking files were not cleaned up.
  goto TestFailed
)
echo [PASS] Scenario 5: DoUpdate Run Report correctly formatted and tracked.

echo.
echo =======================================================================
echo SUCCESS: All 5 integrity fail-closed and run report scenarios passed.
echo =======================================================================
call :Cleanup
exit /b 0

:TestFailed
echo.
echo ERROR: Integrity fail-closed verification suite failed.
call :Cleanup
exit /b 1

:CleanMarkers
if exist "%TEMP%\wou_corrupt_updates.txt" del "%TEMP%\wou_corrupt_updates.txt" 2>nul
if exist "%TEMP%\wou_verification_skipped.txt" del "%TEMP%\wou_verification_skipped.txt" 2>nul
if exist "%TEMP%\wou_installed_updates.txt" del "%TEMP%\wou_installed_updates.txt" 2>nul
if exist "%TEMP%\wou_clean_skipped_updates.txt" del "%TEMP%\wou_clean_skipped_updates.txt" 2>nul
if exist "%TEMP%\wou_failed_updates.txt" del "%TEMP%\wou_failed_updates.txt" 2>nul
if exist "%TEMP%\wou_run_report.txt" del "%TEMP%\wou_run_report.txt" 2>nul
goto :eof

:Cleanup
call :CleanMarkers
if exist "%SANDBOX%" rd /s /q "%SANDBOX%" >nul 2>&1
goto :eof
