# Unicode and long-path implementation strategy

## Scope and baseline

Implement `Entwicklungsauftrag_01.md` in the existing Win32/VS 2026 architecture.
Working baseline: `5303c25ff44aa69da5ae146d36359a36ee8f396d` plus the uncommitted
alias-safe UTF-16 factory changes recorded in `Legacy-Find-UTF16-Migration.md`.
Only this worktree may receive changes or build/test output. No Git mutations,
updates, installations, system policy changes or release are authorized.

Verified working directory:
`C:\Users\mk\.codex\worktrees\0e93\Salamander`, detached HEAD at the commit above.
It has a separate working directory from `C:\Repositories\Salamander`, while
Git objects/common metadata remain shared through the normal linked-worktree
mechanism. `AGENTS.md` was read and applied. The worktree now contains the
intentional uncommitted changes described below; it is not clean.

## Architecture and order

1. **P1, identity and safety:** owned UTF-16 paths, checked dynamic module names,
   exact conversions at legacy boundaries; retain `CFileData` and virtual SDK ABI.
   Fix confirmed buffer defects before extending destructive operations.
2. **P2, core operations:** carry W identities into the existing asynchronous
   worker, retaining progress, cancellation, overwrite/retry and metadata policy.
   Do not remove the current synchronous-transfer size guard in isolation.
3. **P3, legacy Find:** convert existing root/options/worker/result/action chains
   together in tested slices. Preserve `IDD_FIND`, Advanced, masks, regex, grep,
   history/refinement/duplicates and keyboard behavior; no replacement UI.
4. **P4, plugins/archives:** negotiate compatible W services and identities.
   An ANSI archive name is not a filesystem identity. Extraction needs W target
   paths, collision handling, traversal confinement and existing overwrite UI.
5. **P5, integration:** x86/x64 Debug/Release, host GUI/plugin acceptance and clean
   Windows 11 VM qualification. Source checks and native helpers prove only their
   stated contracts. Mark unavailable checks explicitly.

## Migration matrix (17 November 2026)

