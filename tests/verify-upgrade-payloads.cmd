@echo off
setlocal enabledelayedexpansion

REM =======================================================================
REM WSUS Offline Update - UUP Upgrade Payload Acquisition Battery (CMD)
REM File: tests\verify-upgrade-payloads.cmd
REM
REM Plan 33-03 task 1 battery (ACQ-02 + the sha256 half of ACQ-04): the
REM subroutines of cmd\UpgradePayloads.cmd, called directly through the
REM entry dispatch. Sandbox only - NO network, NO API calls, NO real
REM downloader: the downloaders are sandbox no-op stubs and the payload
REM bytes are locally generated fixture files. Every case below is a
REM can-fail bite: the corrupt/truncated/failing-stub cases assert nonzero
REM exits, and the cleanup cases assert the token-bearing TEMP artifacts
REM are gone after the run.
REM
REM   Case 1: :UpgClassifySize boundaries - 104857600 -> aria2 (exactly at),
REM           104857599 -> wget (one below), 10902883408 -> aria2 (the
REM           11-digit value that silently wraps signed 32-bit arithmetic),
REM           99 -> wget, abc -> refused (exit 2)
REM   Case 2: :UpgReadFuMedia over a sandbox copy of the committed
REM           upgrades.txt - 26200/x64 answers 1, 19045/x64 answers 0,
REM           an unknown build exits 1
REM   Case 3: :UpgBudgetLine - the fixture manifest's total_mib figure and
REM           row count appear on the BUDGET line
REM   Case 4: :UpgHashGate positive - fixture spool matching the fixture
REM           manifest passes (hashdeep Audit passed)
REM   Case 5: :UpgHashGate corrupt - one byte flipped in a scratch copy is
REM           refused, nothing moved
REM   Case 6: :UpgHashGate truncated - a shortened fixture file is refused
REM   Case 7: :UpgAcquire orchestration - fixture url map + pre-placed
REM           spool + succeeding stubs: budget line precedes the download,
REM           the hash gate runs, the spool files stay in place, and the
REM           token-bearing TEMP artifacts (url map + downloader lists) are
REM           deleted afterwards
REM   Case 8: DEC-33-15 https-first/http-fallback - a stub that refuses
REM           https URLs still ends green through the bounded http retry
REM   Case 9: fail-path cleanup - a stub that fails both schemes aborts
REM           loudly AND the url map is deleted (cleanup on the failure
REM           path too)
REM
REM Plan 33-04 cases (assembly + staging + purge), appended, existing
REM cases untouched:
REM   Case 10: :UpgAssembleMedia positive - stub wimlib over a 2-edition
REM           fixture spool, matching SHA256SUMS pins, census + scaffold +
REM           boot.wim + exclusion-pattern cab skip
REM   Case 11: tampered vendored-tool pin = fail-closed refusal, nothing
REM           staged (T-33-SC)
REM   Case 12: failing stub export = loud refusal, stage dir cleaned
REM   Case 12b: boot.wim emission can-fail pair (the live-UAT 2026-11-11
REM           finding: setup.exe refuses a boot.wim-less scaffold with
REM           0x80070002) - a stub refusing the boot.wim export refuses the
REM           assembly; a stub whose info fails on boot.wim (corrupt
REM           census) refuses the assembly; stage cleaned both ways
REM   Case 13: :UpgAuthenticodeGate trio - Signed stub passes, Unsigned
REM           .exe row refuses, .mui convention row allowed and counted
REM   Case 14: staging-order - a corrupted spool fails the hash gate
REM           BEFORE the Authenticode scan or any move (gate order, T-33-12)
REM   Case 15: revision replacement - old revision aside in the spool and
REM           deleted ONLY after the new media reads back (delete-after-
REM           success)
REM   Case 16: :UpgPurgeRevisions trio - sole revision 0 removals / stale
REM           pair removed exactly while the staged-uuid keep set survives /
REM           failed-staging simulation removes nothing
REM   Case 17: :UpgCreateMediaDb - the staged fixture produces the db file
REM           carrying the hashdeep header
REM
REM NOTE (DEC-33-13 supersession): the assembly runs the VENDORED wimlib
REM (owner decision 2026-11-11), a userspace tool - there is NO elevation
REM and NO RunAs prompt anywhere in this pipeline. The fail-closed refusal
REM discipline the elevation policy protected (nothing staged on a failed
REM gate) is proven by cases 11/12/14 instead.
REM
REM Fixture hashes are pinned constants for fixed byte strings: big.esd is
REM 104857600 zero bytes (created with fsutil, exactly at the aria2/wget
REM threshold), small.cab is 100 B's + CRLF. The committed upgrades.txt is
REM only ever COPIED into the sandbox - never mutated.
REM =======================================================================

pushd "%~dp0.."
set "REPO_ROOT=%CD%"
popd

echo =======================================================================
echo WSUS Offline Update - UUP Upgrade Payload Acquisition Battery (CMD)
echo =======================================================================

set "SANDBOX=%TEMP%\wou_test_upg_%RANDOM%_%RANDOM%"
set "SB_FIX=%SANDBOX%\fixtures"
set "SB_STUBS=%SANDBOX%\stubs"
set "SB_OUT=%SANDBOX%\out"
mkdir "%SB_FIX%" 2>nul
mkdir "%SB_STUBS%" 2>nul
mkdir "%SB_OUT%" 2>nul
if not exist "%SB_OUT%" (
  echo ERROR: Failed to create the test sandbox at "%SANDBOX%".
  exit /b 1
)

rem The library under test - called through the entry dispatch
set "LIB=cmd\UpgradePayloads.cmd"

rem The downloader binaries are sandbox stubs for every :UpgAcquire case
set "UUP_ARIA2_PATH=%SB_STUBS%\aria2-stub.cmd"
set "UUP_WGET_PATH=%SB_STUBS%\wget-stub.cmd"
set "UUP_ARIA2_FETCH=0"

rem -----------------------------------------------------------------------
rem Fixture payloads + pinned manifest
rem -----------------------------------------------------------------------
set "BIG=%SB_FIX%\big.esd"
set "SMALL=%SB_FIX%\small.cab"
fsutil file createnew "%BIG%" 104857600 >nul 2>&1
if not exist "%BIG%" (
  echo ERROR: Failed to create the 104857600-byte fixture payload.
  goto Fail
)
for /F %%F in ("%BIG%") do set "BIG_SIZE=%%~zF"
if not "%BIG_SIZE%"=="104857600" (
  echo ERROR: big.esd fixture size is %BIG_SIZE%, expected 104857600.
  goto Fail
)
set "SB100="
for /L %%i in (1,1,100) do set "SB100=!SB100!B"
>"%SMALL%" echo !SB100!
for /F %%F in ("%SMALL%") do set "SMALL_SIZE=%%~zF"
if not "%SMALL_SIZE%"=="102" (
  echo ERROR: small.cab fixture size is %SMALL_SIZE%, expected 102.
  goto Fail
)

