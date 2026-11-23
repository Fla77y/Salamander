# Microsoft dependency and support review — 2026-11-17

Scope: Open Salamander 5.2, `bugfix/v5.2`. This is a **source-level inventory**, not a binary SBOM or an executed clean-VM dependency scan. It does not establish that a component is unsupported merely because its API or project file is old. Product requirements in `Anforderungen.md` prohibit removal of features or changes to UI/control behavior.

## Out of support or explicitly retired

| Component | Evidence in repository | Purpose | Status and replacement decision |
| --- | --- | --- | --- |
| **Visual Studio 2015 C++ toolset v140** | `src/plugins/portables/vcproj2015_manison/portables.vcxproj` declares `ToolsVersion="14.0"`, `PlatformToolset=v140` and SDK `10.0.14393.0`. | An **old, retained** build configuration of the Portables plug-in. | Visual Studio 2015 support ended **October 2025**. This is **not the active solution reference**: `src/vcxproj/salamand.sln` uses `src/plugins/portables/vcxproj/portables.vcxproj` (v143). Keep the old project as archival source if needed; do not add it to active builds. Replace only after parity verification; do not remove source functionality. |
| **Internet Explorer 11 desktop application** | `src/plugins/ieviewer/ieviewer.cpp` embeds `CLSID_WebBrowser`, `IWebBrowser` / `IWebBrowser2` and IE FeatureControl registry keys. | HTML viewing within the IE Viewer plug-in. | The **IE11 desktop application** was retired on many Windows 10 editions **2022-06-15**. **Crucial distinction:** Microsoft's own documentation says embedded `WebBrowser` / MSHTML controls **continue to work** after IE11 desktop retirement. The control itself is not proven out-of-support by this date. Evaluate Edge **WebView2** only as a separately tested, opt-in replacement preserving HTML display, file handling, keyboard controls and original UI. Do not silently replace or remove IE Viewer. |
| **Windows 7 operating system** | `src/plugins/7zip/vcxproj/7zip.props` explicitly targets `WINVER=0x0601`, `_WIN32_WINNT=0x0601`. | Minimum Win32 API feature declarations when building this plug-in, **not** a runtime library and not necessarily the current supported deployment OS. | Standard support ended **2020-01-14**; ESU finished **2023-01-10** (date may differ by product/timezone). The macro is legacy compatibility metadata, not proof that Salamander depends at runtime on a Windows 7 installation. Update it only after testing APIs and compatible behavior on supported Windows targets. |

## Legacy technology: support not conclusively ended

| Component | Evidence | Function | Recommendation |
| --- | --- | --- | --- |
| **Microsoft HTML Help Workshop 1.3 / hhc.exe, CHM** | `tools/Manage-Salamander.ps1` locates `HTML Help Workshop\hhc.exe` and builds the application's compiled help. | Turns `.hhp`, `.hhc`, `.hhk` and HTML into distributable `.chm` help files. | Microsoft calls HTML Help Workshop **1.3** the latest version, and the compiler is documented in archived Microsoft documentation. An explicit, verifiable current end-of-support date was **not established** here. Treat as old and dependency-risky, not categorically unsupported. Preserve CHM output in releases; investigate supported authoring workflows without changing the help UI/format. |
| **MSHTML / WebBrowser ActiveX embedding** | `src/plugins/ieviewer/ieviewer.cpp` and `ieviewer.h`. | Provides the embedded browser surface and COM events. | Windows still retains the control for compatibility according to Microsoft; separate its lifecycle from the retired IE11 desktop app. Security/compatibility review and a faithful WebView2 proof-of-concept are warranted before any migration. |

## In support, despite older version numbers

| Component | Evidence | Status / decision |
| --- | --- | --- |
| **Visual Studio 2026 MSBuild** | `src/vcxproj/find-vs2026.cmd` selects VS installation version **[18.0,19.0)** via `vswhere`; `tools/Manage-Salamander.ps1` resolves the selected MSBuild. | Supported; the Windows 2026-11-17 build log shows MSBuild 18.12.2 was actually used. |
| **MSVC v143 / version 14.44 and VC++ Runtime 14.44** | Active `src/vcxproj/salamand.vcxproj` and plug-in projects specify `PlatformToolset=v143`; `.vsconfig` requests 14.44 x86/x64 and ATL. | **Supported through January 2032** when using the supported servicing baseline. VS 2026 also provides **v145** (14.50+); migration is optional and requires full builds and ABI/packaging tests. Building under VS 2026 with v143 does **not** imply v143 is unsupported. |
| **Windows 11 SDK 26100** | `.vsconfig` selects `Microsoft.VisualStudio.Component.Windows11SDK.26100`; projects request `WindowsTargetPlatformVersion=10.0`. | Modern Windows SDK; choosing `10.0` permits SDK resolution and is not itself an EOL indication. |
| **Visual Studio 2022 solution header** | `src/vcxproj/salamand.sln` contains `# Visual Studio Version 17` and `VisualStudioVersion=17.9...`. | Stale **solution metadata**, not proof that MSBuild 17 is invoked. Move to VS18 metadata in an isolated change with regeneration/build verification if the team wants the solution explicitly stamped for VS2026. |

## Verification and follow-ups

1. Generate a binary dependency inventory from **release** EXE/DLL packages (`dumpbin /DEPENDENTS` and manifest checks) and compare against a clean Windows 11 VM without separately installed VC++ redistributables. This is **not done** in this source review.
2. Enumerate every **active** solution/project file and check that build scripts require VS2026. Historical samples may remain, but must not be built or packaged by default.
3. Preserve full UI behavior and plug-in compatibility when evaluating **WebView2** or a new help toolchain. No automatic replacements.
4. Re-run `manage.cmd --build --test-all --setup` on Windows and verify clean-VM startup before changing any EOL status to resolved.

## Microsoft primary references

- VS 2026 and older VS servicing: https://learn.microsoft.com/en-us/visualstudio/releases/2026/servicing-vs
- MSVC toolset lifecycle and supported 14.50+: https://learn.microsoft.com/en-us/cpp/overview/compiler-versions
- MSVC Runtime and v143 lifecycle: https://learn.microsoft.com/en-us/lifecycle/faq/visual-c-faq
- IE11 desktop retirement: https://learn.microsoft.com/en-us/lifecycle/announcements/internet-explorer-11-end-of-support
- Confirmation that embedded WebBrowser controls continue to function: https://learn.microsoft.com/en-us/microsoft-edge/devtools/ie-mode/
- HTML Help Workshop version information: https://learn.microsoft.com/en-us/previous-versions/windows/desktop/htmlhelp/microsoft-html-help-downloads
- Windows 7 lifecycle: https://learn.microsoft.com/en-us/lifecycle/products/windows-7