| Priority / component and call chain | Inspected behavior / restriction | Requirements | Planned correction and compatibility risk | Verification / state |
| --- | --- | --- | --- | --- |
| P1 `Utf16FileName`, `Utf16DiskPath`, `LegacyFindUtf16Identity` factories | Input views could alias cleared output | A1/A2 | Stage ownership before replacing output; no layout change | Previous slice: RED/GREEN, 8 native runs plus 12 regressions |
| P1 `CPluginData::InitDLL` | Previously unchecked `GetModuleFileName`, `char[MAX_PATH]`, `strcpy/strcat`; ANSI loader | A1/A2 | Dynamic W module path and monitored W loader; entry/version/unload contracts unchanged | Implemented; native path/load fixtures and four core builds pass; plugin host GUI acceptance blocked |
| P1 plugin `LoadLanguageModule` -> language selector -> `CLanguage::Init` | Previously reconstructed module/lang paths using fixed ANSI buffers | A0/A1/A2 | W directory identity and loader; existing fallback/selector and validation retained; persisted SLG leaf remains exact ACP | Implemented and built; native resolver tests pass; actual fallback/selector GUI not verified |
| P1 suffix matching / `RemoveNoLongerExistingPlugins` | Previously reconstructed bounded ANSI full names; bad pathname could remove configuration | A1/A2 | Resolve original W path; remove only on confirmed file/path absence, retain on conversion/access/network errors | Implemented; native present/missing fixture and error-policy tests pass; no real user configuration removed |
| P1 SDK `CFileData`, archiver/FS/menu/view interfaces | Public `char*` names/paths and caller buffers | A0/A1/A2 | Explicit negotiated extension and per-entry identity; adding vtable methods or changing existing struct layout is incompatible | Public headers inspected; no extension implemented |
| P2 panel W enumeration -> row sidecars -> `CFileData` | Original W rows exist; ANSI compatibility aliases and guards remain | A0/A1/A2 | Use original row identities throughout selection/filtering/sorting/rendering and navigation | Existing native panel tests; full UI coverage open |
| P2 `TryUnicodeSingleFileTransfer` / batch -> W helpers | Single-file copies above 16 MiB use the existing async worker; small/move/batch guards remain | A0/A1/A2 | Complete recursive/multi/move, filters, Unicode parent navigation and remaining metadata/security matrix | Large-copy slice implemented; execution evidence below |
| P2 recursive file engine / attributes / open/edit | Legacy ANSI and bounded paths coexist with W slices | A0/A1/A2 | Trace worker operations, retries, ACL/ADS/times, cancellation and shell boundaries before conversion | End-to-end audit and tests open |
| P2 Unicode recycle adapters | Shell constraints and temporary fail-closed guards | A0/A1/A2 | Preserve policy, cancellation and restore semantics; never permanent-delete fallback | Native safety tests exist; actual restore/VM acceptance open |
| P3 `FindFile` -> W replacement / legacy `CFindDialog` | Replacement remains regular disk route; original advanced dialog has ANSI roots/worker/actions | A0/A1/A2/A6 | Migrate original chain, then restore regular original-dialog route without losing W coverage | Existing A6 gap; native W Find is not legacy feature parity |
| P4 7-Zip `AddFileDir` -> `GetAnsiString(kpidPath)` -> host archive tree | W archive names collapse through ACP | A0/A1/A2 | Preserve archive index plus original W path; migrate host directory identity and selection, not aliases | Confirmed source conversion; end-to-end correction open |
| P4 7-Zip extract callback -> `TargetFileName[MAX_PATH]` -> safe-file dialog/stream/cleanup | Target composed from ANSI archive names, re-encoded as W, converted back for opening/deletion | A0/A1/A2 | Migrate complete destination/overwrite/stream/cleanup chain with traversal checks | Call chain inspected; dangerous to fix only listing |
| P4 ZIP/TAR/other archive plugins | Separate legacy name/path models | A0/A1/A2 | Audit each format's encoding and host API transitions; retain archive features | Not yet audited end-to-end |
| P4 FTP/virtual FS | Plugin protocol paths differ from disk/extended Windows paths | A0/A1/A2 | Explicit protocol encoding and negotiated host W names; no blind Windows prefixing | Not yet audited end-to-end |
| P4 FileComp/Renamer/Checksum | Legacy plugin paths, some host guards | A0/A1/A2 | Migrate host/plugin operation contract together; preserve ABI and functionality | Not yet verified by actual plugin operations |
| P4 PictView WIC | Existing native WIC implementation | A1/A2/A7 | Preserve WIC; audit host filename handoff rather than decoder-only tests | Unchanged, not tested in this assignment yet |
| P5 `manage.cmd` -> `Manage-Salamander.ps1` | Fixed `D:\Build\OpenSal`, transcript/clipboard side effects | A4 | Use inspected local direct drivers until management output can be explicitly isolated | Not invoked; no shared output writes |
| P5 regular application build | Initial sandbox build failed `C1902`; subsequent regular builds pass | A3 | Actual VS 2026/MSBuild compilation, resources, linking and PDBs; no installed toolchain changes | Core Debug/Release x64/Win32 pass; selected components pass; entire solution/help/release not verified |
| P5 isolated desktop acceptance | Normal driver used real application configuration; authorization requires isolation | A0/A5 | Explicit instrumented build redirects all version roots before discovery; fresh GUID namespace, deterministic English upgrade fixture, native clipboard snapshot, own process only | Release x64 baseline, ASCII operations and four-plugin host smoke pass; additional Debug baseline blocked by desktop focus; full GUI matrix open |
| P5 packaging / clean VM | Independent release qualification | A5 | Reject instrumented test binaries before staging deletion; retain PE/version/inventory checks | Marker and package helper regressions pass; actual setup/7z and clean VM acceptance not executed |

Remaining plugin directories requiring their own end-to-end audit: automation,
checkver, dbviewer, demomenu, demoplug, demoview, diskmap, folders, ieviewer,
mmviewer, nethood, pak, peviewer, portables, regedt, splitcbn, unarj, uncab,
unchm, undelete, unfat, uniso, unlha, unmime, unole, unrar, winscp and wmobile.
Their presence is inventory, not a Unicode compatibility finding.

## Execution record

### Implemented P1 correction

`win32_plugin_module_path.h` reads module names with a bounded growing W buffer,
normalizes ordinary absolute paths, preserves explicit extended-path semantics,
and resolves relative plugin entries beside the actual host module. Language
resources are anchored at the actual loaded module, independently of the process
working directory. This removes the loader's unchecked fixed-buffer construction.
`C__Handles::LoadLibraryW` preserves debug handle bookkeeping and releases its
monitor lock around the Windows loader, retaining the original error afterward.

The host entry/version/initialization/unload path, language fallback and resource
validation stay in place. Existing SDK vtables and `CFileData` layout are untouched.
Debug heap reporting still has a checked ACP/MAX_PATH diagnostic-only boundary;
it is skipped when that diagnostic path does not fit. It never determines I/O.

Remaining limits are explicit: persisted DLL names still use ACP, so already lost
characters in absolute settings cannot be recovered. Language leaves still use
legacy `MAX_PATH` storage and must round-trip exactly through ACP; enumeration
fails explicitly on an unrepresentable leaf rather than loading an alias.
`ReadPluginsVer`, `AutoInstallStdPluginsDir` and other startup/discovery paths in
`plugins2.cpp` still require migration. Thus installing/running the entire host
from every long Unicode directory is not yet verified.

