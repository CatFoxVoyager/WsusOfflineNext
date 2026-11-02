@echo off
rem *** Author: WSUS Offline Update Community / Antigravity ***
rem *** Modern Office Click-to-Run (ODT) Staging Engine ***

setlocal enabledelayedexpansion

pushd "%~dp0.."
set "REPO_ROOT=%CD%"
popd

set "ODT_DIR=%REPO_ROOT%\bin\odt"
set "ODT_EXE=%ODT_DIR%\setup.exe"
set "TEMPLATES_DIR=%REPO_ROOT%\static\odt-templates"
set "MD_DIR=%REPO_ROOT%\client\md"
set "HASHES_FILE=%MD_DIR%\hashes-office-c2r.txt"

rem *** Parameter Validation ***
if "%1"=="" goto Usage
if "%2"=="" goto Usage

set "TARGET_PROD=%1"
set "TARGET_ARCH=%2"

if /i not "%TARGET_PROD%"=="o2k19" (
  if /i not "%TARGET_PROD%"=="o2k21" (
    if /i not "%TARGET_PROD%"=="o2k24" goto Usage
  )
)

if /i not "%TARGET_ARCH%"=="x86" (
  if /i not "%TARGET_ARCH%"=="x64" goto Usage
)

set "TARGET_LANG=%3"
if "%TARGET_LANG%"=="" set "TARGET_LANG=MatchOS"
if "%TARGET_LANG:~0,1%"=="/" set "TARGET_LANG=MatchOS"

rem *** Optional 4th argument: /dry-run test lenience flag - case-insensitive, ***
rem *** parsed in the free 4th slot (no existing caller passes an argument 4) ***
rem *** /dry-run scopes ALL test lenience to the ODT download: a dead ODT ***
rem *** warns and continues, and NO hash entry is written (no ghost integrity ***
rem *** file). Without the flag the run is fail-closed. The bash-side ***
rem *** equivalent is the warn-and-baseline behavior of ***
rem *** sh/download-updates-tasks/65-office-c2r.bash (pinned at plan 20-02). ***
set "DRY_RUN="
if /i "%4"=="/dry-run" set "DRY_RUN=1"

if /i "%TARGET_ARCH%"=="x86" (
  set "EDITION_NUM=32"
) else (
  set "EDITION_NUM=64"
)

set "DEST_DIR=%REPO_ROOT%\client\office\c2r\%TARGET_PROD%\%TARGET_ARCH%"
set "CONFIG_XML=%TEMP%\odt-config-%TARGET_PROD%-%TARGET_ARCH%.xml"

echo =======================================================================
echo WSUS Offline Update - Office Click-to-Run (ODT) Staging
echo Product:      Microsoft Office %TARGET_PROD%
echo Architecture: %TARGET_ARCH% (Edition %EDITION_NUM%)
echo Language:     %TARGET_LANG%
echo Destination:  %DEST_DIR%
echo =======================================================================

rem *** 1. Ensure ODT setup.exe is present and verified ***
if not exist "%ODT_DIR%" mkdir "%ODT_DIR%" 2>nul

