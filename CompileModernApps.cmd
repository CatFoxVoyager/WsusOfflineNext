@echo off
setlocal
cd /d "%~dp0"

echo =======================================================================
echo [WSUS Offline Next] Compiling v6.0.1+2026.11 Executables
echo =======================================================================
echo.

rem 1. UpdateGenerator.exe
echo [1/3] Building React frontend for WSUS Offline Next Generator...
cd /d "%~dp0src-modern\generator"
call npm run build
if %errorlevel% neq 0 (
    echo [ERROR] Generator frontend build failed.
    if /i "%~1" neq "--no-pause" if /i "%~1" neq "/nopause" pause
    exit /b %errorlevel%
)

rem Empty-dist guard (DEPS-07): refuse to publish over an empty frontend.
set EMPTY_DIST=0
if not exist "dist\index.html" set EMPTY_DIST=1
dir /b "dist\assets\*.js" >nul 2>&1
if errorlevel 1 set EMPTY_DIST=1
if "%EMPTY_DIST%"=="1" (
    echo [ERROR] Empty-dist guard: dist\index.html missing or no JS asset in dist\assets for the Generator.
    if /i "%~1" neq "--no-pause" if /i "%~1" neq "/nopause" pause
    exit /b 1
)

echo [1/3] .NET 8 single-file publish of UpdateGenerator.exe...
dotnet publish host\UpdateGenerator.csproj -c Release -r win-x64 /p:PublishSingleFile=true /p:SelfContained=false -o bin
if %errorlevel% neq 0 (
    echo [ERROR] dotnet publish failed for UpdateGenerator.
    if /i "%~1" neq "--no-pause" if /i "%~1" neq "/nopause" pause
    exit /b %errorlevel%
)
copy /y bin\UpdateGenerator.exe "%~dp0UpdateGeneratorModern.exe"
xcopy /e /i /y bin\wwwroot "%~dp0wwwroot"

rem 2. UpdateInstaller.exe
echo.
echo [2/3] Building the React frontend of UpdateInstaller...
cd /d "%~dp0src-modern\installer"
call npm run build
if %errorlevel% neq 0 (
    echo [ERROR] Installer frontend build failed.
    if /i "%~1" neq "--no-pause" if /i "%~1" neq "/nopause" pause
    exit /b %errorlevel%
)

rem Empty-dist guard (DEPS-07): refuse to publish over an empty frontend.
set EMPTY_DIST=0
if not exist "dist\index.html" set EMPTY_DIST=1
dir /b "dist\assets\*.js" >nul 2>&1
if errorlevel 1 set EMPTY_DIST=1
if "%EMPTY_DIST%"=="1" (
    echo [ERROR] Empty-dist guard: dist\index.html missing or no JS asset in dist\assets for the Installer.
    if /i "%~1" neq "--no-pause" if /i "%~1" neq "/nopause" pause
    exit /b 1
)

echo [2/3] .NET 8 single-file publish of UpdateInstaller.exe...
dotnet publish host\UpdateInstaller.csproj -c Release -r win-x64 /p:PublishSingleFile=true /p:SelfContained=false -o bin
if %errorlevel% neq 0 (
    echo [ERROR] dotnet publish failed for UpdateInstaller.
    if /i "%~1" neq "--no-pause" if /i "%~1" neq "/nopause" pause
    exit /b %errorlevel%
)
copy /y bin\UpdateInstaller.exe "%~dp0client\UpdateInstallerModern.exe"
xcopy /e /i /y bin\wwwroot "%~dp0client\wwwroot"