`TryMakeExtendedLengthPath` now owns an aliased input before replacing the output,
complementing the filename/path/Find-identity factory fixes. Invalid-input clearing
and Win32 error contracts remain intact.

### RED and GREEN evidence

| Change | Observed RED | Observed GREEN |
| --- | --- | --- |
| Owned UTF-16 factories | Existing native programs failed on self-aliasing input in all four configurations, eight failing runs | `utf16_disk_path` and `legacy_find_utf16_identity`, eight passing runs |
| Shared Win32 path expansion | In-place Unicode path regression failed at the expected path-expansion assertion in all four configurations | `long_path_io`, four passing runs, including real filesystem I/O |
| Plugin loader/language/configuration removal | New source contract rejected each remaining fixed ANSI loader/language/removal chain before correction | Source contract passes; `plugin_module_path` passes four configurations |
| Isolated GUI configuration | New contract rejected missing opt-in driver/startup isolation | Source contract and `isolated_test_configuration` pass four configurations |
| Test-build release gate | Existing version validator accepted the actual instrumented EXE; direct stage helper deleted its private sentinel before a later unrelated error | Actual instrumented EXE rejected for its marker; normal EXE accepted; staging sentinel preserved on early rejection |

Native `plugin_module_path` tests cover truncation without termination, growth
limits, exact error propagation, invalid/relative/UNC/extended inputs, in-place
ownership, long Unicode paths, strict legacy leaf conversion, suffix matching
and uncertain-versus-missing file status. A real private fixture copies the test
EXE into a long Unicode directory as `.spl`, maps it with `LoadLibraryW`, and
queries that module's actual W path and language directory. Mapping an EXE does
not run a plugin entry point: this is **not plugin host initialization proof**.
UNC syntax tests do not establish live network/share behavior.

Four-config native tests use x86/x64 with Debug `/MDd /Od` and optimized `/MD /O2`,
C++17, `/W4 /WX`, assertions enabled. Seven programs passed, **28 executions**:
`utf16_disk_path`, `legacy_find_utf16_identity`, `plugin_module_path`,
`isolated_test_configuration`, `long_path_io`, `unicode_find`, and
`win32_unicode_primary_panel`. The last two are regressions of existing W slices,
not complete legacy Find or GUI parity tests.

### Executed builds and checks

- VS 2026 Community 18.12.12405.243, MSVC v143 14.44.35207 and Windows SDK
  10.0.26100.0 were verified locally. No installation/upgrade was performed.
- **Regular main executable:** `salamand.vcxproj` `Build`, Debug/Release x64/Win32,
  resources/linking/PDBs included, passed with zero warning/error diagnostics in
  these logs. The initial sandbox `C1902` failure is historical; it no longer
  prevents these builds. Successful execution used x64 MSBuild, explicit tool
  architecture/PATH and the approved host context; the isolated contribution of
  each environment difference was not established.
- **Selected components:** salmon, salspawn, salopen, 7zip, checksum, filecomp and
  renamer, Debug/Release x64/Win32: 28 top-level builds succeeded, including their
  project dependencies. This local verification used `/Z7` and disabled most
  linker PDBs; salspawn/salopen retained the PDBs required by their post-build
  copies. It is not the normal full-solution/release build.
- **Instrumented main executable:** all four configurations built with the
  documented `/p:OpenSalamanderIsolatedGuiTest=true` opt-in. Local `/Z7` settings
  also applied. Default production builds do not contain this hook.
- Passed source checks: `Test-PluginModulePaths-Contract`,
  `Test-HandlesLoaderLock-Contract`, `Test-LegacyFind-UiContract`,
  `Test-VS2026-ProjectMetadata`, `Test-GuiConfig-Isolation`, and
  `Test-GuiDriver-Contract`. The metadata check covers 90 active projects;
  source/UI contracts are static evidence, not runtime GUI acceptance.
- Passed `Test-ProductionBinary-Contract` against the actual instrumented binary,
  synthetic marker inputs and an existing staging sentinel. The normal Release
  and Debug binaries in both x86 and x64 also passed `Test-ProductVersion` and
  the production-marker exclusion gate.
- Passed the existing `Test-Package-Helpers` regression suite: synthetic payloads,
  hashes/export parsing, staging/prerequisite/source contracts, isolated TEMP/TMP,
  and cross-process clipboard tests. No installer or production release ran.
- `Test-ClipboardSnapshot` passed on the authorized desktop: exact Unicode text,
  initially empty clipboard, restoration of the original native formats, and
  unchanged original DIB bytes checked by an in-memory fingerprint. Native
  snapshot capture also passed independently. No clipboard contents were logged
  or saved. The helper copies native handles rather than keeping delayed OLE
  references; unsupported owner/private GDI formats abort before mutation.
