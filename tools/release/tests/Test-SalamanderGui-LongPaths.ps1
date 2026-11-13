#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
    Tests Salamander's GUI with Unicode names and paths >260 UTF-16 units.
.DESCRIPTION
    Requires unlocked interactive Windows desktop and PowerShell 7 in STA.
    Uses documented Ctrl+V, Ctrl+Alt+Insert, Alt+Shift+Insert, F2/F5/F6/F8
    shortcuts. Only creates/operates on disposable temporary files.
    An explicit failure means no long-path GUI compatibility was proven.
.EXAMPLE
    pwsh -Sta -NoProfile -File .\tools\release\tests\Test-SalamanderGui-LongPaths.ps1
#>
[CmdletBinding()]
param(
    [string]$SalamanderExe = 'D:\Build\OpenSal\salamander\Release_x64\salamand.exe',
    [ValidateRange(5,120)][int]$TimeoutSeconds = 25,
    [switch]$KeepFixture,
    [switch]$BaselineOnly,
    [switch]$ShortUnicodeOnly
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
using System.Collections.Generic;
using System.Text;
public static class SalamanderGuiNative
{
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowTextW(IntPtr window, StringBuilder buffer, int capacity);
    [DllImport("user32.dll")]
    public static extern IntPtr GetLastActivePopup(IntPtr window);
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr window);
    public delegate bool WindowCallback(IntPtr window, IntPtr parameter);
    [DllImport("user32.dll")]
    private static extern bool EnumChildWindows(IntPtr window, WindowCallback callback, IntPtr parameter);

    // A dialog's message is in child controls; the caption alone is ambiguous.
    public static string DescribeWindow(IntPtr window) {
        List<string> messages = new List<string>();
        StringBuilder caption = new StringBuilder(512);
        GetWindowTextW(window, caption, caption.Capacity);
        if (caption.Length > 0) messages.Add(caption.ToString());
        WindowCallback callback = (child, parameter) => {
            StringBuilder label = new StringBuilder(512);
            GetWindowTextW(child, label, label.Capacity);
            if (label.Length > 0 && messages.Count < 12)
                messages.Add(label.ToString());
            return true;
        };
        EnumChildWindows(window, callback, IntPtr.Zero);
        return string.Join(" | ", messages);
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct GuiRect { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out GuiRect rect);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
}
'@

$oldClipboard = $null
try { $oldClipboard = [System.Windows.Forms.Clipboard]::GetDataObject() }
catch { Write-Warning 'Original clipboard could not be saved.' }

$root = Join-Path ([IO.Path]::GetTempPath()) ('OpenSal-GuiLong-' + [guid]::NewGuid().ToString('N'))
$source = Join-Path $root 'source'
$destination = Join-Path $root 'destination'
$moveDir = Join-Path $root 'move-target'
$maxDir = Join-Path $root 'maximum-names'
$maxName = ('n' * 251) + '.txt'
$renamedName = 'Umbenannt_日本_😀.txt'
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

function Get-TestDialog {
    if ($null -eq $process) { return $null }
    $process.Refresh()
    if ($process.HasExited) { return $null }
    $main = $process.MainWindowHandle
    $popup = [SalamanderGuiNative]::GetLastActivePopup($main)
    $foreground = [SalamanderGuiNative]::GetForegroundWindow()
    [uint32]$ownerPid = 0
    [void][SalamanderGuiNative]::GetWindowThreadProcessId($foreground, [ref]$ownerPid)
    if ($ownerPid -eq [uint32]$process.Id -and $foreground -ne $main) {
        return [SalamanderGuiNative]::DescribeWindow($foreground)
    }
    if ($popup -ne [IntPtr]::Zero -and $popup -ne $main -and
        [SalamanderGuiNative]::IsWindowVisible($popup)) {
        return [SalamanderGuiNative]::DescribeWindow($popup)
    }
    return $null
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
    # Salamander's documented Edit > Paste (Ctrl+V) directly changes the
    # active panel to a directory stored as plain clipboard text. Avoid
    # Shift+F7 here: its modal dialog was not reliably detected and blocked
    # even the short-path automation baseline on a real desktop.
    #
    # The clipboard contains only CF_UNICODETEXT, never CF_HDROP, so this
    # does not instruct Salamander to copy/move user files.
    Set-ClipboardText $Path
    Assert-True ((Get-ClipboardText) -ceq $Path) 'Clipboard contains only the requested text path'
    Send-Keys '^v'
    Wait-Until {
        $dialogText = Get-TestDialog
        if ($dialogText -match 'Error Changing Directory|too long name|Cannot finish operation') {
            throw "Salamander rejected path '$Path': $dialogText"
        }
        if ((Get-ActiveProcessId) -ne [uint32]$process.Id) { return $false }
        # Do not force main window to the foreground here. Doing so hides
        # native error dialogs and turns a genuine application error into a timeout.
        try { return (Read-PanelPath) -ceq $Path }
        catch {
            $dialogText = Get-TestDialog
            if ($dialogText -match 'Error Changing Directory|too long name') {
                throw "Salamander rejected path '$Path': $dialogText"
            }
            return $false
        }
    } "Salamander navigation to $Path"
    Assert-True ((Read-PanelPath) -ceq $Path) "Salamander panel path agrees with requested ($($Path.Length) UTF-16 units)"
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
        # Save only the app window; other desktop windows may contain private data.
        if ($null -eq $process -or $process.HasExited) { return }
        $shotWindow = $process.MainWindowHandle
        $foreground = [SalamanderGuiNative]::GetForegroundWindow()
        [uint32]$ownerPid = 0
        [void][SalamanderGuiNative]::GetWindowThreadProcessId($foreground, [ref]$ownerPid)
        if ($ownerPid -eq [uint32]$process.Id) { $shotWindow = $foreground }
        $b = [SalamanderGuiNative+GuiRect]::new()
        if (-not [SalamanderGuiNative]::GetWindowRect($shotWindow, [ref]$b)) { return }
        $width = $b.Right - $b.Left
        $height = $b.Bottom - $b.Top
        if ($width -le 0 -or $height -le 0) { return }
        $bitmap = [Drawing.Bitmap]::new($width, $height)
        try {
            $graphics = [Drawing.Graphics]::FromImage($bitmap)
            try { $graphics.CopyFromScreen($b.Left, $b.Top, 0, 0, [Drawing.Size]::new($width, $height)) }
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
    # Independent Unicode-only fixture: total path safely below MAX_PATH.
    $unicodeShortFile = Join-Path $source $utfName
    [IO.File]::WriteAllBytes($unicodeShortFile, $payload)
    Assert-True ($unicodeShortFile.Length -lt 260) 'Unicode-only fixture fits below MAX_PATH'
    [IO.Directory]::CreateDirectory($destination) | Out-Null
    [IO.Directory]::CreateDirectory($moveDir) | Out-Null
    [IO.Directory]::CreateDirectory($maxDir) | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $maxDir $maxName), $payload)
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

    # First validate the GUI driver against a normal short path. If this
    # fails, treat it as an automation/infrastructure problem, NOT as proof
    # that the application lacks long-path support.
    Go-ToPath $source
    Assert-True ((Read-PanelPath) -ceq $source) 'GUI driver can navigate a normal short directory'
    if ($BaselineOnly) {
        $passed = $true
        Write-Host 'PASS: GUI automation driver works with short ASCII paths.'
        return
    }

    if ($ShortUnicodeOnly) {
        # A failure here is a Unicode/ANSI filename issue, not a path-length
        # failure: the full path has been checked to be below MAX_PATH.
        Send-Keys '{END}'
        Assert-True ((Read-FocusedFilename) -ceq $utfName) 'Short Unicode name preserved in Salamander panel'
        Assert-True (Test-Content $unicodeShortFile) 'Unicode-only file bytes preserved'
        $passed = $true
        Write-Host 'PASS: Salamander GUI supports a Unicode name on a short path.'
        return
    }

    # ACT + ASSERT: actual GUI long directory change and filename retrieval.
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

    # ACT + ASSERT: F2 renames the selected Unicode file in our test directory.
    Send-Keys '{TAB}'
    Assert-True ((Read-PanelPath) -ceq $destination) 'Destination panel active before rename'
    Send-Keys '{END}'
    Assert-True ((Read-FocusedFilename) -ceq $utfName) 'Copied file selected before F2'
    Set-ClipboardText $renamedName
    Send-Keys '{F2}'
    Start-Sleep -Milliseconds 350
    Send-Keys '^a'
    Send-Keys '^v'
    Send-Keys '{ENTER}'
    $renamedFile = Join-Path $destination $renamedName
    Wait-Until { (Test-Content $renamedFile) -and -not [IO.File]::Exists($targetFile) } 'F2 Unicode rename with byte integrity'
    Assert-True (Test-Content $renamedFile) 'F2 Unicode rename preserved bytes'

    # ACT + ASSERT: F6 moves from the verified destination to another
    # disposable panel directory. Do not send F6 without verifying both.
    Send-Keys '{TAB}'
    Go-ToPath $moveDir
    Send-Keys '{TAB}'
    Assert-True ((Read-PanelPath) -ceq $destination) 'Source panel verified before F6'
    Send-Keys '{END}'
    Assert-True ((Read-FocusedFilename) -ceq $renamedName) 'Correct source file selected before F6'
    Send-Keys '{F6}'
    Start-Sleep -Milliseconds 400
    Send-Keys '{ENTER}'
    $movedFile = Join-Path $moveDir $renamedName
    Wait-Until { (Test-Content $movedFile) -and -not [IO.File]::Exists($renamedFile) } 'F6 Unicode move with byte integrity'
    Assert-True (Test-Content $movedFile) 'F6 move preserved all bytes'

    # ACT + ASSERT: F8 deletes ONLY the fixture item after verifying the panel.
    Send-Keys '{TAB}'
    Assert-True ((Read-PanelPath) -ceq $moveDir) 'Deletion panel verified as disposable fixture'
    Send-Keys '{END}'
    Assert-True ((Read-FocusedFilename) -ceq $renamedName) 'Correct item selected before F8'
    Send-Keys '{F8}'
    Start-Sleep -Milliseconds 350
    Send-Keys '{ENTER}'
    Wait-Until { -not [IO.File]::Exists($movedFile) } 'F8 deletion of disposable Unicode file'
    Assert-True (-not [IO.File]::Exists($movedFile)) 'F8 removed only the selected test file'

    # ACT + ASSERT: a maximum-size single path component is not a long
    # absolute path. The filename must be preserved exactly, not truncated.
    Go-ToPath $maxDir
    Send-Keys '{END}'
    Assert-True ((Read-FocusedFilename) -ceq $maxName) '255-unit ASCII filename visible in Salamander panel'
    Assert-True (Test-Content (Join-Path $maxDir $maxName)) '255-unit filename data intact'

    $passed = $true
    Write-Host 'PASS: REAL Salamander GUI long paths, Unicode, F2/F5/F6/F8, 255-unit names.'
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