rem Fixture manifest (DEC-33-02 shape): 2 payload rows, self-consistent
rem totals (104857600 + 102 = 104857702 bytes; int(104857702/1048576) = 99)
set "MANIFEST=%SB_FIX%\manifest.txt"
set "H_BIG=20492a4d0d84f8beb1767f6616229f85d44c2827b64bdbfb260ee12fa1109e0e"
set "H_SMALL=5e12acba512f827c7ee243b2cd25be1291caed73325eae3b9b1818e84febd874"
>"%MANIFEST%" echo # fixture acquisition manifest for the plan 33-03 battery
>>"%MANIFEST%" echo updateName^|Battery Test Set
>>"%MANIFEST%" echo uuid^|00000000-0000-0000-0000-000000000000
>>"%MANIFEST%" echo arch^|amd64
>>"%MANIFEST%" echo lang^|en-us
>>"%MANIFEST%" echo build^|26200.9974
>>"%MANIFEST%" echo total_bytes^|104857702
>>"%MANIFEST%" echo total_mib^|99
>>"%MANIFEST%" echo small.cab^|!H_SMALL!^|102
>>"%MANIFEST%" echo big.esd^|!H_BIG!^|104857600

rem Fixture url map: name TAB url (token-shaped, https scheme). The map is
rem a TEMP runtime artifact in the sandbox - never committed.
set "URLMAP=%SB_FIX%\url-map.tmp"
set "TAB=	"
>"%URLMAP%" echo small.cab!TAB!https://tlu.dl.delivery.mp.microsoft.com/filestreamingservice/files/11111111-1111-1111-1111-111111111111?P1=1794420000^&P2=404^&P3=2^&P4=sigsmall
>>"%URLMAP%" echo big.esd!TAB!https://tlu.dl.delivery.mp.microsoft.com/filestreamingservice/files/22222222-2222-2222-2222-222222222222?P1=1794420000^&P2=404^&P3=2^&P4=sigbig

rem Fixture upgrades.txt copy for :UpgReadFuMedia (the committed contract
rem file is only read through this sandbox copy)
set "UPGTAB=%SB_FIX%\upgrades.txt"
copy /y "%REPO_ROOT%\client\UpdateTable\upgrades.txt" "%UPGTAB%" >nul 2>&1
if not exist "%UPGTAB%" (
  echo ERROR: Failed to copy the committed upgrades.txt into the sandbox.
  goto Fail
)

rem TEMP artifact baseline: every :UpgAcquire case must leave the count of
rem wou-upg-* artifacts exactly here (cleanup on every exit path, T-33-09)
call :TempArtifactCount
set "TEMP_BASELINE=%TEMP_COUNT%"

rem -----------------------------------------------------------------------
rem Downloader stubs (sandbox no-ops). Written with delayed expansion
rem DISABLED so the stubs' own !variables! survive the generation.
rem -----------------------------------------------------------------------
setlocal disabledelayedexpansion
>"%SB_STUBS%\aria2-stub.cmd" echo @echo off
>>"%SB_STUBS%\aria2-stub.cmd" echo setlocal enabledelayedexpansion
>>"%SB_STUBS%\aria2-stub.cmd" echo set "STUB_LIST="
>>"%SB_STUBS%\aria2-stub.cmd" echo set "PREV="
>>"%SB_STUBS%\aria2-stub.cmd" echo :stub_loop
>>"%SB_STUBS%\aria2-stub.cmd" echo if "%%~1"=="" goto stub_decide
>>"%SB_STUBS%\aria2-stub.cmd" echo if "%%PREV%%"=="-i" set "STUB_LIST=%%~1"
>>"%SB_STUBS%\aria2-stub.cmd" echo set "PREV=%%~1"
>>"%SB_STUBS%\aria2-stub.cmd" echo shift
>>"%SB_STUBS%\aria2-stub.cmd" echo goto stub_loop
>>"%SB_STUBS%\aria2-stub.cmd" echo :stub_decide
>>"%SB_STUBS%\aria2-stub.cmd" echo if defined STUB_LIST if exist "!STUB_LIST!" findstr /C:"https://" "!STUB_LIST!" ^>nul 2^>^&1
>>"%SB_STUBS%\aria2-stub.cmd" echo if not errorlevel 1 if /i "%%STUB_MODE%%"=="HTTPS-FAILS" exit /b 1
>>"%SB_STUBS%\aria2-stub.cmd" echo if /i "%%STUB_MODE%%"=="ALWAYS-FAILS" exit /b 1
>>"%SB_STUBS%\aria2-stub.cmd" echo echo ARIA2-STUB-DOWNLOAD
>>"%SB_STUBS%\aria2-stub.cmd" echo exit /b 0
>"%SB_STUBS%\wget-stub.cmd" echo @echo off
>>"%SB_STUBS%\wget-stub.cmd" echo setlocal enabledelayedexpansion
>>"%SB_STUBS%\wget-stub.cmd" echo set "STUB_HAS_HTTPS=0"
>>"%SB_STUBS%\wget-stub.cmd" echo :stub_loop
>>"%SB_STUBS%\wget-stub.cmd" echo if "%%~1"=="" goto stub_decide
>>"%SB_STUBS%\wget-stub.cmd" echo set "STUB_ARG=%%~1"
>>"%SB_STUBS%\wget-stub.cmd" echo if not "!STUB_ARG!"=="!STUB_ARG:https://=!" set "STUB_HAS_HTTPS=1"
>>"%SB_STUBS%\wget-stub.cmd" echo shift
>>"%SB_STUBS%\wget-stub.cmd" echo goto stub_loop
>>"%SB_STUBS%\wget-stub.cmd" echo :stub_decide
>>"%SB_STUBS%\wget-stub.cmd" echo if "!STUB_HAS_HTTPS!"=="1" if /i "%%STUB_MODE%%"=="HTTPS-FAILS" exit /b 1
>>"%SB_STUBS%\wget-stub.cmd" echo if /i "%%STUB_MODE%%"=="ALWAYS-FAILS" exit /b 1
>>"%SB_STUBS%\wget-stub.cmd" echo echo WGET-STUB-DOWNLOAD
>>"%SB_STUBS%\wget-stub.cmd" echo exit /b 0
endlocal
if not exist "%SB_STUBS%\aria2-stub.cmd" goto Fail
if not exist "%SB_STUBS%\wget-stub.cmd" goto Fail

