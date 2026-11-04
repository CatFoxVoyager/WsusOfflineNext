@echo off
rem *** Author: T. Wittrock, Kiel ***
rem ***   - Next Edition -   ***

verify other 2>nul
setlocal enableextensions
if errorlevel 1 goto NoExtensions

if /i "%PROCESSOR_ARCHITECTURE%"=="AMD64" (set AUT2EXE_EXE=Aut2exe_x64.exe) else (
  if /i "%PROCESSOR_ARCHITEW6432%"=="AMD64" (set AUT2EXE_EXE=Aut2exe_x64.exe) else (set AUT2EXE_EXE=Aut2Exe.exe)
)

echo Compiling AutoIt Legacy GUIs...
"%~dps0bin\%AUT2EXE_EXE%" /in "%~dps0UpdateGenerator.au3" /out "%~dps0UpdateGeneratorLegacy.exe" /icon "%~dps0ico\wson.ico" /x86 /comp 0 /nopack
"%~dps0bin\%AUT2EXE_EXE%" /in "%~dps0client\UpdateInstaller.au3" /out "%~dps0client\UpdateInstallerLegacy.exe" /icon "%~dps0ico\wson.ico" /x86 /comp 0 /nopack

rem The adaptive-launcher compile lane was removed in Phase 24 plan 02: the
rem entry points are now the pure .cmd launchers (UpdateGenerator.cmd and
rem client\UpdateInstaller.cmd), which need no compilation. The superseded
rem .au3 launcher sources stay in the repo, version-frozen, until Phase
rem 25/26 deletes them.
goto EoF

:NoExtensions
echo.
echo ERROR: No command extensions available.
echo.
goto EoF

:EoF
endlocal