cd /d "%~dp0"
echo.
echo [3/3] Building the native installer GUI (Lazarus, both architectures)...
rem Toolchain resolution: WO_LAZARUS_ROOT override, else the scratch default.
rem The CI lane is WIRED: the monthly-updates.yml release job feeds this
rem override from the WO_LAZARUS_ROOT repository variable (27-01). The
rem scratch default under .planning/tmp/23-tools/lazarus remains the
rem dev-machine fallback and fails closed with a named error when absent.
if not defined WO_LAZARUS_ROOT set "WO_LAZARUS_ROOT=%~dp0.planning\tmp\23-tools\lazarus"
set "LAZBUILD=%WO_LAZARUS_ROOT%\lazbuild.exe"
if not exist "%LAZBUILD%" (
    echo [ERROR] lazbuild not found: %LAZBUILD%
    echo Install the Lazarus toolchain or set WO_LAZARUS_ROOT - the CI release job feeds it from the WO_LAZARUS_ROOT repo variable.
    if /i "%~1" neq "--no-pause" if /i "%~1" neq "/nopause" pause
    exit /b 1
)
rem Stale-slot hygiene (Pitfall A / 2026.10 xcopy lesson): delete BEFORE
rem writing; a locked exe must fail named, never silently ship the old GUI.
del /f /q "%~dp0client\UpdateInstallerLegacy.exe" 2>nul
del /f /q "%~dp0client\UpdateInstallerLegacy64.exe" 2>nul
if exist "%~dp0client\UpdateInstallerLegacy.exe" (
    echo [ERROR] client\UpdateInstallerLegacy.exe is locked - close every launched instance and retry.
    if /i "%~1" neq "--no-pause" if /i "%~1" neq "/nopause" pause
    exit /b 1
)
if exist "%~dp0client\UpdateInstallerLegacy64.exe" (
    echo [ERROR] client\UpdateInstallerLegacy64.exe is locked - close every launched instance and retry.
    if /i "%~1" neq "--no-pause" if /i "%~1" neq "/nopause" pause
    exit /b 1
)
"%LAZBUILD%" --build-mode=Release-i386 "%~dp0src-native\installer\installer.lpi"
if %errorlevel% neq 0 (
    echo [ERROR] lazbuild Release-i386 failed for the native GUI.
    if /i "%~1" neq "--no-pause" if /i "%~1" neq "/nopause" pause
    exit /b %errorlevel%
)
"%LAZBUILD%" --build-mode=Release-x64 "%~dp0src-native\installer\installer.lpi"
if %errorlevel% neq 0 (
    echo [ERROR] lazbuild Release-x64 failed for the native GUI.
    if /i "%~1" neq "--no-pause" if /i "%~1" neq "/nopause" pause
    exit /b %errorlevel%
)
copy /y "%~dp0src-native\installer\bin\installer-i386.exe" "%~dp0client\UpdateInstallerLegacy.exe"
if %errorlevel% neq 0 (
    echo [ERROR] Failed to copy the i386 binary to client\UpdateInstallerLegacy.exe.
    if /i "%~1" neq "--no-pause" if /i "%~1" neq "/nopause" pause
    exit /b %errorlevel%
)
copy /y "%~dp0src-native\installer\bin\installer-x64.exe" "%~dp0client\UpdateInstallerLegacy64.exe"
if %errorlevel% neq 0 (
    echo [ERROR] Failed to copy the x64 binary to client\UpdateInstallerLegacy64.exe.
    if /i "%~1" neq "--no-pause" if /i "%~1" neq "/nopause" pause
    exit /b %errorlevel%
)

echo.
echo =======================================================================
echo [SUCCESS] The complete WSUS Offline Next ecosystem is built and deployed.
echo  - %~dp0UpdateGenerator.cmd (adaptive launcher entry point, pure .cmd)
echo  - %~dp0UpdateGeneratorModern.exe (.NET 8 modern interface)
echo  - %~dp0client\UpdateInstaller.cmd (adaptive launcher entry point, pure .cmd)
echo  - %~dp0client\UpdateInstallerModern.exe (.NET 8 modern interface)
echo  - %~dp0client\UpdateInstallerLegacy.exe (native Win32 classic interface, Lazarus i386)
echo  - %~dp0client\UpdateInstallerLegacy64.exe (native Win32 classic interface, Lazarus x64)
echo =======================================================================
if /i "%~1"=="--no-pause" goto :eof
if /i "%~1"=="/nopause" goto :eof
if defined CI goto :eof
pause
