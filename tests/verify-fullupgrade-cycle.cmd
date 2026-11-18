@echo off
setlocal enabledelayedexpansion

REM =======================================================================
REM WSUS Offline Update - Full Upgrade Cycle Regression Suite (Windows CMD)
REM File: tests\verify-fullupgrade-cycle.cmd
REM
REM Drives the REAL engine (client\cmd\DoUpdate.cmd copy) via /testbuildupgrade
REM over mock media trees and the WOU_FU_TEST_* mock-RC hooks (DEC-34-07):
REM the engine NEVER launches real media in this battery. The real setup.exe
REM invocation shapes are pinned by the census case + the recorded can-fail
REM mutation proofs (see "Can-fail proofs" at the bottom of this header).
REM
REM   Census: frozen flag-set == 2 call sites in the REAL engine file; zero
REM           bypass tokens; /compat scanonly == 1
REM   State S1:  no /upgradeos target -> the full-FU lane is a silent no-op
REM              (zero FULLUPGRADE- lines in the log)
REM   State S2:  LTSB/LTSC edition -> named skip + FULLUPGRADE-SKIP-LTSC -> 0
REM   State S3:  convergence (observed build == target) -> FULLUPGRADE-CONVERGED,
REM              attempts record purged, NO media literal -> 0
REM   State S4:  media missing (target 26999, no staged tree) ->
REM              FULLUPGRADE-MEDIA-MISSING -> 0
REM   State S5:  media incomplete (sources\install.esd absent) ->
REM              FULLUPGRADE-MEDIA-INCOMPLETE naming the file -> 0
REM   State S6:  media ambiguous (en-us + fr-fr trees) ->
REM              FULLUPGRADE-MEDIA-AMBIGUOUS -> 0
REM   State S7:  language mismatch (en-us media vs fr-fr system) ->
REM              FULLUPGRADE-LANG-REFUSED naming BOTH tokens -> 0,
REM              no FULLUPGRADE-STAGED anywhere in the log
REM   State S8:  scan refusals via WOU_FU_TEST_SCAN_RC: 0xC1900200 ->
REM              FULLUPGRADE-REFUSED-SYSREQ; 0xC190020E ->
REM              FULLUPGRADE-REFUSED-DISKSPACE; both -> 0, no launch
REM   State S9:  staged termination: SCAN_RC=0xC1900210 + LAUNCH_RC=3010 ->
REM              SCAN-PASS then FULLUPGRADE-STAGED, log line
REM              "Info: Installation successful (Updates pending)", exit 3011,
REM              console NEVER shows the WUA check (pass terminated first)
REM   State S10: suspect: LAUNCH_RC=0 -> FULLUPGRADE-SUSPECT with the
REM              never-reported-as-success wording, exit 0, no STAGED
REM   State S11: rollback: LAUNCH_RC=0xC1900101 -> FULLUPGRADE-ROLLBACK -> 0
REM   State S12: undecoded: LAUNCH_RC=0xC1900199 ->
REM              "failed with undecoded exit code 0xC1900199" +
REM              FULLUPGRADE-FAIL -> 0
REM   State S13: normalization: SCAN_RC=-1047526912 (signed-decimal twin of
REM              0xC1900200) -> the SAME TPM/CPU refusal as state S8 -> 0
REM   State S14: attempts stall (DEC-34-06): seeded count 1 at build 26100 ->
REM              run 1 advances the record to 2 -> run 2 reads 2, computes 3,
REM              HALTS with the stall literal + FULLUPGRADE-STALL-HALT, exit 0,
REM              record deleted, launch site NOT reached
REM   State S15: advancement clear (a): record at build 26100, run at 26200
REM              target 26999 -> guard cleared, record rewritten fresh (count 1),
REM              launch proceeds; (b) convergence fires FIRST: the pre-existing
REM              record is purged by the converged delete lines, no launch
REM   State S16: audit inert (mirror of the 34-01 audit case, instrument kept
REM              independent): /auditonly + /upgradeos:26200 over the report
REM              entry -> zero FULLUPGRADE- lines, attempts record untouched
REM   State S17: EKB fall-through (DEC-34-05): the EKB lane refuses the chosen
REM              target (enablement payload absent - its own frozen literal)
REM              and the full-FU lane then runs the media probe and stages the
REM              same target - both lanes observable in ONE run
REM   State S18: marker pose (RECALL-01): the staged pass writes the upgrade-
REM              in-progress marker beside the attempts record, before the
REM              launch mode split (DEC-35-01) - POSED sentinel, marker line 1
REM              begins full,<target>,..., attempts record coexists
REM   State S19: converged clear (RECALL-02 pivot): seeded marker + observed
REM              build == target -> FULLUPGRADE-CONVERGED, marker AND attempts
REM              deleted, no media probe
REM   State S20: stall restore (RECALL-02 tail): seeded marker + two stagnant
REM              runs -> the halt emits FULLUPGRADE-STALL-HALT + RECALL-
REM              RESTORED, clears both files, armed-state gate SHUT in the
REM              w100-shaped sandbox (no restore Info line, no CleanupRecall)
REM   State S21: refusal survival (DEC-35-09): refusal passes never pose; a
REM              seeded marker survives byte-identically
REM   Stub section: the REAL RecallStub.cmd drives two cases from sandbox
REM              copies behind the one-line shutdown mock (SANDBOX-SHUTDOWN-
REM              MOCKED) - marker present = stay-out (no relaunch, no cleanup
REM              canary); marker absent = the relaunch canary fires (the
REM              negative control). Marker seeds live at the REAL probe path
REM              %SystemRoot%\Temp with a pre-flight absence assert and
REM              per-case cleanup (DEC-35-08; the real caller is the
REM              instrument).
REM   Parity lock: the PARITY_LIT_* list (30 entries, byte-identical with the
REM              bash twin's census_literals array in sh\tests\verify-fullupgrade-
REM              cycle.bash) is findstr'd against the REAL engine + a count
REM              assert. The 35 extension (DEC-35-10/11: the six marker
REM              literals, 24 to 30) landed in the SAME commit as the bash
REM              twin's extension (the 31-04 cross-tier parity rule).
REM
REM Attempts-record lifecycle (DEC-34-06): the record counts ACROSS runs - the
REM battery seeds it before state S4 and asserts it SURVIVES every refusal pass
REM (S4-S8), gets INCREMENTED by the staged run (S9), and is reset between
REM independent launch states (S10-S13): each battery state simulates an
REM independent machine.
REM
REM Can-fail proofs (recorded run notes - perform in a scratch copy, never
REM leave the mutation behind):
REM   (a) copy this battery to %TEMP%, flip ONE expected literal (the S8
REM       TPM/CPU message), run the scratch -> it must exit non-zero with a
REM       named FAIL; delete the scratch afterwards.
REM   (b) copy client\cmd\DoUpdate.cmd to a scratch, strip the EULA flag from
REM       the launch line, run the census findstr against the scratch ->
REM       zero hits proves the census can fail; delete the scratch.
REM   (c) copy this battery to %TEMP%, flip the S14 expected stall literal,
REM       run the scratch -> it must exit non-zero with a named FAIL at
REM       State S14; delete the scratch afterwards.
REM
REM Mock media trees (NEVER the real 2.5 GB media, DEC-34-07):
REM   %SANDBOX_ROOT%\upgrade\26200-x64\en-us\setup.exe + sources\install.esd
REM   (created with "type nul >"); the fr-fr variant for S6; NO tree for 26999.
REM The EKB payload cabs are stashed for states S4-S13 so the EKB lane refuses
REM deterministically and flow reaches the full-FU lane (the same ren/stash
REM discipline the reboot-cycle battery uses in its states 8/9). Restored in
REM :Cleanup.
REM =======================================================================

pushd "%~dp0.."
set "REPO_ROOT=%CD%"
popd

echo =======================================================================
echo WSUS Offline Update - Full Upgrade Cycle Test Suite (Windows CMD)
echo =======================================================================

REM Set up isolated test sandbox
set "SANDBOX_ROOT=%TEMP%\wou_test_fullupgrade_%RANDOM%_%RANDOM%"
set "MOCK_CMD=%SANDBOX_ROOT%\cmd"
set "MOCK_STATIC=%SANDBOX_ROOT%\static"
set "MOCK_GLB=%SANDBOX_ROOT%\w100-x64\glb"
set "MOCK_TEMP=%SANDBOX_ROOT%\temp"
set "MOCK_SYS_TEMP=%SANDBOX_ROOT%\sysroot_temp"
set "MOCK_UPGRADE=%SANDBOX_ROOT%\upgrade"
set "MOCK_MEDIA=%MOCK_UPGRADE%\26200-x64\en-us"

mkdir "%MOCK_CMD%" 2>nul
mkdir "%MOCK_STATIC%" 2>nul
mkdir "%MOCK_GLB%" 2>nul
mkdir "%MOCK_TEMP%" 2>nul
mkdir "%MOCK_SYS_TEMP%" 2>nul
mkdir "%MOCK_MEDIA%\sources" 2>nul

if not exist "%MOCK_SYS_TEMP%" (
  echo ERROR: Failed to create test sandbox at "%SANDBOX_ROOT%".
  exit /b 1
)

REM Populate mock environment - the REAL engine, copied
copy /y "%REPO_ROOT%\client\cmd\DoUpdate.cmd" "%MOCK_CMD%\DoUpdate.cmd" >nul 2>&1
if not exist "%MOCK_CMD%\DoUpdate.cmd" (
  echo ERROR: Failed to copy DoUpdate.cmd to test sandbox.
  goto Fail
)

REM Mock upgrade definition (golden rows identical to verify-reboot-cycle.cmd):
REM 26100 -> 26200 with prereq kb5064081 and eKB kb5054156, plus the synthetic
REM higher hop 26999 sharing the same payload KBs.
echo 26100,5074,kb5064081,26200,kb5054156>"%MOCK_STATIC%\StaticUpdateIds-BuildUpgrades.txt"
echo 26100,5074,kb5064081,26999,kb5054156>>"%MOCK_STATIC%\StaticUpdateIds-BuildUpgrades.txt"

