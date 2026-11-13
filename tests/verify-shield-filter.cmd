@echo off
setlocal enabledelayedexpansion

REM =======================================================================
REM WSUS Offline Update - Shield-Feed Chosen-Target Filter Battery (Windows CMD)
REM File: tests\verify-shield-filter.cmd
REM
REM Sandbox battery for the Phase-32 CMD chosen-target vertical slice
REM (plan 32-01, DEC-32-04 / DEC-32-05 / DEC-32-08): an evaluator mirrors
REM the production os-upgrades reader + shield-feed filter semantics of
REM cmd\DownloadUpdates.cmd (same grammar literal, same all-or-nothing
REM rule, same build-part membership) and proves the frozen branches:
REM
REM   Case 1: no selection file           -> full statu-quo golden feed
REM   Case 2: 26200_x64=on                -> exactly windows10.0-kb5064081
REM   Case 3: 19045_x64=on                -> exactly windows10.0-kb5021233
REM   Case 4: 26200_x64=on AND 19045_x64=on -> exactly kb5064081 + kb5021233
REM   Case 5: one key plus bad_line       -> full statu-quo feed (all-or-nothing)
REM   Case 6: CRLF fixture + blank tail   -> case 2 result unchanged
REM   Case 7: acquisition absence (no selection) -> no output, no spool
REM   Case 8: fu_media=0 row              -> no resolve attempt, no spool
REM   Case 9: fu_media=1 fixture seam     -> budget line, spool root created
REM   Case 10: eol-target exemption pair  -> derived row flips on membership
REM
REM T-32-06 report: per-target dropped exemption lines vs the golden are
REM enumerated per case (Pitfall-4 warning signs).
REM The battery NEVER reads or writes the real gitignored sh\os-upgrades.ini
REM - every fixture lives under its own %TEMP% sandbox.
REM =======================================================================

pushd "%~dp0.."
set "REPO_ROOT=%CD%"
popd

echo =======================================================================
echo WSUS Offline Update - Shield-Feed Filter Battery (Windows CMD)
echo =======================================================================

set "SANDBOX=%TEMP%\wou_test_shield_%RANDOM%_%RANDOM%"
set "SB_STATIC=%SANDBOX%\static"
set "SB_SH=%SANDBOX%\sh"
set "SB_FEED=%SANDBOX%\feed"
mkdir "%SB_STATIC%" 2>nul
mkdir "%SB_SH%" 2>nul
mkdir "%SB_FEED%" 2>nul
if not exist "%SB_FEED%" (
  echo ERROR: Failed to create test sandbox at "%SANDBOX%".
  exit /b 1
)

rem Fixture hop files: copies of the committed census data (the battery
rem consumes copies under its sandbox - the committed files are frozen).
copy /y "%REPO_ROOT%\client\static\StaticUpdateIds-BuildUpgrades.txt" "%SB_STATIC%\" >nul 2>&1
copy /y "%REPO_ROOT%\client\static\StaticUpdateIds-BuildUpgradesForced.txt" "%SB_STATIC%\" >nul 2>&1
if not exist "%SB_STATIC%\StaticUpdateIds-BuildUpgrades.txt" (
  echo ERROR: Failed to copy StaticUpdateIds-BuildUpgrades.txt to the sandbox.
  goto Fail
)
if not exist "%SB_STATIC%\StaticUpdateIds-BuildUpgradesForced.txt" (
  echo ERROR: Failed to copy StaticUpdateIds-BuildUpgradesForced.txt to the sandbox.
  goto Fail
)

