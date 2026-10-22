@echo off
setlocal
python "%~dp0verify-gui-contracts.py"
exit /b %ERRORLEVEL%
