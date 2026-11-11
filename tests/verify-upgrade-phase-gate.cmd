@echo off
setlocal

REM =======================================================================
REM WSUS Offline Update - Upgrade Phase Gate (consigned; extended by 33-04)
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
REM       + the Phase-33 acquisition bash files (62 task, resolver
REM       library, payloads battery - the 33-04 extension; the original
REM       five-file command shape is preserved, the list only grew)
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
REM   14. sh/tests/verify-upgrade-resolver.bash (Phase-33 bash resolver twin)
REM   15. tests/verify-upgrade-resolver.cmd     (Phase-33 CMD resolver + parity)
REM   16. sh/tests/verify-upgrade-payloads.bash (Phase-33 acquisition + staging)
REM   17. tests/verify-upgrade-payloads.cmd     (Phase-33 assembly + gates + purge)
REM   18. tests/verify-upgrade-media.cmd        (consigned record + staged media)
REM   19. the assembly doc markers (winning set / GPLv3 / exFAT)
REM
REM A red link is diagnosable by its GATE number: every link echoes one
REM numbered line before running and a PASS line after. Bash resolves at
REM runtime (bare PATH first, the Git for Windows fallback second) - the
REM contract-twin idiom. Success sentinel: UPGRADE-PHASE-GATE-PASS.
REM
REM ENVIRONMENT: run this gate from a clean MSYS environment. If
REM MSYS2_ARG_CONV_EXCL='*' is inherited from the caller, the bash-side
REM children that invoke Windows binaries with POSIX paths (the bash
REM batteries' hashdeep calls) receive unconverted paths and fail - the
REM gate was consigned green WITHOUT the exclusion (33-04 consigned run).
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

echo [GATE 1] bash -n syntax over the five Phase-32 bash files + the Phase-33 acquisition bash files...
"%BASH_EXE%" -n sh/download-updates-tasks/50-superseded-updates.bash sh/libraries/upgrade-selection.bash sh/tests/verify-reboot-cycle.bash sh/tests/verify-shield-filter.bash sh/tests/verify-upgrade-contracts.bash sh/download-updates-tasks/62-upgrade-payloads.bash sh/libraries/upgrade-payloads.bash sh/tests/verify-upgrade-payloads.bash
if errorlevel 1 (
  echo FAIL: GATE 1 red - bash -n syntax check failed on a Phase-32/33 bash file
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

REM =======================================================================
REM Phase 33 extension (plan 33-04): the original 13 links above are
REM byte-identical to the consigned 32-04 chain - Phase-33 links APPEND
REM as GATE 14..19 (DEC-32-10 consignment discipline: extend, never
REM rewrite). The resolver twins, the acquisition batteries on both
REM platforms, the media gate and the assembly-doc markers join the chain.
REM =======================================================================

echo [GATE 14] bash resolver twin battery...
"%BASH_EXE%" sh/tests/verify-upgrade-resolver.bash
if errorlevel 1 (
  echo FAIL: GATE 14 red - the bash resolver battery is not green
  goto Fail
)
echo [GATE 14] PASS

echo [GATE 15] CMD resolver launcher (VBS positive + negatives + byte parity)...
call tests\verify-upgrade-resolver.cmd
if errorlevel 1 (
  echo FAIL: GATE 15 red - the CMD resolver launcher is not green
  goto Fail
)
echo [GATE 15] PASS

echo [GATE 16] bash payload acquisition battery (download + staging + purge)...
"%BASH_EXE%" sh/tests/verify-upgrade-payloads.bash
if errorlevel 1 (
  echo FAIL: GATE 16 red - the bash payloads battery is not green
  goto Fail
)
echo [GATE 16] PASS

echo [GATE 17] CMD payload acquisition battery (assembly + refuse-staging + staging + db + purge)...
call tests\verify-upgrade-payloads.cmd
if errorlevel 1 (
  echo FAIL: GATE 17 red - the CMD payloads battery is not green
  goto Fail
)
echo [GATE 17] PASS

echo [GATE 18] the media gate (consigned record + staged media + contingency branch)...
call tests\verify-upgrade-media.cmd
if errorlevel 1 (
  echo FAIL: GATE 18 red - the media gate is not green
  goto Fail
)
echo [GATE 18] PASS

echo [GATE 19] the assembly doc markers (winning set + GPLv3 + exFAT guidance)...
findstr /I /C:"winning" doc\upgrade-media-assembly.md >nul 2>&1
if errorlevel 1 (
  echo FAIL: GATE 19 red - the doc carries no winning-set section
  goto Fail
)
findstr /I /C:"GPLv3" doc\upgrade-media-assembly.md >nul 2>&1
if errorlevel 1 (
  echo FAIL: GATE 19 red - the doc carries no GPLv3 note
  goto Fail
)
findstr /I /C:"exFAT" doc\upgrade-media-assembly.md >nul 2>&1
if errorlevel 1 (
  echo FAIL: GATE 19 red - the doc carries no exFAT guidance
  goto Fail
)
echo [GATE 19] PASS

echo.
echo =======================================================================
echo UPGRADE-PHASE-GATE-PASS: all 19 links green in one run.
echo =======================================================================
popd
exit /b 0

:Fail
echo.
echo =======================================================================
echo FAILURE: upgrade phase gate failed - see the named GATE above.
echo =======================================================================
popd
exit /b 1
