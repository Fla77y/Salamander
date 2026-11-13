@echo off

pushd "%~dp0" || exit /b 1

:: Check for command line arguments
if "%~1"=="help" (
  echo Usage: build.cmd [build_config] [build_arch]
  echo.
  echo build_config: Build configuration, default is 'Debug'
  echo build_arch: Build architecture, default is 'x64'
  echo.
  popd
  exit /b 0
)

:: Resolve the VS 2026 MSBuild installation, independently of the shell PATH.
call "%~dp0find-vs2026.cmd"
if errorlevel 1 (
  popd
  exit /b 1
)

if "%OPENSAL_BUILD_DIR%"=="" (
  echo Please set OPENSAL_BUILD_DIR environment variable.
  echo.
  popd
  exit /b 1
)

:: Default values for build_config and build_arch
set build_config=Debug
set build_arch=x64

:: Override default values with command line arguments if provided
if not "%~1"=="" set build_config=%~1
if not "%~2"=="" set build_arch=%~2

call :build "%build_config%" "%build_arch%"
set "BUILD_EXIT_CODE=%errorlevel%"
popd
exit /b %BUILD_EXIT_CODE%

:build
  echo Building %~1/%2
  "%msb%" salamand.sln /t:build "/p:Configuration=%~1" /p:Platform=%2 /m:%NUMBER_OF_PROCESSORS%
  exit /b %errorlevel%
