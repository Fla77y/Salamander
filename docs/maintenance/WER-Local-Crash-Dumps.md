# Local crash diagnosis with Windows Error Reporting

Open Salamander no longer starts SalMon, creates its shared-memory bridge,
patches `SetUnhandledExceptionFilter`, uploads proprietary crash reports or
opens the SalMon bug-report UI. Unhandled native exceptions are left to Windows'
default exception handling and Windows Error Reporting (WER). Ordinary builds
use the Microsoft C runtime entry point again. The special
`X64_STRESS_TEST` build retains its pre-CRT allocation probe.

## Inspecting local dump configuration (read-only)

From any normal PowerShell 7 session at the repository root:

```powershell
pwsh -NoProfile -File .\tools\release\Configure-LocalCrashDumps.ps1
```

WER LocalDumps is **not enabled by default**. Dump registration uses
`HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\salamand.exe`
rather than `HKCU` (the latter does not support LocalDumps). This affects all
installed copies named `salamand.exe`, not only one checkout. The helper
reads both 32-bit and 64-bit registry views on x64 Windows.

## Explicitly enabling local minidumps

Only when local crash capture is desired, start an **elevated** Windows
PowerShell 7 session and run:

```powershell
cd C:\Repositories\Salamander
pwsh -NoProfile -File .\tools\release\Configure-LocalCrashDumps.ps1 -Enable
```

The helper first refuses any pre-existing per-application configuration;
it never overwrites settings maintained by the user or another tool.
It registers `DumpType=1` (small/minidump) and `DumpCount=10` in the
appropriate HKLM registry views. WER uses its default per-user path,
`%LOCALAPPDATA%\CrashDumps` (expand this in Explorer). Files may contain
private data and must not be uploaded publicly or shipped in releases.
Deleting existing old `.DMP`/`.BUG` files is **not** part of migration.

The helper does **not** configure uploads, change global WER reporting policy,
start a debugger or crash Salamander. OS-wide WER privacy settings are
managed by Windows itself and must be reviewed separately. To undo the
optional registration, inspect both registry views and remove only the
`salamand.exe` LocalDumps subkey created by this tool; do not remove
global `LocalDumps` settings or other applications' configuration.

## Validation limitations

- For an actual crash acceptance, use a disposable isolated test process
  with symbols and a dedicated test system. Verify that WER writes a readable
  `salamand.exe.*.dmp`, verify the original fault in WinDbg, and confirm
  the program no longer launches `salmon.exe` or prompts for uploads.
  Never deliberately crash a productive instance or endanger user data.
- An attached automatic debugger can prevent WER LocalDumps capture.
  WER crash dumps do not diagnose a hung-but-running application: the
  existing explicitly opted-in GUI hang-dump tool remains independent.
- Without an explicit elevated LocalDumps configuration, native Windows
  crash handling still applies, but a local dump file is **not guaranteed**.
- Solution, project, package exclusions and GUI tests must be rebuilt and
  exercised on Windows for x86/x64 Debug/Release. Pure source-level checks
  cannot prove the operating-system WER behavior.

Microsoft reference:
https://learn.microsoft.com/en-us/windows/win32/wer/collecting-user-mode-dumps
