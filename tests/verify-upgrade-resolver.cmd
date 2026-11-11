@echo off
setlocal enabledelayedexpansion

REM =======================================================================
REM WSUS Offline Update - UUP Payload Resolver Twin Battery (Windows CMD)
REM File: tests\verify-upgrade-resolver.cmd
REM
REM Plan 33-02 task 2 battery (ACQ-01): the VBS resolver twin
REM (cmd\ResolveUpgradePayloads.vbs) plus the cross-twin sha256 parity
REM gate over the committed golden fixture. Sandbox only - no network,
REM no API calls (the fixtures ARE the bites: golden + 5 negatives).
REM
REM   GATE 1. VBS positive: resolve over the golden fixture writes the
REM           DEC-33-02 manifest (206 lines: 3 header + 7 meta + 196
REM           rows), zero token-URL material.
REM   GATE 2. VBS negatives: the five failure shapes (USER_RATE_LIMITED,
REM           UNSUPPORTED_LANG, empty files map, hostile names, malformed
REM           JSON) each exit nonzero and leave NO manifest file.
REM   GATE 3. Bash twin: uup_resolve --fixture over the SAME golden
REM           fixture via the resolved bash interpreter (bare PATH
REM           first, Git for Windows fallback - the phase-gate idiom).
REM   GATE 4. Parity: certutil SHA256 digests of both manifests are
REM           EQUAL - one input, two evaluators, byte-identical output
REM           (a VBS emission with different field order, unsorted rows
REM           or different line endings fails this gate).
REM
REM Known-bad proof the gates can fail: the five negatives drive every
REM VBS refusal red by construction; any emission drift breaks the
REM GATE 4 digest equality.
REM Success sentinel: UPG-RESOLVER-CMD-PASS. Any miss prints FAIL and
REM exits 1.
REM =======================================================================

pushd "%~dp0.."
set "REPO_ROOT=%CD%"

echo =======================================================================
echo WSUS Offline Update - UUP Payload Resolver Twin Battery (Windows CMD)
echo =======================================================================

set "GOLDEN=tests\fixtures\uup-get-26200-en-us-multiedition.json"
set "VBS_SCRIPT=cmd\ResolveUpgradePayloads.vbs"
set "SCRATCH=%TEMP%\wou-upg-resolver-battery"
set "TMPD_FWD=%SCRATCH:\=/%"

if not exist "%REPO_ROOT%\%GOLDEN%" (
  echo FAIL: missing golden fixture "%REPO_ROOT%\%GOLDEN%"
  goto Fail
)
if not exist "%REPO_ROOT%\%VBS_SCRIPT%" (
  echo FAIL: missing VBS twin "%REPO_ROOT%\%VBS_SCRIPT%"
  goto Fail
)

if exist "%SCRATCH%" rd /s /q "%SCRATCH%"
md "%SCRATCH%" >nul 2>&1
if not exist "%SCRATCH%" (
  echo FAIL: cannot create the battery scratch dir "%SCRATCH%"
  goto Fail
)

REM -----------------------------------------------------------------------
REM GATE 1: VBS positive - manifest written from the golden fixture
REM -----------------------------------------------------------------------
echo [GATE 1] VBS positive resolve over the golden fixture ...
set "VBS_MANIFEST=%SCRATCH%\manifest-vbs.txt"
cscript //Nologo "%VBS_SCRIPT%" 26200 x64 en-us "%VBS_MANIFEST%" "--fixture:%GOLDEN%"
if errorlevel 1 (
  echo FAIL: the VBS positive resolve exited nonzero
  goto Fail
)
if not exist "%VBS_MANIFEST%" (
  echo FAIL: the VBS positive resolve wrote no manifest
  goto Fail
)
findstr /C:"total_bytes|10902883408" "%VBS_MANIFEST%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: the VBS manifest does not carry the pinned total_bytes meta row
  goto Fail
)
findstr /C:"total_mib|10397" "%VBS_MANIFEST%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: the VBS manifest does not carry the pinned total_mib meta row
  goto Fail
)
findstr /I /C:"http" "%VBS_MANIFEST%" >nul 2>&1
if not errorlevel 1 (
  echo FAIL: token-URL material ^(http^) found in the VBS manifest
  goto Fail
)
echo [GATE 1] PASS: manifest written, totals pinned, zero token-URL material

