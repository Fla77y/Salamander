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
    blocks the writer while a second process reads CF_UNICODETEXT and inspects
    the OLE IDataObject format enumeration.
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
Add-Type -TypeDefinition $match.Groups[1].Value -ErrorAction Stop

$root = Join-Path ([IO.Path]::GetTempPath()) ('OpenSal-ClipboardTest-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$reader = Join-Path $root 'reader.ps1'
$original = $null
$owner = [SalamanderGuiClipboardOwner]::new()
try {
    $original = [Windows.Forms.Clipboard]::GetDataObject()
    $text = 'C:\Release-F3_東京_😀\normal'
    if ($owner.OwnerThreadId -eq [Threading.Thread]::CurrentThread.ManagedThreadId) {
        throw 'Clipboard owner must have an independent STA message pump.'
    }
    $owner.SetText($text)
    if ([Windows.Forms.Clipboard]::GetText() -cne $text) {
        throw 'The global UTF-16 clipboard payload was not preserved.'
    }

    # Exercise the native text path and OLE format enumeration separately.
    # A stage file identifies exactly which call stalls without pumping the
    # management STA, matching its synchronous GUI-command behaviour.
    @'
param(
    [Parameter(Mandatory)][string]$Output,
    [Parameter(Mandatory)][string]$Stage,
    [Parameter(Mandatory)][ValidateSet('Text','Ole')][string]$Mode
)
$ErrorActionPreference = 'Stop'
function Set-Stage([string]$Value) {
    [IO.File]::WriteAllText($Stage, $Value)
}
Set-Stage 'child started'
try {
    if ($Mode -eq 'Text') {
        Add-Type -AssemblyName System.Windows.Forms
        Set-Stage 'before Clipboard.GetText'
        $value = [Windows.Forms.Clipboard]::GetText()
        Set-Stage 'after Clipboard.GetText'
        [IO.File]::WriteAllText($Output, $value)
    }
    else {
        Set-Stage 'before OLE interop compilation'
        Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
public static class SalamanderClipboardOleProbe
{
    [DllImport("ole32.dll")]
    private static extern int OleInitialize(IntPtr reserved);
    [DllImport("ole32.dll")]
    private static extern void OleUninitialize();
    [DllImport("ole32.dll")]
    private static extern int OleGetClipboard(out IDataObject data);

    public static void InspectFormats(string stagePath)
    {
        int initialized = OleInitialize(IntPtr.Zero);
        if (initialized < 0)
            throw new InvalidOperationException(
                "OleInitialize failed: HRESULT 0x" + initialized.ToString("X8"));
        try
        {
            File.WriteAllText(stagePath, "before OleGetClipboard");
            IDataObject data = null;
            int hr = OleGetClipboard(out data);
            if (hr != 0 || data == null)
                throw new InvalidOperationException(
                    "OleGetClipboard failed: HRESULT 0x" + hr.ToString("X8"));
            try
            {
                File.WriteAllText(stagePath, "before IDataObject.EnumFormatEtc");
                IEnumFORMATETC formats = data.EnumFormatEtc(DATADIR.DATADIR_GET);
                if (formats == null)
                    throw new InvalidOperationException(
                        "OLE clipboard has no format enumerator.");
                try {
                    File.WriteAllText(stagePath, "OLE formats enumerated");
                }
                finally { Marshal.ReleaseComObject(formats); }
            }
            finally { Marshal.ReleaseComObject(data); }
        }
        finally { OleUninitialize(); }
    }
}
"@
        Set-Stage 'before OLE inspection'
        [SalamanderClipboardOleProbe]::InspectFormats($Stage)
    }
    Set-Stage 'completed'
}
catch {
    Set-Stage ("FAILED: " + $_.Exception.Message)
    throw
}
'@ | Set-Content -LiteralPath $reader -Encoding utf8

    foreach ($mode in @('Text', 'Ole')) {
        $readOutput = Join-Path $root ('read-' + $mode + '.txt')
        $stageFile = Join-Path $root ('stage-' + $mode + '.txt')
        $process = Start-Process -FilePath (Join-Path $PSHOME 'pwsh.exe') -ArgumentList @(
            '-Sta', '-NoLogo', '-NoProfile', '-NonInteractive', '-File',
            ('"' + $reader + '"'), ('"' + $readOutput + '"'),
            ('"' + $stageFile + '"'), $mode
        ) -PassThru
        try {
            if (-not $process.WaitForExit(15000)) {
                $stage = if ([IO.File]::Exists($stageFile)) {
                    [IO.File]::ReadAllText($stageFile)
                } else { '<child did not reach its first stage>' }
                $process.Kill()
                [void]$process.WaitForExit(4000)
                throw (("Cross-process clipboard {0} reader stalled while the " +
                        "management STA was blocked; last stage: {1}.") -f
                       $mode, $stage)
            }
            if ($process.ExitCode -ne 0) {
                $stage = if ([IO.File]::Exists($stageFile)) {
                    [IO.File]::ReadAllText($stageFile)
                } else { '<no stage marker>' }
                throw (("Cross-process clipboard {0} reader exited with code {1}; " +
                        "last stage: {2}.") -f $mode, $process.ExitCode, $stage)
            }
            if ($mode -eq 'Text' -and
                (-not [IO.File]::Exists($readOutput) -or
                [IO.File]::ReadAllText($readOutput) -cne $text)) {
                throw 'Cross-process CF_UNICODETEXT payload was not preserved.'
            }
            Write-Host "PASS: cross-process clipboard $mode reader completed while management STA was blocked."
        }
        finally { $process.Dispose() }
    }

    # The next clipboard owner may be this blocked test STA itself. This
    # catches WM_DESTROYCLIPBOARD callbacks during a cross-STA replacement.
    [Windows.Forms.Clipboard]::SetText('OLE previous owner is the management STA')
    $replacementText = $text + '\owner-switch'
    $owner.SetText($replacementText)
    if ([Windows.Forms.Clipboard]::GetText() -cne $replacementText) {
        throw 'Replacing an OLE clipboard owned by the management STA failed.'
    }
    Write-Host 'PASS: STA owner replacement pumps previous-owner clipboard notifications.'

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
        $owner.SetText($retryText)
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

    # PowerShell wraps C# method failures in MethodInvocationException.
    # The clipboard owner STA adds its own exception around the native
    # OpenClipboard failure; inspect the complete cause chain, not just
    # the outer exception message.
    function Test-ExpectedClipboardLockFailure {
        param([Parameter(Mandatory)][Exception]$Exception)
        $cause = $Exception
        for ($depth = 0; $null -ne $cause -and $depth -lt 16; $depth++) {
            if ($cause -is [InvalidOperationException] -and
                $cause.Message -ceq 'OpenClipboard busy after 16 attempts; last Win32 error 5') {
                return $true
            }
            $cause = $cause.InnerException
        }
        return $false
    }

    # Verify that nested error 5 is recognized but unrelated errors and
    # owner thread timeouts cannot make the negative test pass.
    $busy = [InvalidOperationException]::new(
        'OpenClipboard busy after 16 attempts; last Win32 error 5')
    $wrappedBusy = [InvalidOperationException]::new(
        'Clipboard owner could not publish CF_UNICODETEXT.', $busy)
    $invocationBusy = [Reflection.TargetInvocationException]::new($wrappedBusy)
    $wrongError = [InvalidOperationException]::new('OpenClipboard failed: 6')
    $timeoutError = [TimeoutException]::new(
        'Clipboard owner STA did not publish CF_UNICODETEXT.')
    if (-not (Test-ExpectedClipboardLockFailure -Exception $invocationBusy) -or
        (Test-ExpectedClipboardLockFailure -Exception $wrongError) -or
        (Test-ExpectedClipboardLockFailure -Exception $timeoutError)) {
        throw 'Clipboard lock classifier accepted a failure other than native Win32 error 5.'
    }
    Write-Host 'PASS: nested clipboard error 5 is recognized; unrelated failures remain fatal.'

    $holder = Start-ClipboardHolder -HoldMilliseconds 2600
    try {
        $rejected = $false
        try {
            $owner.SetText($text + '\must-not-write')
        }
        catch {
            if (Test-ExpectedClipboardLockFailure -Exception $_.Exception) {
                $rejected = $true
            }
            else {
                $chain = [Collections.Generic.List[string]]::new()
                $cause = $_.Exception
                for ($depth = 0; $null -ne $cause -and $depth -lt 16; $depth++) {
                    [void]$chain.Add(
                        ('{0}: {1}' -f $cause.GetType().FullName, $cause.Message))
                    $cause = $cause.InnerException
                }
                throw ('Unexpected clipboard lock failure: ' + ($chain -join ' -> '))
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
