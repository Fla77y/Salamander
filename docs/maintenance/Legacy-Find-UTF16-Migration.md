# Legacy Ctrl+F Unicode and long-path migration

Scope: `bugfix/v5.2`; requirements 0, 1, 2, 4 and 6 in `Anforderungen.md`.
This document records **work in progress**, not feature completion.

## Invariants

- The original `CFindDialog` created with `IDD_FIND` remains the user interface. No new search window may replace its layout or controls.
- Preserve **Advanced**, attributes, size/date filters, regular expressions, whole-word/case-sensitive/hex text search, search histories/options, ignored paths, duplicate search, refinement (intersect/subtract/append), file operations, sorting and result selection.
- All filesystem identities must originate from Win32 **W** enumeration and retain their exact UTF-16 components. A legacy ACP alias is *never* an authoritative identity.
- No result action may concatenate truncated `char[MAX_PATH]` paths or use a best-fit alias. Guard operations until their UTF-16 implementations exist.
- Maintain independent test coverage for path limits, supplementary-plane characters, identity collisions, cancellation, sorting, selected-result operations, and a regular-expression search that crosses nested directories.
- Continue using the original keyboard shortcuts, resource IDs, visual layout and localization mechanisms.

## Source audit and dependency order

| Subsystem | Current source | Migration requirement |
| --- | --- | --- |
| Ctrl+F route | `src/fileswn5.cpp::CFilesWindow::FindFile` | Currently opens `UnicodeFindWindow` by default for physical disks; after migration, it must directly open **legacy `CFindDialog`** for all roots without losing Unicode coverage |
| Dialog, options and original layout | `src/finddlg1.cpp`, `src/finddlg2.cpp`, `src/find.h` | Keep `IDD_FIND` and every current control, history, advanced filter and command |
| Initial root and directories | `CFindDialog::CFindDialog`, `BuildSerchForData`, `CSearchForData` | Remove ANSI and `MAX_PATH` storage at the root and input validation; reject invalid paths without truncation |
| Search worker | `src/find.cpp::SearchDirectory` and `GrepThreadFBody` | Enumerate with `FindFirstFileW` / `FindNextFileW` and extended-length absolute paths; preserve ignore, masks, recursion, cancellation and error log |
| Search content | `TestFileContent`, `CRegularExpression`, `CSearchData` | Preserve binary, regex, case, whole-word, hex and EOL semantics on W paths; never reinterpret search **content** as a filename |
| Found results | `CFoundFilesData`, `CFoundFilesListView` | Keep actual `std::u16string` directory and filename identities; upgrade the existing result listview to display Unicode faithfully and sort by the real names; maintain viewer enumeration semantics |
| Actions on results | `CFindDialog::OnDelete`, `OnOpen`, `OnViewFile`, drag/drop, clipboard and shell operations | Move to verified W paths, support long paths where the Windows destination API allows, and fail safely on unsupported shell/plugin operations |
| Existing W infrastructure | `src/common/win32_unicode_find.h`, `win32_long_directory.h`, `utf16_disk_path.h` | Reuse tested UTF-16 filesystem traversal where behavior matches the original criteria; do **not** adopt the replacement window or silently discard original search predicates |

## First completed foundation

- `src/common/legacy_find_utf16_identity.h`: validated, owned UTF-16 directory and result name without code-page conversion; rejects invalid components and overlong full paths.
- `CFoundFilesData::UnicodeIdentity`: optional identity populated **only from a future Win32 W record**; legacy ANSI results do not gain an invented identity.
- `tools/tests/legacy_find_utf16_identity.cpp`: stand-alone Unicode, long-path, invalid component and boundary cases.
- `tools/release/tests/Test-LegacyFind-UiContract.ps1`: source-level preservation check for original controls and features; both tests are called from `manage.cmd --test-all`.

**Not complete:** The original dialog is not yet the default Ctrl+F UI. The search worker, editable `Look in` field, result rendering and result actions are still ANSI-based. Reverting the Ctrl+F route at this stage would lose Unicode functionality, so it is deliberately postponed. The new result identity has no effect until the W enumerator and W result actions consume it.

## Required release-gating acceptance tests