if not exist "%ODT_EXE%" (
  echo Info: Office Deployment Tool setup.exe not found in bin\odt.
  echo Downloading official Office Deployment Tool from Microsoft...
  set "ODT_URL=https://download.microsoft.com/download/6c1eeb25-cf8b-41d9-8d0d-cc1dbc032140/officedeploymenttool_20430-20146.exe"
  set "ODT_INSTALLER=%TEMP%\officedeploymenttool.exe"
  
  if exist "%REPO_ROOT%\bin\wget.exe" (
    "%REPO_ROOT%\bin\wget.exe" -N -O "!ODT_INSTALLER!" "!ODT_URL!"
  ) else (
    powershell -NoProfile -Command "(New-Object System.Net.WebClient).DownloadFile('!ODT_URL!', '!ODT_INSTALLER!')"
  )
  
  if not exist "!ODT_INSTALLER!" (
    echo Error: Failed to download Office Deployment Tool installer.
    exit /b 1
  )
  
  echo Extracting setup.exe...
  powershell -NoProfile -Command ^
    "$raw = [System.IO.File]::ReadAllBytes('!ODT_INSTALLER!'); " ^
    "$mscf = [System.Text.Encoding]::ASCII.GetBytes('MSCF'); " ^
    "$idx = -1; " ^
    "for ($i=0; $i -lt $raw.Length-4; $i++) { " ^
    "  if ($raw[$i] -eq $mscf[0] -and $raw[$i+1] -eq $mscf[1] -and $raw[$i+2] -eq $mscf[2] -and $raw[$i+3] -eq $mscf[3]) { $idx = $i; break; } " ^
    "}; " ^
    "if ($idx -ge 0) { " ^
    "  $cabPath = [System.IO.Path]::Combine($env:TEMP, 'odt_inner.cab'); " ^
    "  $cabBytes = New-Object byte[] ($raw.Length - $idx); " ^
    "  [Array]::Copy($raw, $idx, $cabBytes, 0, $cabBytes.Length); " ^
    "  [System.IO.File]::WriteAllBytes($cabPath, $cabBytes); " ^
    "  & expand.exe -F:* $cabPath '%ODT_DIR%' >$null; " ^
    "  Remove-Item -Force $cabPath 2>$null; " ^
    "} else { " ^
    "  & '!ODT_INSTALLER!' /quiet /extract:'%ODT_DIR%'; " ^
    "}"
  del "!ODT_INSTALLER!" 2>nul
)

if not exist "%ODT_EXE%" (
  echo Error: setup.exe missing from bin\odt.
  exit /b 1
)

rem *** ODT freshness check (warn-only) ***
rem *** Compares the pinned ODT build with the Microsoft release-history page ***
rem *** at generation time. This block NEVER aborts the run: it holds no ***
rem *** failure exit at all - an offline host, a fetch failure, a timeout or ***
rem *** an unreadable page warn and fall through. It never touches the ***
rem *** pinned download URL above: the pin moves only by a deliberate re-pin ***
rem *** (the mirror port keeps byte-identical pins of its own). ***
set "ODT_HISTORY_URL=https://learn.microsoft.com/en-us/officeupdates/odt-release-history"
set "ODT_HISTORY_TMP=%TEMP%\odt-release-history.html"
rem *** build token searched on the release-history page (dot form, as the ***
rem *** page spells builds); MUST mirror the build embedded in the pinned ***
rem *** download URL above - ODT_PIN_TOKEN is its dash form as spelled in ***
rem *** the file name ***
set "ODT_PIN_BUILD=20430.20146"
set "ODT_PIN_TOKEN=%ODT_PIN_BUILD:.=-%"
set "FRESH_WGET="
if exist "%REPO_ROOT%\bin\wget.exe" set "FRESH_WGET=%REPO_ROOT%\bin\wget.exe"
if not defined FRESH_WGET if exist "%REPO_ROOT%\bin\wget64.exe" set "FRESH_WGET=%REPO_ROOT%\bin\wget64.exe"
echo --- ODT staging report: freshness ---
if defined DRY_RUN goto FreshnessDryRun
if not defined FRESH_WGET goto FreshnessSkip
"%FRESH_WGET%" -q -T 30 -t 1 -O "%ODT_HISTORY_TMP%" "%ODT_HISTORY_URL%" >nul 2>&1
if errorlevel 1 goto FreshnessSkip
set "FRESH_HEAD="
for /f "tokens=2-5 delims=. " %%A in ('findstr /i /r /c:"Version 16\.0\.[0-9][0-9]*\.[0-9][0-9]*" "%ODT_HISTORY_TMP%"') do if not defined FRESH_HEAD set "FRESH_HEAD=%%C.%%D"
if not defined FRESH_HEAD (
  echo Warning: ODT freshness verdict inconclusive - no build entry read on the release history page; pin %ODT_PIN_BUILD% not confirmed, refresh deliberately via the pinned-URL procedure.
  goto FreshnessDone
)
if not "%FRESH_HEAD%"=="%ODT_PIN_BUILD%" (
  echo Warning: ODT pin may be stale - the newest release-history entry does not list pin %ODT_PIN_BUILD%; refresh deliberately via the pinned-URL procedure.
  goto FreshnessDone
)
findstr /i "officedeploymenttool_" "%ODT_HISTORY_TMP%" 2>nul | findstr /i /v "%ODT_PIN_TOKEN%" >nul 2>&1
if errorlevel 1 (
  echo Info: ODT pin is current per release history.
) else (
  echo Warning: ODT pin may be stale - release history lists another build; refresh deliberately via the pinned-URL procedure.
)
goto FreshnessDone

