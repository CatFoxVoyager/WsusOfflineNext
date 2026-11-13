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
REM
REM Can-fail proofs (recorded run notes - perform in a scratch copy, never
REM leave the mutation behind):
REM   (a) copy this battery to %TEMP%, flip ONE expected literal (the S8
REM       TPM/CPU message), run the scratch -> it must exit non-zero with a
REM       named FAIL; delete the scratch afterwards.
REM   (b) copy client\cmd\DoUpdate.cmd to a scratch, strip the EULA flag from
REM       the launch line, run the census findstr against the scratch ->
REM       zero hits proves the census can fail; delete the scratch.
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

REM -----------------------------------------------------------------------
REM Census: the frozen flag-set on the REAL engine file
REM -----------------------------------------------------------------------
echo [Test 1/14] Census: frozen flag-set == 2 call sites, zero bypass tokens...
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
echo [Test 2/14] State S1: no /upgradeos target - zero FULLUPGRADE- lines...
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
echo [Test 3/14] State S2: LTSB/LTSC edition detected - named skip...
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
echo [Test 4/14] State S3: observed convergence - jump complete + purge...
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
echo [Test 5/14] State S4: no media staged for the target - named refusal...
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
echo [PASS] State S4: media-missing refusal fired verbatim (exit 0).

REM -----------------------------------------------------------------------
REM State S5: Media incomplete (sources\install.esd absent)
REM -----------------------------------------------------------------------
echo [Test 6/14] State S5: media incomplete - names the missing file...
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
echo [Test 7/14] State S6: ambiguous multi-language media tree...
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
echo [Test 8/14] State S7: media language differs from system language...
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
echo [Test 9/14] State S8a: scan refusal 0xC1900200 - TPM/CPU eligibility...
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

echo [Test 10/14] State S8b: scan refusal 0xC190020E - disk space...
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
echo [PASS] State S8b: scan refusal 0xC190020E decoded to the disk-space cause (exit 0).

REM -----------------------------------------------------------------------
REM State S9: Staged termination (scan passes, launch reports 3010)
REM -----------------------------------------------------------------------
echo [Test 11/14] State S9: staged upgrade terminates the pass before the security pass...
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
echo [PASS] State S9: staged termination proven (exit 3011, Updates pending, WUA never reached).

REM -----------------------------------------------------------------------
REM State S10: Suspect - exit 0 without an observed build change
REM -----------------------------------------------------------------------
echo [Test 12/14] State S10: launch exit 0 without build change is the suspect row...
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

if "!S10_EXIT!" NEQ "0" (
  echo FAIL: State S10 expected exit code 0, got !S10_EXIT!.
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
echo [PASS] State S10: suspect row fired with the never-success wording (exit 0).

REM -----------------------------------------------------------------------
REM State S11: Rollback (0xC1900101)
REM -----------------------------------------------------------------------
echo [Test 13/14] State S11: launch exit 0xC1900101 - rollback row...
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
echo [Test 14/14] State S12 and S13: undecoded code + signed-decimal normalization...
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
REM All Passed
REM -----------------------------------------------------------------------
echo.
echo =======================================================================
echo SUCCESS: Full upgrade cycle battery passed - census + states S1-S13.
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

:Cleanup
REM restore the stashed EKB payload cabs and remove the sandbox
if exist "%MOCK_GLB%\fu_stash_pre.cab" ren "%MOCK_GLB%\fu_stash_pre.cab" "windows11.0-kb5064081-x64.cab" >nul 2>&1
if exist "%MOCK_GLB%\fu_stash_epkg.cab" ren "%MOCK_GLB%\fu_stash_epkg.cab" "windows11.0-kb5054156-x64.cab" >nul 2>&1
if exist "%SANDBOX_ROOT%" (
  rmdir /s /q "%SANDBOX_ROOT%" 2>nul
)
goto :eof
