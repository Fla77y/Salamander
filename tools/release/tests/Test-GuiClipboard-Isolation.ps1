#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
    Prove that a GUI navigation clipboard payload is readable by another process.
.DESCRIPTION
    The GUI driver dispatches WM_COMMAND 775 synchronously. Its clipboard
    payload must not rely on an OLE IDataObject hosted by the sending STA,
    which can otherwise wait for its own blocked apartment. The regression
    blocks the writer while a second process reads CF_UNICODETEXT.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Native GUI clipboard regression requires Windows.' }
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    throw 'Run GUI clipboard regression with pwsh -Sta.'
}
Add-Type -AssemblyName System.Windows.Forms
$driverPath = Join-Path $PSScriptRoot 'Test-SalamanderGui-LongPaths.ps1'
$source = [IO.File]::ReadAllText($driverPath)
$match = [regex]::Match($source, "(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@")
if (-not $match.Success) { throw 'GUI Win32 interop definition not found.' }
if ($source -notmatch '(?s)function Set-VerifiedNavigationClipboard.*?Set-NativeNavigationClipboard') {
    throw 'Navigation must use non-OLE global UTF-16 clipboard memory.'
}
Add-Type -TypeDefinition $match.Groups[1].Value

$root = Join-Path ([IO.Path]::GetTempPath()) ('OpenSal-ClipboardTest-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$reader = Join-Path $root 'reader.ps1'
$result = Join-Path $root 'read.txt'
$original = $null
$owner = [Windows.Forms.Control]::new()
try {
    $original = [Windows.Forms.Clipboard]::GetDataObject()
    $text = 'C:\Release-F3_東京_😀\normal'
    $handle = $owner.Handle
    if ($handle -eq [IntPtr]::Zero) { throw 'Clipboard owner HWND was not created.' }
    [SalamanderGuiNative]::SetClipboardUnicodeText($handle, $text)
    if ([Windows.Forms.Clipboard]::GetText() -cne $text) {
        throw 'The global UTF-16 clipboard payload was not preserved.'
    }

    @'
param([string]$Output)
Add-Type -AssemblyName System.Windows.Forms
[IO.File]::WriteAllText($Output, [Windows.Forms.Clipboard]::GetText())
'@ | Set-Content -LiteralPath $reader -Encoding utf8
    $process = Start-Process -FilePath (Join-Path $PSHOME 'pwsh.exe') -ArgumentList @(
        '-Sta', '-NoLogo', '-NoProfile', '-NonInteractive', '-File',
        ('"' + $reader + '"'), ('"' + $result + '"')
    ) -PassThru
    try {
        if (-not $process.WaitForExit(10000)) {
            $process.Kill()
            [void]$process.WaitForExit(4000)
            throw 'Cross-process clipboard reader stalled while owner STA was blocked.'
        }
        if ($process.ExitCode -ne 0 -or
            -not [IO.File]::Exists($result) -or
            [IO.File]::ReadAllText($result) -cne $text) {
            throw 'Second process could not read UTF-16 text while clipboard owner was blocked.'
        }
    }
    finally { $process.Dispose() }
    Write-Host 'PASS: cross-process CF_UNICODETEXT is independently readable while writer STA is blocked.'

    # A second process deliberately owns the clipboard for a short interval.
    # The navigation writer must wait only for OpenClipboard, without clearing
    # or dispatching any GUI command during the contention.
    $holderPath = Join-Path $root 'clipboard-holder.ps1'
    $readyPath = Join-Path $root 'clipboard-held.txt'
    @'
param([Parameter(Mandatory)][string]$Ready, [Parameter(Mandatory)][int]$HoldMilliseconds)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class ClipboardHoldNative {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool OpenClipboard(IntPtr window);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool CloseClipboard();
}
"@
$opened = $false
try {
    for ($attempt = 0; $attempt -lt 40; ++$attempt) {
        if ([ClipboardHoldNative]::OpenClipboard([IntPtr]::Zero)) {
            $opened = $true
            break
        }
        Start-Sleep -Milliseconds 50
    }
    if (-not $opened) { throw 'Clipboard fixture could not obtain its exclusive lock.' }
    [IO.File]::WriteAllText($Ready, 'locked')
    Start-Sleep -Milliseconds $HoldMilliseconds
}
finally {
    if ($opened) { [void][ClipboardHoldNative]::CloseClipboard() }
}
'@ | Set-Content -LiteralPath $holderPath -Encoding utf8

    function Start-ClipboardHolder {
        param([int]$HoldMilliseconds)
        Remove-Item -LiteralPath $readyPath -ErrorAction SilentlyContinue
        $args = @('-NoLogo', '-NoProfile', '-NonInteractive', '-File',
                  ('"' + $holderPath + '"'), '-Ready', ('"' + $readyPath + '"'),
                  '-HoldMilliseconds', [string]$HoldMilliseconds)
        $child = Start-Process -FilePath (Join-Path $PSHOME 'pwsh.exe') -ArgumentList $args -PassThru
        $deadline = [DateTime]::UtcNow.AddSeconds(5)
        while (-not [IO.File]::Exists($readyPath)) {
            if ($child.HasExited -or [DateTime]::UtcNow -ge $deadline) {
                try { if (-not $child.HasExited) { $child.Kill() } }
                finally { $child.Dispose() }
                throw 'Exclusive clipboard holder failed to start in time.'
            }
            Start-Sleep -Milliseconds 20
        }
        return $child
    }

    $retryText = $text + '\retry'
    $holder = Start-ClipboardHolder -HoldMilliseconds 500
    try {
        [SalamanderGuiNative]::SetClipboardUnicodeText($handle, $retryText)
        if ([Windows.Forms.Clipboard]::GetText() -cne $retryText) {
            throw 'Transient clipboard contention did not preserve the exact UTF-16 text.'
        }
        if (-not $holder.WaitForExit(5000) -or $holder.ExitCode -ne 0) {
            throw 'Transient clipboard holder did not exit cleanly.'
        }
    }
    finally {
        if (-not $holder.HasExited) {
            $holder.Kill()
            [void]$holder.WaitForExit(4000)
        }
        $holder.Dispose()
    }

    $holder = Start-ClipboardHolder -HoldMilliseconds 2600
    try {
        $rejected = $false
        try {
            [SalamanderGuiNative]::SetClipboardUnicodeText($handle, $text + '\must-not-write')
        }
        catch {
            if ($_.Exception.Message -match 'OpenClipboard.*(busy|failed).*after') {
                $rejected = $true
            }
            else {
                throw
            }
        }
        if (-not $rejected) {
            throw 'Persistent clipboard lock must be rejected within the retry bound.'
        }
        if (-not $holder.WaitForExit(5000) -or $holder.ExitCode -ne 0) {
            throw 'Persistent clipboard holder did not exit cleanly.'
        }
        if ([Windows.Forms.Clipboard]::GetText() -cne $retryText) {
            throw 'Failed clipboard acquisition must not replace the existing clipboard.'
        }
    }
    finally {
        if (-not $holder.HasExited) {
            $holder.Kill()
            [void]$holder.WaitForExit(4000)
        }
        $holder.Dispose()
    }
    Write-Host 'PASS: transient clipboard lock retries safely; persistent lock fails without mutation.'

}
finally {
    try {
        if ($null -ne $original) {
            [Windows.Forms.Clipboard]::SetDataObject($original, $true)
        }
        else {
            [Windows.Forms.Clipboard]::Clear()
        }
    }
    catch { Write-Warning "Could not restore clipboard after native regression: $($_.Exception.Message)" }
    $owner.Dispose()
    Remove-Item -LiteralPath $root -Force -Recurse -ErrorAction SilentlyContinue
}
