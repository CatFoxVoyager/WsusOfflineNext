@echo off
rem *** Author: T. Wittrock, Kiel ***
rem ***   - Next Edition -   ***

verify other 2>nul
setlocal enableextensions
if errorlevel 1 goto NoExtensions

if /i "%PROCESSOR_ARCHITECTURE%"=="AMD64" (set AUT2EXE_EXE=Aut2exe_x64.exe) else (
  if /i "%PROCESSOR_ARCHITEW6432%"=="AMD64" (set AUT2EXE_EXE=Aut2exe_x64.exe) else (set AUT2EXE_EXE=Aut2Exe.exe)
)

echo Compiling the AutoIt legacy installer GUI...
"%~dps0bin\%AUT2EXE_EXE%" /in "%~dps0client\UpdateInstaller.au3" /out "%~dps0client\UpdateInstallerLegacy.exe" /icon "%~dps0ico\wson.ico" /x86 /comp 0 /nopack

rem The generator AutoIt compile lane was removed in Phase 25, in the same
rem commit that deleted its source. The installer twin keeps compiling here
rem until Phase 26 replaces it with the native GUI; that phase also deletes
rem this script, the vendored compiler in bin\ and the Include\ library,
rem ending AutoIt in this repository.
goto EoF

:NoExtensions
echo.
echo ERROR: No command extensions available.
echo.
goto EoF

:EoF
endlocal
