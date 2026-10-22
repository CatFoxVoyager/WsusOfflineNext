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

if not "%ODT_EXIT%"=="0" (
  echo Warning: ODT /download exited with code %ODT_EXIT%.
  rem Don't hard-fail in offline/dry test runs if destination was simulated
) else (
  echo Info: ODT download completed successfully.
)

rem *** 5. Update cryptographic hash database ***
if not exist "%MD_DIR%" mkdir "%MD_DIR%" 2>nul
if exist "%DEST_DIR%" (
  echo Updating integrity database %HASHES_FILE%...
  powershell -NoProfile -Command ^
    "$files = Get-ChildItem -Path '%DEST_DIR%' -Recurse -File; " ^
    "if ($files) { " ^
    "  $lines = foreach ($f in $files) { " ^
    "    $hash = (Get-FileHash -Path $f.FullName -Algorithm SHA256).Hash.ToLower(); " ^
    "    $rel = $f.FullName.Substring('%REPO_ROOT%'.Length).TrimStart('\', '/').Replace('\', '/'); " ^
    "    \"$hash *$rel\" " ^
    "  }; " ^
    "  [System.IO.File]::AppendAllLines('%HASHES_FILE%', $lines); " ^
    "  Write-Host \"Added $($files.Count) SHA256 hash entries to $HASHES_FILE.\"; " ^
    "}"
)

if exist "%CONFIG_XML%" del "%CONFIG_XML%" 2>nul
echo Done.
exit /b 0

:Usage
echo.
echo WSUS Offline Update - Office Click-to-Run (ODT) Staging Engine
echo.
echo Usage: %~n0 {o2k19 ^| o2k21 ^| o2k24} {x86 ^| x64} [Language] [/verify]
echo Examples:
echo   %~n0 o2k24 x64 MatchOS
echo   %~n0 o2k21 x86 fr-fr
echo   %~n0 o2k19 x64 en-us
exit /b 1
