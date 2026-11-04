@echo off
setlocal
cd /d "%~dp0"

echo =======================================================================
echo [WSUS Offline Next] Compiling v5.2.0+2026.11 Executables
echo =======================================================================
echo.

rem 1. UpdateGenerator.exe
echo [1/3] Building React frontend for WSUS Offline Next Generator...
cd /d "%~dp0src-modern\generator"
call npm run build
if %errorlevel% neq 0 (
    echo [ERREUR] Echec de la compilation frontend du Generator.
    if /i "%~1" neq "--no-pause" if /i "%~1" neq "/nopause" pause
    exit /b %errorlevel%
)

rem Garde empty-dist DEPS-07 : refuser un publish sur un frontend vide.
set EMPTY_DIST=0
if not exist "dist\index.html" set EMPTY_DIST=1
dir /b "dist\assets\*.js" >nul 2>&1
if errorlevel 1 set EMPTY_DIST=1
if "%EMPTY_DIST%"=="1" (
    echo [ERREUR] Garde empty-dist : dist\index.html absent ou aucun asset JS dans dist\assets pour le Generator.
    if /i "%~1" neq "--no-pause" if /i "%~1" neq "/nopause" pause
    exit /b 1
)

echo [1/3] Publication .NET 8 Single-File de UpdateGenerator.exe...
dotnet publish host\UpdateGenerator.csproj -c Release -r win-x64 /p:PublishSingleFile=true /p:SelfContained=false -o bin
if %errorlevel% neq 0 (
    echo [ERREUR] Echec de la publication dotnet de UpdateGenerator.
    if /i "%~1" neq "--no-pause" if /i "%~1" neq "/nopause" pause
    exit /b %errorlevel%
)
copy /y bin\UpdateGenerator.exe "%~dp0UpdateGeneratorModern.exe"
xcopy /e /i /y bin\wwwroot "%~dp0wwwroot"

rem 2. UpdateInstaller.exe
echo.
echo [2/3] Build du frontend React de UpdateInstaller...
cd /d "%~dp0src-modern\installer"
call npm run build
if %errorlevel% neq 0 (
    echo [ERREUR] Echec de la compilation frontend de l'Installer.
    if /i "%~1" neq "--no-pause" if /i "%~1" neq "/nopause" pause
    exit /b %errorlevel%
)

rem Garde empty-dist DEPS-07 : refuser un publish sur un frontend vide.
set EMPTY_DIST=0
if not exist "dist\index.html" set EMPTY_DIST=1
dir /b "dist\assets\*.js" >nul 2>&1
if errorlevel 1 set EMPTY_DIST=1
if "%EMPTY_DIST%"=="1" (
    echo [ERREUR] Garde empty-dist : dist\index.html absent ou aucun asset JS dans dist\assets pour l'Installer.
    if /i "%~1" neq "--no-pause" if /i "%~1" neq "/nopause" pause
    exit /b 1
)

echo [2/3] Publication .NET 8 Single-File de UpdateInstaller.exe...
dotnet publish host\UpdateInstaller.csproj -c Release -r win-x64 /p:PublishSingleFile=true /p:SelfContained=false -o bin
if %errorlevel% neq 0 (
    echo [ERREUR] Echec de la publication dotnet de l'Installer.
    if /i "%~1" neq "--no-pause" if /i "%~1" neq "/nopause" pause
    exit /b %errorlevel%
)
copy /y bin\UpdateInstaller.exe "%~dp0client\UpdateInstallerModern.exe"
xcopy /e /i /y bin\wwwroot "%~dp0client\wwwroot"

