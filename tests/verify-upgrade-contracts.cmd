@echo off
setlocal enabledelayedexpansion

REM =======================================================================
REM WSUS Offline Update - Upgrade Contract Twin (Windows CMD)
REM File: tests\verify-upgrade-contracts.cmd
REM
REM Plan 31-04 CMD-side contract assertions (PATH-01/PATH-02/PATH-03):
REM   1. Frozen consent literals over the real sources: enginecontracts
REM      25/25 counts, the /upgradeos token, the INI template default,
REM      the engine refusal + acceptance literals + the WOU_UPGRADE_TARGET
REM      carriage, the mainform write-back absence comment, the host
REM      [OS Upgrades] section literals, the gitignored bash twin file.
REM   2. Battery invocation: the /upgradeos argv acceptance battery,
REM      the Phase-32 shield-filter sandbox battery and the bash contract
REM      twin (cross-tier parity) must all exit 0.
REM   3. Phase-32 chosen-target pins (section D, plan 32-01): the CMD
REM      os-upgrades reader + shield-feed filter literals, the host
REM      multi-EKB grammar marker, the 6-row hop census and the
REM      unmodified exemption echo lines.
REM   4. Phase-32 engine-literal pins (plan 32-04): the five DEC-32-07
REM      refusal/report messages, the WOU_ROW_ALLOWED target guard, the
REM      DEC-32-06 perform record, the DEC-32-03 consent composition,
REM      and the negative pins holding the frozen 31-02 parse contract
REM      and the CSV-only engine (DEC-32-01) over client\cmd\DoUpdate.cmd.
REM   4. Phase-32 engine-literal pins (plan 32-04): the chosen-target
REM      engine contract in client\cmd\DoUpdate.cmd - the five DEC-32-07
REM      message literals, the WOU_ROW_ALLOWED guard census, the
REM      consent-composition branch, the attempts write-backs (DEC-32-06),
REM      the frozen 31-02 parse refusal census and the DEC-32-01 CSV-only
REM      absence pin. Message fragments pin by presence; the exact
REM      two-channel counts live in the bash twin (a delayed-expansion
REM      batch file cannot spell the engine's at-variable tokens).
REM
REM No DoUpdate sandbox of its own - the acceptance sandbox lives in
REM tests\verify-upgrade-argv.cmd, which is invoked, not duplicated.
REM Success sentinel: UPGRADE-CONTRACTS-CMD-PASS. Any miss prints FAIL
REM and exits 1.
REM =======================================================================

pushd "%~dp0.."
set "REPO_ROOT=%CD%"
popd

echo =======================================================================
echo WSUS Offline Update - Upgrade Contract Twin (Windows CMD)
echo =======================================================================

REM -----------------------------------------------------------------------
REM 1. Source assertions - frozen literals over the real files
REM -----------------------------------------------------------------------
set "CONTRACTS_PAS=%REPO_ROOT%\src-native\installer\enginecontracts.pas"
set "TEMPLATE_INI=%REPO_ROOT%\client\UpdateInstaller.ini"
set "ENGINE_CMD=%REPO_ROOT%\client\cmd\DoUpdate.cmd"
set "MAINFORM_PAS=%REPO_ROOT%\src-native\installer\mainform.pas"
set "HOST_CS=%REPO_ROOT%\src-modern\generator\host\Program.cs"
set "GITIGNORE=%REPO_ROOT%\.gitignore"

if not exist "%CONTRACTS_PAS%" (
  echo FAIL: missing enginecontracts.pas at "%CONTRACTS_PAS%"
  goto Fail
)

findstr /C:"ENG_SWITCH_COUNT = 25" "%CONTRACTS_PAS%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: enginecontracts.pas is missing the frozen ENG_SWITCH_COUNT = 25 literal
  goto Fail
)
echo [PASS] enginecontracts.pas: ENG_SWITCH_COUNT = 25

findstr /C:"ENG_INI_DEFAULT_COUNT = 25" "%CONTRACTS_PAS%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: enginecontracts.pas is missing the frozen ENG_INI_DEFAULT_COUNT = 25 literal
  goto Fail
)
echo [PASS] enginecontracts.pas: ENG_INI_DEFAULT_COUNT = 25

