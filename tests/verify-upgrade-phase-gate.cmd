@echo off
setlocal

REM =======================================================================
REM WSUS Offline Update - Phase 32 Upgrade Phase Gate (consigned)
REM File: tests\verify-upgrade-phase-gate.cmd
REM
REM Plan 32-04 / DEC-32-10: the full phase gate lives as THIS artifact -
REM one command re-runs every platform instrument the phase produced.
REM Prose-recorded chains degrade; a consigned artifact re-runs
REM identically. Modeled on the contract-twin launcher (%~dp0.. root,
REM :Fail protocol, exit-code fail-closed per link).
REM
REM The chain requires exit 0 from EACH link, in order:
REM    1. bash -n over the five Phase-32 bash files (the task file, the
REM       selection library, both bash batteries, the bash contract twin)
REM    2. sh/tests/verify-reboot-cycle.bash     (evaluator, 12 states)
REM    3. tests/verify-reboot-cycle.cmd         (real engine, 12 states)
REM    4. sh/tests/verify-win11-26h1.bash
REM    5. tests/verify-win11-26h1.cmd
REM    6. sh/tests/verify-upgrade-contracts.bash
REM    7. tests/verify-upgrade-contracts.cmd
REM    8. sh/tests/verify-shield-filter.bash
REM    9. tests/verify-shield-filter.cmd        (chains the bash twin)
REM   10. tests/verify-upgrade-argv.cmd
REM   11. ci/tests/test-native-installer-units.sh (lazbuild i386; WO_LAZARUS_ROOT
REM       override or the .planning/tmp/23-tools/lazarus scratch default)
REM   12. tests/verify-gui-contracts.cmd        (lazbuild both modes)
REM   13. both generation twins' drift check: bash sh/generate-build-sites.bash
REM       --check AND cscript //Nologo cmd\GenerateBuildSites.vbs --check
REM       (run from the repo root, the cscript double-slash preserved)
REM
REM A red link is diagnosable by its GATE number: every link echoes one
REM numbered line before running and a PASS line after. Bash resolves at
REM runtime (bare PATH first, the Git for Windows fallback second) - the
REM contract-twin idiom. Success sentinel: UPGRADE-PHASE-GATE-PASS.
REM =======================================================================

REM The pushd is HELD for the whole run: every link runs from the repo
REM root (link 13's cscript form is direct-execution friendly), and both
REM exit paths popd before returning.
pushd "%~dp0.."
set "REPO_ROOT=%CD%"

echo =======================================================================
echo WSUS Offline Update - Phase 32 Upgrade Phase Gate
echo =======================================================================

REM Resolve a bash interpreter: bare PATH first, Git for Windows fallback
set "BASH_EXE=bash"
where bash >nul 2>&1
if errorlevel 1 (
  if exist "%ProgramFiles%\Git\bin\bash.exe" (
    set "BASH_EXE=%ProgramFiles%\Git\bin\bash.exe"
  )
)
echo [INFO] bash resolved to "%BASH_EXE%"

echo [GATE 1] bash -n syntax over the five Phase-32 bash files...
"%BASH_EXE%" -n sh/download-updates-tasks/50-superseded-updates.bash sh/libraries/upgrade-selection.bash sh/tests/verify-reboot-cycle.bash sh/tests/verify-shield-filter.bash sh/tests/verify-upgrade-contracts.bash
if errorlevel 1 (
  echo FAIL: GATE 1 red - bash -n syntax check failed on a Phase-32 bash file
  goto Fail
)
echo [GATE 1] PASS

echo [GATE 2] bash reboot-cycle twin (evaluator, 12 states)...
"%BASH_EXE%" sh/tests/verify-reboot-cycle.bash
if errorlevel 1 (
  echo FAIL: GATE 2 red - the bash reboot-cycle twin is not green
  goto Fail
)
echo [GATE 2] PASS

echo [GATE 3] CMD reboot-cycle twin (real engine, 12 states)...
call tests\verify-reboot-cycle.cmd
if errorlevel 1 (
  echo FAIL: GATE 3 red - the CMD reboot-cycle twin is not green
  goto Fail
)
echo [GATE 3] PASS

echo [GATE 4] bash win11-26h1 battery...
"%BASH_EXE%" sh/tests/verify-win11-26h1.bash
if errorlevel 1 (
  echo FAIL: GATE 4 red - the bash win11-26h1 battery is not green
  goto Fail
)
echo [GATE 4] PASS

echo [GATE 5] CMD win11-26h1 battery...
call tests\verify-win11-26h1.cmd
if errorlevel 1 (
  echo FAIL: GATE 5 red - the CMD win11-26h1 battery is not green
  goto Fail
)
echo [GATE 5] PASS

echo [GATE 6] bash contract twin (engine-literal pins)...
"%BASH_EXE%" sh/tests/verify-upgrade-contracts.bash
if errorlevel 1 (
  echo FAIL: GATE 6 red - the bash contract twin is not green
  goto Fail
)
echo [GATE 6] PASS

echo [GATE 7] CMD contract twin (engine-literal pins + batteries)...
call tests\verify-upgrade-contracts.cmd
if errorlevel 1 (
  echo FAIL: GATE 7 red - the CMD contract twin is not green
  goto Fail
)
echo [GATE 7] PASS

echo [GATE 8] bash shield-filter battery...
"%BASH_EXE%" sh/tests/verify-shield-filter.bash
if errorlevel 1 (
  echo FAIL: GATE 8 red - the bash shield-filter battery is not green
  goto Fail
)
echo [GATE 8] PASS

echo [GATE 9] CMD shield-filter battery (chains the bash twin)...
call tests\verify-shield-filter.cmd
if errorlevel 1 (
  echo FAIL: GATE 9 red - the CMD shield-filter battery is not green
  goto Fail
)
echo [GATE 9] PASS

echo [GATE 10] /upgradeos argv acceptance battery...
call tests\verify-upgrade-argv.cmd
if errorlevel 1 (
  echo FAIL: GATE 10 red - the argv acceptance battery is not green
  goto Fail
)
echo [GATE 10] PASS

echo [GATE 11] native installer units gate (lazbuild i386)...
"%BASH_EXE%" ci/tests/test-native-installer-units.sh
if errorlevel 1 (
  echo FAIL: GATE 11 red - the native installer units gate is not green
  goto Fail
)
echo [GATE 11] PASS

echo [GATE 12] GUI contracts (lazbuild both modes)...
call tests\verify-gui-contracts.cmd
if errorlevel 1 (
  echo FAIL: GATE 12 red - the GUI contracts gate is not green
  goto Fail
)
echo [GATE 12] PASS

echo [GATE 13] generation twins drift check (bash + VBS --check)...
"%BASH_EXE%" sh/generate-build-sites.bash --check
if errorlevel 1 (
  echo FAIL: GATE 13 red - the bash generation twin reported drift
  goto Fail
)
cscript //Nologo cmd\GenerateBuildSites.vbs --check
if errorlevel 1 (
  echo FAIL: GATE 13 red - the VBS generation twin reported drift
  goto Fail
)
echo [GATE 13] PASS

echo.
echo =======================================================================
echo UPGRADE-PHASE-GATE-PASS: all 13 links green in one run.
echo =======================================================================
popd
exit /b 0

:Fail
echo.
echo =======================================================================
echo FAILURE: Phase-32 upgrade phase gate failed - see the named GATE above.
echo =======================================================================
popd
exit /b 1