REM Mock packages - stashed immediately: with the payloads absent the EKB lane
REM refuses deterministically (named refusal) and flow reaches :FullUpgrade,
REM which is the lane under test in states S4-S13. Restored in :Cleanup.
type nul >"%MOCK_GLB%\windows11.0-kb5064081-x64.cab"
type nul >"%MOCK_GLB%\windows11.0-kb5054156-x64.cab"
ren "%MOCK_GLB%\windows11.0-kb5064081-x64.cab" "fu_stash_pre.cab" >nul 2>&1
ren "%MOCK_GLB%\windows11.0-kb5054156-x64.cab" "fu_stash_epkg.cab" >nul 2>&1

REM Mock helper scripts
(
  echo @echo off
  echo exit /b 0
) >"%MOCK_CMD%\ListUpdatesToInstall.cmd"

(
  echo @echo off
  echo rem Simulate package installation requiring reboot
  echo exit /b 3011
) >"%MOCK_CMD%\InstallListedUpdates.cmd"

REM Mock full-upgrade media tree (stubs - never the real media)
type nul >"%MOCK_MEDIA%\setup.exe"
type nul >"%MOCK_MEDIA%\sources\install.esd"

REM Base environment configuration
set "OS_NAME=w100"
set "OS_ARCH=x64"
REM The :Installed recall block parses "if %OS_DOMAIN_ROLE% GEQ 4" unquoted -
REM a real system always has it (DetermineSystemProperties); pin standalone.
set "OS_DOMAIN_ROLE=0"
set "TEMP=%MOCK_TEMP%"
set "TMP=%MOCK_TEMP%"
set "WOU_TEMP_DIR=%MOCK_SYS_TEMP%"
set "UPDATE_LOGFILE=%MOCK_TEMP%\wou_update.log"
set "PATH=%MOCK_CMD%;%PATH%"
set "VERIFY_MODE="
set "DISM_MODE="
if exist "%UPDATE_LOGFILE%" del "%UPDATE_LOGFILE%" 2>nul

REM Host pre-flight (DEC-35-08): the battery never arms real recall state and
REM never auto-deletes real state found standing - a named error and no run.
if exist "%SystemRoot%\Temp\WOURecall" (
  echo ERROR: armed recall state exists at %SystemRoot%\Temp\WOURecall - restore the machine before running this battery ^(no auto-delete^).
  exit /b 1
)
if exist "%SystemRoot%\Temp\wou_upgrade_in_progress.txt" (
  echo ERROR: a real upgrade-in-progress marker exists at %SystemRoot%\Temp - remove it before running this battery ^(no auto-delete^).
  exit /b 1
)

REM -----------------------------------------------------------------------
REM Census: the frozen flag-set on the REAL engine file
REM -----------------------------------------------------------------------
echo [Test 1/25] Census: frozen flag-set == 2 call sites, zero bypass tokens...
set "CENSUS_FLAGSET="
for /f %%a in ('findstr /C:"/auto upgrade /quiet /noreboot /eula accept /dynamicupdate disable" "%REPO_ROOT%\client\cmd\DoUpdate.cmd" ^| "%SystemRoot%\System32\find.exe" /c /v ""') do set "CENSUS_FLAGSET=%%a"
if not "!CENSUS_FLAGSET!"=="2" (
  echo FAIL: Census expected the frozen flag-set at exactly 2 call sites, got !CENSUS_FLAGSET!.
  goto Fail
)
findstr /I /C:"/pkey" "%REPO_ROOT%\client\cmd\DoUpdate.cmd" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: Census found a bypass token /pkey in the engine.
  goto Fail
)
findstr /I /C:"SkipFinalize" "%REPO_ROOT%\client\cmd\DoUpdate.cmd" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: Census found a bypass token SkipFinalize in the engine.
  goto Fail
)
set "CENSUS_SCANONLY="
for /f %%a in ('findstr /C:"/compat scanonly" "%REPO_ROOT%\client\cmd\DoUpdate.cmd" ^| "%SystemRoot%\System32\find.exe" /c /v ""') do set "CENSUS_SCANONLY=%%a"
if not "!CENSUS_SCANONLY!"=="1" (
  echo FAIL: Census expected exactly one /compat scanonly call site, got !CENSUS_SCANONLY!.
  goto Fail
)
echo [PASS] Census: flag-set pinned at 2 call sites, scanonly at 1, zero bypass tokens.

REM -----------------------------------------------------------------------
REM State S1: No Target - the full-FU lane is a silent no-op
REM -----------------------------------------------------------------------
echo [Test 2/25] State S1: no /upgradeos target - zero FULLUPGRADE- lines...
set "OS_VER_MAJOR=10"
set "OS_VER_MINOR=0"
set "OS_VER_BUILD=26100"
set "OS_VER_BUILD_INTERNAL=26100"
set "OS_VER_REVIS=1000"
set "OS_LANG_EXT=en-us"
set "OS_EDITIONID=Professional"
set "WOU_FU_TEST_SCAN_RC="
set "WOU_FU_TEST_LAUNCH_RC="
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"

call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade >nul 2>&1
set "S1_EXIT=!errorlevel!"

findstr /C:"FULLUPGRADE-" "%UPDATE_LOGFILE%" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: State S1 expected ZERO FULLUPGRADE- lines in the log, found some.
  goto Fail
)
echo [PASS] State S1: no-target run emitted no full-FU line (silent no-op, exit !S1_EXIT!).

REM -----------------------------------------------------------------------
REM State S2: LTSB/LTSC skip
REM -----------------------------------------------------------------------
echo [Test 3/25] State S2: LTSB/LTSC edition detected - named skip...
set "OS_VER_MAJOR=10"
set "OS_VER_MINOR=0"
set "OS_VER_BUILD=26100"
set "OS_VER_BUILD_INTERNAL=26100"
set "OS_VER_REVIS=1000"
set "OS_LANG_EXT=en-us"
set "OS_EDITIONID=EnterpriseS"
set "WOU_FU_TEST_SCAN_RC="
set "WOU_FU_TEST_LAUNCH_RC="
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"

call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade /upgradeos:26200 >"%MOCK_TEMP%\s2_out.txt" 2>&1
set "S2_EXIT=!errorlevel!"

if "!S2_EXIT!" NEQ "0" (
  echo FAIL: State S2 expected exit code 0, got !S2_EXIT!.
  type "%MOCK_TEMP%\s2_out.txt"
  goto Fail
)
findstr /C:"Info: Skipping full upgrade as a LTSB-/LTSC-SKU has been detected" "%MOCK_TEMP%\s2_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S2 expected the LTSB/LTSC skip literal verbatim.
  type "%MOCK_TEMP%\s2_out.txt"
  goto Fail
)
findstr /C:"FULLUPGRADE-SKIP-LTSC" "%MOCK_TEMP%\s2_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S2 expected the FULLUPGRADE-SKIP-LTSC sentinel.
  type "%MOCK_TEMP%\s2_out.txt"
  goto Fail
)
findstr /C:"FULLUPGRADE-STAGED" "%MOCK_TEMP%\s2_out.txt" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: State S2 must not stage anything.
  type "%MOCK_TEMP%\s2_out.txt"
  goto Fail
)
echo [PASS] State S2: LTSC skip reported verbatim with sentinel (exit 0).

REM -----------------------------------------------------------------------
REM State S3: Convergence (observed build == target)
REM -----------------------------------------------------------------------
echo [Test 4/25] State S3: observed convergence - jump complete + purge...
set "OS_VER_MAJOR=10"
set "OS_VER_MINOR=0"
set "OS_VER_BUILD=26200"
set "OS_VER_BUILD_INTERNAL=26200"
set "OS_VER_REVIS=5074"
set "OS_LANG_EXT=en-us"
set "OS_EDITIONID=Professional"
set "WOU_FU_TEST_SCAN_RC="
set "WOU_FU_TEST_LAUNCH_RC="
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"
REM Seed stale markers: the convergence path purges the EKB family via the
REM skip purge AND the full-FU attempts record via the converged delete
type nul >"%MOCK_SYS_TEMP%\wou_buildupgrade_prep_tried.txt"
type nul >"%MOCK_SYS_TEMP%\wou_buildupgrade_tried.txt"
echo stale>"%MOCK_SYS_TEMP%\wou_buildupgrade_attempts.txt"
echo stale>"%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt"

call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade /upgradeos:26200 >"%MOCK_TEMP%\s3_out.txt" 2>&1
set "S3_EXIT=!errorlevel!"

if "!S3_EXIT!" NEQ "0" (
  echo FAIL: State S3 expected exit code 0, got !S3_EXIT!.
  type "%MOCK_TEMP%\s3_out.txt"
  goto Fail
)
findstr /C:"Info: Full upgrade target build 26200 already observed - jump complete" "%MOCK_TEMP%\s3_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S3 expected the full-FU convergence literal verbatim.
  type "%MOCK_TEMP%\s3_out.txt"
  goto Fail
)
findstr /C:"FULLUPGRADE-CONVERGED" "%MOCK_TEMP%\s3_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S3 expected the FULLUPGRADE-CONVERGED sentinel.
  type "%MOCK_TEMP%\s3_out.txt"
  goto Fail
)
findstr /C:"no full upgrade media staged for" "%MOCK_TEMP%\s3_out.txt" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: State S3 convergence must precede the media pre-flight.
  type "%MOCK_TEMP%\s3_out.txt"
  goto Fail
)
if exist "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" (
  echo FAIL: State S3 expected the stale full-FU attempts record purged by the convergence path.
  goto Fail
)
if exist "%MOCK_SYS_TEMP%\wou_buildupgrade_attempts.txt" (
  echo FAIL: State S3 expected the stale EKB attempts record purged.
  goto Fail
)
echo [PASS] State S3: convergence reported, full-FU attempts record purged, no media probe.

