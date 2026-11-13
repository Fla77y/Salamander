#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
    Tests Salamander's GUI with Unicode names and paths >260 UTF-16 units.
.DESCRIPTION
    Requires unlocked interactive Windows desktop and PowerShell 7 in STA.
    Uses documented Salamander commands and F2/F5/F6/F8 with synchronized clipboard access
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
    [switch]$ShortUnicodeOnly,
    [switch]$ShortUnicodeBestFitOnly,
    [switch]$ShortUnicodeCollisionOnly,
    [switch]$ShortUnicodeUnsafeOperationsOnly,
    [switch]$ShortOperationsOnly
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
    [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW", SetLastError = true)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint msg, UIntPtr wParam, IntPtr lParam,
        uint flags, uint timeoutMilliseconds, out IntPtr result);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowTextW(IntPtr window, StringBuilder buffer, int capacity);
    [DllImport("user32.dll")]
    public static extern IntPtr GetLastActivePopup(IntPtr window);
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")]
    public static extern bool IsHungAppWindow(IntPtr window);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int WideCharToMultiByte(
        uint codePage, uint flags, string source, int sourceLength,
        byte[] destination, int destinationLength, IntPtr defaultChar, IntPtr usedDefault);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int MultiByteToWideChar(
        uint codePage, uint flags, byte[] source, int sourceLength,
        [Out] char[] destination, int destinationLength);

    // Use Windows CP_ACP itself, not .NET's UTF-8 Encoding.Default, to
    // detect silent best-fit substitution without any '?' byte.
    public static bool HasLossyAliasWithoutQuestionMark(string name)
    {
        int bytes = WideCharToMultiByte(0, 0, name, -1, null, 0, IntPtr.Zero, IntPtr.Zero);
        if (bytes <= 1) return false;
        byte[] encoded = new byte[bytes];
        if (WideCharToMultiByte(0, 0, name, -1, encoded, bytes, IntPtr.Zero, IntPtr.Zero) != bytes)
            return false;
        for (int i = 0; i < bytes - 1; ++i)
            if (encoded[i] == (byte)'?') return false;
        int units = MultiByteToWideChar(0, 0, encoded, bytes, null, 0);
        if (units <= 1) return false;
        char[] roundTrip = new char[units];
        if (MultiByteToWideChar(0, 0, encoded, bytes, roundTrip, units) != units)
            return false;
        return !String.Equals(name, new String(roundTrip, 0, units - 1), StringComparison.Ordinal);
    }
    public static string GetLegacyFilenameAliasHex(string name)
    {
        if (String.IsNullOrEmpty(name)) throw new ArgumentException("Missing filename", "name");
        int bytes = WideCharToMultiByte(0, 0, name, -1, null, 0, IntPtr.Zero, IntPtr.Zero);
        if (bytes <= 1) throw new InvalidOperationException("Cannot encode ANSI filename alias");
        byte[] encoded = new byte[bytes];
        if (WideCharToMultiByte(0, 0, name, -1, encoded, bytes, IntPtr.Zero, IntPtr.Zero) != bytes)
            throw new InvalidOperationException("Cannot encode ANSI filename alias");
        return BitConverter.ToString(encoded, 0, bytes - 1);
    }
    public delegate bool WindowCallback(IntPtr window, IntPtr parameter);
    [DllImport("user32.dll")]
    private static extern bool EnumChildWindows(IntPtr window, WindowCallback callback, IntPtr parameter);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool EnumWindows(WindowCallback callback, IntPtr parameter);

    public sealed class TopLevelWindow
    {
        public IntPtr Handle { get; set; }
        public uint ProcessId { get; set; }
        public string Title { get; set; }
        public bool Visible { get; set; }
    }

    // Enumerate real top-level HWNDs, not Process.MainWindowHandle's heuristic.
    public static List<TopLevelWindow> GetProcessWindows(uint processId)
    {
        List<TopLevelWindow> windows = new List<TopLevelWindow>();
        WindowCallback callback = (window, parameter) =>
        {
            uint ownerPid;
            GetWindowThreadProcessId(window, out ownerPid);
            if (ownerPid == processId)
            {
                StringBuilder title = new StringBuilder(512);
                GetWindowTextW(window, title, title.Capacity);
                windows.Add(new TopLevelWindow
                {
                    Handle = window,
                    ProcessId = ownerPid,
                    Title = title.ToString(),
                    Visible = IsWindowVisible(window)
                });
            }
            return true;
        };
        if (!EnumWindows(callback, IntPtr.Zero))
            throw new InvalidOperationException("EnumWindows failed: " + Marshal.GetLastWin32Error());
        return windows;
    }

    // Select only a visible Salamander top-level window owned by our launched PID.
    public static IntPtr FindMainWindow(uint processId)
    {
        foreach (TopLevelWindow window in GetProcessWindows(processId))
        {
            if (window.Visible &&
                window.Title.IndexOf("Open Salamander", StringComparison.OrdinalIgnoreCase) >= 0)
                return window.Handle;
        }
        return IntPtr.Zero;
    }

    public static string GetWindowCaption(IntPtr window)
    {
        StringBuilder caption = new StringBuilder(512);
        GetWindowTextW(window, caption, caption.Capacity);
        return caption.ToString();
    }

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
$mainWindowHandle = [IntPtr]::Zero
$passed = $false
$utfName = 'Größe_東京_😀.txt'
$utfCollisionName = 'Größe_大阪_😀.txt'
$bestFitName = $null
$bestFitFile = $null
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

