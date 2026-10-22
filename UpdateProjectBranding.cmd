@echo off
setlocal
cd /d "%~dp0"

echo =======================================================================
echo [WSUS Offline Next] Project Branding and Build Stamping Utility
echo =======================================================================
echo.

python UpdateProjectBranding.py %*
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] UpdateProjectBranding.py failed with exit code %errorlevel%.
    if /i "%~1" neq "--no-pause" if /i "%~1" neq "/nopause" pause
    exit /b %errorlevel%
)

echo.
if /i "%~1" neq "--no-pause" if /i "%~1" neq "/nopause" if not defined CI pause
