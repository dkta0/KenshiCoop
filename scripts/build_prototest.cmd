@echo off
REM Build the CRT-only automated layer:
REM   dist\prototest.exe  - packed wire/layout/content tests
REM   dist\sessiontest.exe - host + two-client topology/relay smoke
REM Both use the shipped plugin's v100 x64 compiler.
setlocal

set "REPO=%~dp0.."
pushd "%REPO%" >nul
set "REPO=%CD%"
popd >nul

set "VS10=C:\Program Files (x86)\Microsoft Visual Studio 10.0"
set "VC=%VS10%\VC"
set "SDK=C:\Program Files\Microsoft SDKs\Windows\v7.1"

set "PATH=%VC%\bin\amd64;%VC%\bin;%VS10%\Common7\IDE;%SDK%\Bin\x64;%SDK%\Bin;%PATH%"
set "INCLUDE=%VC%\include;%SDK%\Include;%REPO%\third_party\vc10_compat"
set "LIB=%VC%\lib\amd64;%SDK%\Lib\x64"

if not exist "%REPO%\dist" mkdir "%REPO%\dist"
if not exist "%REPO%\build\prototest" mkdir "%REPO%\build\prototest"
if not exist "%REPO%\build\sessiontest" mkdir "%REPO%\build\sessiontest"

echo === Building prototest.exe (Release^|x64, v100) ===
REM KENSHICOOP_PROTOTEST keeps SaveXfer.cpp CRT-only (its NetLink/engine-coupled
REM sender + quiescence watch are #ifdef'd out) so the real save-transfer RECEIVER
REM (onSaveBegin/onSaveFile/onSaveDone -> stage/verify/commit) can be exercised
REM end-to-end here without pulling in ENet/KenshiLib.
cl.exe /nologo /O2 /EHsc /W3 /D KENSHICOOP_PROTOTEST ^
    /Fo"%REPO%\build\prototest\\" ^
    /Fe"%REPO%\dist\prototest.exe" ^
    "%REPO%\src\prototest\main.cpp" ^
    "%REPO%\src\plugin\sync\Interp.cpp" ^
    "%REPO%\src\plugin\sync\SaveXfer.cpp"
if errorlevel 1 (
    echo prototest build FAILED
    exit /b 1
)
echo prototest built: %REPO%\dist\prototest.exe

echo === Building sessiontest.exe (Release^|x64, v100) ===
cl.exe /nologo /O2 /EHsc /W3 ^
    /Fo"%REPO%\build\sessiontest\\" ^
    /Fe"%REPO%\dist\sessiontest.exe" ^
    "%REPO%\src\sessiontest\main.cpp"
if errorlevel 1 (
    echo sessiontest build FAILED
    exit /b 1
)
echo sessiontest built: %REPO%\dist\sessiontest.exe
exit /b 0
