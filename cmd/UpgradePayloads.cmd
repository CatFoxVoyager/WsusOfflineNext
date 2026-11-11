@echo off
setlocal enabledelayedexpansion

rem =======================================================================
rem WSUS Offline Update - UUP Upgrade Payload Acquisition Library (CMD)
rem File: cmd\UpgradePayloads.cmd
rem
rem Plan 33-03 (ACQ-02 + the sha256 half of ACQ-04): the CMD acquisition
rem stage for the full feature-update payloads resolved by
rem cmd\ResolveUpgradePayloads.vbs. The bash twin lives in
rem sh\download-updates-tasks\62-upgrade-payloads.bash +
rem sh\libraries\upgrade-payloads.bash - parity of BEHAVIOR, not bytes.
rem
rem Entry dispatch: when the first argument names a subroutine label the
rem script jumps to it, so the battery (tests\verify-upgrade-payloads.cmd)
rem calls subroutines directly without network, while the engine
rem (cmd\DownloadUpdates.cmd Phase-33 region) calls :UpgSectionEntry.
rem
rem Subroutines:
rem   :UpgReadFuMedia <build> <arch> [table]   - echo the upgrades.txt row's
rem           field 11 (fu_media); exit 1 when the row is absent (DEC-33-09)
rem   :UpgBudgetLine <manifest>                - the ACQ-05 budget INFO line
rem           (warn-only, DEC-33-07), named before ANY download
rem   :UpgClassifySize <size_bytes>            - >= 104857600 -> aria2,
rem           < -> wget. STRING compare only (digit-count, then a zero-padded
rem           lexicographic compare): NEVER signed 32-bit arithmetic on raw
rem           byte sizes - the measured 10902883408-byte total silently
rem           wraps set /a (DEC-33-02 extension).
rem   :UpgHashGate <manifest> <spool_dir> [hashdeep]
rem           - fail-closed whole-spool audit against a hashdeep expectation
rem             generated from the manifest in TEMP; ANY mismatch = loud
rem             refusal with NOTHING staged (T-33-08, the structural
rem             after-resume re-verify, ACQ-02)
rem   :UpgAcquire <manifest> <url_map> <spool_dir> - orchestrator: budget
rem           line FIRST, size-descending (big-first) split download (aria2
rem           resume-tuned / wget -c), hash gate, TEMP-artifact cleanup on
rem           EVERY exit path (T-33-09: the url map and the downloader lists
rem           carry token URL material and never persist)
rem   :UpgSectionEntry - the engine gate: no TMP_UPG_TARGETS selection or no
rem           fu_media=1 row = absolute no-op (statu quo, DEC-33-09)
rem
rem Resume-tuned options (ACQ-02, research Pitfall 4): this library defines
rem its OWN option variables (UUP_DLDR_* / UUP_WGET_*). The engine's shared
rem DLDR_* defaults are consumed NOWHERE here and stay byte-identical - the
rem generated aria2 line carries --always-resume=false
rem --max-resume-failure-tries=0, the NOT-resume-tuned shape, and a
rem multi-GiB ESD must never redownload from zero.
rem =======================================================================

rem Entry dispatch - the battery calls subroutines directly.
rem UUP_LIB_DIR is captured BEFORE the dispatch shift: `call script :label`
rem moves the label into %0, which makes %~dp0 resolve to the caller's cwd
rem everywhere below (measured live); the internal `call :label` form
rem restores the real script dir, but the capture here is authoritative.
set "UUP_LIB_DIR=%~dp0"
if "%~1"=="" goto :UpgUsage
set "UUP_ENTRY=%~1"
if "!UUP_ENTRY:~0,1!" neq ":" goto :UpgUsage
shift
goto %UUP_ENTRY%

:UpgUsage
echo Usage: %~n0 ^<subroutine^> [args...]
echo Subroutines: :UpgReadFuMedia :UpgBudgetLine :UpgClassifySize :UpgHashGate :UpgAcquire :UpgSectionEntry
exit /b 1