- Final checks passed: syntax parsing of all 12 changed/new PowerShell scripts,
  existing-file encoding preservation, new-source UTF-8 BOM/CRLF, and
  `git diff --check`. No unrelated files were cleaned or reverted.

All compiler/linker/test/temp/log paths are within this worktree's ignored
`.Build`. Evaluated MSBuild output and intermediate directories were checked
before building. Main logs: `.Build/utf16-core-normal/build-*.log`; instrumented
logs: `.Build/utf16-core-no-pdb/build-*.log` and `.Build/isolated-core-final.log`;
component logs: `.Build/utf16-core-no-pdb/component-*.log`; native logs:
`.Build/utf16-identity/{red,green}/{x64,x86}/{Debug,Release}`; package log:
`.Build/package-regression-final.log`. Logs/local drivers are untracked artifacts,
not committed reproducibility infrastructure; durable tests are registered in
the existing manager/CI. No new test framework was introduced.

### Initial desktop dependency and next steps

The user authorized a desktop test with isolated Salamander configuration and
backed-up/restored clipboard. `Test-SalamanderGui-LongPaths -IsolatedConfiguration`
now requires the instrumented binary marker before starting. All version roots
redirect to `HKCU\Software\Open Salamander\CodexTests\<fresh GUID>\ConfigN`
before upgrade/configuration discovery. Cleanup is restricted to that namespace,
after the owned process exits. Failure to capture the clipboard prevents launch;
failed clipboard/process cleanup prevents acceptance. Test executables are
rejected by both binary version validation and distribution staging, including
`-SkipBuild` paths, before an existing staging directory can be deleted.

GUI attempts stopped **before application launch** because the pre-existing
foreign process remained present: PID **6292**,
`D:\Build\OpenSal\salamander\Release_x64\salamand.exe`, title
`SalamanderDev - Open Salamander 5.2 (x64)`. The user stated they would close it;
the subsequent read-only check still found it, and a final GUI retry aborted at
the same existing-process preflight. It was neither controlled nor
terminated. This is an environment dependency, not a failed application result.
No isolated application registry configuration was created by those aborted runs.

Next: rerun baseline/ASCII characterization, short Unicode operations, long-path
operations and plugin-load smoke with the foreign instance closed; validate
language fallback through the real host. Then migrate the existing asynchronous
operation data/worker chain in small tested slices. `COperation` is stored in a
raw relocatable `TDirectArray`: adding `std::wstring` members directly would break
its storage contract. Use an owning operation-level sidecar or first establish a
compatible ownership model. Preserve progress/cancel/retry/overwrite and metadata
before relaxing the current 16 MiB synchronous guard. Original Find root, worker,
content-search, results/actions and dispatch follow together, with Advanced,
regex and filters characterized first. Archive/SDK W extensions need compatible
negotiation; changing existing vtables or replacing ANSI names with aliases is
not an acceptable solution.

### Requirements and honest completion state

| Requirement | Current evidence / remaining acceptance |
| --- | --- |
| A0 | Existing UI/resources and plugin ABI retained in this correction; full behavior preservation remains unverified pending real GUI/operations. |
| A1/A2 | Specific factory, module loader and language-directory defects corrected and natively tested. Full core/plugin Unicode and long paths remain **open**; legacy persisted names/SDK boundaries remain. |
| A3 | Four normal main builds and selected component builds pass on VS 2026. All plugins, help, full build pipeline and release remain **not verified**. |
| A4 | New tests registered in the existing manager; source/package contracts pass. `manage.cmd --update/--build/--test-all/--setup` were **not executed**, due fixed shared build outputs and update/installation side effects. No automatic update occurred. |
| A5 | Test-build exclusion and synthetic package regressions pass. Actual clean release setup/7z inventory and clean Windows 11 VM install/start/uninstall are **not verified**. |
| A6 | **Existing HIGH gap:** regular disk Ctrl+F still routes to a replacement W window. Original Advanced/regex/filter feature parity and complete W worker/results/actions remain **open**. No acceptance claim follows from native W search tests. |
| A7 | WIC/proprietary-converter policy unchanged. Real PictView-host loading and the full configured codec/extension matrix are **not tested** in this slice. |

The assignment is **partially implemented and tested**, not fully verified.
The initial GUI dependency above and its later resolution are recorded below;
the remaining matrix records unfinished work before riskier P2/P3 behavior changes.
No commits, branches, staging, updates or original-repository edits were made.

### Follow-up: local GUI startup correction, 17 November 2026

