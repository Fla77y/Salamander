@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem Regression: vswhere and Visual Studio are installed under paths containing spaces.
rem The resolver must work independently of the invoking working directory.
set "TEST_DIR=%TEMP%\Open Salamander VS2026 resolver test"
if not exist "%TEST_DIR%" mkdir "%TEST_DIR%"
if errorlevel 1 (
  >&2 echo FAIL: Unable to create test working directory.
  exit /b 1
)

pushd "%TEST_DIR%" || exit /b 1
call "%~dp0..\find-vs2026.cmd"
if errorlevel 1 goto :failed
if not defined VS2026_INSTALL_DIR goto :failed
if not defined MSB goto :failed
if not exist "%MSB%" goto :failed

"%MSB%" -version >nul 2>&1
if errorlevel 1 goto :failed

popd
echo PASS: VS 2026 MSBuild discovery succeeds with spaces in paths.
exit /b 0

:failed
>&2 echo FAIL: VS 2026 MSBuild discovery failed.
popd
exit /b 1