if not exist "%TEMPLATE_INI%" (
  echo FAIL: missing UpdateInstaller.ini at "%TEMPLATE_INI%"
  goto Fail
)
findstr /C:"upgradeos=Disabled" "%TEMPLATE_INI%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: UpdateInstaller.ini template is missing the upgradeos=Disabled default
  goto Fail
)
echo [PASS] UpdateInstaller.ini: upgradeos=Disabled template default

if not exist "%ENGINE_CMD%" (
  echo FAIL: missing DoUpdate.cmd at "%ENGINE_CMD%"
  goto Fail
)
findstr /C:"ERROR: /upgradeos target must be a build number" "%ENGINE_CMD%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: DoUpdate.cmd is missing the loud refusal literal
  goto Fail
)
echo [PASS] DoUpdate.cmd: refusal literal pinned

findstr /C:"Info: Upgrade target build" "%ENGINE_CMD%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: DoUpdate.cmd is missing the acceptance literal
  goto Fail
)
echo [PASS] DoUpdate.cmd: acceptance literal pinned

findstr /C:"%%WOU_UPGRADE_TARGET%%" "%ENGINE_CMD%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: DoUpdate.cmd is missing the WOU_UPGRADE_TARGET carriage variable
  goto Fail
)
echo [PASS] DoUpdate.cmd: WOU_UPGRADE_TARGET carriage pinned

if not exist "%MAINFORM_PAS%" (
  echo FAIL: missing mainform.pas at "%MAINFORM_PAS%"
  goto Fail
)
findstr /C:"SECOND never-written key" "%MAINFORM_PAS%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: mainform.pas is missing the SECOND never-written key comment - write-back absence undocumented
  goto Fail
)
echo [PASS] mainform.pas: SECOND never-written key comment pinned

if not exist "%HOST_CS%" (
  echo FAIL: missing Program.cs at "%HOST_CS%"
  goto Fail
)
findstr /C:"[OS Upgrades]" "%HOST_CS%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: Program.cs is missing the [OS Upgrades] section literal
  goto Fail
)
echo [PASS] Program.cs: [OS Upgrades] section pinned

findstr /C:"os-upgrades.ini" "%HOST_CS%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: Program.cs is missing the flat bash twin file name
  goto Fail
)
echo [PASS] Program.cs: os-upgrades.ini flat twin pinned

findstr /C:"sh/os-upgrades.ini" "%GITIGNORE%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: .gitignore is missing the sh/os-upgrades.ini twin line
  goto Fail
)
echo [PASS] .gitignore: sh/os-upgrades.ini excluded

REM -----------------------------------------------------------------------
REM 3. Phase-32 chosen-target pins (section D, plan 32-01): CMD reader,
REM    feed filter, and host multi-EKB grammar literals fail-closed.
REM    Full path on find.exe: this twin is launched from POSIX-spawned
REM    cmd.exe sessions (MSYS PATH), where plain `find` resolves to GNU
REM    find and turns census walks into whole-drive scans.
REM -----------------------------------------------------------------------
if not exist "%REPO_ROOT%\cmd\DownloadUpdates.cmd" (
  echo FAIL: missing DownloadUpdates.cmd at "%REPO_ROOT%\cmd\DownloadUpdates.cmd"
  goto Fail
)
set "PIPELINE_CMD=%REPO_ROOT%\cmd\DownloadUpdates.cmd"

findstr /C:"TMP_UPG_TARGETS" "%PIPELINE_CMD%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: DownloadUpdates.cmd is missing the os-upgrades reader literal TMP_UPG_TARGETS
  goto Fail
)
echo [PASS] DownloadUpdates.cmd: TMP_UPG_TARGETS reader literal pinned

set PIPELINE_TARGETS_COUNT=0
for /F %%c in ('%SystemRoot%\System32\findstr.exe /C:"TMP_UPG_TARGETS" "%PIPELINE_CMD%" ^| %SystemRoot%\System32\find.exe /c /v ""') do set PIPELINE_TARGETS_COUNT=%%c
if %PIPELINE_TARGETS_COUNT% LSS 6 (
  echo FAIL: DownloadUpdates.cmd carries only %PIPELINE_TARGETS_COUNT% TMP_UPG_TARGETS sites ^(reader + both loop guards expect 6 or more^)
  goto Fail
)
echo [PASS] DownloadUpdates.cmd: TMP_UPG_TARGETS site count = %PIPELINE_TARGETS_COUNT% (expected 6 or more)

