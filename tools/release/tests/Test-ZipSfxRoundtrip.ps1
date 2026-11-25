#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BuildDirectory,
    [Parameter(Mandatory)][string]$BuildRoot,
    [Parameter(Mandatory)][string]$SevenZipExe,
    [Parameter(Mandatory)][ValidateSet('Store','Deflate')][string]$Method,
    [Parameter(Mandatory)][ValidateSet('None','ZipCrypto')][string]$Encryption
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'SFX roundtrip requires Windows.' }

. (Join-Path $PSScriptRoot '..\Build-Helpers.ps1')
$converter = Join-Path $BuildDirectory 'plugins\zip\zip2sfx\zip2sfx.exe'
$package = Join-Path $BuildDirectory 'plugins\zip\sfx\english.sfx'
Assert-ZipSfxWin32Executable -Path $converter
Assert-ZipSfxPackage -Path $package
$encrypted = $Encryption -eq 'ZipCrypto'
# Public, disposable fixture password only; never read or enter user secrets.
$password = 'SfxTest123'
if ($encrypted) {
    if (-not [Environment]::UserInteractive) { throw 'ZipCrypto SFX requires an interactive Windows desktop.' }
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class ZipSfxPasswordDialog
{
    private delegate bool WindowCallback(IntPtr hwnd, IntPtr arg);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool EnumWindows(WindowCallback callback, IntPtr arg);
    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")]
    private static extern bool IsWindowEnabled(IntPtr hwnd);
    [DllImport("user32.dll")]
    private static extern IntPtr GetDlgItem(IntPtr hwnd, int id);
    [DllImport("user32.dll")]
    private static extern IntPtr GetParent(IntPtr hwnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "GetClassNameW")]
    private static extern int GetClassName(IntPtr hwnd, StringBuilder name, int length);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")]
    private static extern int GetWindowLong(IntPtr hwnd, int index);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "SendMessageTimeoutW", SetLastError = true)]
    private static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint message, UIntPtr wparam,
        string text, uint flags, uint timeout, out UIntPtr result);
    [DllImport("user32.dll", EntryPoint = "PostMessageW", SetLastError = true)]
    private static extern bool PostMessage(IntPtr hwnd, uint message, IntPtr wparam, IntPtr lparam);

    private const int PasswordId = 126; // IDC_PASSWORD, selfextr/RESOURCE.H
    private const int FileId = 103;     // IDC_FILE
    private const int OkId = 1;         // IDOK
    private const int CancelId = 2;     // IDCANCEL
    private const int SkipId = 112;     // IDC_SKIP
    private const int SkipAllId = 113;  // IDC_SKIPALL
    private const uint WmSetText = 0x000C;
    private const uint WmCommand = 0x0111;
    private const uint SendFlags = 0x23; // SMTO_BLOCK | ABORTIFHUNG | ERRORONEXIT

    private static bool Owned(IntPtr hwnd, uint pid)
    {
        uint actual;
        return hwnd != IntPtr.Zero && GetWindowThreadProcessId(hwnd, out actual) != 0 && actual == pid;
    }

    private static bool IsClass(IntPtr hwnd, string expected)
    {
        var name = new StringBuilder(128);
        return GetClassName(hwnd, name, name.Capacity) > 0 &&
            String.Equals(name.ToString(), expected, StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsControl(IntPtr dialog, int id, uint pid, string expectedClass)
    {
        IntPtr hwnd = GetDlgItem(dialog, id);
        return Owned(hwnd, pid) && GetParent(hwnd) == dialog && IsClass(hwnd, expectedClass);
    }

    // Match the real IDD_PASSWORD template by its control layout, never by
    // localized caption or foreground window. Never send input to other PIDs.
    private static bool IsPasswordDialog(IntPtr dialog, uint pid)
    {
        if (!Owned(dialog, pid) || !IsWindowVisible(dialog) || !IsWindowEnabled(dialog) ||
            !IsClass(dialog, "#32770"))
            return false;
        if (!IsControl(dialog, PasswordId, pid, "Edit") ||
            !IsControl(dialog, FileId, pid, "Static") ||
            !IsControl(dialog, OkId, pid, "Button") ||
            !IsControl(dialog, CancelId, pid, "Button") ||
            !IsControl(dialog, SkipId, pid, "Button") ||
            !IsControl(dialog, SkipAllId, pid, "Button"))
            return false;
        IntPtr edit = GetDlgItem(dialog, PasswordId);
        IntPtr ok = GetDlgItem(dialog, OkId);
        return (GetWindowLong(edit, -16) & 0x20) != 0 && // ES_PASSWORD
            IsWindowEnabled(edit) && IsWindowEnabled(ok) &&
            IsWindowVisible(edit) && IsWindowVisible(ok);
    }

    public static bool TrySubmit(uint pid, string password)
    {
        var matches = new List<IntPtr>();
        if (!EnumWindows((hwnd, arg) => {
            if (IsPasswordDialog(hwnd, pid)) matches.Add(hwnd);
            return true;
        }, IntPtr.Zero))
            throw new InvalidOperationException("Cannot enumerate SFX dialog windows.");
        if (matches.Count == 0) return false;
        if (matches.Count != 1)
            throw new InvalidOperationException("Ambiguous SFX password dialog.");

        IntPtr dialog = matches[0];
        if (!IsPasswordDialog(dialog, pid))
            throw new InvalidOperationException("SFX dialog disappeared before input.");
        IntPtr edit = GetDlgItem(dialog, PasswordId);
        IntPtr ok = GetDlgItem(dialog, OkId);
        UIntPtr result;
        if (!Owned(edit, pid) || GetParent(edit) != dialog ||
            SendMessageTimeout(edit, WmSetText, UIntPtr.Zero, password, SendFlags, 2000, out result) == IntPtr.Zero ||
            result == UIntPtr.Zero)
            throw new InvalidOperationException("SFX password field rejected WM_SETTEXT.");
        if (!IsPasswordDialog(dialog, pid) || !Owned(ok, pid) || GetParent(ok) != dialog ||
            GetDlgItem(dialog, OkId) != ok ||
            !PostMessage(dialog, WmCommand, new IntPtr(OkId), ok))
            throw new InvalidOperationException("SFX password dialog rejected IDOK.");
        return true;
    }
}
'@
}