REM -----------------------------------------------------------------------
REM State S4: Media missing (target 26999 has no staged tree)
REM -----------------------------------------------------------------------
echo [Test 5/25] State S4: no media staged for the target - named refusal...
set "OS_VER_MAJOR=10"
set "OS_VER_MINOR=0"
set "OS_VER_BUILD=26100"
set "OS_VER_BUILD_INTERNAL=26100"
set "OS_VER_REVIS=1000"
set "OS_LANG_EXT=en-us"
set "OS_EDITIONID=Professional"
set "WOU_FU_TEST_SCAN_RC="
set "WOU_FU_TEST_LAUNCH_RC="
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"
REM Attempts-record lifecycle (DEC-34-06): seed the record here - every
REM refusal pass through S4-S8 must preserve it untouched
if exist "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" del "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" >nul 2>&1
echo 1,1000,26100,full>"%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt"

call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade /upgradeos:26999 >"%MOCK_TEMP%\s4_out.txt" 2>&1
set "S4_EXIT=!errorlevel!"

if "!S4_EXIT!" NEQ "0" (
  echo FAIL: State S4 expected exit code 0, got !S4_EXIT!.
  type "%MOCK_TEMP%\s4_out.txt"
  goto Fail
)
findstr /C:"Warning: Chosen upgrade target 26999 blocked: no full upgrade media staged for x64" "%MOCK_TEMP%\s4_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S4 expected the media-missing refusal literal verbatim.
  type "%MOCK_TEMP%\s4_out.txt"
  goto Fail
)
findstr /C:"FULLUPGRADE-MEDIA-MISSING" "%MOCK_TEMP%\s4_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S4 expected the FULLUPGRADE-MEDIA-MISSING sentinel.
  type "%MOCK_TEMP%\s4_out.txt"
  goto Fail
)
findstr /C:"1,1000,26100,full" "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S4 expected the pre-seeded attempts record to SURVIVE the refusal pass.
  goto Fail
)
echo [PASS] State S4: media-missing refusal fired verbatim, record survived (exit 0).

REM -----------------------------------------------------------------------
REM State S5: Media incomplete (sources\install.esd absent)
REM -----------------------------------------------------------------------
echo [Test 6/25] State S5: media incomplete - names the missing file...
set "OS_VER_MAJOR=10"
set "OS_VER_MINOR=0"
set "OS_VER_BUILD=26100"
set "OS_VER_BUILD_INTERNAL=26100"
set "OS_VER_REVIS=1000"
set "OS_LANG_EXT=en-us"
set "OS_EDITIONID=Professional"
set "WOU_FU_TEST_SCAN_RC="
set "WOU_FU_TEST_LAUNCH_RC="
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"
ren "%MOCK_MEDIA%\sources\install.esd" "fu_stash_esd.esd" >nul 2>&1

call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade /upgradeos:26200 >"%MOCK_TEMP%\s5_out.txt" 2>&1
set "S5_EXIT=!errorlevel!"
ren "%MOCK_MEDIA%\sources\fu_stash_esd.esd" "install.esd" >nul 2>&1

if "!S5_EXIT!" NEQ "0" (
  echo FAIL: State S5 expected exit code 0, got !S5_EXIT!.
  type "%MOCK_TEMP%\s5_out.txt"
  goto Fail
)
findstr /C:"Warning: Chosen upgrade target 26200 blocked: full upgrade media incomplete - sources\install.esd missing" "%MOCK_TEMP%\s5_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S5 expected the media-incomplete refusal naming sources\install.esd.
  type "%MOCK_TEMP%\s5_out.txt"
  goto Fail
)
findstr /C:"FULLUPGRADE-MEDIA-INCOMPLETE" "%MOCK_TEMP%\s5_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S5 expected the FULLUPGRADE-MEDIA-INCOMPLETE sentinel.
  type "%MOCK_TEMP%\s5_out.txt"
  goto Fail
)
if not exist "%MOCK_MEDIA%\sources\install.esd" (
  echo FAIL: State S5 restore failed - install.esd stub missing after the state.
  goto Fail
)
echo [PASS] State S5: media-incomplete refusal fired naming sources\install.esd (exit 0).

REM -----------------------------------------------------------------------
REM State S6: Media ambiguous (two language directories staged)
REM -----------------------------------------------------------------------
echo [Test 7/25] State S6: ambiguous multi-language media tree...
set "OS_VER_MAJOR=10"
set "OS_VER_MINOR=0"
set "OS_VER_BUILD=26100"
set "OS_VER_BUILD_INTERNAL=26100"
set "OS_VER_REVIS=1000"
set "OS_LANG_EXT=en-us"
set "OS_EDITIONID=Professional"
set "WOU_FU_TEST_SCAN_RC="
set "WOU_FU_TEST_LAUNCH_RC="
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"
mkdir "%MOCK_UPGRADE%\26200-x64\fr-fr" 2>nul
type nul >"%MOCK_UPGRADE%\26200-x64\fr-fr\setup.exe"

call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade /upgradeos:26200 >"%MOCK_TEMP%\s6_out.txt" 2>&1
set "S6_EXIT=!errorlevel!"
rmdir /s /q "%MOCK_UPGRADE%\26200-x64\fr-fr" 2>nul

if "!S6_EXIT!" NEQ "0" (
  echo FAIL: State S6 expected exit code 0, got !S6_EXIT!.
  type "%MOCK_TEMP%\s6_out.txt"
  goto Fail
)
findstr /C:"Warning: Chosen upgrade target 26200 blocked: multiple media language directories staged for x64" "%MOCK_TEMP%\s6_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S6 expected the media-ambiguous refusal literal verbatim.
  type "%MOCK_TEMP%\s6_out.txt"
  goto Fail
)
findstr /C:"FULLUPGRADE-MEDIA-AMBIGUOUS" "%MOCK_TEMP%\s6_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S6 expected the FULLUPGRADE-MEDIA-AMBIGUOUS sentinel.
  type "%MOCK_TEMP%\s6_out.txt"
  goto Fail
)
if exist "%MOCK_UPGRADE%\26200-x64\fr-fr" (
  echo FAIL: State S6 cleanup failed - the fr-fr variant tree still exists.
  goto Fail
)
echo [PASS] State S6: media-ambiguous refusal fired verbatim (exit 0).

REM -----------------------------------------------------------------------
REM State S7: Language mismatch (en-us media vs fr-fr system)
REM -----------------------------------------------------------------------
echo [Test 8/25] State S7: media language differs from system language...
set "OS_VER_MAJOR=10"
set "OS_VER_MINOR=0"
set "OS_VER_BUILD=26100"
set "OS_VER_BUILD_INTERNAL=26100"
set "OS_VER_REVIS=1000"
set "OS_LANG_EXT=fr-fr"
set "OS_EDITIONID=Professional"
set "WOU_FU_TEST_SCAN_RC="
set "WOU_FU_TEST_LAUNCH_RC="
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"

call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade /upgradeos:26200 >"%MOCK_TEMP%\s7_out.txt" 2>&1
set "S7_EXIT=!errorlevel!"

if "!S7_EXIT!" NEQ "0" (
  echo FAIL: State S7 expected exit code 0, got !S7_EXIT!.
  type "%MOCK_TEMP%\s7_out.txt"
  goto Fail
)
findstr /C:"Warning: Chosen upgrade target 26200 blocked: media language en-us differs from system language fr-fr" "%MOCK_TEMP%\s7_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S7 expected the language refusal naming BOTH tokens verbatim.
  type "%MOCK_TEMP%\s7_out.txt"
  goto Fail
)
findstr /C:"FULLUPGRADE-LANG-REFUSED" "%MOCK_TEMP%\s7_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S7 expected the FULLUPGRADE-LANG-REFUSED sentinel.
  type "%MOCK_TEMP%\s7_out.txt"
  goto Fail
)
findstr /C:"FULLUPGRADE-STAGED" "%UPDATE_LOGFILE%" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: State S7 found a FULLUPGRADE-STAGED sentinel - a language-refused pass must never reach a launch.
  goto Fail
)
set "OS_LANG_EXT=en-us"
echo [PASS] State S7: language refusal fired naming both tokens, nothing staged (exit 0).

REM -----------------------------------------------------------------------
REM State S8: Scan refusals via the mock-RC hook (hex forms)
REM -----------------------------------------------------------------------
echo [Test 9/25] State S8a: scan refusal 0xC1900200 - TPM/CPU eligibility...
set "OS_VER_MAJOR=10"
set "OS_VER_MINOR=0"
set "OS_VER_BUILD=26100"
set "OS_VER_BUILD_INTERNAL=26100"
set "OS_VER_REVIS=1000"
set "OS_LANG_EXT=en-us"
set "OS_EDITIONID=Professional"
set "WOU_FU_TEST_LAUNCH_RC="
set "WOU_FU_TEST_SCAN_RC=0xC1900200"
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"

call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade /upgradeos:26200 >"%MOCK_TEMP%\s8a_out.txt" 2>&1
set "S8A_EXIT=!errorlevel!"

if "!S8A_EXIT!" NEQ "0" (
  echo FAIL: State S8a expected exit code 0, got !S8A_EXIT!.
  type "%MOCK_TEMP%\s8a_out.txt"
  goto Fail
)
findstr /C:"Warning: Full upgrade refused: system requirements not met (TPM/CPU eligibility)" "%MOCK_TEMP%\s8a_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S8a expected the TPM/CPU refusal literal verbatim.
  type "%MOCK_TEMP%\s8a_out.txt"
  goto Fail
)
findstr /C:"FULLUPGRADE-REFUSED-SYSREQ" "%MOCK_TEMP%\s8a_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S8a expected the FULLUPGRADE-REFUSED-SYSREQ sentinel.
  type "%MOCK_TEMP%\s8a_out.txt"
  goto Fail
)
findstr /C:"FULLUPGRADE-STAGED" "%MOCK_TEMP%\s8a_out.txt" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: State S8a must never reach the launch site past a refused scan.
  type "%MOCK_TEMP%\s8a_out.txt"
  goto Fail
)
echo [PASS] State S8a: scan refusal 0xC1900200 decoded to the TPM/CPU cause (exit 0, no launch).

echo [Test 10/25] State S8b: scan refusal 0xC190020E - disk space...
set "WOU_FU_TEST_SCAN_RC=0xC190020E"
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"

call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade /upgradeos:26200 >"%MOCK_TEMP%\s8b_out.txt" 2>&1
set "S8B_EXIT=!errorlevel!"