cd /d "%~dp0"
echo.
echo [3/3] Building the native installer GUI (Lazarus, both architectures)...
rem Toolchain resolution: WO_LAZARUS_ROOT override, else the scratch default.
rem The CI runner installation is Phase 27's lane - until then the lane
rem fails closed with a named error rather than shipping a stale binary.
if not defined WO_LAZARUS_ROOT set "WO_LAZARUS_ROOT=%~dp0.planning\tmp\23-tools\lazarus"
set "LAZBUILD=%WO_LAZARUS_ROOT%\lazbuild.exe"
if not exist "%LAZBUILD%" (
    echo [ERREUR] lazbuild introuvable: %LAZBUILD%
    echo Installez le toolchain Lazarus ou definissez WO_LAZARUS_ROOT. La lane CI est cablee en Phase 27.
    if /i "%~1" neq "--no-pause" if /i "%~1" neq "/nopause" pause
    exit /b 1
)
rem Stale-slot hygiene (Pitfall A / 2026.10 xcopy lesson): delete BEFORE
rem writing; a locked exe must fail named, never silently ship the old GUI.
del /f /q "%~dp0client\UpdateInstallerLegacy.exe" 2>nul
del /f /q "%~dp0client\UpdateInstallerLegacy64.exe" 2>nul
if exist "%~dp0client\UpdateInstallerLegacy.exe" (
    echo [ERREUR] client\UpdateInstallerLegacy.exe est verrouille - fermez toute instance lancee puis relancez.
    if /i "%~1" neq "--no-pause" if /i "%~1" neq "/nopause" pause
    exit /b 1
)
if exist "%~dp0client\UpdateInstallerLegacy64.exe" (
    echo [ERREUR] client\UpdateInstallerLegacy64.exe est verrouille - fermez toute instance lancee puis relancez.
    if /i "%~1" neq "--no-pause" if /i "%~1" neq "/nopause" pause
    exit /b 1
)
"%LAZBUILD%" --build-mode=Release-i386 "%~dp0src-native\installer\installer.lpi"
if %errorlevel% neq 0 (
    echo [ERREUR] Echec lazbuild Release-i386 pour la GUI native.
    if /i "%~1" neq "--no-pause" if /i "%~1" neq "/nopause" pause
    exit /b %errorlevel%
)
"%LAZBUILD%" --build-mode=Release-x64 "%~dp0src-native\installer\installer.lpi"
if %errorlevel% neq 0 (
    echo [ERREUR] Echec lazbuild Release-x64 pour la GUI native.
    if /i "%~1" neq "--no-pause" if /i "%~1" neq "/nopause" pause
    exit /b %errorlevel%
)
copy /y "%~dp0src-native\installer\bin\installer-i386.exe" "%~dp0client\UpdateInstallerLegacy.exe"
if %errorlevel% neq 0 (
    echo [ERREUR] Echec de la copie du binaire i386 vers client\UpdateInstallerLegacy.exe.
    if /i "%~1" neq "--no-pause" if /i "%~1" neq "/nopause" pause
    exit /b %errorlevel%
)
copy /y "%~dp0src-native\installer\bin\installer-x64.exe" "%~dp0client\UpdateInstallerLegacy64.exe"
if %errorlevel% neq 0 (
    echo [ERREUR] Echec de la copie du binaire x64 vers client\UpdateInstallerLegacy64.exe.
    if /i "%~1" neq "--no-pause" if /i "%~1" neq "/nopause" pause
    exit /b %errorlevel%
)

echo.
echo =======================================================================
echo [SUCCES] L'ecosysteme complet WSUS Offline Next est genere et deploye !
echo  - %~dp0UpdateGenerator.cmd (adaptive launcher entry point, pure .cmd)
echo  - %~dp0UpdateGeneratorModern.exe (Interface moderne .NET 8)
echo  - %~dp0client\UpdateInstaller.cmd (adaptive launcher entry point, pure .cmd)
echo  - %~dp0client\UpdateInstallerModern.exe (Interface moderne .NET 8)
echo  - %~dp0client\UpdateInstallerLegacy.exe (Interface classique native Win32, Lazarus i386)
echo  - %~dp0client\UpdateInstallerLegacy64.exe (Interface classique native Win32, Lazarus x64)
echo =======================================================================
if /i "%~1"=="--no-pause" goto :eof
if /i "%~1"=="/nopause" goto :eof
if defined CI goto :eof
pause
