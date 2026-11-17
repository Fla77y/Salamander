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