rem Census pin: the goldens below are frozen against 6 optional + 2 forced
rem rows - upstream drift must fail loudly instead of validating stale goldens.
rem Full path on find.exe: this battery is launched from POSIX-spawned
rem cmd.exe sessions (MSYS PATH), where plain `find` resolves to GNU find
rem and turns the census walk into a whole-drive scan.
set HOP_ROWS=0
for /F %%c in ('type "%SB_STATIC%\StaticUpdateIds-BuildUpgrades.txt" ^| %SystemRoot%\System32\find.exe /c /v ""') do set HOP_ROWS=%%c
set FORCED_ROWS=0
for /F %%c in ('type "%SB_STATIC%\StaticUpdateIds-BuildUpgradesForced.txt" ^| %SystemRoot%\System32\find.exe /c /v ""') do set FORCED_ROWS=%%c
if not "%HOP_ROWS%"=="6" (
  echo FAIL: hop census drifted - StaticUpdateIds-BuildUpgrades.txt carries %HOP_ROWS% rows, golden expects 6; re-freeze the battery goldens.
  goto Fail
)
if not "%FORCED_ROWS%"=="2" (
  echo FAIL: forced census drifted - StaticUpdateIds-BuildUpgradesForced.txt carries %FORCED_ROWS% rows, golden expects 2; re-freeze the battery goldens.
  goto Fail
)

echo --- Case 1: no selection file - full statu-quo golden feed ---
set "EXP1=%SB_FEED%\expected1.txt"
call :BuildGolden "%EXP1%"
call :FilterEvaluator NONE "%SB_FEED%\feed1.txt"
fc /l "%EXP1%" "%SB_FEED%\feed1.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: case 1 ^(no selection^) - feed does not equal the statu-quo golden ^(windows10.0-kb5008212 / kb5021233 / kb5064081^).
  goto Fail
)
echo PASS: case 1 - feed byte-identical without selection.

echo --- Case 2: 26200_x64=on - exactly windows10.0-kb5064081 ---
set "SEL2=%SB_SH%\sel-case2.ini"
echo 26200_x64=on>"%SEL2%"
set "EXP2=%SB_FEED%\expected2.txt"
set "EXP_LINE=windows10.0-kb5064081"
echo !EXP_LINE!>"%EXP2%"
call :FilterEvaluator "%SEL2%" "%SB_FEED%\feed2.txt"
fc /l "%EXP2%" "%SB_FEED%\feed2.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: case 2 ^(26200_x64=on^) - feed does not carry exactly windows10.0-kb5064081.
  goto Fail
)
call :ReportDropped "%SB_FEED%\feed2.txt" "26200"
echo PASS: case 2 - single chosen target narrows the feed.

echo --- Case 3: 19045_x64=on - exactly windows10.0-kb5021233 ---
set "SEL3=%SB_SH%\sel-case3.ini"
echo 19045_x64=on>"%SEL3%"
set "EXP3=%SB_FEED%\expected3.txt"
set "EXP_LINE=windows10.0-kb5021233"
echo !EXP_LINE!>"%EXP3%"
echo !EXP_LINE!>>"%EXP3%"
echo !EXP_LINE!>>"%EXP3%"
call :FilterEvaluator "%SEL3%" "%SB_FEED%\feed3.txt"
fc /l "%EXP3%" "%SB_FEED%\feed3.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: case 3 ^(19045_x64=on^) - feed does not carry exactly windows10.0-kb5021233.
  goto Fail
)
call :ReportDropped "%SB_FEED%\feed3.txt" "19045"
echo PASS: case 3 - second single target narrows the feed.

echo --- Case 4: 26200_x64=on AND 19045_x64=on - multi-EKB = all emitted ---
set "SEL4=%SB_SH%\sel-case4.ini"
echo 26200_x64=on>"%SEL4%"
>>"%SEL4%" echo 19045_x64=on
set "EXP4=%SB_FEED%\expected4.txt"
set "EXP_LINE=windows10.0-kb5021233"
echo !EXP_LINE!>"%EXP4%"
echo !EXP_LINE!>>"%EXP4%"
echo !EXP_LINE!>>"%EXP4%"
set "EXP_LINE=windows10.0-kb5064081"
echo !EXP_LINE!>>"%EXP4%"
call :FilterEvaluator "%SEL4%" "%SB_FEED%\feed4.txt"
fc /l "%EXP4%" "%SB_FEED%\feed4.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: case 4 ^(26200_x64 + 19045_x64^) - feed does not carry exactly windows10.0-kb5064081 + windows10.0-kb5021233.
  goto Fail
)
call :ReportDropped "%SB_FEED%\feed4.txt" "26200 19045"
echo PASS: case 4 - multi-EKB selection emits all chosen targets.

