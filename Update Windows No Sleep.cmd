@echo off
setlocal EnableExtensions
title Update Windows No Sleep

cd /d "%~dp0"

echo.
echo ==========================================
echo   Windows No Sleep - Update Local Build
echo ==========================================
echo.

tasklist /FI "IMAGENAME eq WindowsNoSleep.exe" | find /I "WindowsNoSleep.exe" >nul
if not errorlevel 1 (
  echo Windows No Sleep is currently running.
  echo Right-click its tray icon ^> Exit, then run this updater again.
  echo.
  pause
  exit /b 2
)

where curl.exe >nul 2>nul
if errorlevel 1 (
  echo ERROR: Windows curl.exe was not found.
  echo.
  pause
  exit /b 3
)

set "DEST=%~dp0artifacts\local-current"
set "STAGE=%TEMP%\WindowsNoSleep-update-%RANDOM%-%RANDOM%"
set "BASE=https://github.com/bohanyt/windows_no_sleep/releases/download/dev-latest"

mkdir "%STAGE%" >nul 2>nul
if errorlevel 1 goto :fail

echo Downloading latest GitHub dev build...
call :download WindowsNoSleep.exe || goto :fail
call :download WindowsNoSleep.exe.config || goto :fail
call :download README.txt || goto :fail
call :download SHA256SUMS.txt || goto :fail
call :download BUILD_SHA.txt || goto :fail

if exist "%DEST%" rmdir /S /Q "%DEST%"
mkdir "%DEST%"
if errorlevel 1 goto :fail

copy /Y "%STAGE%\WindowsNoSleep.exe" "%DEST%\" >nul || goto :fail
copy /Y "%STAGE%\WindowsNoSleep.exe.config" "%DEST%\" >nul || goto :fail
copy /Y "%STAGE%\README.txt" "%DEST%\" >nul || goto :fail
copy /Y "%STAGE%\SHA256SUMS.txt" "%DEST%\" >nul || goto :fail
copy /Y "%STAGE%\BUILD_SHA.txt" "%DEST%\" >nul || goto :fail

rmdir /S /Q "%STAGE%" >nul 2>nul

echo.
echo Updated successfully to GitHub build:
type "%DEST%\BUILD_SHA.txt"
echo.
echo Launching Windows No Sleep...
start "" "%DEST%\WindowsNoSleep.exe"
exit /b 0

:download
curl.exe -fL --retry 3 --retry-delay 1 -o "%STAGE%\%~1" "%BASE%/%~1"
exit /b %errorlevel%

:fail
echo.
echo UPDATE FAILED.
echo Nothing in artifacts\local-current was replaced unless all downloads completed.
if exist "%STAGE%" rmdir /S /Q "%STAGE%" >nul 2>nul
echo.
pause
exit /b 1