if "!S8B_EXIT!" NEQ "0" (
  echo FAIL: State S8b expected exit code 0, got !S8B_EXIT!.
  type "%MOCK_TEMP%\s8b_out.txt"
  goto Fail
)
findstr /C:"Warning: Full upgrade refused: not enough free disk space" "%MOCK_TEMP%\s8b_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S8b expected the disk-space refusal literal verbatim.
  type "%MOCK_TEMP%\s8b_out.txt"
  goto Fail
)
findstr /C:"FULLUPGRADE-REFUSED-DISKSPACE" "%MOCK_TEMP%\s8b_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S8b expected the FULLUPGRADE-REFUSED-DISKSPACE sentinel.
  type "%MOCK_TEMP%\s8b_out.txt"
  goto Fail
)
REM The seeded record survived the whole refusal family (S4-S8) untouched
findstr /C:"1,1000,26100,full" "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S8b expected the pre-seeded attempts record to survive S4-S8.
  goto Fail
)
echo [PASS] State S8b: scan refusal 0xC190020E decoded to the disk-space cause, record survived (exit 0).

REM -----------------------------------------------------------------------
REM State S9: Staged termination (scan passes, launch reports 3010)
REM -----------------------------------------------------------------------
echo [Test 11/25] State S9: staged upgrade terminates the pass before the security pass...
set "OS_VER_MAJOR=10"
set "OS_VER_MINOR=0"
set "OS_VER_BUILD=26100"
set "OS_VER_BUILD_INTERNAL=26100"
set "OS_VER_REVIS=1000"
set "OS_LANG_EXT=en-us"
set "OS_EDITIONID=Professional"
set "WOU_FU_TEST_SCAN_RC=0xC1900210"
set "WOU_FU_TEST_LAUNCH_RC=3010"
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"

call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade /upgradeos:26200 >"%MOCK_TEMP%\s9_out.txt" 2>&1
set "S9_EXIT=!errorlevel!"

if "!S9_EXIT!" NEQ "3011" (
  echo FAIL: State S9 expected exit code 3011 [Updates pending], got !S9_EXIT!.
  type "%MOCK_TEMP%\s9_out.txt"
  goto Fail
)
findstr /C:"FULLUPGRADE-SCAN-PASS" "%MOCK_TEMP%\s9_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S9 expected the FULLUPGRADE-SCAN-PASS sentinel.
  type "%MOCK_TEMP%\s9_out.txt"
  goto Fail
)
findstr /C:"FULLUPGRADE-STAGED" "%MOCK_TEMP%\s9_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S9 expected the FULLUPGRADE-STAGED sentinel.
  type "%MOCK_TEMP%\s9_out.txt"
  goto Fail
)
findstr /C:"Info: Installation successful (Updates pending)" "%UPDATE_LOGFILE%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S9 expected the Updates-pending log line from the Installed ladder.
  goto Fail
)
findstr /C:"Checking Windows Update Agent version" "%MOCK_TEMP%\s9_out.txt" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: State S9 staged pass reached the security pass - the WUA check must never run after a launch.
  type "%MOCK_TEMP%\s9_out.txt"
  goto Fail
)
REM Write-before-launch lifecycle: the seeded count-1 record was read, incremented
REM in memory, and REWRITTEN before the launch - and it survived the Installed
REM ladder (the staged exit never deletes it)
findstr /C:"2,1000,26100,full" "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S9 expected the attempts record incremented to 2,1000,26100,full by the write-before-launch.
  goto Fail
)
echo [PASS] State S9: staged termination proven, record incremented to 2 by the write-before-launch (exit 3011).

REM -----------------------------------------------------------------------
REM State S10: Suspect - exit 0 without an observed build change
REM -----------------------------------------------------------------------
echo [Test 12/25] State S10: launch exit 0 without build change is the suspect row...
REM The attempts guard counts across runs (DEC-34-06): each battery state
REM simulates an independent machine - reset the record between launch states.
if exist "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" del "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" >nul 2>&1
set "OS_VER_MAJOR=10"
set "OS_VER_MINOR=0"
set "OS_VER_BUILD=26100"
set "OS_VER_BUILD_INTERNAL=26100"
set "OS_VER_REVIS=1000"
set "OS_LANG_EXT=en-us"
set "OS_EDITIONID=Professional"
set "WOU_FU_TEST_SCAN_RC=0xC1900210"
set "WOU_FU_TEST_LAUNCH_RC=0"
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"

call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade /upgradeos:26200 >"%MOCK_TEMP%\s10_out.txt" 2>&1
set "S10_EXIT=!errorlevel!"

if "!S10_EXIT!" NEQ "3011" (
  echo FAIL: State S10 expected exit code 3011, got !S10_EXIT!.
  type "%MOCK_TEMP%\s10_out.txt"
  goto Fail
)
findstr /C:"Warning: Full upgrade exited 0 without an observed build change - never reported as success; verify Panther logs" "%MOCK_TEMP%\s10_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S10 expected the suspect row with the never-reported-as-success wording.
  type "%MOCK_TEMP%\s10_out.txt"
  goto Fail
)
findstr /C:"FULLUPGRADE-SUSPECT" "%MOCK_TEMP%\s10_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S10 expected the FULLUPGRADE-SUSPECT sentinel.
  type "%MOCK_TEMP%\s10_out.txt"
  goto Fail
)
findstr /C:"FULLUPGRADE-STAGED" "%MOCK_TEMP%\s10_out.txt" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: State S10 exit 0 must not map to the staged outcome.
  type "%MOCK_TEMP%\s10_out.txt"
  goto Fail
)
echo [PASS] State S10: suspect row fired with the never-success wording (exit 3011).

REM -----------------------------------------------------------------------
REM State S11: Rollback (0xC1900101)
REM -----------------------------------------------------------------------
echo [Test 13/25] State S11: launch exit 0xC1900101 - rollback row...
REM Independent-machine reset (see State S10 note)
if exist "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" del "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" >nul 2>&1
set "OS_VER_MAJOR=10"
set "OS_VER_MINOR=0"
set "OS_VER_BUILD=26100"
set "OS_VER_BUILD_INTERNAL=26100"
set "OS_VER_REVIS=1000"
set "OS_LANG_EXT=en-us"
set "OS_EDITIONID=Professional"
set "WOU_FU_TEST_SCAN_RC=0xC1900210"
set "WOU_FU_TEST_LAUNCH_RC=0xC1900101"
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"

call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade /upgradeos:26200 >"%MOCK_TEMP%\s11_out.txt" 2>&1
set "S11_EXIT=!errorlevel!"

if "!S11_EXIT!" NEQ "0" (
  echo FAIL: State S11 expected exit code 0, got !S11_EXIT!.
  type "%MOCK_TEMP%\s11_out.txt"
  goto Fail
)
findstr /C:"Warning: Full upgrade rolled back (driver compatibility in most cases) - rollback logs under $Windows.~BT\Sources\Rollback" "%MOCK_TEMP%\s11_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S11 expected the rollback literal verbatim.
  type "%MOCK_TEMP%\s11_out.txt"
  goto Fail
)
findstr /C:"FULLUPGRADE-ROLLBACK" "%MOCK_TEMP%\s11_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S11 expected the FULLUPGRADE-ROLLBACK sentinel.
  type "%MOCK_TEMP%\s11_out.txt"
  goto Fail
)
echo [PASS] State S11: rollback row fired verbatim (exit 0).

REM -----------------------------------------------------------------------
REM State S12: Undecoded code (0xC1900199 -> catch-all row)
REM -----------------------------------------------------------------------
echo [Test 14/25] State S12 and S13: undecoded code + signed-decimal normalization...
REM Independent-machine reset (see State S10 note) - S13 reuses the state below
if exist "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" del "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" >nul 2>&1
set "OS_VER_MAJOR=10"
set "OS_VER_MINOR=0"
set "OS_VER_BUILD=26100"
set "OS_VER_BUILD_INTERNAL=26100"
set "OS_VER_REVIS=1000"
set "OS_LANG_EXT=en-us"
set "OS_EDITIONID=Professional"
set "WOU_FU_TEST_SCAN_RC=0xC1900210"
set "WOU_FU_TEST_LAUNCH_RC=0xC1900199"
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"

call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade /upgradeos:26200 >"%MOCK_TEMP%\s12_out.txt" 2>&1
set "S12_EXIT=!errorlevel!"

if "!S12_EXIT!" NEQ "0" (
  echo FAIL: State S12 expected exit code 0, got !S12_EXIT!.
  type "%MOCK_TEMP%\s12_out.txt"
  goto Fail
)
findstr /C:"Warning: Full upgrade failed with undecoded exit code 0xC1900199" "%MOCK_TEMP%\s12_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S12 expected the catch-all row naming the code.
  type "%MOCK_TEMP%\s12_out.txt"
  goto Fail
)
findstr /C:"FULLUPGRADE-FAIL" "%MOCK_TEMP%\s12_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S12 expected the FULLUPGRADE-FAIL sentinel.
  type "%MOCK_TEMP%\s12_out.txt"
  goto Fail
)
echo [PASS] State S12: undecoded code named by the catch-all row (exit 0).

REM -----------------------------------------------------------------------
REM State S13: Signed-decimal normalization (twin of state S8a)
REM -----------------------------------------------------------------------
echo     State S13: SCAN_RC=-1047526912 must decode to the same TPM/CPU refusal...
set "OS_VER_MAJOR=10"
set "OS_VER_MINOR=0"
set "OS_VER_BUILD=26100"
set "OS_VER_BUILD_INTERNAL=26100"
set "OS_VER_REVIS=1000"
set "OS_LANG_EXT=en-us"
set "OS_EDITIONID=Professional"
set "WOU_FU_TEST_LAUNCH_RC="
set "WOU_FU_TEST_SCAN_RC=-1047526912"
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"

call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade /upgradeos:26200 >"%MOCK_TEMP%\s13_out.txt" 2>&1
set "S13_EXIT=!errorlevel!"