function Get-ProcessWindowSummary {
    param([uint32]$OwnerProcessId)

    $windows = [SalamanderGuiNative]::GetProcessWindows($OwnerProcessId)
    if ($windows.Count -eq 0) { return '<no top-level windows for launched process>' }
    $descriptions = foreach ($window in $windows) {
        $title = $window.Title.Replace([char]13, ' ').Replace([char]10, ' ')
        'HWND=0x{0:X} visible={1} title={2}' -f
            $window.Handle.ToInt64(), $window.Visible, $title
    }
    return ($descriptions -join '; ')
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
    $main = $mainWindowHandle
    if ($main -eq [IntPtr]::Zero) { return $null }
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
    $h = $mainWindowHandle
    if ($h -eq [IntPtr]::Zero) { throw 'No verified main window for test Salamander.' }
    [uint32]$windowPid = 0
    [void][SalamanderGuiNative]::GetWindowThreadProcessId($h, [ref]$windowPid)
    if ($windowPid -ne [uint32]$process.Id) {
        throw "Main window no longer belongs to launched Salamander PID $($process.Id)."
    }
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

# Salamander resource.rh2: CM_CLIPPASTE=775, CM_CLIPCOPYFULLPATH=711,
# CM_CLIPCOPYNAME=710. Dispatch synchronously to avoid racing with clipboard
# contents: SendKeys posts input, after which the test used to overwrite the
# clipboard before Salamander had consumed the original path.
function Invoke-SalamanderCommand {
    param(
        [ValidateSet(710,711,775)][int]$CommandId
    )
    $process.Refresh()
    if ($process.HasExited) { throw 'Salamander exited while dispatching a GUI command.' }
    $main = $mainWindowHandle
    if ($main -eq [IntPtr]::Zero) { throw 'Verified Salamander main window handle missing.' }
    [uint32]$ownerPid = 0
    [void][SalamanderGuiNative]::GetWindowThreadProcessId($main, [ref]$ownerPid)
    if ($ownerPid -ne [uint32]$process.Id) {
        throw "Refusing GUI command: window owner PID $ownerPid does not match test process $($process.Id)."
    }

    [IntPtr]$commandResult = [IntPtr]::Zero
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $sent = [SalamanderGuiNative]::SendMessageTimeout(
        $main, [uint32]0x0111, [UIntPtr]::new([uint32]$CommandId),
        [IntPtr]::Zero, [uint32]0x0002, [uint32]5000, [ref]$commandResult)
    # Do not call Get-TestDialog (or any other P/Invoke) before capturing
    # this error; otherwise the diagnostic loses the failed Win32 status.
    $lastError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    $timer.Stop()
    if ($sent -eq [IntPtr]::Zero) {
        $hung = [SalamanderGuiNative]::IsHungAppWindow($main)
        $dialog = Get-TestDialog
        throw ("Salamander command {0} did not complete after {1} ms; " +
            "SendMessageTimeout Win32 error {2}; IsHungAppWindow={3}; modal dialog='{4}'" -f
            $CommandId, $timer.ElapsedMilliseconds, $lastError, $hung, $dialog)
    }
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
    Invoke-SalamanderCommand -CommandId 711
    Wait-Until { (Get-ClipboardText) -ne 'SENTINEL_NOT_PATH' } 'panel path clipboard shortcut'
    return (Get-ClipboardText).TrimEnd([char]13, [char]10)
}

function Go-ToPath {
    param([string]$Path)
    Focus-TestProcess
    # Salamander's documented Edit > Paste command directly changes the
    # active panel to a directory stored as plain clipboard text. Avoid
    # Shift+F7 here: its modal dialog was not reliably detected and blocked
    # even the short-path automation baseline on a real desktop.
    #
    # The clipboard contains plain text (not CF_HDROP file data), so
    # Salamander interprets it as a directory to navigate to. Synchronous
    # WM_COMMAND dispatch ensures the path is consumed before we reset the
    # clipboard to query the panel path.
    Set-ClipboardText $Path
    Assert-True ((Get-ClipboardText) -ceq $Path) 'Clipboard contains only the requested text path'
    Invoke-SalamanderCommand -CommandId 775
    # Hashtable fields survive Wait-Until's child scriptblock scope and allow
    # the failure report to distinguish input failure from path rejection.
    $diagnostics = @{
        ForegroundPid = 0
        PanelPath = '<not read>'
        PanelReadError = '<none>'
    }
    try {
        Wait-Until {
            $dialogText = Get-TestDialog
            if ($dialogText -match 'Error Changing Directory|too long name|Cannot finish operation') {
                throw "Salamander rejected path '$Path': $dialogText"
            }
            $diagnostics.ForegroundPid = Get-ActiveProcessId
            if ($diagnostics.ForegroundPid -ne [uint32]$process.Id) { return $false }
            # Do not force main window to the foreground here. Doing so hides
            # native error dialogs and turns a genuine application error into a timeout.
            try {
                $diagnostics.PanelPath = Read-PanelPath
                $diagnostics.PanelReadError = '<none>'
                return $diagnostics.PanelPath -ceq $Path
            }
            catch {
                $diagnostics.PanelReadError = $_.Exception.Message
                $dialogText = Get-TestDialog
                if ($dialogText -match 'Error Changing Directory|too long name') {
                    throw "Salamander rejected path '$Path': $dialogText"
                }
                return $false
            }
        } "Salamander navigation to $Path"
    }
    catch {
        $process.Refresh()
        $dialogText = Get-TestDialog
        throw ("GUI navigation failed: {0}; Salamander PID={1}; HWND=0x{2:X}; title='{3}'; " +
            "foreground PID={4}; last panel path='{5}'; panel read error='{6}'; dialog='{7}'" -f
            $_.Exception.Message, $process.Id, $mainWindowHandle.ToInt64(),
            [SalamanderGuiNative]::GetWindowCaption($mainWindowHandle),
            $diagnostics.ForegroundPid, $diagnostics.PanelPath,
            $diagnostics.PanelReadError, $dialogText)
    }
    # Wait-Until already read the panel path and established equality.
    # Repeating the synchronous clipboard command can fail even after a
    # successful navigation, creating a false negative and extra races.
    Assert-True ($diagnostics.PanelPath -ceq $Path) "Salamander panel path agrees with requested ($($Path.Length) UTF-16 units)"
}

function Read-FocusedFilename {
    Set-ClipboardText 'SENTINEL_NOT_FILENAME'
    Invoke-SalamanderCommand -CommandId 710
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
        $shotWindow = $mainWindowHandle
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
    # ARRANGE: fixtures are scoped to the chosen test mode. In particular
    # a baseline-only pass must never be confused with a long-path pass.
    [IO.Directory]::CreateDirectory($source) | Out-Null
    Assert-True ($source.Length -lt 257) 'Short-path GUI baseline fixture is below MAX_PATH'
    if ($ShortOperationsOnly) {
        # Arrange an independent, short ASCII operation baseline before
        # migrating disk file operations. Never touch non-fixture files.
        [IO.Directory]::CreateDirectory($destination) | Out-Null
        [IO.Directory]::CreateDirectory($moveDir) | Out-Null
        $asciiName = 'baseline.txt'
        $asciiRenamedName = 'renamed-baseline.txt'
        [IO.File]::WriteAllBytes((Join-Path $source $asciiName), $payload)
    }
    if (-not $BaselineOnly -and -not $ShortOperationsOnly -and
        -not $ShortUnicodeBestFitOnly) {
        # Independent Unicode-only fixture with a short total path.
        $unicodeShortFile = Join-Path $source $utfName
        [IO.File]::WriteAllBytes($unicodeShortFile, $payload)
        Assert-True ($unicodeShortFile.Length -lt 260) 'Unicode filename fixture fits below MAX_PATH'
    }
    if ($ShortUnicodeBestFitOnly) {
        foreach ($unicodeChar in @(
            [char]0xFF21, [char]0xFF41, [char]0x2010,
            [char]0x2011, [char]0x2013, [char]0x2014,
            [char]0x2212, [char]0x2018, [char]0x2019,
            [char]0x2460, [char]0x2160
        )) {
            $candidate = 'bestfit_' + $unicodeChar + '.txt'
            if ([SalamanderGuiNative]::HasLossyAliasWithoutQuestionMark($candidate)) {
                $bestFitName = $candidate
                $bestFitFile = Join-Path $source $bestFitName
                [IO.File]::WriteAllBytes($bestFitFile, $payload)
                Assert-True ($bestFitFile.Length -lt 260) 'Best-fit Unicode filename fits below MAX_PATH'
                break
            }
        }
    }
    if ($ShortUnicodeCollisionOnly -or $ShortUnicodeUnsafeOperationsOnly) {
        # These distinct UTF-16 names may have the same CP_ACP alias.
        # A distinct marker protects against cross-file identity errors.
        if ($ShortUnicodeUnsafeOperationsOnly) {
            [IO.Directory]::CreateDirectory($destination) | Out-Null
        }
        $collisionFile = Join-Path $source $utfCollisionName
        $collisionPayload = [Text.Encoding]::UTF8.GetBytes('DISTINCT-OSAKA-FILE')
        [IO.File]::WriteAllBytes($collisionFile, $collisionPayload)
        Assert-True ($collisionFile.Length -lt 260) 'Unicode collision fixture uses a short path'
    }
    if (-not $BaselineOnly -and -not $ShortUnicodeOnly -and
        -not $ShortUnicodeCollisionOnly -and
        -not $ShortUnicodeBestFitOnly -and
        -not $ShortUnicodeUnsafeOperationsOnly -and -not $ShortOperationsOnly) {
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
        Assert-True ($sourceFile.Length -gt 260) 'Long-path fixture exceeds 260 UTF-16 units'
    }

    # Never attach keystrokes to an existing user instance.
    if (@(Get-Process salamand -ErrorAction SilentlyContinue).Count -gt 0) {
        throw 'Please close existing Salamander instances before running automated GUI tests.'
    }
    $process = Start-Process -FilePath $SalamanderExe -WorkingDirectory (Split-Path -Parent $SalamanderExe) -PassThru
    # Process.MainWindowHandle/MainWindowTitle may select an auxiliary
    # window. The GUI driver must use the HWND found by Win32 enumeration.
    try {
        Wait-Until {
            $process.Refresh()
            if ($process.HasExited) {
                throw 'Test Salamander exited before its main window became ready.'
            }
            $script:mainWindowHandle = [SalamanderGuiNative]::FindMainWindow([uint32]$process.Id)
            return $script:mainWindowHandle -ne [IntPtr]::Zero
        } 'visible Open Salamander top-level window owned by launched process'
    }
    catch {
        $process.Refresh()
        $windowSummary = Get-ProcessWindowSummary -OwnerProcessId ([uint32]$process.Id)
        throw ("GUI startup failed: {0}; launched PID={1}; .NET MainWindowHandle=0x{2:X}; " +
            ".NET title='{3}'; process windows: {4}" -f
            $_.Exception.Message, $process.Id, $process.MainWindowHandle.ToInt64(),
            $process.MainWindowTitle, $windowSummary)
    }
    $process.Refresh()
    $testIsAdmin = [Security.Principal.WindowsPrincipal]::new(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $windowTitle = [SalamanderGuiNative]::GetWindowCaption($mainWindowHandle)
    Write-Host ("GUI driver: Salamander PID = {0}; verified HWND = 0x{1:X}; title = '{2}'; test session elevated = {3}" -f
        $process.Id, $mainWindowHandle.ToInt64(), $windowTitle, $testIsAdmin)
    # Salamander marks its window title with '(Administrator)' when elevated.
    # UIPI can silently block SendKeys from a non-elevated PowerShell process.
    # Refuse to misclassify that as a path/name failure.
    if (-not $testIsAdmin -and $windowTitle -match '\(Administrator\)') {
        throw 'Salamander is elevated but the GUI-test PowerShell is not. Keyboard input can be blocked by Windows UIPI. Run both at the same integrity level, preferably both unelevated.'
    }
    Focus-TestProcess

    # First validate the GUI driver against a normal short path. If this
    # fails, treat it as an automation/infrastructure problem, NOT as proof
    # that the application lacks long-path support.
    Go-ToPath $source
    # Go-ToPath already verified the observed panel path. A duplicate
    # WM_COMMAND 711 adds no coverage and can race with GUI processing.
    Write-Host 'PASS: GUI driver can navigate a normal short directory'
    if ($BaselineOnly) {
        $passed = $true
        Write-Host 'PASS: GUI automation driver works with short ASCII paths.'
        return
    }

    if ($ShortOperationsOnly) {
        # ACT + ASSERT: establish F5, F2, F6 and F8 behavior on a short ASCII
        # path before changing the production file-operation engine.
        Send-Keys '{END}'
        Assert-True ((Read-FocusedFilename) -ceq $asciiName) 'ASCII source file selected for F5'
        Send-Keys '{TAB}'
        Go-ToPath $destination
        Send-Keys '{TAB}'
        Assert-True ((Read-PanelPath) -ceq $source) 'ASCII source panel active for F5'
        Send-Keys '{END}'
        Assert-True ((Read-FocusedFilename) -ceq $asciiName) 'Exact ASCII file selected before F5'
        Send-Keys '{F5}'
        Start-Sleep -Milliseconds 400
        Send-Keys '{ENTER}'
        $copied = Join-Path $destination $asciiName
        Wait-Until { Test-Content $copied } 'ASCII F5 copy'
        Assert-True (Test-Content (Join-Path $source $asciiName)) 'F5 preserved original ASCII source'

        Send-Keys '{TAB}'
        Assert-True ((Read-PanelPath) -ceq $destination) 'ASCII copy destination active for F2'
        Send-Keys '{END}'
        Assert-True ((Read-FocusedFilename) -ceq $asciiName) 'Exact ASCII file selected before F2'
        Set-ClipboardText $asciiRenamedName
        Send-Keys '{F2}'
        Start-Sleep -Milliseconds 350
        Send-Keys '^a'
        Send-Keys '^v'
        Send-Keys '{ENTER}'
        $renamed = Join-Path $destination $asciiRenamedName
        Wait-Until { (Test-Content $renamed) -and -not [IO.File]::Exists($copied) } 'ASCII F2 rename'

        Send-Keys '{TAB}'
        Go-ToPath $moveDir
        Send-Keys '{TAB}'
        Assert-True ((Read-PanelPath) -ceq $destination) 'ASCII source panel active for F6'
        Send-Keys '{END}'
        Assert-True ((Read-FocusedFilename) -ceq $asciiRenamedName) 'Exact ASCII file selected before F6'
        Send-Keys '{F6}'
        Start-Sleep -Milliseconds 400
        Send-Keys '{ENTER}'
        $moved = Join-Path $moveDir $asciiRenamedName
        Wait-Until { (Test-Content $moved) -and -not [IO.File]::Exists($renamed) } 'ASCII F6 move'

        Send-Keys '{TAB}'
        Assert-True ((Read-PanelPath) -ceq $moveDir) 'Disposable ASCII panel active for F8'
        Send-Keys '{END}'
        Assert-True ((Read-FocusedFilename) -ceq $asciiRenamedName) 'Exact disposable ASCII file selected before F8'
        Send-Keys '{F8}'
        Start-Sleep -Milliseconds 350
        Send-Keys '{ENTER}'
        Wait-Until { -not [IO.File]::Exists($moved) } 'ASCII F8 deletion'
        Assert-True (Test-Content (Join-Path $source $asciiName)) 'Original ASCII source unaffected by F8'

        $passed = $true
        Write-Host 'PASS: real short ASCII F5/F2/F6/F8 GUI operation baseline.'
        return
    }

    if ($ShortUnicodeBestFitOnly) {
        if ($null -eq $bestFitName) {
            $passed = $true
            Write-Host 'SKIP: Windows ACP has no best-fit mapping without a question mark among the test candidates.'
            return
        }

        Send-Keys '{END}'
        $actualName = Read-FocusedFilename
        Write-Host "GUI best-fit filename comparison: expected='$bestFitName'; actual='$actualName'"
        Assert-True ($actualName -ceq $bestFitName) 'Unicode best-fit filename recovered without question mark'
        Assert-True (Test-Content $bestFitFile) 'Best-fit Unicode file content remains intact'
        $passed = $true
        Write-Host 'PASS: Unicode GUI filename round-trip survives non-question-mark ANSI best-fit mapping.'
        return
    }

    if ($ShortUnicodeUnsafeOperationsOnly) {
        # Destructive shortcuts are only sent to disposable fixture names,
        # and the operation MUST be rejected by the new production guard.
        # An unexpected native rename/confirmation dialog is not accepted.
        $aliasA = [SalamanderGuiNative]::GetLegacyFilenameAliasHex($utfName)
        $aliasB = [SalamanderGuiNative]::GetLegacyFilenameAliasHex($utfCollisionName)
        if ($aliasA -cne $aliasB) {
            $passed = $true
            Write-Host 'SKIP: current Windows ANSI code page does not conflate the Unicode test names.'
            return
        }

        Send-Keys '{END}'
        foreach ($operation in @(
            @{ Key = '{F2}'; Name = 'F2 rename' },
            @{ Key = '{F5}'; Name = 'F5 copy' },
            @{ Key = '{F6}'; Name = 'F6 move' },
            @{ Key = '{F8}'; Name = 'F8 delete' }
        )) {
            if ($operation.Name -eq 'F5 copy') {
                Send-Keys '{TAB}'
                Go-ToPath $destination
                Send-Keys '{TAB}'
                Send-Keys '{END}'
            }

            Send-Keys $operation.Key
            $blocked = @{ Dialog = '<none>' }
            Wait-Until {
                $blocked.Dialog = Get-TestDialog
                return $blocked.Dialog -match 'legacy ANSI file-operation engine'
            } "safe refusal dialog for $($operation.Name)"
            Write-Host "PASS: $($operation.Name) refused unsafe Unicode identity"
            Send-Keys '{ESC}'
            Wait-Until { -not (Get-TestDialog) } "dismissal of $($operation.Name) refusal dialog"

            Assert-True ((Test-Content $unicodeShortFile) -and
                [Linq.Enumerable]::SequenceEqual[byte](
                    [IO.File]::ReadAllBytes($collisionFile), $collisionPayload
                )) "Original Unicode files intact after $($operation.Name)"
            Assert-True (-not [IO.File]::Exists((Join-Path $destination $utfName)) -and
                -not [IO.File]::Exists((Join-Path $destination $utfCollisionName))) "No Unicode destination created by $($operation.Name)"
        }

        $passed = $true
        Write-Host 'PASS: F2/F5/F6/F8 reject lossy disk filenames without changing either file.'
        return
    }

    if ($ShortUnicodeCollisionOnly) {
        # Require an actual CP_ACP alias collision before checking that
        # Salamander refuses to export a guessed filename. When the system
        # ACP represents both names distinctly (e.g. UTF-8), skip cleanly.
        $aliasA = [SalamanderGuiNative]::GetLegacyFilenameAliasHex($utfName)
        $aliasB = [SalamanderGuiNative]::GetLegacyFilenameAliasHex($utfCollisionName)
        if ($aliasA -cne $aliasB) {
            $passed = $true
            Write-Host 'SKIP: current Windows ANSI code page does not conflate the two Unicode names.'
            return
        }

        # Both files are real and remain inside the disposable test fixture.
        # Neither F2/F5/F6/F8 nor any other destructive GUI command is sent.
        Send-Keys '{END}'
        Set-ClipboardText 'SENTINEL_COLLISION'
        Invoke-SalamanderCommand -CommandId 710
        Assert-True ((Get-ClipboardText) -ceq 'SENTINEL_COLLISION') 'Unicode filename collision refuses clipboard export'
        Assert-True ((Test-Content $unicodeShortFile) -and
            [Linq.Enumerable]::SequenceEqual[byte](
                [IO.File]::ReadAllBytes($collisionFile), $collisionPayload
            )) 'Collision retained both original file contents'
        $passed = $true
        Write-Host 'PASS: Unicode filename collision fails closed without modifying either file.'
        return
    }

    if ($ShortUnicodeOnly) {
        # A failure here is a Unicode/ANSI filename issue, not a path-length
        # failure: the full path has been checked to be below MAX_PATH.
        Send-Keys '{END}'
        $actualName = Read-FocusedFilename
        # Retain the strict Unicode assertion; make a mismatch diagnosable.
        # A fallback to the ANSI-transliterated name would conceal a defect.
        Write-Host "GUI filename comparison: expected='$utfName'; actual='$actualName'"
        $expectedUnits = ([char[]]$utfName | ForEach-Object { '{0:X4}' -f [int]$_ }) -join ' '
        $actualUnits = ([char[]]$actualName | ForEach-Object { '{0:X4}' -f [int]$_ }) -join ' '
        Write-Host "GUI filename UTF-16 units: expected=[$expectedUnits]; actual=[$actualUnits]"
        Assert-True ($actualName -ceq $utfName) 'Short Unicode name preserved in Salamander panel'
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
