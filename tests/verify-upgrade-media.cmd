@echo off
setlocal enabledelayedexpansion

REM =======================================================================
REM WSUS Offline Update - Upgrade Media Gate
REM File: tests\verify-upgrade-media.cmd
REM
REM Plan 33-04 (ACQ-03/ACQ-05 documentation links + the staged-media truth):
REM validates the consigned spike record and the assembled media honestly.
REM
REM Unconditional legs (the consigned record the code implements):
REM   1. .planning\tmp\33-spike\33-SPIKE-RECORD.md exists and carries the
REM      four [PROBE- markers (probe matrix a-d each with an outcome token)
REM   2. the record is scrub clean of signed-URL token query material
REM      (grep P[1-4]= = 0)
REM   3. doc\upgrade-media-assembly.md carries the winning-set section, the
REM      wimlib GPLv3 note and the exFAT/FAT32 guidance (ACQ-05)
REM
REM Branch on the staged media (T-33-11/T-33-12 honesty):
REM   - client\upgrade\26200-x64\en-us\sources\install.esd present:
REM     sources\setup.exe must exist non-empty, the staged manifest meta
REM     rows must parse (uuid + totals present), and the integrity class
REM     file must exist (created after staging, ACQ-04)
REM   - absent: media absence is legitimate ONLY under the consigned
REM     contingency - the record must carry the CONSIGN-DISM-FAILURE
REM     marker; a missing record always fails
REM
REM Success sentinel: UPGRADE-MEDIA-PASS. Modeled on the consigned-gate
REM pattern (pushd-held root, :Fail protocol, exit-code fail-closed).
REM =======================================================================

REM The pushd is HELD for the whole run: every check runs from the repo root.
pushd "%~dp0.."
set "REPO_ROOT=%CD%"

echo =======================================================================
echo WSUS Offline Update - Upgrade Media Gate
echo =======================================================================

set "RECORD=.planning\tmp\33-spike\33-SPIKE-RECORD.md"
set "DOC=doc\upgrade-media-assembly.md"
set "MEDIA=client\upgrade\26200-x64\en-us"

if not exist "%RECORD%" (
  echo FAIL: the consigned spike record is missing: %RECORD%
  goto Fail
)

echo [MEDIA 1] the consigned probe matrix - four [PROBE- markers...
rem find /c prints "---------- PATH: N" - parse the count after the colon
for /F "tokens=2 delims=:" %%c in ('%SystemRoot%\System32\find.exe /c "[PROBE-" "%RECORD%" 2^>nul') do set "PROBES=%%c"
if not defined PROBES set "PROBES=0"
if %PROBES% LSS 4 (
  echo FAIL: the record carries %PROBES% PROBE markers, expected at least 4
  goto Fail
)
echo [MEDIA 1] PASS ^(4 probe markers^)

echo [MEDIA 2] the record scrub gate - zero token query material...
set "SCRUB="
for /F %%c in ('%SystemRoot%\System32\findstr.exe /R /C:"P[1-4]=" "%RECORD%" 2^>nul ^| %SystemRoot%\System32\find.exe /c /v ""') do set "SCRUB=%%c"
if not defined SCRUB set "SCRUB=0"
if not "%SCRUB%"=="0" (
  echo FAIL: the record carries %SCRUB% token-material line^(s^) - scrub before consigning
  goto Fail
)
echo [MEDIA 2] PASS ^(scrub = 0^)

echo [MEDIA 3] the assembly doc markers - winning set / wimlib GPLv3 / exFAT...
findstr /I /C:"winning" "%DOC%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: the doc carries no winning-set section
  goto Fail
)
for /F "tokens=2 delims=:" %%c in ('%SystemRoot%\System32\find.exe /c /i "wimlib" "%DOC%" 2^>nul') do set "WIMLIBS=%%c"
if not defined WIMLIBS set "WIMLIBS=0"
if %WIMLIBS% LSS 2 (
  echo FAIL: the doc names wimlib %WIMLIBS% time^(s^), expected at least 2
  goto Fail
)
findstr /I /C:"GPLv3" "%DOC%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: the doc carries no GPLv3 license note
  goto Fail
)
findstr /I /C:"exFAT" "%DOC%" >nul 2>&1
if errorlevel 1 (
  echo FAIL: the doc carries no exFAT/FAT32 guidance
  goto Fail
)
echo [MEDIA 3] PASS ^(winning set, wimlib GPLv3 note, exFAT guidance^)

if exist "%MEDIA%\sources\install.esd" (
  echo [MEDIA 4] the staged media - setup.exe, manifest meta rows, integrity class...
  if not exist "%MEDIA%\sources\setup.exe" (
    echo FAIL: the staged media carries no sources\setup.exe
    goto Fail
  )
  for /F %%F in ("%MEDIA%\sources\setup.exe") do (
    if %%~zF EQU 0 (
      echo FAIL: sources\setup.exe is empty
      goto Fail
    )
  )
  set "M_UUID="
  set "M_TOTAL_BYTES="
  set "M_TOTAL_MIB="
  for /F "usebackq eol=# tokens=1-2 delims=|" %%a in ("%MEDIA%\manifest.txt") do (
    if /i "%%a"=="uuid" if not defined M_UUID set "M_UUID=%%b"
    if /i "%%a"=="total_bytes" if not defined M_TOTAL_BYTES set "M_TOTAL_BYTES=%%b"
    if /i "%%a"=="total_mib" if not defined M_TOTAL_MIB set "M_TOTAL_MIB=%%b"
  )
  if "!M_UUID!"=="" (
    echo FAIL: the staged manifest carries no uuid meta row
    goto Fail
  )
  if "!M_TOTAL_BYTES!"=="" (
    echo FAIL: the staged manifest carries no total_bytes meta row
    goto Fail
  )
  if "!M_TOTAL_MIB!"=="" (
    echo FAIL: the staged manifest carries no total_mib meta row
    goto Fail
  )
  if not exist "client\md\hashes-upgrade-26200-x64-en-us.txt" (
    echo FAIL: the media integrity class is missing ^(created after staging, ACQ-04^)
    goto Fail
  )
  findstr /B /C:"%%%%" "client\md\hashes-upgrade-26200-x64-en-us.txt" >nul 2>&1
  if errorlevel 1 (
    echo FAIL: the integrity class carries no hashdeep header
    goto Fail
  )
  echo [MEDIA 4] PASS ^(media uuid !M_UUID!, totals !M_TOTAL_BYTES! bytes / !M_TOTAL_MIB! MiB, db class present^)
) else (
  echo [MEDIA 4] no staged media - the consigned contingency is the only legitimate absence...
  %SystemRoot%\System32\findstr.exe /C:"CONSIGN-DISM-FAILURE" "%RECORD%" >nul 2>&1
  if errorlevel 1 (
    echo FAIL: no staged media AND no CONSIGN-DISM-FAILURE marker in the record - media absence is unexplained
    goto Fail
  )
  echo [MEDIA 4] PASS ^(absence under the consigned CONSIGN-DISM-FAILURE contingency^)
)

echo.
echo =======================================================================
echo UPGRADE-MEDIA-PASS: the consigned record and the staged media validate.
echo =======================================================================
popd
exit /b 0

:Fail
echo.
echo =======================================================================
echo FAILURE: the upgrade media gate failed - see the named MEDIA leg above.
echo =======================================================================
popd
exit /b 1