findstr /C:"TMP_UPG_SEL_BAD" "%PIPELINE_CMD%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: DownloadUpdates.cmd is missing the all-or-nothing bad flag TMP_UPG_SEL_BAD
  goto Fail
)
echo [PASS] DownloadUpdates.cmd: TMP_UPG_SEL_BAD bad flag pinned

findstr /C:"^[0-9][0-9]*_[A-Za-z0-9][A-Za-z0-9]*=on$" "%PIPELINE_CMD%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: DownloadUpdates.cmd is missing the frozen selection grammar literal

  goto Fail
)
echo [PASS] DownloadUpdates.cmd: selection grammar literal pinned

set READER_LINE=
set STEP5_LINE=
for /F "delims=: tokens=1" %%a in ('%SystemRoot%\System32\findstr.exe /N /B /C:"set TMP_UPG_TARGETS=" "%PIPELINE_CMD%"') do if not defined READER_LINE set "READER_LINE=%%a"
for /F "delims=: tokens=1" %%a in ('%SystemRoot%\System32\findstr.exe /N /B /C:"rem *** Step 5" "%PIPELINE_CMD%"') do if not defined STEP5_LINE set "STEP5_LINE=%%a"
if not defined READER_LINE (
  echo FAIL: DownloadUpdates.cmd reader block start line not found
  goto Fail
)
if not defined STEP5_LINE (
  echo FAIL: DownloadUpdates.cmd Step 5 header line not found
  goto Fail
)
if !READER_LINE! GEQ !STEP5_LINE! (
  echo FAIL: the os-upgrades reader ^(line !READER_LINE!^) must sit BEFORE the Step 5 header ^(line !STEP5_LINE!^) - DEC-32-04 placement
  goto Fail
)
echo [PASS] DownloadUpdates.cmd: reader at line !READER_LINE! precedes Step 5 at line !STEP5_LINE!

set PIPELINE_ECHO_COUNT=0
for /F %%c in ('%SystemRoot%\System32\findstr.exe /C:"echo windows10.0-%%%%c>>" "%PIPELINE_CMD%" ^| %SystemRoot%\System32\find.exe /c /v ""') do set PIPELINE_ECHO_COUNT=%%c
if %PIPELINE_ECHO_COUNT% LSS 4 (
  echo FAIL: DownloadUpdates.cmd carries only %PIPELINE_ECHO_COUNT% unmodified echo windows10.0-%%%%c>> exemption lines ^(4 expected across both feed loops^)
  goto Fail
)
echo [PASS] DownloadUpdates.cmd: exemption echo lines unmodified (count = %PIPELINE_ECHO_COUNT%)

set "HOP_FILE=%REPO_ROOT%\client\static\StaticUpdateIds-BuildUpgrades.txt"
set HOP_ROWS=0
for /F %%c in ('type "%HOP_FILE%" ^| %SystemRoot%\System32\find.exe /c /v ""') do set HOP_ROWS=%%c
if not "%HOP_ROWS%"=="6" (
  echo FAIL: hop census drifted - StaticUpdateIds-BuildUpgrades.txt carries %HOP_ROWS% rows, the frozen contract is 6 ^(T-32-02^)
  goto Fail
)
echo [PASS] StaticUpdateIds-BuildUpgrades.txt: hop census = 6 rows

findstr /C:"multi-EKB grammar (DEC-32-02)" "%HOST_CS%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: Program.cs is missing the multi-EKB grammar ^(DEC-32-02^) marker comment
  goto Fail
)
echo [PASS] Program.cs: multi-EKB grammar (DEC-32-02) marker pinned

findstr /C:"File.WriteAllLines(upgradeFlat" "%HOST_CS%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: Program.cs is missing the flat-twin File.WriteAllLines^(upgradeFlat call - the twin must write the full N-line list
  goto Fail
)
echo [PASS] Program.cs: flat-twin N-line write pinned

REM -----------------------------------------------------------------------
REM 4. Phase-32 engine-literal pins (plan 32-04): the chosen-target engine
REM    contract in client\cmd\DoUpdate.cmd fails closed.
REM -----------------------------------------------------------------------
findstr /C:"blocked: enablement package" "%ENGINE_CMD%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: DoUpdate.cmd is missing the blocked-enablement refusal literal
  goto Fail
)
echo [PASS] DoUpdate.cmd: blocked-enablement refusal literal pinned