The user ran the local baseline from an elevated PowerShell. The application
displayed its main window and a plugin-install progress window, but the driver
timed out waiting for `Config0`. The screenshot shows `filecomp.spl` installation.
The configuration is saved only after startup/plugin initialization; the missing
key did not prove that the application selected a wrong configuration namespace.
The cleanup's four-second wait also expired and its final exception masked the
primary startup failure. That original process was already gone at subsequent
read-only inspection; it was not terminated by this follow-up.

A non-elevated reproduction with an empty isolated configuration stopped before
the main window, consistent with the locale-dependent first-run language selector.
The previous fixture depended on first-run UI/startup work it had not prepared.

The driver now seeds **only its fresh GUID namespace** with `Language=english.slg`
and configuration version 59, the version from which Salamander reads the language
setting. This deliberately remains older than the current version: real upgrade,
plugin discovery and plugin initialization are still exercised. Readiness requires
the application to write an upgraded version, so merely creating the fixture is
insufficient. A missing built English SLG fails before launch. This fixture tests
an upgrade and subsequent operations, not a wholly unconfigured first run or the
language selector itself.

Startup has a separate bounded `-StartupReadyTimeoutSeconds` (90 seconds by
default, maximum 120); normal operation deadlines remain unchanged. A failed
startup includes a read-only wait-chain diagnostic for a verified owned window.
Cleanup waits up to ten seconds for termination of its own process and retains
the primary GUI failure in any cleanup exception. Failed process termination still
prevents configuration/fixture deletion and cannot yield a passing result.

`Test-GuiConfig-Isolation` first failed on the missing deterministic initialization
and diagnostic contract, then passed after correction. `Test-GuiDriver-Contract`
and `Test-GuiProcessTemp-Isolation` also passed. No production C++ or ABI changes
were needed in this follow-up; existing instrumented binaries were used.
The existing `Test-Package-Helpers` suite passed again after the driver change,
including the authorized native clipboard preservation regressions. Final syntax,
encoding/CRLF and diff checks passed; read-only inspection found no Salamander
test process and zero remaining GUID test namespaces.

Actual non-elevated **Release x64** results:

- `BaselineOnly`: PASS, exact short-path clipboard navigation and keyboard focus.
- `ShortOperationsOnly`: PASS, real ASCII F5 copy, F2 rename, F6 move, F8 deletion
  of disposable test data; original source bytes retained.
- `PluginLoadSmokeOnly`: PASS, the real Plugin Manager's Test All retained the
  exact built 7zip, checksum, filecomp and renamer module paths, and the original
  Unicode fixture bytes were unchanged. This is host initialization proof for
  these four modules, not plugin Unicode operation/format coverage.
- Native clipboard restoration and owned-process/configuration cleanup completed
  in all three successful runs. Logs are `.Build/gui-Release-x64-<scenario>.log`.

An additional **Debug x64** baseline initially timed out during renamer startup
with the old 25-second deadline. A repeat with a 120-second limit completed the
configuration upgrade and startup, then failed safely because another application
held the foreground; no keyboard input was sent. Its result is **environment
blocked**, not PASS. Evidence: `.Build/gui-Debug-x64-BaselineOnly.log` and
`.Build/gui-Debug-x64-BaselineOnly-120s.log`. x86 GUI baselines were not reached.
The cause of the original elevated first-run/plugin stall is not proven resolved;
that case and completely unconfigured first-run behavior remain open. No timeout
or focus guard was disabled and no other application was controlled.

Remaining full migration/requirements status above continues to apply. The
previous foreign-instance block has been cleared; broader Debug/x86, Unicode,
long-path, legacy Find, plugin-operation and PictView acceptance remain open.

### Follow-up: TEMP-independent MAX_PATH transition fixture

The user subsequently reported passing Release x64 `BaselineOnly`,
`ShortOperationsOnly` and `ShortUnicodeOnly`. The latter's exact UTF-16 units
matched the original CJK and supplementary-plane filename even where the console
rendered question marks; its full-path and byte checks also passed.

The user's `LongPaths` run then failed before starting Salamander:
`Nested directory fixture crosses MAX_PATH on Enter`. Fixed 77-unit component
names made a 116-unit source directory grow to 194, 272, 350 and 428 units.
The intended second-level short path was already too long. This was a confirmed
test-fixture defect, not an observed application long-path failure.

`Get-BoundaryDirectoryNames` now derives its first two component lengths from
the actual parent length. The second level is 259 UTF-16 units; the third Enter
crosses MAX_PATH. Four levels, named prefixes, component limits, exact navigation
assertions and byte checks remain in place. Impossible parent lengths fail
explicitly instead of producing negative padding or moving the boundary.

