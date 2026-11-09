# Long-path and Unicode filename investigation

## Confirmed legacy limitations

- `src/fileswn6.cpp::BuildScriptDir` explicitly rejects source paths close to `MAX_PATH` and the surrounding code uses fixed-size ANSI buffers.
- `src/worker.cpp::DoDeleteFile` previously copied an unchecked source name into `char nameList[MAX_PATH + 1]` for the recycle-bin path; this could overwrite stack memory.
- `src/fileswn6.cpp` previously retried a DOS 8.3 name only for a single selected delete entry. Multi-selection missed this fallback.
- The file manager still passes narrow `char*` paths to many Windows ANSI filesystem APIs. Unrepresentable Unicode filenames cannot be faithfully round-tripped through `CP_ACP`. An 8.3 alias cannot be assumed to exist.

## Changes on this branch

- Validate the recycle-bin name-list length before writing, and return `ERROR_FILENAME_EXCED_RANGE` for names that do not fit.
- Apply the pre-existing DOS-name fallback to *each* selected delete entry when a short name is available, with source-path bounds checking.
- Add a standalone MSVC regression test for name-list boundaries.
- Add `UpdateBuildAndDeploy.ps1` for both Release architectures, the standalone tests, runtime data staging, and verified 7z archives.

## Remaining work (not fixed in this branch)

The changes do **not** provide complete Unicode or Windows extended-length path support. That requires migrating the disk-panel name model, directory enumeration, source/target operation plans, move/copy/delete worker paths, recycle-bin handling, shell integration, and affected plugins to UTF-16/Wide Win32 APIs. Changing the process ACP or adding `longPathAware` to the manifest alone is insufficient and may introduce regressions in existing ANSI-dependent components.

The generated archives contain portable program files, **not an installer**. Visual C++ runtime dependencies and third-party plugin dependencies must already be present or supplied separately. The existing `!populate_build_dir.cmd` includes machine-specific interactive CRT/dependency steps and is deliberately not invoked from the automated script.

## Windows validation plan

1. Run `pwsh -NoProfile -File .\UpdateBuildAndDeploy.ps1` with VS2022 C++ and 7-Zip installed.
2. Confirm both test executables exit successfully and both archives pass `7z t`.
3. In an isolated NTFS test directory, manually verify single and multi-file delete (direct and Recycle Bin), rename, same-volume move, cross-volume move and directory recursion.
4. Test ASCII, Western-European characters, CJK, emoji (surrogate pairs), decomposed Unicode, and a name without a DOS 8.3 alias.
5. Exercise paths near 259 characters and above 260 characters (where allowed); verify that failures are explicit and never delete or overwrite an unrelated file.
6. Test with and without 8.3 name creation enabled, using a non-English Windows locale.

**Verification status:** The standalone boundary algorithm was exercised on Linux with clang/ASan/UBSan; Windows MSVC, the full solution build, Windows filesystem integration and 7-Zip packaging have not been executed in the editing environment.
