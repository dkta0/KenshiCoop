@echo off
setlocal
cd /d "%~dp0"
if not defined KENSHICOOP_DISCORD_CLIENT_ID (
  set /p KENSHICOOP_DISCORD_CLIENT_ID="Discord application ID: "
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0KenshiCoop-Presence.ps1"
if errorlevel 1 (
  echo.
  echo Companion stopped with an error.
  pause
)
