@echo off
setlocal
set "WNS_PS=%~dp0WindowsNoSleep.ps1"
set "WNS_POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if not exist "%WNS_PS%" (
  echo WindowsNoSleep.ps1 was not found next to this launcher.
  pause
  exit /b 2
)

start "" "%WNS_POWERSHELL%" -NoProfile -STA -WindowStyle Hidden -File "%WNS_PS%"
exit /b 0
