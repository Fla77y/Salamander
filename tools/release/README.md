# One-command management (Visual Studio 2026)

Start from the repository root in a Windows terminal:

| Command | Effect |
| --- | --- |
| `.\manage.cmd` | List options (also `--help`) |
| `.\manage.cmd --update` | Update **current** branch, fast-forward only |
| `.\manage.cmd --build` | Rebuild x64 Debug and Release and compile all CHM help |
| `.\manage.cmd --test` | Run PowerShell/package validation and Windows path/name tests, plus standalone C++ tests when present |
| `.\manage.cmd --setup` | Rebuild as needed, then create two 7z files and two setups |
| `.\manage.cmd --run` | Start Release, `--run --debug` starts Debug |
| `.\manage.cmd --all` | Update, build, test, setup, run |

Actions can be combined: `.\manage.cmd --update --build --test --setup`.
If `--build` and `--setup` are combined, the packaging step reuses
the successful build instead of compiling again.

**Complete output and diagnostics:** Each invocation writes a PowerShell
transcript under `D:\Build\OpenSal\logs\manage-*.log`. At the end the
**whole transcript, including errors and command output**, is copied to the
Windows clipboard, ready to paste into an issue or a conversation. If
clipboard access is unavailable (e.g. on some CI runners), the log remains on
disk. A failed command returns a nonzero exit code and blocks later actions.

**Test scope:** The `Test-FilenamesAndPaths.ps1` suite validates Windows
file-system capabilities, boundary lengths and byte integrity. It is **not**
a GUI automation suite and does **not** prove Salamander panel/file-operation
or plugin compatibility. The long-path Win32 C++ tests run when their
development-branch sources are available. The complete GUI migration must be
verified separately before calling long-path support complete.

**Prerequisites:** PowerShell 7.4+, VS2026 Desktop C++ + v143/ATL, Windows
SDK; HTML Help Workshop for build; 7-Zip and Inno Setup for packaging.
Debug packages are solely for internal developer-owned test machines.

---

# Windows x64 Debug and Release distributions

The scripts build Open Salamander with Visual Studio 2026 and the existing
MSVC v143 toolset, targeting Windows 11 x64.

## Prerequisites on the build computer

- Visual Studio Community 2026, Desktop development with C++, v143 MSVC x64
  compiler and ATL, Windows 11 SDK and Windows SDK Debug UCRT.
  Import the repository .vsconfig file in Visual Studio Installer.
- Microsoft HTML Help Workshop (hhc.exe) for core and plug-in CHM help.
- 7-Zip with 7z.exe to produce and verify portable archives.
- Inno Setup 6 or 7 (ISCC.exe) for installer generation.
- PowerShell 7.4 or later and Git.
- The MSVC v143 redist and debug_nonredist runtime files.

The script fails if a required tool or runtime is unavailable. It does not
silently publish incomplete packages.

## Run

Open PowerShell in the repository and switch to the feature branch.

~~~powershell
cd C:\Repositories\Salamander
git status
git fetch origin
git switch --track origin/feature/windows-build-and-packages
pwsh -File .\tools\release\tests\Test-Package-Helpers.ps1
pwsh -File .\tools\release\Update-Build-Test-Package.ps1 -BuildRoot 'D:\Build\OpenSal'
~~~

If the branch already exists locally, use:
git switch feature/windows-build-and-packages

The updater only fast-forwards the currently checked-out branch. It refuses
to update a dirty Git worktree, and never switches branches or discards changes.
Use -SkipUpdate when testing uncommitted changes.
Use -SkipInstaller if Inno Setup is unavailable (only the two archives
will be generated).

## Output files

The output directory is D:\Build\OpenSal\dist (unless BuildRoot is changed):

| File | Use |
| --- | --- |
| OpenSalamander-Release-x64.7z | Portable Windows 11 x64 application |
| OpenSalamander-Release-x64-Setup.exe | Per-user x64 installer and uninstaller |
| OpenSalamander-Debug-x64.7z | INTERNAL TEST MACHINES ONLY |
| OpenSalamander-Debug-x64-Setup.exe | INTERNAL TEST MACHINES ONLY |

The archive contains the required application-side MSVC CRT DLLs, so neither
Visual Studio nor a separately installed Visual C++ Redistributable should
be needed on Windows 11. An installer is optional for portable operation:
extract Release and run salamand.exe. The installer uses identical files.

**Microsoft Debug CRT licensing:** Debug binaries and Debug CRT DLLs are not
publicly redistributable. They may be deployed only on your other computers
for the sole purpose of debugging and testing. Never upload the Debug
archive or setup as a public release or customer download. See Microsoft
Learn: "Prepare a test machine to run a debug executable".

## Automated checks

1. Working tree is clean before a fast-forward-only Git update.
2. Both x64 Debug and Release solution rebuilds must succeed.
3. Core and every plug-in HTML Help project must generate a new CHM file.
4. Each package must contain salamand.exe, main help, licenses and matching CRT.
5. Direct PE imports are checked with dumpbin against the application directory
   and the Windows system directory. Debug runtimes are forbidden in Release.
6. A SHA256SUMS.txt manifest is generated for staged distribution files.
7. Each 7z archive is validated by 7z t; each setup must compile with ISCC.
8. Windows CI runs parser and package-validation regression tests.

The pipeline deliberately does not call the existing interactive
!populate_build_dir.cmd or help/src/compileall.bat.

## Mandatory validation in a fresh Windows 11 VM

Direct import checking cannot detect every dynamically loaded DLL and cannot
prove correct UI or shell integration. Do not claim clean-machine compatibility
until the following manual test has passed:

1. Use a clean Windows 11 x64 VM without Visual Studio, development SDKs or
   a separately installed Visual C++ Redistributable.
2. Extract the Release 7z, run salamand.exe and test file browsing, F1,
   the plug-in manager and representative plug-ins.
3. On a separate clean VM snapshot, install the Release setup. Verify launch,
   F1, plug-ins, uninstall and removal of program files and shortcuts.
4. Validate Debug only on a developer-owned isolated test VM; never publish it.
5. Verify the SHA-256 checksums in each package before distribution.

Not all upstream plug-ins are available or buildable because some need
third-party binary dependencies. Only compiled plug-ins plus their required
assets are included.