echo --- Case 5: one key plus bad_line - all-or-nothing voids to statu quo ---
set "SEL5=%SB_SH%\sel-case5.ini"
echo 26200_x64=on>"%SEL5%"
>>"%SEL5%" echo bad_line
call :FilterEvaluator "%SEL5%" "%SB_FEED%\feed5.txt"
set "EXPG=%SB_FEED%\expected5.txt"
call :BuildGolden "%EXPG%"
fc /l "%EXPG%" "%SB_FEED%\feed5.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: case 5 ^(one key + bad_line^) - a grammar-violating line must void the ENTIRE selection ^(full statu-quo feed expected^), never a partial one.
  goto Fail
)
echo PASS: case 5 - invalid selection refuses loudly to the full feed.

echo --- Case 6: CRLF fixture with blank tail line - case 2 result unchanged ---
set "SEL6=%SB_SH%\sel-case6.ini"
echo 26200_x64=on>"%SEL6%"
>>"%SEL6%" echo.
call :FilterEvaluator "%SEL6%" "%SB_FEED%\feed6.txt"
fc /l "%EXP2%" "%SB_FEED%\feed6.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: case 6 ^(CRLF fixture + blank tail^) - CRLF line endings must not change the case-2 result.
  goto Fail
)
echo PASS: case 6 - CRLF fixture parses to the case-2 feed.