:UpgReadFuMedia
rem %1 = target build, %2 = arch, %3 = optional table override
rem (default ..\client\UpdateTable\upgrades.txt). Echoes the matched row's
rem field 11 (fu_media), also sets UUP_FM_VALUE for internal callers;
rem exit 1 = row absent, exit 2 = bad arguments.
rem NOTE on empty fields: for /F collapses consecutive delimiters, so a row
rem with empty EKB fields shifts token 11. The shift can only ever DOWNGRADE
rem an answer to empty (fail-closed to the statu quo) - a false "1" is
rem impossible because a fu_media=1 row carries a complete EKB prefix and an
rem empty blocked_reason, leaving nothing at token 11 to misread.
set "UUP_FM_VALUE="
set "UUP_FM_BUILD=%~1"
set "UUP_FM_ARCH=%~2"
set "UUP_FM_TABLE=%~3"
if "!UUP_FM_BUILD!"=="" exit /b 2
if "!UUP_FM_ARCH!"=="" exit /b 2
if "!UUP_FM_TABLE!"=="" set "UUP_FM_TABLE=..\client\UpdateTable\upgrades.txt"
if not exist "!UUP_FM_TABLE!" exit /b 1
for /F "usebackq eol=# tokens=1-12 delims=|" %%a in ("!UUP_FM_TABLE!") do (
  if "%%a"=="!UUP_FM_BUILD!" if "%%b"=="!UUP_FM_ARCH!" (
    if not "%%k"=="" (
      set "UUP_FM_VALUE=%%k"
      echo %%k
    )
    exit /b 0
  )
)
exit /b 1

:UpgBudgetLine
rem %1 = the acquisition manifest (DEC-33-02). Emits the ACQ-05 media
rem budget line BEFORE any download: a warning, never a block (DEC-33-07).
rem The MiB figure comes verbatim from the manifest's total_mib meta row -
rem computed twin-side in double precision only (DEC-33-02), never re-summed
rem here with set /a.
set "UUP_BL_MANIFEST=%~1"
if "!UUP_BL_MANIFEST!"=="" (
  echo ERROR: upgrade payload manifest argument missing.
  exit /b 1
)
if not exist "!UUP_BL_MANIFEST!" (
  echo ERROR: upgrade payload manifest not found: !UUP_BL_MANIFEST!
  exit /b 1
)
set "UUP_BL_MIB="
set "UUP_BL_BYTES="
set "UUP_BL_BUILD="
set "UUP_BL_LANG="
set /a UUP_BL_ROWS=0
for /F "usebackq eol=# tokens=1-3 delims=|" %%a in ("!UUP_BL_MANIFEST!") do (
  if "%%a"=="total_mib" set "UUP_BL_MIB=%%b"
  if "%%a"=="total_bytes" set "UUP_BL_BYTES=%%b"
  if "%%a"=="build" set "UUP_BL_BUILD=%%b"
  if "%%a"=="lang" set "UUP_BL_LANG=%%b"
  if not "%%c"=="" set /a UUP_BL_ROWS+=1
)
if "!UUP_BL_MIB!"=="" (
  echo ERROR: manifest carries no total_mib meta row: !UUP_BL_MANIFEST!
  exit /b 1
)
echo BUDGET: !UUP_BL_ROWS! files, !UUP_BL_BYTES! bytes, !UUP_BL_MIB! MiB ^(target !UUP_BL_BUILD! !UUP_BL_LANG!^)
exit /b 0