rem -----------------------------------------------------------------------
rem Plan 33-04 stubs: the wimlib stub (apply/export/capture/info over
rem fixture files) and the sigcheck stub (CSV rows by mode). Written with
rem delayed expansion DISABLED so the stubs' own %variables% survive.
rem -----------------------------------------------------------------------
setlocal disabledelayedexpansion
>"%SB_STUBS%\wimlib-stub.cmd" echo @echo off
>>"%SB_STUBS%\wimlib-stub.cmd" echo setlocal enabledelayedexpansion
>>"%SB_STUBS%\wimlib-stub.cmd" echo set "STUB_CMD=%%~1"
>>"%SB_STUBS%\wimlib-stub.cmd" echo if /i "%%STUB_CMD%%"=="capture" (
>>"%SB_STUBS%\wimlib-stub.cmd" echo   type nul ^> "%%~3"
>>"%SB_STUBS%\wimlib-stub.cmd" echo   exit /b 0
>>"%SB_STUBS%\wimlib-stub.cmd" echo )
>>"%SB_STUBS%\wimlib-stub.cmd" echo if /i "%%STUB_CMD%%"=="apply" (
>>"%SB_STUBS%\wimlib-stub.cmd" echo   mkdir "%%~4\sources" 2^>nul
>>"%SB_STUBS%\wimlib-stub.cmd" echo   ^>"%%~4\sources\setup.exe" echo STUB-SETUP
>>"%SB_STUBS%\wimlib-stub.cmd" echo   ^>"%%~4\sources\setuphost.exe" echo STUB-SETUPHOST
>>"%SB_STUBS%\wimlib-stub.cmd" echo   exit /b 0
>>"%SB_STUBS%\wimlib-stub.cmd" echo )
>>"%SB_STUBS%\wimlib-stub.cmd" echo if /i "%%STUB_CMD%%"=="export" (
>>"%SB_STUBS%\wimlib-stub.cmd" echo   if /i "%%STUB_WIMLIB_MODE%%"=="EXPORT-FAILS" exit /b 1
>>"%SB_STUBS%\wimlib-stub.cmd" echo   if /i "%%STUB_WIMLIB_MODE%%"=="BOOT-EXPORT-FAILS" if "%%~3"=="1" exit /b 1
>>"%SB_STUBS%\wimlib-stub.cmd" echo   ^>^>"%%~4" echo %%~5
>>"%SB_STUBS%\wimlib-stub.cmd" echo   exit /b 0
>>"%SB_STUBS%\wimlib-stub.cmd" echo )
>>"%SB_STUBS%\wimlib-stub.cmd" echo if /i "%%STUB_CMD%%"=="info" (
>>"%SB_STUBS%\wimlib-stub.cmd" echo   if /i "%%STUB_WIMLIB_MODE%%"=="BOOT-INFO-FAILS" if /i "%%~nx2"=="boot.wim" exit /b 1
>>"%SB_STUBS%\wimlib-stub.cmd" echo   if /i "%%~4"=="--image-property" (
>>"%SB_STUBS%\wimlib-stub.cmd" echo     if /i "%%STUB_WIMLIB_MODE%%"=="FLAG-SET-FAILS" exit /b 1
>>"%SB_STUBS%\wimlib-stub.cmd" echo     if not "%%STUB_WIMLIB_MODE%%"=="FLAG-NO-SET" ^>"%%~2.flag9" echo 9
>>"%SB_STUBS%\wimlib-stub.cmd" echo     echo Setting the FLAGS property of image %%~3 to "9".
>>"%SB_STUBS%\wimlib-stub.cmd" echo     exit /b 0
>>"%SB_STUBS%\wimlib-stub.cmd" echo   )
>>"%SB_STUBS%\wimlib-stub.cmd" echo   if "%%~3"=="" (
>>"%SB_STUBS%\wimlib-stub.cmd" echo     set /a STUB_N=0
>>"%SB_STUBS%\wimlib-stub.cmd" echo     for /F "usebackq delims=" %%%%L in ("%%~2") do set /a STUB_N+=1
>>"%SB_STUBS%\wimlib-stub.cmd" echo     echo WIM header
>>"%SB_STUBS%\wimlib-stub.cmd" echo     echo Image Count: !STUB_N!
>>"%SB_STUBS%\wimlib-stub.cmd" echo     if exist "%%~2.flag9" echo Flags: 9
>>"%SB_STUBS%\wimlib-stub.cmd" echo     exit /b 0
>>"%SB_STUBS%\wimlib-stub.cmd" echo   )
>>"%SB_STUBS%\wimlib-stub.cmd" echo   for /F "delims=_-" %%%%x in ("%%~nx2") do echo Edition ID: %%%%x
>>"%SB_STUBS%\wimlib-stub.cmd" echo   exit /b 0
>>"%SB_STUBS%\wimlib-stub.cmd" echo )
>>"%SB_STUBS%\wimlib-stub.cmd" echo exit /b 1
>"%SB_STUBS%\sigcheck-stub.cmd" echo @echo off
>>"%SB_STUBS%\sigcheck-stub.cmd" echo type nul ^> "%%TEMP%%\wou-upg-sigcheck-stub-invoked"
>>"%SB_STUBS%\sigcheck-stub.cmd" echo if /i "%%UUP_STUB_SIGCHECK_MODE%%"=="UNSIGNED-MUI" (
>>"%SB_STUBS%\sigcheck-stub.cmd" echo   echo "Path","Company","Product","Version","Unsigned"
>>"%SB_STUBS%\sigcheck-stub.cmd" echo   echo "D:\stage\sources\en-us\helper.mui","Microsoft","Resources","","Unsigned"
>>"%SB_STUBS%\sigcheck-stub.cmd" echo   echo "D:\stage\sources\replacementmanifests\diskmonmigplugin.dll","Microsoft","Migration","","Unsigned"
>>"%SB_STUBS%\sigcheck-stub.cmd" echo   exit /b 0
>>"%SB_STUBS%\sigcheck-stub.cmd" echo )
>>"%SB_STUBS%\sigcheck-stub.cmd" echo if /i "%%UUP_STUB_SIGCHECK_MODE%%"=="UNSIGNED-EXE" (
>>"%SB_STUBS%\sigcheck-stub.cmd" echo   echo "Path","Company","Product","Version","Unsigned"
>>"%SB_STUBS%\sigcheck-stub.cmd" echo   echo "D:\stage\sources\evil.exe","Evil","Bad","","Unsigned"
>>"%SB_STUBS%\sigcheck-stub.cmd" echo   exit /b 0
>>"%SB_STUBS%\sigcheck-stub.cmd" echo )
>>"%SB_STUBS%\sigcheck-stub.cmd" echo echo "Path","Company","Product","Version","Signed"
>>"%SB_STUBS%\sigcheck-stub.cmd" echo echo "D:\stage\sources\setup.exe","Microsoft","Setup","","Signed"
>>"%SB_STUBS%\sigcheck-stub.cmd" echo exit /b 0
endlocal
if not exist "%SB_STUBS%\wimlib-stub.cmd" goto Fail
if not exist "%SB_STUBS%\sigcheck-stub.cmd" goto Fail

rem The wimlib stub's true SHA256 for the matching-pin sidecar (the
rem fail-closed verification computes certutil hashes - the sidecar here
rem must carry the stub's real digest)
set "STUB_WIMLIB=%SB_STUBS%\wimlib-stub.cmd"
set "STUB_WIMLIB_HASH="
for /F "skip=1 delims=" %%h in ('certutil -hashfile "%STUB_WIMLIB%" SHA256 2^>nul') do if not defined STUB_WIMLIB_HASH set "STUB_WIMLIB_HASH=%%h"
set "STUB_WIMLIB_HASH=%STUB_WIMLIB_HASH: =%"
if not defined STUB_WIMLIB_HASH (
  echo ERROR: certutil produced no hash for the wimlib stub.
  goto Fail
)

