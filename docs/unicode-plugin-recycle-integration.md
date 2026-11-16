# Unicode, plug-in and Recycle Bin integration: first acceptance slice

Date: 16 November 2026. Base: `main` merge commit
`17d1d0e611f31a8370d666a1a7a540210e65ecd8` (PR #7).

This branch extends verification, not the legacy plug-in ABI or broad
filesystem behavior. Tests that have not run on an actual Windows desktop
are **not considered passed**.

## Inventory and risk boundaries

- **Unicode disk-panel F2/F5/F6/F8:** real short-path, long-path, collision,
  alias and near-32700-unit behavior passed in PR #6/#7 x64 Debug/Release
  regression runs. This does **not** prove all legacy plug-in operations.
- **Recycle Bin:** existing GUI F8 test had observed removal of an isolated
  Unicode file. A subsequent explicit desktop acceptance on 16 November 2026
  verified exact original-path identity, shell restoration and unchanged bytes
  for a short-path Unicode file. `win32_unicode_recycle.h` deliberately
  supports only short absolute regular files on fixed local drives and rejects
  unsupported cases without direct deletion.
- **Plug-ins:** `7zip`, `checksum`, `filecomp` and `renamer` export
  `SalamanderPluginEntry` and `SalamanderPluginGetReqVer` from their
  respective `.def` files. The old ANSI plug-in SDK must not be changed
  merely to add Unicode names. Actual plug-in load/menu behavior, long
  paths and nonrepresentable Unicode filename handling remain acceptance
  gaps.

## Implemented in this branch

### 1. Opt-in F8 Unicode Recycle Bin round trip

```powershell
cd C:\Repositories\Salamander
.\manage.cmd --update --test-recycle-restore
# Optional: use --debug to test only the x64 Debug binary
```

This starts a disposable Salamander instance on the unlocked Windows
desktop (STA) and creates a GUID-scoped temporary directory. It verifies
the selected exact UTF-16 filename, invokes the existing F8 recycle
operation, then uses the Windows Shell Recycle Bin folder
(`Shell.Application.NameSpace(10)`) to enumerate items.

The test checks **both** exact filename and exact original directory
via `System.Recycle.DeletedFrom`. Zero or multiple matches fail; it
does not select an item by its position or partial name. It refuses
restoration if the original destination exists. It invokes only the
verified item's specifically enumerated `Restore`/`Wiederherstellen`
verb; unknown localizations fail closed instead of executing the default
shell verb. After restoration, it checks the **exact original file bytes**.

The test **requires successful recycling**. A refused/disabled Recycle
Bin is a test failure in this explicit mode (rather than the ordinary
test's safe SKIP). Failures may leave the uniquely marked disposable
item in the user's Recycle Bin. The test never empties the Recycle Bin,
deletes an unrelated item or silently substitutes permanent deletion.
It retains the diagnostic source directory on failure.

The first real Windows round trip **passed** on 16 November 2026. This
operation remains **explicit opt-in**, excluded from `--test-all` while
coverage of configurations (including Debug, non-elevated and clean-host
acceptance) remains limited. The original
`--test-gui-unicode-recycle` remains unchanged in scope.

### 2. Read-only built plug-in SDK/PE contract

```powershell
cd C:\Repositories\Salamander
.\manage.cmd --update --build --test-plugin-exports
# Optional: --release or --debug selects only one x64 configuration
```

The test locates Visual Studio 2026's `dumpbin.exe` and inspects the
actual Debug and Release x64 `.spl` files for the four priority plug-ins.
For each plug-in, it requires:

- a corresponding source `.def` file and built binary;
- the x64 COFF machine value `8664`;
- both precise SDK export names in both the source definition and
  the **real binary export table**.

It does not load or execute any plug-in DLL. Therefore this is an
**ABI smoke test**, not proof of plug-in startup, GUI integration,
content processing or full Unicode support. It is likewise excluded
from `--test-all` pending Windows acceptance.

### 3. Test wiring safety

`Test-GuiDriver-Contract.ps1` statically checks that opt-in restore
identification uses original-path metadata and rejects a pre-existing
destination. It also checks the plug-in test parses and uses inspection
rather than `LoadLibrary`. Actual behavior still requires the real
Windows acceptance commands above.

## Verified Windows acceptance — 16 November 2026

**PASS: opt-in Unicode F8 Recycle Bin restore, 16:19:56–16:20:00 CET.**

Source: user-provided Windows PowerShell 7.7 transcript from
`manage.cmd --test-recycle-restore`. The disposable short-path fixture
was below `MAX_PATH`; the launched Salamander was x64 and elevated
(`test session elevated = True`). The GUI driver verified the selected
UTF-16 filename, the Windows shell supplied a Recycle Bin entry matching
both that filename and the exact original directory, and invoking the
guarded restore operation returned the file with its exact expected bytes.
The entire test command completed successfully.

The run had **no `--update` option and no Git commit SHA in its log**.
It verifies the reported runtime behavior on that workstation; it does
not independently prove which repository revision or binary build produced
the result. It does not cover long paths, network/removable drives,
directory recycling, alternative locales or non-elevated GUI behavior.

**Still pending:** the separate `--test-plugin-exports` Windows result
for the revised public-export parser. A previous attempt on commit
`199195f` failed at the parser assertion for `7zip.spl` before
the Recycle Bin test ran. The corrected parser is committed, but the
present acceptance transcript tests only restoration.

## Next independently testable development slices

1. **Recycle restoration acceptance:** the first opt-in Unicode round trip
   passed on an actual Windows desktop. Repeat with Debug and non-elevated
   contexts, evaluate other shell locales without guessing, then decide
   whether inclusion in `--test-all` is safe. Test refusal and cancellation
   separately.
2. **Plug-in activation smoke:** in a disposable short-path GUI fixture,
   exercise normal 7-Zip archive listing, Checksum output, File
   Comparator and Batch Renamer using exact expected bytes/filenames.
   Never infer success from merely having a plug-in export.
3. **Unicode and long-path plug-in boundary:** supply a long path and
   distinct Unicode aliases to plug-in menus; verify explicit,
   non-destructive refusal until end-to-end original UTF-16 identity
   can be guaranteed. Preserve saved configuration and existing
   ANSI plug-in SDK structures.
4. **Shell and path corner cases:** automate short-path Recycle Bin
   source/destination collisions and trailing-dot/space identities
   only after a dedicated, non-destructive acceptance harness exists.
5. **Release gate:** full `--update --build --test-all`, both x64
   configurations, GitHub CI and clean-host setup/plug-in acceptance
   before integrating any behavior-changing implementation.

This document distinguishes **source analysis**, **committed but
unexecuted test cases**, and **real Windows evidence** deliberately.
