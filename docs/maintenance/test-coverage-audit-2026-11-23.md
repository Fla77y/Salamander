# Test coverage audit — 23 November 2026

This record separates executed test evidence from source contracts, added but
unexecuted tests, and behavior that remains unimplemented or unverified. A green
\`--test-all\` is **not** a claim of 100% source, branch, UI or plugin coverage.

## Proven baseline (unchanged reference)

- Branch: \`baseline/test-all-pass-2026-11-23\`
- Commit: \`37a5cc595e45c37b32ad8460148717d975bc600b\`
- User-executed Windows transcript: \`manage-20261123-134228-583-ada92b.log\`
- Environment: Windows NT 10.0.26300, PowerShell 7.7.0, Visual Studio 2026.
- Command: \`manage.cmd --test-all\`; completed successfully on 23 November 2026.
- Relevant results: native Unicode/long-path and copy/ADS tests, PictView WIC
  decoder and writer tests on x86/x64, all 36 isolated legacy Ctrl+F scenarios
  on **each** of Release x64 and Debug x64, multi-selection and F2/F5/F6/F8
  GUI actions, 32 MiB copy/cancel/collision/lock, Unicode Find, and a
  32,700-UTF-16-unit GUI path.
- This test run did **not** execute \`--setup\`, an actual clean-VM install, or
  the separately opt-in third-party/real-plugin load tests.

## Added after that baseline (Windows execution outstanding)

| Area | New executable evidence | Limits |
| --- | --- | --- |
| A7 WIC decoder format coverage | \`tools/tests/pictview_wic_formats.cpp\` compiled/executed by \`Invoke-PictViewTests.ps1\` in x86 and x64 and by the PictView WIC CI workflow; tests all 13 extensions from both registrations, a real decoder response and decoded red BGRA pixels, Unicode paths and an extended-length PNG path | Cannot prove the complete in-process plug-in path, animation, thumbnails, or unsupported legacy codecs; JPEG XR depends on the actual Windows WIC codec |
| A7 viewer and thumbnail declaration drift | \`Test-PictView-Management.ps1\` compares the real \`AddViewer\`/\`SetThumbnailLoader\` registrations against the compiled native format table | Static contract alone does not demonstrate GUI behavior |
| A7 PictView host formats | Explicit \`manage.cmd --test-pictview-host --release\` now drives F3 for BMP, PNG, JPEG, GIF, TIFF and ICO in distinct verified child processes, checks SPL/HWND identity and unchanged image bytes | Opt-in, unlocked interactive Windows desktop and compatible PictView associations required; cannot be included unconditionally in \`--test-all\` |
| CI format gate | \`.github/workflows/pr-pictview-wic.yml\` compiles/runs the same format regression on x86 and x64 when the test/decoder changes | A CI success is not a clean end-user VM |

Run these tests on a clean checkout of the new commit before using them as
qualification evidence:

\`\`\`powershell
pwsh -NoProfile -File .\tools\release\tests\Test-PictView-Management.ps1
.\manage.cmd --test-pictview
.\manage.cmd --test-pictview-host --release
.\manage.cmd --test-all
\`\`\`

## Remaining acceptance gaps and risks (not closed)

| Requirement | Gaps not demonstrated by \`--test-all\` | Needed acceptance |
| --- | --- | --- |
| A0 — legacy behavior/UI | Full visual/functional equivalence of old PictView features has **not** been implemented. WIC viewer lacks documented historical operations (e.g. timed GIF playback, editing/undo, print/capture and other older menus). | Product-level decision on preserving/reimplementing the missing legacy behavior, then separate positive GUI tests against the existing UI. Tests cannot implement missing features. See \`docs/pictview-wic-migration.md\`. |
| A1/A2 — all areas and plugins | No universal end-to-end guarantee for every archive/plugin filesystem, plugin SDK ANSI boundary, external viewer, shell integration or all file operations. | Real x64 plugin operation matrix for Unicode/long paths with lossless identity, no collision/overwrite and byte integrity; fix the incompatible ABI boundary instead of claiming it supports all names. |
| A3 — VS 2026 | The successful run exercises the automated native matrix and x64 GUI/core builds. It does not prove all supported x86 plugin/project configurations on the same release SHA. | Clean full solution/component builds for every supported platform and configuration. |
| A4 — manager | CLI/build-mode contracts pass; a standalone \`--test-all\` run does not perform the complete \`--update --build --test-all --setup\` lifecycle. | Run the complete release pipeline in an authorized clean checkout, without treating automatic updates as implicit user consent. |
| A5 — release packages | Portable manifests and package scripts have automated checks, but \`--setup\` and a **fresh Windows 11 VM** portable/install/uninstall are different gates. | Verify two fresh VM snapshots with no VS/SDK/VC++ redist, include plugins, help, first-run, upgrade, installer/uninstaller, and exact artifact hashes. See \`tools/release/Release-5.2-Gates.md\`. |
| A6 — original Find | 72 GUI scenarios passed, but the Legacy Find 32,700-unit result scenario \`NearLimit\`, positive EFS \`EncryptedFixture\`, and full plugin-FS search are not in the automatic suite. | Dedicated isolated GUI runs on an environment that can create those exact fixtures; verify content, identity and all relevant actions, fail rather than silently skip if the acceptance environment is required. |
| A7 — plugin-host and codec matrix | Real F3 format matrix unexecuted; WIC acceptance is codec-dependent. Animated GIF, historical proprietary file formats, transforms/save/menu parity and thumbnail host behavior are not covered end-to-end. | Run the new codec and F3 matrix; add host thumbnail, multi-frame, failure-dialog, repeated-open/close, format availability and legacy parity acceptance. |
| Reliability | Previous isolated GUI startup and focus problems were intermittent; one green run does not establish a failure rate. | Paired repeated GUI test runs using \`--diagnose-gui\` and analysis of failing native wait chains/dumps when available. |

Do not mark these as green simply because the source contains calls, an
earlier build passed, or the fixture cannot be constructed on a host.
Any destructive test must use a unique, verified test-owned path. Positive
Recycle Bin restore, third-party plug-in load and system-specific EFS/VM tests
must retain their explicit environmental controls.
