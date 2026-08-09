@echo off
setlocal
set "KCOOP_CHANNEL=playtest"
call "%~dp0Install-KenshiCoop.cmd"
exit /b %ERRORLEVEL%
