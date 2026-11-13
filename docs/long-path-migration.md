# Long path and Unicode filename migration (Windows)

## Current status

**Not yet implemented:** Open Salamander does not have end-to-end support for
filesystem paths longer than `MAX_PATH` (260), or all Unicode filenames.

The current core stores panel and work paths in fixed ANSI buffers:
- `src/fileswnd.h`: `Path[MAX_PATH]`, `WorkPath[MAX_PATH]`, `ZIPArchive[MAX_PATH]`.
- `src/salamdr1.cpp`, `BuildName()`: reports names as too long at `MAX_PATH`.
- `src/safefile.cpp`, `SafeFileOpen()` / `SafeFileCreate()`: explicitly reject
  paths of length `MAX_PATH` or above.

Simply removing the limits or enabling a `longPathAware` application manifest
would be unsafe: upstream and downstream code still assumes these buffers have
a fixed capacity. A path can exceed 260 characters while its individual
filename components remain limited by the filesystem (typically 255 UTF-16
code units on NTFS).

## Test-first Unicode migration foundations (13 November 2026)

This is **incremental work, not an end-to-end migration**. The sections below
distinguish standalone foundations from the partial GUI code now present:

1. **Owned disk names and paths:** `src/common/utf16_disk_path.h`
   introduces separate, dynamically allocated `Utf16FileName` and
   `Utf16DiskPath` C++17 types. The model preserves UTF-16 surrogate pairs,
   distinguishes names that collapse to the same ANSI replacement characters,
   validates component length and reserved Win32 syntax, and rejects relative,
   ambiguous and invalid UNC paths. It deliberately does **not** change
   `CFileData`, its `char* Name` field, or the plugin ABI.
2. **Native Unicode directory enumeration:** Existing
   `TryEnumerateLongDirectory` in `src/common/win32_long_directory.h`
   now accepts the owned disk-path type as well as existing `wchar_t*` paths.
   Results retain their full Unicode names. An independent wide enumeration
   now feeds the panel's sidecar identity cache, but the legacy `CFileData`
   enumeration and plugin ABI remain ANSI.
3. **Non-overwriting file operations:** The standalone
   `src/common/win32_unicode_file_ops.h` uses extended-length Win32
   paths and explicit `CopyFileW`, `MoveFileExW`, and `DeleteFileW`.
   Rename is the same-volume move primitive. It neither overwrites existing
   destinations nor silently attempts cross-volume copy-and-delete.
   These primitives are **not** a completed replacement for Salamander's
   F2/F5/F6/F8 engine, recursive handling, plugins, cancellation or UI.
4. **Long paths:** The owned model handles absolute UTF-16 paths above
   `MAX_PATH` without a fixed `char[]`. The production disk-panel
   `Path[MAX_PATH]`, `ChangePathToDisk` guard, shell integration and
   operation engines have not been migrated. A long-path GUI pass remains
   blocked; do not merge this PR as a finished fix.

### Regression and acceptance gates

- Test definitions were committed before each new foundation implementation.
- `tools/tests/utf16_disk_path.cpp` tests Unicode identity, supplementary
  characters, invalid surrogates, 255/256-code-unit components, path
  validation and UNC. It is compiled by `manage.cmd --test` and Windows CI.
- `tools/tests/long_path_io.cpp` tests Unicode file I/O, enumeration,
  non-overwriting copy, same-volume move and deletion on >260-unit paths.
