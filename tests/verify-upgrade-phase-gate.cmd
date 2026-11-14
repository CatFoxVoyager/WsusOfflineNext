@echo off
setlocal

REM =======================================================================
REM WSUS Offline Update - Upgrade Phase Gate (consigned; extended by 33-04, 34-03, 35-02, 36-05 and 37-03)
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
REM    2. sh/tests/verify-reboot-cycle.bash     (evaluator, 16 states)
REM    3. tests/verify-reboot-cycle.cmd         (real engine, 16 states)
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
REM   25. tests/verify-fullupgrade-cycle.cmd    (Phase-35 state set: census +
REM       states S1-S21 + the real-caller stub section + the 30-literal
REM       parity lock; the twin's own fail-closed exit is the verdict and
REM       its PASS census must reach 21)
REM   26. sh/tests/verify-fullupgrade-cycle.bash (Phase-35 bash evaluator
REM       twin: S1-S21 + the 30-literal source census over the REAL engine
REM       and the real stub)
REM   27. tests/verify-recall-stub-cycle.cmd    (the dedicated real-caller
REM       stub battery, C1-C7 + recorded can-fail; RECALL-STUB-CYCLE-PASS
REM       required in its output)
REM   28. ci/tests/test-native-installer-units.sh (compiled TAP battery;
REM       exit 0 with the resume: upgrade cases green)
REM   29. the engine marker census (marker filename == 4,
REM       FullUpgradeClearMarker == 3, POSED == 2, RESTORED == 2, restore
REM       Info == 2, the :Cleanup-to-:Installed region == 0, the stub guard
REM       literal == 1 in RecallStub.cmd, attempts == 7 unchanged)
REM   30. the GUI census (RES_UPGRADE_MARKER == 3 in resume.pas; the
REM       installer.lpr line-order chain ResDeleteResume <
REM       ResUpgradeResumeBlocked < the ResumePending branch)
REM   31. parity equality (PARITY_LIT entries == 30 == census_literals
REM       entries; each of the six new literals present in BOTH twin files)
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
REM
REM MIXED-CASE OBSERVABLE (pinned by 36-05 - UI-SPEC unresolved row,
REM DEC-36-07 adjacent): the os-upgrades selection grammar is a flat key
REM list; the acquisition takes the FIRST selected key whose upgrades.txt
REM row carries fu_media=1 AND whose arch matches the invocation's scope
REM arch; every EKB key flows to the EKB lane. One full-FU target per
REM medium - the one-per-medium rule is full-FU only, and no UI copy
REM claims one-target-per-medium for EKB. Comment-only pin - zero engine
REM edits.
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

REM =======================================================================
REM Phase 35 extension (plan 35-02): the 24 links above stay byte-identical
REM to the consigned 34-03 chain - Phase-35 links APPEND as GATE 25..31
REM (DEC-32-10 consignment discipline: extend, never rewrite). The extended
REM full-FU twins over the full state set, the dedicated real-caller stub
REM battery, the compiled TAP battery, the engine marker census, the GUI
REM ownership/ordering census and the cross-tier parity equality join the
REM chain (DEC-35-12). The 35 extension rides BESIDE the frozen links - a
REM gate that reaches green by dropping a legacy link is a failed
REM verification (threat T-35-07).
REM =======================================================================

echo [GATE 25] CMD full-FU twin over the full state set (census + S1-S21 + stub section + 30-literal parity lock)...
call tests\verify-fullupgrade-cycle.cmd > "%TEMP%\wou_gate_t25.log" 2>&1
if errorlevel 1 (
  echo FAIL: GATE 25 red - the CMD full-FU twin is not green over the full state set
  type "%TEMP%\wou_gate_t25.log"
  del "%TEMP%\wou_gate_t25.log" 2>nul
  goto Fail
)
for /f %%N in ('findstr /C:"PASS" "%TEMP%\wou_gate_t25.log" ^| "%FIND_EXE%" /C /V ""') do set "CNT_T25=%%N"
if not defined CNT_T25 set "CNT_T25=0"
if %CNT_T25% LSS 21 (
  echo FAIL: GATE 25 red - PASS census is "%CNT_T25%", expected at least 21
  del "%TEMP%\wou_gate_t25.log" 2>nul
  goto Fail
)
del "%TEMP%\wou_gate_t25.log" 2>nul
echo [GATE 25] PASS

