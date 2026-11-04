@echo off
rem ***  WSUS Offline Next - Generator Adaptive Launcher (pure .cmd)  ***
rem ***  Takes over the adaptive launcher role of the former AutoIt  ***
rem ***  launcher source: it routes to the modern WebView2/.NET 8    ***
rem ***  generator - the only generator executable since the classic ***
rem ***  interface was retired (Phase 25) - with the same registry   ***
rem ***  probes, overrides and exit-code propagation as the          ***
rem ***  incumbent.                                                  ***

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
echo(%*| findstr /i /C:"/legacy" /C:"/classic" >nul && set "FORCE_LEGACY=1"
echo(%*| findstr /i /C:"/modern" /C:"/next" >nul && set "FORCE_MODERN=1"

rem --- INI override -------------------------------------------------------
rem Frozen contract parity: the incumbent read the ForceLegacyGUI key from
rem section [Control] of this INI file. This reader honors a same-named key
rem wherever it appears in the file (including under another section) - an
rem accepted contract simplification; the only possible effect is a Legacy
rem route, i.e. the fail-safe direction.
if exist "%~dp0UpdateGenerator.ini" for /f "eol=; tokens=1,* delims==" %%A in ('findstr /b /i "ForceLegacyGUI=" "%~dp0UpdateGenerator.ini" 2^>nul') do if /i "%%A"=="ForceLegacyGUI" if "%%B"=="1" set "FORCE_LEGACY=1"

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

rem Gate 3, the modern generator executable must exist.
set "MODERN_EXE_OK=0"
if exist "%~dp0UpdateGeneratorModern.exe" set "MODERN_EXE_OK=1"

rem Gate 4, WebView2 runtime at or above the SDK-matched floor. Version
rem comparison is never reimplemented in batch: client/cmd/CompareVersions.vbs
rem exits 0 (equal), 1 (parser error), 2 (newer) or 3 (older). 0 and 2 are
rem capable; 1 and 3 route Legacy - an absent runtime, an unparsable value
rem and a parser error all fail safe to Legacy, matching the incumbent.
set "WV2_OK=0"
set "CMP_RC=1"
if not defined WEBVIEW2_PV goto Wv2Evaluated
"%SystemRoot%\System32\cscript.exe" //nologo "%~dp0client\cmd\CompareVersions.vbs" "%WEBVIEW2_PV%" "%MIN_WEBVIEW2_VERSION%" >nul 2>&1
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

rem Phase 25 retarget: the classic generator executable was retired, so a
rem single target remains. A Legacy route (a /legacy or /classic override,
rem or a failed capability gate) resolves to the same modern exe - the
rem in-host Evergreen dialog then explains the runtime situation.
set "TARGET_NAME=UpdateGeneratorModern.exe"
if exist "%~dp0%TARGET_NAME%" goto HaveTarget

rem Target missing: bilingual error, pause, exit code 1.
echo [launcher] FEHLER: Kein geeignetes Programm gefunden.
echo [launcher] ERROR: No suitable generator executable found.
echo [launcher] Ziel/Target: "%~dp0%TARGET_NAME%"
pause
endlocal & exit /b 1

:HaveTarget
rem Phase 25 retarget: the classic interface is retired - every route lands
rem on the modern exe; the in-host dialog explains the runtime situation.
echo [launcher] Vorgang: Die klassische Variante wird nicht mehr angeboten.
echo [launcher] Operation: The classic interface is no longer offered.
echo [launcher] Starte moderne Programmvariante...
echo [launcher] Launching modern interface...
:DoHandoff

rem Handoff (RunWait parity): a batch invoking an exe synchronously waits
rem for it. No window-spawning shell verb is used; the quoted path and the
rem raw argument tail are passed verbatim and the child's exit code
rem propagates as the launcher exit code.
"%~dp0%TARGET_NAME%" %*
set "LAUNCH_RC=%errorlevel%"
endlocal & exit /b %LAUNCH_RC%

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
