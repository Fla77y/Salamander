@echo off
setlocal
set "managePwsh="
for %%I in (pwsh.exe) do set "managePwsh=%%~$PATH:I"
if not defined managePwsh (
  >&2 echo ERROR: PowerShell 7.4 or newer is required. Install it with winget install Microsoft.PowerShell
  exit /b 1
)
"%managePwsh%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Manage-Salamander.ps1" %*
exit /b %errorlevel%
