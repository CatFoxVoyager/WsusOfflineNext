@echo off
rem ***  WSUS Offline Next - Installer Adaptive Launcher (pure .cmd)   ***
rem ***  Takes over the adaptive launcher role of the retired AutoIt   ***
rem ***  launcher source: it routes to the modern                      ***
rem ***  WebView2/.NET 8 installer when all capability gates pass, and ***
rem ***  to the classic Win32 installer otherwise, with the same       ***
rem ***  registry probes, overrides, fallback chain and exit-code      ***
rem ***  propagation as the incumbent, plus the single-prompt UAC      ***
rem ***  elevation boundary described below.                           ***

verify other 2>nul
setlocal enableextensions
if errorlevel 1 goto NoExtensions

rem Work in the launcher directory (parity with the AutoIt launcher,
rem which used @ScriptDir as the working directory of the child).
cd /d "%~dp0"

rem Minimum WebView2 runtime version accepted by the modern interface.
rem This literal is rewritten automatically by ci/bump-webview2-dep.bash
rem and must not be recopied or duplicated anywhere else in this file.
set "MIN_WEBVIEW2_VERSION=156.0.4314.35"

set "FORCE_LEGACY=0"
set "FORCE_MODERN=0"
set "TARGET_NAME="
set "CAN_MODERN=0"
set "ROUTE_MODERN=0"
set "LAUNCH_RC=0"