echo --- Case 1: :UpgClassifySize boundaries (string compare, no set /a) ---
call :AnswerOf :UpgClassifySize 104857600
if not "%ANS_OUT%"=="aria2" (echo FAIL: 104857600 must classify aria2 ^(exactly at the threshold^), got "%ANS_OUT%" & goto Fail)
call :AnswerOf :UpgClassifySize 104857599
if not "%ANS_OUT%"=="wget" (echo FAIL: 104857599 must classify wget ^(one below the threshold^), got "%ANS_OUT%" & goto Fail)
call :AnswerOf :UpgClassifySize 10902883408
if not "%ANS_OUT%"=="aria2" (echo FAIL: the 11-digit 10902883408 total must classify aria2 ^(big-number compare; signed 32-bit arithmetic would wrap it^), got "%ANS_OUT%" & goto Fail)
call :AnswerOf :UpgClassifySize 99
if not "%ANS_OUT%"=="wget" (echo FAIL: 99 must classify wget, got "%ANS_OUT%" & goto Fail)
call cmd\UpgradePayloads.cmd :UpgClassifySize abc >"%SB_OUT%\cs-bad.out" 2>&1
set "CS_BAD_RC=!errorlevel!"
if not "%CS_BAD_RC%"=="2" (echo FAIL: a non-numeric size must be refused with exit 2, got %CS_BAD_RC% & goto Fail)
echo PASS: case 1 - classification boundaries correct, 11-digit value safe.

echo --- Case 2: :UpgReadFuMedia over the fixture upgrades.txt copy ---
call :AnswerOfEx :UpgReadFuMedia 26200 x64 "%UPGTAB%"
if not "%ANS_RC%"=="0" (echo FAIL: the 26200 x64 row must answer with exit 0, got %ANS_RC% & goto Fail)
if not "%ANS_OUT%"=="1" (echo FAIL: the 26200 x64 row must answer fu_media=1, got "%ANS_OUT%" & goto Fail)
call :AnswerOfEx :UpgReadFuMedia 19045 x64 "%UPGTAB%"
if not "%ANS_RC%"=="0" (echo FAIL: the 19045 x64 row must answer with exit 0, got %ANS_RC% & goto Fail)
if not "%ANS_OUT%"=="0" (echo FAIL: the 19045 x64 row must answer fu_media=0, got "%ANS_OUT%" & goto Fail)
call cmd\UpgradePayloads.cmd :UpgReadFuMedia 99999 x64 "%UPGTAB%" >nul 2>&1
set "FM_UNKNOWN_RC=!errorlevel!"
if not "%FM_UNKNOWN_RC%"=="1" (echo FAIL: an unknown build must exit 1, got %FM_UNKNOWN_RC% & goto Fail)
echo PASS: case 2 - row read answers 1 / 0 / absent-row exit 1.

echo --- Case 3: :UpgBudgetLine names the fixture total_mib before any download ---
call cmd\UpgradePayloads.cmd :UpgBudgetLine "%MANIFEST%" >"%SB_OUT%\budget.out" 2>&1
if errorlevel 1 (echo FAIL: :UpgBudgetLine exited nonzero on a valid fixture manifest & goto Fail)
findstr /C:"BUDGET: 2 files, 104857702 bytes, 99 MiB" "%SB_OUT%\budget.out" >nul 2>&1
if errorlevel 1 (
  echo FAIL: the budget line must name the fixture row count, byte total and the total_mib figure 99.
  type "%SB_OUT%\budget.out"
  goto Fail
)
echo PASS: case 3 - budget line carries the fixture figures.

echo --- Case 4: :UpgHashGate positive - fixture spool matches the manifest ---
set "SB_SPOOL=%SANDBOX%\spool4"
mkdir "%SB_SPOOL%" 2>nul
copy /y "%BIG%" "%SB_SPOOL%\big.esd" >nul 2>&1
copy /y "%SMALL%" "%SB_SPOOL%\small.cab" >nul 2>&1
call cmd\UpgradePayloads.cmd :UpgHashGate "%MANIFEST%" "%SB_SPOOL%" "%REPO_ROOT%\client\bin\hashdeep64.exe" >"%SB_OUT%\hg-pos.out" 2>&1
if errorlevel 1 (echo FAIL: the matching spool must pass the hash gate & type "%SB_OUT%\hg-pos.out" & goto Fail)
findstr /C:"Audit passed" "%SB_OUT%\hg-pos.out" >nul 2>&1
if errorlevel 1 (echo FAIL: hashdeep did not report "Audit passed" & type "%SB_OUT%\hg-pos.out" & goto Fail)
echo PASS: case 4 - hash gate positive.

echo --- Case 5: :UpgHashGate corrupt - one flipped byte refused, nothing moved ---
set "SB_SPOOL=%SANDBOX%\spool5"
mkdir "%SB_SPOOL%" 2>nul
copy /y "%BIG%" "%SB_SPOOL%\big.esd" >nul 2>&1
>"%SB_SPOOL%\small.cab" echo !SB100:~0,99!C
call cmd\UpgradePayloads.cmd :UpgHashGate "%MANIFEST%" "%SB_SPOOL%" "%REPO_ROOT%\client\bin\hashdeep64.exe" >"%SB_OUT%\hg-cor.out" 2>&1
set "HG_COR_RC=!errorlevel!"
if "%HG_COR_RC%"=="0" (echo FAIL: a corrupted payload must be refused by the hash gate & goto Fail)
if not exist "%SB_SPOOL%\small.cab" (echo FAIL: the corrupt case must NOT move or delete spool files & goto Fail)
findstr /C:"integrity verification FAILED" "%SB_OUT%\hg-cor.out" >nul 2>&1
if errorlevel 1 (echo FAIL: the corrupt case must fail loudly with the refusal line & goto Fail)
echo PASS: case 5 - corrupt spool refused, nothing moved.

echo --- Case 6: :UpgHashGate truncated - shortened fixture refused ---
set "SB_SPOOL=%SANDBOX%\spool6"
mkdir "%SB_SPOOL%" 2>nul
copy /y "%BIG%" "%SB_SPOOL%\big.esd" >nul 2>&1
>"%SB_SPOOL%\small.cab" echo !SB100:~0,50!
call cmd\UpgradePayloads.cmd :UpgHashGate "%MANIFEST%" "%SB_SPOOL%" "%REPO_ROOT%\client\bin\hashdeep64.exe" >"%SB_OUT%\hg-tr.out" 2>&1
set "HG_TR_RC=!errorlevel!"
if "%HG_TR_RC%"=="0" (echo FAIL: a truncated payload must be refused even though a resume succeeded & goto Fail)
echo PASS: case 6 - truncated spool refused.

