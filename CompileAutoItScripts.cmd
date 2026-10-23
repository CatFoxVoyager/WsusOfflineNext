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

echo Compiling AutoIt Adaptive Launchers...
"%~dps0bin\%AUT2EXE_EXE%" /in "%~dps0UpdateGeneratorLauncher.au3" /out "%~dps0UpdateGenerator.exe" /icon "%~dps0ico\wson.ico" /x86 /comp 0 /nopack
"%~dps0bin\%AUT2EXE_EXE%" /in "%~dps0client\UpdateInstallerLauncher.au3" /out "%~dps0client\UpdateInstaller.exe" /icon "%~dps0ico\wson.ico" /x86 /comp 0 /nopack
goto EoF

:NoExtensions
echo.
echo ERROR: No command extensions available.
echo.
goto EoF

:EoF
endlocal