:FreshnessDryRun
echo Info: dry-run - the ODT freshness check is skipped, a dry test never probes the network.
goto FreshnessDone

:FreshnessSkip
echo Warning: freshness check skipped (offline or source unreachable).
:FreshnessDone
if exist "%ODT_HISTORY_TMP%" del "%ODT_HISTORY_TMP%" 2>nul
set "FRESH_WGET="
set "FRESH_HEAD="
echo --- end ODT freshness section ---

rem *** Authenticode verification via sigcheck if available ***
if exist "%REPO_ROOT%\bin\sigcheck.exe" (
  echo Verifying digital signature of %ODT_EXE%...
  "%REPO_ROOT%\bin\sigcheck.exe" -q -vt "%ODT_EXE%" >nul 2>&1
  if errorlevel 1 (
    echo Warning: sigcheck -vt returned non-zero. Verifying basic signature...
    "%REPO_ROOT%\bin\sigcheck.exe" -q "%ODT_EXE%" | findstr /i /c:"Signed" >nul 2>&1
    if errorlevel 1 (
      echo Error: ODT setup.exe signature verification failed.
      exit /b 1
    )
  )
  echo Info: ODT setup.exe digital signature verified.
)

rem *** 2. Generate configuration XML from template ***
set "TEMPLATE_FILE=%TEMPLATES_DIR%\%TARGET_PROD%-template.xml"
if not exist "%TEMPLATE_FILE%" (
  echo Error: Template file %TEMPLATE_FILE% not found.
  exit /b 1
)

echo Generating ODT configuration manifest %CONFIG_XML%...
powershell -NoProfile -Command ^
  "$t = [System.IO.File]::ReadAllText('%TEMPLATE_FILE%'); " ^
  "$t = $t.Replace('{SOURCE_PATH}', '%DEST_DIR%'); " ^
  "$t = $t.Replace('{EDITION}', '%EDITION_NUM%'); " ^
  "$t = $t.Replace('{LANG}', '%TARGET_LANG%'); " ^
  "[System.IO.File]::WriteAllText('%CONFIG_XML%', $t);"

if not exist "%CONFIG_XML%" (
  echo Error: Failed to write ODT configuration manifest.
  exit /b 1
)

rem *** 3. Ensure destination folder exists ***
if not exist "%DEST_DIR%" mkdir "%DEST_DIR%" 2>nul

rem *** 4. Run ODT download ***
echo Starting ODT download process...
echo Command: "%ODT_EXE%" /download "%CONFIG_XML%"
"%ODT_EXE%" /download "%CONFIG_XML%"
set "ODT_EXIT=%ERRORLEVEL%"

rem *** 5. Remove the generated config manifest BEFORE any exit path - the ***
rem *** fail-closed branch below must never short-circuit this cleanup ***
if exist "%CONFIG_XML%" del "%CONFIG_XML%" 2>nul

rem *** fail-closed branch (OFC-04): a non-zero ODT exit fails a real run ***
if not "%ODT_EXIT%"=="0" goto OdtDownloadFailed
echo Info: ODT download completed successfully.
goto UpdateHashes

