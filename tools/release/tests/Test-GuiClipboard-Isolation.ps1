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