echo --- Case 7: :UpgAcquire orchestration over fixture url map + stubs ---
set "STUB_MODE=OK"
set "SB_SPOOL=%SANDBOX%\spool7"
mkdir "%SB_SPOOL%\files" 2>nul
copy /y "%BIG%" "%SB_SPOOL%\files\big.esd" >nul 2>&1
copy /y "%SMALL%" "%SB_SPOOL%\files\small.cab" >nul 2>&1
copy /y "%URLMAP%" "%SB_SPOOL%\url-map.tmp" >nul 2>&1
call cmd\UpgradePayloads.cmd :UpgAcquire "%MANIFEST%" "%SB_SPOOL%\url-map.tmp" "%SB_SPOOL%\files" >"%SB_OUT%\aq.out" 2>&1
set "AQ_RC=!errorlevel!"
if not "%AQ_RC%"=="0" (echo FAIL: the orchestration case must end green over matching stubs & type "%SB_OUT%\aq.out" & goto Fail)
call :OrderOf "BUDGET:" "ARIA2-STUB-DOWNLOAD" "%SB_OUT%\aq.out"
if not "%ORDER_OK%"=="1" (echo FAIL: the budget line must precede the first downloader invocation & goto Fail)
findstr /C:"Audit passed" "%SB_OUT%\aq.out" >nul 2>&1
if errorlevel 1 (echo FAIL: the hash gate must run over the orchestrated spool & goto Fail)
findstr /C:"WGET-STUB-DOWNLOAD" "%SB_OUT%\aq.out" >nul 2>&1
if errorlevel 1 (echo FAIL: the small payload list must go through wget & goto Fail)
if not exist "%SB_SPOOL%\files\big.esd" (echo FAIL: the orchestration must not move spool files & goto Fail)
if not exist "%SB_SPOOL%\files\small.cab" (echo FAIL: the orchestration must not move spool files & goto Fail)
if exist "%SB_SPOOL%\url-map.tmp" (echo FAIL: the url map must be deleted after the run - token material never persists & goto Fail)
call :TempArtifactCount
if not "%TEMP_COUNT%"=="%TEMP_BASELINE%" (echo FAIL: TEMP artifact count %TEMP_COUNT% differs from the baseline %TEMP_BASELINE% - token-bearing artifacts leaked past the cleanup & goto Fail)
echo PASS: case 7 - budget-first order, hash gate ran, spool intact, temp artifacts deleted.

echo --- Case 8: https-first / http-fallback (DEC-33-15) ---
set "STUB_MODE=HTTPS-FAILS"
set "SB_SPOOL=%SANDBOX%\spool8"
mkdir "%SB_SPOOL%\files" 2>nul
copy /y "%BIG%" "%SB_SPOOL%\files\big.esd" >nul 2>&1
copy /y "%SMALL%" "%SB_SPOOL%\files\small.cab" >nul 2>&1
copy /y "%URLMAP%" "%SB_SPOOL%\url-map.tmp" >nul 2>&1
call cmd\UpgradePayloads.cmd :UpgAcquire "%MANIFEST%" "%SB_SPOOL%\url-map.tmp" "%SB_SPOOL%\files" >"%SB_OUT%\aq8.out" 2>&1
set "AQ8_RC=!errorlevel!"
if not "%AQ8_RC%"=="0" (echo FAIL: the https-refusing stub must still end green through the http fallback & type "%SB_OUT%\aq8.out" & goto Fail)
findstr /C:"falling back to the original http URLs" "%SB_OUT%\aq8.out" >nul 2>&1
if errorlevel 1 (echo FAIL: the aria2 http fallback line is missing & goto Fail)
findstr /C:"http fallback" "%SB_OUT%\aq8.out" >nul 2>&1
if errorlevel 1 (echo FAIL: the wget http fallback line is missing & goto Fail)
echo PASS: case 8 - bounded https-first, http-fallback transport proven.

echo --- Case 9: loud abort + cleanup on the failure path ---
set "STUB_MODE=ALWAYS-FAILS"
set "SB_SPOOL=%SANDBOX%\spool9"
mkdir "%SB_SPOOL%\files" 2>nul
copy /y "%BIG%" "%SB_SPOOL%\files\big.esd" >nul 2>&1
copy /y "%SMALL%" "%SB_SPOOL%\files\small.cab" >nul 2>&1
copy /y "%URLMAP%" "%SB_SPOOL%\url-map.tmp" >nul 2>&1
call cmd\UpgradePayloads.cmd :UpgAcquire "%MANIFEST%" "%SB_SPOOL%\url-map.tmp" "%SB_SPOOL%\files" >"%SB_OUT%\aq9.out" 2>&1
set "AQ9_RC=!errorlevel!"
if "%AQ9_RC%"=="0" (echo FAIL: a downloader that fails both schemes must abort loudly & goto Fail)
findstr /C:"acquisition failed" "%SB_OUT%\aq9.out" >nul 2>&1
if errorlevel 1 (echo FAIL: the failure path must carry the loud acquisition-failed line & goto Fail)
if exist "%SB_SPOOL%\url-map.tmp" (echo FAIL: the failure path must delete the url map too & goto Fail)
call :TempArtifactCount
if not "%TEMP_COUNT%"=="%TEMP_BASELINE%" (echo FAIL: TEMP artifact count %TEMP_COUNT% differs from the baseline %TEMP_BASELINE% - the failure path leaked artifacts & goto Fail)
echo PASS: case 9 - loud abort, url map deleted on the failure path.

echo --- Case 10: :UpgAssembleMedia positive - stub wimlib, matching pins ---
set "STUB_WIMLIB_MODE=OK"
set "UUP_WIMLIB=%STUB_WIMLIB%"
set "ASM_SPOOL=%SANDBOX%\spool10"
mkdir "%ASM_SPOOL%" 2>nul
>"%ASM_SPOOL%\core_en-us.esd" echo fake-metadata-core
>"%ASM_SPOOL%\professional_en-us.esd" echo fake-metadata-professional
>"%ASM_SPOOL%\ssu-26200-test.cab" echo excluded-pattern-cab
>"%SB_FIX%\SHA256SUMS.ok" echo %STUB_WIMLIB_HASH% *wimlib-stub.cmd
set "UUP_WIMLIB_SHA256SUMS=%SB_FIX%\SHA256SUMS.ok"
set "ASM_STAGE=%SANDBOX%\stage10"
call cmd\UpgradePayloads.cmd :UpgAssembleMedia "%ASM_SPOOL%" "%ASM_STAGE%" "%MANIFEST%" >"%SB_OUT%\asm10.out" 2>&1
if errorlevel 1 (echo FAIL: the stubbed assembly must end green over matching pins & type "%SB_OUT%\asm10.out" & goto Fail)
if not exist "%ASM_STAGE%\sources\setup.exe" (echo FAIL: the assembly must produce the scaffold sources\setup.exe & type "%SB_OUT%\asm10.out" & goto Fail)
if not exist "%ASM_STAGE%\sources\install.esd" (echo FAIL: the assembly must produce sources\install.esd & goto Fail)
if not exist "%ASM_STAGE%\sources\boot.wim" (echo FAIL: the assembly must produce sources\boot.wim - the live-UAT 0x80070002 finding & goto Fail)
findstr /C:"Media assembly complete - 2 edition image" "%SB_OUT%\asm10.out" >nul 2>&1
if errorlevel 1 (echo FAIL: the census must report 2 images for the 2-edition fixture & type "%SB_OUT%\asm10.out" & goto Fail)
findstr /C:"Converted 0 component cab" "%SB_OUT%\asm10.out" >nul 2>&1
if errorlevel 1 (echo FAIL: the excluded-pattern cab must not be converted & goto Fail)
set "CONV_COUNT=0"
for /F %%c in ('dir /B "%SANDBOX%\converted\*" 2^>nul ^| %SystemRoot%\System32\find.exe /c /v ""') do set "CONV_COUNT=%%c"
if not "%CONV_COUNT%"=="0" (echo FAIL: no conversion-target cab existed - the converted dir must hold nothing to convert, holds %CONV_COUNT% & goto Fail)
echo PASS: case 10 - assembly positive with the vendored-tool pin verification.

