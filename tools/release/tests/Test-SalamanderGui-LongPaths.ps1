#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
    Tests Salamander's GUI with Unicode names and paths >260 UTF-16 units.
.DESCRIPTION
    Requires unlocked interactive Windows desktop and PowerShell 7 in STA.
    Uses the documented Shift+F7, Ctrl+Alt+Insert, Alt+Shift+Insert, F5
    shortcuts. Only creates/operates on disposable temporary files.
    An explicit failure means no long-path GUI compatibility was proven.
.EXAMPLE
    pwsh -Sta -NoProfile -File .\tools\release\tests\Test-SalamanderGui-LongPaths.ps1
#>
[CmdletBinding()]
param(
    [string]$SalamanderExe = 'D:\Build\OpenSal\salamander\Release_x64\salamand.exe',
    [ValidateRange(5,120)][int]$TimeoutSeconds = 25,
    [switch]$KeepFixture
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'This GUI test requires Windows.' }
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    throw 'Use STA mode: pwsh -Sta -NoProfile -File Test-SalamanderGui-LongPaths.ps1'
}
if (-not (Test-Path -LiteralPath $SalamanderExe -PathType Leaf)) {
    throw "Salamander executable missing: $SalamanderExe"
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SalamanderGuiNative
{
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
}
'@

$oldClipboard = $null
try { $oldClipboard = [System.Windows.Forms.Clipboard]::GetDataObject() }
catch { Write-Warning 'Original clipboard could not be saved.' }

$root = Join-Path ([IO.Path]::GetTempPath()) ('OpenSal-GuiLong-' + [guid]::NewGuid().ToString('N'))
$source = Join-Path $root 'source'
$destination = Join-Path $root 'destination'
$deep = $source
$process = $null
$passed = $false
$utfName = 'Größe_東京_😀.txt'
$payload = [Text.Encoding]::UTF8.GetBytes(('Regression-äöü-東京-😀' * 1024))

function Assert-True {
    param([bool]$Condition, [string]$Description)
    if (-not $Condition) { throw "FAIL: $Description" }
    Write-Host "PASS: $Description"
}

function Wait-Until {
    param([scriptblock]$Condition, [string]$Description)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        if (& $Condition) { return }
        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Timeout waiting for $Description"
}

function Get-ActiveProcessId {
    [uint32]$id = 0
    $h = [SalamanderGuiNative]::GetForegroundWindow()
    [void][SalamanderGuiNative]::GetWindowThreadProcessId($h, [ref]$id)
    return $id
}

function Focus-TestProcess {
    $process.Refresh()
    if ($process.HasExited) { throw 'Test Salamander process terminated unexpectedly.' }
    $h = $process.MainWindowHandle
    if ($h -eq [IntPtr]::Zero) { throw 'No main window for test Salamander.' }
    [void][SalamanderGuiNative]::ShowWindow($h, 9)
    [void][SalamanderGuiNative]::SetForegroundWindow($h)
    Wait-Until { (Get-ActiveProcessId) -eq [uint32]$process.Id } 'test application to be foreground'
}

function Send-Keys {
    param([string]$Keys)
    if ((Get-ActiveProcessId) -ne [uint32]$process.Id) {
        throw 'Refusing to send input to a window owned by another process.'
    }
    [Windows.Forms.SendKeys]::SendWait($Keys)
    Start-Sleep -Milliseconds 200
}

function Set-ClipboardText {
    param([string]$Text)
    for ($i=0; $i -lt 10; $i++) {
        try { [Windows.Forms.Clipboard]::SetText($Text); return }
        catch { Start-Sleep -Milliseconds 100 }
    }
    throw 'Clipboard unavailable for GUI input.'
}

function Get-ClipboardText {
    for ($i=0; $i -lt 10; $i++) {
        try { return [Windows.Forms.Clipboard]::GetText() }
        catch { Start-Sleep -Milliseconds 100 }
    }
    throw 'Clipboard unavailable for GUI assertion.'
}

function Read-PanelPath {
    Set-ClipboardText 'SENTINEL_NOT_PATH'
    Send-Keys '^%{INSERT}'
    Wait-Until { (Get-ClipboardText) -ne 'SENTINEL_NOT_PATH' } 'panel path clipboard shortcut'
    return (Get-ClipboardText).TrimEnd([char]13, [char]10)
}

function Go-ToPath {
    param([string]$Path)
    Focus-TestProcess
    Set-ClipboardText $Path
    Send-Keys '+{F7}'
    Start-Sleep -Milliseconds 400
    Send-Keys '^a'
    Send-Keys '^v'
    Send-Keys '{ENTER}'
    Wait-Until {
        try {
            Focus-TestProcess
            return (Read-PanelPath) -ceq $Path
        }
        catch { return $false }
    } "Salamander navigation to $Path"
    Assert-True ((Read-PanelPath) -ceq $Path) 'Salamander panel preserves entire long UTF-16 directory path'
}

function Read-FocusedFilename {
    Set-ClipboardText 'SENTINEL_NOT_FILENAME'
    Send-Keys '%+{INSERT}'
    Wait-Until { (Get-ClipboardText) -ne 'SENTINEL_NOT_FILENAME' } 'focused file name clipboard shortcut'
    return (Get-ClipboardText).TrimEnd([char]13, [char]10)
}

function Test-Content {
    param([string]$Path)
    if (-not [IO.File]::Exists($Path)) { return $false }
    return [Linq.Enumerable]::SequenceEqual[byte]([IO.File]::ReadAllBytes($Path), $payload)
}

function Save-FailureScreenshot {
    try {
        $b = [Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bitmap = [Drawing.Bitmap]::new($b.Width, $b.Height)
        try {
            $graphics = [Drawing.Graphics]::FromImage($bitmap)
            try { $graphics.CopyFromScreen($b.Left, $b.Top, 0, 0, $b.Size) }
            finally { $graphics.Dispose() }
            $file = Join-Path $root 'gui-failure.png'
            $bitmap.Save($file, [Drawing.Imaging.ImageFormat]::Png)
            Write-Warning "Screenshot of failed GUI test: $file"
        }
        finally { $bitmap.Dispose() }
    }
    catch { Write-Warning "Screenshot unavailable: $($_.Exception.Message)" }
}

try {
    # ARRANGE: no real user files are touched.
    [IO.Directory]::CreateDirectory($source) | Out-Null
    [IO.Directory]::CreateDirectory($destination) | Out-Null
    foreach ($n in 1..5) {
        $deep = Join-Path $deep ('depth-' + $n + '-' + ('x' * 56))
        [IO.Directory]::CreateDirectory($deep) | Out-Null
    }
    $sourceFile = Join-Path $deep $utfName
    [IO.File]::WriteAllBytes($sourceFile, $payload)
    Assert-True ($sourceFile.Length -gt 260) 'Test file absolute path exceeds 260 UTF-16 units'

    # Never attach keystrokes to an existing user instance.
    if (@(Get-Process salamand -ErrorAction SilentlyContinue).Count -gt 0) {
        throw 'Please close existing Salamander instances before running automated GUI tests.'
    }
    $process = Start-Process -FilePath $SalamanderExe -WorkingDirectory (Split-Path -Parent $SalamanderExe) -PassThru
    Wait-Until {
        $process.Refresh()
        (-not $process.HasExited) -and ($process.MainWindowHandle -ne [IntPtr]::Zero)
    } 'Salamander main window'
    Focus-TestProcess

    # ACT + ASSERT: actual GUI directory change and filename retrieval.
    Go-ToPath $deep
    Send-Keys '{END}'
    Assert-True ((Read-FocusedFilename) -ceq $utfName) 'Salamander panel preserves Unicode filename'

    # ACT + ASSERT: real F5 copy, destination verified by independent byte read.
    Send-Keys '{TAB}'
    Go-ToPath $destination
    Send-Keys '{TAB}'
    Assert-True ((Read-PanelPath) -ceq $deep) 'Source panel still shows long path'
    Send-Keys '{END}'
    Assert-True ((Read-FocusedFilename) -ceq $utfName) 'Correct source selected before copy'
    Send-Keys '{F5}'
    Start-Sleep -Milliseconds 400
    Send-Keys '{ENTER}'
    $targetFile = Join-Path $destination $utfName
    Wait-Until { Test-Content $targetFile } 'F5 copy and byte verification'
    Assert-True (Test-Content $targetFile) 'F5 copy retains all UTF-8 file bytes'

    $passed = $true
    Write-Host 'PASS: REAL Salamander GUI long path, Unicode filename, F5 copy.'
    Write-Warning 'F2/F6/F8, plugins, 255-unit names and UNC need separate GUI coverage.'
}
catch {
    Write-Warning "GUI integration FAILED: $($_.Exception.Message)"
    Save-FailureScreenshot
    throw
}
finally {
    if ($null -ne $process) {
        try {
            if (-not $process.HasExited) {
                [void]$process.CloseMainWindow()
                if (-not $process.WaitForExit(4000)) {
                    $process.Kill()
                    [void]$process.WaitForExit(4000)
                }
            }
        }
        catch { Write-Warning "Could not stop test app: $($_.Exception.Message)" }
        $process.Dispose()
    }
    if ($oldClipboard) {
        try { [Windows.Forms.Clipboard]::SetDataObject($oldClipboard, $true) }
        catch { Write-Warning 'Original clipboard could not be restored.' }
    }
    if ($passed -and -not $KeepFixture) {
        try { [IO.Directory]::Delete($root, $true) }
        catch { Write-Warning "Test fixture cleanup failed: $root - $($_.Exception.Message)" }
    }
    else {
        Write-Host "Diagnostic fixture retained: $root"
    }
}