rem --- CLI overrides ------------------------------------------------------
rem Whole-tail substring match on the raw argument tail (parity with the
rem AutoIt launcher's StringInStr on $CmdLineRaw). The four frozen tokens
rem are /legacy /classic (force Legacy) and /modern /next (force Modern).
rem The /C: literal form is required: a quoted /-prefixed search string
rem without /C: is misparsed by findstr as option letters.
echo(%*| findstr /i /C:"/legacy" /C:"/classic" >nul && set "FORCE_LEGACY=1"
echo(%*| findstr /i /C:"/modern" /C:"/next" >nul && set "FORCE_MODERN=1"

rem --- INI override -------------------------------------------------------
rem Frozen contract parity: the incumbent read the ForceLegacyGUI key from
rem section [Control] of this INI file. This reader honors a same-named key
rem wherever it appears in the file (including under another section) - an
rem accepted contract simplification; the only possible effect is a Legacy
rem route, i.e. the fail-safe direction.
if exist "%~dp0UpdateInstaller.ini" for /f "eol=; tokens=1,* delims==" %%A in ('findstr /b /i "ForceLegacyGUI=" "%~dp0UpdateInstaller.ini" 2^>nul') do if /i "%%A"=="ForceLegacyGUI" if "%%B"=="1" set "FORCE_LEGACY=1"

rem --- WebView2 runtime probe --------------------------------------------
rem Exactly 6 physical registry keys, first non-empty pv value wins, order
rem fixed (contract parity with the incumbent's 8 probes: the AutoIt
rem HKLM64/duplicate-view probes resolve to the same physical keys, and the
rem /reg:64 flag keeps every HKLM probe bitness-invariant even when this
rem script is spawned from a 32-bit cmd.exe).
call :ProbeWebView2Key "HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" "/reg:64"
if not defined WEBVIEW2_PV call :ProbeWebView2Key "HKLM\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" "/reg:64"
if not defined WEBVIEW2_PV call :ProbeWebView2Key "HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-F55F-4E40-8A2F-69DF4B838507}" "/reg:64"
if not defined WEBVIEW2_PV call :ProbeWebView2Key "HKLM\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-F55F-4E40-8A2F-69DF4B838507}" "/reg:64"
if not defined WEBVIEW2_PV call :ProbeWebView2Key "HKCU\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" ""
if not defined WEBVIEW2_PV call :ProbeWebView2Key "HKCU\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-F55F-4E40-8A2F-69DF4B838507}" ""

rem --- Capability gates (all four must pass for Modern) -------------------
rem Gate 1, architecture: x64 or ARM64. PROCESSOR_ARCHITEW6432 covers the
rem 32-bit cmd.exe on a 64-bit OS case (repo idiom).
set "ARCH_OK=0"
if /i "%PROCESSOR_ARCHITECTURE%"=="AMD64" set "ARCH_OK=1"
if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "ARCH_OK=1"
if /i "%PROCESSOR_ARCHITEW6432%"=="AMD64" set "ARCH_OK=1"
if /i "%PROCESSOR_ARCHITEW6432%"=="ARM64" set "ARCH_OK=1"

rem Gate 2, OS build: .NET 8 requires Windows 10 1607 (build 14393) or
rem newer. Sanitize-then-use: the captured value replaces the preset 0 only
rem when it is purely numeric, so a hostile registry value can never reach
rem the comparison; the comparison itself stays UNQUOTED - a quoted GEQ
rem would degrade to a lexicographic string compare and let old builds pass.
set "OS_BUILD=0"
for /f "tokens=2,*" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v CurrentBuildNumber /reg:64 2^>nul ^| findstr /C:"REG_SZ"') do (
    echo(%%B| findstr /r "^[0-9][0-9]*$" >nul && set "OS_BUILD=%%B"
)
set "BUILD_OK=0"
if %OS_BUILD% GEQ 14393 set "BUILD_OK=1"

rem Gate 3, the modern installer executable must exist.
set "MODERN_EXE_OK=0"
if exist "%~dp0UpdateInstallerModern.exe" set "MODERN_EXE_OK=1"

rem Gate 4, WebView2 runtime at or above the SDK-matched floor. Version
rem comparison is never reimplemented in batch: cmd/CompareVersions.vbs
rem exits 0 (equal), 1 (parser error), 2 (newer) or 3 (older). 0 and 2 are
rem capable; 1 and 3 route Legacy - an absent runtime, an unparsable value
rem and a parser error all fail safe to Legacy, matching the incumbent.
set "WV2_OK=0"
set "CMP_RC=1"
if not defined WEBVIEW2_PV goto Wv2Evaluated
"%SystemRoot%\System32\cscript.exe" //nologo "%~dp0cmd\CompareVersions.vbs" "%WEBVIEW2_PV%" "%MIN_WEBVIEW2_VERSION%" >nul 2>&1
set "CMP_RC=%errorlevel%"
:Wv2Evaluated
if "%CMP_RC%"=="0" set "WV2_OK=1"
if "%CMP_RC%"=="2" set "WV2_OK=1"

set "CAN_MODERN=1"
if "%ARCH_OK%"=="0" set "CAN_MODERN=0"
if "%BUILD_OK%"=="0" set "CAN_MODERN=0"
if "%MODERN_EXE_OK%"=="0" set "CAN_MODERN=0"
if "%WV2_OK%"=="0" set "CAN_MODERN=0"

rem --- Decision rule (exact incumbent parity) -----------------------------
rem Modern iff FORCE_MODERN is set, or CAN_MODERN and not FORCE_LEGACY.
rem A force-Modern override bypasses every capability gate.
set "ROUTE_MODERN=0"
if "%FORCE_MODERN%"=="1" set "ROUTE_MODERN=1"
if "%FORCE_LEGACY%"=="1" goto TargetResolved
if "%CAN_MODERN%"=="1" set "ROUTE_MODERN=1"
:TargetResolved

set "TARGET_NAME=UpdateInstallerLegacy.exe"
if "%ROUTE_MODERN%"=="1" set "TARGET_NAME=UpdateInstallerModern.exe"
if exist "%~dp0%TARGET_NAME%" goto HaveTarget

rem Fallback chain: the chosen target is missing, use the other exe (Legacy
rem first on the Legacy branch, Modern first on the Modern branch).
if "%ROUTE_MODERN%"=="1" set "TARGET_NAME=UpdateInstallerLegacy.exe"
if "%ROUTE_MODERN%"=="0" set "TARGET_NAME=UpdateInstallerModern.exe"
if exist "%~dp0%TARGET_NAME%" goto HaveTarget

rem Both targets missing: bilingual error, pause, exit code 1.
echo [launcher] FEHLER: Kein geeignetes Programm gefunden.
echo [launcher] ERROR: No suitable installer executable found.
echo [launcher] Ziel/Target: "%~dp0%TARGET_NAME%"
pause
endlocal & exit /b 1

:HaveTarget
if "%ROUTE_MODERN%"=="1" goto LaunchModern
echo [launcher] Starte klassische Programmvariante (Fallback)...
echo [launcher] Launching classic interface (fallback)...
goto DoHandoff
:LaunchModern
echo [launcher] Starte moderne Programmvariante...
echo [launcher] Launching modern interface...
:DoHandoff

rem --- Elevation-aware launch (LANC-03) -----------------------------------
rem Both installer targets carry requireAdministrator manifests, so the UAC
rem consent belongs at the target-exe manifest boundary: exactly ONE prompt
rem per launch. This launcher stays non-elevated and never relaunches
rem itself, so no second consent boundary can exist.
net session >nul 2>&1
if errorlevel 1 goto UnelevatedHandoff

rem Elevated session: an elevated parent launching a requireAdministrator
rem child neither prompts nor hits system error 740, so the target is
rem invoked directly with full wait and exit-code parity.
"%~dp0%TARGET_NAME%" %*
set "LAUNCH_RC=%errorlevel%"
endlocal & exit /b %LAUNCH_RC%

:UnelevatedHandoff
rem A direct CreateProcess on a requireAdministrator target from a
rem non-elevated launcher fails with system error 740, so the handoff goes
rem through Windows Script Host: a temporary, self-contained VBS under
rem %TEMP% raises the target via Shell.Application. The raw argument tail
rem is never interpolated into VBS source text - the arguments reach the
rem VBS through cscript argv and are re-quoted from WScript.Arguments
rem (threat T-24-03); the elevation verb itself is a static literal.
set "TEMP_VBS=%TEMP%\wson_elevate_installer.vbs"
for %%I in ("%~dp0.") do set "LAUNCHER_DIR=%%~fI"
>"%TEMP_VBS%" echo Option Explicit
>>"%TEMP_VBS%" echo Dim shShell, sParams, i
>>"%TEMP_VBS%" echo On Error Resume Next
>>"%TEMP_VBS%" echo Set shShell = CreateObject("Shell.Application")
>>"%TEMP_VBS%" echo sParams = ""
>>"%TEMP_VBS%" echo For i = 2 To WScript.Arguments.Count - 1
>>"%TEMP_VBS%" echo   sParams = sParams ^& Space(1) ^& """" ^& Replace(WScript.Arguments(i), """", """""") ^& """"
>>"%TEMP_VBS%" echo Next
>>"%TEMP_VBS%" echo shShell.ShellExecute WScript.Arguments(0), sParams, WScript.Arguments(1), "runas", 1
>>"%TEMP_VBS%" echo If Err.Number ^<^> 0 Then
>>"%TEMP_VBS%" echo   WScript.Echo "WSON-UAC-DECLINED"
>>"%TEMP_VBS%" echo   WScript.Quit 1
>>"%TEMP_VBS%" echo End If
>>"%TEMP_VBS%" echo WScript.Quit 0
"%SystemRoot%\System32\cscript.exe" //nologo "%TEMP_VBS%" "%~dp0%TARGET_NAME%" "%LAUNCHER_DIR%" %*
set "ELEV_RC=%errorlevel%"
del "%TEMP_VBS%" >nul 2>&1
if not "%ELEV_RC%"=="0" goto ElevationDeclined

rem Documented deviations from the AutoIt incumbent, specific to this
rem non-elevated branch: the handoff is asynchronous (Shell.Application
rem returns after process creation, so this console closes immediately
rem with exit code 0; the elevated branch above keeps full wait parity),
rem arguments are re-quoted through cscript argv (embedded-quote arguments
rem are out of the incumbent flag-only contract), and no registry or
rem routing values are ever echoed.
endlocal & exit /b 0

:ElevationDeclined
echo [launcher] Vorgang vom Benutzer abgebrochen.
echo [launcher] Operation cancelled by user.
pause
endlocal & exit /b 1

:NoExtensions
echo [launcher] FEHLER: Windows-Befehlserweiterungen nicht verfuegbar.
echo [launcher] ERROR: Windows command extensions not available.
pause
endlocal & exit /b 1

:ProbeWebView2Key
rem Reads the pv value of one EdgeUpdate client key. A missing key, an
rem empty value or a value of unexpected shape leaves WEBVIEW2_PV
rem undefined so probing continues with the next key. The anchored
rem numeric-shape check keeps hostile registry content (the HKCU copies are
rem user-writable) away from every later expansion sink; such values fail
rem safe to Legacy, matching the incumbent's zero-count rule.
set "WEBVIEW2_PV="
for /f "tokens=2,*" %%A in ('reg query %1 /v pv %~2 2^>nul ^| findstr /C:"REG_SZ"') do (
    echo(%%B| findstr /r "^[0-9][0-9.]*$" >nul && set "WEBVIEW2_PV=%%B"
)
goto :eof