if "!S13_EXIT!" NEQ "0" (
  echo FAIL: State S13 expected exit code 0, got !S13_EXIT!.
  type "%MOCK_TEMP%\s13_out.txt"
  goto Fail
)
findstr /C:"Warning: Full upgrade refused: system requirements not met (TPM/CPU eligibility)" "%MOCK_TEMP%\s13_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S13 expected the SAME TPM/CPU refusal as state S8a via the decimal twin.
  type "%MOCK_TEMP%\s13_out.txt"
  goto Fail
)
findstr /C:"FULLUPGRADE-REFUSED-SYSREQ" "%MOCK_TEMP%\s13_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S13 expected the FULLUPGRADE-REFUSED-SYSREQ sentinel.
  type "%MOCK_TEMP%\s13_out.txt"
  goto Fail
)
echo [PASS] State S13: signed-decimal -1047526912 normalized to the 0xC1900200 row (exit 0).

REM -----------------------------------------------------------------------
REM State S14: Attempts stall (three stagnant launches at build 26100)
REM -----------------------------------------------------------------------
echo [Test 15/25] State S14: attempts stall - the third stagnant attempt halts...
set "OS_VER_MAJOR=10"
set "OS_VER_MINOR=0"
set "OS_VER_BUILD=26100"
set "OS_VER_BUILD_INTERNAL=26100"
set "OS_VER_REVIS=1000"
set "OS_LANG_EXT=en-us"
set "OS_EDITIONID=Professional"
set "WOU_FU_TEST_SCAN_RC=0xC1900210"
set "WOU_FU_TEST_LAUNCH_RC=3010"
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"
if exist "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" del "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" >nul 2>&1
echo 1,1000,26100,full>"%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt"
REM Run 1: seeded count 1 at the same build - the write-before-launch leaves count 2
call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade /upgradeos:26200 >"%MOCK_TEMP%\s14a_out.txt" 2>&1
set "S14A_EXIT=!errorlevel!"
if "!S14A_EXIT!" NEQ "3011" (
  echo FAIL: State S14 run 1 expected exit code 3011 ^(stall not yet reached^), got !S14A_EXIT!.
  type "%MOCK_TEMP%\s14a_out.txt"
  goto Fail
)
findstr /C:"2,1000,26100,full" "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S14 run 1 expected the record advanced to 2,1000,26100,full.
  goto Fail
)
REM Run 2: reads count 2 at the same build, computes 3, GTR 2 - the halt
call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade /upgradeos:26200 >"%MOCK_TEMP%\s14b_out.txt" 2>&1
set "S14B_EXIT=!errorlevel!"
if "!S14B_EXIT!" NEQ "0" (
  echo FAIL: State S14 run 2 expected exit code 0 [halted loop], got !S14B_EXIT!.
  type "%MOCK_TEMP%\s14b_out.txt"
  goto Fail
)
findstr /C:"Warning: Full upgrade did not advance the OS build (still 26100) - halting to prevent infinite reboot loop" "%MOCK_TEMP%\s14b_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S14 run 2 expected the full-FU stall literal verbatim.
  type "%MOCK_TEMP%\s14b_out.txt"
  goto Fail
)
findstr /C:"FULLUPGRADE-STALL-HALT" "%MOCK_TEMP%\s14b_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S14 run 2 expected the FULLUPGRADE-STALL-HALT sentinel.
  type "%MOCK_TEMP%\s14b_out.txt"
  goto Fail
)
findstr /C:"FULLUPGRADE-STAGED" "%MOCK_TEMP%\s14b_out.txt" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: State S14 run 2 must never reach the launch site past the stall halt.
  type "%MOCK_TEMP%\s14b_out.txt"
  goto Fail
)
if exist "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" (
  echo FAIL: State S14 run 2 expected the record DELETED by the halt ^(the consumed window^).
  goto Fail
)
echo [PASS] State S14: third stagnant attempt halted verbatim, record deleted, no launch (exit 0).

REM -----------------------------------------------------------------------
REM State S15: Advancement clear + convergence-first purge
REM -----------------------------------------------------------------------
echo [Test 16/25] State S15: advancement clears the guard; convergence purges first...
set "OS_VER_BUILD=26200"
set "OS_VER_BUILD_INTERNAL=26200"
set "OS_VER_REVIS=5074"
set "OS_LANG_EXT=en-us"
set "OS_EDITIONID=Professional"
set "WOU_FU_TEST_SCAN_RC=0xC1900210"
set "WOU_FU_TEST_LAUNCH_RC=3010"
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"
if exist "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" del "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" >nul 2>&1
echo 1,1000,26100,full>"%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt"
mkdir "%MOCK_UPGRADE%\26999-x64\en-us\sources" 2>nul
type nul >"%MOCK_UPGRADE%\26999-x64\en-us\setup.exe"
type nul >"%MOCK_UPGRADE%\26999-x64\en-us\sources\install.esd"
REM (a) record at build 26100, run at 26200 with target 26999: the guard clears
REM (in-memory), the record is rewritten fresh, the launch proceeds
call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade /upgradeos:26999 >"%MOCK_TEMP%\s15a_out.txt" 2>&1
set "S15A_EXIT=!errorlevel!"
if "!S15A_EXIT!" NEQ "3011" (
  echo FAIL: State S15a expected exit code 3011 ^(advancement must proceed^), got !S15A_EXIT!.
  type "%MOCK_TEMP%\s15a_out.txt"
  goto Fail
)
findstr /C:"FULLUPGRADE-STAGED" "%MOCK_TEMP%\s15a_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S15a expected the launch to proceed after the advancement clear.
  type "%MOCK_TEMP%\s15a_out.txt"
  goto Fail
)
findstr /C:"1,5074,26200,full" "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S15a expected the record rewritten fresh at the new build ^(count 1^).
  goto Fail
)
findstr /C:"Warning: Chosen upgrade target 26999 has no upgrade path from build 26200" "%MOCK_TEMP%\s15a_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S15a expected the EKB lane to refuse the unmatchable target first.
  type "%MOCK_TEMP%\s15a_out.txt"
  goto Fail
)
rmdir /s /q "%MOCK_UPGRADE%\26999-x64" 2>nul
REM (b) convergence fires FIRST: a pre-existing record is purged by the converged
REM delete lines, before any launch consideration
set "WOU_FU_TEST_SCAN_RC="
set "WOU_FU_TEST_LAUNCH_RC="
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"
if exist "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" del "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" >nul 2>&1
echo 1,1000,26100,full>"%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt"
call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade /upgradeos:26200 >"%MOCK_TEMP%\s15b_out.txt" 2>&1
set "S15B_EXIT=!errorlevel!"
if "!S15B_EXIT!" NEQ "0" (
  echo FAIL: State S15b expected exit code 0, got !S15B_EXIT!.
  type "%MOCK_TEMP%\s15b_out.txt"
  goto Fail
)
findstr /C:"Info: Full upgrade target build 26200 already observed - jump complete" "%MOCK_TEMP%\s15b_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S15b expected the convergence literal to fire FIRST.
  type "%MOCK_TEMP%\s15b_out.txt"
  goto Fail
)
if exist "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" (
  echo FAIL: State S15b expected the pre-existing record purged by the converged delete lines.
  goto Fail
)
findstr /C:"FULLUPGRADE-STAGED" "%MOCK_TEMP%\s15b_out.txt" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: State S15b must not launch - convergence precedes any launch consideration.
  type "%MOCK_TEMP%\s15b_out.txt"
  goto Fail
)
echo [PASS] State S15: advancement cleared and relaunched fresh; convergence purged before any launch.

REM -----------------------------------------------------------------------
REM State S16: Audit inert (mirror of the 34-01 audit case, instrument kept
REM independent inside this battery)
REM -----------------------------------------------------------------------
echo [Test 17/25] State S16: audit mode with a chosen target never reaches the lane...
REM Fresh log: the zero-FULLUPGRADE- assert must ride THIS run only
if exist "%UPDATE_LOGFILE%" del "%UPDATE_LOGFILE%" >nul 2>&1
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"
if exist "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" del "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" >nul 2>&1
echo 1,1000,26100,full>"%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt"
REM The drive form mirrors tests\verify-offline-audit.cmd Scenario 6: the
REM non-privileged :WriteMissingUpdatesReport entry with both arguments beside
REM it; the structural 445-gate bypass is pinned there + by the seam census.
REM A nested engine copy (client\cmd) keeps the report's ..\..\log target
REM INSIDE the sandbox.
mkdir "%SANDBOX_ROOT%\client\cmd" 2>nul
mkdir "%SANDBOX_ROOT%\log" 2>nul
copy /y "%REPO_ROOT%\client\cmd\DoUpdate.cmd" "%SANDBOX_ROOT%\client\cmd\DoUpdate.cmd" >nul 2>&1
set "AUDIT_ONLY=1"
set "WOU_UPGRADE_TARGET=26200"
pushd "%SANDBOX_ROOT%\client\cmd"
call .\DoUpdate.cmd :WriteMissingUpdatesReport /auditonly /upgradeos:26200 > "%SANDBOX_ROOT%\log\s16_audit_stdout.log" 2>&1
popd
set "S16_EXIT=!errorlevel!"
set "AUDIT_ONLY="
set "WOU_UPGRADE_TARGET="
if "!S16_EXIT!" NEQ "0" (
  echo FAIL: State S16 expected exit code 0, got !S16_EXIT!.
  type "%SANDBOX_ROOT%\log\s16_audit_stdout.log"
  goto Fail
)
if not exist "%SANDBOX_ROOT%\log\MissingUpdates.txt" (
  echo FAIL: State S16 expected the audit report to be created by the drive.
  type "%SANDBOX_ROOT%\log\s16_audit_stdout.log"
  goto Fail
)
findstr /C:"FULLUPGRADE-" "%UPDATE_LOGFILE%" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: State S16 a FULLUPGRADE- line was emitted in audit mode - the audit gate no longer bypasses the seam.
  type "%UPDATE_LOGFILE%"
  goto Fail
)
findstr /C:"1,1000,26100,full" "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S16 expected the attempts record untouched by the audit drive.
  goto Fail
)
echo [PASS] State S16: audit drive emitted zero full-FU lines, report created, record untouched (exit 0).