:UpgClassifySize
rem %1 = a byte size string. Echoes the downloader class AND sets UUP_CLASS
rem for internal callers; exit 2 on a non-numeric argument. The threshold is
rem 104857600 bytes (100 MiB): >= aria2 (resumable, segmented), < wget.
rem Big-number compare by STRING shape only: a longer digit count always
rem wins; equal length compares the zero-padded strings (which for 9-digit
rem numeric strings resolves identically numerically or lexicographically).
rem set /a is NEVER applied to the raw size.
set "UUP_CS_SIZE=%~1"
set "UUP_CLASS="
if "!UUP_CS_SIZE!"=="" exit /b 2
echo !UUP_CS_SIZE!| findstr /R "^[0-9][0-9]*$" >nul 2>&1
if errorlevel 1 exit /b 2
if not "!UUP_CS_SIZE:~9!"=="" (
  rem 10 or more digits: always above the 9-digit 104857600 threshold
  set "UUP_CLASS=aria2"
  echo aria2
  exit /b 0
)
set "UUP_CS_PAD=000000000!UUP_CS_SIZE!"
if "!UUP_CS_PAD:~-9!" GEQ "104857600" (
  set "UUP_CLASS=aria2"
  echo aria2
) else (
  set "UUP_CLASS=wget"
  echo wget
)
exit /b 0

:UpgHashGate
rem %1 = manifest, %2 = spool directory with the downloaded payloads,
rem %3 = optional hashdeep binary override (default ..\client\bin\hashdeep
rem by architecture). Generates a hashdeep-format expectation file in TEMP
rem from the manifest rows (size,sha256,name - the unquoted CSV hashdeep
rem writes, size always the first column), audits the WHOLE spool with
rem hashdeep -a -b -vv -k -r, and refuses loudly on ANY mismatch with
rem NOTHING moved (fail-closed, T-33-08). A truncated or otherwise modified
rem spool cannot pass even though a resume "succeeded" - the gate runs
rem AFTER download completion unconditionally.
set "UUP_HG_MANIFEST=%~1"
set "UUP_HG_SPOOL=%~2"
set "UUP_HG_BIN=%~3"
if "!UUP_HG_MANIFEST!"=="" (
  echo ERROR: manifest argument missing for the hash gate.
  exit /b 1
)
if "!UUP_HG_SPOOL!"=="" (
  echo ERROR: spool directory argument missing for the hash gate.
  exit /b 1
)
if not exist "!UUP_HG_MANIFEST!" (
  echo ERROR: manifest not found: !UUP_HG_MANIFEST!
  exit /b 1
)
if not exist "!UUP_HG_SPOOL!\" (
  echo ERROR: spool directory not found: !UUP_HG_SPOOL!
  exit /b 1
)
if "!UUP_HG_BIN!"=="" (
  rem The default is anchored at the library's own directory (captured
  rem before the dispatch shift), not at the caller's cwd - the sandbox
  rem batteries run from the repo root.
  if /i "%PROCESSOR_ARCHITECTURE%"=="AMD64" (set "UUP_HG_BIN=!UUP_LIB_DIR!..\client\bin\hashdeep64.exe") else (
    if /i "%PROCESSOR_ARCHITEW6432%"=="AMD64" (set "UUP_HG_BIN=!UUP_LIB_DIR!..\client\bin\hashdeep64.exe") else (set "UUP_HG_BIN=!UUP_LIB_DIR!..\client\bin\hashdeep.exe")
  )
)
if not exist "!UUP_HG_BIN!" (
  echo ERROR: hash computing/auditing utility not found: !UUP_HG_BIN!
  exit /b 1
)
set "UUP_HG_EXP=%TEMP%\wou-upg-expectation-%RANDOM%%RANDOM%.txt"
rem The expectation lives OUTSIDE the audited spool (hashdeep counts the
rem -k file itself as a new file otherwise) and is deleted on every path.
>"!UUP_HG_EXP!" echo %%%%%%%% HASHDEEP-1.0
>>"!UUP_HG_EXP!" echo %%%%%%%% size,sha256,filename
>>"!UUP_HG_EXP!" echo ## Generated from the upgrade payload manifest by cmd\UpgradePayloads.cmd :UpgHashGate - TEMP runtime artifact, never persisted
set /a UUP_HG_ROWS=0
set /a UUP_HG_BAD=0
for /F "usebackq eol=# tokens=1-3 delims=|" %%a in ("!UUP_HG_MANIFEST!") do (
  if not "%%c"=="" (
    set /a UUP_HG_ROWS+=1
    set "UUP_HG_N=%%a"
    set "UUP_HG_H=%%b"
    set "UUP_HG_S=%%c"
    rem Row grammar guards (the manifest is a generated contract; any
    rem malformed row is a loud failure, never a skipped row)
    echo !UUP_HG_N!| findstr /R "^[A-Za-z0-9._-][A-Za-z0-9._-]*$" >nul 2>&1
    if errorlevel 1 set /a UUP_HG_BAD+=1
    if "!UUP_HG_H:~63!"=="" set /a UUP_HG_BAD+=1
    if not "!UUP_HG_H:~64!"=="" set /a UUP_HG_BAD+=1
    echo !UUP_HG_H!| findstr /R "^[0-9a-f][0-9a-f]*$" >nul 2>&1
    if errorlevel 1 set /a UUP_HG_BAD+=1
    echo !UUP_HG_S!| findstr /R "^[0-9][0-9]*$" >nul 2>&1
    if errorlevel 1 set /a UUP_HG_BAD+=1
    if !UUP_HG_BAD! GTR 0 (
      echo ERROR: malformed manifest row refused by the hash gate: %%a
      goto :UpgHashGateFail
    )
    >>"!UUP_HG_EXP!" echo !UUP_HG_S!,!UUP_HG_H!,!UUP_HG_N!
  )
)
if !UUP_HG_ROWS! EQU 0 (
  echo ERROR: manifest carries no payload rows: !UUP_HG_MANIFEST!
  goto :UpgHashGateFail
)
echo Info: Auditing !UUP_HG_ROWS! payload file^(s^) in the spool against the manifest sha256 values...
"!UUP_HG_BIN!" -a -b -vv -k "!UUP_HG_EXP!" -r "!UUP_HG_SPOOL!"
set "UUP_HG_RC=!errorlevel!"
if exist "!UUP_HG_EXP!" del "!UUP_HG_EXP!" >nul 2>&1
if not "!UUP_HG_RC!"=="0" (
  echo ERROR: Upgrade payload integrity verification FAILED - the spool is refused, nothing is staged.
  exit /b 1
)
echo Info: Spool integrity audit passed - the whole spool matches the manifest sha256 values.
exit /b 0