1. Ctrl+F opens `IDD_FIND` with original geometry, controls and shortcuts; no `UnicodeFindWindow`.
2. Name/contents search returns exact UTF-16 paths: German umlauts, Japanese and a supplementary-plane character, across nested directories exceeding `MAX_PATH` and near the 32767-unit limit.
3. `Advanced` attribute/size/date filters, regex/hex/whole-word/case options, ignore rules, duplicate/refinement actions and saved options match the pre-migration behavior.
4. Sorting, displayed names, selection, clipboard, open/view/edit/delete and shell/plugin operations cannot target a different file due to ACP substitution, truncation or ambiguity.
5. Cancellation, error reporting and clean shutdown preserve the original threading and dialog behavior.
6. Run the complete `manage.cmd --build --test-all` suite on Windows and an interactive GUI test in a clean Windows VM; record actual results.

Until every acceptance test passes, requirement 6 must remain **open**.

## Runtime characterization before changing the production dialog

`tools/release/tests/LegacyFind-GuiCases.ps1` drives the original `IDD_FIND`
inside an isolated Windows GUI run. On the current branch, the driver uses
**Advanced (legacy)** to open it, closes the separate Unicode window and checks
the original dialog's control IDs before the first query. After the default
changes, the same cases can enter directly. The legacy test fixtures live under
the driver's temporary root. Use a short private root such as a new directory
under `C:\Test`, with process-local `TEMP` and `TMP`.

```powershell
pwsh -Sta -NoProfile -File .\tools\release\tests\Test-SalamanderGui-LongPaths.ps1 `
    -SalamanderExe <isolated-test-build> -IsolatedConfiguration -LegacyFindScenario Baseline