The existing `Test-GuiDriver-Contract` executes the actual fixture assignment
and pure helper without starting a GUI or accessing the filesystem. **RED**:
the original calculation failed with parent length 116 and the lengths above.
**GREEN**: eight parent cases (drive root; 40/80/116/170/225/239-unit bases;
Unicode including a surrogate pair) pass, together with explicit refusal for a
240-unit base. Existing driver message/focus/clipboard/safety contracts pass.
Evidence: `.Build/gui-fixture-red.log` and `.Build/gui-fixture-green.log`.
The regression is already included through the existing manager/CI invocation of
`Test-GuiDriver-Contract`; no new runner, build or test framework is required.

The corrected **real Release x64 `LongPaths` scenario passed with exit code 0**,
PID 2444, non-elevated. It covered all four Enter transitions, the 255-unit
directory component, 441-unit Unicode source navigation, parent traversal,
594-unit clipboard navigation, F5/F2/F6/F8 file operations, same-volume nested
directory move, short-to-long copy and a 255-unit filename, with byte checks.
The existing local `\\localhost\C$` share was accessible: 453-unit UNC navigation
also passed; no share was created or changed. One clipboard-publication mismatch
was handled by the existing bounded safe-write retry; no destructive input was
replayed. Native clipboard restoration, own-process shutdown and fixture cleanup
completed. Log: `.Build/gui-Release-x64-LongPaths.log`.

This corrects the fixture and verifies the stated Release x64 GUI slice. It does
not close Debug/x86, near-32767-unit GUI, complete asynchronous operation/metadata,
legacy Find, all plugin operations, PictView or clean-VM release acceptance.
A0 and A1/A2 have this additional runtime evidence; A3/A4/A5/A6/A7 status otherwise
remains as recorded above. Only test scripts and this report changed in this
follow-up; the existing instrumented application was used without a rebuild.

### Follow-up: background Unicode single-file copy, 18 November 2026

The next authorized slice replaces the synchronous size refusal for **single
regular-file copies larger than 16 MiB** with the existing background copy
worker. A 32-MiB file means exactly 33,554,432 bytes. Small transfers, moves,
multi-selection and recursive operations retain their current routes/guards.

`worker_copy_paths.h` owns original UTF-16 source/target identities in the
`COperations` sidecar. `COperation` is still byte-relocatable and its layout is
unchanged; public `CFileData`, SDK structs and plugin vtables are unchanged.
Its internal char pointers hold deliberately invalid filesystem tokens, so an
unconverted legacy API cannot silently act on an ACP replacement name.
`win32_worker_copy_io.h` binds those tokens to W APIs only within the selected
copy worker's thread scope. Existing original/asynchronous read/write loops,
retry/overwrite policy, progress, pause, cancellation, timestamps, attributes,
ADS and security helpers are reused. Unknown tokens fail closed; source File-ID
is pinned across retries, source mutation is refused, reparse objects and
source/target hard-link identity are checked before destructive I/O. Truncation
is deferred until the opened target handle's identity is validated.

`fileswn8.cpp` prepares the owned script after rechecking panel identity and
source/target type following the confirmation. `dialogs.cpp/.h` retain existing
resources, controls and button handlers. An opt-in W subclass presents full W
path identities in the original progress, overwrite/error and queued-operation
statics. It owns its text, checks UI-thread ownership and restores the original
A/W procedure when detached. This does not replace the original dialogs.

**RED:** the real GUI fixture navigated to the 323-unit source directory and
verified its original Unicode row. Invoking `CM_COPYFILES` (the original F5
handler) then failed with the existing "native Unicode file operation ...
unavailable" guard. Evidence: `.Build/large-unicode-copy-red.log`. Earlier
foreign-focus and Unicode-parent-navigation failures were setup/gap evidence,
not the feature's RED result.

The new driver mode `-LargeUnicodeCopyOnly -LargeUnicodeCopyCase
Copy|Cancel|Collision|LockedSource` uses verified own HWNDs rather than global
keyboard input for the copy/dialog controls. Both directories exceed MAX_PATH;
the name contains accents, CJK and a surrogate pair. The default parent names
are ASCII: optional `-UnicodeParentDirectories` exposes the separate, still-open
W parent-navigation gap instead of hiding it.

The isolated build alone supports GUID-scoped, pre-existing named test events
to hold the worker before the data loop. No polling sleeps determine the
cancellation point. The driver checks the original progress source/target text,
Pause/Resume acknowledgement and cancellation confirmation, then releases the
worker. A 30-second checkpoint timeout cancels; it is never success. Normal
builds contain neither the checkpoint nor configuration redirection. This
intentional test pause can look stationary, but progress UI controls must still
respond. No foreign instance is closed. Native clipboard formats and only the
test's private configuration namespace are restored/removed after each run.

