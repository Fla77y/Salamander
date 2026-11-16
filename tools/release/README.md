# One-command management (Visual Studio 2026)

Start from the repository root in a Windows terminal:

| Command | Effect |
| --- | --- |
| `.\manage.cmd` | List options (also `--help`) |
| `.\manage.cmd --update` | Update **current** branch, fast-forward only |
| `.\manage.cmd --build` | Rebuild x64 Debug and Release and compile all CHM help |
| `.\manage.cmd --test` | Run PowerShell/package validation and Windows path/name tests, plus standalone C++ tests when present |
| `.\manage.cmd --test-pictview` | Build and run all native WIC regression tests with MSVC x86 **and** x64 locally |
| `.\manage.cmd --test-pictview-window` | Same tests plus an opt-in real WIC HWND/close/lock smoke (requires an unlocked desktop) |
| `.\manage.cmd --test-pictview-host` | Isolated real Salamander F3-to-PictView SPL/HWND smoke with an owned BMP fixture |
| `.\manage.cmd --test-gui` | Create persistent test paths and launch Salamander for manual F5/F6, rename, delete, search and plugin checks |
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
verified separately before calling long-path support complete. Run
`.\manage.cmd --test-gui` after building; it deliberately leaves the
unique test fixture on disk and prints a manual acceptance checklist.
A launched application does not count as a passed GUI test.

## Open Salamander 5.2 / PictView local acceptance

The product and Inno Setup version are 5.2 (build 184). The plug-in SDK
version remains 103 for binary compatibility. The independent PictView plug-in
version is not the Salamander product version.

**5.2 configuration migration:** The application now uses
`HKCU\\Software\\Open Salamander\\5.2` and configuration version **105**,
instead of reusing the legacy `5.0` registry key and version **104**.
The older key remains available for rollback. On the **first interactive
startup** of 5.2, Salamander can offer to import the previous settings;
review the migration dialog before proceeding and do **not** delete the old
settings if you still use an older installation. Following the existing
upgrade path, the new configuration version triggers discovery of the
installed `plugins` directory, including the new PictView WIC module.
It does not rewrite viewer rules on an already migrated 5.2 profile,
nor guarantee that a PictView SPL and its language/dependency files
initialize successfully. Run the normal application once, confirm the
new PictView registration and `*.bmp` viewer mask, then execute the
opt-in F3 host smoke. The smoke itself does not import/delete config.

On your Windows 11 development machine, after checking out this branch:

~~~powershell
.\manage.cmd --update --build --test-pictview
.\manage.cmd --test-pictview-window
.\manage.cmd --test-pictview-host
.\manage.cmd --test
~~~

The first command rebuilds x64 Debug/Release, verifies compiled product
VERSIONINFO, then runs native WIC decode, image presentation, UTF-16 file
decoding, frame navigation, in-memory transforms, image writer and clipboard
tests with MSVC x86 and x64. The second command also opens and closes a
disposable native WIC Win32 viewer and checks its ready/close/lock lifetime.
The third command starts a fresh disposable Salamander process, invokes F3 on the sole BMP fixture, validates the exact PictView SPL and owned WIC HWND, then closes it and checks the source bytes. It is opt-in and refuses to run alongside existing Salamander processes. Its GUI automation requires a trusted plug-in configuration. The final command runs the ordinary project regressions, including a PowerShell
syntax and PictView local-runner registry contract.

`--test-all` includes the WIC native suite and the interactive HWND test,
along with existing Salamander GUI tests. It needs a real unlocked Windows
desktop. To avoid touching other plug-ins, the PictView HWND test runs the
standalone viewer, **not** an in-process Salamander plug-in manager test.
The opt-in real-host F3 smoke covers one BMP on an unlocked desktop; other modes, codecs, actions and saved configurations remain separate release gates.

The F3 host smoke respects the developer's existing Salamander Viewer
associations; it does not silently overwrite registry preferences. In
particular, an external Viewer rule for `*.bmp` can intercept F3 before the
PictView plug-in is loaded. If the dialog reports
`Environment variable "X8D_BIN_TOOLS_PATH" was not found`, this indicates
that a configured external Viewer command references an undefined environment
variable. Do **not** set the variable to a dummy directory: that would test the
wrong Viewer. In Salamander, open **Options > Configuration > Viewers**, assign
`*.bmp` to PictView ahead of matching external rules, and confirm PictView is
installed under **Plugins > Plugins Manager**. The host diagnostic now points
to this configuration problem without changing the environment, registry or
the user's saved Viewer associations. The F3 test must actually open the WIC
viewer to pass.

**Stale plug-in registration:** If **Plugins Manager** reports that
`C:\\X8D\\Bin\\Salamander_5.1\\plugins\\pictview\\pictview.spl`
is not a valid plug-in while testing Salamander 5.2, the manager is
attempting to load a plug-in from the old 5.1-labelled directory, **not**
the current build output. Do not assume that the missing/invalid file
proves a defect in the new WIC module. Remove or correct only the stale
PictView registration and install the PictView SPL from
`D:\\Build\\OpenSal\\salamander\\Release_x64\\plugins\\pictview\\pictview.spl`
(alongside the matching 5.2 `salamand.exe` build). The Release x64
ABI verification `manage.cmd --test-plugin-exports --release` now checks
five plug-ins including PictView for PE architecture and exact SDK
entry-point exports. This **does not** execute the plug-in or establish
that its language/dependency files are present; a real host smoke is
still required afterward.

A second failure mode is a window with native class
`Salamander's Viewer Window` and a caption ending in `test-image.bmp - Viewer`.
This is Salamander's built-in **text/hex viewer**, not PictView. The GUI
host smoke now recognizes this condition immediately and fails with a
specific diagnostic instead of waiting for the WIC HWND timeout. The
presence of `plugins\\pictview\\pictview.spl` beside salamand.exe is
not sufficient proof that PictView is installed in the user's Plugin
Manager or chosen ahead of the default internal `*.*` association.
If PictView is absent, install the SPL via **Plugins > Plugins Manager >
Add** from the same x64 build; then configure the `*.bmp` rule under
**Options > Configuration > Viewers** and save configuration. The host
test must not silently mutate these user preferences.


Test outputs are generated beneath the user's temporary
`OpenSalamander\PictView-Tests` directory unless `-OutputDirectory` is
specified for `Invoke-PictViewTests.ps1`. No test overwrites user files.
The GUI fixture uses a temporary BMP file and removes it afterward. A
non-zero exit code stops the combined management command.

The current PictView WIC migration does **not** implement all proprietary
PVW32 features. Some old codecs, timed GIF playback, EXIF orientation, print,
capture, historical file operations and the legacy viewer UI remain
incomplete. Do not publish this as complete PictView parity without explicit
feature acceptance and clean-host tests.

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