echo --- Case 11: :UpgAssembleMedia tampered pin - fail-closed refusal ---
set "ASM_STAGE=%SANDBOX%\stage11"
>"%SB_FIX%\SHA256SUMS.bad" echo 20492a4d0d84f8beb1767f6616229f85d44c2827b64bdbfb260ee12fa1109e0e *wimlib-stub.cmd
set "UUP_WIMLIB_SHA256SUMS=%SB_FIX%\SHA256SUMS.bad"
call cmd\UpgradePayloads.cmd :UpgAssembleMedia "%ASM_SPOOL%" "%ASM_STAGE%" "%MANIFEST%" >"%SB_OUT%\asm11.out" 2>&1
set "ASM11_RC=!errorlevel!"
if "%ASM11_RC%"=="0" (echo FAIL: a tampered vendored-tool pin must be refused fail-closed & goto Fail)
if exist "%ASM_STAGE%" (echo FAIL: a refused assembly must leave NOTHING staged & goto Fail)
findstr /C:"SHA256 pin MISMATCH" "%SB_OUT%\asm11.out" >nul 2>&1
if errorlevel 1 (echo FAIL: the refusal must name the pin mismatch & type "%SB_OUT%\asm11.out" & goto Fail)
echo PASS: case 11 - tampered vendored tool refused, nothing staged.

echo --- Case 12: :UpgAssembleMedia failing export - loud refusal, stage cleaned ---
set "STUB_WIMLIB_MODE=EXPORT-FAILS"
set "UUP_WIMLIB_SHA256SUMS=%SB_FIX%\SHA256SUMS.ok"
set "ASM_STAGE=%SANDBOX%\stage12"
call cmd\UpgradePayloads.cmd :UpgAssembleMedia "%ASM_SPOOL%" "%ASM_STAGE%" "%MANIFEST%" >"%SB_OUT%\asm12.out" 2>&1
set "ASM12_RC=!errorlevel!"
if "%ASM12_RC%"=="0" (echo FAIL: a failing wimlib export must refuse the assembly & goto Fail)
if exist "%ASM_STAGE%" (echo FAIL: the failing assembly must clean the stage dir - nothing may linger & goto Fail)
findstr /C:"install.esd export failed" "%SB_OUT%\asm12.out" >nul 2>&1
if errorlevel 1 (echo FAIL: the export failure must be named loudly & type "%SB_OUT%\asm12.out" & goto Fail)
set "STUB_WIMLIB_MODE=OK"
echo PASS: case 12 - failing export refused loudly, stage dir cleaned.

echo --- Case 12b: boot.wim emission can-fail pair - export refusal / unreadable census ---
set "STUB_WIMLIB_MODE=BOOT-EXPORT-FAILS"
set "ASM_STAGE=%SANDBOX%\stage12b"
call cmd\UpgradePayloads.cmd :UpgAssembleMedia "%ASM_SPOOL%" "%ASM_STAGE%" "%MANIFEST%" >"%SB_OUT%\asm12b.out" 2>&1
set "ASM12B_RC=!errorlevel!"
if "%ASM12B_RC%"=="0" (echo FAIL: a failing boot.wim export must refuse the assembly & goto Fail)
if exist "%ASM_STAGE%" (echo FAIL: the boot.wim-export refusal must clean the stage dir - nothing may linger & goto Fail)
findstr /C:"boot.wim export failed" "%SB_OUT%\asm12b.out" >nul 2>&1
if errorlevel 1 (echo FAIL: the boot.wim export refusal must be named loudly & type "%SB_OUT%\asm12b.out" & goto Fail)
set "STUB_WIMLIB_MODE=BOOT-INFO-FAILS"
call cmd\UpgradePayloads.cmd :UpgAssembleMedia "%ASM_SPOOL%" "%ASM_STAGE%" "%MANIFEST%" >"%SB_OUT%\asm12c.out" 2>&1
set "ASM12C_RC=!errorlevel!"
if "%ASM12C_RC%"=="0" (echo FAIL: an unreadable boot.wim census must refuse the assembly & goto Fail)
if exist "%ASM_STAGE%" (echo FAIL: the boot.wim-census refusal must clean the stage dir - nothing may linger & goto Fail)
findstr /C:"census could not read the Image Count of sources\boot.wim" "%SB_OUT%\asm12c.out" >nul 2>&1
if errorlevel 1 (echo FAIL: the boot.wim census refusal must be named loudly & type "%SB_OUT%\asm12c.out" & goto Fail)
set "STUB_WIMLIB_MODE=OK"
echo PASS: case 12b - boot.wim emission proven can-fail both ways, stage cleaned.

echo --- Case 12c: boot.wim setup flag can-fail pair - flag-set refusal / flag missing from census ---
set "STUB_WIMLIB_MODE=FLAG-SET-FAILS"
set "ASM_STAGE=%SANDBOX%\stage12c"
call cmd\UpgradePayloads.cmd :UpgAssembleMedia "%ASM_SPOOL%" "%ASM_STAGE%" "%MANIFEST%" >"%SB_OUT%\asm12d.out" 2>&1
set "ASM12D_RC=!errorlevel!"
if "%ASM12D_RC%"=="0" (echo FAIL: a failing boot.wim flag set must refuse the assembly & goto Fail)
if exist "%ASM_STAGE%" (echo FAIL: the flag-set refusal must clean the stage dir - nothing may linger & goto Fail)
findstr /C:"setting the boot.wim setup flag 9 failed" "%SB_OUT%\asm12d.out" >nul 2>&1
if errorlevel 1 (echo FAIL: the flag-set refusal must be named loudly & type "%SB_OUT%\asm12d.out" & goto Fail)
set "STUB_WIMLIB_MODE=FLAG-NO-SET"
call cmd\UpgradePayloads.cmd :UpgAssembleMedia "%ASM_SPOOL%" "%ASM_STAGE%" "%MANIFEST%" >"%SB_OUT%\asm12e.out" 2>&1
set "ASM12E_RC=!errorlevel!"
if "%ASM12E_RC%"=="0" (echo FAIL: a flag-less boot.wim census must refuse the assembly & goto Fail)
if exist "%ASM_STAGE%" (echo FAIL: the flag-census refusal must clean the stage dir - nothing may linger & goto Fail)
findstr /C:"could not read the Flags of sources\boot.wim" "%SB_OUT%\asm12e.out" >nul 2>&1
if errorlevel 1 (echo FAIL: the flag-census refusal must be named loudly & type "%SB_OUT%\asm12e.out" & goto Fail)
set "STUB_WIMLIB_MODE=OK"
echo PASS: case 12c - the boot.wim setup flag proven can-fail both ways, stage cleaned.