findstr /C:"blocked: baseline revision" "%ENGINE_CMD%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: DoUpdate.cmd is missing the blocked-baseline refusal literal
  goto Fail
)
echo [PASS] DoUpdate.cmd: blocked-baseline refusal literal pinned

findstr /C:"has no upgrade path from build" "%ENGINE_CMD%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: DoUpdate.cmd is missing the no-upgrade-path refusal literal
  goto Fail
)
echo [PASS] DoUpdate.cmd: no-upgrade-path refusal literal pinned

findstr /C:"observed - jump complete" "%ENGINE_CMD%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: DoUpdate.cmd is missing the observed-convergence Info literal
  goto Fail
)
echo [PASS] DoUpdate.cmd: observed-convergence Info literal pinned

findstr /C:"did not advance the OS build" "%ENGINE_CMD%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: DoUpdate.cmd is missing the perform-stall Warning literal
  goto Fail
)
echo [PASS] DoUpdate.cmd: perform-stall Warning literal pinned

set ENGINE_GUARD_COUNT=0
for /F %%c in ('%SystemRoot%\System32\findstr.exe /C:"WOU_ROW_ALLOWED" "%ENGINE_CMD%" ^| %SystemRoot%\System32\find.exe /c /v ""') do set ENGINE_GUARD_COUNT=%%c
if %ENGINE_GUARD_COUNT% LSS 4 (
  echo FAIL: DoUpdate.cmd carries only %ENGINE_GUARD_COUNT% WOU_ROW_ALLOWED sites - both chosen-target loop guards expect 4 or more
  goto Fail
)
echo [PASS] DoUpdate.cmd: WOU_ROW_ALLOWED site count = %ENGINE_GUARD_COUNT% (expected 4 or more)

findstr /C:"if defined WOU_UPGRADE_TARGET goto CheckBuildUpgradeOptional" "%ENGINE_CMD%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: DoUpdate.cmd is missing the consent-composition branch - a defined target must route to the optional lane
  goto Fail
)
set ENGINE_CONSENT_COUNT=0
for /F %%c in ('%SystemRoot%\System32\findstr.exe /C:"if defined WOU_UPGRADE_TARGET goto CheckBuildUpgradeOptional" "%ENGINE_CMD%" ^| %SystemRoot%\System32\find.exe /c /v ""') do set ENGINE_CONSENT_COUNT=%%c
if not "%ENGINE_CONSENT_COUNT%"=="1" (
  echo FAIL: the consent-composition branch appears %ENGINE_CONSENT_COUNT% times - exactly 1 expected ^(DEC-32-03^)
  goto Fail
)
echo [PASS] DoUpdate.cmd: consent-composition branch pinned (exactly 1)

findstr /C:",perform>" "%ENGINE_CMD%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: DoUpdate.cmd is missing the perform-leg attempts write-back
  goto Fail
)
set ENGINE_PERFORM_WB=0
for /F %%c in ('%SystemRoot%\System32\findstr.exe /C:",perform>" "%ENGINE_CMD%" ^| %SystemRoot%\System32\find.exe /c /v ""') do set ENGINE_PERFORM_WB=%%c
if not "%ENGINE_PERFORM_WB%"=="1" (
  echo FAIL: the perform-leg write-back appears %ENGINE_PERFORM_WB% times - exactly 1 expected ^(DEC-32-06^)
  goto Fail
)
echo [PASS] DoUpdate.cmd: perform-leg attempts write-back pinned (exactly 1)

findstr /C:",prepare>" "%ENGINE_CMD%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: DoUpdate.cmd is missing the prepare-leg attempts write-back
  goto Fail
)
set ENGINE_PREPARE_WB=0
for /F %%c in ('%SystemRoot%\System32\findstr.exe /C:",prepare>" "%ENGINE_CMD%" ^| %SystemRoot%\System32\find.exe /c /v ""') do set ENGINE_PREPARE_WB=%%c
if not "%ENGINE_PREPARE_WB%"=="1" (
  echo FAIL: the prepare-leg write-back appears %ENGINE_PREPARE_WB% times - exactly 1 expected ^(DEC-32-06^)
  goto Fail
)
echo [PASS] DoUpdate.cmd: prepare-leg attempts write-back pinned (exactly 1)

