# Open Salamander

Open Salamander is a fast and reliable two-panel file manager for Windows.

## Origin

The original version of Servant Salamander was developed by Petr Šolín during his studies at the Czech Technical University. He released it as freeware in 1997. After graduation, Petr Šolín founded the company [Altap](https://www.altap.cz/) in cooperation with Jan Ryšavý. In 2001 they released the first shareware version of the program. In 2007 a new version was renamed to Altap Salamander 2.5. Many other programmers and translators [contributed](AUTHORS) to the project. In 2019, Altap was acquired by [Fine](https://www.finesoftware.eu/). After this acquisition, Altap Salamander 4.0 was released as freeware. In 2023, the project was open sourced under the GPLv2 license as Open Salamander 5.0.

The name Servant Salamander came about when Petr Šolín and his friend Pavel Schreib were brainstorming name for this project. At that time, the well-known file managers were the aging Norton Commander and the rising Windows Commander. They questioned why a file manager should be named Commander, which implied that it commanded instead of served. This thought led to the birth of the name Servant Salamander.

Please bear with us as Salamander was our first major project where we learned to program in C++. From a technology standpoint, it does not use [C++ Core Guidelines](https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines), smart pointers, [RAII](https://en.cppreference.com/w/cpp/language/raii), [STL](https://github.com/microsoft/STL), or [WIL](https://github.com/microsoft/wil), all of which were just beginning to evolve during the time Salamander was created. Many of the comments are written in Czech, but this is manageable due to recent progress in AI-powered translation. Salamander is a pure WinAPI application and does not use any frameworks, such as MFC.

We would like to thank [Fine company](https://www.finesoftware.eu/) for making the open sourced Salamander release possible.

## Development

### Prerequisites
- Windows 11 or newer
- [Visual Studio Community 2026](https://visualstudio.microsoft.com/downloads/) (or another Visual Studio 2026 edition)
- [Desktop development with C++](https://learn.microsoft.com/en-us/cpp/build/vscpp-step-0-installation) workload and the MSVC v143 (14.44) toolset and matching v143 ATL libraries installed in VS 2026; import the repository `.vsconfig` in Visual Studio Installer
- [Windows 11 SDK (10.0.26100)](https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/) installed in VS 2026

### Optional requirements
- [Git](https://git-scm.com/downloads)
- [PowerShell 7.4](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows) or newer
- [HTMLHelp Workshop 1.3](https://learn.microsoft.com/en-us/answers/questions/265752/htmlhelp-workshop-download-for-chm-compiler-instal)
- Set the ```OPENSAL_BUILD_DIR``` environment variable to specify the build directory. Make sure the path has a trailing backslah, e.q. ```D:\Build\OpenSal\```

### Building

Solution ```\src\vcxproj\salamand.sln``` may be built from within Visual Studio or from the command-line using ```\src\vcxproj\rebuild.cmd```.

Use ```\src\vcxproj\!populate_build_dir.cmd``` to populate build directory with files required to run Open Salamander.

### Build modes (Visual Studio 2026)

Run these commands from the repository root on Windows with PowerShell 7.4+,
Visual Studio 2026/MSVC v143 and the Windows SDK installed:

```cmd
manage.cmd --build-delta
manage.cmd --build
manage.cmd --build-clean
manage.cmd --build-delta --test
manage.cmd --build-clean --test-all
manage.cmd --build-delta --setup
```

- `--build-delta` invokes MSBuild `Build` for Debug and Release x64 and reuses
  unchanged object files, libraries and CHM help when their dependencies have
  not changed. The first invocation also works without prior build outputs.
- `--build` retains its existing behavior: MSBuild `Rebuild` for both x64
  configurations and recompilation of all HTML Help projects.
- `--build-clean` removes the two dedicated x64 build-output directories
  before building both configurations and recompiles HTML Help. It does not
  remove the Git workspace or the separately staged distribution packages.
- `--test-all` executes the existing automated native and GUI test sequence.
  GUI tests require an interactive unlocked Windows desktop.
- `--setup` packages both configurations and verifies distribution content.
  If it is invoked without a preceding build mode, the packaging pipeline
  continues to rebuild both configurations itself.

For direct packaging, `tools/release/Update-Build-Test-Package.ps1` also accepts
`-BuildMode Delta`, `-BuildMode Rebuild` (default), or `-BuildMode Clean`.
The existing `-SkipBuild` switch still bypasses MSBuild and uses present
binaries. Never treat an incremental build alone as a public release
qualification; perform the clean build, full tests, package checks and clean-VM
acceptance before publishing.

#### Diagnosing an unresponsive GUI test

The GUI test driver never sends navigation or destructive input when its
verified Salamander HWND stops responding to read-only `WM_NULL` probes.
Some Windows failures return `LastError=0`; the driver retries these
ambiguous failures, along with timeouts, only until a fixed deadline.

For a **local, opt-in** native stack dump when the test-owned GUI hangs:

```powershell
$env:OPENSAL_GUI_CAPTURE_HANG_DUMP = '1'
try {
    .\manage.cmd --test-gui-temp-delete
}
finally {
    Remove-Item Env:\OPENSAL_GUI_CAPTURE_HANG_DUMP -ErrorAction SilentlyContinue
}
```

#### Investigating sporadic --test-all GUI startup stalls

The normal `manage.cmd --test-gui-temp-delete` runs the Release x64 F8 handler
test directly. In `--test-all`, the same test runs after non-GUI C++,
clipboard, plug-in ABI and WIC regressions; both Release and Debug x64 are
tested. To distinguish a startup problem from a prelude side effect, run a
controlled comparison on an unlocked interactive Windows desktop:

```powershell
.\manage.cmd --diagnose-gui
.\manage.cmd --diagnose-gui --debug
# Optional: change the number of paired runs (default 3)
pwsh -NoProfile -File .\tools\release\tests\Invoke-GuiReliability.ps1 -Iterations 5 -Configuration Release -CaptureHangDump
```

This explicit diagnostic runs the **same one** F8 GUI case both in isolation
and after `--test --test-plugin-exports --test-pictview
--test-pictview-window`, keeping the x64 configuration fixed. It alternates
the order of these scenarios, streams the complete test-prelude output live
while writing individual management logs and a `Summary.csv` under `D:\Build\OpenSal\logs\gui-reliability`, and reports
nonzero exit codes as failures. It refuses to continue if another Salamander
process remains, without killing unknown processes. The diagnostic manager
runs do not copy their nested transcripts to the global clipboard. The GUI
test also restores a captured initially empty clipboard rather than leaving
test text in it.

`--diagnose-gui` explicitly opts in to a locally stored minimal native hang
dump if the GUI stops responding. Dumps are *not* captured by ordinary
`--test-all` unless `OPENSAL_GUI_CAPTURE_HANG_DUMP=1` is explicitly set.
Do not share dumps without reviewing their contents. A/B runs are not
perfectly hermetic because the registry, Windows desktop, clipboard and
filesystem caches are shared. Only a native call stack establishes which
startup function actually blocked; failures must never be converted into
test passes merely by lengthening timeouts.

The driver records a `MiniDumpNormal` file in the current user's TEMP
directory before terminating the isolated test process. Analyze it locally
in WinDbg with Salamander's matching PDBs (for example `~* kb` and
`!analyze -hang`). Dumps may contain private stack data: do not upload
or distribute them without inspecting their contents. No dump is written
by default. A hang is **not** considered a passed test.


### Contributing

This project welcomes contributions to build and enhance Open Salamander!

## Repository Content

```
\convert         Conversion tables for the Convert command
\doc             Documentation
\help            User manual source files
\src             Open Salamander core source code
\src\common      Shared libraries
\src\common\dep  Shared third-party libraries
\src\lang        English resources
\src\plugins     Plugins source code
\src\reglib      Access to Windows Registry files
\src\res         Image resources
\src\salmon      Crash detecting and reporting
\src\salopen     Open files helper
\src\salspawn    Process spawning helper
\src\setup       Installer and uinstaller
\src\sfx7zip     Self-extractor based on 7-Zip
\src\shellext    Shell extension DLL
\src\translator  Translate Salamander UI to other languages
\src\tserver     Trace Server to display info and error messages
\src\vcxproj     Visual Studio project files
\tools           Minor utilities
\translations    Translations into other languages
```

A few Altap Salamander 4.0 plugins are either not included or cannot be compiled. For instance, the PictView engine ```pvw32cnv.dll``` is not open-sourced, so we should consider switching to [WIC](https://learn.microsoft.com/en-us/windows/win32/wic/-wic-about-windows-imaging-codec) or another library. The Encrypt plugin is incompatible with modern SSD disks and has been deprecated. The UnRAR plugin lacks [unrar.dll](https://www.rarlab.com/rar_add.htm), and the FTP plugin is missing [OpenSSL](https://www.openssl.org/) libraries. Both issues are solvable as both projects are open source. To build WinSCP plugin you need Embarcadero C++ Builder.

All the source code uses UTF-8-BOM encoding and is formatted with ```clang-format```. Refer to the ```\normalize.ps1``` script for more information.

## Resources

- [Altap Salamander Website](https://www.altap.cz/)
- Altap Salamander 4.0 [features](https://www.altap.cz/salamander/features/)
- Altap Salamander 4.0 [documentation](https://www.altap.cz/salamander/help/)
- Servant Salamander and Altap Salamander [changelogs](https://www.altap.cz/salamander/changelogs/)
- [User Community Forum](https://forum.altap.cz/)
- Altap Salamander on [Wikipedia](https://en.wikipedia.org/wiki/Altap_Salamander)

## License

Open Salamander is open source software licensed [GPLv2](doc/license_gpl.txt) and later.
Individual [files and libraries](doc/third_party.txt) have a different, but compatible license.