echo --- Case 13: :UpgAuthenticodeGate refuse-staging trio ---
set "AG_STAGE=%SANDBOX%\stage13"
mkdir "%AG_STAGE%\sources" 2>nul
>"%AG_STAGE%\sources\setup.exe" echo STUB-SETUP
set "UUP_SIGCHK_PATH=%SB_STUBS%\sigcheck-stub.cmd"
set "UUP_STUB_SIGCHECK_MODE=SIGNED"
call cmd\UpgradePayloads.cmd :UpgAuthenticodeGate "%AG_STAGE%" >"%SB_OUT%\ag13a.out" 2>&1
if errorlevel 1 (echo FAIL: the Signed stub must pass the Authenticode gate & type "%SB_OUT%\ag13a.out" & goto Fail)
set "UUP_STUB_SIGCHECK_MODE=UNSIGNED-EXE"
call cmd\UpgradePayloads.cmd :UpgAuthenticodeGate "%AG_STAGE%" >"%SB_OUT%\ag13b.out" 2>&1
set "AG13B_RC=!errorlevel!"
if "%AG13B_RC%"=="0" (echo FAIL: an Unsigned executable row must REFUSE staging & goto Fail)
findstr /C:"UNSIGNED executable" "%SB_OUT%\ag13b.out" >nul 2>&1
if errorlevel 1 (echo FAIL: the unsigned refusal must name the row & type "%SB_OUT%\ag13b.out" & goto Fail)
set "UUP_STUB_SIGCHECK_MODE=UNSIGNED-MUI"
call cmd\UpgradePayloads.cmd :UpgAuthenticodeGate "%AG_STAGE%" >"%SB_OUT%\ag13c.out" 2>&1
if errorlevel 1 (echo FAIL: the .mui and migration-DLL convention rows must be allowed & type "%SB_OUT%\ag13c.out" & goto Fail)
findstr /C:"2 allowed convention row" "%SB_OUT%\ag13c.out" >nul 2>&1
if errorlevel 1 (echo FAIL: the allowed .mui row must be counted loudly, not silently skipped & goto Fail)
set "UUP_STUB_SIGCHECK_MODE=SIGNED"
echo PASS: case 13 - Signed passes, Unsigned refuses, .mui + migration-DLL convention allowed and counted.

echo --- Case 14: staging-order - corrupted spool fails the hash gate BEFORE any scan or move ---
set "SM_SPOOL=%SANDBOX%\spool14"
mkdir "%SM_SPOOL%\files" 2>nul
copy /y "%BIG%" "%SM_SPOOL%\files\big.esd" >nul 2>&1
>"%SM_SPOOL%\files\small.cab" echo !SB100:~0,99!C
>"%SM_SPOOL%\manifest.txt" echo uuid^|aaaaaaaa-0000-0000-0000-000000000000
>>"%SM_SPOOL%\manifest.txt" echo small.cab^|!H_SMALL!^|102
>>"%SM_SPOOL%\manifest.txt" echo big.esd^|!H_BIG!^|104857600
mkdir "%SANDBOX%\stage14" 2>nul
>"%SANDBOX%\stage14\sources\setup.exe" echo STUB
set "UUP_CLIENT_ROOT=%SANDBOX%\client"
if exist "%TEMP%\wou-upg-sigcheck-stub-invoked" del "%TEMP%\wou-upg-sigcheck-stub-invoked" >nul 2>&1
call cmd\UpgradePayloads.cmd :UpgStageMedia "%SANDBOX%\stage14" "%SM_SPOOL%\manifest.txt" 26200 x64 en-us >"%SB_OUT%\sm14.out" 2>&1
set "SM14_RC=!errorlevel!"
if "%SM14_RC%"=="0" (echo FAIL: a corrupted spool must refuse staging & goto Fail)
if exist "%UUP_CLIENT_ROOT%\upgrade\26200-x64\en-us" (echo FAIL: the hash-gate refusal must move NOTHING into the tree & goto Fail)
if exist "%TEMP%\wou-upg-sigcheck-stub-invoked" (echo FAIL: the hash gate must fire BEFORE the Authenticode scan - gate order violated & goto Fail)
findstr /C:"hash gate refused staging" "%SB_OUT%\sm14.out" >nul 2>&1
if errorlevel 1 (echo FAIL: the gate-order refusal must be named & type "%SB_OUT%\sm14.out" & goto Fail)
echo PASS: case 14 - hash gate precedes Authenticode and the move, nothing moved.

echo --- Case 15: staging replacement - old revision dies only after the new one reads back ---
set "SM_SPOOL=%SANDBOX%\spool15"
mkdir "%SM_SPOOL%\files" 2>nul
copy /y "%BIG%" "%SM_SPOOL%\files\big.esd" >nul 2>&1
copy /y "%SMALL%" "%SM_SPOOL%\files\small.cab" >nul 2>&1
>"%SM_SPOOL%\manifest.txt" echo uuid^|bbbbbbbb-0000-0000-0000-000000000000
>>"%SM_SPOOL%\manifest.txt" echo small.cab^|!H_SMALL!^|102
>>"%SM_SPOOL%\manifest.txt" echo big.esd^|!H_BIG!^|104857600
mkdir "%SANDBOX%\stage15\sources" 2>nul
>"%SANDBOX%\stage15\sources\setup.exe" echo STUB-NEW
>"%SM_SPOOL%\urlmap-marker.txt" echo spool-working-set
mkdir "%UUP_CLIENT_ROOT%\upgrade\26200-x64\en-us" 2>nul
>"%UUP_CLIENT_ROOT%\upgrade\26200-x64\en-us\manifest.txt" echo uuid^|aaaaaaaa-0000-0000-0000-000000000000
>"%UUP_CLIENT_ROOT%\upgrade\26200-x64\en-us\old-media.bin" echo OLD-REVISION
call cmd\UpgradePayloads.cmd :UpgStageMedia "%SANDBOX%\stage15" "%SM_SPOOL%\manifest.txt" 26200 x64 en-us >"%SB_OUT%\sm15.out" 2>&1
if errorlevel 1 (echo FAIL: the replacement staging must end green & type "%SB_OUT%\sm15.out" & goto Fail)
findstr /C:"uuid|bbbbbbbb-0000-0000-0000-000000000000" "%UUP_CLIENT_ROOT%\upgrade\26200-x64\en-us\manifest.txt" >nul 2>&1
if errorlevel 1 (echo FAIL: the staged manifest must carry the new uuid & goto Fail)
if not exist "%UUP_CLIENT_ROOT%\upgrade\26200-x64\en-us\sources\setup.exe" (echo FAIL: the new media must be in the tree & goto Fail)
if exist "%UUP_CLIENT_ROOT%\upgrade\26200-x64\en-us\old-media.bin" (echo FAIL: the old revision media must be gone after success & goto Fail)
for /F %%c in ('dir /B "%SM_SPOOL%\replaced-*" 2^>nul ^| %SystemRoot%\System32\find.exe /c /v ""') do set "ASIDES_LEFT=%%c"
if not "%ASIDES_LEFT%"=="0" (echo FAIL: the moved-aside old revision must be DELETED after the successful staging, %ASIDES_LEFT% asides remain & goto Fail)
echo PASS: case 15 - delete-after-success replacement proven.

