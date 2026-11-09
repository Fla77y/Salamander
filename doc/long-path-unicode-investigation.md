# Long-path and Unicode filename investigation

## Confirmed causes

1. `src/fileswn6.cpp::BuildScriptDir` rejects source paths near `MAX_PATH`, and `src/salamdr1.cpp::BuildName` enforces `MAX_PATH` in operation names. Numerous UI structures use fixed ANSI buffers.
2. `FindFirstFileA` / `WIN32_FIND_DATAA` in `src/fileswn3.cpp` convert names into the process ANSI code page, losing unrepresentable Unicode characters. DOS 8.3 aliases may not exist.
3. Many legacy operations use ANSI Win32 APIs and can reject long paths or normalize trailing dots/spaces.
4. `src/worker.cpp::DoDeleteFile` and `DoDeleteDir` contained separate unchecked writes into the `MAX_PATH + 1` Recycle Bin name lists.
5. Before this branch, the DOS-name fallback applied only to one selected deletion entry.

## Implemented changes

- Both Recycle Bin name lists are bounds-checked. The legacy `SHFileOperationA` path rejects trailing-dot/space names rather than risking deletion of the wrong item.
- The 8.3-name fallback is applied per selected delete entry and checks source-buffer capacity.
- `src/common/win32widepaths.h` converts representable ANSI strings to UTF-16 and uses extended-length Win32 paths with `MoveFileW`, `CreateFileW`, `GetFileAttributesW`, `SetFileAttributesW`, `CreateDirectoryW`, `RemoveDirectoryW` and `DeleteFileW`. UTF-16 overloads are available for new code.
- Common move/attribute operations in `src/salamdr5.cpp`, and direct Win32 calls in `src/worker.cpp`, now use that adapter. Direct deletion can operate on an exact trailing-dot or trailing-space file name where the rest of the legacy pipeline permits it.
- The process-wide ANSI code page and plugin ABI remain unchanged.

## Automated tests and CI

`UpdateBuildAndDeploy.ps1` builds Release Win32 and x64 and executes:

- `ShellFileOperationNameListTests.exe`: double-NUL termination, capacity boundaries, invalid inputs and overflow rejection.
- `Win32FilesystemIntegrationTests.exe`: real Windows filesystem operations within an isolated temporary directory, including long paths, CJK/accented/emoji filenames, directory rename/removal, ANSI adapter operations when losslessly representable, UNC prefix formatting, no-overwrite moves, and trailing-dot deletion without touching another file.

Test failures stop archive creation. `.github/workflows/long-path-unicode-integration.yml` invokes the same pipeline on Windows CI.

**Scope of the tests:** They exercise the real Win32 filesystem backend, not Salamander's GUI and complete operation-plan/worker pipeline. They do not cover network shares, a second physical volume, Recycle Bin COM integration, plugins, or deliberately ill-formed UTF-16 names.

## Remaining architecture work

The application is still fundamentally ANSI. Complete support for *all* Unicode names and arbitrary path lengths requires coordinated changes to disk-panel enumeration, stored filenames, operation plans (`BuildName` and `BuildScriptDir`), workers, shell integration, Recycle Bin handling, and plugin compatibility. Some paths are still rejected before they can reach the new wide backend; filenames already substituted during ANSI directory enumeration cannot be restored. Neither a UTF-8 active code page nor a long-path-aware manifest alone is a safe complete fix.

## Windows validation

1. Run `pwsh -NoProfile -File .\UpdateBuildAndDeploy.ps1` on Windows 11 with VS2022 C++ tools, PowerShell 7.4+, and 7-Zip.
2. Confirm both test executables and the archive integrity checks succeed.
3. Use the built Salamander **only on disposable test data** to check single/multi-delete (direct and Recycle Bin), rename, same-volume move, cross-volume move, recursive copy/delete, and name collisions.
4. Include ANSI, CJK, emoji, decomposed Unicode, a name without an 8.3 alias, trailing dot/space, and paths near 259 and above 260 characters; verify the original file's contents after every failure.
5. Repeat on a filesystem where 8.3 names are disabled and under a non-English Windows locale.

Archives are portable program folders, **not installers**. Visual C++ runtime and external plugin dependencies might be needed.

**Verification status:** The user-provided 9 November 2026 log confirms that the **earlier** branch revision built and its old tests passed on Win32 and x64. The new UTF-16 adapter and Windows filesystem tests added **after** that run have not been executed by this editing environment. No passing Windows CI status is claimed.
