@echo off
setlocal
where pwsh.exe >nul 2>&1
if errorlevel 1 (
  >&2 echo ERROR: PowerShell 7.4 or newer is required. Install it with winget install Microsoft.PowerShell
  exit /b 1
)
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Manage-Salamander.ps1" %*
exit /b %errorlevel%