rem ----------------------------------------------------------------------
rem Acquisition statu quo cases (plan 33-03, DEC-33-09 / DEC-33-14):
rem the REAL acquisition entry (cmd\UpgradePayloads.cmd :UpgSectionEntry -
rem the exact code the engine's Phase-33 region calls) is driven in a
rem sandbox over fixture seams. Without a qualifying selection the region
rem is invisible: no output lines, no spool. With the fu_media=1 fixture
rem seam the section gets as far as the budget line before any network
rem attempt would occur.
rem ----------------------------------------------------------------------
set "WOU_UPGRADE_SEL=%SB_SH%\os-upgrades-acq.ini"
set "WOU_UPGRADE_TABLE=%SB_STATIC%\upgrades.txt"
set "WOU_UPGRADE_SPOOL=%SANDBOX%\spool-acq"
set "WOU_UPGRADE_LANG=en-us"
copy /y "%REPO_ROOT%\client\UpdateTable\upgrades.txt" "%WOU_UPGRADE_TABLE%" >nul 2>&1
if not exist "%WOU_UPGRADE_TABLE%" (
  echo ERROR: Failed to copy the committed upgrades.txt into the sandbox.
  goto Fail
)

echo --- Case 7: acquisition absence - no selection, no spool, no output ---
rem The carrying scope rides the call (live-UAT 33 finding #7b): without
rem it the new scope gate would answer the no-op before the selection
rem branch under test is reached, and this case would pass vacuously.
set "TMP_UPG_TARGETS="
type nul >"%SB_FEED%\acq7.out"
call "%REPO_ROOT%\cmd\UpgradePayloads.cmd" :UpgSectionEntry w100-x64 >"%SB_FEED%\acq7.out" 2>&1
set "ACQ7_RC=!errorlevel!"
if not "%ACQ7_RC%"=="0" (
  echo FAIL: case 7 ^(no selection^) - the acquisition entry must exit 0, got %ACQ7_RC%.
  type "%SB_FEED%\acq7.out"
  goto Fail
)
for /F %%c in ('type "%SB_FEED%\acq7.out" ^| %SystemRoot%\System32\find.exe /c /v ""') do set "ACQ7_LINES=%%c"
if not "%ACQ7_LINES%"=="0" (
  echo FAIL: case 7 ^(no selection^) - the engine output must carry no acquisition-section lines ^(got %ACQ7_LINES%^).
  type "%SB_FEED%\acq7.out"
  goto Fail
)
if exist "%WOU_UPGRADE_SPOOL%" (
  echo FAIL: case 7 ^(no selection^) - the DEC-33-14 spool root must NOT be created.
  goto Fail
)
echo PASS: case 7 - no selection = the Phase-33 region is a byte-level no-op.

echo --- Case 8: acquisition absence - fu_media=0 row answers the no-op path ---
set "TMP_UPG_TARGETS=19045"
echo 19045_x64=on>"%WOU_UPGRADE_SEL%"
type nul >"%SB_FEED%\acq8.out"
call "%REPO_ROOT%\cmd\UpgradePayloads.cmd" :UpgSectionEntry w100-x64 >"%SB_FEED%\acq8.out" 2>&1
set "ACQ8_RC=!errorlevel!"
if not "%ACQ8_RC%"=="0" (
  echo FAIL: case 8 ^(fu_media=0^) - the acquisition entry must exit 0, got %ACQ8_RC%.
  type "%SB_FEED%\acq8.out"
  goto Fail
)
for /F %%c in ('type "%SB_FEED%\acq8.out" ^| %SystemRoot%\System32\find.exe /c /v ""') do set "ACQ8_LINES=%%c"
if not "%ACQ8_LINES%"=="0" (
  echo FAIL: case 8 ^(fu_media=0^) - the gate refuses loudly-silent: no resolve attempt, no spool ^(got %ACQ8_LINES% lines^).
  type "%SB_FEED%\acq8.out"
  goto Fail
)
if exist "%WOU_UPGRADE_SPOOL%" (
  echo FAIL: case 8 ^(fu_media=0^) - the spool root must NOT be created.
  goto Fail
)
echo PASS: case 8 - fu_media=0 = no resolve attempt, no spool.

echo --- Case 9: fu_media=1 fixture seam - budget-deep, offline-bounded ---
set "TMP_UPG_TARGETS=26200"
echo 26200_x64=on>"%WOU_UPGRADE_SEL%"
set "WOU_UUP_FIXTURE=%REPO_ROOT%\tests\fixtures\uup-get-26200-en-us-multiedition.json"
if not exist "%WOU_UUP_FIXTURE%" (
  echo ERROR: the golden fixture is missing at "%WOU_UUP_FIXTURE%".
  goto Fail
)
call "%REPO_ROOT%\cmd\UpgradePayloads.cmd" :UpgSectionEntry w100-x64 >"%SB_FEED%\acq9.out" 2>&1
set "ACQ9_RC=!errorlevel!"
if "%ACQ9_RC%"=="0" (
  echo FAIL: case 9 ^(fu_media=1^) - in the sandbox the fixture resolve emits no url map, so the section must abort at the join, not end green.
  type "%SB_FEED%\acq9.out"
  goto Fail
)
findstr /C:"BUDGET:" "%SB_FEED%\acq9.out" >nul 2>&1
if errorlevel 1 (
  echo FAIL: case 9 ^(fu_media=1^) - the budget line must precede any network attempt.
  type "%SB_FEED%\acq9.out"
  goto Fail
)
if not exist "%WOU_UPGRADE_SPOOL%" (
  echo FAIL: case 9 ^(fu_media=1^) - the spool root must be created by the qualifying run.
  goto Fail
)
if not exist "%WOU_UPGRADE_SPOOL%\manifest.txt" (
  echo FAIL: case 9 ^(fu_media=1^) - the resolved manifest must land in the spool.
  goto Fail
)
echo PASS: case 9 - budget line emitted, spool root created, wiring proven without network.
set "TMP_UPG_TARGETS="
set "WOU_UUP_FIXTURE="

echo --- Case 10: eol-target exemption pair - selection membership only ---
rem ACQ-06's exemption half (can-fail BOTH directions): the expected
rem exemption row is DERIVED from the fixture hop file - the row whose
rem field 4 equals 19044 ^(the eol-status target of the DEC-31-05
rem precedent^) - its KB literal is never hardcoded here. With a selection
rem naming only 26200_x64 the derived row is ABSENT (suppressed - not
rem chosen); with 26200_x64 PLUS 19044_x64 the SAME row is PRESENT -
rem presence flips purely on selection membership because the
rem chosen-target filter reads no status field.
set "EOL_KB="
for /F "usebackq tokens=3,4 delims=," %%c in ("%SB_STATIC%\StaticUpdateIds-BuildUpgrades.txt") do (
  if "%%d"=="19044" if not defined EOL_KB set "EOL_KB=%%c"
)
if not defined EOL_KB (
  echo FAIL: case 10 - the eol-target derivation found no hop row with field 4 = 19044.
  goto Fail
)
set "SEL10A=%SB_SH%\sel-case10a.ini"
echo 26200_x64=on>"%SEL10A%"
call :FilterEvaluator "%SEL10A%" "%SB_FEED%\feed10a.txt"
findstr /L /C:"windows10.0-%EOL_KB%" "%SB_FEED%\feed10a.txt" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: case 10 ^(absent direction^) - the derived eol row windows10.0-%EOL_KB% must be suppressed when only 26200_x64 is chosen.
  goto Fail
)
set "SEL10B=%SB_SH%\sel-case10b.ini"
echo 26200_x64=on>"%SEL10B%"
>>"%SEL10B%" echo 19044_x64=on
call :FilterEvaluator "%SEL10B%" "%SB_FEED%\feed10b.txt"
findstr /L /C:"windows10.0-%EOL_KB%" "%SB_FEED%\feed10b.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: case 10 ^(present direction^) - the derived eol row windows10.0-%EOL_KB% must be emitted when 19044_x64 joins the selection - a superseded-stated target stays selectable.
  goto Fail
)
echo PASS: case 10 - the eol exemption row flips absent-to-present purely on selection membership ^(derived row: windows10.0-%EOL_KB%^).

