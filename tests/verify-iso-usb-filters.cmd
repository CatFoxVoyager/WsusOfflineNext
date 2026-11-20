@echo off
rem Regression gate for issue #38:
rem Ensures every OS target supported by CreateISOImage.cmd and CopyToTarget.cmd
rem resolves an ISO and USB exclusion list in both exclude\ and sh\exclude\,
rem that DownloadUpdates.cmd never self-deletes legacy exclude lists, and that
rem CreateISOImage.cmd / CopyToTarget.cmd fail closed on a missing filter.
setlocal enableextensions enabledelayedexpansion

set "REPO_ROOT=%~dp0.."
set "FAIL=0"

echo =======================================================================
echo WSUS Offline Next - ISO/USB Exclusion Filter Verification (Issue #38)
echo =======================================================================

echo [1/5] Checking Windows ISO/USB exclude lists for all supported targets...
for %%t in (all all-x86 all-x64 wxp w60 w60-x64 w61 w61-x64 w62-x64 w63 w63-x64 w100 w100-x64 o2k16) do (
  set "ISO_OK=0"
  if exist "%REPO_ROOT%\exclude\ExcludeListISO-%%t.txt" set "ISO_OK=1"
  if exist "%REPO_ROOT%\exclude\ExcludeListISO-%%t-x86.txt" set "ISO_OK=1"
  if "!ISO_OK!"=="0" (
    echo [FAIL] Missing Windows ISO exclude list for target %%t
    set "FAIL=1"
  )
  set "USB_OK=0"
  if exist "%REPO_ROOT%\exclude\ExcludeListUSB-%%t.txt" set "USB_OK=1"
  if exist "%REPO_ROOT%\exclude\ExcludeListUSB-%%t-x86.txt" set "USB_OK=1"
  if "!USB_OK!"=="0" (
    echo [FAIL] Missing Windows USB exclude list for target %%t
    set "FAIL=1"
  )
)
if "%FAIL%"=="0" echo [PASS] All 14 Windows ISO and USB exclude lists present.

echo [2/5] Checking Bash ISO/USB exclude lists in sh\exclude\...
for %%t in (wxp w60 w60-x64 w61 w61-x64 w62-x64 w63 w63-x64 w100 w100-x64 o2k16) do (
  if not exist "%REPO_ROOT%\sh\exclude\ExcludeListISO-%%t.txt" (
    echo [FAIL] Missing sh\exclude\ExcludeListISO-%%t.txt
    set "FAIL=1"
  )
  if not exist "%REPO_ROOT%\sh\exclude\ExcludeListUSB-%%t.txt" (
    echo [FAIL] Missing sh\exclude\ExcludeListUSB-%%t.txt
    set "FAIL=1"
  )
)
if "%FAIL%"=="0" echo [PASS] All Bash ISO and USB exclude lists present.

echo [3/5] Verifying w61-x64 filter excludes sibling OSes and keeps w61-x64...
for %%p in ("*w63*" "*w100*" "*/w61/*" "*/upgrade/*") do (
  %SystemRoot%\System32\findstr.exe /L /X /C:%%p "%REPO_ROOT%\exclude\ExcludeListISO-w61-x64.txt" >nul 2>&1
  if errorlevel 1 (
    echo [FAIL] ExcludeListISO-w61-x64.txt missing required pattern %%~p
    set "FAIL=1"
  )
)
%SystemRoot%\System32\findstr.exe /L /X /C:"*w61*" "%REPO_ROOT%\exclude\ExcludeListISO-w61-x64.txt" >nul 2>&1
if not errorlevel 1 (
  echo [FAIL] ExcludeListISO-w61-x64.txt contains broad *w61* which would exclude w61-x64 itself
  set "FAIL=1"
)
for %%p in ("w63-x64\\" "w100-x64\\" "w61\\" "upgrade\\") do (
  %SystemRoot%\System32\findstr.exe /L /X /C:%%p "%REPO_ROOT%\exclude\ExcludeListUSB-w61-x64.txt" >nul 2>&1
  if errorlevel 1 (
    echo [FAIL] ExcludeListUSB-w61-x64.txt missing required pattern %%~p
    set "FAIL=1"
  )
)
%SystemRoot%\System32\findstr.exe /L /X /C:"w61-x64\\" "%REPO_ROOT%\exclude\ExcludeListUSB-w61-x64.txt" >nul 2>&1
if not errorlevel 1 (
  echo [FAIL] ExcludeListUSB-w61-x64.txt excludes w61-x64 itself
  set "FAIL=1"
)
if "%FAIL%"=="0" echo [PASS] w61-x64 ISO and USB filters exclude sibling OSes and retain w61-x64.

echo [4/5] Verifying DownloadUpdates.cmd no longer deletes legacy exclude lists...
for %%n in (ExcludeListISO-w61 ExcludeListUSB-w61 ExcludeListISO-w60 ExcludeListUSB-w60 ExcludeListISO-wxp ExcludeListUSB-wxp) do (
  %SystemRoot%\System32\findstr.exe /I /C:"del ..\exclude\%%n" "%REPO_ROOT%\cmd\DownloadUpdates.cmd" >nul 2>&1
  if not errorlevel 1 (
    echo [FAIL] DownloadUpdates.cmd still deletes %%n
    set "FAIL=1"
  )
)
if "%FAIL%"=="0" echo [PASS] DownloadUpdates.cmd preserves wxp/w60/w61 ISO and USB exclude lists.

echo [5/5] Verifying CreateISOImage.cmd and CopyToTarget.cmd fail-closed on missing filter...
%SystemRoot%\System32\findstr.exe /I /C:"ERROR: Exclusion list ..\exclude\ExcludeListISO-%%1.txt not found." "%REPO_ROOT%\cmd\CreateISOImage.cmd" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] CreateISOImage.cmd missing fail-closed error branch in :CopyFilter
  set "FAIL=1"
)
%SystemRoot%\System32\findstr.exe /I /C:"ERROR: Exclusion list ..\exclude\ExcludeListUSB-%%1.txt not found." "%REPO_ROOT%\cmd\CopyToTarget.cmd" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] CopyToTarget.cmd missing fail-closed error branch in :CopyFilter
  set "FAIL=1"
)