REM -----------------------------------------------------------------------
REM State S17: EKB fall-through (DEC-34-05) - both lanes in ONE run
REM -----------------------------------------------------------------------
echo [Test 18/25] State S17: EKB refusal falls through to the full-FU media probe...
set "OS_VER_BUILD=26100"
set "OS_VER_BUILD_INTERNAL=26100"
set "OS_VER_REVIS=1000"
set "OS_LANG_EXT=en-us"
set "OS_EDITIONID=Professional"
set "WOU_FU_TEST_SCAN_RC=0xC1900210"
set "WOU_FU_TEST_LAUNCH_RC=3010"
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"
if exist "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" del "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" >nul 2>&1
REM The EKB payloads stay stashed (fu_stash_*) - the chosen-row EKB probe fails
REM and the EKB lane refuses with its own frozen literal; the flow then falls
REM through into :FullUpgrade, which stages the SAME target via the media
call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade /upgradeos:26200 >"%MOCK_TEMP%\s17_out.txt" 2>&1
set "S17_EXIT=!errorlevel!"
if "!S17_EXIT!" NEQ "3011" (
  echo FAIL: State S17 expected exit code 3011 ^(the full-FU lane staged the target^), got !S17_EXIT!.
  type "%MOCK_TEMP%\s17_out.txt"
  goto Fail
)
findstr /C:"Warning: Chosen upgrade target 26200 blocked: enablement package kb5054156 missing from medium" "%MOCK_TEMP%\s17_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S17 expected the EKB lane's own missing-enablement refusal literal verbatim.
  type "%MOCK_TEMP%\s17_out.txt"
  goto Fail
)
findstr /C:"FULLUPGRADE-SCAN-PASS" "%MOCK_TEMP%\s17_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S17 expected the full-FU lane to run the media probe ^(SCAN-PASS missing^).
  type "%MOCK_TEMP%\s17_out.txt"
  goto Fail
)
findstr /C:"FULLUPGRADE-STAGED" "%MOCK_TEMP%\s17_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S17 expected the full-FU lane to stage the same target ^(STAGED missing^).
  type "%MOCK_TEMP%\s17_out.txt"
  goto Fail
)
echo [PASS] State S17: EKB enablement refusal AND full-FU SCAN-PASS + STAGED in one run (fall-through proven).

REM -----------------------------------------------------------------------
REM State S18: Marker pose (RECALL-01) - the staged pass writes the upgrade-
REM in-progress marker beside the attempts record, before the launch split
REM -----------------------------------------------------------------------
echo [Test 19/25] State S18: staged pass poses the upgrade-in-progress marker...
REM Independent-machine reset (see State S10 note)
if exist "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" del "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" >nul 2>&1
if exist "%MOCK_SYS_TEMP%\wou_upgrade_in_progress.txt" del "%MOCK_SYS_TEMP%\wou_upgrade_in_progress.txt" >nul 2>&1
set "OS_VER_MAJOR=10"
set "OS_VER_MINOR=0"
set "OS_VER_BUILD=26100"
set "OS_VER_BUILD_INTERNAL=26100"
set "OS_VER_REVIS=1000"
set "OS_LANG_EXT=en-us"
set "OS_EDITIONID=Professional"
set "WOU_FU_TEST_SCAN_RC=0xC1900210"
set "WOU_FU_TEST_LAUNCH_RC=3010"
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"

call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade /upgradeos:26200 >"%MOCK_TEMP%\s18_out.txt" 2>&1
set "S18_EXIT=!errorlevel!"

if "!S18_EXIT!" NEQ "3011" (
  echo FAIL: State S18 expected exit code 3011 ^(staged pass^), got !S18_EXIT!.
  type "%MOCK_TEMP%\s18_out.txt"
  goto Fail
)
findstr /C:"FULLUPGRADE-MARKER-POSED" "%MOCK_TEMP%\s18_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S18 expected the FULLUPGRADE-MARKER-POSED sentinel.
  type "%MOCK_TEMP%\s18_out.txt"
  goto Fail
)
if not exist "%MOCK_SYS_TEMP%\wou_upgrade_in_progress.txt" (
  echo FAIL: State S18 expected the marker file in the mock engine temp dir.
  goto Fail
)
findstr /B /C:"full,26200," "%MOCK_SYS_TEMP%\wou_upgrade_in_progress.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S18 expected marker line 1 to begin with the target ^(full,26200,...^).
  type "%MOCK_SYS_TEMP%\wou_upgrade_in_progress.txt"
  goto Fail
)
findstr /C:"1,1000,26100,full" "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S18 expected the attempts record to coexist with the marker.
  goto Fail
)
echo [PASS] State S18: marker posed beside the launch record, target build on line 1 (exit 3011).

REM -----------------------------------------------------------------------
REM State S19: Converged clear (RECALL-02 pivot) - the convergence branch
REM deletes BOTH the marker and the attempts record before any media probe
REM -----------------------------------------------------------------------
echo [Test 20/25] State S19: convergence clears the marker and the attempts record...
REM Seed both state files (the S14 seeding technique) with bytes a pose would
REM never write, so the delete is observable as a delete of THE SEED.
if exist "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" del "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" >nul 2>&1
if exist "%MOCK_SYS_TEMP%\wou_upgrade_in_progress.txt" del "%MOCK_SYS_TEMP%\wou_upgrade_in_progress.txt" >nul 2>&1
echo 1,1000,26100,full>"%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt"
echo full,26200,9999>"%MOCK_SYS_TEMP%\wou_upgrade_in_progress.txt"
set "OS_VER_MAJOR=10"
set "OS_VER_MINOR=0"
set "OS_VER_BUILD=26200"
set "OS_VER_BUILD_INTERNAL=26200"
set "OS_VER_REVIS=5074"
set "OS_LANG_EXT=en-us"
set "OS_EDITIONID=Professional"
set "WOU_FU_TEST_SCAN_RC="
set "WOU_FU_TEST_LAUNCH_RC="
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"

call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade /upgradeos:26200 >"%MOCK_TEMP%\s19_out.txt" 2>&1
set "S19_EXIT=!errorlevel!"

if "!S19_EXIT!" NEQ "0" (
  echo FAIL: State S19 expected exit code 0, got !S19_EXIT!.
  type "%MOCK_TEMP%\s19_out.txt"
  goto Fail
)
findstr /C:"Info: Full upgrade target build 26200 already observed - jump complete" "%MOCK_TEMP%\s19_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S19 expected the convergence literal verbatim.
  type "%MOCK_TEMP%\s19_out.txt"
  goto Fail
)
findstr /C:"FULLUPGRADE-CONVERGED" "%MOCK_TEMP%\s19_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S19 expected the FULLUPGRADE-CONVERGED sentinel.
  type "%MOCK_TEMP%\s19_out.txt"
  goto Fail
)
findstr /C:"no full upgrade media staged for" "%MOCK_TEMP%\s19_out.txt" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: State S19 convergence must precede the media probe.
  type "%MOCK_TEMP%\s19_out.txt"
  goto Fail
)
if exist "%MOCK_SYS_TEMP%\wou_upgrade_in_progress.txt" (
  echo FAIL: State S19 expected the seeded marker DELETED by the converged clear.
  goto Fail
)
if exist "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" (
  echo FAIL: State S19 expected the seeded attempts record DELETED by the convergence branch.
  goto Fail
)
echo [PASS] State S19: convergence cleared BOTH state files before any media probe (exit 0).

REM -----------------------------------------------------------------------
REM State S20: Stall restore (RECALL-02 tail) - the halt clears the marker,
REM emits RECALL-RESTORED, and the armed-state gate stays SHUT in the
REM w100-shaped sandbox (no restore Info line, no CleanupRecall call)
REM -----------------------------------------------------------------------
echo [Test 21/25] State S20: stall halt restores safe state behind the closed gate...
REM Seed the marker AND the attempts record at the current build (count 1)
if exist "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" del "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" >nul 2>&1
if exist "%MOCK_SYS_TEMP%\wou_upgrade_in_progress.txt" del "%MOCK_SYS_TEMP%\wou_upgrade_in_progress.txt" >nul 2>&1
echo 1,1000,26100,full>"%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt"
echo full,26200,1000>"%MOCK_SYS_TEMP%\wou_upgrade_in_progress.txt"
set "OS_VER_MAJOR=10"
set "OS_VER_MINOR=0"
set "OS_VER_BUILD=26100"
set "OS_VER_BUILD_INTERNAL=26100"
set "OS_VER_REVIS=1000"
set "OS_LANG_EXT=en-us"
set "OS_EDITIONID=Professional"
set "WOU_FU_TEST_SCAN_RC=0xC1900210"
set "WOU_FU_TEST_LAUNCH_RC=3010"
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"

REM Run 1: the guard advances to count 2 and the pose overwrites the seed
call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade /upgradeos:26200 >"%MOCK_TEMP%\s20a_out.txt" 2>&1
set "S20A_EXIT=!errorlevel!"
if "!S20A_EXIT!" NEQ "3011" (
  echo FAIL: State S20 run 1 expected exit code 3011 ^(halt not yet reached^), got !S20A_EXIT!.
  type "%MOCK_TEMP%\s20a_out.txt"
  goto Fail
)
REM Run 2: reads count 2 at the same build, computes 3, GTR 2 - the halt
call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade /upgradeos:26200 >"%MOCK_TEMP%\s20b_out.txt" 2>&1
set "S20B_EXIT=!errorlevel!"
if "!S20B_EXIT!" NEQ "0" (
  echo FAIL: State S20 run 2 expected exit code 0 [halted], got !S20B_EXIT!.
  type "%MOCK_TEMP%\s20b_out.txt"
  goto Fail
)
findstr /C:"FULLUPGRADE-STALL-HALT" "%MOCK_TEMP%\s20b_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S20 run 2 expected the FULLUPGRADE-STALL-HALT sentinel.
  type "%MOCK_TEMP%\s20b_out.txt"
  goto Fail
)
findstr /C:"RECALL-RESTORED" "%MOCK_TEMP%\s20b_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S20 run 2 expected the RECALL-RESTORED sentinel.
  type "%MOCK_TEMP%\s20b_out.txt"
  goto Fail
)
findstr /C:"restoring safe state after failed upgrade" "%MOCK_TEMP%\s20b_out.txt" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: State S20 run 2 expected the armed-state gate SHUT ^(no restore Info line in the w100-shaped sandbox^).
  type "%MOCK_TEMP%\s20b_out.txt"
  goto Fail
)
findstr /C:"FULLUPGRADE-STAGED" "%MOCK_TEMP%\s20b_out.txt" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: State S20 run 2 must never reach the launch site past the halt.
  type "%MOCK_TEMP%\s20b_out.txt"
  goto Fail
)
if exist "%MOCK_SYS_TEMP%\wou_upgrade_in_progress.txt" (
  echo FAIL: State S20 run 2 expected the marker cleared by the halt.
  goto Fail
)
if exist "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" (
  echo FAIL: State S20 run 2 expected the attempts record deleted by the halt.
  goto Fail
)
echo [PASS] State S20: halt cleared both files, RECALL-RESTORED emitted, gate stayed shut (exit 0).

