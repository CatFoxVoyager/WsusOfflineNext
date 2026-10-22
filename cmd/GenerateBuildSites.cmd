@echo off
rem =======================================================================
rem WSUS Offline Update - Build Site Propagation Tool (Windows Launcher)
rem File: cmd/GenerateBuildSites.cmd
rem
rem Propagates build definitions from static/builds.ini into 5 build sites.
rem Supports --check for drift detection.
rem =======================================================================

cscript //Nologo "%~dp0GenerateBuildSites.vbs" %*
exit /b %ERRORLEVEL%
