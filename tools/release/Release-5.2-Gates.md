# Open Salamander 5.2 — release acceptance and merge gates

Status: **not yet approved for public release**. Keep the change set in Draft until every applicable gate below has a dated result. A green GitHub check does **not** substitute for testing on a clean end-user machine.

## 1. Automated checks — exact PR head

- [ ] GitHub Actions **PR Build**: Win32 Debug and x64 Debug using `/warnaserror`.
- [ ] GitHub Actions **Product 5.2 and local PictView acceptance commands**: product/version/config-migration contracts; native WIC x86/x64 decoder, GDI, transforms, writer and clipboard.
- [ ] GitHub Actions **Long path regression foundations** and **Package script checks**.
- [ ] GitHub Actions **Release portability packages (Windows 2026)**: Debug/Release rebuilds, compiled help, recursive PE dependencies, runtime staging, 7z integrity checks, both Inno Setup outputs.
- [ ] **Public Release artifact gate**: the GitHub artifact contains exactly `OpenSalamander-Release-x64.7z`, `OpenSalamander-Release-x64-Setup.exe` and `SHA256SUMS-Release.txt`. Run `Test-ReleaseChecksumManifest.ps1 -DistributionDirectory <downloaded-directory> -RequirePublicOnly` after extracting the GitHub artifact ZIP. The new `Test-ReleasePublicArtifact.ps1` regression validates strict contents (including hidden entries) with synthetic payloads; the internal `dist` directory remains permitted to contain private Debug artifacts. Reject any staged `.pdb`, `.lib`, `.exp`, Debug CRTs, or missing `pictview.spl`, `lang/english.slg`, `exif.dll`.
- [ ] The temporary Windows CI runner executes `Test-ReleaseInstaller.ps1` against the just-generated Release installer, installs the executable and required plugin files into a GUID-scoped directory, uninstalls, and confirms removal. **This runner contains development tools and is not a clean VM**.

All checks must target the **same final commit**. Recheck after every code or packaging change.

## 2. Interactive GUI and plugin acceptance on Windows x64

Stop running Salamander instances first; use the matching freshly-built Release binaries. These commands are opt-in because they send real input and may load installed third-party plugins.

```powershell
.\manage.cmd --test-plugin-exports --release
.\manage.cmd --test-pictview
.\manage.cmd --test-pictview-window
.\manage.cmd --test-pictview-host
.\manage.cmd --test-plugin-load
.\manage.cmd --test-all --release
```

- [x] **2026-11-16 19:02 CET**: local `--test-pictview-host` passed for one BMP through F3; verified the exact PictView SPL and native WIC HWND, clean close and unchanged source bytes.
- [x] **2026-11-16 19:10 CET**: local `--test-plugin-load` passed, including the WIC prerequisite and actual Plug-in Manager Test All retaining the 7zip, checksum, filecomp and renamer Release x64 modules; Unicode fixture bytes unchanged.
- [ ] Fresh post-packaging `--test-pictview-window`, complete GUI file operations (F5/F6, rename, delete/recycle restore, Unicode/long-path Find) and `--test-all --release` with logs.
- [ ] A selected BMP, PNG, JPEG, GIF, TIFF (including multi-frame), and ICO opens with F3, correct dimensions/pixels and no modal errors. Verify Save As/export, transform and clipboard actions appropriate to the actually implemented WIC scope.

The original PictView/PVW32 engine is **not fully replaced feature-for-feature**. Legacy proprietary codecs, timed GIF playback, print/capture, and parts of the historical UI are outside the verified WIC scope. Do not claim full legacy equivalence. Document these limitations explicitly in the user-facing release notes or defer the public release if parity is a requirement.

## 3. Mandatory clean Windows 11 x64 release test

Use two **fresh Windows 11 x64 VM snapshots** without Visual Studio, Windows SDK, or a separately installed VC++ redistributable. The GitHub-hosted Windows builder is **not** an acceptable substitute.

- [ ] Snapshot A: download the exact final-head artifact ZIP; verify Release-only SHA-256 manifest locally; extract the Release portable 7z to a disposable user folder. Start `salamand.exe` (no SDK/IDE), browse a few directories, open F1 help, check Plugin Manager and launch representative plugins, F3 PictView for BMP/PNG/JPEG/TIFF, close normally. Check Event Viewer and any missing-DLL dialogs.
- [ ] Snapshot B: run `OpenSalamander-Release-x64-Setup.exe` interactively; verify install path and Start Menu shortcut, launch/F1/F3/plugins, then uninstall and confirm removal of program files and shortcuts. Verify that user data and unrelated installations were not removed.
- [ ] On a snapshot with an existing 5.0 configuration, launch 5.2 and verify the prompt, migration to `HKCU\Software\Open Salamander\5.2`, plugin auto-discovery, preserved 5.0 registry data, and rollback to 5.0.
- [ ] Record date, OS build, final commit SHA, test transcript/screenshots and specific pass/fail outcomes.

## 4. Trust, licensing and provenance

- [ ] Decide the **public Authenticode signing policy** before distribution. `tools/codesign/sign_with_retry.cmd` is currently a placeholder; a successful build does not constitute signed software. If releasing unsigned binaries is explicitly accepted, disclose this fact and likely Windows SmartScreen warning behavior. Otherwise provision a trusted signing certificate and verify signatures on the final EXE, DLL/SPL and installer.
- [ ] Review `LICENSE`, `THIRD_PARTY_LICENSES.txt`, third-party bundled dependencies and their redistributability.
- [ ] Keep Debug builds and Microsoft Debug CRTs for private developer test machines only; no Debug artifacts in public Actions uploads or GitHub Releases.
- [ ] Prepare public 5.2 release notes describing the implemented WIC feature subset and known incompatibilities.

## 5. PR integration order

The open PRs are stacked; do **not** squash or merge PR #11 to `main` in isolation while its bases are still draft:

1. PR #8 — `feature/unicode-plugin-recycle-integration` → `main`
2. PR #9 — `feature/pictview-wic-backend` → `main`
3. PR #10 — `feature/pictview-wic-viewer-integration` → PR #9's branch, then retarget to `main` after PR #9 is integrated
4. PR #11 — `feature/salamander-5.2-pictview-local-acceptance` → PR #10's branch, then retarget to `main` after PR #10 is integrated

The PR #11 branch contains PR #8 ancestry as well; inspect the final main-versus-head diff and rerun required checks after integration of the predecessor PRs. Do not merge or tag before approval of all gates above.

## Decision record

**GO** is permitted only after the exact release artifacts, all required CI jobs, GUI scenarios, clean-machine portable/install/uninstall acceptance, and a signing/scope decision are evidenced. Otherwise status remains **NO-GO**, even if isolated WIC and plugin-load smoke tests pass.