A second actual bug was found in the test driver: PowerShell binds `$null` to
an empty C# string. Dialog lookup consequently required an empty caption and
missed the visible Yes button. `Test-GuiDriver-Contract.ps1` now invokes the real
C# comparison across this boundary, including exact/mismatched Unicode captions.
**RED/GREEN** logs: `.Build/copy-dialog-null-red.log` (exit 1 for that assertion)
and `.Build/copy-dialog-null-green.log` (exit 0). This fix also makes the
completion wait actually observe the absence of the progress dialog.

Verification records for this slice:

| Check | Result / evidence |
| --- | --- |
| `worker_copy_paths`, `worker_copy_io`, `win32_utf16_static_text` | 12/12 native runs pass: Debug/optimized Release, x86/x64, `/W4 /WX`, assertions enabled; `.Build/worker-copy-native-final.log`. Real hard links require the authorized host run; sandbox-denied fixture setup was not counted as RED or pass. |
| Existing `long_path_io`, `unicode_find`, `win32_unicode_primary_panel` | 12/12 runs pass in the same configuration matrix; `.Build/worker-copy-existing-io.log`. |
| Normal main executable | Debug/Release Win32/x64 builds pass with normal PDB settings; `.Build/worker-copy-normal-build.log`. All four version/production-marker gates pass. |
| Isolated main executable | Debug/Release Win32/x64 builds pass; `.Build/worker-copy-build.log`. The real instrumented binary is rejected by the release gate. |
| GUI copy | SHA256 of all 32 MiB, original source, last-write time, read-only flag, exact Unicode ADS name/bytes, full progress text, Pause/Resume and completed worker are checked. |
| GUI negatives | Cancel leaves no target; cancelling the original overwrite dialog preserves existing target bytes; locked-source error displays the original full path and creates no target; every case checks source SHA256. |
| Actual GUI configuration matrix | **12/12 cases pass**: Copy/Cancel/Collision/LockedSource on Release x64, Debug x64 and Release x86. Logs `.Build/large-unicode-copy-<case>-<configuration>-<architecture>.log`. One held-modifier precondition abort was retried only with a fresh fixture before any file command. |
| Debug x86 GUI | **Open:** Copy failed before operation acceptance, waiting for isolated startup configuration upgrade/plugin initialization (PID 5696, no remaining top-level HWND in final diagnostics). Other three cases were not reached. No extra timeout or acceptance waiver was added. Log `.Build/large-unicode-copy-Copy-Debug-x86.log`. |
| Final short-operation GUI regression | F5 copy/source-integrity passed; the full F5/F2/F6/F8 scenario did **not** pass. Driver refused foreground recovery while the original Quick Rename dialog was open; clipboard restored, diagnostic fixture retained. Investigate owned-dialog input/focus before rerunning; do not classify this as a confirmed product rename defect. `.Build/worker-copy-short-operations-final.log`. |
| Native GUI driver/config/reliability contracts | Executed successfully, including compilation of the actual embedded C# interop. |

The three new native tests are registered in the existing `manage.cmd` manager
and in a VS 2026 CI matrix for Debug/Release x86/x64. This is CI configuration,
not a claim that the remote workflow ran. The opt-in GUI command is documented
in README; the local ignored `.Build/Run-IsolatedGui.ps1` also accepts this mode
and `-LargeUnicodeCopyCase`.

Remaining acceptance is explicit: no claim for large moves, multi-file/recursive
transfers, all copy filters, all ACL/EFS/compression/retry/recovery combinations,
UNC/remote large-copy behavior, near-32767-unit GUI paths or concurrent hostile
parent-directory replacement. Saved legacy mask/advanced filters are safely
refused for this newly supported route; source ADS on a target without stream
support are not silently discarded. The legacy 8.3 alias collision is refused
rather than renaming an unrelated DOS-name owner. Unicode parent-directory GUI
navigation, full plugin/archive W contracts and A6's original Find migration
remain separate open work. Queue path display is statically reviewed/built;
the new copy test covers manual Pause/Resume, not a second-operation queue test.

Requirement status: **A0** has this concrete original-dialog/operation evidence,
with full product preservation still open; **A1/A2** have a tested large-copy
slice, not complete migration; **A3** has four local core configurations, not
the full plugin/help/release build; **A4** has manager/CI registration without
running shared-output/update/setup commands; **A5** has test-build exclusion,
not real package/clean-VM acceptance; **A6/A7** are not verified by this change.

At the user's request to close this bounded development slice, no additional
migration work or GUI retries were started. The source is ready for review and
handoff; the two explicit GUI gaps above prevent a "fully verified" claim.
No commit, branch, staging, merge, update or original-repository write occurred.

### Management integration and requested branch handoff