rem Live can-fail proof in a scratch sandbox (missing ExcludeListISO-w61-x64.txt must fail non-zero)
set "SBX=%TEMP%\wou-iso-filter-test-%RANDOM%"
mkdir "%SBX%\cmd" "%SBX%\exclude" "%SBX%\log" "%SBX%\iso" "%SBX%\client" >nul 2>&1
copy /Y "%REPO_ROOT%\cmd\CreateISOImage.cmd" "%SBX%\cmd\CreateISOImage.cmd" >nul
copy /Y "%REPO_ROOT%\cmd\CopyToTarget.cmd" "%SBX%\cmd\CopyToTarget.cmd" >nul
call "%SBX%\cmd\CreateISOImage.cmd" w61-x64 glb >"%SBX%\iso_out.txt" 2>&1
set "ISO_MISSING_RC=!errorlevel!"
if "!ISO_MISSING_RC!"=="0" (
  echo [FAIL] CreateISOImage.cmd returned 0 when ExcludeListISO-w61-x64.txt was absent
  set "FAIL=1"
)
%SystemRoot%\System32\findstr.exe /I /C:"ERROR: Exclusion list" "%SBX%\iso_out.txt" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] CreateISOImage.cmd did not emit named missing-filter error
  set "FAIL=1"
)
call "%SBX%\cmd\CopyToTarget.cmd" w61-x64 glb "%SBX%\usbout" >"%SBX%\usb_out.txt" 2>&1
set "USB_MISSING_RC=!errorlevel!"
if "!USB_MISSING_RC!"=="0" (
  echo [FAIL] CopyToTarget.cmd returned 0 when ExcludeListUSB-w61-x64.txt was absent
  set "FAIL=1"
)
%SystemRoot%\System32\findstr.exe /I /C:"ERROR: Exclusion list" "%SBX%\usb_out.txt" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] CopyToTarget.cmd did not emit named missing-filter error
  set "FAIL=1"
)
rd /S /Q "%SBX%" >nul 2>&1
if "%FAIL%"=="0" echo [PASS] Fail-closed sandbox proof succeeded (ISO rc=!ISO_MISSING_RC!, USB rc=!USB_MISSING_RC!).

echo.
if "%FAIL%"=="0" (
  echo =======================================================================
  echo ISO-USB-FILTERS-PASS: all 5 verification checks green.
  echo =======================================================================
  exit /b 0
) else (
  echo =======================================================================
  echo ISO-USB-FILTERS-FAIL: one or more checks failed.
  echo =======================================================================
  exit /b 1
)