REM -----------------------------------------------------------------------
REM GATE 2: VBS negatives - five failure shapes, all fail-closed
REM -----------------------------------------------------------------------
echo [GATE 2] VBS negative refusals ...
set "NEG_LIST=uup-error-ratelimited.json uup-error-unsupported-lang.json uup-error-empty-files.json uup-error-hostile-name.json uup-error-malformed.json"
for %%N in (%NEG_LIST%) do (
  set "NEG_OUT=%SCRATCH%\neg-%%N.manifest"
  if exist "!NEG_OUT!" del /q "!NEG_OUT!"
  cscript //Nologo "%VBS_SCRIPT%" 26200 x64 en-us "!NEG_OUT!" "--fixture:tests\fixtures\%%N" >nul 2>&1
  if not errorlevel 1 (
    echo FAIL: negative fixture %%N exited 0 - the refusal did not fire
    goto Fail
  )
  if exist "!NEG_OUT!" (
    echo FAIL: negative fixture %%N left an output file - not all-or-nothing
    goto Fail
  )
  echo [GATE 2]   %%N: exit nonzero, no output file
)
echo [GATE 2] PASS: all five failure shapes refuse all-or-nothing

REM -----------------------------------------------------------------------
REM GATE 3: the bash twin over the SAME golden fixture
REM -----------------------------------------------------------------------
echo [GATE 3] bash twin resolve (fixture seam) ...
set "BASH_EXE=bash"
where bash >nul 2>&1
if errorlevel 1 (
  if exist "%ProgramFiles%\Git\bin\bash.exe" (
    set "BASH_EXE=%ProgramFiles%\Git\bin\bash.exe"
  )
)
set "BASH_MANIFEST=%SCRATCH%\manifest-bash.txt"
"%BASH_EXE%" -c "source sh/libraries/upgrade-payloads.bash && uup_resolve 26200 x64 en-us \"$1\" --fixture tests/fixtures/uup-get-26200-en-us-multiedition.json" resolver-battery "%TMPD_FWD%/manifest-bash.txt"
if errorlevel 1 (
  echo FAIL: the bash twin resolve exited nonzero
  goto Fail
)
if not exist "%BASH_MANIFEST%" (
  echo FAIL: the bash twin resolve wrote no manifest
  goto Fail
)
echo [GATE 3] PASS: bash twin manifest written

REM -----------------------------------------------------------------------
REM GATE 4: cross-twin sha256 parity (certutil digests must be equal)
REM -----------------------------------------------------------------------
echo [GATE 4] cross-twin sha256 parity ...
set "VBS_HASH="
set "BASH_HASH="
for /F "skip=1 delims=" %%H in ('certutil -hashfile "%VBS_MANIFEST%" SHA256 2^>nul') do (
  if not defined VBS_HASH set "VBS_HASH=%%H"
)
for /F "skip=1 delims=" %%H in ('certutil -hashfile "%BASH_MANIFEST%" SHA256 2^>nul') do (
  if not defined BASH_HASH set "BASH_HASH=%%H"
)
if not defined VBS_HASH (
  echo FAIL: could not digest the VBS manifest
  goto Fail
)
if not defined BASH_HASH (
  echo FAIL: could not digest the bash manifest
  goto Fail
)
if not "%VBS_HASH%"=="%BASH_HASH%" (
  echo FAIL: cross-twin parity broken - the two manifests differ
  echo        VBS : %VBS_HASH%
  echo        bash: %BASH_HASH%
  goto Fail
)
echo [GATE 4] PASS: byte-identical manifests (sha256 %VBS_HASH%)

REM -----------------------------------------------------------------------
REM All gates green - clean the scratch and print the sentinel
REM -----------------------------------------------------------------------
rd /s /q "%SCRATCH%" >nul 2>&1
popd
echo.
echo =======================================================================
echo UPG-RESOLVER-CMD-PASS: VBS positive + 5 negatives + bash twin + parity green.
echo =======================================================================
exit /b 0

:Fail
popd
echo.
echo =======================================================================
echo FAILURE: UUP payload resolver twin battery failed.
echo =======================================================================
exit /b 1