set ENGINE_ATTEMPTS_FMT=0
for /F %%c in ('%SystemRoot%\System32\findstr.exe /C:",%%OS_VER_REVIS%%,%%OS_VER_BUILD%%," "%ENGINE_CMD%" ^| %SystemRoot%\System32\find.exe /c /v ""') do set ENGINE_ATTEMPTS_FMT=%%c
if not "%ENGINE_ATTEMPTS_FMT%"=="3" (
  echo FAIL: the attempts count,revision,build write prefix appears %ENGINE_ATTEMPTS_FMT% times - exactly 3 expected ^(prepare + perform + full-FU write-backs^)
  goto Fail
)
echo [PASS] DoUpdate.cmd: attempts format write prefix pinned (exactly 3)

findstr /C:",full>" "%ENGINE_CMD%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: DoUpdate.cmd is missing the full-FU leg attempts write-back
  goto Fail
)
set ENGINE_FULL_WB=0
for /F %%c in ('%SystemRoot%\System32\findstr.exe /C:",full>" "%ENGINE_CMD%" ^| %SystemRoot%\System32\find.exe /c /v ""') do set ENGINE_FULL_WB=%%c
if not "%ENGINE_FULL_WB%"=="1" (
  echo FAIL: the full-FU leg write-back appears %ENGINE_FULL_WB% times - exactly 1 expected ^(DEC-34-06^)
  goto Fail
)
echo [PASS] DoUpdate.cmd: full-FU leg attempts write-back pinned (exactly 1)

set ENGINE_REFUSAL_COUNT=0
for /F %%c in ('%SystemRoot%\System32\findstr.exe /C:"ERROR: /upgradeos target must be a build number" "%ENGINE_CMD%" ^| %SystemRoot%\System32\find.exe /c /v ""') do set ENGINE_REFUSAL_COUNT=%%c
if not "%ENGINE_REFUSAL_COUNT%"=="4" (
  echo FAIL: the frozen 31-02 parse refusal drifted to %ENGINE_REFUSAL_COUNT% lines - exactly 4 expected ^(2 sites x 2 echo channels^)
  goto Fail
)
echo [PASS] DoUpdate.cmd: frozen 31-02 parse refusal census = 4 lines (2 sites x 2 channels)

findstr /C:"os-upgrades" "%ENGINE_CMD%" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: DoUpdate.cmd references a selection file - the DEC-32-01 CSV-only composition is violated
  goto Fail
)
echo [PASS] DoUpdate.cmd: zero selection-file references (DEC-32-01 CSV-only)

REM -----------------------------------------------------------------------
REM 5. Phase-37 family census (plan 37-02, VAL-02b): zero pre-Win10 rows
REM    at the data layer. Field-4 walks over the live roster and the
REM    generator source of truth (for /f token walks - NOT findstr
REM    pattern counting), counts captured into variables and compared
REM    numerically. The upgrade entries the GUIs surface come ONLY from
REM    this roster, so a w61/wxp family can never reach the picker; the
REM    FPC resolver's R4 refusal is exercised by the TAP negative
REM    (upg-case-21-wxp-family-r4) instead.
REM -----------------------------------------------------------------------
set "UPGRADES_TXT=%REPO_ROOT%\client\UpdateTable\upgrades.txt"
set "BUILDS_INI=%REPO_ROOT%\static\builds.ini"
if not exist "%UPGRADES_TXT%" (
  echo FAIL: missing upgrades.txt at "%UPGRADES_TXT%"
  goto Fail
)
set ROSTER_TOTAL=0
set ROSTER_WIN10=0
set ROSTER_WIN11=0
set ROSTER_OTHER=0
set "ROSTER_OTHER_FIRST="
for /F "usebackq eol=# delims=| tokens=4" %%f in ("%UPGRADES_TXT%") do (
  set /a ROSTER_TOTAL+=1
  if /i "%%f"=="win10" (
    set /a ROSTER_WIN10+=1
  ) else if /i "%%f"=="win11" (
    set /a ROSTER_WIN11+=1
  ) else (
    set /a ROSTER_OTHER+=1
    if not defined ROSTER_OTHER_FIRST set "ROSTER_OTHER_FIRST=%%f"
  )
)
if %ROSTER_TOTAL% LSS 1 (
  echo FAIL: the roster family census read 0 data rows - vacuous census ^(population proof failed^)
  goto Fail
)
if %ROSTER_OTHER% NEQ 0 (
  echo FAIL: upgrades.txt carries %ROSTER_OTHER% pre-Win10 os_family row^(s^) ^(first: %ROSTER_OTHER_FIRST%; expected zero^)
  goto Fail
)
set /a ROSTER_W1011=ROSTER_WIN10+ROSTER_WIN11
if not "%ROSTER_W1011%"=="%ROSTER_TOTAL%" (
  echo FAIL: the roster family census is inconsistent - win10+win11 = %ROSTER_W1011% of %ROSTER_TOTAL% rows
  goto Fail
)
echo [PASS] upgrades.txt: zero pre-Win10 os_family rows (census %ROSTER_TOTAL%/%ROSTER_W1011% win10+win11, 0 other)

