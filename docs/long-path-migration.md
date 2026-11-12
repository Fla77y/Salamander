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
