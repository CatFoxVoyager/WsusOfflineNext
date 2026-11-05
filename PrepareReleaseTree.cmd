@echo off
rem *** Author: T. Wittrock, Kiel ***

verify other 2>nul
setlocal enableextensions
if errorlevel 1 goto NoExtensions

if %1~==~ goto NoParam
set TARGET_DIR="%~f1"
if not exist %TARGET_DIR% goto InvalidParam

rem *** Copy scripts and binaries ***
echo Copying scripts and binaries...
pushd "%~dps0"
xcopy *.* %TARGET_DIR% /E /Q /Y /EXCLUDE:exclude\ExcludeList-ReleaseTree.txt
popd

rem *** Stale legacy exe deletion lane (Pitfall 12) ***
rem *** These four are gitignored build leftovers: exclusion-list entries ***
rem *** cannot be trusted for them (substring semantics), so the staging  ***
rem *** tree is cleaned by explicit deletion - the .orig.exe sweep in     ***
rem *** MakeRelease.cmd only covers that one caller, not standalone use   ***
rem *** (ISO/USB target preparation) of this script.                      ***
del /f /q "%~f1\UpdateGenerator.exe" 2>nul
del /f /q "%~f1\UpdateGeneratorLegacy.exe" 2>nul
del /f /q "%~f1\client\UpdateInstaller.exe" 2>nul
del /f /q "%~f1\client\UpdateInstaller.orig.exe" 2>nul
goto EoF

:NoExtensions
echo.
echo ERROR: No command extensions available.
echo.
goto EoF

:NoParam
echo.
echo ERROR: Missing parameter %1
echo Usage: %~n0 ^<TargetDirectory^>
echo.
goto EoF

:InvalidParam
echo.
echo ERROR: Target directory %TARGET_DIR% not found.
echo Usage: %~n0 ^<TargetDirectory^>
echo.
goto EoF

:EoF
endlocal