echo --- Cross-tier link: bash shield-filter twin - both must be green ---
rem Resolve a bash interpreter: bare PATH first, Git for Windows fallback
rem (31-04 contract-twin invocation idiom). The CMD sentinel below is
rem only emitted when the bash twin exits 0 - the cross-tier link is
rem silent when green.
set "BASH_EXE=bash"
where bash >nul 2>&1
if errorlevel 1 (
  if exist "%ProgramFiles%\Git\bin\bash.exe" (
    set "BASH_EXE=%ProgramFiles%\Git\bin\bash.exe"
  )
)
set "BASH_TWIN=%REPO_ROOT:\=/%\sh\tests\verify-shield-filter.bash"
echo [RUN ] invoking the bash shield-filter twin via "%BASH_EXE%" ...
"%BASH_EXE%" "%BASH_TWIN%"
if errorlevel 1 (
  echo FAIL: the bash shield-filter twin did not exit 0 - cross-tier parity broken
  goto Fail
)
echo [PASS] bash shield-filter twin exit 0

echo.
echo =======================================================================
echo SHIELD-FILTER-CMD-PASS: all 10 shield-filter cases green.
echo =======================================================================
rd /s /q "%SANDBOX%" 2>nul
exit /b 0

:BuildGolden
rem %1 = golden output file. Byte-frozen statu-quo feed: 6 optional rows
rem then 2 forced rows in file order. Lines are emitted through a delayed
rem variable so no digit sits before the redirect at parse time.
set "GOLD_OUT=%~1"
set "EXP_LINE=windows10.0-kb5008212"
echo !EXP_LINE!>"%GOLD_OUT%"
echo !EXP_LINE!>>"%GOLD_OUT%"
set "EXP_LINE=windows10.0-kb5021233"
echo !EXP_LINE!>>"%GOLD_OUT%"
echo !EXP_LINE!>>"%GOLD_OUT%"
echo !EXP_LINE!>>"%GOLD_OUT%"
set "EXP_LINE=windows10.0-kb5064081"
echo !EXP_LINE!>>"%GOLD_OUT%"
set "EXP_LINE=windows10.0-kb5008212"
echo !EXP_LINE!>>"%GOLD_OUT%"
echo !EXP_LINE!>>"%GOLD_OUT%"
exit /b 0