echo [GATE 26] bash full-FU twin over the full state set (S1-S21 + 30-literal source census)...
"%BASH_EXE%" sh/tests/verify-fullupgrade-cycle.bash > "%TEMP%\wou_gate_t26.log" 2>&1
if errorlevel 1 (
  echo FAIL: GATE 26 red - the bash full-FU twin is not green over the full state set
  type "%TEMP%\wou_gate_t26.log"
  del "%TEMP%\wou_gate_t26.log" 2>nul
  goto Fail
)
for /f %%N in ('findstr /C:"PASS" "%TEMP%\wou_gate_t26.log" ^| "%FIND_EXE%" /C /V ""') do set "CNT_T26=%%N"
if not defined CNT_T26 set "CNT_T26=0"
if %CNT_T26% LSS 21 (
  echo FAIL: GATE 26 red - PASS census is "%CNT_T26%", expected at least 21
  del "%TEMP%\wou_gate_t26.log" 2>nul
  goto Fail
)
del "%TEMP%\wou_gate_t26.log" 2>nul
echo [GATE 26] PASS

echo [GATE 27] the dedicated real-caller stub battery (C1-C7 + recorded can-fail)...
call tests\verify-recall-stub-cycle.cmd > "%TEMP%\wou_gate_t27.log" 2>&1
if errorlevel 1 (
  echo FAIL: GATE 27 red - the real-caller stub battery is not green
  type "%TEMP%\wou_gate_t27.log"
  del "%TEMP%\wou_gate_t27.log" 2>nul
  goto Fail
)
findstr /C:"RECALL-STUB-CYCLE-PASS" "%TEMP%\wou_gate_t27.log" >nul 2>&1
if errorlevel 1 (
  echo FAIL: GATE 27 red - the stub battery pass sentinel RECALL-STUB-CYCLE-PASS is absent
  type "%TEMP%\wou_gate_t27.log"
  del "%TEMP%\wou_gate_t27.log" 2>nul
  goto Fail
)
del "%TEMP%\wou_gate_t27.log" 2>nul
echo [GATE 27] PASS

echo [GATE 28] compiled TAP battery (lazbuild i386; resume: upgrade cases included)...
"%BASH_EXE%" ci/tests/test-native-installer-units.sh
if errorlevel 1 (
  echo FAIL: GATE 28 red - the compiled TAP battery is not green
  goto Fail
)
echo [GATE 28] PASS

