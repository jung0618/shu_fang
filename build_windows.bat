@echo off
REM ============================================================
REM ShuFang Flutter Windows Build Script
REM Auto-configures D:\ VS2022 Build Tools + Flutter SDK PATH
REM ============================================================

setlocal EnableDelayedExpansion

REM D-drive first strategy - no global PATH pollution
set "FLUTTER_HOME=D:\flutter"
set "VS_TOOLS=D:\vs2022cppWindowsBuildTool"

REM Verify dependencies
if not exist "%FLUTTER_HOME%\bin\flutter.bat" (
    echo [ERROR] Flutter SDK not found: %FLUTTER_HOME%
    exit /b 1
)
if not exist "%VS_TOOLS%\VC\Tools\MSVC" (
    echo [ERROR] VS2022 Build Tools not found: %VS_TOOLS%
    exit /b 1
)

REM Configure PATH (D-drive first, Windows SDK uses C-drive system)
set "PATH=%FLUTTER_HOME%\bin;%PATH%"
set "PATH=%VS_TOOLS%\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64;%PATH%"
set "PATH=%VS_TOOLS%\Common7\IDE;%VS_TOOLS%\Common7\Tools;%PATH%"

REM Pub cache on D-drive
if not defined PUB_CACHE set "PUB_CACHE=D:\Hermes\.pub-cache"

REM Enter Flutter project
cd /d "%~dp0"

echo ============================================================
echo  ShuFang Flutter Windows Build
echo  Flutter: %FLUTTER_HOME%
echo  VS Tools: %VS_TOOLS%
echo  PUB_CACHE: %PUB_CACHE%
echo ============================================================

REM Default release mode
set "MODE="
if "%~1"=="" set "MODE=--release"
if /i "%~1"=="debug" set "MODE=--debug"
if /i "%~1"=="release" set "MODE=--release"
if /i "%~1"=="profile" set "MODE=--profile"
if "%MODE%"=="" set "MODE=%*"

call "%FLUTTER_HOME%\bin\flutter.bat" build windows %MODE%

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [FAIL] Build failed
    exit /b 1
)

echo.
echo [OK] Build success
echo Output: %~dp0build\windows\x64\runner\Release\shufang_flutter.exe
endlocal
