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
5. Restore direct legacy-dialog dispatch only when its Unicode/long-path behavior
   and the original Advanced/regex/filter workflows pass together. The currently
   active replacement W window remains an existing A6 compliance gap, not an
   accepted alternative to the original dialog.

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
