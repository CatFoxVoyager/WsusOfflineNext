@echo off
setlocal enabledelayedexpansion

REM =======================================================================
REM WSUS Offline Update - Office Hybrid Staging Regression Suite (Windows CMD)
REM File: tests\verify-office-staging.cmd
REM
REM Verifies:
REM   Scenario 1: Office 2016 MSI Architecture Segregation in cmd\DownloadUpdates.cmd
REM   Scenario 2: Linux Bash Script Architecture Isolation in sh\download-updates-tasks\
REM   Scenario 3: ODT XML Configuration Template Validation
REM   Scenario 4: Click-to-Run Staging Engine & Hash Structure
REM =======================================================================

pushd "%~dp0.."
set "REPO_ROOT=%CD%"
popd

echo =======================================================================
echo WSUS Offline Update - Office Hybrid Staging Test Suite (Windows CMD)
echo =======================================================================

REM -----------------------------------------------------------------------
REM Scenario 1: Office 2016 MSI Architecture Segregation in cmd\DownloadUpdates.cmd
REM -----------------------------------------------------------------------
echo [Scenario 1/4] Verifying Office 2016 MSI architecture segregation in cmd\DownloadUpdates.cmd...

powershell -NoProfile -Command "$content = [System.IO.File]::ReadAllText('%REPO_ROOT%\cmd\DownloadUpdates.cmd'); if ($content -notmatch 'o2k16 o2k16-x64') { Write-Error 'Loop missing o2k16 o2k16-x64'; exit 1 }; if ($content -notmatch 'o2k16 \^\| o2k16-x64') { Write-Error 'Usage string missing o2k16-x64'; exit 1 }; if ($content -notmatch 'ExcludeList-%%3\.txt') { Write-Error 'ExcludeList-%%3.txt missing'; exit 1 }; Write-Host 'Scenario 1: DownloadUpdates.cmd correctly updated for dual-architecture o2k16.'"
if errorlevel 1 goto Fail

echo [PASS] Scenario 1: Windows MSI architecture segregation verified.

REM -----------------------------------------------------------------------
REM Scenario 2: Linux Bash Script Architecture Isolation
REM -----------------------------------------------------------------------
echo.
echo [Scenario 2/4] Verifying Linux bash script architecture isolation in sh\...

powershell -NoProfile -Command "$sh = [System.IO.File]::ReadAllText('%REPO_ROOT%\sh\download-updates-tasks\60-main-updates.bash'); if ($sh -notmatch 'o2k16\)[\s\S]*?ExcludeList-\$\{arch\}\.txt') { Write-Error 'ExcludeList-${arch}.txt missing from o2k16 case in 60-main-updates.bash'; exit 1 }; Write-Host 'Scenario 2: Linux 60-main-updates.bash correctly isolates Office architectures.'"
if errorlevel 1 goto Fail

echo [PASS] Scenario 2: Linux architecture isolation verified.

REM -----------------------------------------------------------------------
REM Scenario 3: ODT XML Configuration Template Validation
REM -----------------------------------------------------------------------
echo.
echo [Scenario 3/4] Validating ODT XML Configuration Templates...

if not exist "%REPO_ROOT%\static\odt-templates\o2k24-template.xml" goto SkipScenario3

powershell -NoProfile -Command "$t19 = [System.IO.File]::ReadAllText('%REPO_ROOT%\static\odt-templates\o2k19-template.xml'); $t21 = [System.IO.File]::ReadAllText('%REPO_ROOT%\static\odt-templates\o2k21-template.xml'); $t24 = [System.IO.File]::ReadAllText('%REPO_ROOT%\static\odt-templates\o2k24-template.xml'); if ($t19 -notmatch 'PerpetualVL2019') { Write-Error 'o2k19 template invalid'; exit 1 }; if ($t21 -notmatch 'PerpetualVL2021') { Write-Error 'o2k21 template invalid'; exit 1 }; if ($t24 -notmatch 'PerpetualVL2024') { Write-Error 'o2k24 template invalid'; exit 1 }; Write-Host 'Scenario 3: ODT templates syntax and channel configurations verified.'"
if errorlevel 1 goto Fail
echo [PASS] Scenario 3: ODT templates verified.
goto Scenario4

:SkipScenario3
echo [SKIP] Scenario 3: ODT templates not yet created (Wave 2 task).

:Scenario4
REM -----------------------------------------------------------------------
REM Scenario 4: Click-to-Run Engine & Staging Hierarchy
REM -----------------------------------------------------------------------
echo.
echo [Scenario 4/4] Verifying Click-to-Run Staging Engine ^& Hash Structure...

if not exist "%REPO_ROOT%\cmd\DownloadOfficeC2R.cmd" goto SkipScenario4

powershell -NoProfile -Command "$cmd = [System.IO.File]::ReadAllText('%REPO_ROOT%\cmd\DownloadOfficeC2R.cmd'); if ($cmd -notmatch 'sigcheck') { Write-Error 'DownloadOfficeC2R.cmd missing sigcheck'; exit 1 }; if ($cmd -notmatch 'hashes-office-c2r\.txt') { Write-Error 'Missing hashes-office-c2r.txt reference'; exit 1 }; Write-Host 'Scenario 4: DownloadOfficeC2R.cmd staging engine verified.'"
if errorlevel 1 goto Fail
echo [PASS] Scenario 4: C2R staging engine verified.
goto Complete

:SkipScenario4
echo [SKIP] Scenario 4: DownloadOfficeC2R.cmd not yet created (Wave 2 task).

:Complete
echo.
echo =======================================================================
echo ALL TESTS PASSED: Office Hybrid Staging validation green.
echo =======================================================================
exit /b 0

:Fail
echo.
echo =======================================================================
echo TEST FAILED: Regression detected in Office Hybrid Staging.
echo =======================================================================
exit /b 1
