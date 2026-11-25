# Open Salamander 5.2 — release acceptance and merge gates

Status: **not yet approved for public release**. Keep the change set in Draft until every applicable gate below has a dated result. A green GitHub check does **not** substitute for testing on a clean end-user machine.

## RC1 source checkpoint (2026-11-16)

- **Frozen source SHA:** [`ba1a81e893f7b2cf5d54b68ae450af927256891e`](https://github.com/Fla77y/Salamander/commit/ba1a81e893f7b2cf5d54b68ae450af927256891e), branch [`release/v5.2.0-rc.1`](https://github.com/Fla77y/Salamander/tree/release/v5.2.0-rc.1).
- **Local automated evidence, PASS:** `manage.cmd --test-all --setup` on 2026-11-16, transcript `manage-20261116-232423-042-1617a7.log`. The transcript explicitly records this SHA and a clean tracked working tree; all requested steps finished successfully, including native x86/x64 WIC regressions, both x64 build modes, GUI Unicode/long-path operations and four local package outputs.
- **Clean-VM report:** the owner states that testing in a clean VM passed. Details sufficient to check each separate portable, setup, uninstall, 5.0 configuration upgrade and plugin/PictView scenario remain to be attached. This does not by itself close section 3.
- **Approval:** still **NO-GO** pending every applicable gate in this document. RC branch is only a source checkpoint, not a public release or a substitute for an annotated tag. Do not publish Debug packages.

## 1. Automated checks — exact PR head

- [ ] GitHub Actions **PR Build**: Win32 Debug and x64 Debug using `/warnaserror`.
- [ ] GitHub Actions **Product 5.2 and local PictView acceptance commands**: product/version/config-migration contracts; native WIC x86/x64 decoder, GDI, transforms, writer and clipboard.
- [ ] GitHub Actions **Long path regression foundations** and **Package script checks**.
- [ ] GitHub Actions **Release portability packages (Windows 2026)**: Debug/Release rebuilds, compiled help, recursive PE dependencies, runtime staging, 7z integrity checks, both Inno Setup outputs.
- [ ] **Independent Release payload gate (AUD-PKG-0001):** compare the complete stage against `tools/release/Release-Payload.tsv` before generating its internal manifest, verify each non-generated file against its declared origin, and verify the extracted 7z with `Test-PortableManifest.ps1 -ExtractedDirectory <extracted-release> -RequireReleasePayload`. The installer smoke must also enforce the independent installed file set (only the paired Inno uninstaller EXE/DAT may be additional). No automatic expansion of the approved CRT or resource lists. On 51c938b4, package validation and the full regression passed, but the owner reported missing unrar.dll on first clean-VM startup. The independent allowlist omitted a required dynamic dependency. The correction candidate adds a hash-pinned upstream source build, AMD64 DLL and original license, mandatory in both variants, and requires Test All completion plus all declared plugin modules. Re-run packaging and all plugin initialization on Windows; fresh-VM, licensing and RAR function acceptance remain pending.
- [ ] **Public Release artifact gate**: the GitHub artifact contains exactly `OpenSalamander-Release-x64.7z`, `OpenSalamander-Release-x64-Setup.exe` and `SHA256SUMS-Release.txt`. Run `Test-ReleaseChecksumManifest.ps1 -DistributionDirectory <downloaded-directory> -RequirePublicOnly` after extracting the GitHub artifact ZIP. The new `Test-ReleasePublicArtifact.ps1` regression validates strict contents (including hidden entries) with synthetic payloads; the internal `dist` directory remains permitted to contain private Debug artifacts. Reject any staged `.pdb`, `.lib`, `.exp`, Debug CRTs, or missing `pictview.spl`, `lang/english.slg`, `exif.dll`.
- [ ] The temporary Windows CI runner executes `Test-ReleaseInstaller.ps1` against the just-generated Release installer, installs the executable and required plugin files into a GUID-scoped directory, uninstalls, and confirms removal. **This runner contains development tools and is not a clean VM**.

All checks must target the **same final commit**. Recheck after every code or packaging change.

### Verified automated results (16 November 2026)

At commit `fd2a94f1a8ccd88d734b6c392cf662a7fd27cafe`, all six GitHub
Actions workflows completed successfully. The Release workflow rebuilt the
packages, validated the portable payload, performed silent install/uninstall
and compared installed files to the portable payload; its downstream job
downloaded and verified the public GitHub artifact again. The Windows
clipboard contention regressions passed, including sustained-lock refusal.

**Do not treat that SHA as the final release SHA after later documentation,
packaging, or manager updates.** The checkboxes above remain open until the
last source commit has all required checks green. The repository's third-party
notice source is `doc/third_party.txt`; the staged release file is
`THIRD_PARTY_LICENSES.txt`. The stage now requires that file to exist.



### Local evidence (25 November 2026)

Latest local rebuild/package evidence: `manage.cmd --setup` on clean tracked HEAD `1b803c7d87f1d786ee210f93213ecf41df62a02a`, transcript `manage-20261125-190523-943-78cea4.log`, 4:21.197. Debug/Release x64 rebuilds, 11 Win32 SFX language packages, 32 CHM projects, both stages with 33 SPLs and 40 sidecars, pinned UnRAR 7.2.7 DLL/license, exact independent Release payload (280 paths including manifest), origin hashes, extracted 7z validation and both installers passed. The previous full regression on `bf51d3a6` was 132 PASS / 0 FAIL / 33 SKIP, with 33 plugin initializations per configuration. The new UnRAR DLL has a different binary hash; no startup of the new package or installer execution is evidenced by this build. Outer artifact hashes, fresh VM acceptance, final-candidate CI, licensing and signing remain outstanding. No gate is closed. See [PKG-02](../../docs/maintenance/Testluecken-und-Abnahmeplan-5.2.md) and journal J-20261125-34.

On `8c136b618abe727e92243bd215941afb40bbdbb2`, the full automated run reported 130 PASS / 0 FAIL / 35 SKIP, after 50 successful uninstrumented ShellClipboard runs per configuration. On the product-code-identical documentation commit `1d278190fb97fceb5f56669afe687dd521f4fe3a`, the clean-checkout Rebuild/Setup and the explicit plugin-load, native PictView window, six-format F3 host and RecycleRestore runs passed. See [handover](../../docs/maintenance/Arbeitsstand-und-Uebergabe.md#4-aktive-fehler-und-nächste-konkrete-arbeit) for logs, scope and exact results. These are historical results, not verification of the newly implemented independent Release gate or final-candidate CI/VM acceptance.

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
- [x] **2026-11-16 22:08 CET**: a real local Windows desktop
  `manage.cmd --test-all` completed successfully for both **Release x64 and
  Debug x64**, including GUI F2/F5/F6/F8, Unicode Find, clipboard/UNC and
  32,700-unit UTF-16 boundaries. Evidence:
  `manage-20261116-220310-109-0bc2c7.log`. The previous clipboard
  deadlock and Win32 `OpenClipboard` error did not recur.
  The transcript **did not record the git SHA or binary build provenance**;
  this is evidence for the observed GUI execution, not an exact-commit
  attestation.
- [ ] Fresh `--test-pictview-window` and any required opt-in plug-in ABI,
  recycle restore and host-initialization checks on the final candidate, with
  dated evidence. These tests are intentionally not part of `--test-all`.
- [ ] A selected BMP, PNG, JPEG, GIF, TIFF (including multi-frame), and ICO opens with F3, correct dimensions/pixels and no modal errors. Verify Save As/export, transform and clipboard actions appropriate to the actually implemented WIC scope.

The original PictView/PVW32 engine is **not fully replaced feature-for-feature**. Legacy proprietary codecs, timed GIF playback, print/capture, and parts of the historical UI are outside the verified WIC scope. Do not claim full legacy equivalence. Document these limitations explicitly in the user-facing release notes or defer the public release if parity is a requirement.

## 3. Mandatory clean Windows 11 x64 release test

**25 November 2026 — owner-reported functional PASS:** following the rebuild/setup on `1b803c7d87f1d786ee210f93213ecf41df62a02a`, the owner reported that all tests in a clean VM succeeded. This refers to the requested portable startup, installer, Plugin Manager Test All, RAR4/RAR5 open/extract, PictView, F1 and uninstall checks. The earlier missing UnRAR DLL error was not reported again. Exact tested artifact hashes, VM OS build, separate snapshot evidence, per-case logs/screenshots and uninstall cleanup details were not supplied. The final artifact gates, upgrade/rollback, and release approval remain open. See PKG-03/04 and J-20261125-35.

Use two **fresh Windows 11 x64 VM snapshots** without Visual Studio, Windows SDK, or a separately installed VC++ redistributable. The GitHub-hosted Windows builder is **not** an acceptable substitute.

- [ ] Snapshot A: download the exact final-head artifact ZIP; verify Release-only SHA-256 manifest locally; extract the Release portable 7z to a disposable user folder. Start `salamand.exe` (no SDK/IDE), browse a few directories, open F1 help, check Plugin Manager and launch representative plugins, F3 PictView for BMP/PNG/JPEG/TIFF, close normally. Check Event Viewer and any missing-DLL dialogs.
- [ ] Snapshot B: run `OpenSalamander-Release-x64-Setup.exe` interactively; verify install path and Start Menu shortcut, launch/F1/F3/plugins, then uninstall and confirm removal of program files and shortcuts. Verify that user data and unrelated installations were not removed.
- [ ] On a snapshot with an existing 5.0 configuration, launch 5.2 and verify the prompt, migration to `HKCU\Software\Open Salamander\5.2`, plugin auto-discovery, preserved 5.0 registry data, and rollback to 5.0.
- [ ] Record date, OS build, final commit SHA, test transcript/screenshots and specific pass/fail outcomes.

## 4. Trust, licensing and provenance

- [ ] Decide the **public Authenticode signing policy** before distribution. `tools/codesign/sign_with_retry.cmd` is currently a placeholder; a successful build does not constitute signed software. If releasing unsigned binaries is explicitly accepted, disclose this fact and likely Windows SmartScreen warning behavior. Otherwise provision a trusted signing certificate and verify signatures on the final EXE, DLL/SPL and installer.
- [ ] Review `LICENSE`, source notices in `doc/third_party.txt` (staged as `THIRD_PARTY_LICENSES.txt`), third-party bundled dependencies, and their redistributability; presence of notices alone is not approval.
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
