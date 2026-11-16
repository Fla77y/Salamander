#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
    Exercises PictView through a real Salamander GUI process.
.DESCRIPTION
    Opt-in: requires an unlocked desktop and trusted installed plug-ins.
    Refuses to interact with an existing Salamander instance.
    Uses an isolated BMP fixture, normal F3 viewer and exact module/HWND IDs.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SalamanderExe,
    [ValidateRange(5, 120)][int]$TimeoutSeconds = 25
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'PictView GUI acceptance requires Windows.' }
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    throw 'Use PowerShell 7 in STA mode (pwsh -Sta).'
}
if (-not (Test-Path -LiteralPath $SalamanderExe -PathType Leaf)) {
    throw "Salamander executable is missing: $SalamanderExe"
}
if (@(Get-Process salamand -ErrorAction SilentlyContinue).Count -gt 0) {
    throw 'Close other Salamander instances first; test cannot reuse a running process.'
}
$SalamanderExe = [IO.Path]::GetFullPath($SalamanderExe)
$expectedPlugin = Join-Path (Split-Path -Parent $SalamanderExe) 'plugins\pictview\pictview.spl'
if (-not (Test-Path -LiteralPath $expectedPlugin -PathType Leaf)) {
    throw "Built PictView plug-in missing: $expectedPlugin"
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class PictViewHostWindows
{
    public sealed class Window
    {
        public IntPtr Handle;
        public string Title;
        public string ClassName;
    }

    public delegate bool WindowCallback(IntPtr hwnd, IntPtr arg);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool EnumWindows(WindowCallback callback, IntPtr arg);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool EnumChildWindows(IntPtr parent, WindowCallback callback, IntPtr arg);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "GetWindowTextW")]
    private static extern int GetWindowText(IntPtr hwnd, StringBuilder value, int length);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "GetClassNameW")]
    private static extern int GetClassName(IntPtr hwnd, StringBuilder value, int length);
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hwnd);
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", EntryPoint = "PostMessageW", SetLastError = true)]
    public static extern bool PostMessage(IntPtr hwnd, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")]
    private static extern int GetDlgCtrlID(IntPtr hwnd);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool GetGUIThreadInfo(uint threadId, ref GuiThreadInfo info);
    [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW", SetLastError = true)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hwnd, uint message, UIntPtr wParam, IntPtr lParam,
        uint flags, uint timeoutMilliseconds, out IntPtr result);

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        public int Left, Top, Right, Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct GuiThreadInfo
    {
        public uint cbSize;
        public uint flags;
        public IntPtr hwndActive, hwndFocus, hwndCapture, hwndMenuOwner;
        public IntPtr hwndMoveSize, hwndCaret;
        public Rect rcCaret;
    }

    public static bool IsFileListFocused(IntPtr mainWindow, uint expectedPid)
    {
        uint mainPid;
        uint threadId = GetWindowThreadProcessId(mainWindow, out mainPid);
        if (threadId == 0 || mainPid != expectedPid) return false;
        GuiThreadInfo info = new GuiThreadInfo();
        info.cbSize = (uint)Marshal.SizeOf(typeof(GuiThreadInfo));
        if (!GetGUIThreadInfo(threadId, ref info) || info.hwndFocus == IntPtr.Zero)
            return false;
        uint focusPid;
        GetWindowThreadProcessId(info.hwndFocus, out focusPid);
        return focusPid == expectedPid && GetDlgCtrlID(info.hwndFocus) == 950;
    }

    public static string GetInputFocusSummary(IntPtr mainWindow, uint expectedPid)
    {
        uint mainPid;
        uint threadId = GetWindowThreadProcessId(mainWindow, out mainPid);
        if (threadId == 0 || mainPid != expectedPid)
            return "main HWND is not owned by the test process";
        GuiThreadInfo info = new GuiThreadInfo();
        info.cbSize = (uint)Marshal.SizeOf(typeof(GuiThreadInfo));
        if (!GetGUIThreadInfo(threadId, ref info))
            return "GetGUIThreadInfo failed";
        uint focusPid = 0;
        if (info.hwndFocus != IntPtr.Zero)
            GetWindowThreadProcessId(info.hwndFocus, out focusPid);
        return String.Format("thread={0}, focus=0x{1:X}, focusPid={2}, controlId={3}, active=0x{4:X}",
            threadId, info.hwndFocus.ToInt64(), focusPid,
            info.hwndFocus == IntPtr.Zero ? -1 : GetDlgCtrlID(info.hwndFocus),
            info.hwndActive.ToInt64());
    }

    // Capture the actual text displayed in Salamander modal dialogs,
    // including their child Static controls. A title-only 'Error' is not
    // sufficient to distinguish a missing viewer association, startup error
    // or a decoder failure.
    public static string GetDialogDetails(uint processId)
    {
        var messages = new List<string>();
        foreach (var window in ForProcess(processId))
        {
            if (window.ClassName != "#32770" || !IsWindowVisible(window.Handle))
                continue;

            var parts = new List<string>();
            WindowCallback callback = (hwnd, unused) => {
                var title = new StringBuilder(4096);
                var cls = new StringBuilder(256);
                GetWindowText(hwnd, title, title.Capacity);
                GetClassName(hwnd, cls, cls.Capacity);
                var value = title.ToString().Trim();
                if (!String.IsNullOrEmpty(value))
                    parts.Add("[" + cls + "] " + value);
                return true;
            };
            if (!EnumChildWindows(window.Handle, callback, IntPtr.Zero))
                throw new InvalidOperationException("Could not enumerate dialog child windows.");
            messages.Add("[" + window.Title + "] " + String.Join(" | ", parts));
        }
        return String.Join(" || ", messages);
    }

    // Always require the PID of our own freshly launched process.
    public static List<Window> ForProcess(uint processId)
    {
        var result = new List<Window>();
        WindowCallback callback = (hwnd, unused) => {
            uint pid;
            GetWindowThreadProcessId(hwnd, out pid);
            if (pid == processId)
            {
                var title = new StringBuilder(512);
                var cls = new StringBuilder(256);
                GetWindowText(hwnd, title, title.Capacity);
                GetClassName(hwnd, cls, cls.Capacity);
                result.Add(new Window {
                    Handle = hwnd, Title = title.ToString(), ClassName = cls.ToString()
                });
            }
            return true;
        };
        if (!EnumWindows(callback, IntPtr.Zero))
            throw new InvalidOperationException("Cannot enumerate Windows desktop.");
        return result;
    }
}
'@