The user subsequently explicitly requested committing/merging the entire
development state into `bugfix/v5.2`. Before that handoff, `--test-all` was
extended with `--test-gui-large-unicode-copy` and `--test-clipboard-snapshot`.
The three new native worker regressions were already in `--test` and therefore
in `--test-all`. The new GUI runner builds only its dedicated instrumented core
under `.Build/isolated-unicode-copy`, validates evaluated OutDir/IntDir before
building, restores process-local environment variables and executes all four
cases. Release/Debug selection follows the existing manager policy. Production
build output and the `manage.cmd` forwarding wrapper need no change.

The real option-expansion regression failed RED for the missing large-copy
option, then passed GREEN after registration/dispatch. The new Release x64
runner actually built and passed Copy/Cancel/Collision/LockedSource. The existing
package/management regression suite and native clipboard snapshot regression
also passed. Logs: `.Build/manage-unicode-copy-red.log`,
`.Build/manage-unicode-copy-green.log`,
`.Build/manage-isolated-unicode-copy-Release.log`,
`.Build/manage-test-all-package-regression.log`,
`.Build/manage-native-clipboard-snapshot.log`.
The entire `manage.cmd --test-all` was not rerun: its existing actions still
write to shared `D:\Build\OpenSal`; the affected dispatch and actual new
subrunner were verified separately. Previously documented GUI gaps remain open.


### Follow-up: Debug x86 startup and F2 driver safety (18 November 2026)

Scope is limited to the two open GUI verification gaps, without changing the
production application, dialog resources, command IDs, plugin SDK or transfer
worker. The previously tested large-copy configurations remain historical
evidence; there is **no new Windows GUI acceptance result** in this follow-up.

**Debug x86 startup:** The only prior observed failure remains the isolated
upgrade/plugin-initialization timeout (PID 5696, no remaining top-level HWND).
The exact native blockage or exit cause was not established. The isolated
startup wait now checks whether the launched process has exited on every poll
and reports its actual exit code rather than treating it as a long-running
upgrade. The failure report additionally captures the isolated
`Config0\Version\Configuration` value, process state, owned top-level windows
and a bounded summary of native thread states. The existing 90-second startup
deadline is unchanged. If `OPENSAL_GUI_CAPTURE_HANG_DUMP=1` is explicitly set
and the test-owned process remains running, the existing private minimal-dump
facility is now available for startup failures even without a main HWND.
No other Salamander process is terminated.

**Short-path F2:** The original F2 handler invokes `CFilesWindow::RenameFile`
and opens `CCopyMoveDialog` (resource `IDD_COPYMOVEDIALOG_CB`, caption
`Quick Rename`, `IDE_PATH=210`, `IDS_SUBJECT=209`). This is distinct
from the separate inline quick-rename edit. The old short GUI baseline sent
Ctrl+A, Ctrl+V and Enter globally after a fixed pause; a foreign foreground
window while Salamander's modal dialog remained open caused a safe abort.
The driver now selects exactly one visible `#32770` dialog belonging to the
launched PID and verified main-window ownership, checks its caption, subject,
ComboBox and OK button, validates the original name, writes the ASCII test
name by bounded HWND-targeted `WM_SETTEXT`, reads it back with `WM_GETTEXT`,
then posts `WM_COMMAND/IDOK` to the verified dialog. An absent, ambiguous,
changed or unresponsive dialog fails without sending global replacement text
or Enter. The product dialog, rename logic and plugin ABI are unchanged.

**RED/GREEN status:** GitHub commit `e41da1f` introduced source-level GUI
regression assertions before these two helpers existed (structural RED);
`6e3fb346` implemented the driver change. Subsequent small commits aligned
the test with the existing `VerifiedChild` ownership check and clarified
PowerShell error-message construction. Read-only post-change source checks
confirmed the intended guard locations, ownership verification, bounded
messages, failure diagnostics and unchanged timeout. No `pwsh`, Windows
native build, interactive GUI or actual x86 debugging was executed in the
available Linux/GitHub-only environment. These checks are **static**, not a
runtime GREEN or proof that the x86 startup issue is fixed.

**Next acceptance:** On a separately authorized unlocked Windows desktop,
run the existing headless `Test-GuiDriver-Contract.ps1` first (it compiles
the embedded interop), then the isolated Debug x86 large-copy `Copy` case
with private build/test outputs and optional private hang dump. Analyze the
dump before changing product loader code if startup still fails. Run
`-ShortOperationsOnly -IsolatedConfiguration` using an isolated Release x64
test executable to recheck F2, F6 and F8; the existing global F5/F6/F8
confirmation inputs are not newly validated by this F2 fix. Preserve any
failure artifacts for review and do not classify either gap as closed until
the corresponding Windows acceptance passes.