echo [GATE 29] engine marker census (pose/clear/restore literals, :Cleanup zero-ratchet, stub guard, attempts 7)...
for /f %%N in ('findstr /C:"wou_upgrade_in_progress.txt" "%ENGINE%" ^| "%FIND_EXE%" /C /V ""') do set "CNT_MARKER=%%N"
if not "%CNT_MARKER%"=="4" (
  echo FAIL: GATE 29 red - marker filename census is "%CNT_MARKER%", expected exactly 4
  goto Fail
)
for /f %%N in ('findstr /C:"FullUpgradeClearMarker" "%ENGINE%" ^| "%FIND_EXE%" /C /V ""') do set "CNT_CLEAR=%%N"
if not "%CNT_CLEAR%"=="3" (
  echo FAIL: GATE 29 red - clear subroutine census is "%CNT_CLEAR%", expected exactly 3
  goto Fail
)
for /f %%N in ('findstr /C:"FULLUPGRADE-MARKER-POSED" "%ENGINE%" ^| "%FIND_EXE%" /C /V ""') do set "CNT_POSED=%%N"
if not "%CNT_POSED%"=="2" (
  echo FAIL: GATE 29 red - POSED sentinel census is "%CNT_POSED%", expected exactly 2 - the echo + Log pair
  goto Fail
)
for /f %%N in ('findstr /C:"RECALL-RESTORED" "%ENGINE%" ^| "%FIND_EXE%" /C /V ""') do set "CNT_RESTORED=%%N"
if not "%CNT_RESTORED%"=="2" (
  echo FAIL: GATE 29 red - RECALL-RESTORED census is "%CNT_RESTORED%", expected exactly 2 - the echo + Log pair
  goto Fail
)
for /f %%N in ('findstr /C:"restoring safe state after failed upgrade" "%ENGINE%" ^| "%FIND_EXE%" /C /V ""') do set "CNT_RESTOREINFO=%%N"
if not "%CNT_RESTOREINFO%"=="2" (
  echo FAIL: GATE 29 red - restore Info census is "%CNT_RESTOREINFO%", expected exactly 2 - the echo + Log pair
  goto Fail
)
"%BASH_EXE%" -c "if awk '/^:Cleanup$/,/^:Installed$/' client/cmd/DoUpdate.cmd | grep -qF 'wou_upgrade_in_progress'; then echo marker literal found inside the :Cleanup region; exit 1; fi"
if errorlevel 1 (
  echo FAIL: GATE 29 red - the :Cleanup region gained a marker reference - the zero-census ratchet broke, a cleanup-deleted marker re-arms the machinery mid-upgrade
  goto Fail
)
for /f %%N in ('findstr /C:"Upgrade in progress - automatic recall suppressed" "client\cmd\RecallStub.cmd" ^| "%FIND_EXE%" /C /V ""') do set "CNT_STUBGUARD=%%N"
if not "%CNT_STUBGUARD%"=="1" (
  echo FAIL: GATE 29 red - stub guard literal census is "%CNT_STUBGUARD%", expected exactly 1 in RecallStub.cmd
  goto Fail
)
for /f %%N in ('findstr /C:"wou_fullupgrade_attempts.txt" "%ENGINE%" ^| "%FIND_EXE%" /C /V ""') do set "CNT_ATTEMPTS=%%N"
if not "%CNT_ATTEMPTS%"=="7" (
  echo FAIL: GATE 29 red - the frozen attempts census moved from 7 to "%CNT_ATTEMPTS%" - a disturbed 34 seam
  goto Fail
)
echo [GATE 29] PASS

echo [GATE 30] GUI census - RES_UPGRADE_MARKER ownership + decide-before-delete ordering in the /resume chain...
for /f %%N in ('findstr /C:"RES_UPGRADE_MARKER" "src-native\installer\resume.pas" ^| "%FIND_EXE%" /C /V ""') do set "CNT_GUIMARKER=%%N"
if not "%CNT_GUIMARKER%"=="3" (
  echo FAIL: GATE 30 red - RES_UPGRADE_MARKER census in resume.pas is "%CNT_GUIMARKER%", expected exactly 3
  goto Fail
)
set "LPR_DELETE="
set "LPR_BLOCKED="
set "LPR_PENDING="
for /f "tokens=1 delims=:" %%N in ('findstr /N /C:"ResDeleteResume;" "src-native\installer\installer.lpr"') do set "LPR_DELETE=%%N"
for /f "tokens=1 delims=:" %%N in ('findstr /N /C:"ResUpgradeResumeBlocked(DetectOsInfo.Build)" "src-native\installer\installer.lpr"') do set "LPR_BLOCKED=%%N"
for /f "tokens=1 delims=:" %%N in ('findstr /N /C:"if ResumePending then" "src-native\installer\installer.lpr"') do set "LPR_PENDING=%%N"
if not defined LPR_DELETE (
  echo FAIL: GATE 30 red - ordering anchor ResDeleteResume; not found in installer.lpr
  goto Fail
)
if not defined LPR_BLOCKED (
  echo FAIL: GATE 30 red - ordering anchor ResUpgradeResumeBlocked with the DetectOsInfo.Build argument not found in installer.lpr
  goto Fail
)
if not defined LPR_PENDING (
  echo FAIL: GATE 30 red - ordering anchor "if ResumePending then" not found in installer.lpr
  goto Fail
)
if %LPR_BLOCKED% LEQ %LPR_DELETE% (
  echo FAIL: GATE 30 red - the stand-down branch line %LPR_BLOCKED% is not strictly after ResDeleteResume line %LPR_DELETE% - decide-before-delete ordering
  goto Fail
)
if %LPR_PENDING% LEQ %LPR_BLOCKED% (
  echo FAIL: GATE 30 red - the ResumePending branch line %LPR_PENDING% is not strictly after the stand-down branch line %LPR_BLOCKED% - converged falls through
  goto Fail
)
echo [GATE 30] PASS

