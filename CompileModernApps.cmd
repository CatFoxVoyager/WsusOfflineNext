@echo off
setlocal
cd /d "%~dp0"

echo =======================================================================
echo [WSUS Offline Next] Compiling v5.2.0+2026.11 Executables
echo =======================================================================
echo.

rem 1. UpdateGenerator.exe
echo [1/4] Building React frontend for WSUS Offline Next Generator...
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

echo [2/4] Publication .NET 8 Single-File de UpdateGenerator.exe...
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
echo [3/4] Build du frontend React de UpdateInstaller...
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

echo [4/4] Publication .NET 8 Single-File de UpdateInstaller.exe...
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
echo Compiling the AutoIt legacy installer GUI (the pure .cmd launchers need no compile)...
call "%~dp0CompileAutoItScripts.cmd"

echo.
echo =======================================================================
echo [SUCCES] L'ecosysteme complet WSUS Offline Next est genere et deploye !
echo  - %~dp0UpdateGenerator.cmd (adaptive launcher entry point, pure .cmd)
echo  - %~dp0UpdateGeneratorModern.exe (Interface moderne .NET 8)
echo  - %~dp0client\UpdateInstaller.cmd (adaptive launcher entry point, pure .cmd)
echo  - %~dp0client\UpdateInstallerModern.exe (Interface moderne .NET 8)
echo  - %~dp0client\UpdateInstallerLegacy.exe (Interface classique AutoIt Win32)
echo =======================================================================
if /i "%~1"=="--no-pause" goto :eof
if /i "%~1"=="/nopause" goto :eof
if defined CI goto :eof
pause
