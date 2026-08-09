@echo off
setlocal
set "KCOOP_INSTALLER=%~dp0Install-KenshiCoop.ps1"
if not defined KCOOP_CHANNEL set "KCOOP_CHANNEL=stable"
echo KenshiCoop %KCOOP_CHANNEL% channel installer/updater
echo.

if not exist "%KCOOP_INSTALLER%" (
  echo ERROR: Install-KenshiCoop.ps1 must be beside this launcher.
  pause
  exit /b 1
)

powershell.exe -NoProfile -Command "$p=[Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent(); if($p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){exit 0}else{exit 1}" >nul 2>&1
if errorlevel 1 (
  echo Requesting administrator access to update the Kenshi mods folder ...
  powershell.exe -NoProfile -Command "$p=Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$env:KCOOP_INSTALLER+'"'),'-Channel',$env:KCOOP_CHANNEL) -PassThru -Wait; exit $p.ExitCode"
  set "RC=%ERRORLEVEL%"
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%KCOOP_INSTALLER%" -Channel "%KCOOP_CHANNEL%"
  set "RC=%ERRORLEVEL%"
)

echo.
if not "%RC%"=="0" echo Installation failed. The existing mod was left in place or restored.
pause
exit /b %RC%