function Wait-For {
    param([Parameter(Mandatory)][scriptblock]$Condition,
          [Parameter(Mandatory)][string]$Description)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        if (& $Condition) { return }
        if ([DateTime]::UtcNow -ge $deadline) {
            throw "Timed out: $Description"
        }
        Start-Sleep -Milliseconds 100
    } while ($true)
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('pictview-host-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$fixture = Join-Path $root 'test-image.bmp'
$process = $null
$viewerHandle = [IntPtr]::Zero
try {
    # Arrange: one disposable image with exact byte identity.
    $bitmap = [Drawing.Bitmap]::new(2, 1)
    try {
        $bitmap.SetPixel(0, 0, [Drawing.Color]::Red)
        $bitmap.SetPixel(1, 0, [Drawing.Color]::Lime)
        $bitmap.Save($fixture, [Drawing.Imaging.ImageFormat]::Bmp)
    }
    finally {
        $bitmap.Dispose()
    }
    $expectedHash = [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($fixture)))
    $startupArgs = '-l "{0}" -r "{0}" -p 2' -f $root
    $process = Start-Process -FilePath $SalamanderExe -ArgumentList $startupArgs -WorkingDirectory (Split-Path -Parent $SalamanderExe) -PassThru

    # Act: open the single BMP fixture through Salamander's normal F3.
    # Do not modify the user's clipboard or viewer associations.
    $fixtures = @(Get-ChildItem -LiteralPath $root -File)
    if ($fixtures.Count -ne 1 -or $fixtures[0].FullName -cne $fixture) {
        throw 'Expected exactly one isolated BMP fixture.'
    }
    Wait-For -Description 'test Salamander main HWND' -Condition {
        $process.Refresh()
        if ($process.HasExited) { throw 'Salamander exited before GUI readiness.' }
        return @([PictViewHostWindows]::ForProcess([uint32]$process.Id) |
                 Where-Object { $_.Title -match 'Open Salamander' -and
                                [PictViewHostWindows]::IsWindowVisible($_.Handle) }).Count -gt 0
    }
    if (-not $process.WaitForInputIdle(15000)) {
        throw 'Salamander did not reach input-idle before GUI interaction.'
    }
    $main = @([PictViewHostWindows]::ForProcess([uint32]$process.Id) |
              Where-Object { $_.Title -match 'Open Salamander' -and
                             [PictViewHostWindows]::IsWindowVisible($_.Handle) })[0]
    if ($main.Title -notmatch [regex]::Escape((Split-Path -Leaf $root))) {
        throw "Salamander is not showing the single BMP fixture directory: $($main.Title)"
    }
    $startupDialog = [PictViewHostWindows]::GetDialogDetails([uint32]$process.Id)
    if (-not [string]::IsNullOrEmpty($startupDialog)) {
        throw "Salamander displayed a modal dialog before F3: $startupDialog"
    }
    if (-not [PictViewHostWindows]::SetForegroundWindow($main.Handle) -or
        [PictViewHostWindows]::GetForegroundWindow() -ne $main.Handle) {
        throw 'Could not securely focus the test-owned Salamander window.'
    }

    # Do not guess where End/F3 will be delivered. The main HWND may be
    # foreground while its command line or a toolbar child has input focus.
    # IDC_FILES = 950 (src/resource.rh2), the same invariant used by the
    # established Salamander long-path GUI test.
    $testIsAdmin = [Security.Principal.WindowsPrincipal]::new(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $testIsAdmin -and $main.Title -match '\(Administrator\)') {
        throw ('Test Salamander is elevated but the GUI-test PowerShell is not. ' +
               'Windows UIPI can block SendKeys. Run both at the same integrity level.')
    }

    if (-not [PictViewHostWindows]::IsFileListFocused(
            $main.Handle, [uint32]$process.Id)) {
        # Salamander's WM_ACTIVATE handler restores focus to its active panel.
        # This notification is sent only to the verified test-owned main HWND.
        [IntPtr]$activationResult = [IntPtr]::Zero
        $activated = [PictViewHostWindows]::SendMessageTimeout(
            $main.Handle, [uint32]0x0006, [UIntPtr]::new([uint32]1),
            [IntPtr]::Zero, [uint32]0x0002, [uint32]5000,
            [ref]$activationResult)
        if ($activated -eq [IntPtr]::Zero) {
            throw 'Salamander WM_ACTIVATE failed to restore file-list focus; no keys sent.'
        }
    }
    if (-not [PictViewHostWindows]::IsFileListFocused(
            $main.Handle, [uint32]$process.Id)) {
        $focus = [PictViewHostWindows]::GetInputFocusSummary(
            $main.Handle, [uint32]$process.Id)
        throw "No verified file-list focus before sending F3: $focus. No keys sent."
    }

    [Windows.Forms.SendKeys]::SendWait('{END}')
    if ([PictViewHostWindows]::GetForegroundWindow() -ne $main.Handle -or
        -not [PictViewHostWindows]::IsFileListFocused(
            $main.Handle, [uint32]$process.Id)) {
        $focus = [PictViewHostWindows]::GetInputFocusSummary(
            $main.Handle, [uint32]$process.Id)
        throw "Focus changed before sending F3: $focus. No viewer command sent."
    }
    [Windows.Forms.SendKeys]::SendWait('{F3}')
    try {
        Wait-For -Description 'WIC PictView HWND owned by test Salamander' -Condition {
        $dialog = [PictViewHostWindows]::GetDialogDetails([uint32]$process.Id)
        if (-not [string]::IsNullOrEmpty($dialog)) {
            throw "Error dialog after F3: $dialog"
        }
        $windows = [PictViewHostWindows]::ForProcess([uint32]$process.Id)
        $found = @($windows | Where-Object {
            $_.ClassName -ceq 'OpenSalamander.PictView.WIC'
        })
        if ($found.Count -gt 1) {
            throw 'Multiple WIC viewer windows unexpectedly opened.'
        }
        if ($found.Count -eq 1) {
            $script:viewerHandle = $found[0].Handle
            return $true
        }
        $process.Refresh()
        if ($process.HasExited) {
            throw 'Salamander exited after F3 without opening the WIC viewer.'
        }
        return $false
        }
    }
    catch {
        $windows = @([PictViewHostWindows]::ForProcess([uint32]$process.Id) |
                     ForEach-Object { "[$($_.ClassName)] $($_.Title)" })
        $loaded = @($process.Modules | Where-Object {
            $_.FileName -ieq $expectedPlugin
        }).Count -gt 0
        $dialog = [PictViewHostWindows]::GetDialogDetails([uint32]$process.Id)
        if (-not $loaded) {
            throw ('PictView SPL is not resident after F3; it may never have been ' +
                   'selected or may have failed initialization and unloaded. ' +
                   'Verify the BMP Viewer associations and the exact Error dialog text. ' +
                   "Dialog: '$dialog'. Test-owned windows: $($windows -join '; '). $($_.Exception.Message)")
        }
        throw ('PictView SPL was present, but no native WIC HWND appeared. ' +
               'F3 may still use a different configured Viewer association; ' +
               'also check plugin CanViewFile, decoder and viewer thread startup. ' +
               "Test-owned windows: $($windows -join '; '). $($_.Exception.Message)")
    }

    # Assert: the real SPL was loaded, window identity matches, and the BMP
    # was not modified. Close the viewer without modifying the source.
    $process.Refresh()
    $plugins = @($process.Modules | Where-Object {
        $_.FileName -ieq $expectedPlugin
    })
    if ($plugins.Count -ne 1) {
        throw "WIC viewer exists but expected SPL module is not loaded: $expectedPlugin"
    }
    $actualHash = [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($fixture)))
    if ($actualHash -cne $expectedHash) {
        throw 'Viewing changed the disposable BMP fixture bytes.'
    }
    if (-not [PictViewHostWindows]::PostMessage($viewerHandle, 0x0010,
                                                [IntPtr]::Zero, [IntPtr]::Zero)) {
        throw 'Could not close the WIC viewer HWND.'
    }
    Wait-For -Description 'WIC PictView HWND close' -Condition {
        return -not [PictViewHostWindows]::IsWindow($viewerHandle)
    }
    Write-Host "PASS: owned Salamander PID $($process.Id) loaded PictView SPL, opened/closed WIC viewer without changing the BMP."
}
catch {
    if ($process -and -not $process.HasExited) {
        $summary = @([PictViewHostWindows]::ForProcess([uint32]$process.Id) |
                     ForEach-Object { "[$($_.ClassName)] $($_.Title)" })
        Write-Warning ("Test process windows: " + ($summary -join '; '))
    }
    throw
}
finally {
    if ($process) {
        $process.Refresh()
        if (-not $process.HasExited) {
            # Terminate only the child we launched, never an existing instance.
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
        $process.Dispose()
    }
    if (Test-Path -LiteralPath $root -PathType Container) {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}
