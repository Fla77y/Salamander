@echo off
rem Resolve MSBuild from an installed Visual Studio 2026 instance (any edition).
rem Called by build.cmd, rebuild.cmd, and !populate_build_dir.cmd.
set "MSB="
set "VS2026_INSTALL_DIR="

set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
  >&2 echo ERROR: vswhere.exe was not found. Install Visual Studio 2026.
  exit /b 1
)

rem FOR /F passes its command to cmd.exe /c. Running a fully qualified
rem executable path with spaces there needs nested quoting; instead run the
rem executable by name from its installation directory.
pushd "%ProgramFiles(x86)%\Microsoft Visual Studio\Installer" || exit /b 1
for /f "usebackq delims=" %%I in (`vswhere.exe -latest -products * -version "[18.0,19.0)" -requires Microsoft.Component.MSBuild -property installationPath`) do set "VS2026_INSTALL_DIR=%%I"
popd

if not defined VS2026_INSTALL_DIR (
  >&2 echo ERROR: Visual Studio 2026 with MSBuild was not found.
  >&2 echo Install the C++ desktop workload using the repository .vsconfig file.
  exit /b 1
)

set "MSB=%VS2026_INSTALL_DIR%\MSBuild\Current\Bin\MSBuild.exe"
if not exist "%MSB%" (
  >&2 echo ERROR: MSBuild.exe was not found: "%MSB%"
  exit /b 1
)

exit /b 0