:FilterEvaluator
rem Mirror of the production reader+filter (cmd\DownloadUpdates.cmd Step 5
rem region): same grammar literal, same all-or-nothing bad flag, same
rem build-part dedup accumulation, same feed guard. %1 = selection file
rem ^(NONE = absent^), %2 = feed output file. Sandbox hop files are the
rem fixed feed inputs.
set "UPG_SEL_FILE=%~1"
set "UPG_FEED_OUT=%~2"
if "%UPG_SEL_FILE%"=="NONE" set "UPG_SEL_FILE="
set TMP_UPG_TARGETS=
set TMP_UPG_SEL_BAD=
if defined UPG_SEL_FILE if exist "%UPG_SEL_FILE%" (
  findstr /R /V /C:"^[0-9][0-9]*_[A-Za-z0-9][A-Za-z0-9]*=on$" /C:"^$" "%UPG_SEL_FILE%" >nul 2>&1
  if not errorlevel 1 set TMP_UPG_SEL_BAD=1
  if not defined TMP_UPG_SEL_BAD (
    for /F "usebackq delims=_ tokens=1" %%i in ("%UPG_SEL_FILE%") do (
      if "!TMP_UPG_TARGETS!"=="" (
        set TMP_UPG_TARGETS=%%i
      ) else (
        echo "!TMP_UPG_TARGETS!" | %SystemRoot%\System32\find.exe "%%i" >nul 2>&1
        if errorlevel 1 set TMP_UPG_TARGETS=!TMP_UPG_TARGETS! %%i
      )
    )
  )
)
type nul >"%UPG_FEED_OUT%"
for /F "usebackq tokens=3,4 delims=," %%c in ("%SB_STATIC%\StaticUpdateIds-BuildUpgrades.txt") do (
  set TMP_UPG_EMIT=0
  if not defined TMP_UPG_TARGETS set TMP_UPG_EMIT=1
  if defined TMP_UPG_TARGETS (
    echo x !TMP_UPG_TARGETS! | %SystemRoot%\System32\find.exe " %%d" >nul 2>&1
    if not errorlevel 1 set TMP_UPG_EMIT=1
  )
  if "!TMP_UPG_EMIT!"=="1" (
    echo windows10.0-%%c>>"%UPG_FEED_OUT%"
  )
)
for /F "usebackq tokens=3,4 delims=," %%c in ("%SB_STATIC%\StaticUpdateIds-BuildUpgradesForced.txt") do (
  set TMP_UPG_EMIT=0
  if not defined TMP_UPG_TARGETS set TMP_UPG_EMIT=1
  if defined TMP_UPG_TARGETS (
    echo x !TMP_UPG_TARGETS! | %SystemRoot%\System32\find.exe " %%d" >nul 2>&1
    if not errorlevel 1 set TMP_UPG_EMIT=1
  )
  if "!TMP_UPG_EMIT!"=="1" (
    echo windows10.0-%%c>>"%UPG_FEED_OUT%"
  )
)
exit /b 0

:ReportDropped
rem T-32-06 report: enumerate the golden exemption lines absent from the
rem narrowed feed of this case (informational Pitfall-4 warning signs).
rem %1 = case feed file, %2 = chosen targets (report label only).
set "REPORT_FEED=%~1"
set "REPORT_TARGETS=%~2"
set "REPORT_LINE=windows10.0-kb5008212"
call :ReportOne
set "REPORT_LINE=windows10.0-kb5021233"
call :ReportOne
set "REPORT_LINE=windows10.0-kb5064081"
call :ReportOne
echo REPORT: targets "%REPORT_TARGETS%" - dropped exemption lines listed above ^(if any^) left the media via the existing supersession exclusion.
exit /b 0

:ReportOne
findstr /L /C:"!REPORT_LINE!" "%REPORT_FEED%" >nul 2>&1
if errorlevel 1 echo REPORT: dropped - !REPORT_LINE!
exit /b 0

:Fail
echo.
echo =======================================================================
echo SHIELD-FILTER-CMD-FAIL
echo =======================================================================
rd /s /q "%SANDBOX%" 2>nul
exit /b 1
