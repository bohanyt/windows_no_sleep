@echo off
setlocal EnableExtensions
title Update Windows No Sleep

cd /d "%~dp0"

echo.
echo ==========================================
echo   Windows No Sleep - Update Local Build
echo ==========================================
echo.

set "CHANNEL=stable"
set "BASE=https://github.com/bohanyt/windows_no_sleep/releases/latest/download"
if not "%~2"=="" goto :usage
if not "%~1"=="" (
  if /I "%~1"=="dev" goto :dev
  if /I "%~1"=="--dev" goto :dev
  goto :usage
)
goto :channel_selected

:dev
set "CHANNEL=dev"
set "BASE=https://github.com/bohanyt/windows_no_sleep/releases/download/dev-latest"

:channel_selected
echo Selected channel: %CHANNEL%
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

mkdir "%STAGE%" >nul 2>nul
if errorlevel 1 goto :fail

echo Downloading GitHub %CHANNEL% build...
call :download WindowsNoSleep.exe || goto :fail
call :download WindowsNoSleep.exe.config || goto :fail
call :download README.txt || goto :fail
call :download SHA256SUMS.txt || goto :fail
call :download BUILD_SHA.txt || goto :fail

call :verify_integrity || goto :fail

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

:verify_integrity
if not exist "%STAGE%\SHA256SUMS.txt" goto :integrity_fail
if not exist "%STAGE%\WindowsNoSleep.exe" goto :integrity_fail
where powershell.exe >nul 2>nul
if errorlevel 1 goto :integrity_fail
powershell.exe -NoProfile -NonInteractive -Command "$ErrorActionPreference='Stop'; try { $lines=[IO.File]::ReadAllLines($env:STAGE+'\SHA256SUMS.txt'); if ($lines.Count -ne 1 -or $lines[0] -cnotmatch '^([0-9a-fA-F]{64})  WindowsNoSleep\.exe$') { throw 'Invalid SHA256SUMS.txt' }; $expected=$Matches[1]; $actual=(Get-FileHash -LiteralPath ($env:STAGE+'\WindowsNoSleep.exe') -Algorithm SHA256).Hash; if (-not [string]::Equals($expected,$actual,[StringComparison]::OrdinalIgnoreCase)) { throw 'EXE SHA-256 mismatch' }; Write-Host 'INTEGRITY PASS: WindowsNoSleep.exe SHA-256 matches SHA256SUMS.txt'; exit 0 } catch { Write-Host ('INTEGRITY FAIL: '+$_.Exception.Message); exit 1 }"
if errorlevel 1 exit /b 1
exit /b 0

:integrity_fail
echo INTEGRITY FAIL: missing EXE, checksum file, or Windows hash tool.
exit /b 1

:usage
echo Usage: "%~nx0" [dev ^| --dev]
echo Default: latest stable non-prerelease release. Use dev before stable publication.
exit /b 2

:fail
echo.
echo UPDATE FAILED.
echo If integrity failed, artifacts\local-current was left untouched.
if exist "%STAGE%" rmdir /S /Q "%STAGE%" >nul 2>nul
echo.
pause
exit /b 1
