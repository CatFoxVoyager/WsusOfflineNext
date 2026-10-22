@echo off
rem *** Like MakeRelease.cmd, but does not create a zip archive. ***
rem *** It builds the compiled release tree directly into the     ***
rem *** parent (..) directory, ready to use.                      ***

verify other 2>nul
setlocal enableextensions
if errorlevel 1 goto NoExtensions

rem *** Determine target directory in the parent folder ***
rem *** Avoid clobbering this repo, which is itself named "wsusoffline". ***
if "%1~"=="~" (
  set TARGET_DIR=%~dps0..\wsusoffline-release
) else (
  set TARGET_DIR=%~dps0..\wsusofflineCE%1
)

if exist "%TARGET_DIR%" rd /S /Q "%TARGET_DIR%"
md "%TARGET_DIR%"
if errorlevel 1 goto NoTargetDir

echo Building unzipped release tree in "%TARGET_DIR%"...
call "%~dps0PrepareReleaseTree.cmd" "%TARGET_DIR%"

echo.
echo Done. Unzipped release tree is at:
echo   %TARGET_DIR%
goto EoF

:NoExtensions
echo.
echo ERROR: No command extensions available.
echo.
goto EoF

:NoTargetDir
echo.
echo ERROR: Could not create target directory "%TARGET_DIR%".
echo.
goto EoF

:EoF
endlocal