function Invoke-SfxTestProcess {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory)][string]$Directory,
        [switch]$SubmitPassword
    )
    $info = [Diagnostics.ProcessStartInfo]::new($Executable)
    $info.WorkingDirectory = $Directory
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.Environment['TEMP'] = $Directory
    $info.Environment['TMP'] = $Directory
    foreach ($arg in $Arguments) { $info.ArgumentList.Add($arg) }

    $process = [Diagnostics.Process]::Start($info)
    if ($null -eq $process) { throw "Cannot start $Executable" }
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $submitted = $false
        while (-not $process.WaitForExit(50)) {
            if ($watch.ElapsedMilliseconds -ge 120000) {
                throw "Timeout (password submitted=$submitted): $Executable"
            }
            if ($SubmitPassword -and -not $submitted) {
                $submitted = [ZipSfxPasswordDialog]::TrySubmit([uint32]$process.Id, $password)
                if ($submitted) { Write-Host 'SFX password dialog: submitted fixture password.' }
            }
        }
        if (-not $stdout.Wait(5000) -or -not $stderr.Wait(5000)) {
            throw "Output pipes did not close: $Executable"
        }
        $output = $stdout.GetAwaiter().GetResult()
        $errors = $stderr.GetAwaiter().GetResult()
        if ($output) { Write-Host $output.TrimEnd() }
        if ($errors) { Write-Host $errors.TrimEnd() }
        if ($process.ExitCode -ne 0) {
            throw "Exit code $($process.ExitCode): $Executable"
        }
        if ($SubmitPassword -and -not $submitted) {
            throw 'Encrypted SFX exited without an observed and automated password dialog.'
        }
        return $output
    }
    finally {
        try {
            if (-not $process.HasExited) {
                try { $process.Kill() }
                catch [InvalidOperationException] { if (-not $process.HasExited) { throw } }
                if (-not $process.WaitForExit(5000)) {
                    throw "Test process did not terminate: $Executable"
                }
            }
        }
        finally { $process.Dispose() }
    }
}