- GitHub Actions **Long path regression foundations** run
  [43437548771](https://github.com/Fla77y/Salamander/actions/runs/43437548771)
  passed the foundation tests at commit `6539d1c`. The typed directory
  overload was added after this run and must be reverified at its new SHA.
- `manage.cmd --test-gui-baseline` previously passed on the actual desktop.
  `--test-gui-names` **failed** reproducibly on
  `Größe_東京_😀.txt`: Salamander copied `Größe_??_??.txt`.
- New `manage.cmd --test-gui-operations-baseline` checks real F2/F5/F6/F8
  on disposable short ASCII files **before** their production implementation
  is changed. It is not yet executed on an interactive Windows desktop.
- `manage.cmd --test-gui` remains the mandatory long-path/Unicode GUI gate.
  No foundation-level green result substitutes for this gate.

### Next production migration

Characterize existing panel selection, filtering, refresh, rename, copy,
move and delete behavior under the new ASCII GUI gate before touching their
implementation. Then migrate on-disk panel metadata and path ownership to
wide UTF-16 without changing the binary layout of `CFileData` or the plugin
interfaces. Preserve plugin-FS/archive behavior using an explicit legacy
compatibility boundary; never send the truncated ANSI alias of a file into
destructive operations. Re-run short ASCII, short Unicode, long-path,
negative and plugin regressions after each converted call chain.

## Read-only Unicode disk-panel GUI slice (13 November 2026)

The Windows desktop short-ASCII operation baseline (F2/F5/F6/F8) passed
before any GUI core change. The existing short Unicode GUI regression
reproduced `Größe_東京_😀.txt` being exported as `Größe_??_??.txt`.

This branch now includes a **partial, read-only GUI integration**:

- `src/common/win32_unicode_panel_name.h` resolves a legacy CP_ACP
  filename to an actual UTF-16 directory entry using the Win32 wide
  enumeration path. Two distinct filenames with an identical ANSI alias
  are marked ambiguous; never choose one arbitrarily.
- `UnicodePanelNameCache` is owned by `CFilesWindow`, not by
  plug-in-visible `CFileData`. The cache is invalidated on every
  listing. After the ANSI best-fit fix below, the Unicode directory is
  scanned for every disk listing so aliases without `?` are checked too.
- `src/fileswn4.cpp` uses wide GDI measurement and drawing for
  uniquely recovered names in **Brief/Detailed name columns**. Unicode
  surrogate pairs are not split by text ellipsizing.
- `src/fileswn9.cpp::CopyFocusedNameToClipboard` returns actual
  `CF_UNICODETEXT` for a unique lossy ANSI alias (including best-fit
  substitution without `?`) after revalidating the original filesystem
  entry. The short name and full path are supported; unsafe UNC translation
  is deliberately refused.

**Not implemented:** data-model identity for ambiguous ANSI aliases;
Unicode-safe selection, filtering, sorting and edit actions; icon/tile/
thumbnail name rendering; long disk-panel directories; F2/F5/F6/F8
migration; plug-in Unicode name handling. A read-only display fix is
not evidence that destructive operations are safe. Do not merge or
advertise Unicode-GUI compatibility until these paths and the
interactive regression suite are completed.

The native MSVC regression covers unique and colliding names, a
per-listing index and invalidation. The real GUI gate remains
`manage.cmd --test-gui-names`, plus visual inspection in Brief/Detailed
mode and the already-passing ASCII operations baseline.

## Fail-closed legacy disk action gate (13 November 2026)

The **real Windows GUI alias collision test passed** on the user desktop:
`manage.cmd --test-gui-name-collisions` (16:02) retained both files'
original bytes and refused a guessed `CM_CLIPCOPYNAME` result.
The **real short ASCII F2/F5/F6/F8 baseline** also passed (16:01).

After these pre-change tests, `src/common/legacy_disk_name_safety.h`
and `tools/tests/legacy_disk_name_safety.cpp` were added test-first.
The helper detects replacement `?` in legacy disk file names and
checks all explicitly selected entries (or only the focused entry when
there is no explicit selection).

The actual disk operation entry points are guarded before side effects:
- `src/fileswn5.cpp::RenameFile`: refuse F2 on a lossy ANSI filename.
- `src/fileswn8.cpp::FilesAction`: refuse the full F5/F6/F8 (and
  change-case) selection if any entry has a lossy ANSI filename.
- ZIP and plugin-FS operations remain on their original code paths.

The user-facing refusal message is currently in English and needs proper
localization before release. This **temporary guard is incomplete**:
ANSI best-fit substitutions that do not contain `?`, shell/context
menu/drag-and-drop operations that bypass these entry points, recursive
operations and plugin paths still require audit and Unicode-safe
identity handling. It is **not** the full F2/F5/F6/F8 Unicode migration.

Regression gates:
- The portable `legacy_disk_name_safety.cpp` checks selected/focused
  semantics, multiple selections and no false positives on ordinary
  ASCII names. Wired into `manage.cmd --test` and Windows CI.
- New `manage.cmd --test-gui-unsafe-unicode-operations` creates two
  disposable colliding Unicode names and requires F2/F5/F6/F8 to show
  the refusal dialog and leave both source files and the target
  unchanged. This needs an interactive desktop and a **fresh build**.
- Re-run `--test-gui-operations-baseline` to detect regressions to
  ordinary ASCII file operations.

## Exact round-trip disk identity gate (13 November 2026)

The previous `?` heuristic missed Windows CP_ACP best-fit substitutions
(e.g. a wide character mapped to a visually similar ANSI character without
a question mark). These are still **not** unique, lossless identities.

Test-first changes:
- `tools/tests/legacy_disk_name_safety.cpp` requires an explicit unsafe
  identity flag to block F2/F5/F6/F8 even for plain-looking aliases.
- `tools/tests/long_path_io.cpp` requires exact ACP-to-UTF-16 round-trip
  equality, refuses unknown and ambiguous names, and dynamically creates
  a genuine best-fit-without-`?` Windows file fixture where CP_ACP permits
  one. On a UTF-8 ACP this optional fixture reports `SKIP`; the exact
  identity contract still runs.
- `src/common/win32_unicode_panel_name.h` now classifies each cached
  original Unicode directory entry as *exact ANSI round-trip*, *unique
  lossy*, or *unusable/ambiguous*. The cache remains separate from
  `CFileData`, preserving its plugin ABI.
- `ReadDirectory` now builds this cache on **every disk listing**,
  including ASCII-only listings; otherwise a best-fit alias cannot be
  recognized from the ANSI bytes alone. This adds one temporary extra
  directory enumeration per refresh until the panel itself becomes
  single-pass `FindFirstFileW`-based.
- F2 and F5/F6/F8 reject selected entries if the cache is missing,
  ambiguous, or shows any non-round-tripping name; existing `?`
  rejection remains in place. Batch operations reject the entire
  selection before their side effects.
- Brief/Detailed drawing and the focused name/full-path clipboard command
  use exact UTF-16 for a uniquely resolved lossy alias, with a fresh
  read-only identity check immediately before export.

**Interactive Windows acceptance still required after rebuilding:**
`manage.cmd --test-gui-baseline`,
`--test-gui-names`, `--test-gui-bestfit`,
`--test-gui-name-collisions`,
`--test-gui-unsafe-unicode-operations`, and
`--test-gui-operations-baseline`. The best-fit GUI test detects a real
CP_ACP mapping at runtime and may SKIP where none of its candidates maps
lossily without `?`.

**Remaining limitations:** this is still *fail-closed*, not Unicode
F2/F5/F6/F8 enablement. A per-ANSI-alias cache cannot identify individual
items when two original Unicode names collide; the correct long-term fix
is per-entry UTF-16 identity captured in one W enumeration pass.
The current extra wide listing costs I/O on large directories; measure
before release. Other GUI operation routes, long panel paths, plugins,
sort/filter and icon/tile/thumbnail displays still need migration.
The refusal message is temporarily English and needs localization.

## Interactive GUI foreground reliability (13 November 2026)

Windows desktop acceptance of 5.1 and normal short-path ASCII F2/F5/F6/F8
passed on the user's machine at 17:01. An earlier run at 16:48 failed **before
any keyboard input**: `Timeout waiting for test application to be foreground`.

The test driver has been hardened without changing production Win32 code:
- It still refuses to attach to an existing Salamander instance and resolves
  the launched main HWND through process-owned top-level Win32 enumeration.
- `Focus-TestProcess` retries activation of **only that verified HWND**.
  The C# Win32 helper first tries `SW_RESTORE` and `SetForegroundWindow`,
  then makes at most two brief `AttachThreadInput`-assisted attempts.
  It rechecks PID ownership, detaches with `finally`, and never sends
  keystrokes as part of focus recovery.
- It requires the *exact target HWND* to become foreground, instead of
  accepting any top-level popup of the same process.
- A failed activation reports the expected HWND/PID, actual foreground
  HWND/PID/title, all top-level windows of the launched process and
  attempt count. `Send-Keys` still refuses when the foreground PID differs.
- `Test-GuiDriver-Contract.ps1` compiles the C# helper on Windows CI
  and checks invalid HWND and foreign-PID refusals.

Foreground activation is ultimately restricted by Windows, and may be
refused on a locked desktop, another desktop or during UAC/dialog focus.
Do not force it by sending Alt/Tab or other input to an unrelated window.
A fresh interactive `manage.cmd --test-gui-baseline` run is required
to validate this driver's resilience on the affected desktop. No
rebuild is necessary for this test-script-only change.

## Genuine Unicode F2 rename — first writable GUI slice

This slice adds a **real UTF-16 rename**, separate from the legacy ANSI
engine, for a disk file or directory **only if** the sidecar cache maps
its legacy name uniquely to one original UTF-16 entry. It is not a
replacement for the legacy operation engine and does not change the
plug-in-visible `CFileData` layout.

1. `tools/release/tests/Test-SalamanderGui-LongPaths.ps1` has a new
   `-ShortUnicodeRenameOnly` mode, exposed through
   `manage.cmd --test-gui-unicode-rename`. It opens F2 on a single
   disposable short-path Unicode file, pastes a second Unicode name
   into the native wide dialog and checks that the old path disappears,
   the new path exists and the bytes are preserved.
2. `src/common/win32_unicode_rename_dialog.h` constructs a runtime
   `DialogBoxIndirectParamW` dialog with a UTF-16 edit control.
   The old `CCopyMoveDialog` remains unchanged for normal ANSI
   names and plug-ins.
3. `CFilesWindow::RenameFile` selects this path only when
   `UnicodeDiskNames.TryGetLossy` succeeds. A collision, unknown
   entry or unavailable index keeps the existing fail-closed error.
   A fresh wide directory enumeration validates the original before
   **and after** the modal editor, and the legacy ANSI alias is copied
   before showing the dialog so it cannot become a dangling pointer.
4. Both the original and requested names are validated as independent
   UTF-16 filename components. The existing
   `TryMoveUnicodeFileNoOverwrite` uses `MoveFileExW` with no
   overwrite or cross-volume-copy flag. Any error is displayed, with
   the original name preserved. A successful rename sends the usual
   panel refresh notification.
5. The native `tools/tests/long_path_io.cpp` now verifies a real
   existing UTF-16 destination **is not overwritten**, and that
   both source and destination are preserved. MSVC also compiles the
   native Unicode dialog template with `/W4 /WX` via
   `tools/tests/win32_unicode_rename_dialog.cpp`.

**Acceptance status:** CI compilation and the user's real interactive
`--test-gui-unicode-rename` result must be checked for this new slice.
The **previous** six short-path regression groups passed on Open
Salamander 5.1 on 13 November 2026, before adding this F2 write path;
they must not be reported as proof of the new path.

**Remaining and important:** F5/F6/F8 still fail closed on lossy names.
The 2nd enumeration introduces TOCTOU risk if an external process
actively swaps a filename immediately before the rename, as does any
name-based Win32 operation; handle/file-ID-based atomic binding is
needed for stronger adversarial guarantees. Real per-row UTF-16
identities require migrating the **primary** panel enumeration away
from `FindFirstFileA`; the current alias cache cannot distinguish
two UTF-16 names that map to the same ANSI bytes. Progress, overwrite
prompts, recycle bin, ACL policy, cancellation, other command entry
points, performance and long GUI paths still need implementation.
Do not treat this slice as full Unicode/long-path support.

## Phase 1: Baseline and bounded operations

- `tools/tests/Test-LongPaths.ps1` generates disposable cases for total
  paths >260, directory names up to 255, filenames up to 255, Unicode
  filenames, and an invalid 256-code-unit component. The script tests the
  **Windows filesystem**, not Salamander's file operations.
- Run it with `-KeepFixture` for manual Salamander exploration.
- `src/fileswn0.cpp`: protect quick-search buffer appends at capacity
  boundaries. The helper is unit-tested in
  `tools/tests/quicksearch_bounds.cpp`.

## Phase 1b: Explicit Unicode Win32 I/O foundation

- `src/common/win32_long_path.h` converts **fully qualified** UTF-16
  drive/UNC paths into extended-length Win32 syntax. It rejects relative,
  device-namespace, slash-mixed and unnormalized dot-segment paths.
- `src/common/win32_long_directory.h` enumerates entries with
  `FindFirstFileW` and `FindNextFileW`, preserving full UTF-16 names and
  attributes without converting them to the system ANSI code page.
- `CSalamanderSafeFile::SafeFileOpen` retains the existing short ANSI path
  behavior; for absolute **ANSI-representable** paths of length at least
  `MAX_PATH`, it now converts to UTF-16 and calls `CreateFileW`.
  Its parent callers, panel path representation and plug-in ABI **are not
  upgraded** by this change.
- The initial open and all read/write retries now share the same path-aware
  helper. Retries use `OPEN_EXISTING`, not the original `CREATE_ALWAYS` or
  `CREATE_NEW` disposition, to avoid truncating previously written bytes.
  The regression test verifies preservation and non-creation of deleted files.
- `tools/tests/long_path_io.cpp` tests real Unicode Win32 I/O on Windows,
  including >260-character paths, a 255-unit filename, and boundary cases.

**Not fixed by this layer:** GUI navigation, `CFileData::Name` ANSI
enumeration, Unicode names outside the active ANSI code page, copying and
renaming long paths, and the `SafeFileCreate` path/overwrite flow. Those
require the following phases. Do not remove current `MAX_PATH` checks.

## Phase 2: Owned Unicode and long-path representation

Introduce a dedicated UTF-16, dynamically sized representation for
**filesystem paths** at the core boundary. Keep filenames (single components)
and full absolute paths distinct; reject invalid input and respect the
filesystem's per-component limit. Use explicit wide Win32 APIs, with
extended-length drive/UNC prefixes only after correct normalization. Handle
relative paths before adding any extended-length prefix.

Do not silently change the plug-in ABI, serialized settings, or the
semantics of a path parameter passed to an external program.

## Phase 3: Incremental core operation migration

Migrate and test one path through the application at a time:
1. Directory navigation and enumeration, selection and refresh.
2. Open, create and overwrite, recursive copy and move.
3. Rename, delete, temporary names and collision handling.
4. Find/search, file viewer/editor launches and external commands.
5. Network shares/UNC, junctions, symlinks and removable filesystems.

Guard error paths, cancellation, partial copies, source/destination identity,
reparse loops and permissions before enabling operations on long paths.

## Phase 4: Shell and plug-in compatibility

Audit shell integration, drag-and-drop, recycle bin, shortcut targets,
archivers, viewer plug-ins, file operations, localization and persistence.
Where a plug-in cannot handle a long or Unicode path, provide a clear,
non-destructive error instead of truncating it. Maintain a compatibility
strategy for the existing ANSI plug-in interfaces.

## Phase 5: Opt-in and release acceptance

Only after the above has passed, evaluate application `longPathAware`
manifest support and Windows `LongPathsEnabled` policy requirements.
Do not change users' system registry from the installer without explicit
consent. Microsoft documents that manifest and Windows policy are both
required for the Win32 long-path opt-in; some APIs and shell operations
still have separate limits.

Before merging or publishing, validate x64 Debug/Release and portable/setup
Release on a clean Windows 11 machine, with both the long-path registry option
on and off.

### Manual regression procedure

Run:

```powershell
pwsh -File .\tools\tests\Test-LongPaths.ps1 -KeepFixture
```

Keep the output path. In the running Salamander build:

- Navigate into the deeply nested directory and verify the filename.
- Copy its file to the disposable destination; compare content.
- Rename it to a Unicode filename, move it, and verify no data loss.
- Use Search to locate the file; try file viewing and archiver plug-ins.
- Test a 255-character name and an invalid >255-character single component.
- Test UNC paths and long paths containing non-ASCII characters separately.
- Record **exact action, complete path, expected/observed behavior, error**.
- Do not test destructive operations on real user data.

The script creates data under a unique temporary directory. With
`-KeepFixture`, clean up that directory manually when finished.

**Documentation:** Microsoft Learn — Maximum Path Length Limitation
https://learn.microsoft.com/windows/win32/fileio/maximum-file-path-limitation


## Real GUI regression gate

Run the fully compiled Salamander (Debug or Release), on an unlocked
interactive Windows desktop:

    .\manage.cmd --test-gui

This invokes PowerShell 7 STA and
`tools/release/tests/Test-SalamanderGui-LongPaths.ps1` with the actual
`salamand.exe`. The test checks a short-path baseline, navigates into a
>260-unit directory, reads the panel path and selected filename through
documented Salamander keyboard shortcuts, performs F5 copy / F2 rename /
F6 move / F8 delete and compares file bytes. It tests a 255-unit name
separately. Every operation is guarded by the expected active panel
directory and filename, and only touches a unique disposable temp fixture.

If the GUI cannot navigate a long Unicode path, the test **must fail**.
A passing .NET or Win32 test by itself cannot override this result.
If automation cannot focus the target window, treat it as an **infrastructure
failure** and rerun on an interactive desktop, rather than claiming an
application defect.

Use `.\manage.cmd --test-gui-manual` for manual inspection, F1,
plugins, drag-and-drop and corner cases not yet covered automatically.

There is no safe architecture shortcut from the Win32 helper tests to full
GUI support. The panel's ANSI representations, filename representation,
plugins, file operation engines and serialized path formats still need
an incremental, compatibility-reviewed migration.


## Confirmed local GUI regression (13 November 2026)

Running `manage.cmd --test` on Windows with VS2026 completed all 18
filesystem assertions plus both standalone C++ tests. Those tests exercise
Windows / the new native helpers, **not** Salamander's path navigation.

A local interactive GUI run then navigated correctly to a short ASCII
directory but failed to reach the long directory. Salamander presented
**Error Changing Directory: Cannot finish operation because too long name.**

This maps directly to the existing production code:

- `src/fileswn2.cpp`, `CFilesWindow::ChangePathToDisk`, rejects paths
  with `strlen(path) >= MAX_PATH - 2`.
- `src/fileswnd.h`, `CFilesWindowAncestor::Path`, is a fixed-size
  `char[MAX_PATH]` buffer.
- `src/fileswn1.cpp`, `CFilesWindowAncestor::SetPath`, uses
  `strcpy(Path, path)`. Removing only the early-length guard can
  overflow the destination.
- `src/fileswn3.cpp`, `ReadDirectory`, uses `WIN32_FIND_DATAA` and
  fixed-size path storage. UTF-16 filenames that cannot be represented
  in the active ANSI code page may lose information.

**Therefore:** do not remove the path-length check or blindly replace
MAX_PATH globally. The migration must change the owned path/name types,
normalize through wide Win32 APIs, audit every copy into plugin-supplied
buffers and preserve data when a call chain is not yet Unicode-safe.

Local test commands:

    .\manage.cmd --test-gui-baseline   # short ASCII GUI/driver check
    .\manage.cmd --test-gui-names      # short UTF-16 filename fidelity
    .\manage.cmd --test-gui            # >260 path + F2/F5/F6/F8 integration

`--test-gui` now uses Salamander's documented Edit/Paste (`Ctrl+V`)
with an absolute directory path stored as clipboard text. This avoids the
unreliable Shift+F7 dialog detection that was reproduced on a real desktop
(three consecutive GUI driver failures on 13 November 2026). It still
reports Salamander's own long-path rejection instead of claiming success
based only on Windows API tests. The GitHub-hosted CI runner is non-interactive and cannot
replace an unlocked Windows desktop; keep the native build/package CI
independent and require the local GUI gate before declaring support.

The local screenshot showed Salamander's title with **(Administrator)**.
Windows User Interface Privilege Isolation (UIPI) can block keyboard
automation if the test shell is less privileged than Salamander. The
test now reports its own elevation and Salamander's window title, and
fails with a specific diagnostic for that mismatch. Prefer running
both Salamander and the test shell **without** elevation.