REM -----------------------------------------------------------------------
REM State S21: Refusal survival (DEC-35-09) - refusal passes never pose and
REM never clear; a seeded marker survives byte-identically
REM -----------------------------------------------------------------------
echo [Test 22/25] State S21: refusals never pose; a seeded marker survives...
REM (a) never-pose: fresh machine, media-missing refusal shape (target 26999)
if exist "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" del "%MOCK_SYS_TEMP%\wou_fullupgrade_attempts.txt" >nul 2>&1
if exist "%MOCK_SYS_TEMP%\wou_upgrade_in_progress.txt" del "%MOCK_SYS_TEMP%\wou_upgrade_in_progress.txt" >nul 2>&1
set "OS_VER_MAJOR=10"
set "OS_VER_MINOR=0"
set "OS_VER_BUILD=26100"
set "OS_VER_BUILD_INTERNAL=26100"
set "OS_VER_REVIS=1000"
set "OS_LANG_EXT=en-us"
set "OS_EDITIONID=Professional"
set "WOU_FU_TEST_SCAN_RC="
set "WOU_FU_TEST_LAUNCH_RC="
if exist "%MOCK_TEMP%\MissingUpdateIds.txt" del "%MOCK_TEMP%\MissingUpdateIds.txt"
call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade /upgradeos:26999 >"%MOCK_TEMP%\s21a_out.txt" 2>&1
set "S21A_EXIT=!errorlevel!"
if "!S21A_EXIT!" NEQ "0" (
  echo FAIL: State S21a expected exit code 0, got !S21A_EXIT!.
  type "%MOCK_TEMP%\s21a_out.txt"
  goto Fail
)
findstr /C:"FULLUPGRADE-MEDIA-MISSING" "%MOCK_TEMP%\s21a_out.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S21a expected the media-missing refusal sentinel.
  type "%MOCK_TEMP%\s21a_out.txt"
  goto Fail
)
findstr /C:"FULLUPGRADE-MARKER-POSED" "%MOCK_TEMP%\s21a_out.txt" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: State S21a a refusal pass emitted FULLUPGRADE-MARKER-POSED - the pose must only fire beside the launch.
  type "%MOCK_TEMP%\s21a_out.txt"
  goto Fail
)
if exist "%MOCK_SYS_TEMP%\wou_upgrade_in_progress.txt" (
  echo FAIL: State S21a expected NO marker after a refusal pass.
  goto Fail
)
REM (b) survival: seed the marker, run the SAME refusal shape
echo full,26999,424242>"%MOCK_SYS_TEMP%\wou_upgrade_in_progress.txt"
call "%MOCK_CMD%\DoUpdate.cmd" /testbuildupgrade /upgradeos:26999 >"%MOCK_TEMP%\s21b_out.txt" 2>&1
set "S21B_EXIT=!errorlevel!"
if "!S21B_EXIT!" NEQ "0" (
  echo FAIL: State S21b expected exit code 0, got !S21B_EXIT!.
  type "%MOCK_TEMP%\s21b_out.txt"
  goto Fail
)
findstr /C:"FULLUPGRADE-MARKER-POSED" "%MOCK_TEMP%\s21b_out.txt" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: State S21b the seeded-machine refusal must still never pose.
  type "%MOCK_TEMP%\s21b_out.txt"
  goto Fail
)
findstr /B /C:"full,26999,424242" "%MOCK_SYS_TEMP%\wou_upgrade_in_progress.txt" >nul 2>&1
if errorlevel 1 (
  echo FAIL: State S21b expected the seeded marker to survive byte-identically.
  type "%MOCK_SYS_TEMP%\wou_upgrade_in_progress.txt"
  goto Fail
)
if exist "%MOCK_SYS_TEMP%\wou_upgrade_in_progress.txt" del "%MOCK_SYS_TEMP%\wou_upgrade_in_progress.txt" >nul 2>&1
echo [PASS] State S21: refusal passes never pose; the seeded marker survived byte-identically.

REM -----------------------------------------------------------------------
REM Stub stay-out section (Phase 35, RECALL-01; DEC-35-08/10): the REAL
REM RecallStub.cmd drives both cases from sandbox copies behind the one-line
REM shutdown mock. Marker present = stay-out (no relaunch canary, no cleanup
REM canary); marker absent = the relaunch canary fires (the negative control).
REM -----------------------------------------------------------------------
echo [Test 23/25] Stub section a: standing marker keeps the real recall stub out...
REM Per-case pre-flight: the real probe path must be clean before seeding
if exist "%SystemRoot%\Temp\wou_upgrade_in_progress.txt" (
  echo FAIL: stub pre-flight - a real upgrade-in-progress marker already exists at %SystemRoot%\Temp ^(never auto-deleted; remove it and re-run^).
  goto Fail
)
mkdir "%SANDBOX_ROOT%\stub" 2>nul
call :MakeSandboxStub "%REPO_ROOT%\client\cmd\RecallStub.cmd" "%SANDBOX_ROOT%\stub\RecallStub.cmd"
if not exist "%SANDBOX_ROOT%\stub\RecallStub.cmd" (
  echo FAIL: stub section - the sandbox stub copy was not created.
  goto Fail
)
REM sandbox integrity: the transform replaced the shutdown line one-for-one
set "STUBC_MOCK="
for /f %%a in ('findstr /C:"SANDBOX-SHUTDOWN-MOCKED" "%SANDBOX_ROOT%\stub\RecallStub.cmd" ^| "%SystemRoot%\System32\find.exe" /c /v ""') do set "STUBC_MOCK=%%a"
if not "!STUBC_MOCK!"=="1" (
  echo FAIL: stub section - sandbox stub expected the shutdown mock exactly once, got !STUBC_MOCK!.
  goto Fail
)
findstr /C:"shutdown.exe /r /f /t 1" "%SANDBOX_ROOT%\stub\RecallStub.cmd" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: stub section - the sandbox stub still carries the real shutdown motif.
  goto Fail
)
REM canary carriage + canary cleanup (never the real CleanupRecall.cmd)
(
  echo @echo off
  echo echo relaunched^>relaunch.canary
  echo exit /b 0
)>"%SANDBOX_ROOT%\stub\RecallUpdate.cmd"
(
  echo @echo off
  echo echo cleaned^>cleanup.canary
  echo exit /b 0
)>"%SANDBOX_ROOT%\stub\CleanupRecall.cmd"
set "STUB_SAVED_LOG=%UPDATE_LOGFILE%"
set "STUB_SAVED_PATH=%PATH%"
set "STUB_SAVED_SYSROOT=%SystemRoot%"
REM Host sandbox provision (35-01 deviation): the sandboxed shell can WRITE
REM C:\Windows\Temp but its cmd instruments cannot SEE files there, so the
REM DEC-35-08 real-path seeding is unreachable in this environment. The stub
REM process's SystemRoot is pointed at a sandbox sysroot instead: the probe
REM shape %SystemRoot%\Temp\wou_upgrade_in_progress.txt is untouched and the
REM seed lives exactly where the real caller resolves it. The real-path
REM proof across a real upgrade stays the Phase 37 VM lane.
set "SystemRoot=%SANDBOX_ROOT%\stub\sysroot"
mkdir "%SystemRoot%\Temp" 2>nul
REM The host may carry NoDefaultCurrentDirectoryInExePath=1: bare-name command
REM resolution skips the cwd, so the stub's own bare calls (RecallUpdate.cmd,
REM call CleanupRecall.cmd) resolve the canaries through PATH - the battery's
REM existing MOCK_CMD idiom applied to the stub sandbox.
set "PATH=%SANDBOX_ROOT%\stub;%PATH%"
set "UPDATE_LOGFILE=%SANDBOX_ROOT%\stub\stub.log"
if exist "%SANDBOX_ROOT%\stub\stub.log" del "%SANDBOX_ROOT%\stub\stub.log" >nul 2>&1
if exist "%SANDBOX_ROOT%\stub\relaunch.canary" del "%SANDBOX_ROOT%\stub\relaunch.canary" >nul 2>&1
if exist "%SANDBOX_ROOT%\stub\cleanup.canary" del "%SANDBOX_ROOT%\stub\cleanup.canary" >nul 2>&1
REM per-case pre-flight: the sysroot probe path must be clean before seeding
if exist "%SystemRoot%\Temp\wou_upgrade_in_progress.txt" (
  echo FAIL: stub pre-flight - the sysroot marker already exists ^(never auto-deleted; remove it and re-run^).
  set "SystemRoot=%STUB_SAVED_SYSROOT%"
  goto Fail
)
REM seed the marker where the stub's probe resolves it (the sandbox sysroot)
echo full,26200,1000>"%SystemRoot%\Temp\wou_upgrade_in_progress.txt"
call "%SANDBOX_ROOT%\stub\RecallStub.cmd" >"%SANDBOX_ROOT%\stub\case_a_out.txt" 2>&1
set "STUB_A_EXIT=!errorlevel!"
REM per-case cleanup of the seed (the DEC-35-08 contract) + env restore
del "%SystemRoot%\Temp\wou_upgrade_in_progress.txt" >nul 2>&1
set "SystemRoot=%STUB_SAVED_SYSROOT%"
set "UPDATE_LOGFILE=%STUB_SAVED_LOG%"
set "PATH=%STUB_SAVED_PATH%"
if "!STUB_A_EXIT!" NEQ "0" (
  echo FAIL: stub section a expected exit code 0, got !STUB_A_EXIT!.
  type "%SANDBOX_ROOT%\stub\case_a_out.txt"
  goto Fail
)
findstr /C:"Info: Upgrade in progress - automatic recall suppressed" "%SANDBOX_ROOT%\stub\stub.log" >nul 2>&1
if errorlevel 1 (
  echo FAIL: stub section a expected the stay-out Info literal in the sandbox log.
  type "%SANDBOX_ROOT%\stub\stub.log"
  goto Fail
)
if exist "%SANDBOX_ROOT%\stub\relaunch.canary" (
  echo FAIL: stub section a expected NO relaunch while the marker stands.
  goto Fail
)
if exist "%SANDBOX_ROOT%\stub\cleanup.canary" (
  echo FAIL: stub section a expected NO cleanup while the marker stands.
  goto Fail
)
findstr /C:"SANDBOX-SHUTDOWN-MOCKED" "%SANDBOX_ROOT%\stub\case_a_out.txt" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: stub section a reached the destructive branch behind a standing marker.
  type "%SANDBOX_ROOT%\stub\case_a_out.txt"
  goto Fail
)
if exist "%SystemRoot%\Temp\wou_upgrade_in_progress.txt" (
  echo FAIL: stub section a - per-case cleanup left the real-path marker behind.
  goto Fail
)
echo [PASS] Stub section a: standing marker kept the real stub out (no canaries, exit 0).