# Unique directories, no user files or existing archives. Keep fixtures and
# logs for diagnosis; no recursive deletion of paths produced by the SFX.
$work = New-ZipSfxDirectory -Root $BuildRoot -Relative ('sfx-test-' + [guid]::NewGuid().ToString('N'))
Write-Host "SFX fixture: $work; $Method; $Encryption"
# The legacy Win32 SFX/CLI currently use ANSI/MAX_PATH APIs. This baseline
# does not claim Unicode or long-path acceptance, which needs separate tests.
foreach ($path in @($work, $converter, $package)) {
    if ($path -match '[^\x20-\x7E]' -or $path.Length -ge 220) {
        throw "ASCII short-path SFX baseline requires a suitable checkout path: $path"
    }
}

$source = Join-Path $work 'payload.txt'
$archive = Join-Path $work 'fixture.zip'
$output = Join-Path $work 'fixture.exe'
$settings = Join-Path $work 'fixture.set'
$target = Join-Path $work 'extracted\payload.txt'
[IO.File]::WriteAllText($source, ('OpenSalamander SFX regression 0123456789' * 4096), [Text.Encoding]::ASCII)
$expectedHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
$zipArgs = @('a', '-tzip', "-mm=$Method", '-bd')
if ($encrypted) { $zipArgs += @('-mem=ZipCrypto', "-p$password") }
$zipArgs += @($archive, 'payload.txt')
$null = Invoke-SfxTestProcess -Executable $SevenZipExe -Arguments $zipArgs -Directory $work

$listing = Invoke-SfxTestProcess -Executable $SevenZipExe -Arguments @('l','-slt',$archive) -Directory $work
$expectedMethod = if ($encrypted) { "ZipCrypto $Method" } else { $Method }
$expectedEncryption = if ($encrypted) { '+' } else { '-' }
$lines = @($listing -split '\r?\n')
if ($lines -cnotcontains "Method = $expectedMethod" -or
    $lines -cnotcontains "Encrypted = $expectedEncryption") {
    throw "Unexpected ZIP method or encryption; expected $expectedMethod."
}
$testArgs = @('t', '-bd')
if ($encrypted) { $testArgs += "-p$password" }
$testArgs += $archive
$null = Invoke-SfxTestProcess -Executable $SevenZipExe -Arguments $testArgs -Directory $work
$zipHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
@"
version=2
target_dir="extracted"
allow_dir_change=0
autostart=1
hide_dlg=1
show_summary=0
create_target_dir=1
ovewrite_all=0
command=""
requires_administrative_privileges=0
sfxpackage="$package"
"@ | Set-Content -LiteralPath $settings -Encoding ascii

$null = Invoke-SfxTestProcess -Executable $converter -Arguments @("-s$settings",$archive,$output) -Directory $work
Assert-ZipSfxWin32Executable -Path $output
if (Test-Path -LiteralPath (Split-Path -Parent $target)) { throw 'Extraction destination already exists.' }
$null = Invoke-SfxTestProcess -Executable $output -Directory $work -SubmitPassword:$encrypted
if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw 'SFX did not extract payload.' }
if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -cne $expectedHash) {
    throw 'Extracted bytes differ.'
}
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -cne $zipHash) {
    throw 'Source ZIP was modified.'
}
Write-Host "PASS: SFX $Method / $Encryption; SHA-256 payload and source archive."
