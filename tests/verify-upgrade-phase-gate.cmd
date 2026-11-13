@echo off
setlocal

REM =======================================================================
REM WSUS Offline Update - Upgrade Phase Gate (consigned; extended by 33-04 and 34-03)
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
REM   20. tests/verify-fullupgrade-cycle.cmd    (Phase-34 CMD full-FU twin:
REM       census + states S1-S17 + parity lock)
REM   21. sh/tests/verify-fullupgrade-cycle.bash (Phase-34 bash evaluator
REM       twin: S1-S17 over byte-identical golden rows + 24-literal census)
REM   22. the engine census (frozen flag-set == 2, /compat scanonly == 1,
REM       bypass tokens == 0, all nine documented hex codes present)
REM   23. the seam-order assert (:SkipBuildUpgrade, then :FullUpgrade, then
REM       the WUA comment - line numbers strictly ordered)
REM   24. tests/verify-offline-audit.cmd        (audit regression battery)
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

REM =======================================================================
REM Phase 34 extension (plan 34-03): the 19 links above stay byte-identical
REM to the consigned 33-04 chain - Phase-34 links APPEND as GATE 20..24
REM (DEC-32-10 consignment discipline: extend, never rewrite). The full-FU
REM twins on both platforms, the engine census, the seam-order assert and
REM the audit regression battery join the chain. The census keeps the
REM 32-01 lesson: full-path System32 find.exe/findstr.exe, never plain find.
REM =======================================================================

set "ENGINE=client\cmd\DoUpdate.cmd"
set "FIND_EXE=%SystemRoot%\System32\find.exe"

echo [GATE 20] CMD full-FU twin battery (census + states S1-S17 + parity lock)...
call tests\verify-fullupgrade-cycle.cmd
if errorlevel 1 (
  echo FAIL: GATE 20 red - the CMD full-FU twin is not green
  goto Fail
)
echo [GATE 20] PASS

echo [GATE 21] bash full-FU twin (evaluator, S1-S17 + 24-literal source census)...
"%BASH_EXE%" sh/tests/verify-fullupgrade-cycle.bash
if errorlevel 1 (
  echo FAIL: GATE 21 red - the bash full-FU twin is not green
  goto Fail
)
echo [GATE 21] PASS

echo [GATE 22] engine census (frozen flag-set, scanonly, bypass tokens, nine hex codes)...
for /f %%N in ('findstr /C:"/auto upgrade /quiet /noreboot /eula accept /dynamicupdate disable" "%ENGINE%" ^| "%FIND_EXE%" /C /V ""') do set "CNT_FLAGS=%%N"
if not "%CNT_FLAGS%"=="2" (
  echo FAIL: GATE 22 red - frozen flag-set census is "%CNT_FLAGS%", expected exactly 2
  goto Fail
)
for /f %%N in ('findstr /C:"/compat scanonly" "%ENGINE%" ^| "%FIND_EXE%" /C /V ""') do set "CNT_SCAN=%%N"
if not "%CNT_SCAN%"=="1" (
  echo FAIL: GATE 22 red - scanonly census is "%CNT_SCAN%", expected exactly 1
  goto Fail
)
for /f %%N in ('findstr /I /C:"/pkey" /C:"/SkipFinalize" /C:"/Finalize" /C:"/ImageIndex" "%ENGINE%" ^| "%FIND_EXE%" /C /V ""') do set "CNT_BYPASS=%%N"
if not "%CNT_BYPASS%"=="0" (
  echo FAIL: GATE 22 red - bypass token census is "%CNT_BYPASS%", expected 0
  goto Fail
)
for %%C in (C1900210 C1900208 C1900204 C1900200 C190020E C190010E C1900215 C1900132 C1900101) do (
  findstr /I /C:"%%C" "%ENGINE%" >nul 2>&1
  if errorlevel 1 (
    echo FAIL: GATE 22 red - documented hex code %%C missing from the engine
    goto Fail
  )
)
for /f %%N in ('findstr /C:"wou_fullupgrade_attempts.txt" "%ENGINE%" ^| "%FIND_EXE%" /C /V ""') do set "CNT_FU_RECORD=%%N"
if not "%CNT_FU_RECORD%"=="7" (
  echo FAIL: GATE 22 red - the full-FU attempts record filename census is "%CNT_FU_RECORD%", expected exactly 7 - the deletion surface is the contract
  goto Fail
)
echo [GATE 22] PASS

echo [GATE 23] seam-order assert - :SkipBuildUpgrade, then :FullUpgrade, then the WUA comment, strictly ordered...
set "SEAM_SKIP="
set "SEAM_FU="
set "SEAM_WUA="
for /f "tokens=1 delims=:" %%N in ('findstr /N /R /C:"^:SkipBuildUpgrade$" "%ENGINE%"') do set "SEAM_SKIP=%%N"
for /f "tokens=1 delims=:" %%N in ('findstr /N /R /C:"^:FullUpgrade$" "%ENGINE%"') do set "SEAM_FU=%%N"
for /f "tokens=1 delims=:" %%N in ('findstr /N /C:"rem *** Update Windows Update Agent ***" "%ENGINE%"') do set "SEAM_WUA=%%N"
if not defined SEAM_SKIP (
  echo FAIL: GATE 23 red - seam anchor :SkipBuildUpgrade not found in the engine
  goto Fail
)
if not defined SEAM_FU (
  echo FAIL: GATE 23 red - seam anchor :FullUpgrade not found in the engine
  goto Fail
)
if not defined SEAM_WUA (
  echo FAIL: GATE 23 red - seam anchor WUA comment not found in the engine
  goto Fail
)
if %SEAM_FU% LEQ %SEAM_SKIP% (
  echo FAIL: GATE 23 red - :FullUpgrade line %SEAM_FU% is not strictly after :SkipBuildUpgrade line %SEAM_SKIP%
  goto Fail
)
if %SEAM_FU% GEQ %SEAM_WUA% (
  echo FAIL: GATE 23 red - :FullUpgrade line %SEAM_FU% is not strictly before the WUA comment line %SEAM_WUA%
  goto Fail
)
echo [GATE 23] PASS

echo [GATE 24] audit regression battery (auditonly skips the full-FU lane)...
call tests\verify-offline-audit.cmd
if errorlevel 1 (
  echo FAIL: GATE 24 red - the audit regression battery is not green
  goto Fail
)
echo [GATE 24] PASS

echo.
echo =======================================================================
echo UPGRADE-PHASE-GATE-PASS: all 24 links green in one run.
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