echo [GATE 31] parity equality - 30 PARITY_LIT entries == 30 census entries, six new literals in BOTH twins...
for /f %%N in ('findstr /R /C:"^set .PARITY_LIT_[0-9]*=" "tests\verify-fullupgrade-cycle.cmd" ^| "%FIND_EXE%" /C /V ""') do set "CNT_PLIT=%%N"
if not "%CNT_PLIT%"=="30" (
  echo FAIL: GATE 31 red - the CMD twin's PARITY_LIT list is "%CNT_PLIT%" entries, expected exactly 30
  goto Fail
)
"%BASH_EXE%" -c "sed -n '/^census_literals=(/,/^)/p' sh/tests/verify-fullupgrade-cycle.bash | grep -c '^    '" > "%TEMP%\wou_gate_t31.log" 2>nul
set /p CNT_CLIT=<"%TEMP%\wou_gate_t31.log"
del "%TEMP%\wou_gate_t31.log" 2>nul
if not "%CNT_CLIT%"=="30" (
  echo FAIL: GATE 31 red - the bash twin's census_literals list is "%CNT_CLIT%" entries, expected exactly 30
  goto Fail
)
for %%L in ("wou_upgrade_in_progress.txt" "FullUpgradeClearMarker" "FULLUPGRADE-MARKER-POSED" "RECALL-RESTORED" "restoring safe state after failed upgrade" "Upgrade in progress - automatic recall suppressed") do (
  findstr /C:%%L "tests\verify-fullupgrade-cycle.cmd" >nul 2>&1
  if errorlevel 1 (
    echo FAIL: GATE 31 red - parity literal missing from the CMD twin: %%~L
    goto Fail
  )
  findstr /C:%%L "sh\tests\verify-fullupgrade-cycle.bash" >nul 2>&1
  if errorlevel 1 (
    echo FAIL: GATE 31 red - parity literal missing from the bash twin: %%~L
    goto Fail
  )
)
echo [GATE 31] PASS

REM =======================================================================
REM Phase 36 extension (plan 36-05): the 31 links above stay byte-identical
REM to the consigned 35-02 chain - Phase-36 links APPEND as GATE 32..36
REM (DEC-32-10 consignment discipline: extend, never rewrite). The six-test
REM GUI contracts battery carrying the Phase-36 picker pins, the installer
REM strings gate, the consent TAP floors over all eight floors, the SC4
REM source pins over the generator host and its frontend, and the
REM engines-untouched bash parse floor join the chain. The red run that
REM preceded this consignment bit through the WSON_GENERATOR_HOST_CS
REM scratch-copy override: in the full chain the frozen GATE 12 twin
REM byte-shares the six-test battery and fail-closed first - a GATE 32
REM named red is structurally unreachable in one sequential chain - and a
REM scoped scratch copy of this gate carrying GATE 32..36 alone recorded
REM the GATE 32 red by name (the 34-03 wrong-location-copy protocol, the
REM copy never committed). The consigned green run covers all 36
REM executable links.
REM =======================================================================

echo [GATE 32] GUI contracts six-test battery (picker pins included)...
python tests\verify-gui-contracts.py
if errorlevel 1 (
  echo FAIL: GATE 32 red - the GUI contracts battery is not green
  goto Fail
)
echo [GATE 32] PASS

echo [GATE 33] installer strings gate - DE/EN bilingual parity...
python ci\tests\test-native-installer-strings.py
if errorlevel 1 (
  echo FAIL: GATE 33 red - the installer strings gate is not green
  goto Fail
)
echo [GATE 33] PASS

echo [GATE 34] consent TAP floors - compiled units battery, all eight floors...
"%BASH_EXE%" ci/tests/test-native-installer-units.sh
if errorlevel 1 (
  echo FAIL: GATE 34 red - the consent TAP floors are not green
  goto Fail
)
echo [GATE 34] PASS