if not exist "%BUILDS_INI%" (
  echo FAIL: missing builds.ini at "%BUILDS_INI%"
  goto Fail
)
set BUILDS_TOTAL=0
set BUILDS_OTHER=0
set "BUILDS_OTHER_FIRST="
for /F "delims== tokens=2" %%v in ('%SystemRoot%\System32\findstr.exe /B /C:"os_family=" "%BUILDS_INI%"') do (
  set /a BUILDS_TOTAL+=1
  if /i not "%%v"=="win10" if /i not "%%v"=="win11" (
    set /a BUILDS_OTHER+=1
    if not defined BUILDS_OTHER_FIRST set "BUILDS_OTHER_FIRST=%%v"
  )
)
if %BUILDS_TOTAL% LSS 1 (
  echo FAIL: the builds.ini family census read 0 os_family values - vacuous census ^(population proof failed^)
  goto Fail
)
if %BUILDS_OTHER% NEQ 0 (
  echo FAIL: builds.ini carries %BUILDS_OTHER% pre-Win10 os_family value^(s^) ^(first: %BUILDS_OTHER_FIRST%; expected zero^)
  goto Fail
)
echo [PASS] builds.ini: zero pre-Win10 os_family values (census %BUILDS_TOTAL% win10+win11, 0 other)

REM -----------------------------------------------------------------------
REM 2. Battery invocation - argv acceptance + bash contract twin
REM -----------------------------------------------------------------------
echo [RUN ] invoking tests\verify-upgrade-argv.cmd ...
call "%REPO_ROOT%\tests\verify-upgrade-argv.cmd"
if errorlevel 1 (
  echo FAIL: the /upgradeos argv acceptance battery did not exit 0
  goto Fail
)
echo [PASS] argv acceptance battery exit 0

echo [RUN ] invoking tests\verify-shield-filter.cmd ...
call "%REPO_ROOT%\tests\verify-shield-filter.cmd"
if errorlevel 1 (
  echo FAIL: the shield-filter sandbox battery did not exit 0 - the CMD chosen-target vertical slice is broken
  goto Fail
)
echo [PASS] shield-filter battery exit 0

REM Resolve a bash interpreter: bare PATH first, Git for Windows fallback
set "BASH_EXE=bash"
where bash >nul 2>&1
if errorlevel 1 (
  if exist "%ProgramFiles%\Git\bin\bash.exe" (
    set "BASH_EXE=%ProgramFiles%\Git\bin\bash.exe"
  )
)
set "BASH_SCRIPT=%REPO_ROOT:\=/%\sh\tests\verify-upgrade-contracts.bash"
echo [RUN ] invoking the bash contract twin via "%BASH_EXE%" ...
"%BASH_EXE%" "%BASH_SCRIPT%"
if errorlevel 1 (
  echo FAIL: the bash contract twin did not exit 0 - cross-tier parity broken
  goto Fail
)
echo [PASS] bash contract twin exit 0 - cross-tier parity holds

REM -----------------------------------------------------------------------
REM All Passed
REM -----------------------------------------------------------------------
echo.
echo =======================================================================
echo UPGRADE-CONTRACTS-CMD-PASS: all source assertions and both batteries green.
echo =======================================================================
exit /b 0

:Fail
echo.
echo =======================================================================
echo FAILURE: Upgrade contract twin failed.
echo =======================================================================
exit /b 1