echo --- Case 16: :UpgPurgeRevisions trio (sole / stale / failed-staging) ---
set "PR_SPOOL=%SANDBOX%\purge-spool"
set "WOU_UPGRADE_SPOOL=%PR_SPOOL%"
set "PR_SETS=%PR_SPOOL%\26200-x64-en-us"
>"%SB_FIX%\pr-staged.txt" echo uuid^|11111111-1111-1111-1111-111111111111
mkdir "%PR_SETS%\11111111-1111-1111-1111-111111111111\files" 2>nul
copy /y "%SB_FIX%\pr-staged.txt" "%PR_SETS%\11111111-1111-1111-1111-111111111111\manifest.txt" >nul
>"%PR_SETS%\11111111-1111-1111-1111-111111111111\files\keep.txt" echo KEEP-ME
call cmd\UpgradePayloads.cmd :UpgPurgeRevisions 26200 x64 en-us "%SB_FIX%\pr-staged.txt" >"%SB_OUT%\pr16a.out" 2>&1
if errorlevel 1 (echo FAIL: the sole-revision purge must end green & type "%SB_OUT%\pr16a.out" & goto Fail)
findstr /C:"PURGE: 0 removals" "%SB_OUT%\pr16a.out" >nul 2>&1
if errorlevel 1 (echo FAIL: a sole revision must answer 0 removals & type "%SB_OUT%\pr16a.out" & goto Fail)
mkdir "%PR_SETS%\22222222-2222-2222-2222-222222222222\files" 2>nul
>"%PR_SETS%\22222222-2222-2222-2222-222222222222\manifest.txt" echo uuid^|22222222-2222-2222-2222-222222222222
>"%PR_SETS%\22222222-2222-2222-2222-222222222222\files\stale.txt" echo STALE
mkdir "%PR_SETS%\33333333-3333-3333-3333-333333333333" 2>nul
>"%PR_SETS%\33333333-3333-3333-3333-333333333333\manifest.txt" echo uuid^|33333333-3333-3333-3333-333333333333
call cmd\UpgradePayloads.cmd :UpgPurgeRevisions 26200 x64 en-us "%SB_FIX%\pr-staged.txt" >"%SB_OUT%\pr16b.out" 2>&1
if errorlevel 1 (echo FAIL: the stale-revision purge must end green & type "%SB_OUT%\pr16b.out" & goto Fail)
if exist "%PR_SETS%\22222222-2222-2222-2222-222222222222" (echo FAIL: the first stale set must be purged & goto Fail)
if exist "%PR_SETS%\33333333-3333-3333-3333-333333333333" (echo FAIL: the second stale set must be purged & goto Fail)
if not exist "%PR_SETS%\11111111-1111-1111-1111-111111111111\files\keep.txt" (echo FAIL: the staged-uuid keep set must still exist after the purge - the kept-set assertion & goto Fail)
findstr /C:"2 stale revision set" "%SB_OUT%\pr16b.out" >nul 2>&1
if errorlevel 1 (echo FAIL: the purge must count exactly 2 removals & type "%SB_OUT%\pr16b.out" & goto Fail)
call cmd\UpgradePayloads.cmd :UpgPurgeRevisions 26200 x64 en-us "%SB_FIX%\nonexistent-staged-manifest.txt" >"%SB_OUT%\pr16c.out" 2>&1
set "PR16C_RC=!errorlevel!"
if "%PR16C_RC%"=="0" (echo FAIL: the purge must refuse without proof of successful staging & goto Fail)
if not exist "%PR_SETS%\11111111-1111-1111-1111-111111111111" (echo FAIL: the failed-staging simulation must remove NOTHING & goto Fail)
set "WOU_UPGRADE_SPOOL="
echo PASS: case 16 - purge answers 0 / exact / nothing, kept set survives.

echo --- Case 17: :UpgCreateMediaDb - the staged media gets its integrity class ---
call cmd\UpgradePayloads.cmd :UpgCreateMediaDb 26200 x64 en-us >"%SB_OUT%\cd17.out" 2>&1
if errorlevel 1 (echo FAIL: the media db creation must end green over the staged fixture & type "%SB_OUT%\cd17.out" & goto Fail)
set "DB17=%UUP_CLIENT_ROOT%\md\hashes-upgrade-26200-x64-en-us.txt"
if not exist "%DB17%" (echo FAIL: the integrity class file is missing & goto Fail)
findstr /B /C:"%%%%" "%DB17%" >nul 2>&1
if errorlevel 1 (echo FAIL: the db file must carry the hashdeep header & goto Fail)
echo PASS: case 17 - media integrity class created with the hashdeep header.

echo.
echo =======================================================================
echo UPG-PAYLOADS-CMD-PASS: all 18 acquisition cases green.
echo =======================================================================
rd /s /q "%SANDBOX%" 2>nul
exit /b 0

:AnswerOf
rem Capture the first stdout line of a library subroutine (value form)
rem %1 = subroutine label, %2 = single argument
set "ANS_OUT="
call cmd\UpgradePayloads.cmd %~1 %~2 >"%SB_OUT%\ans.out" 2>&1
for /F "usebackq delims=" %%v in ("%SB_OUT%\ans.out") do if not defined ANS_OUT set "ANS_OUT=%%v"
exit /b 0

:AnswerOfEx
rem Same as :AnswerOf but carries three arguments and keeps the exit code
set "ANS_OUT="
call cmd\UpgradePayloads.cmd %~1 %~2 %~3 %~4 >"%SB_OUT%\ans.out" 2>&1
set "ANS_RC=!errorlevel!"
for /F "usebackq delims=" %%v in ("%SB_OUT%\ans.out") do if not defined ANS_OUT set "ANS_OUT=%%v"
exit /b 0

:OrderOf
rem Assert that line %1 appears EARLIER in file %3 than line %2
set "ORDER_LINE_A=%~1"
set "ORDER_LINE_B=%~2"
set "ORDER_FILE=%~3"
set "ORDER_OK=0"
set "ORDER_LNA="
set "ORDER_LNB="
for /F "tokens=1 delims=:" %%i in ('findstr /N /C:"!ORDER_LINE_A!" "!ORDER_FILE!"') do if not defined ORDER_LNA set "ORDER_LNA=%%i"
for /F "tokens=1 delims=:" %%i in ('findstr /N /C:"!ORDER_LINE_B!" "!ORDER_FILE!"') do if not defined ORDER_LNB set "ORDER_LNB=%%i"
if defined ORDER_LNA if defined ORDER_LNB if !ORDER_LNA! LSS !ORDER_LNB! set "ORDER_OK=1"
exit /b 0

:TempArtifactCount
rem Count wou-upg-* artifacts in TEMP. :UpgAcquire must leave exactly the
rem baseline count behind - the url map, the join files, both downloader
rem lists and the hashdeep expectation all die on every exit path (T-33-09).
set "TEMP_COUNT=0"
for /F %%c in ('dir /B "%TEMP%\wou-upg-*" 2^>nul ^| %SystemRoot%\System32\find.exe /c /v ""') do set "TEMP_COUNT=%%c"
exit /b 0

:Fail
echo.
echo =======================================================================
echo UPG-PAYLOADS-CMD-FAIL
echo =======================================================================
rem Debug knob: set UUP_KEEP_SANDBOX=1 to keep the failing sandbox tree
rem for inspection - default behavior cleans it up.
if "%UUP_KEEP_SANDBOX%"=="1" (
  echo Sandbox kept for inspection: %SANDBOX%
) else (
  rd /s /q "%SANDBOX%" 2>nul
)
exit /b 1