echo [GATE 35] SC4 source pins - spread conditional, payload fragment, token prefix, env carriage...
"%BASH_EXE%" -c "grep -cF 'upgradeTouched || upgradeSelection.length > 0 || upgradeFullTarget' src-modern/generator/src/App.tsx" > "%TEMP%\wou_gate_t35a.log" 2>nul
set /p CNT_T35A=<"%TEMP%\wou_gate_t35a.log"
del "%TEMP%\wou_gate_t35a.log" 2>nul
if not "%CNT_T35A%"=="1" (
  echo FAIL: GATE 35 red - the payload rule spread-conditional census is "%CNT_T35A%", expected exactly 1 in App.tsx
  goto Fail
)
"%BASH_EXE%" -c "grep -cF 'upgrade: upgradeFullTarget' src-modern/generator/src/App.tsx" > "%TEMP%\wou_gate_t35b.log" 2>nul
set /p CNT_T35B=<"%TEMP%\wou_gate_t35b.log"
del "%TEMP%\wou_gate_t35b.log" 2>nul
if not "%CNT_T35B%"=="1" (
  echo FAIL: GATE 35 red - the upgrade payload property census is "%CNT_T35B%", expected exactly 1 in App.tsx
  goto Fail
)
"%BASH_EXE%" -c "grep -cF '/includeupgrade:' src-modern/generator/host/Program.cs" > "%TEMP%\wou_gate_t35c.log" 2>nul
set /p CNT_T35C=<"%TEMP%\wou_gate_t35c.log"
del "%TEMP%\wou_gate_t35c.log" 2>nul
if not defined CNT_T35C set "CNT_T35C=0"
if %CNT_T35C% LSS 1 (
  echo FAIL: GATE 35 red - the /includeupgrade: token composition census is "%CNT_T35C%", expected at least 1 in Program.cs
  goto Fail
)
"%BASH_EXE%" -c "grep -F 'psi.EnvironmentVariables' src-modern/generator/host/Program.cs | grep -cF 'WOU_UPGRADE_LANG'" > "%TEMP%\wou_gate_t35d.log" 2>nul
set /p CNT_T35D=<"%TEMP%\wou_gate_t35d.log"
del "%TEMP%\wou_gate_t35d.log" 2>nul
if not "%CNT_T35D%"=="1" (
  echo FAIL: GATE 35 red - the WOU_UPGRADE_LANG env carriage census is "%CNT_T35D%", expected exactly 1 in Program.cs
  goto Fail
)
echo [GATE 35] PASS

echo [GATE 36] engines-untouched parse floor - bash -n over the consumed bash engines...
"%BASH_EXE%" -n sh/download-updates.bash sh/update-generator.bash sh/libraries/upgrade-payloads.bash
if errorlevel 1 (
  echo FAIL: GATE 36 red - bash -n syntax check failed on a consumed bash engine file
  goto Fail
)
echo [GATE 36] PASS

REM =======================================================================
REM Phase 37 extension (plan 37-03): the 36 links above stay byte-identical
REM to the consigned 36-05 chain - Phase-37 links APPEND as GATE 37
REM (DEC-32-10 consignment discipline: extend, never rewrite). The bash
REM media-gate twin (sh/tests/verify-upgrade-media.bash, VAL-01c) joins
REM the chain; the 16-state cycle twins flow through their existing frozen
REM links (GATE 2/3), the roster family census cases through the contracts
REM links (GATE 6/7), and the wxp-family TAP case and picker exclusion pins
REM through GATE 32/34's instruments.
REM =======================================================================

echo [GATE 37] bash media-gate twin (consigned record + staged media, bash pipeline)...
"%BASH_EXE%" sh/tests/verify-upgrade-media.bash
if errorlevel 1 (
  echo FAIL: GATE 37 red - the bash media twin is not green
  goto Fail
)
echo [GATE 37] PASS

echo.
echo =======================================================================
echo UPGRADE-PHASE-GATE-PASS: all 37 links green in one run.
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