:UpgHashGateFail
if exist "!UUP_HG_EXP!" del "!UUP_HG_EXP!" >nul 2>&1
exit /b 1

:UpgAcquire
rem === orchestrator ===
rem %1 = manifest (DEC-33-02), %2 = url map (TEMP runtime artifact written
rem by the resolver's /urlmap: mode), %3 = spool directory for the payload
rem files (the DEC-33-14 spool subtree).
rem Order (ACQ-02): the budget line FIRST, then the size-descending
rem (big-first) split download - aria2 for >= 104857600 bytes with the
rem resume-tuned option set, wget -c below - then the fail-closed hash
rem gate, then TEMP-artifact cleanup on EVERY exit path (T-33-09).
set "UUP_AQ_MANIFEST=%~1"
set "UUP_AQ_URLMAP=%~2"
set "UUP_AQ_SPOOL=%~3"
if "!UUP_AQ_MANIFEST!"=="" (
  echo ERROR: manifest argument missing for :UpgAcquire.
  exit /b 1
)
if "!UUP_AQ_URLMAP!"=="" (
  echo ERROR: url map argument missing for :UpgAcquire.
  exit /b 1
)
if "!UUP_AQ_SPOOL!"=="" (
  echo ERROR: spool directory argument missing for :UpgAcquire.
  exit /b 1
)
if not exist "!UUP_AQ_MANIFEST!" (
  echo ERROR: upgrade payload manifest not found: !UUP_AQ_MANIFEST!
  exit /b 1
)
if not exist "!UUP_AQ_SPOOL!" md "!UUP_AQ_SPOOL!"

rem The media budget precedes ANY download (ACQ-05, DEC-33-07: warn only)
call :UpgBudgetLine "!UUP_AQ_MANIFEST!"
if errorlevel 1 goto :UpgAcquireFail

rem The url map must exist once the budget is named - the budget is the
rem FIRST observable output of the acquisition, and the map check precedes
rem every downloader invocation (a fixture-mode resolve writes no map; the
rem battery's budget-deep case depends on this order)
if not exist "!UUP_AQ_URLMAP!" (
  echo ERROR: UUP url map not found: !UUP_AQ_URLMAP!
  goto :UpgAcquireFail
)

rem Downloader binaries: env overrides exist for the sandbox battery; the
rem engine defaults mirror the shared resolution idioms.
if defined UUP_ARIA2_PATH (set "UUP_DLDR_PATH=!UUP_ARIA2_PATH!") else (
  if /i "%PROCESSOR_ARCHITECTURE%"=="AMD64" (set "UUP_DLDR_PATH=..\bin\aria2c-x64.exe") else set "UUP_DLDR_PATH=..\bin\aria2c-x86.exe"
)
if defined UUP_WGET_PATH (set "UUP_WGET_BIN=!UUP_WGET_PATH!") else (
  if defined WGET_PATH (set "UUP_WGET_BIN=!WGET_PATH!") else set "UUP_WGET_BIN="
)
if "!UUP_WGET_BIN!"=="" (
  if /i "%PROCESSOR_ARCHITECTURE%"=="AMD64" (set "UUP_WGET_BIN=..\bin\wget64.exe") else set "UUP_WGET_BIN=..\bin\wget.exe"
)
rem Resume-tuned option variables (ACQ-02, research Pitfall 4) - the UUP
rem section carries its own set; the shared DLDR_* vars are not touched.
rem The aria2 set is the spike-proven shape: continue semantics kept
rem default-on, segmented connections, no file allocation, bounded retries.
set "UUP_DLDR_COPT=--continue -x8 -s8 -j4 -k1M --file-allocation=none --max-tries=10 --retry-wait=10 --timeout=60"
set "UUP_DLDR_IOPT=-i"
set "UUP_DLDR_POPT=-d"
set "UUP_WGET_COPT=-c -nv"
set "UUP_WGET_LOGOPT="
if defined DOWNLOAD_LOGFILE set UUP_WGET_LOGOPT=-a "!DOWNLOAD_LOGFILE!"

rem TEMP artifacts of this run - all carry token URL material and are
rem deleted on every exit path below (T-33-09)
set "UUP_AQ_JOIN=%TEMP%\wou-upg-join-%RANDOM%%RANDOM%.txt"
set "UUP_AQ_JOINSRT=%TEMP%\wou-upg-join-srt-%RANDOM%%RANDOM%.txt"
set "UUP_AQ_ARIA=%TEMP%\wou-upg-aria2-%RANDOM%%RANDOM%.txt"
set "UUP_AQ_ARIA_HTTP=%TEMP%\wou-upg-aria2-http-%RANDOM%%RANDOM%.txt"
set "UUP_AQ_WGET=%TEMP%\wou-upg-wget-%RANDOM%%RANDOM%.txt"
type nul >"!UUP_AQ_JOIN!"
type nul >"!UUP_AQ_JOINSRT!"
type nul >"!UUP_AQ_ARIA!"
type nul >"!UUP_AQ_ARIA_HTTP!"
type nul >"!UUP_AQ_WGET!"

rem Index the url map: one variable per payload name. The names were
rem validated against the frozen grammar by the resolver, so they are safe
rem as variable-name suffixes. An empty url undefines its variable - the
rem join below then fails loudly (fail-closed, never a partial download).
for /F "usebackq tokens=1-2 delims=	" %%n in ("!UUP_AQ_URLMAP!") do set "UUP_URL_%%n=%%o"

set /a UUP_AQ_ARIA_ROWS=0
set /a UUP_AQ_WGET_ROWS=0
for /F "usebackq eol=# tokens=1-3 delims=|" %%a in ("!UUP_AQ_MANIFEST!") do (
  if not "%%c"=="" (
    if not defined UUP_URL_%%a (
      echo ERROR: no URL in the url map for payload %%a - refusing to download a partially mapped set.
      goto :UpgAcquireFail
    )
    call :UpgClassifySize %%c
    if errorlevel 1 (
      echo ERROR: size classification failed for payload %%a.
      goto :UpgAcquireFail
    )
    set "UUP_AQ_PAD=000000000000%%c"
    if "!UUP_CLASS!"=="aria2" (
      rem size-descending big-first ordering: the padded size sorts the
      rem join lexicographically (12-digit zero pad = numeric order for
      rem every byte count up to 999 GB), sort /R reverses it descending.
      rem The big payloads start first, minimizing the token expiry window
      rem (the spike-proven coupled-resolve shape).
      set "UUP_AQ_LINE=!UUP_AQ_PAD:~-12!|!UUP_URL_%%a!|%%a"
      >>"!UUP_AQ_JOIN!" echo !UUP_AQ_LINE!
      set /a UUP_AQ_ARIA_ROWS+=1
    ) else (
      set "UUP_AQ_WLINE=%%a	!UUP_URL_%%a!"
      >>"!UUP_AQ_WGET!" echo !UUP_AQ_WLINE!
      set /a UUP_AQ_WGET_ROWS+=1
    )
  )
)

if !UUP_AQ_ARIA_ROWS! GTR 0 (
  rem Full System32 path: a POSIX-spawned session (the sandbox batteries,
  rem MSYS dev shells) resolves bare sort to GNU sort, which rejects the /R
  rem flag - the same shadowing hazard the find.exe resolution already
  rem froze for the battery idiom (32-01 lesson).
  %SystemRoot%\System32\sort.exe /R "!UUP_AQ_JOIN!" >"!UUP_AQ_JOINSRT!"
  for /F "usebackq tokens=1-3 delims=|" %%p in ("!UUP_AQ_JOINSRT!") do (
    >>"!UUP_AQ_ARIA!" echo %%q
    >>"!UUP_AQ_ARIA!" echo   out=%%r
    rem The DEC-33-15 http twin list: same order, original token scheme
    set "UUP_AQ_HURL=%%q"
    set "UUP_AQ_HURL=!UUP_AQ_HURL:https://=http://!"
    >>"!UUP_AQ_ARIA_HTTP!" echo !UUP_AQ_HURL!
    >>"!UUP_AQ_ARIA_HTTP!" echo   out=%%r
  )
)

if !UUP_AQ_ARIA_ROWS! GTR 0 (
  rem Ensure the aria2 binary: fetch through the EXISTING audited activation
  rem path when absent (T-33-SC). The sandbox battery pre-places a stub and
  rem sets UUP_ARIA2_FETCH=0 to skip the fetch. Still absent = loud failure:
  rem a multi-GiB payload is NEVER downgraded to a non-resumable download.
  if not exist "!UUP_DLDR_PATH!" (
    if not "!UUP_ARIA2_FETCH!"=="0" call ActivateAria2Downloads.cmd
  )
  if not exist "!UUP_DLDR_PATH!" (
    echo ERROR: aria2 is not available and could not be fetched - refusing to download a multi-GiB payload non-resumably ^(no wget downgrade^).
    goto :UpgAcquireFail
  )
  echo Info: Downloading !UUP_AQ_ARIA_ROWS! big upgrade payload^(s^) resume-tuned via aria2...
  call "%UUP_DLDR_PATH%" !UUP_DLDR_COPT! !UUP_DLDR_IOPT! "!UUP_AQ_ARIA!" !UUP_DLDR_POPT! "!UUP_AQ_SPOOL!"
  if errorlevel 1 (
    echo Info: https token URLs failed - falling back to the original http URLs once ^(DEC-33-15, legitimized by the end-to-end sha256 audit^).
    call "%UUP_DLDR_PATH%" !UUP_DLDR_COPT! !UUP_DLDR_IOPT! "!UUP_AQ_ARIA_HTTP!" !UUP_DLDR_POPT! "!UUP_AQ_SPOOL!"
    if errorlevel 1 goto :UpgAcquireFail
  )
)

if !UUP_AQ_WGET_ROWS! GTR 0 (
  if not exist "!UUP_WGET_BIN!" (
    echo ERROR: wget not found for the small payload list: !UUP_WGET_BIN!
    goto :UpgAcquireFail
  )
  echo Info: Downloading !UUP_AQ_WGET_ROWS! small upgrade payload^(s^) with wget -c...
  for /F "usebackq tokens=1-2 delims=	" %%w in ("!UUP_AQ_WGET!") do (
    call "%UUP_WGET_BIN%" !UUP_WGET_COPT! !UUP_WGET_LOGOPT! -O "!UUP_AQ_SPOOL!\%%w" "%%x"
    if errorlevel 1 (
      set "UUP_AQ_WURL=%%x"
      set "UUP_AQ_WURL=!UUP_AQ_WURL:https://=http://!"
      echo Info: https failed for %%w - http fallback ^(DEC-33-15^).
      call "%UUP_WGET_BIN%" !UUP_WGET_COPT! !UUP_WGET_LOGOPT! -O "!UUP_AQ_SPOOL!\%%w" "!UUP_AQ_WURL!"
      if errorlevel 1 goto :UpgAcquireFail
    )
  )
)

echo Info: Running the fail-closed hash gate over the whole spool...
call :UpgHashGate "!UUP_AQ_MANIFEST!" "!UUP_AQ_SPOOL!"
if errorlevel 1 goto :UpgAcquireFail
goto :UpgAcquireEnd

:UpgAcquireFail
set "UUP_AQ_RC=1"
goto :UpgAcquireCleanup

:UpgAcquireEnd
set "UUP_AQ_RC=0"

:UpgAcquireCleanup
rem TEMP-artifact hygiene on EVERY exit path (T-33-09): the url map and the
rem downloader lists carry token URL material and die here, success or not.
if exist "!UUP_AQ_URLMAP!" del "!UUP_AQ_URLMAP!" >nul 2>&1
if exist "!UUP_AQ_JOIN!" del "!UUP_AQ_JOIN!" >nul 2>&1
if exist "!UUP_AQ_JOINSRT!" del "!UUP_AQ_JOINSRT!" >nul 2>&1
if exist "!UUP_AQ_ARIA!" del "!UUP_AQ_ARIA!" >nul 2>&1
if exist "!UUP_AQ_ARIA_HTTP!" del "!UUP_AQ_ARIA_HTTP!" >nul 2>&1
if exist "!UUP_AQ_WGET!" del "!UUP_AQ_WGET!" >nul 2>&1
if "!UUP_AQ_RC!"=="0" (
  echo Info: UUP upgrade payload acquisition complete - spool verified fail-closed, no token material persisted.
) else (
  echo ERROR: UUP upgrade payload acquisition failed - nothing staged, temp artifacts deleted.
)
exit /b !UUP_AQ_RC!

:UpgSectionEntry
rem === engine gate (called by the cmd\DownloadUpdates.cmd Phase-33 region) ===
rem No selection, an invalid selection, or no fu_media=1 row = absolute
rem no-op: zero output, zero side effects (DEC-33-09 statu quo). With one
rem qualifying target: resolve (coupled, one-shot) into the DEC-33-14 spool,
rem then :UpgAcquire.
if not defined TMP_UPG_TARGETS exit /b 0
set "UUP_SEL_FILE=%WOU_UPGRADE_SEL%"
if "!UUP_SEL_FILE!"=="" set "UUP_SEL_FILE=..\sh\os-upgrades.ini"
if not exist "!UUP_SEL_FILE!" exit /b 0
rem Frozen selection grammar, all-or-nothing (byte-identical to the engine
rem reader's validation): any violating line voids the whole selection.
findstr /R /V /C:"^[0-9][0-9]*_[A-Za-z0-9][A-Za-z0-9]*=on$" /C:"^$" "!UUP_SEL_FILE!" >nul 2>&1
if not errorlevel 1 exit /b 0
set "UUP_LANG=%WOU_UPGRADE_LANG%"
if "!UUP_LANG!"=="" set "UUP_LANG=en-us"
set "UUP_SPOOL=%WOU_UPGRADE_SPOOL%"
if "!UUP_SPOOL!"=="" set "UUP_SPOOL=%TEMP%\wou-upgrade-spool"
set "UUP_TABLE=%WOU_UPGRADE_TABLE%"
rem First selected build_arch key whose upgrades.txt row carries fu_media=1
rem (DEC-33-09). The key grammar is <build>_<arch>=on - the delims walk
rem splits on BOTH the underscore and the equals sign, so %%b carries the
rem build part and %%c the bare arch. One full-FU target per medium: the
rem first qualifying key wins; further keys would be consumed by a later
rem run.
set "UUP_TGT_BUILD="
set "UUP_TGT_ARCH="
for /F "usebackq eol=# tokens=1-2 delims=_=" %%b in ("!UUP_SEL_FILE!") do (
  if "!UUP_TGT_BUILD!"=="" (
    rem the internal caller reads UUP_FM_VALUE; the value echo is redirected
    call :UpgReadFuMedia %%b %%c "!UUP_TABLE!" >nul
    if "!UUP_FM_VALUE!"=="1" (
      set "UUP_TGT_BUILD=%%b"
      set "UUP_TGT_ARCH=%%c"
    )
  )
)
if "!UUP_TGT_BUILD!"=="" exit /b 0
echo Info: UUP upgrade payload acquisition target: !UUP_TGT_BUILD!-!UUP_TGT_ARCH! lang !UUP_LANG! ^(fu_media=1^)
if not exist "!UUP_SPOOL!" md "!UUP_SPOOL!"
set "UUP_SE_MANIFEST=!UUP_SPOOL!\manifest.txt"
set "UUP_SE_URLMAP=!UUP_SPOOL!\url-map.tmp"
if exist "!UUP_SE_URLMAP!" del "!UUP_SE_URLMAP!" >nul 2>&1
if not exist "!UUP_SPOOL!\files" md "!UUP_SPOOL!\files"
set "UUP_SE_CSCRIPT=%CSCRIPT_PATH%"
if "!UUP_SE_CSCRIPT!"=="" set "UUP_SE_CSCRIPT=cscript"
"!UUP_SE_CSCRIPT!" //Nologo "!UUP_LIB_DIR!ResolveUpgradePayloads.vbs" !UUP_TGT_BUILD! !UUP_TGT_ARCH! !UUP_LANG! "!UUP_SE_MANIFEST!" /urlmap:"!UUP_SE_URLMAP!"
if errorlevel 1 (
  echo ERROR: UUP payload resolve failed - download aborted, no token material persisted.
  exit /b 1
)
call :UpgAcquire "!UUP_SE_MANIFEST!" "!UUP_SE_URLMAP!" "!UUP_SPOOL!\files"
exit /b !errorlevel!
