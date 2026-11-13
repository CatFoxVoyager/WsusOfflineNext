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
rem   :UpgPinDownloadLists - the downloader list shape pin (live-UAT 33
rem           finding #5, can-fail): validates the WRITTEN aria2/aria2-http/
rem           wget lists BEFORE any downloader runs - every URI line must
rem           match the frozen scheme+charset grammar (no whitespace, no
rem           backslash, no second token riding the line) and every output
rem           path must be an indented "  out=<name>" continuation line.
rem           A glued mega-URI, a bare local path, or a space-separated
rem           second URI fails the pin and the acquisition refuses
rem           fail-closed with NOTHING downloaded. Diagnostics carry line
rem           counts only, never line content (ACQ-01).
rem   :UpgHashGate <manifest> <spool_dir> [hashdeep]
rem           - fail-closed whole-spool audit against a hashdeep expectation
rem             generated from the manifest in TEMP; ANY mismatch = loud
rem             refusal with NOTHING staged (T-33-08, the structural
rem             after-resume re-verify, ACQ-02)
rem   :UpgAcquire <manifest> <url_map> <spool_dir> - orchestrator: budget
rem           line FIRST, size-descending (big-first) split download (aria2
rem           resume-tuned / wget -c), hash gate, TEMP-artifact cleanup on
rem           EVERY exit path (T-33-09: the url map and the downloader lists
rem           carry token URL material and never persist). A pre-download
rem           short-circuit (live-UAT 33 finding #8): a spool whose file
rem           count already equals the manifest rows is audited FIRST and,
rem           if green, skips both download legs - the wget leg cannot
rem           survive a token-service refusal on an already-complete spool.
rem   :UpgAssembleMedia <payload_dir> <media_stage_dir> <manifest>
rem           - the media assembly stage (plan 33-04, ACQ-03): verifies the
rem             vendored wimlib fail-closed against bin\wimlib\SHA256SUMS
rem             (owner vendoring decision 2026-11-11 - see LICENSE-NOTES),
rem             converts the set's component cabs to reference ESDs
rem             (System32 expand.exe + wimlib capture - the converter v0.7.3
rem             sequence), applies metadata ESD index 1 into the stage dir
rem             (media scaffold), exports each edition metadata ESD's index 3
rem             into sources\install.esd with --ref globs (the step in-box
rem             DISM provably cannot do: CONSIGN-DISM-FAILURE, 33-01), exports
rem             the setup image (index 1) as sources\boot.wim with --boot
rem             (the live-UAT 2026-11-11 finding: setup.exe refuses a
rem             boot.wim-less scaffold with 0x80070002), and runs the wimlib
rem             info censuses. NO ELEVATION anywhere: wimlib
rem             is a userspace tool, so the DEC-33-13 targeted-elevation
rem             policy (the RunAs wrapper + owner UAC click the plan built
rem             around in-box DISM) has NO surface on this path - the
rem             owner's 2026-11-11 vendoring decision replaced the DISM
rem             assembly mechanism and with it the elevation prompt. The
rem             policy's fail-closed refusal discipline (nothing staged on
rem             a failed gate, loud error, error counted) is preserved on
rem             EVERY tool-gate failure instead: pin mismatch, failed
rem             conversion/apply/export/census all leave NOTHING staged.
rem   :UpgAuthenticodeGate <media_stage_dir> - refuse-staging signature gate
rem           (DEC-33-06, T-33-11): arch-switched sigcheck over the staged
rem           tree; ANY unsigned row that is not a .mui resource or a
rem           catalog-signed migration DLL (the consigned Microsoft media
rem           convention, 33-01 spike census) = loud refusal, media stays in
rem           the spool. The engine's delete-and-continue loop is
rem           deliberately NOT copied. Binary absent = one runtime fetch
rem           (the Sysinternals task-20 path) then still absent = loud
rem           refusal - a silent skip is forbidden.
rem   :UpgStageMedia <media_stage_dir> <manifest> <cible> <arche> <langue>
rem           - gate-ordered whole-tree staging (T-33-12): the spool hash
rem             gate AND the Authenticode gate must both pass BEFORE the
rem             move; on a revision change the old target moves aside INTO
rem             THE SPOOL first and is deleted ONLY after the new media is
rem             staged and its manifest reads back (delete-after-success).
rem   :UpgCreateMediaDb <cible> <arche> <langue> - the media integrity class
rem           (ACQ-04): recreates client\md\hashes-upgrade-<c>-<a>-<l>.txt
rem           over the staged tree with hashdeep (md5,sha1,sha256), mirroring
rem           the bash create_integrity_database idiom.
rem   :UpgPurgeRevisions <cible> <arche> <langue> <staged_manifest> - revision
rem           churn purge (ACQ-06, DEC-33-08, Pitfall 6): invoked ONLY after
rem           successful staging; archives the current working set under the
rem           staged uuid and removes every sibling spool set for the same
rem           target-lang-arch whose manifest uuid differs (keep-list =
rem           staged uuid). Zero matching siblings = zero deletions. This
rem           stage NEVER touches client\upgrade\ content and never
rem           registers the subtree with the existing cleanup walk.
rem   :UpgSectionEntry - the engine gate: no TMP_UPG_TARGETS selection, no
rem           carrying scope token (w100/w100-x64 whose arch matches the
rem           picked row - the scope gate, live-UAT 33 finding #7b), or no
rem           fu_media=1 row = absolute no-op (statu quo, DEC-33-09); with a
rem           qualifying target: acquire, assemble, stage gate-ordered,
rem           create the media db, purge revisions post-success.
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
echo Subroutines: :UpgReadFuMedia :UpgBudgetLine :UpgClassifySize :UpgHashGate :UpgAcquire :UpgSectionEntry :UpgAssembleMedia :UpgAuthenticodeGate :UpgMoveTree :UpgStageMedia :UpgCreateMediaDb :UpgPurgeRevisions
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

:UpgPinDownloadLists
rem === downloader list shape pin (live-UAT 33 finding #5, can-fail) ===
rem Validates the WRITTEN downloader lists before any downloader runs:
rem   aria2 lists (2 lines per payload): a URI line matching the frozen
rem     scheme+charset grammar - http(s):// followed ONLY by
rem     [A-Za-z0-9._~:/?&=%%+-] (no whitespace, no backslash, no second
rem     token riding the line) - and an indented "  out=<name>" continuation;
rem   wget list (1 line per payload): "name<TAB>URI" with the same grammar.
rem The whole-line counts must equal the classified row counts: any other
rem line (a glued mega-URI fragment, a bare local path, a space-separated
rem second URI) means the input construction is broken and the acquisition
rem refuses BEFORE any download - nothing lands in the spool (fail-closed).
rem Diagnostics carry line counts only, never line content (ACQ-01: the
rem lists carry token URL material).
set /a UUP_PIN_BAD=0
rem Line counting goes through the FULL System32 find.exe path: a
rem POSIX-spawned session (the sandbox batteries, MSYS dev shells) resolves
rem bare find to GNU find, which reads /c as a PATH and scans the drive -
rem the same shadowing hazard frozen for sort.exe in :UpgAcquire (32-01).
if !UUP_AQ_ARIA_ROWS! GTR 0 (
  set /a UUP_PIN_EXPECT=!UUP_AQ_ARIA_ROWS! * 2
  for /F %%C in ('%SystemRoot%\System32\find.exe /c /v "" ^<"!UUP_AQ_ARIA!"') do set /a UUP_PIN_TOTAL=%%C
  for /F %%C in ('findstr /R /C:"^https*://[A-Za-z0-9._~:/?&=%%+-]*$" "!UUP_AQ_ARIA!" ^| %SystemRoot%\System32\find.exe /c /v ""') do set /a UUP_PIN_MATCH=%%C
  if !UUP_PIN_TOTAL! NEQ !UUP_PIN_EXPECT! set /a UUP_PIN_BAD+=1
  if !UUP_PIN_MATCH! NEQ !UUP_AQ_ARIA_ROWS! set /a UUP_PIN_BAD+=1
  for /F %%C in ('%SystemRoot%\System32\find.exe /c /v "" ^<"!UUP_AQ_ARIA_HTTP!"') do set /a UUP_PIN_TOTAL=%%C
  for /F %%C in ('findstr /R /C:"^https*://[A-Za-z0-9._~:/?&=%%+-]*$" "!UUP_AQ_ARIA_HTTP!" ^| %SystemRoot%\System32\find.exe /c /v ""') do set /a UUP_PIN_MATCH=%%C
  if !UUP_PIN_TOTAL! NEQ !UUP_PIN_EXPECT! set /a UUP_PIN_BAD+=1
  if !UUP_PIN_MATCH! NEQ !UUP_AQ_ARIA_ROWS! set /a UUP_PIN_BAD+=1
  for /F %%C in ('findstr /R /C:"^  out=[A-Za-z0-9._-][A-Za-z0-9._-]*$" "!UUP_AQ_ARIA!" ^| %SystemRoot%\System32\find.exe /c /v ""') do set /a UUP_PIN_MATCH=%%C
  if !UUP_PIN_MATCH! NEQ !UUP_AQ_ARIA_ROWS! set /a UUP_PIN_BAD+=1
  for /F %%C in ('findstr /R /C:"^  out=[A-Za-z0-9._-][A-Za-z0-9._-]*$" "!UUP_AQ_ARIA_HTTP!" ^| %SystemRoot%\System32\find.exe /c /v ""') do set /a UUP_PIN_MATCH=%%C
  if !UUP_PIN_MATCH! NEQ !UUP_AQ_ARIA_ROWS! set /a UUP_PIN_BAD+=1
  rem Live-UAT 33 finding #6 extension: an URL-encoded backslash (%5C)
  rem passes the frozen charset (% is a legal URL byte) and is exactly
  rem the wget-normalized shape of a local path glued into a token URL -
  rem the live 403 mega-URL rendered the glue as %5C. Any list line
  rem carrying the sequence refuses the acquisition like a literal
  rem backslash does.
  for /F %%C in ('findstr /L /C:"%%5C" "!UUP_AQ_ARIA!" ^| %SystemRoot%\System32\find.exe /c /v ""') do set /a UUP_PIN_MATCH=%%C
  if !UUP_PIN_MATCH! GTR 0 set /a UUP_PIN_BAD+=1
  for /F %%C in ('findstr /L /C:"%%5C" "!UUP_AQ_ARIA_HTTP!" ^| %SystemRoot%\System32\find.exe /c /v ""') do set /a UUP_PIN_MATCH=%%C
  if !UUP_PIN_MATCH! GTR 0 set /a UUP_PIN_BAD+=1
)
if !UUP_AQ_WGET_ROWS! GTR 0 (
  for /F %%C in ('%SystemRoot%\System32\find.exe /c /v "" ^<"!UUP_AQ_WGET!"') do set /a UUP_PIN_TOTAL=%%C
  for /F %%C in ('findstr /R /C:"^[A-Za-z0-9._-][A-Za-z0-9._-]*	https*://[A-Za-z0-9._~:/?&=%%+-]*$" "!UUP_AQ_WGET!" ^| %SystemRoot%\System32\find.exe /c /v ""') do set /a UUP_PIN_MATCH=%%C
  if !UUP_PIN_TOTAL! NEQ !UUP_AQ_WGET_ROWS! set /a UUP_PIN_BAD+=1
  if !UUP_PIN_MATCH! NEQ !UUP_AQ_WGET_ROWS! set /a UUP_PIN_BAD+=1
  for /F %%C in ('findstr /L /C:"%%5C" "!UUP_AQ_WGET!" ^| %SystemRoot%\System32\find.exe /c /v ""') do set /a UUP_PIN_MATCH=%%C
  if !UUP_PIN_MATCH! GTR 0 set /a UUP_PIN_BAD+=1
)
if !UUP_PIN_BAD! GTR 0 (
  echo ERROR: the downloader list shape pin refused the acquisition - a download list carries a line outside the frozen URI/continuation grammar ^(glued token, bare path, URL-encoded backslash, or second URI on one line^). Nothing was downloaded; the acquisition fails closed.
  exit /b 1
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
rem === live-UAT 33 finding #6 (2026-11-12 17:41 run): form-gated call ===
rem `call` re-parses its arguments and expands %N against THIS script's
rem own call arguments (%1..%3 = the manifest, the url map, the spool
rem files dir). The UUP token URLs are percent-encoded (%2b = +, %2f = /,
rem %3d = =, %3A = :), so the call-shaped wget invocation shredded every
rem token: ...P4=...%2b...%3d%3d reached wget as
rem ...P4=...<url-map-path>b...<files-dir>d<files-dir>d: - the glued
rem mega-URL behind the live 403s. The written list and the url map were
rem proven byte-clean (offline bite + the resolver twins); the bite is
rem the call re-parse. An .exe downloader - the production shape - is
rem invoked DIRECTLY: no re-parse, the URL reaches the binary
rem byte-intact. A batch-shaped battery stub still needs the call form
rem (a batch file invoked without call terminates the caller), so the
rem form switches on the binary extension. The aria2 leg takes the same
rem gate for the one-rule shape; its arguments are library-built paths
rem with no percent material today.
set "UUP_DLDR_CALL=call "
if /i "!UUP_DLDR_PATH:~-4!"==".exe" set "UUP_DLDR_CALL="
set "UUP_AQ_WCALL=call "
if /i "!UUP_WGET_BIN:~-4!"==".exe" set "UUP_AQ_WCALL="
rem Token confinement (ACQ-01, live-UAT 33 finding #5): the UUP section
rem NEVER wires wget's -a log at the persistent DOWNLOAD_LOGFILE - wget -nv
rem echoes full token URLs (P1=..P4= material) into it (the 2026-11-12
rem 15:29 live run leaked the glued token URIs into log\download.log
rem through exactly that channel). The wget console is redirected into the
rem spool scratch per call below; the aria2 console (which echoes the full
rem URI of every attempt) is redirected into the same scratch.

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
rem The downloader run logs live in the SPOOL SCRATCH (the audited files\
rem dir's parent), truncated per acquisition: the LAST run's downloader
rem output stays available for post-mortem there, while log\download.log
rem (a persistent file) never receives token URL material (ACQ-01).
type nul >"!UUP_AQ_SPOOL!\..\aria2-run.log"
type nul >"!UUP_AQ_SPOOL!\..\wget-run.log"

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

rem The downloader list shape pin (live-UAT 33 finding #5, can-fail): the
rem written lists are validated BEFORE any downloader runs - a glued or
rem multi-token line refuses the acquisition fail-closed with nothing
rem downloaded, instead of feeding fake URIs to aria2/wget.
call :UpgPinDownloadLists
if errorlevel 1 goto :UpgAcquireFail

rem === Verify-before-download short-circuit (live-UAT 33 finding #8) ===
rem On an already-complete spool the aria2 leg completes network-free
rem ("Download has already completed", measured live 2026-11-12 20:44)
rem while the wget leg still contacts the token service for every small
rem payload - and the token service refuses post-bulk-download requests
rem (the live 20:44 wget-run.log carries exactly two localized
rem access-denied lines: https try + http fallback on the FIRST small
rem file). The acquisition then dies with nothing wrong on disk and the
rem staging that follows never runs. So: when the working files\ dir
rem already carries exactly the manifest's payload file count, audit it
rem FIRST - a green audit skips both download legs entirely; anything
rem else (missing, extra, or corrupted file) falls through to the legs
rem exactly as before, and the unconditional final hash gate below keeps
rem the fail-closed contract. The count equality is load-bearing, not
rem cosmetic: hashdeep's audit mode reports known-but-absent files in its
rem summary without failing the audit.
set /a UUP_AQ_ROWS=!UUP_AQ_ARIA_ROWS! + !UUP_AQ_WGET_ROWS!
set /a UUP_AQ_HAVE=0
for /F %%c in ('dir /B "!UUP_AQ_SPOOL!" 2^>nul ^| %SystemRoot%\System32\find.exe /c /v ""') do set /a UUP_AQ_HAVE=%%c
if !UUP_AQ_HAVE! EQU !UUP_AQ_ROWS! if !UUP_AQ_ROWS! GTR 0 (
  echo Info: the spool already carries all !UUP_AQ_ROWS! payload file^(s^) - auditing before any download...
  call :UpgHashGate "!UUP_AQ_MANIFEST!" "!UUP_AQ_SPOOL!"
  if not errorlevel 1 (
    echo Info: pre-verified spool accepted - skipping the download legs ^(nothing to download^).
    goto :UpgAcquireEnd
  )
  echo Info: the pre-download audit refused the spool - falling through to the download legs.
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
  >"!UUP_AQ_SPOOL!\..\aria2-run.log" 2>&1 !UUP_DLDR_CALL!"%UUP_DLDR_PATH%" !UUP_DLDR_COPT! !UUP_DLDR_IOPT! "!UUP_AQ_ARIA!" !UUP_DLDR_POPT! "!UUP_AQ_SPOOL!"
  if errorlevel 1 (
    echo Info: https token URLs failed - falling back to the original http URLs once ^(DEC-33-15, legitimized by the end-to-end sha256 audit^).
    >>"!UUP_AQ_SPOOL!\..\aria2-run.log" 2>&1 !UUP_DLDR_CALL!"%UUP_DLDR_PATH%" !UUP_DLDR_COPT! !UUP_DLDR_IOPT! "!UUP_AQ_ARIA_HTTP!" !UUP_DLDR_POPT! "!UUP_AQ_SPOOL!"
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
    rem Form-gated invocation (live-UAT 33 finding #6): the token URL
    rem argument must never ride through a call re-parse - see the gate
    rem block at the option variables above.
    >>"!UUP_AQ_SPOOL!\..\wget-run.log" 2>&1 !UUP_AQ_WCALL!"%UUP_WGET_BIN%" !UUP_WGET_COPT! -O "!UUP_AQ_SPOOL!\%%w" "%%x"
    if errorlevel 1 (
      set "UUP_AQ_WURL=%%x"
      set "UUP_AQ_WURL=!UUP_AQ_WURL:https://=http://!"
      echo Info: https failed for %%w - http fallback ^(DEC-33-15^).
      >>"!UUP_AQ_SPOOL!\..\wget-run.log" 2>&1 !UUP_AQ_WCALL!"%UUP_WGET_BIN%" !UUP_WGET_COPT! -O "!UUP_AQ_SPOOL!\%%w" "!UUP_AQ_WURL!"
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
rem === Scope gate (live-UAT 33 finding #7b) ===
rem The selection twin (sh\os-upgrades.ini) and the upgrade table are
rem GLOBAL - every scope invocation of the engine saw the same fu_media=1
rem row and fired the acquisition, so the 2026-11-12 20:14 GUI run
rem produced one real acquisition (the w100-x64 invocation) plus nine
rem redundant resolves whose download legs the token service refused
rem (403) - ten UpgradeErrors total, nine of them pure waste. The upgrade
rem payloads are a w100-family product: only the invocation whose OWN
rem target token carries the picked row's arch may acquire - the
rem engine-side equivalent of the generator's Win10/11-x64 job gate
rem (job.HasWin11Or10x64). The scope token rides in the subroutine's %1
rem (w100 / w100-x64 / ...), forwarded by the call site after the
rem dispatcher shift; an absent token (battery or manual call) stays an
rem absolute no-op - fail-closed to the statu quo. Non-carrying scopes:
rem zero output, zero side effects (the DEC-33-09 discipline).
set "UUP_SCOPE=%~1"
if "!UUP_SCOPE!"=="" exit /b 0
if /i "!UUP_SCOPE!"=="w100" (set "UUP_SCOPE_ARCH=x86") else if /i "!UUP_SCOPE!"=="w100-x64" (set "UUP_SCOPE_ARCH=x64") else exit /b 0
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
rem First selected build_arch key whose upgrades.txt row carries
rem fu_media=1 (DEC-33-09) AND whose arch matches this invocation's scope
rem arch (the scope gate above) - each scope acquires only what it
rem carries. The key grammar is
rem <build>_<arch>=on - the delims walk splits on BOTH the underscore and
rem the equals sign, so %%b carries the build part and %%c the bare arch.
rem One full-FU target per medium: the first qualifying key wins; further
rem keys would be consumed by a later run.
set "UUP_TGT_BUILD="
set "UUP_TGT_ARCH="
for /F "usebackq eol=# tokens=1-2 delims=_=" %%b in ("!UUP_SEL_FILE!") do (
  if "!UUP_TGT_BUILD!"=="" (
    if /i "%%c"=="!UUP_SCOPE_ARCH!" (
      rem the internal caller reads UUP_FM_VALUE; the value echo is redirected
      call :UpgReadFuMedia %%b %%c "!UUP_TABLE!" >nul
      if "!UUP_FM_VALUE!"=="1" (
        set "UUP_TGT_BUILD=%%b"
        set "UUP_TGT_ARCH=%%c"
      )
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
if errorlevel 1 exit /b 1
rem The verified spool becomes the assembled media (plan 33-04). Gate order
rem is the contract: hash gate + Authenticode gate inside :UpgStageMedia
rem precede the move; the purge runs ONLY after successful staging.
call :UpgAssembleMedia "!UUP_SPOOL!\files" "!UUP_SPOOL!\media-stage" "!UUP_SE_MANIFEST!"
if errorlevel 1 exit /b 1
call :UpgStageMedia "!UUP_SPOOL!\media-stage" "!UUP_SE_MANIFEST!" !UUP_TGT_BUILD! !UUP_TGT_ARCH! !UUP_LANG!
if errorlevel 1 exit /b 1
call :UpgCreateMediaDb !UUP_TGT_BUILD! !UUP_TGT_ARCH! !UUP_LANG!
if errorlevel 1 exit /b 1
call :UpgPurgeRevisions !UUP_TGT_BUILD! !UUP_TGT_ARCH! !UUP_LANG! "!UUP_LIB_DIR!..\client\upgrade\!UUP_TGT_BUILD!-!UUP_TGT_ARCH!\!UUP_LANG!\manifest.txt"
exit /b !errorlevel!

:UpgAssembleMedia
rem === media assembly stage (plan 33-04, ACQ-03) ===
rem %1 = payload dir (the spool's files\ dir), %2 = media stage dir (created;
rem cleaned on failure), %3 = the acquisition manifest.
rem Implements the consigned assembly record (doc\upgrade-media-assembly.md)
rem through the VENDORED wimlib (owner decision 2026-11-11):
rem   1. fail-closed vendored-tool verification against bin\wimlib\SHA256SUMS
rem   2. component-cab -> reference ESD conversion (System32 expand.exe +
rem      wimlib capture, the converter v0.7.3 sequence, exclusions kept)
rem   3. wimlib apply of metadata ESD index 1 (the media scaffold)
rem   4. wimlib export of each edition metadata ESD index 3 into
rem      sources\install.esd with --ref globs (appending indexes)
rem   5. the install.esd census (wimlib info Image Count vs the edition count)
rem   6. wimlib export of metadata ESD index 1 (the setup image) into
rem      sources\boot.wim with --boot, then its own >=1-image census (the
rem      live-UAT 2026-11-11 finding: setup.exe refuses a scaffold without
rem      sources\boot.wim with error 0x80070002)
rem   7. the boot.wim setup flag: wimlib info --image-property FLAGS=9 on
rem      index 1, verified by the Flags census (the live-UAT 2026-11-12
rem      finding: setup.exe refuses a flag-less first image with error
rem      0x8030002F)
rem Every failure: loud ERROR line, stage dir cleaned, NOTHING staged.
set "UUP_AM_PAYLOAD=%~1"
set "UUP_AM_STAGE=%~2"
set "UUP_AM_MANIFEST=%~3"
if "!UUP_AM_PAYLOAD!"=="" (
  echo ERROR: payload directory argument missing for :UpgAssembleMedia.
  exit /b 1
)
if "!UUP_AM_STAGE!"=="" (
  echo ERROR: media stage directory argument missing for :UpgAssembleMedia.
  exit /b 1
)
if "!UUP_AM_MANIFEST!"=="" (
  echo ERROR: manifest argument missing for :UpgAssembleMedia.
  exit /b 1
)
if not exist "!UUP_AM_PAYLOAD!\" (
  echo ERROR: payload directory not found: !UUP_AM_PAYLOAD!
  exit /b 1
)
if not exist "!UUP_AM_MANIFEST!" (
  echo ERROR: manifest not found: !UUP_AM_MANIFEST!
  exit /b 1
)
if exist "!UUP_AM_STAGE!" (
  echo ERROR: media stage directory already exists - refusing to assemble into a dirty stage: !UUP_AM_STAGE!
  exit /b 1
)

rem --- vendored wimlib resolution + fail-closed SHA256 verification ---
rem The override pair (UUP_WIMLIB / UUP_WIMLIB_SHA256SUMS) exists for the
rem sandbox battery; the engine defaults to the vendored pair. Pin keys are
rem the FULL sidecar-relative paths (x64/... vs x86/... share basenames).
set "UUP_AM_WIMLIB=%UUP_WIMLIB%"
set "UUP_AM_SHA256SUMS=%UUP_WIMLIB_SHA256SUMS%"
set "UUP_AM_WIMDLL="
if "!UUP_AM_WIMLIB!"=="" (
  if /i "%PROCESSOR_ARCHITECTURE%"=="AMD64" (
    set "UUP_AM_ARCHDIR=x64"
  ) else (
    if /i "%PROCESSOR_ARCHITEW6432%"=="AMD64" (set "UUP_AM_ARCHDIR=x64") else (set "UUP_AM_ARCHDIR=x86")
  )
  set "UUP_AM_WIMLIB=!UUP_LIB_DIR!..\bin\wimlib\!UUP_AM_ARCHDIR!\wimlib-imagex.exe"
  set "UUP_AM_WIMDLL=!UUP_LIB_DIR!..\bin\wimlib\!UUP_AM_ARCHDIR!\libwim-15.dll"
  set "UUP_AM_SHA256SUMS=!UUP_LIB_DIR!..\bin\wimlib\SHA256SUMS"
  set "UUP_AM_KEY1=!UUP_AM_ARCHDIR!/wimlib-imagex.exe"
  set "UUP_AM_KEY2=!UUP_AM_ARCHDIR!/libwim-15.dll"
) else (
  for %%n in ("!UUP_AM_WIMLIB!") do set "UUP_AM_KEY1=%%~nxn"
  set "UUP_AM_KEY2="
)
if not exist "!UUP_AM_WIMLIB!" (
  echo ERROR: vendored wimlib binary not found: !UUP_AM_WIMLIB!
  echo ERROR: the assembly refuses to run without the verified vendored tool ^(see bin\wimlib\LICENSE-NOTES^).
  exit /b 1
)
if "!UUP_AM_SHA256SUMS!"=="" (
  echo ERROR: no SHA256SUMS sidecar named for the assembly tool - refusing fail-closed.
  exit /b 1
)
if not exist "!UUP_AM_SHA256SUMS!" (
  echo ERROR: SHA256SUMS sidecar not found: !UUP_AM_SHA256SUMS!
  exit /b 1
)
call :UpgVerifySha256Pin "!UUP_AM_WIMLIB!" "!UUP_AM_SHA256SUMS!" "!UUP_AM_KEY1!"
if errorlevel 1 (
  echo ERROR: vendored wimlib binary FAILED the SHA256 pin verification - assembly refused, nothing staged ^(T-33-SC^).
  exit /b 1
)
if not "!UUP_AM_KEY2!"=="" (
  if not exist "!UUP_AM_WIMDLL!" (
    echo ERROR: vendored wimlib library not found beside the binary: !UUP_AM_WIMDLL!
    exit /b 1
  )
  call :UpgVerifySha256Pin "!UUP_AM_WIMDLL!" "!UUP_AM_SHA256SUMS!" "!UUP_AM_KEY2!"
  if errorlevel 1 (
    echo ERROR: vendored wimlib library FAILED the SHA256 pin verification - assembly refused, nothing staged ^(T-33-SC^).
    exit /b 1
  )
)

rem --- edition metadata ESD detection (lang from the manifest meta rows) ---
set "UUP_AM_LANG="
for /F "usebackq eol=# tokens=1-2 delims=|" %%a in ("!UUP_AM_MANIFEST!") do (
  if /i "%%a"=="lang" if not defined UUP_AM_LANG set "UUP_AM_LANG=%%b"
)
if "!UUP_AM_LANG!"=="" (
  echo ERROR: manifest carries no lang meta row: !UUP_AM_MANIFEST!
  exit /b 1
)
set "UUP_AM_META=%TEMP%\wou-upg-asm-meta-%RANDOM%%RANDOM%.txt"
dir /B "!UUP_AM_PAYLOAD!\*_!UUP_AM_LANG!.esd" >"!UUP_AM_META!" 2>nul
%SystemRoot%\System32\sort.exe <"!UUP_AM_META!" >"!UUP_AM_META!.srt"
set /a UUP_AM_EDITIONS=0
set "UUP_AM_FIRST="
for /F "usebackq delims=" %%e in ("!UUP_AM_META!.srt") do (
  rem Edition-name grammar: <word>_<lang>.esd only (a LanguagePack or other
  rem package ESD carries hyphens in the name part and is NOT an edition
  rem metadata ESD - the reference converter selects editions the same way)
  echo %%e| %SystemRoot%\System32\findstr.exe /R /I "^[A-Za-z0-9][A-Za-z0-9]*_!UUP_AM_LANG!.esd$" >nul 2>&1
  if errorlevel 1 (
    echo Info: %%e is not an edition metadata ESD ^(package ESD^) - skipped.
  ) else (
    if not exist "!UUP_AM_PAYLOAD!\%%e" (
      echo ERROR: manifest lang !UUP_AM_LANG! names no matching metadata ESD in the payload dir - refusing.
      goto :UpgAssembleFail
    )
    set /a UUP_AM_EDITIONS+=1
    if not defined UUP_AM_FIRST set "UUP_AM_FIRST=%%e"
  )
)
if !UUP_AM_EDITIONS! EQU 0 (
  echo ERROR: no metadata ESD for lang !UUP_AM_LANG! in the payload dir: !UUP_AM_PAYLOAD!
  goto :UpgAssembleFail
)
echo Info: Assembling media for !UUP_AM_EDITIONS! edition metadata ESD^(s^), scaffold from !UUP_AM_FIRST!

rem --- component-cab -> reference ESD conversion (converter v0.7.3 set) ---
rem The exclusions keep the update/SSU/metadata cabs out of the reference
rem set exactly as the reference implementation does. Converted ESDs live
rem in the spool subtree (outside the shipped tree) and are reused by later
rem runs of the same revision family. The sibling dir is derived from the
rem payload dir's PARENT (%%~dp expansion) - a literal ".." segment in the
rem path would poison wimlib's glob expansion later (measured live).
rem NOTE: the for /R directory argument MUST be percent-expanded
rem (%UUP_AM_PAYLOAD%, not !UUP_AM_PAYLOAD!) - delayed expansion in a
rem for /R dir argument silently iterates NOTHING (measured live).
for %%p in ("%UUP_AM_PAYLOAD%") do set "UUP_AM_PARENT=%%~dpp"
set "UUP_AM_CONVERTED=!UUP_AM_PARENT!converted"
set "UUP_AM_EXTRACT=!UUP_AM_PARENT!convert-extract"
if not exist "!UUP_AM_CONVERTED!\" md "!UUP_AM_CONVERTED!"
set /a UUP_AM_CONVERTED_N=0
for /R "%UUP_AM_PAYLOAD%" %%C in (*.cab) do (
  set "UUP_AM_CABNAME=%%~nxC"
  echo !UUP_AM_CABNAME!| %SystemRoot%\System32\findstr.exe /I /C:"windows1" /C:"-kb" /C:"ssu-" /C:"desktopdeployment" /C:"aggregatedmetadata" >nul 2>&1
  if errorlevel 1 (
    if not exist "!UUP_AM_CONVERTED!\%%~nC.esd" (
      echo Info: CAB -^> ESD: %%~nC
      if exist "!UUP_AM_EXTRACT!\" rd /s /q "!UUP_AM_EXTRACT!" >nul 2>&1
      md "!UUP_AM_EXTRACT!"
      %SystemRoot%\System32\expand.exe -F:* "%%~fC" "!UUP_AM_EXTRACT!" >nul 2>&1
      if errorlevel 1 (
        echo ERROR: cab extraction failed for %%~nxC - assembly refused.
        goto :UpgAssembleFail
      )
      rem The call form is REQUIRED: the battery stub is batch-shaped, and a
      rem batch-shaped binary invoked without call terminates the caller with
      rem its own exit code (the 33-03 lesson replayed).
      call "!UUP_AM_WIMLIB!" capture "!UUP_AM_EXTRACT!" "!UUP_AM_CONVERTED!\%%~nC.esd" --no-acls --norpfix "Edition Package" "Edition Package" >nul 2>&1
      if errorlevel 1 (
        echo ERROR: wimlib capture failed for %%~nxC - assembly refused.
        goto :UpgAssembleFail
      )
      rd /s /q "!UUP_AM_EXTRACT!" >nul 2>&1
      set /a UUP_AM_CONVERTED_N+=1
    )
  )
)
if exist "!UUP_AM_EXTRACT!\" rd /s /q "!UUP_AM_EXTRACT!" >nul 2>&1
echo Info: Converted !UUP_AM_CONVERTED_N! component cab^(s^) to reference ESD^(s^) ^(reused from previous runs when present^).

rem --- scaffold apply: metadata ESD index 1 into the stage dir ---
echo Info: Applying the media scaffold from index 1 of !UUP_AM_FIRST! ...
if not exist "!UUP_AM_STAGE!\" md "!UUP_AM_STAGE!"
rem call form: see the capture note (batch-shaped stubs terminate the caller otherwise)
call "!UUP_AM_WIMLIB!" apply "!UUP_AM_PAYLOAD!\!UUP_AM_FIRST!" 1 "!UUP_AM_STAGE!" --no-acls --no-attributes >nul
if errorlevel 1 (
  echo ERROR: scaffold apply failed - assembly refused, nothing staged.
  goto :UpgAssembleFail
)

rem --- install.esd export: one per edition metadata ESD, appended ---
rem --ref globs resolve the external blob resources that killed the DISM
rem export (CONSIGN-DISM-FAILURE); wimlib expands the globs itself.
set "UUP_AM_INSTALL=!UUP_AM_STAGE!\sources\install.esd"
if not exist "!UUP_AM_STAGE!\sources\" (
  echo ERROR: the scaffold produced no sources\ directory - assembly refused.
  goto :UpgAssembleFail
)
for /F "usebackq delims=" %%e in ("!UUP_AM_META!.srt") do (
  set "UUP_AM_EDITION_ID="
  rem The extra quote pair defeats the cmd /c leading-quote stripping (a
  rem command line that both starts with a quote and carries more quotes is
  rem otherwise mangled)
  for /F "usebackq delims=" %%L in (`""!UUP_AM_WIMLIB!" info "!UUP_AM_PAYLOAD!\%%e" 3 ^| %SystemRoot%\System32\findstr.exe /B /C:"Edition ID:""`) do (
    for /F "tokens=3 delims=: " %%z in ("%%L") do set "UUP_AM_EDITION_ID=%%z"
  )
  if "!UUP_AM_EDITION_ID!"=="" (
    echo ERROR: no Edition ID reported for %%e - assembly refused.
    goto :UpgAssembleFail
  )
  echo Info: Exporting edition !UUP_AM_EDITION_ID! to sources\install.esd ...
  rem --ref IS the glob form on the Windows wimlib build (its usage line
  rem documents --ref="GLOB"): the patterns are expanded by wimlib itself -
  rem the shell never expands them on this side. The glob must NOT carry
  rem [eE] character classes (wimlib's glob rejects them - measured live);
  rem plain *.esd covers the .ESD payload files because Windows globbing is
  rem case-insensitive (the converter's classes exist for Linux shells).
  call "!UUP_AM_WIMLIB!" export "!UUP_AM_PAYLOAD!\%%e" 3 "!UUP_AM_INSTALL!" "Windows 11 !UUP_AM_EDITION_ID!" --solid --ref="!UUP_AM_PAYLOAD!\*.esd" --ref="!UUP_AM_CONVERTED!\*.esd" >nul
  if errorlevel 1 (
    echo ERROR: install.esd export failed for %%e - assembly refused, nothing staged.
    goto :UpgAssembleFail
  )
)

rem --- the census: image count must equal the exported edition count ---
set "UUP_AM_IMAGECOUNT="
for /F "usebackq delims=" %%L in (`""!UUP_AM_WIMLIB!" info "!UUP_AM_INSTALL!" ^| %SystemRoot%\System32\findstr.exe /B /C:"Image Count:""`) do (
  for /F "tokens=3 delims=: " %%z in ("%%L") do set "UUP_AM_IMAGECOUNT=%%z"
)
if "!UUP_AM_IMAGECOUNT!"=="" (
  echo ERROR: the census could not read the Image Count of !UUP_AM_INSTALL! - assembly refused.
  goto :UpgAssembleFail
)
if !UUP_AM_IMAGECOUNT! NEQ !UUP_AM_EDITIONS! (
  echo ERROR: census mismatch - install.esd carries !UUP_AM_IMAGECOUNT! image^(s^), expected !UUP_AM_EDITIONS! - assembly refused.
  goto :UpgAssembleFail
)

rem --- boot.wim export: the setup image (index 1) becomes sources\boot.wim ---
rem The live-UAT finding (2026-11-11): setup.exe refuses a scaffold that
rem carries no sources\boot.wim (0x80070002 "unable to locate required
rem installation file [boot.wim]") - real Microsoft media carries the setup
rem image exactly there. The scaffold apply already proved index 1's
rem resources are internal to the metadata ESD, so unlike the install.esd
rem export no --ref globs are needed. --boot marks the exported image
rem bootable in the new WIM (wimlib export usage line: [--boot]) - the
rem convention real boot.wim files carry.
echo Info: Exporting the setup boot image to sources\boot.wim ...
call "!UUP_AM_WIMLIB!" export "!UUP_AM_PAYLOAD!\!UUP_AM_FIRST!" 1 "!UUP_AM_STAGE!\sources\boot.wim" "Windows Setup Media" --boot >nul
if errorlevel 1 (
  echo ERROR: boot.wim export failed - assembly refused, nothing staged.
  goto :UpgAssembleFail
)
set "UUP_AM_BOOTCOUNT="
for /F "usebackq delims=" %%L in (`""!UUP_AM_WIMLIB!" info "!UUP_AM_STAGE!\sources\boot.wim" ^| %SystemRoot%\System32\findstr.exe /B /C:"Image Count:""`) do (
  for /F "tokens=3 delims=: " %%z in ("%%L") do set "UUP_AM_BOOTCOUNT=%%z"
)
if "!UUP_AM_BOOTCOUNT!"=="" (
  echo ERROR: the census could not read the Image Count of sources\boot.wim - assembly refused.
  goto :UpgAssembleFail
)
if !UUP_AM_BOOTCOUNT! LSS 1 (
  echo ERROR: boot.wim census - !UUP_AM_BOOTCOUNT! image^(s^), expected at least 1 - assembly refused.
  goto :UpgAssembleFail
)

rem --- boot.wim setup flag: FLAGS=9 on the first image ---
rem The live-UAT finding (2026-11-12): setup.exe refuses a boot.wim whose
rem FIRST image carries no FLAGS metadata with 0x8030002F ("reconfigure
rem your boot.wim file to use the flag 9 settings for the first image").
rem The flag lives in the image metadata, not the file layout, so export
rem --boot alone cannot carry it; the vendored wimlib (1.14.5) sets image
rem properties through info --image-property (measured live on the staged
rem 26200 media: "Setting the FLAGS property of image 1 to ""9""." and the
rem plain info census then reports a "Flags: 9" line where the flag-less
rem image reported none). Fail-closed: a flag-set refusal and any census
rem value other than 9 both refuse the assembly, nothing staged.
echo Info: Setting the setup flag 9 on the boot.wim first image ...
call "!UUP_AM_WIMLIB!" info "!UUP_AM_STAGE!\sources\boot.wim" 1 --image-property FLAGS=9 >nul
if errorlevel 1 (
  echo ERROR: setting the boot.wim setup flag 9 failed - assembly refused, nothing staged.
  goto :UpgAssembleFail
)
set "UUP_AM_BOOTFLAG="
for /F "usebackq delims=" %%L in (`""!UUP_AM_WIMLIB!" info "!UUP_AM_STAGE!\sources\boot.wim" ^| %SystemRoot%\System32\findstr.exe /B /C:"Flags:""`) do (
  for /F "tokens=2 delims=: " %%z in ("%%L") do set "UUP_AM_BOOTFLAG=%%z"
)
if "!UUP_AM_BOOTFLAG!"=="" (
  echo ERROR: the census could not read the Flags of sources\boot.wim - assembly refused.
  goto :UpgAssembleFail
)
if not "!UUP_AM_BOOTFLAG!"=="9" (
  echo ERROR: boot.wim census - the first image reports Flags !UUP_AM_BOOTFLAG!, expected 9 ^(0x8030002F^) - assembly refused.
  goto :UpgAssembleFail
)
del "!UUP_AM_META!" >nul 2>&1
del "!UUP_AM_META!.srt" >nul 2>&1
echo Info: Media assembly complete - !UUP_AM_IMAGECOUNT! edition image^(s^) in sources\install.esd + sources\boot.wim with !UUP_AM_BOOTCOUNT! image^(s^) flag !UUP_AM_BOOTFLAG!, census green.
exit /b 0

:UpgAssembleFail
if exist "!UUP_AM_STAGE!\" rd /s /q "!UUP_AM_STAGE!" >nul 2>&1
if exist "!UUP_AM_META!" del "!UUP_AM_META!" >nul 2>&1
if exist "!UUP_AM_META!.srt" del "!UUP_AM_META!.srt" >nul 2>&1
exit /b 1

:UpgVerifySha256Pin
rem %1 = file to verify, %2 = SHA256SUMS sidecar (sha256sum -c format:
rem "<hex>[ *]<relative/path>"), %3 = the pin key (the sidecar-relative path
rem of the file - basenames collide across x64/ and x86/). Computes certutil
rem SHA256 of %1 and compares case-insensitively against the sidecar line
rem naming the same key. Exit 0 = pin verified; exit 1 = missing line,
rem missing file, or mismatch.
set "UUP_VSP_FILE=%~1"
set "UUP_VSP_SIDECAR=%~2"
set "UUP_VSP_KEY=%~3"
set "UUP_VSP_EXPECTED="
for /F "usebackq tokens=1,2 delims= " %%a in ("!UUP_VSP_SIDECAR!") do (
  for /F "delims=*" %%n in ("%%b") do (
    if /i "%%n"=="!UUP_VSP_KEY!" set "UUP_VSP_EXPECTED=%%a"
  )
)
if "!UUP_VSP_EXPECTED!"=="" (
  echo ERROR: SHA256SUMS sidecar carries no pin for !UUP_VSP_NAME!: !UUP_VSP_SIDECAR!
  exit /b 1
)
set "UUP_VSP_ACTUAL="
for /F "skip=1 delims=" %%h in ('certutil -hashfile "!UUP_VSP_FILE!" SHA256 2^>nul') do (
  if not defined UUP_VSP_ACTUAL set "UUP_VSP_ACTUAL=%%h"
)
set "UUP_VSP_ACTUAL=!UUP_VSP_ACTUAL: =!"
if "!UUP_VSP_ACTUAL!"=="" (
  echo ERROR: certutil produced no hash for !UUP_VSP_FILE!
  exit /b 1
)
if /i not "!UUP_VSP_ACTUAL!"=="!UUP_VSP_EXPECTED!" (
  echo ERROR: SHA256 pin MISMATCH for !UUP_VSP_NAME!: expected !UUP_VSP_EXPECTED!, got !UUP_VSP_ACTUAL!
  exit /b 1
)
exit /b 0

:UpgAuthenticodeGate
rem === refuse-staging signature gate (DEC-33-06, T-33-11) ===
rem %1 = the assembled media stage dir. Runs the arch-switched sigcheck over
rem the staged tree (-s, CSV) and classifies every row: rows carrying the
rem quoted "Signed" marker pass; unsigned rows are allowed ONLY for .mui
rem resources and replacementmanifests migration DLLs (the consigned
rem Microsoft media convention - the 33-01 spike census measured exactly
rem those two classes on the real scaffold); ANY other unsigned row refuses
rem staging: loud ERROR, exit 1, NOTHING moved (the caller keeps the media
rem in the spool). Binary absent = one runtime fetch through the existing
rem Sysinternals path (task-20 precedent), then still absent = loud refusal.
set "UUP_AG_STAGE=%~1"
set "UUP_AG_SIGCHK=%UUP_SIGCHK_PATH%"
if "!UUP_AG_STAGE!"=="" (
  echo ERROR: media stage directory argument missing for :UpgAuthenticodeGate.
  exit /b 1
)
if not exist "!UUP_AG_STAGE!\" (
  echo ERROR: media stage directory not found: !UUP_AG_STAGE!
  exit /b 1
)
if not exist "!UUP_AG_STAGE!\sources\" (
  echo ERROR: media stage carries no sources\ directory: !UUP_AG_STAGE!
  exit /b 1
)
if "!UUP_AG_SIGCHK!"=="" (
  if /i "%PROCESSOR_ARCHITECTURE%"=="AMD64" (set "UUP_AG_SIGCHK=!UUP_LIB_DIR!..\bin\sigcheck64.exe") else (
    if /i "%PROCESSOR_ARCHITEW6432%"=="AMD64" (set "UUP_AG_SIGCHK=!UUP_LIB_DIR!..\bin\sigcheck64.exe") else (set "UUP_AG_SIGCHK=!UUP_LIB_DIR!..\bin\sigcheck.exe")
  )
)
if not exist "!UUP_AG_SIGCHK!" (
  rem Runtime fetch through the EXISTING Sysinternals path - never a silent
  rem skip. Wget is vendored; unzip is vendored; both are anchored at the
  rem library dir so the caller's cwd cannot shadow them.
  echo Info: sigcheck not found - fetching through the existing Sysinternals runtime path...
  "!UUP_LIB_DIR!..\bin\wget.exe" -nv -O "!UUP_LIB_DIR!..\bin\Sigcheck.zip" https://download.sysinternals.com/files/Sigcheck.zip >nul 2>&1
  if errorlevel 1 (
    echo ERROR: the Sysinternals Sigcheck fetch failed - the Authenticode gate refuses fail-closed ^(no silent skip^).
    exit /b 1
  )
  pushd "!UUP_LIB_DIR!..\bin"
  unzip.exe -u -o Sigcheck.zip -x Eula.txt >nul 2>&1
  popd
)
if not exist "!UUP_AG_SIGCHK!" (
  echo ERROR: sigcheck is not available and the fetch did not produce it - the Authenticode gate refuses fail-closed.
  exit /b 1
)
set "UUP_AG_CSV=%TEMP%\wou-upg-sigcheck-%RANDOM%%RANDOM%.csv"
rem call form: the battery stub is batch-shaped (see the capture note)
call "!UUP_AG_SIGCHK!" -accepteula -q -c -nobanner -utf8 -e -s "!UUP_AG_STAGE!" >"!UUP_AG_CSV!" 2>nul
set /a UUP_AG_ROWS=0
set /a UUP_AG_SIGNED=0
set /a UUP_AG_ALLOWED=0
set /a UUP_AG_BAD=0
for /F "skip=1 usebackq tokens=1,* delims=," %%a in ("!UUP_AG_CSV!") do (
  set /a UUP_AG_ROWS+=1
  echo %%b| %SystemRoot%\System32\findstr.exe /C:"\"Signed\"" >nul 2>&1
  if not errorlevel 1 (
    set /a UUP_AG_SIGNED+=1
  ) else (
    set UUP_AG_ROWPATH=%%a
    rem Strip the CSV quoting so the extension anchor can bind (delayed
    rem substitution, not a path modifier - %%~q is not a defined modifier
    rem and mangles the path)
    set UUP_AG_ROWPATH=!UUP_AG_ROWPATH:"=!
    set "UUP_AG_ALLOWED_ROW=0"
    echo !UUP_AG_ROWPATH!| %SystemRoot%\System32\findstr.exe /I /E /C:".mui" >nul 2>&1
    if not errorlevel 1 set "UUP_AG_ALLOWED_ROW=1"
    rem The doubled backslashes are REQUIRED: a single trailing backslash
    rem before the closing quote escapes the quote at the C-runtime argv
    rem layer and findstr receives a mangled literal (measured live on the
    rem real scaffold's replacementmanifests migration DLL)
    echo !UUP_AG_ROWPATH!| %SystemRoot%\System32\findstr.exe /I /C:"\\replacementmanifests\\" >nul 2>&1
    if not errorlevel 1 set "UUP_AG_ALLOWED_ROW=1"
    if "!UUP_AG_ALLOWED_ROW!"=="1" (
      set /a UUP_AG_ALLOWED+=1
    ) else (
      set /a UUP_AG_BAD+=1
      echo ERROR: UNSIGNED executable in the staged media - staging refused: !UUP_AG_ROWPATH!
    )
  )
)
del "!UUP_AG_CSV!" >nul 2>&1
if !UUP_AG_ROWS! EQU 0 (
  echo ERROR: the Authenticode scan examined zero rows - the gate refuses fail-closed ^(an empty scan verifies nothing^).
  exit /b 1
)
if !UUP_AG_BAD! GTR 0 (
  echo ERROR: Authenticode gate FAILED - !UUP_AG_BAD! unsigned row^(s^) outside the consigned convention. Media stays in the spool, nothing staged.
  exit /b 1
)
echo Info: Authenticode gate passed - !UUP_AG_SIGNED! signed row^(s^), !UUP_AG_ALLOWED! allowed convention row^(s^) ^(.mui resources / catalog-signed migration DLLs^), !UUP_AG_ROWS! rows scanned.
exit /b 0

:UpgMoveTree
rem === cross-volume whole-tree move (live-UAT 33 finding #7a) ===
rem %1 = source dir, %2 = destination dir (must NOT exist; the callers
rem clear the way first). cmd's internal `move` cannot move a DIRECTORY
rem across volumes - measured 2026-11-12: same-volume dir move rc=0,
rem cross-volume rc=1 "Access denied", cross-volume FILE move rc=0 - and
rem the engine geometry is cross-volume by construction: the spool lives
rem in %TEMP% (C: on the live deployment) while the client tree lives
rem beside this script (D:). The staging refresh never fired there - the
rem sandbox batteries place spool, stage and client root under one %TEMP%
rem volume, so the defect was invisible to every gate until the live run.
rem robocopy (System32, no new dependency) implements the move as
rem copy+delete with preserved file and directory timestamps
rem (/COPY:DAT /DCOPY:DAT - the staged scaffold must keep its media
rem timestamps), bounded retries, and the robocopy exit convention:
rem 0-7 are success classes, >= 8 is a failure. A mid-copy failure
rem leaves the source partially consumed (each file is deleted only
rem after its copy) - the callers own the rollback, through this same
rem helper for the cross-volume direction. The bash twin needs no
rem counterpart: `mv` handles cross-device moves natively.
set "UUP_MT_SRC=%~1"
set "UUP_MT_DST=%~2"
if "!UUP_MT_SRC!"=="" (
  echo ERROR: source directory argument missing for :UpgMoveTree.
  exit /b 1
)
if "!UUP_MT_DST!"=="" (
  echo ERROR: destination directory argument missing for :UpgMoveTree.
  exit /b 1
)
if not exist "!UUP_MT_SRC!\" (
  echo ERROR: source directory not found: !UUP_MT_SRC!
  exit /b 1
)
if exist "!UUP_MT_DST!\" (
  echo ERROR: destination directory already exists - refusing to merge: !UUP_MT_DST!
  exit /b 1
)
"%SystemRoot%\System32\robocopy.exe" "!UUP_MT_SRC!" "!UUP_MT_DST!" /E /MOVE /COPY:DAT /DCOPY:DAT /R:1 /W:1 /NFL /NDL /NP /NJH >nul 2>&1
set "UUP_MT_RC=!errorlevel!"
if !UUP_MT_RC! GEQ 8 (
  echo ERROR: the whole-tree move failed ^(robocopy exit class !UUP_MT_RC!^): "!UUP_MT_SRC!" -^> "!UUP_MT_DST!"
  exit /b 1
)
exit /b 0

:UpgStageMedia
rem === gate-ordered whole-tree staging (T-33-12) ===
rem %1 = assembled media stage dir, %2 = the spool acquisition manifest,
rem %3..%5 = target cible/arche/langue. Gate order is the contract: the
rem spool hash gate runs FIRST, then the Authenticode gate, and only then
rem the move into client\upgrade\<cible>-<arche>\<langue>\. On a revision
rem change (existing target dir whose manifest uuid differs - or an
rem unparseable existing manifest) the old target moves aside INTO THE
rem SPOOL first and the aside is deleted ONLY after the new media is staged
rem and its manifest reads back with the staged uuid (delete-after-success).
rem A gate failure stages nothing.
set "UUP_SM_STAGE=%~1"
set "UUP_SM_MANIFEST=%~2"
set "UUP_SM_CIBLE=%~3"
set "UUP_SM_ARCHE=%~4"
set "UUP_SM_LANGUE=%~5"
if "!UUP_SM_STAGE!"=="" (
  echo ERROR: media stage directory argument missing for :UpgStageMedia.
  exit /b 1
)
if "!UUP_SM_MANIFEST!"=="" (
  echo ERROR: manifest argument missing for :UpgStageMedia.
  exit /b 1
)
if "!UUP_SM_CIBLE!"=="" exit /b 2
if "!UUP_SM_ARCHE!"=="" exit /b 2
if "!UUP_SM_LANGUE!"=="" exit /b 2
if not exist "!UUP_SM_STAGE!\" (
  echo ERROR: media stage directory not found: !UUP_SM_STAGE!
  exit /b 1
)
if not exist "!UUP_SM_MANIFEST!" (
  echo ERROR: manifest not found: !UUP_SM_MANIFEST!
  exit /b 1
)
rem Spool root = the manifest's directory (the DEC-33-14 working layout:
rem <spool>\manifest.txt + <spool>\files\)
set "UUP_SM_SPOOL=%~dp2"
set "UUP_SM_SPOOL=!UUP_SM_SPOOL:~0,-1!"
rem The client tree root: the sandbox battery pins UUP_CLIENT_ROOT; the
rem engine default is the library's sibling client tree.
set "UUP_SM_CLIENT=%UUP_CLIENT_ROOT%"
if "!UUP_SM_CLIENT!"=="" set "UUP_SM_CLIENT=!UUP_LIB_DIR!..\client"
set "UUP_SM_TARGET=!UUP_SM_CLIENT!\upgrade\!UUP_SM_CIBLE!-!UUP_SM_ARCHE!\!UUP_SM_LANGUE!"

rem Gate 1: the whole-spool sha256 audit (33-03) - refusal leaves the tree
rem untouched, the media in the stage dir
echo Info: Staging gate 1/2 - the fail-closed spool hash audit...
call :UpgHashGate "!UUP_SM_MANIFEST!" "!UUP_SM_SPOOL!\files"
if errorlevel 1 (
  echo ERROR: the spool hash gate refused staging - NOTHING moved ^(T-33-12 gate order^).
  exit /b 1
)
rem Gate 2: Authenticode refuse-staging over the assembled tree
echo Info: Staging gate 2/2 - the Authenticode refuse-staging scan...
call :UpgAuthenticodeGate "!UUP_SM_STAGE!"
if errorlevel 1 (
  echo ERROR: the Authenticode gate refused staging - NOTHING moved ^(T-33-12 gate order^).
  exit /b 1
)
rem Staged uuid from the spool manifest meta rows
set "UUP_SM_UUID="
for /F "usebackq eol=# tokens=1-2 delims=|" %%a in ("!UUP_SM_MANIFEST!") do (
  if /i "%%a"=="uuid" if not defined UUP_SM_UUID set "UUP_SM_UUID=%%b"
)
if "!UUP_SM_UUID!"=="" (
  echo ERROR: the spool manifest carries no uuid meta row - staging refused.
  exit /b 1
)
rem Revision replacement: move an existing target aside INTO THE SPOOL
set "UUP_SM_ASIDE="
if exist "!UUP_SM_TARGET!\" (
  set "UUP_SM_ASIDE=!UUP_SM_SPOOL!\replaced-!UUP_SM_UUID!-%RANDOM%"
  echo Info: Existing media found - moving the old tree aside ^(delete-after-success^): !UUP_SM_ASIDE!
  call :UpgMoveTree "!UUP_SM_TARGET!" "!UUP_SM_ASIDE!"
  if errorlevel 1 (
    echo ERROR: could not move the existing media aside - staging refused, the old revision stays untouched.
    set "UUP_SM_ASIDE="
    exit /b 1
  )
)
rem The move: the whole assembled tree lands in the target in one movement
rem (cross-volume safe - the spool and the client tree typically sit on
rem different volumes, where cmd's internal move refuses directories)
if not exist "!UUP_SM_CLIENT!\upgrade\!UUP_SM_CIBLE!-!UUP_SM_ARCHE!\" md "!UUP_SM_CLIENT!\upgrade\!UUP_SM_CIBLE!-!UUP_SM_ARCHE!"
call :UpgMoveTree "!UUP_SM_STAGE!" "!UUP_SM_TARGET!"
if errorlevel 1 (
  echo ERROR: the media move failed - staging refused.
  if defined UUP_SM_ASIDE (
    rem A failed robocopy move may leave a PARTIAL target behind - clear
    rem it before the old revision can move back in
    rd /s /q "!UUP_SM_TARGET!" >nul 2>&1
    call :UpgMoveTree "!UUP_SM_ASIDE!" "!UUP_SM_TARGET!"
    if errorlevel 1 echo ERROR: the old revision could not be restored from the aside - recover it manually from: !UUP_SM_ASIDE!
  )
  exit /b 1
)
rem The acquisition manifest lands beside the media
copy /y "!UUP_SM_MANIFEST!" "!UUP_SM_TARGET!\manifest.txt" >nul
if errorlevel 1 (
  echo ERROR: staging the manifest beside the media failed.
  if defined UUP_SM_ASIDE (
    rd /s /q "!UUP_SM_TARGET!" >nul 2>&1
    call :UpgMoveTree "!UUP_SM_ASIDE!" "!UUP_SM_TARGET!"
    if errorlevel 1 echo ERROR: the old revision could not be restored from the aside - recover it manually from: !UUP_SM_ASIDE!
  )
  exit /b 1
)
rem Delete-after-success: the new media must be staged AND its manifest
rem must read back with the staged uuid before the old revision dies
set "UUP_SM_READBACK="
for /F "usebackq eol=# tokens=1-2 delims=|" %%a in ("!UUP_SM_TARGET!\manifest.txt") do (
  if /i "%%a"=="uuid" if not defined UUP_SM_READBACK set "UUP_SM_READBACK=%%b"
)
if not "!UUP_SM_READBACK!"=="!UUP_SM_UUID!" (
  echo ERROR: the staged manifest does not read back with uuid !UUP_SM_UUID! - the old revision is kept for recovery.
  exit /b 1
)
if defined UUP_SM_ASIDE (
  rd /s /q "!UUP_SM_ASIDE!" >nul 2>&1
  echo Info: Old revision media deleted after successful staging ^(delete-after-success^).
)
echo Info: Media staged - client\upgrade\!UUP_SM_CIBLE!-!UUP_SM_ARCHE!\!UUP_SM_LANGUE! \(uuid !UUP_SM_UUID!\).
exit /b 0

:UpgCreateMediaDb
rem === media integrity class (ACQ-04) ===
rem %1..%3 = cible/arche/langue. Recreates client\md\hashes-upgrade-<..>.txt
rem over the STAGED tree (create pattern, mirroring the bash
rem create_integrity_database idiom: rm -f the existing db, hashdeep -c
rem md5,sha1,sha256 -b -r over the directory).
set "UUP_CD_CIBLE=%~1"
set "UUP_CD_ARCHE=%~2"
set "UUP_CD_LANGUE=%~3"
if "!UUP_CD_CIBLE!"=="" exit /b 2
if "!UUP_CD_ARCHE!"=="" exit /b 2
if "!UUP_CD_LANGUE!"=="" exit /b 2
set "UUP_CD_CLIENT=%UUP_CLIENT_ROOT%"
if "!UUP_CD_CLIENT!"=="" set "UUP_CD_CLIENT=!UUP_LIB_DIR!..\client"
set "UUP_CD_DIR=!UUP_CD_CLIENT!\upgrade\!UUP_CD_CIBLE!-!UUP_CD_ARCHE!\!UUP_CD_LANGUE!"
set "UUP_CD_DB=!UUP_CD_CLIENT!\md\hashes-upgrade-!UUP_CD_CIBLE!-!UUP_CD_ARCHE!-!UUP_CD_LANGUE!.txt"
if not exist "!UUP_CD_DIR!\" (
  echo ERROR: staged media directory not found: !UUP_CD_DIR!
  exit /b 1
)
if not exist "!UUP_CD_CLIENT!\md\" md "!UUP_CD_CLIENT!\md"
if exist "!UUP_CD_DB!" del "!UUP_CD_DB!" >nul 2>&1
if /i "%PROCESSOR_ARCHITECTURE%"=="AMD64" (set "UUP_CD_HASHDEEP=!UUP_LIB_DIR!..\client\bin\hashdeep64.exe") else (
  if /i "%PROCESSOR_ARCHITEW6432%"=="AMD64" (set "UUP_CD_HASHDEEP=!UUP_LIB_DIR!..\client\bin\hashdeep64.exe") else (set "UUP_CD_HASHDEEP=!UUP_LIB_DIR!..\client\bin\hashdeep.exe")
)
if not exist "!UUP_CD_HASHDEEP!" (
  echo ERROR: hashdeep not found: !UUP_CD_HASHDEEP!
  exit /b 1
)
echo Info: Creating the media integrity class - client\md\hashes-upgrade-!UUP_CD_CIBLE!-!UUP_CD_ARCHE!-!UUP_CD_LANGUE!.txt
"!UUP_CD_HASHDEEP!" -c md5,sha1,sha256 -b -r "!UUP_CD_DIR!" >"!UUP_CD_DB!"
if errorlevel 1 (
  echo ERROR: hashdeep failed creating the media integrity class.
  if exist "!UUP_CD_DB!" del "!UUP_CD_DB!" >nul 2>&1
  exit /b 1
)
findstr /B /C:"%%%%" "!UUP_CD_DB!" >nul 2>&1
if errorlevel 1 (
  echo ERROR: the media integrity class carries no hashdeep header - refusing.
  del "!UUP_CD_DB!" >nul 2>&1
  exit /b 1
)
exit /b 0

:UpgPurgeRevisions
rem === revision churn purge (ACQ-06, DEC-33-08, Pitfall 6) ===
rem %1..%3 = cible/arche/langue, %4 = the STAGED manifest (the keep-list
rem source). Invoked ONLY after successful staging. Archives the current
rem working set under the staged uuid, then removes every sibling spool set
rem for the same target-lang-arch whose manifest uuid differs. Zero matching
rem siblings = zero deletions. NEVER touches client\upgrade\ content; never
rem registers the subtree with the existing cleanup walk.
set "UUP_PR_CIBLE=%~1"
set "UUP_PR_ARCHE=%~2"
set "UUP_PR_LANGUE=%~3"
set "UUP_PR_MANIFEST=%~4"
if "!UUP_PR_CIBLE!"=="" exit /b 2
if "!UUP_PR_ARCHE!"=="" exit /b 2
if "!UUP_PR_LANGUE!"=="" exit /b 2
if "!UUP_PR_MANIFEST!"=="" (
  echo ERROR: staged manifest argument missing for :UpgPurgeRevisions.
  exit /b 1
)
if not exist "!UUP_PR_MANIFEST!" (
  echo ERROR: staged manifest not found - the purge refuses without proof of successful staging: !UUP_PR_MANIFEST!
  exit /b 1
)
set "UUP_PR_UUID="
for /F "usebackq eol=# tokens=1-2 delims=|" %%a in ("!UUP_PR_MANIFEST!") do (
  if /i "%%a"=="uuid" if not defined UUP_PR_UUID set "UUP_PR_UUID=%%b"
)
if "!UUP_PR_UUID!"=="" (
  echo ERROR: the staged manifest carries no uuid meta row - purge refused.
  exit /b 1
)
set "UUP_PR_SPOOL=%WOU_UPGRADE_SPOOL%"
if "!UUP_PR_SPOOL!"=="" set "UUP_PR_SPOOL=%TEMP%\wou-upgrade-spool"
set "UUP_PR_SETS=!UUP_PR_SPOOL!\!UUP_PR_CIBLE!-!UUP_PR_ARCHE!-!UUP_PR_LANGUE!"
if not exist "!UUP_PR_SETS!\" md "!UUP_PR_SETS!"
rem Archive the current working set under the staged uuid (the spool keeps
rem exactly the current uuid set per target-lang-arch). The working set is
rem the spool root's manifest.txt + files\ - moved only when the keep-list
rem revision dir does not exist yet and the working manifest matches the
rem staged uuid.
if not exist "!UUP_PR_SETS!\!UUP_PR_UUID!\" (
  if exist "!UUP_PR_SPOOL!\manifest.txt" (
    set "UUP_PR_WUUID="
    for /F "usebackq eol=# tokens=1-2 delims=|" %%a in ("!UUP_PR_SPOOL!\manifest.txt") do (
      if /i "%%a"=="uuid" if not defined UUP_PR_WUUID set "UUP_PR_WUUID=%%b"
    )
    if /i "!UUP_PR_WUUID!"=="!UUP_PR_UUID!" (
      md "!UUP_PR_SETS!\!UUP_PR_UUID!"
      move "!UUP_PR_SPOOL!\manifest.txt" "!UUP_PR_SETS!\!UUP_PR_UUID!\manifest.txt" >nul 2>&1
      if exist "!UUP_PR_SPOOL!\files\" move "!UUP_PR_SPOOL!\files" "!UUP_PR_SETS!\!UUP_PR_UUID!\files" >nul 2>&1
      echo Info: Working set archived under the staged uuid: !UUP_PR_UUID!
    )
  )
)
set /a UUP_PR_REMOVED=0
set /a UUP_PR_KEPT=0
for /F "delims=" %%d in ('dir /B /AD "!UUP_PR_SETS!" 2^>nul') do (
  if exist "!UUP_PR_SETS!\%%d\manifest.txt" (
    set "UUP_PR_DUUID="
    for /F "usebackq eol=# tokens=1-2 delims=|" %%a in ("!UUP_PR_SETS!\%%d\manifest.txt") do (
      if /i "%%a"=="uuid" if not defined UUP_PR_DUUID set "UUP_PR_DUUID=%%b"
    )
    if /i "!UUP_PR_DUUID!"=="!UUP_PR_UUID!" (
      set /a UUP_PR_KEPT+=1
    ) else (
      rd /s /q "!UUP_PR_SETS!\%%d" >nul 2>&1
      set /a UUP_PR_REMOVED+=1
      echo Info: Purged stale revision set %%d \(uuid !UUP_PR_DUUID!\)
    )
  )
)
if !UUP_PR_REMOVED! EQU 0 (
  echo Info: PURGE: 0 removals - the spool keeps only the staged revision !UUP_PR_UUID! ^(!UUP_PR_KEPT! set^(s^) kept^).
) else (
  echo Info: PURGE: !UUP_PR_REMOVED! stale revision set^(s^) removed, !UUP_PR_KEPT! kept - the spool holds only revision !UUP_PR_UUID! for !UUP_PR_CIBLE!-!UUP_PR_ARCHE!-!UUP_PR_LANGUE!.
)
exit /b 0
