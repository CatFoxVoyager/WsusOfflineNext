@echo off
rem ***  WSUS Offline Next - Offline Runtime Bootstrap Helper          ***
rem ***  Called by the installer launcher INSIDE the already-elevated  ***
rem ***  context: silently installs the missing .NET 8 desktop runtime ***
rem ***  and/or the WebView2 runtime from the tree itself, re-probes   ***
rem ***  what it installed, and launches the final target with exit-   ***
rem ***  code propagation. It never elevates on its own and carries no ***
rem ***  consent boundary of its own.                                  ***
rem ***
rem ***  Invocation contract:                                          ***
rem ***    /apply dotnet-setup-or-dash webview2-setup-or-dash floor    ***
rem ***        target-name [flags...]                                  ***
rem ***  The floor value arrives positionally from the launcher, which ***
rem ***  keeps that value single-sourced; this file never names it.    ***
rem ***
rem ***  Re-probe scope: this helper re-verifies BOTH components with  ***
rem ***  a fresh probe pass before choosing Modern (conservative - a   ***
rem ***  dash setup argument is re-probed, not trusted, so a machine   ***
rem ***  that was only partially fixable still routes fail-safe).      ***
rem ***
rem ***  Sync note: both probe subroutines below are kept byte-shape   ***
rem ***  identical with the launcher's (same variable names), so the   ***
rem ***  battery parity gates read the same structure twice.           ***
rem ***
rem ***  Visibility note: the console stays up until the launched      ***
rem ***  installer exits - progress visibility is deliberate.          ***

verify other 2>nul
setlocal enableextensions
if errorlevel 1 goto NoExtensions