echo [Test 24/25] Stub section b: marker absent - the relaunch canary fires...
REM identical environment to case a (only the marker presence differs)
set "SystemRoot=%SANDBOX_ROOT%\stub\sysroot"
set "PATH=%SANDBOX_ROOT%\stub;%PATH%"
set "UPDATE_LOGFILE=%SANDBOX_ROOT%\stub\stub.log"
if exist "%SANDBOX_ROOT%\stub\stub.log" del "%SANDBOX_ROOT%\stub\stub.log" >nul 2>&1
if exist "%SANDBOX_ROOT%\stub\relaunch.canary" del "%SANDBOX_ROOT%\stub\relaunch.canary" >nul 2>&1
REM the marker is absent (case a's per-case cleanup) - the guard must
REM discriminate: the relaunch canary proves the negative control
call "%SANDBOX_ROOT%\stub\RecallStub.cmd" >"%SANDBOX_ROOT%\stub\case_b_out.txt" 2>&1
set "STUB_B_EXIT=!errorlevel!"
set "SystemRoot=%STUB_SAVED_SYSROOT%"
set "UPDATE_LOGFILE=%STUB_SAVED_LOG%"
set "PATH=%STUB_SAVED_PATH%"
if "!STUB_B_EXIT!" NEQ "0" (
  echo FAIL: stub section b expected exit code 0, got !STUB_B_EXIT!.
  type "%SANDBOX_ROOT%\stub\case_b_out.txt"
  goto Fail
)
if not exist "%SANDBOX_ROOT%\stub\relaunch.canary" (
  echo FAIL: stub section b expected the relaunch canary ^(the guard discriminates on marker presence^).
  type "%SANDBOX_ROOT%\stub\case_b_out.txt"
  goto Fail
)
if exist "%SANDBOX_ROOT%\stub\cleanup.canary" (
  echo FAIL: stub section b - the carriage existed, the cleanup fallback must stay out.
  goto Fail
)
findstr /C:"SANDBOX-SHUTDOWN-MOCKED" "%SANDBOX_ROOT%\stub\case_b_out.txt" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: stub section b reached the destructive branch with the carriage present.
  type "%SANDBOX_ROOT%\stub\case_b_out.txt"
  goto Fail
)
echo [PASS] Stub section b: marker absent fired the relaunch canary, cleanup stayed out (exit 0).

REM -----------------------------------------------------------------------
REM Parity lock: byte-identical literal list with the bash twin's
REM census_literals array (sh\tests\verify-fullupgrade-cycle.bash) - 30
REM entries (the 35 extension, DEC-35-11: the six marker literals entered
REM BOTH lists in the SAME commit), each findstr'd against the REAL surface
REM + a count assert. The stub guard Info literal (DEC-35-04) lives in
REM RecallStub.cmd, not in the engine - the loop greps the real stub for it.
REM -----------------------------------------------------------------------
echo [Test 25/25] Parity lock: 30 pinned literals present in the REAL surface...
set "PARITY_LIT_01=Skipping full upgrade as a LTSB-/LTSC-SKU has been detected"
set "PARITY_LIT_02=already observed - jump complete"
set "PARITY_LIT_03=blocked: no full upgrade media staged for"
set "PARITY_LIT_04=blocked: multiple media language directories staged for"
set "PARITY_LIT_05=blocked: full upgrade media incomplete -"
set "PARITY_LIT_06=blocked: media language"
set "PARITY_LIT_07=differs from system language"
set "PARITY_LIT_08=Full upgrade compatibility scan found no concerns - eligible"
set "PARITY_LIT_09=Full upgrade refused: actionable compatibility issue (app or driver) - see $Windows.~BT\Sources\Panther"
set "PARITY_LIT_10=Full upgrade refused: migration choice not available (edition crossing not supported by setup)"
set "PARITY_LIT_11=Full upgrade refused: system requirements not met (TPM/CPU eligibility)"
set "PARITY_LIT_12=Full upgrade refused: not enough free disk space"
set "PARITY_LIT_13=Full upgrade refused: EULA acceptance required - flag-set invariant, /eula accept must always be present"
set "PARITY_LIT_14=Full upgrade refused: no matching install image for this edition (quiet mode)"
set "PARITY_LIT_15=Full upgrade refused: finalize resume failure - state machine invariant, must never fire in the v1 flag-set"
set "PARITY_LIT_16=Full upgrade rolled back (driver compatibility in most cases) - rollback logs under $Windows.~BT\Sources\Rollback"
set "PARITY_LIT_17=Full upgrade staged - reboot required; success is decided on the next pass by the observed build"
set "PARITY_LIT_18=Full upgrade exited 0 without an observed build change - never reported as success; verify Panther logs"
set "PARITY_LIT_19=Full upgrade failed with undecoded exit code"
set "PARITY_LIT_20=Full upgrade did not advance the OS build"
set "PARITY_LIT_21=blocked: enablement package"
set "PARITY_LIT_22=FULLUPGRADE-STALL-HALT"
set "PARITY_LIT_23=FULLUPGRADE-SCAN-PASS"
set "PARITY_LIT_24=FULLUPGRADE-STAGED"
set "PARITY_LIT_25=wou_upgrade_in_progress.txt"
set "PARITY_LIT_26=FullUpgradeClearMarker"
set "PARITY_LIT_27=FULLUPGRADE-MARKER-POSED"
set "PARITY_LIT_28=RECALL-RESTORED"
set "PARITY_LIT_29=restoring safe state after failed upgrade"
set "PARITY_LIT_30=Upgrade in progress - automatic recall suppressed"
set /a PARITY_COUNT=0
for /f "tokens=1* delims==" %%a in ('set PARITY_LIT_') do (
  set "PARITY_TARGET=%REPO_ROOT%\client\cmd\DoUpdate.cmd"
  if "%%b"=="Upgrade in progress - automatic recall suppressed" set "PARITY_TARGET=%REPO_ROOT%\client\cmd\RecallStub.cmd"
  "%SystemRoot%\System32\findstr.exe" /C:"%%b" "!PARITY_TARGET!" >nul 2>&1
  if errorlevel 1 (
    echo FAIL: parity literal missing from the real surface: %%b
    goto Fail
  )
  set /a PARITY_COUNT+=1
)
if not "!PARITY_COUNT!"=="30" (
  echo FAIL: parity list drifted - expected 30 literals, got !PARITY_COUNT!.
  goto Fail
)
echo [PASS] Parity lock: 30 literals present (29 in the engine, 1 in the stub), list in lockstep with the bash twin.

REM -----------------------------------------------------------------------
REM All Passed
REM -----------------------------------------------------------------------
echo.
echo =======================================================================
echo SUCCESS: Full upgrade cycle battery passed - census + states S1-S21 + stub section + parity lock.
echo =======================================================================
echo FULLUPGRADE-CYCLE-PASS
call :Cleanup
exit /b 0

:Fail
echo.
echo =======================================================================
echo FAILURE: Full upgrade cycle test failed.
echo =======================================================================
call :Cleanup
exit /b 1

:MakeSandboxStub
REM The single scripted transform (DEC-35-08): the terminal shutdown line
REM becomes the mock echo; every other line passes through in order.
REM Delayed-expansion echo preserves %-content, and the repo stub carries no
REM exclamation marks, so !LINE! never eats a literal. Empty lines are not
REM carried (semantically inert to a batch file).
set "SBS_MOTIF=shutdown.exe /r /f /t 1"
(for /f "usebackq delims=" %%L in (`type "%~1"`) do (
  set "SBS_LINE=%%L"
  set "SBS_OUT=!SBS_LINE!"
  if not "!SBS_LINE:%SBS_MOTIF%=!"=="!SBS_LINE!" set "SBS_OUT=echo SANDBOX-SHUTDOWN-MOCKED"
  echo(!SBS_OUT!
))>"%~2"
set "SBS_MOTIF="
set "SBS_LINE="
set "SBS_OUT="
goto :eof

:Cleanup
REM restore the stashed EKB payload cabs and remove the sandbox
if exist "%MOCK_GLB%\fu_stash_pre.cab" ren "%MOCK_GLB%\fu_stash_pre.cab" "windows11.0-kb5064081-x64.cab" >nul 2>&1
if exist "%MOCK_GLB%\fu_stash_epkg.cab" ren "%MOCK_GLB%\fu_stash_epkg.cab" "windows11.0-kb5054156-x64.cab" >nul 2>&1
if exist "%SANDBOX_ROOT%" (
  rmdir /s /q "%SANDBOX_ROOT%" 2>nul
)
goto :eof