```

The baseline covers actual results for name masks, root lists, recursion,
plain/whole-word/case-sensitive/regex/hex content search, Advanced attributes,
size and date/time filters, refinement, duplicate criteria, saved searches,
directory exclusions, sorting, selection, clipboard, focus navigation, input
validation and the error log for a missing root. Absolute dates and times are
seeded through the isolated profile, round-tripped through Advanced and used by
the real search worker. The archive checkbox is hidden in this branch.
Ordinary Advanced Cancel retains the applied criteria. Reset followed by Cancel
currently clears the criteria immediately. Append retains overlapping matches.

Run `Cancel`, `AdvancedInputs`, `ViewResults` and `ShellClipboard` separately
for the active stop/restart sequence, edited date/time limits, actual NTFS
compression, internal viewer navigation and Shell file-drop formats. `Cancel`
uses a GUID-scoped event pair compiled only into the isolated GUI test binary.
The worker checkpoint precedes enumeration. Stop uses the original dialog
command and releases the checkpoint after recording the cancellation request.
The date fixture uses the same current-offset FILETIME convention as the
legacy filter, including when the requested date is in a different DST season.

`EncryptedFixture` accepts a pre-existing disposable encrypted ASCII-named
`.txt` under `C:\Test` via `-LegacyFindEncryptedFixture`. It checks include
and exclude against the real attribute and never creates EFS keys or writes to
the supplied file. The ordinary baseline tests the same filter on an
unencrypted file.

Run `UnicodeName`, `UnicodeResult`, `UnicodeDistinct`, `UnicodeFeatures`,
`UnicodeSettings`, `UnicodeRoot`, `LongRoot`, `LongDescendant`, `LongResult`,
`NearLimit` separately in place of `Baseline`.
These are positive assertions for the target behavior. Failed assertions stay
red until the corresponding production feature works. The name/result
cases distinguish an exact Unicode name
mask from finding and copying an exact Unicode identity via a plain mask.

`DefaultDialog` and `DefaultDialogLongRoot` verify that the main Find command
opens `IDD_FIND` directly with the complete active panel directory in Look
in. `DefaultDialogShortcut` and `DefaultDialogAltF7` cover the actual shortcuts
on an interactive desktop. `UnicodeFindCommand` and `UnicodeFindShortcut` cover
the secondary command and its keyboard shortcut.

`LongResult` keeps the root below `MAX_PATH` and crosses it only with the
filename. `NearLimit` requires a real 32,700-UTF-16-unit fixture. A filesystem
error before enumeration is a blocked fixture, not a red product result.
Open verification still includes the positive EFS fixture, external editor and
Shell associations, deletion/recovery, plugin boundaries, and near-limit
acceptance on a suitable disposable Windows desktop.

### Windows verification on 19 November 2026

- `Baseline`, `Cancel`, `AdvancedInputs`, `ViewResults` and `ShellClipboard`
  passed on Release x64 and Debug x86 using disposable files under `C:\Test`.
  The baseline also verifies saved settings, history and editing the ignore list.
- Ten target cases, including `DefaultDialog`, failed as intended on both
  architectures. For example, the
  distinct-name fixture returned one of four expected files, and the combined
  Unicode/long-path Advanced query returned zero of two expected files.
- `NearLimit` was blocked at fixture construction. The local `C:\Test` run
  failed to create a 2,290-unit directory with Win32 error 998 before any search.
  `EncryptedFixture` was checked for refusal when no fixture is supplied. Its
  positive EFS run remains open.
- The four isolated Debug/Release x86/x64 core builds passed. Regular
  Release x64 and Debug x86 core builds passed and did not contain the Find
  checkpoint. The ordinary lookup, filtering and routing code was not
  changed in this test phase.

### Migration boundaries confirmed during test preparation

- `CDialog::Create` already supports `CreateDialogParamW`. Selecting that path
  for `IDD_FIND` requires checking owner-data ListView notification encoding
  and the ACP-only combo history accessors together. A W edit control alone
  does not prevent best-fit conversion in the later validation/transfer path.
- Keep root parsing and mask matching separate from text-content matching.
  The baseline covers semicolon escaping, multiple roots, exclusions and
  bare-name substring masks. Preserve these when moving root/mask identities
  to UTF-16. Send the original W path to file-open APIs while retaining the
  original byte-oriented contents, grep, regex and hex semantics.
- `CFindOptionsItem` retains fixed ACP buffers and a manager that copies items.
  Review those copy operations and registry I/O before adding owned UTF-16
  settings and histories. Read prior settings losslessly and check the
  representability boundary before handing W-only paths to legacy clients.
- A result's owned W identity must survive filtering, duplicate grouping,
  refinement, sorting and clipboard. Navigation, viewer enumeration and
  destructive actions require the same verified identity. Keep SDK layout
  and compatibility constraints at the Shell/plugin boundary.

### UTF-16 query input and settings on 20 November 2026

- The original dialog now uses a Unicode message loop and owned UTF-16
  strings for Named, Look in, and the corresponding histories and presets.
  The existing registry values are read and written as wide REG_SZ, including
  values written by previous ANSI versions. Histories are copied under a lock
  before sending combo-box messages. The owner-data result list retains its
  ANSI notification contract for this stage.
- The parser preserves escaped semicolons, separates roots and retains each
  root in the worker's query data. At the ANSI worker boundary, a root must
  round-trip through ACP and fit together with its separator and wildcard.
  The temporary ANSI mask boundary also checks round-trip equality.
- The native test reproduced a malformed UNC root becoming a current-drive
  root during trailing-separator normalization. The fix preserves the UNC
  prefix. The same native test covers mixed roots, Unicode, escaped
  semicolons and paths beyond MAX_PATH.
- Regular and isolated core builds passed on VS 2026 with v143 14.44.35207
  and SDK 10.0.26100.0 in Debug and Release on Win32 and x64. The native
  query/identity test passed in all four configurations. The legacy UI and
  GUI-driver source contracts passed.
- Added GUI scenarios for the registry-backed Unicode preset round trip
  (`UnicodeSettingsStorage`), Shell properties, and an isolated external
  editor probe. The baseline also exercises a root list beyond MAX_PATH
  containing individually short roots. When invoked directly, the editor
  probe saved its designated file and rejected a different fixture.
- An existing Salamander instance in the desktop session prevented the GUI
  driver from launching its own instance in the final Release x64 run.
  The new GUI scenarios and the
  baseline after the change are pending. Positive EFS, Shell associations,
  deletion/recovery and plugin acceptance are still open.
- Retrying `NearLimit` with explicit extended prefixes failed at 2,497 units
  with Win32 998 before search. A separate run of `win32_max_path.cpp` under
  C:\Test also failed in native directory creation with Win32 998. Both are
  environment failures during fixture construction.
- The next implementation boundary is wide enumeration and file opening in
  the original worker, followed by exact result identities throughout result
  rendering and actions. Ctrl+F dispatch still uses the separate search window.

### GUI acceptance after the desktop became available

- `UnicodeSettingsStorage` reproduced the UTF-16 loss before saving. The two
  edits still installed the legacy ANSI Backspace handler. Using a Unicode
  subclass and UTF-16 word-break callback for Named and Look in eliminated
  the narrowing and kept the legacy word delimiters.
- Release x64 and Debug Win32 each passed 120 checks in `Baseline`.
  `UnicodeSettingsStorage` passed in both configurations, including full
  root-list and name-mask registry values, history and Unicode character
  input through the original dialog's message loop.
- `AdvancedInputs`, `Cancel`, `ViewResults`, `ShellClipboard`,
  `ExternalEditor`, `ShellProperties`, `ShellOpen` and `RecycleRestore`
  passed on both configurations with isolated data under C:\Test. The Shell
  Open test launches a disposable shortcut. The recycle test restores only
  the file with the exact expected original path.
- Positive EFS, plugin integration and the 32,700-unit real-path run remain
  open. The current GUI results cover dialog input and saved data. The
  worker still requires a representable ANSI mask and root.
- The ten target scenarios still failed as expected on Release x64. Name,
  root and saved-option queries reached the original dialog and were
  rejected at ANSI validation. Enumeration produced zero matches in the
  long-path and combined-filter checks, and one of four exact names in the
  distinct-Unicode fixture. `DefaultDialog` confirmed the current routing.
- In the GUI suite, the original dialog is identified by class and its
  Look in and result controls. The earlier Ctrl+F route was used to reach
  Advanced (legacy), and the separate window is closed before the original
  dialog's behavior is tested. The dispatch check required the original
  dialog to open immediately.

### Legacy Find as the default

- Ctrl+F, Alt+F7 and the main Find command open the original `IDD_FIND`
  directly. Alt+Shift+F7 opens the separate Unicode Find window. The
  existing plug-in search hook is still consulted for plug-in panels.
- The active disk directory reaches Look in as UTF-16, including long
  paths. The legacy ANSI worker still applies its existing search-time
  validation. The separate Unicode Find scenario exercises its own shortcut.
- The Legacy GUI scenarios now require `IDD_FIND` immediately. Before changing
  dispatch, both Ctrl+F checks failed because the separate window opened.
  The long-path test reached a 327-unit panel path before reporting the
  wrong dialog.
- Release x64 and Debug Win32 passed the real Ctrl+F shortcut, the legacy
  and Unicode command tests, and the 327-unit Look in check. Both also
  passed 120 baseline checks and the nine additional legacy scenarios in
  isolated fixtures under C:\Test.
- Regular VS 2026 core builds passed in Debug and Release on x64 and Win32.
  Both F7 accelerators were checked in the compiled resources of all four
  builds. The Legacy UI and GUI-driver contracts and the Find checks in
  the package-helper script passed.
- The real Alt+Shift+F7 shortcut passed in Release x64 and Debug Win32. The
  real Alt+F7 check passed in Debug Win32. On Release x64 it was unstable
  across interactive runs. The compiled accelerator and the destination
  command were verified on both architectures.
- The Unicode Find functional suite uses background window messages for
  navigation and result selection. Clipboard checks verify publication
  and exact contents. The rename dialog is identified by its owner and
  controls, and cleanup waits for the search window handle to be destroyed.
  The complete suite passed 58 checks each on Release x64 and Debug Win32.
- A0 was checked through the legacy regression suite. A6 default dispatch
  was verified. A1/A2 and the worker portion of A6 remain open. A3 was
  checked for the core builds. Full manage.cmd, release packaging and
  PictView verification (A4, A5, A7) were outside this check.

## 17 November 2026: alias-safe owned identities

Verified on the uncommitted worktree changes based on
`5303c25ff44aa69da5ae146d36359a36ee8f396d`, in
`C:\Users\mk\.codex\worktrees\0e93\Salamander`.

The owned-path factories previously cleared their output before reading the
input view. Revalidating `name.Value()` or `path.Value()` into the same object
therefore lost the original UTF-16 identity. `LegacyFindUtf16Identity::TryCreate`
also invalidated views into its own directory/name fields before validation;
heap-backed fields could become dangling views.

The factories now retain input before replacing its owner. Invalid input still
clears the old output and reports the original validation error. This changes
neither `CFileData` nor the plug-in ABI, search predicates, dialog resources or
Ctrl+F dispatch. It does not connect the legacy worker to W enumeration yet.

### Executed verification

- **RED:** both existing native test programs, `utf16_disk_path.cpp` and
  `legacy_find_utf16_identity.cpp`, reproduced the aliasing failure in x86/x64,
  with Debug and Release runtime/optimization settings (8 failing executions).
- **GREEN:** both programs passed in all four configurations after the fix,
  including additional substring, split-surrogate, output-clearing and precise
  error checks. Existing Unicode, UNC, component-length and 32767-unit namespace
  boundary checks also passed. Assertions remained enabled in optimized tests.
- **Regression:** `long_path_io.cpp`, `unicode_find.cpp` and
  `win32_unicode_primary_panel.cpp` passed in all four configurations (12 more
  executions). Filesystem fixtures stayed below the worktree and were cleaned
  by their respective tests. These are native tests, not GUI acceptance.
- **Source contracts:** `Test-LegacyFind-UiContract.ps1` and
  `Test-VS2026-ProjectMetadata.ps1` passed. The former checks feature presence;
  it does not prove original-dialog dispatch or runtime feature parity.
- **Toolchain:** VS 2026 18.12, MSVC v143 14.44.35207, Windows SDK 10.0.26100.0;
  native tests used C++17, `/W4 /WX`, `/MDd /Od` and `/MD /O2`.
- **Regular core build:** Debug x64 failed with compiler error `C1902`
  (program database manager) while using the repository's `/ZI` setting.
  No normal Release or Win32 build was reached. This is an unresolved build
  verification failure; no toolchain repair or installation was performed.
- **Supplementary compile:** all C++ core sources compiled successfully through
  MSBuild target `ClCompile` in Debug/Release x64/Win32 with an ignored local
  props override selecting `/Z7`. This excludes linking, full resources,
  plug-in builds, help, packaging and runtime/GUI acceptance; it is not a
  successful regular full build.

Every build/test output, temporary file and local driver is under the ignored
`.Build` directory in this worktree. Evaluated MSBuild output and intermediate
paths were checked before compilation. Native logs are in
`.Build/utf16-identity/{red,green}/{x64,x86}/{Debug,Release}`; the failed regular
build log is `.Build/utf16-core/build-Debug-x64.log`; supplementary compile logs
are in `.Build/utf16-core-no-pdb`. Existing source encodings and CRLF were
preserved. `manage.cmd` was inspected but not invoked because its manager fixes
the output root at `D:\Build\OpenSal` and can modify the global clipboard.
The two extended test programs remain registered in its existing `--test` gate.
No update, installation, branch creation, commit or original-repository edit
was performed.

### Remaining work and dependency order

1. Establish an isolated regular full build and an authorized disposable GUI
   acceptance environment. Preserve the current advanced-search predicates in
   behavior tests before changing their inputs or enumeration.
2. Migrate `CSearchForData`, `BuildSerchForData` and the existing root edit control
   to owned W roots without truncation; preserve histories, multiple roots,
   validation and saved options.
3. Migrate `SearchDirectory` and file-content opening to W paths while retaining
   original masks, ignored paths, recursion, cancellation, error logging, regex,
   hex, case and whole-word semantics. Populate result identities from W records.
4. Migrate the existing result list rendering/sorting and result actions to those
   identities, including refinement/duplicates, clipboard, open/view/edit/delete,
   drag/drop and shell/plugin boundaries. Unsupported boundaries remain explicit.
5. Verify the restored default dispatch together with the Unicode and long-path
   worker and the original Advanced, regex and filter workflows.

A0: no UI/operation contract changed in this slice; full runtime regression
remains unverified. A1/A2: this identity defect is covered, overall migration
remains open. A3: native tests and supplementary core compilation passed; regular
full build remains unverified. A4: script unchanged and not run. A5: release/VM
acceptance not performed. A6: legacy migration and runtime parity remain open.
A7: PictView/WIC unchanged and not tested in this slice.

### Subsequent verification on 17 November 2026

The later [implementation record](Unicode-LongPath-Implementation.md) supersedes
the build blocker above: normal core compilation, resources, linking and PDBs
now pass in Debug/Release x64/Win32. It records the loader/language-directory
corrections, selected component builds and the still-blocked GUI acceptance.
The historical failed attempt is retained here as evidence. Full original-Find
migration and A6 acceptance remain open.