rem Work in the client directory (the launcher's child cwd contract), and
rem resolve its full path for the final launch: the target exe is always
rem started by full path (the launcher's own pattern), never by a bare
rem name that would depend on cwd-based command resolution.
cd /d "%~dp0.."
if errorlevel 1 goto CdFailed
for %%I in ("%~dp0..") do set "CLIENT_DIR=%%~fI"

rem --- Mode dispatch -------------------------------------------------------
if /i "%~1"=="/apply" goto ModeOk
echo [runtime-bootstrap] FEHLER: Unbekannter Modus. Erwartet: /apply ^<dotnet-setup-oder-strich^> ^<webview2-setup-oder-strich^> ^<floor^> ^<zielname^> [flags...]
echo [runtime-bootstrap] ERROR: Unknown mode. Expected: /apply ^<dotnet-setup-or-dash^> ^<webview2-setup-or-dash^> ^<floor^> ^<target-name^> [flags...]
endlocal & exit /b 1
:ModeOk

set "DOTNET_SETUP=%~2"
set "WV2_SETUP=%~3"
set "WV2_FLOOR=%~4"
set "TARGET_NAME=%~5"
set "TAIL_ARGS="
:BuildTailArgs
if "%~6"=="" goto TailArgsBuilt
set "TAIL_ARGS=%TAIL_ARGS% %~6"
shift
goto BuildTailArgs
:TailArgsBuilt

rem --- Defensive architecture guard (never trusts the caller) ---------------
rem The same W6432-aware AMD64 pattern as the launcher; a non-AMD64 context
rem skips straight to the route phase with both capability flags forced
rem absent - the classic route, and no installation is ever attempted there.
set "BOOTSTRAP_ARCH_OK=0"
if /i "%PROCESSOR_ARCHITECTURE%"=="AMD64" set "BOOTSTRAP_ARCH_OK=1"
if /i "%PROCESSOR_ARCHITEW6432%"=="AMD64" set "BOOTSTRAP_ARCH_OK=1"
if "%BOOTSTRAP_ARCH_OK%"=="1" goto ArchOk
echo [runtime-bootstrap] Kein AMD64-Kontext - keine Runtime-Installation, klassische Route.
echo [runtime-bootstrap] Non-AMD64 context - no runtime installation, classic route.
set "DOTNET8_OK=0"
set "WV2_CAPABLE=0"
goto RoutePhase
:ArchOk

set "PF_BASE=%ProgramFiles%"
if defined ProgramW6432 set "PF_BASE=%ProgramW6432%"

rem --- Install phase ---------------------------------------------------------
rem Documented silent switches; the numeric exit code is echoed (values are
rem never echoed, numbers are), 3010 only adds the restart note. A dash or a
rem vanished setup is skipped with a note; no medium file is ever deleted.
if "%DOTNET_SETUP%"=="-" goto DotnetSkip
if not exist "%DOTNET_SETUP%" goto DotnetSkip
echo [runtime-bootstrap] Starte Installation des .NET Desktop Runtimes...
echo [runtime-bootstrap] Launching the .NET Desktop Runtime installer...
"%DOTNET_SETUP%" /install /quiet /norestart
set "INSTALL_RC=%errorlevel%"
echo [runtime-bootstrap] Installer-Exitcode/Installer exit code: %INSTALL_RC%
if "%INSTALL_RC%"=="3010" echo [runtime-bootstrap] Hinweis: Neustart erforderlich, um die Installation abzuschliessen.
if "%INSTALL_RC%"=="3010" echo [runtime-bootstrap] Note: A restart is required to complete the installation.
goto DotnetDone
:DotnetSkip
echo [runtime-bootstrap] Kein .NET Desktop Runtime Setup uebergeben - Installation uebersprungen.
echo [runtime-bootstrap] No desktop runtime setup passed - installation skipped.
:DotnetDone

if "%WV2_SETUP%"=="-" goto Wv2Skip
if not exist "%WV2_SETUP%" goto Wv2Skip
echo [runtime-bootstrap] Starte Installation der WebView2 Runtime...
echo [runtime-bootstrap] Launching the WebView2 runtime installer...
"%WV2_SETUP%" /silent /install
set "INSTALL_RC=%errorlevel%"
echo [runtime-bootstrap] Installer-Exitcode/Installer exit code: %INSTALL_RC%
goto Wv2Done
:Wv2Skip
echo [runtime-bootstrap] Kein WebView2 Setup uebergeben - Installation uebersprungen.
echo [runtime-bootstrap] No WebView2 setup passed - installation skipped.
:Wv2Done

rem --- Re-probe phase (fresh pass, both components) ---------------------------
call :ProbeDotNet8 "%PF_BASE%\dotnet\dotnet.exe"

call :ProbeWebView2Key "HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" "/reg:64"
if not defined WEBVIEW2_PV call :ProbeWebView2Key "HKLM\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" "/reg:64"
if not defined WEBVIEW2_PV call :ProbeWebView2Key "HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-F55F-4E40-8A2F-69DF4B838507}" "/reg:64"
if not defined WEBVIEW2_PV call :ProbeWebView2Key "HKLM\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-F55F-4E40-8A2F-69DF4B838507}" "/reg:64"
if not defined WEBVIEW2_PV call :ProbeWebView2Key "HKCU\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" ""
if not defined WEBVIEW2_PV call :ProbeWebView2Key "HKCU\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-F55F-4E40-8A2F-69DF4B838507}" ""

set "WV2_CAPABLE=0"
set "CMP_RC=1"
if not defined WEBVIEW2_PV goto Wv2ProbeEvaluated
"%SystemRoot%\System32\cscript.exe" //nologo "%~dp0CompareVersions.vbs" "%WEBVIEW2_PV%" "%WV2_FLOOR%" >nul 2>&1
set "CMP_RC=%errorlevel%"
:Wv2ProbeEvaluated
if "%CMP_RC%"=="0" set "WV2_CAPABLE=1"
if "%CMP_RC%"=="2" set "WV2_CAPABLE=1"

goto RoutePhase

:RoutePhase
rem --- Route phase ------------------------------------------------------------
rem Conservative: Modern only when a fresh probe pass confirms BOTH the
rem desktop runtime and WebView2; every failed install, failed re-probe and
rem non-AMD64 context falls back to the classic interface. The modern target
rem name arrives as the caller-supplied target-name argument - it is never a
rem literal here; the classic name is the only target literal in this file.
set "FINAL_TARGET=UpdateInstallerLegacy.exe"
set "BOOTSTRAP_ROUTE_MODERN=0"
if "%DOTNET8_OK%"=="1" if "%WV2_CAPABLE%"=="1" set "BOOTSTRAP_ROUTE_MODERN=1"
if "%BOOTSTRAP_ROUTE_MODERN%"=="1" set "FINAL_TARGET=%TARGET_NAME%"
set "FINAL_PATH=%CLIENT_DIR%\%FINAL_TARGET%"
if exist "%FINAL_PATH%" goto BootstrapTargetResolved

rem Fallback chain: the chosen target is missing, use the other exe.
if "%BOOTSTRAP_ROUTE_MODERN%"=="1" set "FINAL_TARGET=UpdateInstallerLegacy.exe"
if "%BOOTSTRAP_ROUTE_MODERN%"=="0" set "FINAL_TARGET=%TARGET_NAME%"
set "FINAL_PATH=%CLIENT_DIR%\%FINAL_TARGET%"
if exist "%FINAL_PATH%" goto BootstrapTargetResolved

echo [runtime-bootstrap] FEHLER: Kein geeignetes Programm gefunden.
echo [runtime-bootstrap] ERROR: No suitable installer executable found.
echo [runtime-bootstrap] Ziel/Target: "%FINAL_PATH%"
pause
endlocal & exit /b 1

:BootstrapTargetResolved
if "%BOOTSTRAP_ROUTE_MODERN%"=="1" goto BootstrapLaunchModern
echo [runtime-bootstrap] Starte klassische Programmvariante (Fallback)...
echo [runtime-bootstrap] Launching classic interface (fallback)...
goto BootstrapLaunch
:BootstrapLaunchModern
echo [runtime-bootstrap] Starte moderne Programmvariante...
echo [runtime-bootstrap] Launching modern interface...
:BootstrapLaunch
"%FINAL_PATH%" %TAIL_ARGS%
set "FINAL_RC=%errorlevel%"
endlocal & exit /b %FINAL_RC%

rem --- Subroutines (byte-shape identical with the launcher's probes) ----------

:NoExtensions
echo [runtime-bootstrap] FEHLER: Windows-Befehlserweiterungen nicht verfuegbar.
echo [runtime-bootstrap] ERROR: Windows command extensions not available.
endlocal & exit /b 1

:CdFailed
echo [runtime-bootstrap] FEHLER: Programmverzeichnis nicht erreichbar.
echo [runtime-bootstrap] ERROR: Unable to enter the program directory.
endlocal & exit /b 1

:ProbeDotNet8
rem Presence-only probe for the installed desktop runtime family at major
rem version 8: run the host at %1 with --list-runtimes (stderr silenced)
rem and set the presence flag only when a listing line names that family at
rem the wanted major version (begin-anchored literal filter; the token is
rem battery-counted and is deliberately not recopied in this comment). The
rem flag starts at 0 on every call: an absent host, a failing listing and a
rem hostile listing all fail safe. No captured value is stored or echoed.
set "DOTNET8_OK=0"
if not exist "%~1" goto :eof
for /f "delims=" %%L in ('^""%~1" --list-runtimes 2^>nul ^| findstr /b /l /c:"Microsoft.WindowsDesktop.App 8."') do set "DOTNET8_OK=1"
goto :eof

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