:OdtDownloadFailed
if not defined DRY_RUN (
  echo Error: ODT /download exited with code %ODT_EXIT% - staging is incomplete.
  echo Error: fail-closed - no integrity entry is written for a partial staging; fix the ODT download and re-run.
  exit /b 1
)
echo Warning: ODT /download exited with code %ODT_EXIT% - dry-run lenience: continuing WITHOUT writing any hash entry.

:UpdateHashes
rem *** 6. Update cryptographic hash database - atomic rewrite, never append ***
if defined DRY_RUN (
  echo Info: dry-run - integrity database %HASHES_FILE% left untouched, no ghost hash file.
  goto Finish
)
if not exist "%MD_DIR%" mkdir "%MD_DIR%" 2>nul
if not exist "%DEST_DIR%" (
  echo Error: ODT payload directory %DEST_DIR% is missing - refusing to regenerate the integrity file.
  exit /b 1
)
echo Updating integrity database %HASHES_FILE% - atomic rewrite of the %TARGET_PROD%/%TARGET_ARCH% slice...
powershell -NoProfile -Command ^
  "$ErrorActionPreference = 'Stop'; " ^
  "$files = @(Get-ChildItem -Path '%DEST_DIR%' -Recurse -File); " ^
  "if ($files.Count -eq 0) { Write-Error 'ODT payload directory is empty'; exit 1; } " ^
  "$prefix = 'client/office/c2r/%TARGET_PROD%/%TARGET_ARCH%/'; " ^
  "$newLines = foreach ($f in $files) { " ^
  "  $hash = (Get-FileHash -Path $f.FullName -Algorithm SHA256).Hash.ToLower(); " ^
  "  $rel = $f.FullName.Substring('%REPO_ROOT%'.Length).TrimStart('\', '/').Replace('\', '/'); " ^
  "    \"$hash *$rel\" " ^
  "  }; " ^
  "$keep = @(); " ^
  "if ([System.IO.File]::Exists('%HASHES_FILE%')) { " ^
  "  $keep = @(Get-Content -Path '%HASHES_FILE%' | Where-Object { $_ -and ($_.TrimEnd() -notmatch ('^[a-fA-F0-9]{64} \*' + [regex]::Escape($prefix))) }); " ^
  "} " ^
  "$tmp = '%HASHES_FILE%.tmp'; " ^
  "[System.IO.File]::WriteAllLines($tmp, @($keep + $newLines)); " ^
  "Move-Item -Force -Path $tmp -Destination '%HASHES_FILE%'; " ^
  "Write-Host \"Rewrote $($newLines.Count) hash entries, kept $($keep.Count) sibling entries.\";"
if errorlevel 1 (
  echo Error: integrity database update failed - failing the run fail-closed.
  exit /b 1
)

:Finish
echo Done.
exit /b 0

:Usage
echo.
echo WSUS Offline Update - Office Click-to-Run (ODT) Staging Engine
echo.
echo Usage: %~n0 {o2k19 ^| o2k21 ^| o2k24} {x86 ^| x64} [Language] [/dry-run]
echo.
echo   /dry-run  test-only lenience, STRICTLY scoped to the ODT download:
echo             a failing ODT download warns and continues WITHOUT writing
echo             any hash entry (no ghost integrity file). Without the flag
echo             the run is fail-closed: a non-zero ODT exit fails the run
echo             with rc 1 and no integrity file is written.
echo             Bash-side equivalent: the warn-and-baseline behavior of
echo             sh/download-updates-tasks/65-office-c2r.bash (plan 20-02).
echo.
echo   A warn-only ODT freshness check runs at generation time on real runs:
echo   it compares the pinned build with the Microsoft release-history page
echo   and warns (never fails) when the pin may be stale or when the page
echo   cannot be reached offline.
echo Examples:
echo   %~n0 o2k24 x64 MatchOS
echo   %~n0 o2k21 x86 fr-fr
echo   %~n0 o2k19 x64 en-us
exit /b 1
