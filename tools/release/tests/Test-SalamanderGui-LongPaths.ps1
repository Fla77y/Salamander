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
    [switch]$MaximumPathOnly,
    [switch]$ShortUnicodeOnly,
    [switch]$ShortUnicodeRenameOnly,
    [switch]$ShortUnicodeRecycleOnly,
    [switch]$VerifyRecycleRestore,
    [switch]$PluginLoadSmokeOnly,
    [switch]$WicViewerVerified,
    [switch]$ShortUnicodeTransferOnly,
    [switch]$ShortUnicodeTransferCollisionOnly,
    [switch]$ShortUnicodeBestFitOnly,
    [switch]$ShortUnicodeCollisionOnly,
    [switch]$ShortUnicodeRowIdentityOnly,
    [switch]$ShortUnicodeMultiSelectOnly,
    [switch]$ShortUnicodeDirectoryRenameOnly,
    [switch]$ShortUnicodeUnsafeOperationsOnly,
    [switch]$ShortOperationsOnly,
    [switch]$TemporaryDirectoryDeletionOnly,
    [switch]$UnicodeFindOnly
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
if ($VerifyRecycleRestore -and -not $ShortUnicodeRecycleOnly) {
    throw '-VerifyRecycleRestore requires -ShortUnicodeRecycleOnly.'
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
    [DllImport("user32.dll")] public static extern uint GetClipboardSequenceNumber();

    // A managed OLE clipboard owner in this PowerShell STA can deadlock when
    // SendMessageTimeout synchronously invokes Salamander's OleGetClipboard.
    // Publish eager, globally allocated CF_UNICODETEXT instead. The recipient
    // never needs to call back into the waiting test thread for delayed data.
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool OpenClipboard(IntPtr owner);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool EmptyClipboard();
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool CloseClipboard();
    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetClipboardData(uint format, IntPtr handle);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalAlloc(uint flags, UIntPtr bytes);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalLock(IntPtr handle);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GlobalUnlock(IntPtr handle);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalFree(IntPtr handle);

    public static void SetClipboardUnicodeText(IntPtr owner, string value)
    {
        if (owner == IntPtr.Zero) throw new ArgumentException("Owner HWND is required.", "owner");
        if (String.IsNullOrEmpty(value) || value.IndexOf('\0') >= 0)
            throw new ArgumentException("Expected nonempty UTF-16 text without embedded nulls.", "value");
        char[] characters = (value + "\0").ToCharArray();
        int byteCount = checked(characters.Length * sizeof(char));
        IntPtr memory = GlobalAlloc(0x0002, new UIntPtr((uint)byteCount)); // GMEM_MOVEABLE
        if (memory == IntPtr.Zero) throw new InvalidOperationException("GlobalAlloc failed for clipboard text.");
        bool clipboardOpened = false;
        bool transferred = false;
        try
        {
            IntPtr destination = GlobalLock(memory);
            if (destination == IntPtr.Zero)
                throw new InvalidOperationException("GlobalLock failed for clipboard text.");
            try { Marshal.Copy(characters, 0, destination, characters.Length); }
            finally { GlobalUnlock(memory); }

            // Another process may briefly hold the clipboard (Windows error 5).
            // Retry ONLY acquiring it, before EmptyClipboard changes any data.
            // Never retry the higher-level navigation WM_COMMAND on this error.
            const int maxOpenAttempts = 16;
            int openError = 0;
            for (int attempt = 1; attempt <= maxOpenAttempts; ++attempt)
            {
                if (OpenClipboard(owner))
                {
                    clipboardOpened = true;
                    break;
                }
                openError = Marshal.GetLastWin32Error();
                if (openError != 5) // ERROR_ACCESS_DENIED: transient clipboard contention
                    throw new InvalidOperationException("OpenClipboard failed: " + openError);
                if (attempt < maxOpenAttempts)
                    System.Threading.Thread.Sleep(75);
            }
            if (!clipboardOpened)
                throw new InvalidOperationException(
                    "OpenClipboard busy after " + maxOpenAttempts +
                    " attempts; last Win32 error " + openError);
            if (!EmptyClipboard())
                throw new InvalidOperationException("EmptyClipboard failed: " + Marshal.GetLastWin32Error());
            if (SetClipboardData(13, memory) == IntPtr.Zero) // CF_UNICODETEXT
                throw new InvalidOperationException("SetClipboardData(CF_UNICODETEXT) failed: " + Marshal.GetLastWin32Error());
            transferred = true; // Windows owns the HGLOBAL now.
        }
        finally
        {
            if (clipboardOpened) CloseClipboard();
            if (!transferred) GlobalFree(memory);
        }
    }
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
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool CheckRemoteDebuggerPresent(
        IntPtr processHandle,
        [MarshalAs(UnmanagedType.Bool)] out bool debuggerPresent);


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

    [StructLayout(LayoutKind.Sequential)]
    private struct GuiThreadInfo
    {
        public uint cbSize;
        public uint flags;
        public IntPtr hwndActive;
        public IntPtr hwndFocus;
        public IntPtr hwndCapture;
        public IntPtr hwndMenuOwner;
        public IntPtr hwndMoveSize;
        public IntPtr hwndCaret;
        public GuiRect rcCaret;
    }
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool GetGUIThreadInfo(uint threadId, ref GuiThreadInfo info);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "GetClassNameW")]
    private static extern int GetClassName(IntPtr window, StringBuilder buffer, int capacity);
    // IDC_FILES is 950 in src/resource.rh2, and CFilesWindow creates the
    // actual keyboard target as a child control with that ID.
    [DllImport("user32.dll")]
    private static extern int GetDlgCtrlID(IntPtr window);

    public static bool IsFileListFocused(IntPtr mainWindow, uint expectedPid)
    {
        uint mainPid;
        uint threadId = GetWindowThreadProcessId(mainWindow, out mainPid);
        if (threadId == 0 || mainPid != expectedPid)
            return false;

        GuiThreadInfo info = new GuiThreadInfo();
        info.cbSize = (uint)Marshal.SizeOf(typeof(GuiThreadInfo));
        if (!GetGUIThreadInfo(threadId, ref info) ||
            info.hwndFocus == IntPtr.Zero)
            return false;

        uint focusPid;
        GetWindowThreadProcessId(info.hwndFocus, out focusPid);
        return focusPid == expectedPid &&
               info.hwndFocus != mainWindow &&
               GetDlgCtrlID(info.hwndFocus) == 950;
    }


    // Read the actual focused control in Salamander's UI thread, without
    // activating a window or changing its state.
    public static string GetInputFocusSummary(IntPtr mainWindow, uint expectedPid)
    {
        uint mainPid;
        uint threadId = GetWindowThreadProcessId(mainWindow, out mainPid);
        if (threadId == 0 || mainPid != expectedPid)
            return "main HWND owner mismatch";

        GuiThreadInfo info = new GuiThreadInfo();
        info.cbSize = (uint)Marshal.SizeOf(typeof(GuiThreadInfo));
        if (!GetGUIThreadInfo(threadId, ref info))
            return "GetGUIThreadInfo failed: " + Marshal.GetLastWin32Error();

        uint focusPid = 0;
        if (info.hwndFocus != IntPtr.Zero)
            GetWindowThreadProcessId(info.hwndFocus, out focusPid);
        StringBuilder windowClass = new StringBuilder(128);
        if (info.hwndFocus != IntPtr.Zero)
            GetClassName(info.hwndFocus, windowClass, windowClass.Capacity);

        return String.Format(
            "thread={0}; active=0x{1:X}; focus=0x{2:X}; focusOwnerPid={3}; focusClass={4}",
            threadId, info.hwndActive.ToInt64(), info.hwndFocus.ToInt64(),
            focusPid, windowClass.ToString());
    }

    [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr window);
    [DllImport("user32.dll")] private static extern bool BringWindowToTop(IntPtr window);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool AttachThreadInput(uint threadId, uint attachToId, bool attach);
    [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();

    // Only a live, visible HWND belonging to the freshly launched test PID
    // may be activated. The final fallback briefly shares the input queue
    // with the foreground thread, then unconditionally detaches it.
    // Windows can still deny foreground activation; callers must verify it.
    public static bool TryActivateVerifiedWindow(IntPtr window, uint expectedPid, bool useSharedInputFallback)
    {
        if (window == IntPtr.Zero || expectedPid == 0 ||
            !IsWindow(window) || !IsWindowVisible(window))
            return false;

        uint ownerPid;
        uint ownerThread = GetWindowThreadProcessId(window, out ownerPid);
        if (ownerThread == 0 || ownerPid != expectedPid)
            return false;

        if (GetForegroundWindow() == window)
            return true;

        ShowWindow(window, 9); // SW_RESTORE; harmless when already visible
        SetForegroundWindow(window);
        if (GetForegroundWindow() == window)
            return true;
        if (!useSharedInputFallback)
            return false;

        IntPtr previous = GetForegroundWindow();
        uint previousPid;
        uint foregroundThread = GetWindowThreadProcessId(previous, out previousPid);
        uint currentThread = GetCurrentThreadId();
        if (foregroundThread == 0 || foregroundThread == currentThread)
            return false;

        if (!AttachThreadInput(currentThread, foregroundThread, true))
            return false;
        try
        {
            // Do not race an intervening user focus change or a destroyed
            // test window. Never attach to an unverified Salamander HWND.
            uint latestPid;
            if (GetForegroundWindow() != previous ||
                !IsWindow(window) ||
                GetWindowThreadProcessId(window, out latestPid) == 0 ||
                latestPid != expectedPid)
                return false;

            BringWindowToTop(window);
            SetForegroundWindow(window);
        }
        finally
        {
            AttachThreadInput(currentThread, foregroundThread, false);
        }
        return GetForegroundWindow() == window;
    }

    // Only operate on controls whose top-level window belongs to the isolated
    // Salamander PID. WM_SETTEXT/WM_GETTEXT are system-marshalled messages;
    // custom ListView messages must not carry pointers across processes.
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr GetDlgItem(IntPtr parent, int id);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool PostMessageW(IntPtr window, uint message, UIntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr GetWindow(IntPtr window, uint command);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")]
    private static extern void mouse_event(uint flags, uint x, uint y, uint data, UIntPtr extra);
    [StructLayout(LayoutKind.Sequential)]
    public struct NativePoint { public int X; public int Y; }
    [DllImport("user32.dll")]
    private static extern IntPtr WindowFromPoint(NativePoint point);

    private static string ClassName(IntPtr window)
    {
        StringBuilder name = new StringBuilder(128);
        GetClassName(window, name, name.Capacity);
        return name.ToString();
    }

    // Open the application's real plug-in manager without blocking on
    // its modal message loop. Only the verified test main HWND may receive
    // the command; no global keyboard accelerators are used.
    public static void PostVerifiedPluginManagerOpen(IntPtr mainWindow, uint pid)
    {
        uint actual;
        if (mainWindow == IntPtr.Zero ||
            GetWindowThreadProcessId(mainWindow, out actual) == 0 ||
            actual != pid || !IsWindowVisible(mainWindow) ||
            GetWindowCaption(mainWindow).IndexOf(
                "Open Salamander", StringComparison.OrdinalIgnoreCase) < 0)
            throw new InvalidOperationException(
                "Refusing to open plug-in manager on an unverified main window");
        if (!PostMessageW(mainWindow, 0x0111, new UIntPtr(815), IntPtr.Zero))
            throw new InvalidOperationException(
                "Could not post CM_PLUGINS to verified Salamander: " +
                Marshal.GetLastWin32Error());
    }

    // The actual CPluginsDlg contains IDL_PLUGINS=2601 and
    // IDB_PLUGINTESTALL=2616. Reject other #32770 dialogs, even ones
    // owned by the same process.
    public static IntPtr FindPluginManagerWindow(IntPtr mainWindow, uint pid)
    {
        uint mainPid;
        if (mainWindow == IntPtr.Zero ||
            GetWindowThreadProcessId(mainWindow, out mainPid) == 0 ||
            mainPid != pid)
            throw new InvalidOperationException("Plug-in manager main HWND was not verified");

        IntPtr found = IntPtr.Zero;
        foreach (TopLevelWindow top in GetProcessWindows(pid))
        {
            if (!top.Visible || top.Handle == mainWindow ||
                ClassName(top.Handle) != "#32770" ||
                GetWindow(top.Handle, 4) != mainWindow) // GW_OWNER
                continue;

            IntPtr list = GetDlgItem(top.Handle, 2601); // IDL_PLUGINS
            IntPtr testAll = GetDlgItem(top.Handle, 2616); // IDB_PLUGINTESTALL
            if (list == IntPtr.Zero || testAll == IntPtr.Zero)
                continue;

            uint listPid, testPid;
            if (GetWindowThreadProcessId(list, out listPid) == 0 ||
                GetWindowThreadProcessId(testAll, out testPid) == 0 ||
                listPid != pid || testPid != pid)
                throw new InvalidOperationException(
                    "Plug-in Manager child controls have wrong PID");
            if (found != IntPtr.Zero)
                throw new InvalidOperationException(
                    "Multiple matching Plug-in Manager dialogs in test process");
            found = top.Handle;
        }
        return found;
    }

    // This invokes only Salamander's built-in "Test All" control in a
    // verified Plug-in Manager. It can load additional configured plugins;
    // consequently the caller must require explicit opt-in.
    // Return diagnostic text for any additional modal dialog owned by the
    // verified Plug-in Manager or its main window. Test All may display
    // an error for an unrelated installed plugin; do not spin for 90 seconds
    // while the dialog blocks Salamander's UI thread.
    public static string GetBlockingPluginDialog(
        IntPtr dialog, IntPtr mainWindow, uint pid)
    {
        if (dialog == IntPtr.Zero ||
            FindPluginManagerWindow(mainWindow, pid) != dialog)
            throw new InvalidOperationException(
                "Plugin Manager identity changed during plug-in initialization");

        foreach (TopLevelWindow top in GetProcessWindows(pid))
        {
            if (!top.Visible || top.Handle == dialog ||
                top.Handle == mainWindow || ClassName(top.Handle) != "#32770")
                continue;

            IntPtr owner = GetWindow(top.Handle, 4); // GW_OWNER
            if (owner == dialog || owner == mainWindow)
                return DescribeWindow(top.Handle);
        }
        return null;
    }

    public static void PostVerifiedPluginTestAll(
        IntPtr dialog, IntPtr mainWindow, uint pid)
    {
        if (dialog == IntPtr.Zero ||
            FindPluginManagerWindow(mainWindow, pid) != dialog)
            throw new InvalidOperationException(
                "Refusing Test All command for unverified Plug-in Manager");
        IntPtr button = VerifiedChild(dialog, pid, 2616);
        if (!PostMessageW(dialog, 0x0111, new UIntPtr(2616), button))
            throw new InvalidOperationException(
                "Could not post verified Plug-in Manager Test All command: " +
                Marshal.GetLastWin32Error());
    }

    public static IntPtr FindUnicodeSearchWindow(uint pid)
    {
        IntPtr result = IntPtr.Zero;
        foreach (TopLevelWindow top in GetProcessWindows(pid))
        {
            if (top.Visible && ClassName(top.Handle) == "OpenSalUnicodeFindWindow")
            {
                if (result != IntPtr.Zero)
                    throw new InvalidOperationException("Multiple Unicode Find windows in test process");
                result = top.Handle;
            }
        }
        return result;
    }


    public static IntPtr FindUnicodeNotice(uint pid)
    {
        IntPtr result = IntPtr.Zero;
        foreach (TopLevelWindow top in GetProcessWindows(pid))
        {
            if (top.Visible && top.Title == "Unicode Find" &&
                ClassName(top.Handle) == "#32770")
            {
                if (result != IntPtr.Zero)
                    throw new InvalidOperationException(
                        "Multiple Unicode Find message boxes in test process");
                result = top.Handle;
            }
        }
        return result;
    }

    // MessageBoxW owns its #32770 window procedure. Sending a fabricated
    // WM_COMMAND/IDOK did not dismiss this system dialog in real Windows
    // GUI tests. WM_CLOSE follows the same route as its visible Close (X).
    // Only the exact notice owned by our launched Unicode Find may receive it.
    public static void PostVerifiedFindNoticeClose(
        IntPtr notice, IntPtr findWindow, uint pid)
    {
        uint noticePid, findPid;
        if (notice == IntPtr.Zero || findWindow == IntPtr.Zero ||
            !IsWindow(notice) || !IsWindow(findWindow) ||
            GetWindowThreadProcessId(notice, out noticePid) == 0 ||
            GetWindowThreadProcessId(findWindow, out findPid) == 0 ||
            noticePid != pid || findPid != pid ||
            !IsWindowVisible(notice) ||
            ClassName(notice) != "#32770" ||
            GetWindowCaption(notice) != "Unicode Find" ||
            ClassName(findWindow) != "OpenSalUnicodeFindWindow" ||
            GetWindow(notice, 4) != findWindow) // GW_OWNER
            throw new InvalidOperationException(
                "Refusing to close an unverified Unicode Find message box");

        // Post, never synchronously block the test process on the modal
        // dialog's message loop. The caller verifies that it disappears.
        if (!PostMessageW(notice, 0x0010, UIntPtr.Zero, IntPtr.Zero)) // WM_CLOSE
            throw new InvalidOperationException(
                "Could not queue WM_CLOSE for verified Unicode Find dialog: " +
                Marshal.GetLastWin32Error());
    }

    public static IntPtr FindRenameDialog(uint pid)
    {
        foreach (TopLevelWindow top in GetProcessWindows(pid))
            if (top.Visible && top.Title == "Rename Unicode item" &&
                ClassName(top.Handle) == "#32770")
                return top.Handle;
        return IntPtr.Zero;
    }

    public static IntPtr VerifiedChild(IntPtr window, uint pid, int id)
    {
        uint actual;
        if (window == IntPtr.Zero || !IsWindow(window) ||
            GetWindowThreadProcessId(window, out actual) == 0 || actual != pid)
            throw new InvalidOperationException("Find control parent has wrong process identity");
        IntPtr child = GetDlgItem(window, id);
        if (child == IntPtr.Zero ||
            GetWindowThreadProcessId(child, out actual) == 0 || actual != pid)
            throw new InvalidOperationException("Missing or unowned Find child " + id);
        return child;
    }

    private static IntPtr SendChecked(IntPtr window, uint msg, UIntPtr wp, IntPtr lp)
    {
        IntPtr result;
        IntPtr sent = SendMessageTimeout(window, msg, wp, lp, 2, 5000, out result);
        if (sent == IntPtr.Zero)
            throw new InvalidOperationException(
                "Unicode Find Win32 message " + msg +
                " failed: " + Marshal.GetLastWin32Error());
        return result;
    }

    public static void SetFindText(IntPtr window, uint pid, int id, string text)
    {
        IntPtr child = VerifiedChild(window, pid, id);
        IntPtr bytes = Marshal.StringToHGlobalUni(text);
        try
        {
            if (SendChecked(child, 0x000C, UIntPtr.Zero, bytes) == IntPtr.Zero)
                throw new InvalidOperationException("WM_SETTEXT rejected Find control " + id);
        }
        finally { Marshal.FreeHGlobal(bytes); }
        if (!String.Equals(ReadFindText(window, pid, id), text, StringComparison.Ordinal))
            throw new InvalidOperationException("Find edit control did not preserve UTF-16 text");
    }

    public static string ReadFindText(IntPtr window, uint pid, int id)
    {
        IntPtr child = VerifiedChild(window, pid, id);
        const int capacity = 32767;
        IntPtr buffer = Marshal.AllocHGlobal(capacity * sizeof(char));
        try
        {
            long count = SendChecked(child, 0x000D, new UIntPtr(capacity), buffer).ToInt64();
            if (count < 0 || count >= capacity - 1)
                throw new InvalidOperationException("Truncated Unicode Find control text");
            return Marshal.PtrToStringUni(buffer, (int)count);
        }
        finally { Marshal.FreeHGlobal(buffer); }
    }

    public static void ClickFindButton(IntPtr window, uint pid, int id)
    {
        IntPtr button = VerifiedChild(window, pid, id);
        SendChecked(window, 0x0111, new UIntPtr((uint)id), button);
    }

    public static void PostFindButton(IntPtr window, uint pid, int id)
    {
        IntPtr button = VerifiedChild(window, pid, id);
        if (!PostMessageW(window, 0x0111, new UIntPtr((uint)id), button))
            throw new InvalidOperationException("Could not queue Unicode Find command " + id);
    }

    public static int FindResultCount(IntPtr window, uint pid)
    {
        IntPtr list = VerifiedChild(window, pid, 5117);
        if (ClassName(list) != "SysListView32")
            throw new InvalidOperationException("Unicode Find results are not a ListView");
        return checked((int)SendChecked(list, 0x1004, UIntPtr.Zero, IntPtr.Zero).ToInt64());
    }

    // Check actual Win32 ListView selection state. These messages have only
    // scalar arguments and are safe across processes; no LVITEM pointer is
    // passed into a different address space.
    private static int SelectedFindIndex(IntPtr list)
    {
        int count = checked((int)SendChecked(
            list, 0x1032, UIntPtr.Zero, IntPtr.Zero).ToInt64()); // LVM_GETSELECTEDCOUNT
        if (count != 1) return -1;
        return checked((int)SendChecked(
            list, 0x100C, new UIntPtr(ulong.MaxValue),
            new IntPtr(2)).ToInt64()); // LVM_GETNEXTITEM, LVNI_SELECTED
    }

    private static bool WaitForFindSelection(IntPtr window, IntPtr list)
    {
        for (int attempt = 0; attempt != 25; ++attempt)
        {
            if (GetForegroundWindow() != window)
                throw new InvalidOperationException(
                    "Unicode Find lost foreground during ListView selection");
            if (SelectedFindIndex(list) == 0)
                return true;
            System.Threading.Thread.Sleep(40);
        }
        return false;
    }

    // A single physical click exercises the real ListView selection. A
    // fallback uses VK_HOME targeted at the verified result control, never
    // a second click (which could accidentally cause a double-click/Open).
    // Every selection is checked before any path is copied or file modified.
    public static int SelectSingleFindResult(IntPtr window, uint pid)
    {
        IntPtr list = VerifiedChild(window, pid, 5117);
        if (FindResultCount(window, pid) != 1 ||
            !TryActivateVerifiedWindow(window, pid, true) ||
            GetForegroundWindow() != window)
            throw new InvalidOperationException(
                "Find result window is not safely foreground or count is not one");

        // Ensure that any ListView scroll position left by a previous search
        // cannot put row zero outside the tested click location.
        if (SendChecked(list, 0x1013, UIntPtr.Zero, IntPtr.Zero) ==
            IntPtr.Zero) // LVM_ENSUREVISIBLE
            throw new InvalidOperationException(
                "Unicode Find could not make its only result visible");

        IntPtr header = SendChecked(list, 0x101F, UIntPtr.Zero, IntPtr.Zero);
        GuiRect listBounds, headerBounds;
        if (header == IntPtr.Zero || !GetWindowRect(list, out listBounds) ||
            !GetWindowRect(header, out headerBounds))
            throw new InvalidOperationException("Find results have no visible header");
        NativePoint point = new NativePoint { X = listBounds.Left + 25,
            Y = headerBounds.Bottom + 10 };
        if (point.Y >= listBounds.Bottom || WindowFromPoint(point) != list)
            throw new InvalidOperationException(
                "Find result row is obscured or outside the list");
        if (!SetCursorPos(point.X, point.Y))
            throw new InvalidOperationException("Could not position pointer over Find result");

        // Only one mouse click is ever sent. Its completion is confirmed by
        // reading the ListView state, not by relying on input queue timing.
        mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
        mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
        if (WaitForFindSelection(window, list))
            return 0;

        // VK_HOME is read-only in a ListView with one result. Unlike a second
        // click, it cannot trigger the result's double-click Open command.
        // Send only to the verified list HWND; keep the exact-path clipboard
        // assertion in PowerShell as the final gate before file operations.
        SendChecked(list, 0x0100, new UIntPtr(0x24), IntPtr.Zero); // WM_KEYDOWN / VK_HOME
        SendChecked(list, 0x0101, new UIntPtr(0x24), IntPtr.Zero); // WM_KEYUP
        if (WaitForFindSelection(window, list))
        {
            Console.WriteLine(
                "INFO: Unicode Find selected result via safe ListView keyboard fallback.");
            return 0;
        }

        uint owner;
        uint thread = GetWindowThreadProcessId(window, out owner);
        GuiThreadInfo info = new GuiThreadInfo();
        info.cbSize = (uint)Marshal.SizeOf(typeof(GuiThreadInfo));
        string focus = GetGUIThreadInfo(thread, ref info)
            ? "0x" + info.hwndFocus.ToInt64().ToString("X")
            : "unavailable";
        int selectedCount = checked((int)SendChecked(
            list, 0x1032, UIntPtr.Zero, IntPtr.Zero).ToInt64());
        throw new InvalidOperationException(String.Format(
            "Unicode Find result selection failed: items=1; selected={0}; " +
            "focus HWND={1}; list HWND=0x{2:X}; foreground HWND=0x{3:X}",
            selectedCount, focus, list.ToInt64(),
            GetForegroundWindow().ToInt64()));
    }
}

// Diagnose only: read a verified GUI thread's Windows wait chain after a
// WM_COMMAND timeout. No remote input, process modification or dump files.
public static class SalamanderGuiWaitChain
{
    private const int MaxNodes = 16;
    private const int UnionBytes = 272; // WCHAR[128], LARGE_INTEGER, BOOL, alignment
    [StructLayout(LayoutKind.Sequential)]
    private struct Node
    {
        public int Type;
        public int Status;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = UnionBytes)]
        public byte[] Union;
    }
    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern IntPtr OpenThreadWaitChainSession(
        uint flags, IntPtr callback);
    [DllImport("advapi32.dll")]
    private static extern void CloseThreadWaitChainSession(IntPtr session);
    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetThreadWaitChain(
        IntPtr session, IntPtr context, uint flags, uint threadId,
        ref uint count, [In, Out] Node[] nodes,
        [MarshalAs(UnmanagedType.Bool)] out bool cycle);

    public static string Describe(uint threadId)
    {
        if (threadId == 0) return "GUI thread ID unavailable";
        var result = System.Threading.Tasks.Task.Run(() => Query(threadId));
        if (!result.Wait(4000))
            return "WCT diagnostic timed out (4 s); GUI failure remains unchanged";
        return result.Result;
    }

    private static string Query(uint threadId)
    {
        if (Marshal.SizeOf(typeof(Node)) != 280)
            return "WCT layout mismatch; refusing native call";
        IntPtr session = OpenThreadWaitChainSession(0, IntPtr.Zero);
        if (session == IntPtr.Zero)
            return "OpenThreadWaitChainSession failed: Win32 " +
                Marshal.GetLastWin32Error();
        try
        {
            Node[] nodes = new Node[MaxNodes];
            for (int i = 0; i < nodes.Length; ++i)
                nodes[i].Union = new byte[UnionBytes];
            uint count = MaxNodes;
            bool cycle;
            // COM, cross-process and critical-section tracking. Failure can
            // indicate insufficient SE_DEBUG_NAME privilege; report the code.
            if (!GetThreadWaitChain(session, IntPtr.Zero, 0x7, threadId,
                                    ref count, nodes, out cycle))
                return "GetThreadWaitChain failed: Win32 " +
                    Marshal.GetLastWin32Error();
            if (count > MaxNodes) count = MaxNodes;
            var detail = new System.Text.StringBuilder();
            detail.Append("thread=").Append(threadId)
                .Append("; cycle=").Append(cycle);
            string[] types = { "invalid", "critical-section", "SendMessage",
                "mutex", "ALPC", "COM", "thread-wait", "process-wait",
                "thread", "COM-activation", "unknown", "socket", "SMB" };
            for (int i = 0; i < count; ++i)
            {
                Node node = nodes[i];
                string type = node.Type > 0 && node.Type < types.Length
                    ? types[node.Type] : "type-" + node.Type;
                detail.Append(" -> ").Append(type).Append("(status=")
                    .Append(node.Status);
                if (node.Type == 8) // WctThreadType
                {
                    detail.Append(",pid=")
                        .Append(BitConverter.ToUInt32(node.Union, 0))
                        .Append(",tid=")
                        .Append(BitConverter.ToUInt32(node.Union, 4))
                        .Append(",waitMs=")
                        .Append(BitConverter.ToUInt32(node.Union, 8));
                }
                else
                {
                    string name = System.Text.Encoding.Unicode.GetString(
                        node.Union, 0, 256).TrimEnd('\0');
                    if (name.Length > 0)
                        detail.Append(",object=").Append(name);
                }
                detail.Append(")");
            }
            return detail.ToString();
        }
        finally { CloseThreadWaitChainSession(session); }
    }
}

// CM_CLIPPASTE calls OleGetClipboard synchronously. Its clipboard-owner
// window must live on another pumping STA, never on the caller STA blocked
// in SendMessageTimeout. Use only Win32 and core .NET here: Add-Type can then
// use PowerShell's standard compiler references without custom DLL lists.
public sealed class SalamanderGuiClipboardOwner : IDisposable
{
    private const uint WM_QUIT = 0x0012;
    private const uint WM_SET_CLIPBOARD = 0x8001; // WM_APP + 1, thread message
    private readonly System.Threading.Thread thread;
    private readonly System.Threading.ManualResetEventSlim ready =
        new System.Threading.ManualResetEventSlim(false);
    private readonly System.Threading.ManualResetEventSlim completed =
        new System.Threading.ManualResetEventSlim(false);
    private readonly object gate = new object();
    private IntPtr window = IntPtr.Zero;
    private uint nativeThreadId;
    private string pendingText;
    private Exception pendingError;
    private Exception startupError;
    private bool disposed;

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeMessage
    {
        public IntPtr hwnd;
        public uint message;
        public UIntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public int x;
        public int y;
        public uint lPrivate;
    }

    [DllImport("user32.dll", EntryPoint = "CreateWindowExW",
        CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateWindowEx(
        uint exStyle, string className, string title, uint style,
        int x, int y, int width, int height, IntPtr parent, IntPtr menu,
        IntPtr instance, IntPtr parameter);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyWindow(IntPtr window);
    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();
    [DllImport("user32.dll", EntryPoint = "PeekMessageW", SetLastError = true)]
    private static extern bool PeekMessage(
        out NativeMessage message, IntPtr window, uint first, uint last,
        uint remove);
    [DllImport("user32.dll", EntryPoint = "GetMessageW", SetLastError = true)]
    private static extern int GetMessage(
        out NativeMessage message, IntPtr window, uint first, uint last);
    [DllImport("user32.dll", EntryPoint = "PostThreadMessageW", SetLastError = true)]
    private static extern bool PostThreadMessage(
        uint threadId, uint message, UIntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")]
    private static extern bool TranslateMessage(ref NativeMessage message);
    [DllImport("user32.dll", EntryPoint = "DispatchMessageW")]
    private static extern IntPtr DispatchMessage(ref NativeMessage message);
    [DllImport("user32.dll")]
    private static extern void PostQuitMessage(int exitCode);

    public int OwnerThreadId { get { return thread.ManagedThreadId; } }

    public SalamanderGuiClipboardOwner()
    {
        thread = new System.Threading.Thread(RunClipboardOwner);
        thread.Name = "Salamander GUI test clipboard owner";
        thread.IsBackground = true;
        thread.SetApartmentState(System.Threading.ApartmentState.STA);
        thread.Start();
        if (!ready.Wait(10000))
            throw new TimeoutException("Clipboard owner STA did not create its HWND.");
        if (startupError != null)
            throw new InvalidOperationException(
                "Clipboard owner STA startup failed.", startupError);
    }

    private void RunClipboardOwner()
    {
        try
        {
            // Built-in STATIC class provides a valid HWND without introducing
            // WinForms or a custom WindowProc. Keep the window hidden.
            window = CreateWindowEx(0, "STATIC", "", 0, 0, 0, 0, 0,
                                    IntPtr.Zero, IntPtr.Zero,
                                    IntPtr.Zero, IntPtr.Zero);
            if (window == IntPtr.Zero)
                throw new InvalidOperationException(
                    "CreateWindowEx clipboard owner failed: " +
                    Marshal.GetLastWin32Error());
            nativeThreadId = GetCurrentThreadId();
            NativeMessage unused;
            PeekMessage(out unused, IntPtr.Zero, 0, 0, 0); // ensure queue exists
            ready.Set();

            NativeMessage message;
            int result;
            while ((result = GetMessage(out message, IntPtr.Zero, 0, 0)) > 0)
            {
                if (message.hwnd == IntPtr.Zero &&
                    message.message == WM_SET_CLIPBOARD)
                {
                    try
                    {
                        SalamanderGuiNative.SetClipboardUnicodeText(
                            window, pendingText);
                    }
                    catch (Exception error) { pendingError = error; }
                    finally { completed.Set(); }
                    continue;
                }
                TranslateMessage(ref message);
                DispatchMessage(ref message);
            }
            if (result < 0)
                throw new InvalidOperationException(
                    "GetMessage clipboard owner failed: " +
                    Marshal.GetLastWin32Error());
        }
        catch (Exception error)
        {
            startupError = error;
            pendingError = error;
            ready.Set();
            completed.Set();
        }
        finally
        {
            if (window != IntPtr.Zero)
                DestroyWindow(window);
        }
    }

    private static void PumpCallerMessages()
    {
        // The caller STA can itself own the previous clipboard data.
        // Pump WM_DESTROYCLIPBOARD and OLE callbacks while the other STA
        // replaces it, preserving WM_QUIT for the caller's outer loop.
        NativeMessage message;
        for (int n = 0; n < 64 &&
            PeekMessage(out message, IntPtr.Zero, 0, 0, 1); ++n)
        {
            if (message.message == WM_QUIT)
            {
                PostQuitMessage(unchecked((int)message.wParam.ToUInt64()));
                break;
            }
            TranslateMessage(ref message);
            DispatchMessage(ref message);
        }
    }

    public void SetText(string text)
    {
        if (String.IsNullOrEmpty(text))
            throw new ArgumentException("Expected nonempty clipboard text.", "text");
        lock (gate)
        {
            if (disposed || !thread.IsAlive || window == IntPtr.Zero)
                throw new ObjectDisposedException("SalamanderGuiClipboardOwner");
            pendingText = text;
            pendingError = null;
            completed.Reset();
            if (!PostThreadMessage(nativeThreadId, WM_SET_CLIPBOARD,
                                   UIntPtr.Zero, IntPtr.Zero))
                throw new InvalidOperationException(
                    "PostThreadMessage clipboard write failed: " +
                    Marshal.GetLastWin32Error());

            DateTime deadline = DateTime.UtcNow.AddSeconds(15);
            while (!completed.Wait(25))
            {
                PumpCallerMessages();
                if (!thread.IsAlive)
                    throw new InvalidOperationException(
                        "Clipboard owner STA exited unexpectedly.", pendingError);
                if (DateTime.UtcNow >= deadline)
                    throw new TimeoutException(
                        "Clipboard owner STA did not publish CF_UNICODETEXT.");
            }
            if (pendingError != null)
                throw new InvalidOperationException(
                    "Clipboard owner could not publish CF_UNICODETEXT.",
                    pendingError);
        }
    }

    public void Dispose()
    {
        lock (gate)
        {
            if (disposed) return;
            disposed = true;
            if (thread.IsAlive &&
                !PostThreadMessage(nativeThreadId, WM_QUIT,
                                   UIntPtr.Zero, IntPtr.Zero))
                throw new InvalidOperationException(
                    "Could not stop clipboard owner STA: " +
                    Marshal.GetLastWin32Error());
            if (!thread.Join(5000))
                throw new TimeoutException(
                    "Clipboard owner STA did not stop within five seconds.");
            ready.Dispose();
            completed.Dispose();
        }
    }
}

'@

$script:clipboardOwner = $null
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
$script:findCancelProbePath = $null
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
    param(
        [scriptblock]$Condition,
        [string]$Description,
        [ValidateRange(0,120)][int]$TimeoutSecondsOverride = 0
    )
    $seconds = if ($TimeoutSecondsOverride -gt 0) { $TimeoutSecondsOverride } else { $TimeoutSeconds }
    $deadline = [DateTime]::UtcNow.AddSeconds($seconds)
    do {
        if (& $Condition) { return }
        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Timeout waiting for $Description"
}

# The restore test is opt-in: it may modify only the uniquely identified
# GUID-scoped fixture, never an arbitrary item from the user's Recycle Bin.
function Find-VerifiedRecycledFixtureItem {
    param(
        [Parameter(Mandatory)][object]$RecycleFolder,
        [Parameter(Mandatory)][string]$OriginalFullPath
    )

    $expectedDirectory = [IO.Path]::GetDirectoryName($OriginalFullPath).TrimEnd('\')
    $expectedName = [IO.Path]::GetFileName($OriginalFullPath)
    $items = $RecycleFolder.Items()
    if ($null -eq $items) { throw 'Recycle Bin item enumeration is unavailable.' }

    $match = $null
    for ($index = 0; $index -lt $items.Count; $index++) {
        $item = $items.Item($index)
        if ($null -eq $item -or [bool]$item.IsFolder -or
            -not [string]::Equals([string]$item.Name, $expectedName,
                [StringComparison]::Ordinal)) { continue }
        $deletedFrom = [string]$item.ExtendedProperty('System.Recycle.DeletedFrom')
        if (-not [string]::Equals($deletedFrom.TrimEnd('\'), $expectedDirectory,
                [StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($null -ne $match) {
            throw 'Ambiguous Recycle Bin identity: more than one item has the exact fixture name and original directory.'
        }
        $match = $item
    }
    return $match
}

function Restore-VerifiedRecycledFixtureItem {
    param(
        [Parameter(Mandatory)][object]$Item,
        [Parameter(Mandatory)][string]$OriginalFullPath
    )

    # Do not let Explorer replace an existing destination or choose its own
    # restore target after the test's original path is reoccupied.
    if ([IO.File]::Exists($OriginalFullPath) -or
        [IO.Directory]::Exists($OriginalFullPath)) {
        throw 'Refusing Recycle Bin restore: fixture destination already exists.'
    }
    $restoreVerb = $null
    $verbs = $Item.Verbs()
    for ($index = 0; $index -lt $verbs.Count; $index++) {
        $verb = $verbs.Item($index)
        $caption = ([string]$verb.Name -replace '&', '').Trim()
        if ($caption -ceq 'Restore' -or $caption -ceq 'Wiederherstellen') {
            if ($null -ne $restoreVerb) { throw 'Ambiguous Recycle Bin restore verbs.' }
            $restoreVerb = $verb
        }
    }
    if ($null -eq $restoreVerb) {
        throw 'No recognized Restore/Wiederherstellen verb; refusing to invoke an unknown shell action.'
    }
    $restoreVerb.DoIt()
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

function Get-ForegroundWindowSummary {
    $h = [SalamanderGuiNative]::GetForegroundWindow()
    if ($h -eq [IntPtr]::Zero) { return 'HWND=<none>' }
    [uint32]$ownerPid = 0
    [void][SalamanderGuiNative]::GetWindowThreadProcessId($h, [ref]$ownerPid)
    $caption = [SalamanderGuiNative]::GetWindowCaption($h)
    return ('HWND=0x{0:X} PID={1} title={2}' -f
            $h.ToInt64(), $ownerPid, $caption)
}

function Get-TestDialog {
    if ($null -eq $process) { return $null }
    $process.Refresh()
    if ($process.HasExited) { return $null }
    $main = $mainWindowHandle
    if ($main -eq [IntPtr]::Zero) { return $null }
    # The startup/error dialog may not yet be the foreground window or the
    # last-active popup. Inspect visible top-level windows of this PID before
    # concluding the GUI is free of known navigation/configuration errors.
    foreach ($window in [SalamanderGuiNative]::GetProcessWindows([uint32]$process.Id)) {
        if ($window.Visible -and $window.Handle -ne $main -and
            ($window.Title -ceq 'Error Changing Directory' -or
             $window.Title -ceq 'Error Loading Configuration')) {
            return [SalamanderGuiNative]::DescribeWindow($window.Handle)
        }
    }
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

    $attempts = 0
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $process.Refresh()
        if ($process.HasExited) { throw 'Test Salamander process terminated unexpectedly.' }

        [uint32]$windowPid = 0
        [void][SalamanderGuiNative]::GetWindowThreadProcessId($h, [ref]$windowPid)
        if ($windowPid -ne [uint32]$process.Id) {
            throw "Main window no longer belongs to launched Salamander PID $($process.Id)."
        }

        $attempts++
        # Two normal attempts first. Bounded input-queue recovery is used
        # only on selected later attempts to avoid excessive UI disruption.
        $useFallback = $attempts -eq 3 -or $attempts -eq 10
        $activated = [SalamanderGuiNative]::TryActivateVerifiedWindow(
            $h, [uint32]$process.Id, $useFallback)
        if ($activated -and [SalamanderGuiNative]::GetForegroundWindow() -eq $h) {
            return
        }
        Start-Sleep -Milliseconds 350
    } while ([DateTime]::UtcNow -lt $deadline)

    $foreground = Get-ForegroundWindowSummary
    $windows = Get-ProcessWindowSummary -OwnerProcessId ([uint32]$process.Id)
    throw (("Cannot activate verified test Salamander window HWND=0x{0:X} PID={1} " +
           "after {2} attempts. Foreground: {3}; test process windows: {4}. " +
           "Windows may deny SetForegroundWindow; no keys were sent.") -f
           $h.ToInt64(), $process.Id, $attempts, $foreground, $windows)
}

# The clipboard path command can leave focus on Salamander's main HWND.
# Salamander's WM_ACTIVATE/WA_ACTIVE handler calls FocusPanel(GetActivePanel()).
# Use that native focus route once, then verify the actual IDC_FILES control
# (950), the observed path and the absence of any modal dialog. Do not guess
# which of the two file lists is active, or dispatch keyboard/file actions
# while focus is unresolved.
function Restore-FilePanelFocus {
    param([Parameter(Mandatory)][string]$ExpectedPath)

    if ([SalamanderGuiNative]::IsFileListFocused(
            $mainWindowHandle, [uint32]$process.Id)) {
        return
    }

    $focusBefore = [SalamanderGuiNative]::GetInputFocusSummary(
        $mainWindowHandle, [uint32]$process.Id)
    $dialogBefore = Get-TestDialog
    if ((Get-ActiveProcessId) -ne [uint32]$process.Id -or
        [SalamanderGuiNative]::GetForegroundWindow() -ne $mainWindowHandle -or
        -not [string]::IsNullOrEmpty($dialogBefore)) {
        throw ("Cannot restore file-panel focus: Salamander main window is not foreground " +
               "or a modal dialog is open. Before=[$focusBefore]; dialog='$dialogBefore'.")
    }

    [uint32]$ownerPid = 0
    [void][SalamanderGuiNative]::GetWindowThreadProcessId(
        $mainWindowHandle, [ref]$ownerPid)
    if ($ownerPid -ne [uint32]$process.Id) {
        throw "Cannot restore file-panel focus: main HWND owner changed."
    }

    # WA_ACTIVE is a focus notification, not a keyboard command. Dispatch
    # it synchronously to the verified main HWND and never repeat blindly.
    [IntPtr]$activationResult = [IntPtr]::Zero
    $sent = [SalamanderGuiNative]::SendMessageTimeout(
        $mainWindowHandle, [uint32]0x0006, [UIntPtr]::new([uint32]1),
        [IntPtr]::Zero, [uint32]0x0002, [uint32]5000,
        [ref]$activationResult)
    $activationError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    if ($sent -eq [IntPtr]::Zero) {
        throw "Salamander WM_ACTIVATE focus recovery failed (Win32 error $activationError). No keys were sent."
    }

    $observedPath = '<unavailable>'
    $readError = '<none>'
    try { $observedPath = Read-PanelPath }
    catch { $readError = $_.Exception.Message }
    $focusAfter = [SalamanderGuiNative]::GetInputFocusSummary(
        $mainWindowHandle, [uint32]$process.Id)
    $dialogAfter = Get-TestDialog
    if (-not [SalamanderGuiNative]::IsFileListFocused(
            $mainWindowHandle, [uint32]$process.Id) -or
        $observedPath -cne $ExpectedPath -or
        -not [string]::IsNullOrEmpty($dialogAfter)) {
        $failureFormat = "File-panel focus recovery failed. Before=[{0}]; after=[{1}]; " +
                         "expected path='{2}'; observed path='{3}'; read error='{4}'; " +
                         "dialog='{5}'. No keyboard or file-operation keys were sent."
        throw ($failureFormat -f $focusBefore, $focusAfter, $ExpectedPath,
               $observedPath, $readError, $dialogAfter)
    }

    Write-Host 'PASS: Verified file-panel keyboard focus restored through Salamander WM_ACTIVATE'
}

# Only the read-only SHORT baseline may recover foreground focus between
# an already-sent END key and observing its selected filename. An unrelated
# window can steal foreground while SendKeys.SendWait is completing. Never
# replay the key: simply restore the verified test app and assert the result.
function Recover-BaselineReadFocus {
    if ((Get-ActiveProcessId) -eq [uint32]$process.Id) { return }

    $dialog = Get-TestDialog
    if (-not [string]::IsNullOrEmpty($dialog)) {
        throw "Cannot recover baseline focus while a modal Salamander dialog is open: $dialog"
    }

    $previousForeground = Get-ForegroundWindowSummary
    Focus-TestProcess
    Restore-FilePanelFocus -ExpectedPath $source
    if ((Get-ActiveProcessId) -ne [uint32]$process.Id) {
        throw ("Baseline foreground changed again after recovery; no key was repeated. " +
               "Foreground: $(Get-ForegroundWindowSummary)")
    }
    Write-Host "GUI baseline read-only focus recovered once; previous foreground: $previousForeground"
}

function Send-Keys {
    param([string]$Keys)

    if ((Get-ActiveProcessId) -ne [uint32]$process.Id) {
        # Never redirect input away from an outstanding Salamander dialog.
        # Recover foreground focus only to the already verified test window.
        $dialog = Get-TestDialog
        if (-not [string]::IsNullOrEmpty($dialog)) {
            throw "Refusing foreground recovery while a Salamander dialog is open: $dialog"
        }

        $previousForeground = Get-ForegroundWindowSummary
        Focus-TestProcess
        Write-Host "GUI focus recovered for test process; previous foreground: $previousForeground"
    }

    if ((Get-ActiveProcessId) -ne [uint32]$process.Id) {
        throw "Refusing to send input to a window owned by another process. Foreground: $(Get-ForegroundWindowSummary)"
    }

    [Windows.Forms.SendKeys]::SendWait($Keys)
    Start-Sleep -Milliseconds 200
}

# Salamander resource.rh2: CM_CLIPPASTE=775, CM_CLIPCOPYFULLPATH=711,
# CM_CLIPCOPYNAME=710, CM_CLIPCOPYFULLNAME=709. Dispatch synchronously to avoid racing with clipboard
# contents: SendKeys posts input, after which the test used to overwrite the
# clipboard before Salamander had consumed the original path.
function Invoke-SalamanderCommand {
    param(
        [ValidateSet(709,710,711,775)][int]$CommandId
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

    # Detect a GUI thread already blocked during startup, independently of
    # the clipboard-paste command. WM_NULL has no user-visible side effects.
    if ($CommandId -eq 775) {
        [IntPtr]$preflightResult = [IntPtr]::Zero
        $ready = [SalamanderGuiNative]::SendMessageTimeout(
            $main, [uint32]0, [UIntPtr]::Zero, [IntPtr]::Zero,
            [uint32]0x0002, [uint32]2500, [ref]$preflightResult)
        $preflightError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        if ($ready -eq [IntPtr]::Zero) {
            [uint32]$preflightOwner = 0
            $preflightThread = [SalamanderGuiNative]::GetWindowThreadProcessId(
                $main, [ref]$preflightOwner)
            $preflightWait = '<not collected>'
            try {
                $preflightWait = [SalamanderGuiWaitChain]::Describe([uint32]$preflightThread)
            }
            catch { $preflightWait = "WCT unavailable: $($_.Exception.Message)" }
            throw ("Salamander GUI unresponsive BEFORE clipboard command 775; " +
                   "WM_NULL preflight Win32 error $preflightError. " +
                   "No clipboard navigation command was sent. " +
                   "GUI thread=$preflightThread; owner PID=$preflightOwner; wait chain=[$preflightWait]")
        }
        Write-Host 'PASS: Salamander GUI responds to WM_NULL immediately before clipboard navigation'
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
        [uint32]$checkedPid = 0
        $uiThreadId = [SalamanderGuiNative]::GetWindowThreadProcessId(
            $main, [ref]$checkedPid)
        $waitChain = '<not collected>'
        try {
            $waitChain = [SalamanderGuiWaitChain]::Describe([uint32]$uiThreadId)
        }
        catch {
            $waitChain = "WCT unavailable: $($_.Exception.Message)"
        }
        throw (("Salamander command {0} did not complete after {1} ms; " +
            "SendMessageTimeout Win32 error {2}; IsHungAppWindow={3}; modal dialog='{4}'; " +
            "GUI thread={5}; owner PID={6}; wait chain=[{7}]") -f
            $CommandId, $timer.ElapsedMilliseconds, $lastError, $hung, $dialog,
            $uiThreadId, $checkedPid, $waitChain)
    }
}

function Set-NativeNavigationClipboard {
    param([Parameter(Mandatory)][string]$Text)

    # An OLE clipboard reader in Salamander may synchronously message its
    # clipboard owner. Keep that HWND on a separately pumped STA so the
    # synchronous GUI command never waits for its own blocked test thread.
    if ($null -eq $script:clipboardOwner) {
        $script:clipboardOwner = [SalamanderGuiClipboardOwner]::new()
    }
    $script:clipboardOwner.SetText($Text)
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

function Set-VerifiedNavigationClipboard {
    param([Parameter(Mandatory)][string]$Text)

    # A clipboard manager or the launching GUI can replace CF_UNICODETEXT
    # between a successful SetText and the immediate GetText. Never dispatch
    # WM_COMMAND 775 until the complete value has round-tripped exactly.
    $maxAttempts = 4
    $lastObservedLength = -1
    $firstSequence = [SalamanderGuiNative]::GetClipboardSequenceNumber()
    $lastSequence = $firstSequence
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        Set-NativeNavigationClipboard -Text $Text
        $observed = Get-ClipboardText
        if ([string]::Equals($observed, $Text, [StringComparison]::Ordinal)) {
            Write-Host 'PASS: Clipboard contains only the requested text path'
            return
        }

        $lastObservedLength = if ($null -eq $observed) { -1 } else { $observed.Length }
        $lastSequence = [SalamanderGuiNative]::GetClipboardSequenceNumber()
        if ($attempt -lt $maxAttempts) {
            $warningFormat = "GUI clipboard changed before navigation (attempt {0}/{1}; " +
                             "expected UTF-16 units={2}; observed UTF-16 units={3}; sequence={4}). " +
                             "Retrying clipboard write only."
            Write-Warning ($warningFormat -f $attempt, $maxAttempts, $Text.Length,
                           $lastObservedLength, $lastSequence)
            Start-Sleep -Milliseconds 250
        }
    }

    $foreground = Get-ForegroundWindowSummary
    $dialog = Get-TestDialog
    throw ("GUI clipboard text did not round-trip after {0} writes; " +
        "expected UTF-16 units={1}; observed UTF-16 units={2}; " +
        "sequence before={3}, after={4}; foreground={5}; dialog='{6}'. " +
        "No navigation command was sent." -f
        $maxAttempts, $Text.Length, $lastObservedLength,
        $firstSequence, $lastSequence, $foreground, $dialog)
}

function Read-PanelPath {
    # WM_COMMAND 711 is synchronous, but the clipboard can be briefly
    # unavailable or a command can fail to publish text during startup.
    # A failed read must not consume the entire navigation timeout.
    $sentinel = 'SENTINEL_NOT_PATH'
    Set-ClipboardText $sentinel
    Invoke-SalamanderCommand -CommandId 711
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        for ($poll = 0; $poll -lt 4; $poll++) {
            $observed = Get-ClipboardText
            if (-not [string]::IsNullOrWhiteSpace($observed) -and $observed -cne $sentinel) {
                return $observed.TrimEnd([char]13, [char]10)
            }
            Start-Sleep -Milliseconds 150
        }
        if ($attempt -lt 3) {
            Set-ClipboardText $sentinel
            Invoke-SalamanderCommand -CommandId 711
        }
    }
    throw 'Panel path clipboard shortcut did not publish a path after 3 verified command dispatches.'
}

function Format-GuiDiagnosticPath {
    param([string]$Path)

    if ($null -eq $Path) { return '<null>' }
    if ($Path.Length -le 180) { return $Path }
    $prefix = $Path.Substring(0, 90)
    $suffix = $Path.Substring($Path.Length - 70)
    return ("length={0} UTF-16 units; prefix='{1}'; omitted={2} units; suffix='{3}'" -f
        $Path.Length, $prefix, ($Path.Length - 160), $suffix)
}

function Get-TestProcessState {
    $process.Refresh()
    if ($process.HasExited) {
        # Preserve the original Windows NTSTATUS as an unsigned 8-digit hex
        # value; .NET Process.ExitCode returns a signed Int32.
        $hexCode = [uint32](([int64]$process.ExitCode) -band 0xFFFFFFFFL)
        return ('exited=True; exitCode={0}; exitCodeHex=0x{1:X8}' -f
            $process.ExitCode, $hexCode)
    }

    [uint32]$mainOwnerPid = 0
    [void][SalamanderGuiNative]::GetWindowThreadProcessId(
        $mainWindowHandle, [ref]$mainOwnerPid)
    return ('exited=False; main HWND owner PID={0}; process windows={1}' -f
        $mainOwnerPid, (Get-ProcessWindowSummary -OwnerProcessId ([uint32]$process.Id)))
}

# Opt-in debugging only. Salamander's DEBUG exception handler deliberately
# forwards native exceptions to an attached debugger instead of terminating
# through its own reporter. Do not rely on WER for an already handled exception.
function Wait-ForNativeDebugger {
    if ($env:SALAMANDER_GUI_ATTACH_DEBUGGER -cne '1') { return }

    $process.Refresh()
    if ($process.HasExited) {
        throw 'Cannot attach debugger: test Salamander exited.'
    }

    $attachMessage = ("DEBUGGER ATTACH: attach Visual Studio native C++ debugger to " +
                      "salamand.exe PID {0} (Debug x64). Navigation will begin " +
                      "after CheckRemoteDebuggerPresent confirms attachment.")
    Write-Host ($attachMessage -f $process.Id)
    $deadline = [DateTime]::UtcNow.AddMinutes(5)
    while ([DateTime]::UtcNow -lt $deadline) {
        $process.Refresh()
        if ($process.HasExited) {
            throw ("Test Salamander exited before debugger attachment: {0}" -f
                (Get-TestProcessState))
        }
        [bool]$attached = $false
        if (-not [SalamanderGuiNative]::CheckRemoteDebuggerPresent(
                $process.Handle, [ref]$attached)) {
            $win32Error = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "CheckRemoteDebuggerPresent failed: Win32 error $win32Error"
        }
        if ($attached) {
            Write-Host "PASS: native debugger attached to test Salamander PID $($process.Id)"
            return
        }
        Start-Sleep -Milliseconds 500
    }
    throw 'Native debugger was not attached within 5 minutes; long-path navigation was not attempted.'
}

# A foreground change can happen between verified WM_COMMAND 775 and
# reading the result. Recover only the original test window once; never
# dispatch a second navigation merely because another app took focus.
function Recover-NavigationForeground {
    param([Parameter(Mandatory)][hashtable]$Diagnostics)

    if ((Get-ActiveProcessId) -eq [uint32]$process.Id) { return }

    $dialog = Get-TestDialog
    if (-not [string]::IsNullOrEmpty($dialog)) {
        throw "Navigation focus lost while Salamander displayed a dialog: $dialog"
    }
    if ($Diagnostics.FocusRecoveryAttempted) {
        throw ("Navigation interrupted by repeated external foreground activation; " +
               "no additional navigation command was dispatched. Foreground: " +
               (Get-ForegroundWindowSummary))
    }

    $Diagnostics.FocusRecoveryAttempted = $true
    $previousForeground = Get-ForegroundWindowSummary
    Focus-TestProcess
    if ((Get-ActiveProcessId) -ne [uint32]$process.Id) {
        throw "Navigation focus recovery did not retain the verified test window."
    }
    Write-Host "GUI navigation focus recovered once; previous foreground: $previousForeground"
}

function Go-ToPath {
    param([string]$Path)

    $pathSummary = Format-GuiDiagnosticPath $Path

    # The only clipboard payload is CF_UNICODETEXT, not a file drop. The
    # synchronous WM_COMMAND 775 requests navigation to that directory.
    # A second request is permitted only after a verified timeout with no
    # modal dialog and the original test process still in the foreground.
    $maxNavigationAttempts = 2
    $diagnostics = @{
        ForegroundPid = 0
        PanelPath = '<not read>'
        PanelReadError = '<none>'
        FocusRecoveryAttempted = $false
    }

    for ($attempt = 1; $attempt -le $maxNavigationAttempts; $attempt++) {
        Focus-TestProcess
        Set-VerifiedNavigationClipboard -Text $Path
        Invoke-SalamanderCommand -CommandId 775

        try {
            # Short first attempt permits a bounded recovery from transient
            # startup clipboard races. The final attempt uses the full timeout.
            $probeSeconds = if ($attempt -eq 1) { 6 } else { $TimeoutSeconds }
            Wait-Until {
                # A process crash destroys the main HWND and moves foreground
                # focus elsewhere. Never report that as an ordinary navigation
                # timeout; preserve the exit status while the Process exists.
                $process.Refresh()
                if ($process.HasExited) {
                    throw ("Salamander exited during navigation to {0}: {1}" -f
                        $pathSummary, (Get-TestProcessState))
                }
                [uint32]$currentMainOwner = 0
                [void][SalamanderGuiNative]::GetWindowThreadProcessId(
                    $mainWindowHandle, [ref]$currentMainOwner)
                if ($currentMainOwner -ne [uint32]$process.Id) {
                    throw ("Verified Salamander main window disappeared during navigation to {0}; {1}" -f
                        $pathSummary, (Get-TestProcessState))
                }
                $dialogText = Get-TestDialog
                if (-not [string]::IsNullOrEmpty($dialogText)) {
                    throw "Salamander raised a dialog during navigation to $($pathSummary): $dialogText"
                }
                $diagnostics.ForegroundPid = Get-ActiveProcessId
                if ($diagnostics.ForegroundPid -ne [uint32]$process.Id) {
                    # This is an infrastructure focus race, not a path failure.
                    # Recover the verified test window at most once, after
                    # checking for modal dialogs and without resending WM_COMMAND.
                    Recover-NavigationForeground -Diagnostics $diagnostics
                    $diagnostics.ForegroundPid = Get-ActiveProcessId
                }
                try {
                    $diagnostics.PanelPath = Read-PanelPath
                    $diagnostics.PanelReadError = '<none>'
                    return $diagnostics.PanelPath -ceq $Path
                }
                catch {
                    $diagnostics.PanelReadError = $_.Exception.Message
                    return $false
                }
            } "Salamander navigation to $pathSummary" -TimeoutSecondsOverride $probeSeconds

            Assert-True ($diagnostics.PanelPath -ceq $Path) "Salamander panel path agrees with requested ($($Path.Length) UTF-16 units)"
            return
        }
        catch {
            $failure = $_.Exception.Message
            $dialogText = Get-TestDialog
            if ($attempt -lt $maxNavigationAttempts -and
                $failure -like 'Timeout waiting for Salamander navigation*' -and
                $diagnostics.ForegroundPid -eq [uint32]$process.Id -and
                -not $diagnostics.FocusRecoveryAttempted -and
                [string]::IsNullOrEmpty($dialogText)) {
                Write-Warning ("GUI navigation not confirmed on attempt {0}; last path='{1}'; clipboard read='{2}'. Retrying once." -f
                    $attempt, (Format-GuiDiagnosticPath $diagnostics.PanelPath), $diagnostics.PanelReadError)
                continue
            }

            $process.Refresh()
            throw (("GUI navigation failed: {0}; Salamander PID={1}; HWND=0x{2:X}; title='{3}'; " +
                "foreground PID={4}; last panel path='{5}'; panel read error='{6}'; dialog='{7}'; attempts={8}; process state=[{9}]; foreground=[{10}]" ) -f
                $failure, $process.Id, $mainWindowHandle.ToInt64(),
                [SalamanderGuiNative]::GetWindowCaption($mainWindowHandle),
                $diagnostics.ForegroundPid, (Format-GuiDiagnosticPath $diagnostics.PanelPath),
                $diagnostics.PanelReadError, $dialogText, $attempt,
                (Get-TestProcessState), (Get-ForegroundWindowSummary))
        }
    }
}

# Commands 709/710 can fail to publish without raising a dialog (e.g. when
# the '..' row is focused or the W-backed row identity is unavailable).
# Retry only this read-only command, never alter the focused row or assume
# that a successful WM_COMMAND dispatch implies clipboard publication.
function Read-FocusedClipboardValue {
    param(
        [ValidateSet(709,710)][int]$CommandId,
        [Parameter(Mandatory)][string]$Sentinel
    )

    $maxAttempts = 2
    $lastObservedLength = -1
    $lastSequenceBefore = 0
    $lastSequenceAfter = 0
    $lastFailure = '<none>'
    $lastFocusBefore = '<not measured>'
    $lastFocusAfter = '<not measured>'

    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $dialog = Get-TestDialog
        if (-not [string]::IsNullOrEmpty($dialog)) {
            throw "Cannot read focused clipboard value while a Salamander dialog is open: $dialog"
        }
        if ((Get-ActiveProcessId) -ne [uint32]$process.Id) {
            throw "Cannot read focused clipboard value while Salamander is not foreground: $(Get-ForegroundWindowSummary)"
        }

        Set-ClipboardText $Sentinel
        if ((Get-ClipboardText) -cne $Sentinel) {
            $lastFailure = 'Clipboard sentinel did not round-trip'
        }
        else {
            $lastSequenceBefore = [SalamanderGuiNative]::GetClipboardSequenceNumber()
            $lastFocusBefore = [SalamanderGuiNative]::GetInputFocusSummary(
                $mainWindowHandle, [uint32]$process.Id)
            Invoke-SalamanderCommand -CommandId $CommandId
            $lastFocusAfter = [SalamanderGuiNative]::GetInputFocusSummary(
                $mainWindowHandle, [uint32]$process.Id)
            for ($poll = 0; $poll -lt 6; $poll++) {
                $observed = Get-ClipboardText
                $lastSequenceAfter = [SalamanderGuiNative]::GetClipboardSequenceNumber()
                $lastObservedLength = if ($null -eq $observed) { -1 } else { $observed.Length }
                if ($lastSequenceAfter -ne $lastSequenceBefore -and
                    -not [string]::IsNullOrWhiteSpace($observed) -and
                    $observed -cne $Sentinel) {
                    return $observed.TrimEnd([char]13, [char]10)
                }
                Start-Sleep -Milliseconds 150
            }
            $lastFailure = 'Command did not publish nonempty new clipboard text'
        }

        if ($attempt -lt $maxAttempts) {
            $retryFormat = "Focused clipboard command {0} did not publish on attempt {1}/{2} " +
                           "({3}); sequence before={4}, after={5}; focus before=[{6}]; " +
                           "focus after=[{7}]. Retrying read-only command without changing selection."
            Write-Warning ($retryFormat -f $CommandId, $attempt, $maxAttempts,
                           $lastFailure, $lastSequenceBefore, $lastSequenceAfter,
                           $lastFocusBefore, $lastFocusAfter)
            Start-Sleep -Milliseconds 250
        }
    }

    # A fresh path read identifies whether the panel is still in the expected
    # directory. Keep errors as diagnostics, not as a replacement for the
    # original failure.
    $panelPath = '<unavailable>'
    if ((Get-ActiveProcessId) -eq [uint32]$process.Id -and
        [string]::IsNullOrEmpty((Get-TestDialog))) {
        try { $panelPath = Read-PanelPath }
        catch { $panelPath = '<read failed: ' + $_.Exception.Message + '>' }
    }

    $failureFormat = "Focused clipboard command {0} failed after {1} attempts: {2}; " +
                     "observed UTF-16 units={3}; sequence before={4}, after={5}; " +
                     "panel path='{6}'; foreground={7}; dialog='{8}'; " +
                     "focus before=[{9}]; focus after=[{10}]"
    throw ($failureFormat -f $CommandId, $maxAttempts, $lastFailure,
           $lastObservedLength, $lastSequenceBefore, $lastSequenceAfter,
           $panelPath, (Get-ForegroundWindowSummary), (Get-TestDialog),
           $lastFocusBefore, $lastFocusAfter)
}

function Read-FocusedFilename {
    Read-FocusedClipboardValue -CommandId 710 -Sentinel 'SENTINEL_NOT_FILENAME'
}


# Mark exactly two verified regular-file rows. In Salamander, one Shift+Up
# selects the previous caret row only, so it cannot prove a two-file selection.
# Insert toggles the focused row and advances to the next row when possible.
function Select-TwoRegularFiles {
    param([string[]]$ExpectedNames)
    if ($ExpectedNames.Count -ne 2) {
        throw 'Exactly two expected filenames are required.'
    }

    Send-Keys '{END}'
    $lastName = Read-FocusedFilename
    Send-Keys '{UP}'
    $previousName = Read-FocusedFilename

    $observedNames = @($previousName, $lastName) | Sort-Object
    $expectedSorted = $ExpectedNames | Sort-Object
    Assert-True (($observedNames -join [char]0) -ceq ($expectedSorted -join [char]0)) 'Both adjacent file rows match the expected source filenames'

    Send-Keys '{INSERT}'
    Assert-True ((Read-FocusedFilename) -ceq $lastName) 'Insert selected the previous row and advanced to the last row'
    Send-Keys '{INSERT}'
}

# Locate a real directory row in a non-root test fixture. Its first row
# is the synthetic '..' entry, which does not publish a name via WM_COMMAND 710.
# Never press Enter until the exact directory row has been verified.
function Focus-DirectoryRow {
    param([Parameter(Mandatory)][string]$Name)

    Send-Keys '{HOME}'
    Send-Keys '{DOWN}'
    for ($row = 0; $row -lt 24; $row++) {
        if ((Read-FocusedFilename) -ceq $Name) {
            return
        }
        Send-Keys '{DOWN}'
    }
    throw "Expected directory row was not found: '$Name'. No Enter was sent."
}

function Read-FocusedFullname {
    Read-FocusedClipboardValue -CommandId 709 -Sentinel 'SENTINEL_NOT_FULLNAME'
}

function Test-Content {
    param([string]$Path)
    if (-not [IO.File]::Exists($Path)) { return $false }
    return [Linq.Enumerable]::SequenceEqual[byte]([IO.File]::ReadAllBytes($Path), $payload)
}


# The new modeless Find window uses fixed control IDs from
# src/common/win32_unicode_find_window.h. Send only bounded Win32 messages
# to HWNDs verified as children of the launched Salamander process.
function Get-UnicodeFindWindow {
    [SalamanderGuiNative]::FindUnicodeSearchWindow([uint32]$process.Id)
}

function Wait-FindCompleted {
    param([int]$Count)
    Wait-Until {
        $status = [SalamanderGuiNative]::ReadFindText(
            $script:findWindow, [uint32]$process.Id, 5118)
        if ($status -like 'Search incomplete*') { throw "Unicode Find failed: $status" }
        return $status -ceq "Completed: $Count Unicode results."
    } "Unicode Find completion with $Count results"
    Assert-True ([SalamanderGuiNative]::FindResultCount(
        $script:findWindow, [uint32]$process.Id) -eq $Count) "Unicode Find displays $Count results"
}

function Start-FindQuery {
    param([string]$Mask, [string]$Content, [int]$ExpectedCount)
    [SalamanderGuiNative]::SetFindText($script:findWindow, [uint32]$process.Id, 5102, $Mask)
    [SalamanderGuiNative]::SetFindText($script:findWindow, [uint32]$process.Id, 5103, $Content)
    [SalamanderGuiNative]::ClickFindButton($script:findWindow, [uint32]$process.Id, 5107)
    Wait-FindCompleted -Count $ExpectedCount
}

function Select-VerifiedFindResult {
    param([string]$ExpectedPath)
    $oldMouse = [Windows.Forms.Cursor]::Position
    try {
        $selected = [SalamanderGuiNative]::SelectSingleFindResult(
            $script:findWindow, [uint32]$process.Id)
    }
    finally { [Windows.Forms.Cursor]::Position = $oldMouse }
    Assert-True ($selected -eq 0) 'Unicode Find selected exactly one visible result'
    Set-ClipboardText 'SENTINEL_NOT_A_FIND_PATH'
    [SalamanderGuiNative]::ClickFindButton($script:findWindow, [uint32]$process.Id, 5109)
    $foundPath = Get-ClipboardText
    Assert-True ($foundPath -ceq $ExpectedPath) 'Unicode Find copied the exact UTF-16 result path'
}


function Assert-FindNotice {
    param([string]$ExpectedText)
    $script:findNotice = [IntPtr]::Zero
    Wait-Until {
        $script:findNotice = [SalamanderGuiNative]::FindUnicodeNotice(
            [uint32]$process.Id)
        return $script:findNotice -ne [IntPtr]::Zero
    } 'Unicode Find guarded shell dialog'
    $message = [SalamanderGuiNative]::DescribeWindow($script:findNotice)
    Assert-True ($message.Contains($ExpectedText, [StringComparison]::Ordinal)) (
        "Unicode Find warning identifies unsupported operation: $ExpectedText")
    [SalamanderGuiNative]::PostVerifiedFindNoticeClose(
        $script:findNotice, $script:findWindow, [uint32]$process.Id)
    Wait-Until {
        [SalamanderGuiNative]::FindUnicodeNotice(
            [uint32]$process.Id) -eq [IntPtr]::Zero
    } 'Unicode Find warning dismissed'
}

function Test-UnicodeFindGui {
    # Arrange: the GUI root is >MAX_PATH. Only test-owned files are altered.
    Go-ToPath $findRoot
    Restore-FilePanelFocus -ExpectedPath $findRoot
    Send-Keys '%{F7}'
    Wait-Until {
        $script:findWindow = Get-UnicodeFindWindow
        return $script:findWindow -ne [IntPtr]::Zero
    } 'modeless Unicode Find window launched by Alt+F7'
    Assert-True ([SalamanderGuiNative]::ReadFindText(
        $script:findWindow, [uint32]$process.Id, 5101) -ceq $findRoot) 'Unicode Find preserves full long-path search root'

    # Act / Assert: recursive enumeration, two original W names, two
    # different content encodings and empty-result handling.
    Start-FindQuery -Mask '*.txt' -Content '' -ExpectedCount 2
    Start-FindQuery -Mask '*.txt' -Content 'unique-utf8-probe' -ExpectedCount 1
    Select-VerifiedFindResult -ExpectedPath $findUtf8Path

    # Act / Assert: shell associations and the ANSI legacy dialog must
    # refuse a long path before crossing unsupported integration boundaries.
    # Message boxes are inspected and dismissed using owned HWNDs only.
    [SalamanderGuiNative]::PostFindButton($script:findWindow, [uint32]$process.Id, 5110)
    Assert-FindNotice -ExpectedText 'Windows shell associations may not support'
    Assert-True ([Linq.Enumerable]::SequenceEqual[byte](
        [IO.File]::ReadAllBytes($findUtf8Path), $findUtf8Bytes)) (
        'Refused shell open preserves long-path file content')

    [SalamanderGuiNative]::PostFindButton($script:findWindow, [uint32]$process.Id, 5115)
    Assert-FindNotice -ExpectedText 'legacy advanced Find interface cannot'
    Assert-True ((Get-UnicodeFindWindow) -eq $script:findWindow) (
        'Legacy advanced Find refusal preserves the Unicode Find window')

    # Recycle is deliberately unsupported for paths beyond MAX_PATH. Test
    # the actual GUI command and ensure no permanent deletion occurs.
    [SalamanderGuiNative]::ClickFindButton($script:findWindow, [uint32]$process.Id, 5114)
    Assert-True ([SalamanderGuiNative]::ReadFindText(
        $script:findWindow, [uint32]$process.Id, 5118) -like
        'Recycle unsupported or refused*') 'Unicode Find refuses long-path recycling'
    Assert-True ([Linq.Enumerable]::SequenceEqual[byte](
        [IO.File]::ReadAllBytes($findUtf8Path), $findUtf8Bytes)) (
        'Recycle refusal preserves the exact original file bytes')

    Start-FindQuery -Mask '*.txt' -Content 'unique-utf16-probe' -ExpectedCount 1
    Select-VerifiedFindResult -ExpectedPath $findUtf16Path
    Start-FindQuery -Mask '*.txt|*utf16*' -Content '' -ExpectedCount 1
    Select-VerifiedFindResult -ExpectedPath $findUtf8Path
    Start-FindQuery -Mask '*.txt' -Content 'not-present-in-disposable-fixtures' -ExpectedCount 0

    # Reject a relative root rather than searching the working directory.
    [SalamanderGuiNative]::SetFindText($script:findWindow, [uint32]$process.Id, 5101, 'relative\unsafe')
    [SalamanderGuiNative]::ClickFindButton($script:findWindow, [uint32]$process.Id, 5107)
    Assert-True ([SalamanderGuiNative]::ReadFindText(
        $script:findWindow, [uint32]$process.Id, 5118) -ceq
        'Invalid or too-long absolute search root.') 'Unicode Find rejects a relative search root'
    [SalamanderGuiNative]::SetFindText($script:findWindow, [uint32]$process.Id, 5101, $findRoot)

    # Copy and collision refusal must never change the original or target
    # bytes; result selection is rechecked against the clipboard identity.
    Start-FindQuery -Mask $findUtf8Name -Content '' -ExpectedCount 1
    Select-VerifiedFindResult -ExpectedPath $findUtf8Path
    [SalamanderGuiNative]::SetFindText($script:findWindow, [uint32]$process.Id, 5104, $findCopyPath)
    [SalamanderGuiNative]::ClickFindButton($script:findWindow, [uint32]$process.Id, 5111)
    Wait-Until { [IO.File]::Exists($findCopyPath) } 'Unicode Find copies file to new destination'
    Assert-True ([Linq.Enumerable]::SequenceEqual[byte](
        [IO.File]::ReadAllBytes($findCopyPath), $findUtf8Bytes) -and
        [Linq.Enumerable]::SequenceEqual[byte](
        [IO.File]::ReadAllBytes($findUtf8Path), $findUtf8Bytes)) 'Unicode Find copy preserves source and destination bytes'
    # Make the existing destination observably different from the source:
    # blindly copying the same payload would otherwise pass a byte check.
    $protectedFindBytes = [Text.Encoding]::UTF8.GetBytes('PROTECTED-UNICODE-FIND-DESTINATION')
    [IO.File]::WriteAllBytes($findCopyPath, $protectedFindBytes)
    [SalamanderGuiNative]::ClickFindButton($script:findWindow, [uint32]$process.Id, 5111)
    Assert-True ([SalamanderGuiNative]::ReadFindText(
        $script:findWindow, [uint32]$process.Id, 5118) -like 'File action rejected*') 'Unicode Find refuses destination overwrite'
    Assert-True ([Linq.Enumerable]::SequenceEqual[byte](
        [IO.File]::ReadAllBytes($findCopyPath), $protectedFindBytes) -and
        [Linq.Enumerable]::SequenceEqual[byte](
        [IO.File]::ReadAllBytes($findUtf8Path), $findUtf8Bytes)) 'Unicode Find collision preserves independent source and destination bytes'

    # Move uses the selected original long Unicode name, not a best-fit alias.
    [SalamanderGuiNative]::SetFindText($script:findWindow, [uint32]$process.Id, 5104, $findMovePath)
    [SalamanderGuiNative]::ClickFindButton($script:findWindow, [uint32]$process.Id, 5112)
    Wait-Until { [IO.File]::Exists($findMovePath) -and
        -not [IO.File]::Exists($findUtf8Path) } 'Unicode Find moves original file without overwrite'
    Assert-True ([Linq.Enumerable]::SequenceEqual[byte](
        [IO.File]::ReadAllBytes($findMovePath), $findUtf8Bytes)) 'Unicode Find move preserves exact bytes'

    # The second result exercises the real native modal Unicode rename dialog.
    Start-FindQuery -Mask $findUtf16Name -Content 'unique-utf16-probe' -ExpectedCount 1
    Select-VerifiedFindResult -ExpectedPath $findUtf16Path
    [SalamanderGuiNative]::PostFindButton($script:findWindow, [uint32]$process.Id, 5113)
    Wait-Until {
        $script:renameWindow = [SalamanderGuiNative]::FindRenameDialog([uint32]$process.Id)
        return $script:renameWindow -ne [IntPtr]::Zero
    } 'native Unicode Find rename confirmation dialog'
    [SalamanderGuiNative]::SetFindText($script:renameWindow, [uint32]$process.Id, 4101, $findRenamedName)
    [SalamanderGuiNative]::PostFindButton($script:renameWindow, [uint32]$process.Id, 1)
    Wait-Until { [IO.File]::Exists($findRenamedPath) -and
        -not [IO.File]::Exists($findUtf16Path) } 'Unicode Find renames nested result'
    Assert-True ([Linq.Enumerable]::SequenceEqual[byte](
        [IO.File]::ReadAllBytes($findRenamedPath), $findUtf16Bytes)) 'Unicode Find rename preserves UTF-16LE content'
    Start-FindQuery -Mask $findRenamedName -Content 'unique-utf16-probe' -ExpectedCount 1
    Select-VerifiedFindResult -ExpectedPath $findRenamedPath


    # Act / Assert: a hit changed after the search must never be used for
    # file operations. Change its length to avoid timestamp-resolution races.
    $staleName = 'stale_result_東京.txt'
    $stalePath = Join-Path $findRoot $staleName
    $staleDestination = Join-Path $destination 'must-not-be-created.txt'
    [IO.File]::WriteAllBytes($stalePath, [Text.Encoding]::UTF8.GetBytes('before'))
    Start-FindQuery -Mask $staleName -Content '' -ExpectedCount 1
    Select-VerifiedFindResult -ExpectedPath $stalePath
    $staleBytes = [Text.Encoding]::UTF8.GetBytes('changed-and-longer-after-search')
    [IO.File]::WriteAllBytes($stalePath, $staleBytes)
    [SalamanderGuiNative]::SetFindText(
        $script:findWindow, [uint32]$process.Id, 5104, $staleDestination)
    [SalamanderGuiNative]::ClickFindButton($script:findWindow, [uint32]$process.Id, 5111)
    Assert-True ([SalamanderGuiNative]::ReadFindText(
        $script:findWindow, [uint32]$process.Id, 5118) -like
        'The result has changed since the search*') (
        'Unicode Find rejects a modified result before file operations')
    Assert-True (-not [IO.File]::Exists($staleDestination) -and
        [Linq.Enumerable]::SequenceEqual[byte](
            [IO.File]::ReadAllBytes($stalePath), $staleBytes)) (
        'Modified-result refusal preserves source and creates no destination')


    # Exercise cancellation while the search worker is scanning a large file.
    # SetLength avoids allocating a 128 MiB managed buffer. The file is
    # disposable and no untrusted files are searched by this stress case.
    $cancelProbePath = Join-Path $findRoot 'cancel-probe.bin'
    $script:findCancelProbePath = $cancelProbePath
    $cancelStream = [IO.File]::Open(
        $cancelProbePath, [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $cancelStream.SetLength(128MB) }
    finally { $cancelStream.Dispose() }
    [SalamanderGuiNative]::SetFindText(
        $script:findWindow, [uint32]$process.Id, 5102, 'cancel-probe.bin')
    [SalamanderGuiNative]::SetFindText(
        $script:findWindow, [uint32]$process.Id, 5103, 'missing-cancellation-needle')
    [SalamanderGuiNative]::ClickFindButton(
        $script:findWindow, [uint32]$process.Id, 5107)
    [SalamanderGuiNative]::ClickFindButton(
        $script:findWindow, [uint32]$process.Id, 5108)
    Wait-Until {
        $status = [SalamanderGuiNative]::ReadFindText(
            $script:findWindow, [uint32]$process.Id, 5118)
        if ($status -like 'Completed:*') {
            throw 'Unicode Find completed too quickly to verify GUI cancellation.'
        }
        if ($status -like 'Search incomplete*') {
            throw "Unicode Find cancellation failed: $status"
        }
        return $status -like 'Search cancelled:*'
    } 'Unicode Find cancellation through the real GUI'
    Assert-True ([SalamanderGuiNative]::FindResultCount(
        $script:findWindow, [uint32]$process.Id) -eq 0) (
        'Cancelled Unicode Find does not invent any results')

    # Start another slow scan and close the modeless window while it runs.
    # Closing is posted because its GUI thread joins the worker; a timed
    # synchronous command could falsely report a hung window.
    [SalamanderGuiNative]::ClickFindButton(
        $script:findWindow, [uint32]$process.Id, 5107)
    [SalamanderGuiNative]::PostFindButton(
        $script:findWindow, [uint32]$process.Id, 5116)
    Wait-Until { (Get-UnicodeFindWindow) -eq [IntPtr]::Zero } (
        'Unicode Find closes and joins an active search worker')
    $process.Refresh()
    Assert-True (-not $process.HasExited) (
        'Closing an active Unicode Find search leaves Salamander alive')
    [IO.File]::Delete($cancelProbePath)
    $script:findCancelProbePath = $null
    Assert-True (-not [IO.File]::Exists($cancelProbePath)) (
        'GUI cancellation fixture cleaned up without modifying other files')
    Write-Host 'PASS: Unicode Find GUI search, actions, shell refusal, cancellation and worker shutdown.'
}

# Exercise the real CPluginsDlg -> CPlugins::TestAll -> InitDLL path
# using only Salamander's disposable child process, never an external DLL.
# Confirm target modules by *absolute path*, not by filename alone.
function Test-PluginLoadSmoke {
    $binaryRoot = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($SalamanderExe))
    # Fail closed even when the GUI driver is invoked directly rather than
    # via manage.cmd. PictView is unrelated to the four target plugins.
    . (Join-Path $PSScriptRoot '..\Plugin-Runtime-Prerequisites.ps1')
    $missingPictView = @(Get-MissingPictViewRuntimeFiles -BuildDirectory $binaryRoot -WicViewerVerified:$WicViewerVerified)
    if ($missingPictView.Count -gt 0) {
        throw ("Refusing global Test All with incomplete PictView runtime: " +
               ($missingPictView -join '; ') +
               ". Targeted plugin initialization is required instead.")
    }
    $expected = @(
        @('7zip', 'checksum', 'filecomp', 'renamer') | ForEach-Object {
            $name = $_
            $fullPath = [IO.Path]::GetFullPath(
                (Join-Path $binaryRoot ("plugins\{0}\{0}.spl" -f $name)))
            if (-not [IO.File]::Exists($fullPath)) {
                throw "Missing built plug-in for GUI integration: $fullPath"
            }
            $fullPath
        }
    )
    Assert-True ($expected.Count -eq 4) 'All four built x64 plug-in paths exist'

    # Arrange: use the checked GUID-scoped source and the verified main HWND.
    Assert-True (Test-Content $unicodeShortFile) 'Plugin smoke source fixture intact before loading'
    [SalamanderGuiNative]::PostVerifiedPluginManagerOpen(
        $mainWindowHandle, [uint32]$process.Id)
    $manager = @{ Window = [IntPtr]::Zero }
    Wait-Until {
        $manager.Window = [SalamanderGuiNative]::FindPluginManagerWindow(
            $mainWindowHandle, [uint32]$process.Id)
        return $manager.Window -ne [IntPtr]::Zero
    } 'verified Salamander Plug-in Manager dialog'
    Write-Host 'PASS: verified Plug-in Manager dialog belongs to launched Salamander PID'

    # Act: the application's actual Test All button invokes each installed
    # plugin's InitDLL. This is explicit opt-in: third-party plugins can run.
    [SalamanderGuiNative]::PostVerifiedPluginTestAll(
        $manager.Window, $mainWindowHandle, [uint32]$process.Id)

    # Assert: the modules must be present in the real child process. InitDLL
    # unloads DLLs that fail entry-point and interface validation. A module
    # with the correct filename in an unrelated directory cannot satisfy it.
    $missing = @{ Paths = @() }
    try {
        Wait-Until {
            $process.Refresh()
            if ($process.HasExited) { throw 'Salamander exited during plugin initialization.' }
            $loadedPaths = [Collections.Generic.HashSet[string]]::new(
                [StringComparer]::OrdinalIgnoreCase)
            foreach ($module in $process.Modules) {
                [void]$loadedPaths.Add([IO.Path]::GetFullPath($module.FileName))
            }
            $missing.Paths = @($expected | Where-Object {
                -not $loadedPaths.Contains($_)
            })

            # Check completion before reporting a modal dialog: Test All may
            # show an informational success dialog after modules are loaded.
            if ($missing.Paths.Count -eq 0) { return $true }

            $blocked = [SalamanderGuiNative]::GetBlockingPluginDialog(
                $manager.Window, $mainWindowHandle, [uint32]$process.Id)
            if (-not [string]::IsNullOrWhiteSpace($blocked)) {
                $diagnostic = ("Blocking plug-in initialization dialog: {0}; " +
                               "Missing target plug-in modules: {1}") -f
                               $blocked, ($missing.Paths -join '; ')
                if ($blocked -match '(?i)pictview') {
                    # On x64 PictView launches the 32-bit SalPVEnv helper,
                    # which depends on PVW32Cnv.dll. Missing files are a
                    # concrete failure; present files require further
                    # runtime diagnosis rather than being declared valid.
                    $pictViewDirectory = Join-Path $binaryRoot 'plugins\pictview'
                    $sidecars = @(@('pictview.spl', 'SalPVEnv.exe', 'PVW32Cnv.dll') |
                        ForEach-Object {
                            $candidate = Join-Path $pictViewDirectory $_
                            $status = if ([IO.File]::Exists($candidate)) { 'present' } else { 'MISSING' }
                            "$candidate ($status)"
                        })
                    $diagnostic += '; PictView runtime files: ' + ($sidecars -join '; ')
                }
                throw $diagnostic
            }
            return $false
        } 'four exact plug-in modules loaded in the Salamander process' -TimeoutSecondsOverride 90
    }
    catch {
        $message = $_.Exception.Message
        if ($message -like 'Timeout waiting*') {
            throw ("{0}; Missing target plug-in modules: {1}; process windows: {2}" -f
                   $message, ($missing.Paths -join '; '),
                   (Get-ProcessWindowSummary -OwnerProcessId ([uint32]$process.Id)))
        }
        throw
    }

    foreach ($path in $expected) {
        Write-Host "PASS: Salamander loaded and retained plug-in module $path"
    }
    Assert-True (Test-Content $unicodeShortFile) 'Plugin test preserved original Unicode fixture bytes'
    Write-Host 'PASS: real Plug-in Manager Test All initialized four built-in x64 plug-in modules.'
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
    if ($MaximumPathOnly) {
        # Arrange: real Win32-scale directory depth with a single 255-unit
        # Unicode file. This mode performs read-only GUI checks and never
        # sends F2/F5/F6/F8 to such an extreme fixture.
        $maximumName = 'Größe_東京_😀_'
        $maximumName += 'x' * (255 - $maximumName.Length - '.bin'.Length)
        $maximumName += '.bin'
        Assert-True ($maximumName.Length -eq 255) 'Maximum GUI filename is 255 UTF-16 units'

        $maximumDirectory = $source
        $requestedLength = 32700
        $parentLength = $requestedLength - 1 - $maximumName.Length
        while ($maximumDirectory.Length -lt $parentLength) {
            $remaining = $parentLength - $maximumDirectory.Length
            if ($remaining -lt 2) {
                throw 'Cannot build an exact maximum-length directory component.'
            }
            $length = if ($remaining -le 202) { $remaining - 1 } else { 200 }
            $maximumDirectory = Join-Path $maximumDirectory ('x' * $length)
            [IO.Directory]::CreateDirectory($maximumDirectory) | Out-Null
        }

        $maximumFile = Join-Path $maximumDirectory $maximumName
        Assert-True ($maximumFile.Length -eq $requestedLength) 'Maximum GUI file path is 32700 UTF-16 units'
        [IO.File]::WriteAllBytes($maximumFile, $payload)
        Assert-True (Test-Content $maximumFile) 'Near-maximum GUI fixture bytes written intact'
    }
    if ($UnicodeFindOnly) {
        # Arrange: two independently identifiable search files. The root is
        # beyond MAX_PATH, and the second file requires recursive search.
        $findRoot = $source
        foreach ($index in 1..4) {
            $findRoot = Join-Path $findRoot ('find-depth-' + $index + '-' + ('q' * 62))
            [IO.Directory]::CreateDirectory($findRoot) | Out-Null
        }
        Assert-True ($findRoot.Length -gt 260) 'Unicode Find fixture root exceeds MAX_PATH'
        $findNested = Join-Path $findRoot 'nested-大阪'
        [IO.Directory]::CreateDirectory($findNested) | Out-Null
        [IO.Directory]::CreateDirectory($destination) | Out-Null
        $findUtf8Name = 'find_utf8_東京.txt'
        $findUtf16Name = 'find_utf16_大阪.txt'
        $findRenamedName = 'renamed_日本_😀.txt'
        $findUtf8Path = Join-Path $findRoot $findUtf8Name
        $findUtf16Path = Join-Path $findNested $findUtf16Name
        $findCopyPath = Join-Path $destination 'copied_東京.txt'
        $findMovePath = Join-Path $destination 'moved_東京.txt'
        $findRenamedPath = Join-Path $findNested $findRenamedName
        $findUtf8Bytes = [Text.Encoding]::UTF8.GetBytes('source unique-utf8-probe 東京 😀')
        $findUtf16Bytes = [Text.Encoding]::Unicode.GetBytes('source unique-utf16-probe 大阪 😀')
        [IO.File]::WriteAllBytes($findUtf8Path, $findUtf8Bytes)
        [IO.File]::WriteAllBytes($findUtf16Path, $findUtf16Bytes)
    }
    if ($TemporaryDirectoryDeletionOnly) {
        # Arrange: a uniquely owned temporary directory with a real nested
        # Unicode file beyond MAX_PATH. This is deliberately not a mock.
        $temporaryDirectoryName = 'OpenSal-GuiLong-Delete-東京'
        $temporaryDirectory = Join-Path $source $temporaryDirectoryName
        $temporaryChild = $temporaryDirectory
        foreach ($index in 1..4) {
            $temporaryChild = Join-Path $temporaryChild (
                'depth-' + $index + '-' + ('x' * 64))
            [void][IO.Directory]::CreateDirectory($temporaryChild)
        }
        $temporaryLeaf = Join-Path $temporaryChild 'Größe_大阪_😀.bin'
        [IO.File]::WriteAllBytes($temporaryLeaf, $payload)
        Assert-True ($temporaryLeaf.Length -gt 260) 'Temporary directory fixture exceeds MAX_PATH'
        Assert-True (Test-Content $temporaryLeaf) 'Nested Unicode temporary payload is intact'
    }
    if ($BaselineOnly) {
        # The baseline must also demonstrate that the automated keystroke
        # reaches the focused file panel without manual window activation.
        $focusProbeName = 'focus-probe.txt'
        [IO.File]::WriteAllBytes((Join-Path $source $focusProbeName), $payload)
    }
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
    if ($ShortUnicodeTransferOnly -or $ShortUnicodeTransferCollisionOnly -or $ShortUnicodeMultiSelectOnly) {
        [IO.Directory]::CreateDirectory($destination) | Out-Null
        [IO.Directory]::CreateDirectory($moveDir) | Out-Null
    }
    if ($ShortUnicodeDirectoryRenameOnly) {
        $unicodeDirectoryName = 'Ordner_東京_😀'
        $renamedUnicodeDirectoryName = 'Verschoben_大阪_😀'
        $unicodeDirectoryPath = Join-Path $source $unicodeDirectoryName
        [IO.Directory]::CreateDirectory($unicodeDirectoryPath) | Out-Null
        [IO.File]::WriteAllBytes((Join-Path $unicodeDirectoryPath 'child.txt'), $payload)
    }
    if ($ShortUnicodeMultiSelectOnly) {
        # The transfer source deliberately mixes one lossy Unicode name with
        # one ordinary ASCII entry. F5/F6 must transfer BOTH selected rows.
        $secondName = 'baseline-second.txt'
        $secondBytes = [Text.Encoding]::UTF8.GetBytes('INDEPENDENT-ASCII-PAYLOAD')
        [IO.File]::WriteAllBytes((Join-Path $source $secondName), $secondBytes)
    }
    if ($ShortUnicodeCollisionOnly -or $ShortUnicodeRowIdentityOnly -or $ShortUnicodeUnsafeOperationsOnly) {
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
        -not $PluginLoadSmokeOnly -and
        -not $ShortUnicodeCollisionOnly -and -not $ShortUnicodeRowIdentityOnly -and
        -not $ShortUnicodeBestFitOnly -and -not $ShortUnicodeRenameOnly -and
        -not $ShortUnicodeTransferOnly -and -not $ShortUnicodeTransferCollisionOnly -and
        -not $ShortUnicodeMultiSelectOnly -and
        -not $ShortUnicodeDirectoryRenameOnly -and
        -not $ShortUnicodeRecycleOnly -and
        -not $ShortUnicodeUnsafeOperationsOnly -and -not $ShortOperationsOnly -and
        -not $UnicodeFindOnly -and -not $MaximumPathOnly -and
        -not $TemporaryDirectoryDeletionOnly) {
        [IO.Directory]::CreateDirectory($destination) | Out-Null
        [IO.Directory]::CreateDirectory($moveDir) | Out-Null
        [IO.Directory]::CreateDirectory($maxDir) | Out-Null
        [IO.File]::WriteAllBytes((Join-Path $maxDir $maxName), $payload)
        # Manual OpenSal-Names fixtures expose two transitions from an
        # ordinary short panel to a directory beyond MAX_PATH. The existing
        # GUI test only entered child folders after the panel was already long.
        $maxDirectoryName = 'd' * 255
        $maxDirectoryPath = Join-Path $source $maxDirectoryName
        [IO.Directory]::CreateDirectory($maxDirectoryPath) | Out-Null
        [IO.File]::WriteAllBytes(
            (Join-Path $maxDirectoryPath 'max-directory-marker.bin'), $payload)
        $boundaryDirectoryNames = @(
            'Ordner-A-' + ('a' * 68)
            'Ordner-B-' + ('b' * 68)
            'Ordner-C-' + ('c' * 68)
            'Ordner-D-' + ('d' * 68)
        )
        $boundaryDirectoryPaths = @()
        $parentDirectory = $source
        foreach ($directoryName in $boundaryDirectoryNames) {
            $parentDirectory = Join-Path $parentDirectory $directoryName
            [IO.Directory]::CreateDirectory($parentDirectory) | Out-Null
            $boundaryDirectoryPaths += $parentDirectory
        }
        [IO.File]::WriteAllBytes(
            (Join-Path $parentDirectory 'nested-directory-marker.bin'), $payload)
        Assert-True (($maxDirectoryName.Length -eq 255) -and
            ($maxDirectoryPath.Length -gt 260)) '255-unit directory fixture crosses MAX_PATH'
        Assert-True (($boundaryDirectoryPaths[1].Length -lt 260) -and
            ($boundaryDirectoryPaths[2].Length -gt 260)) 'Nested directory fixture crosses MAX_PATH on Enter'
        foreach ($n in 1..5) {
            $deep = Join-Path $deep ('depth-' + $n + '-' + ('x' * 56))
            [IO.Directory]::CreateDirectory($deep) | Out-Null
        }
        $sourceFile = Join-Path $deep $utfName
        [IO.File]::WriteAllBytes($sourceFile, $payload)
        $nestedLongDirectory = Join-Path $deep 'nested-child'
        [IO.Directory]::CreateDirectory($nestedLongDirectory) | Out-Null
        $treeMoveName = 'tree-move'
        $treeMoveSource = Join-Path $deep $treeMoveName
        $treeMoveLeaf = Join-Path (Join-Path $treeMoveSource 'nested') 'payload.bin'
        [IO.Directory]::CreateDirectory((Split-Path -Parent $treeMoveLeaf)) | Out-Null
        [IO.File]::WriteAllBytes($treeMoveLeaf, $payload)
        $beyondClipboardLimit = Join-Path $deep ('z-' + ('x' * 150))
        [IO.Directory]::CreateDirectory($beyondClipboardLimit) | Out-Null
        Assert-True ($beyondClipboardLimit.Length -gt (2 * 260)) 'GUI clipboard path exceeds former 2*MAX_PATH buffer'
        Assert-True ($sourceFile.Length -gt 260) 'Long-path fixture exceeds 260 UTF-16 units'
    }

    # Never attach keystrokes to an existing user instance.
    if (@(Get-Process salamand -ErrorAction SilentlyContinue).Count -gt 0) {
        throw 'Please close existing Salamander instances before running automated GUI tests.'
    }
    # Always override BOTH saved panel paths before LoadConfig restores them.
    # Previous GUI runs may have persisted a disposable fixture path which was
    # subsequently deleted. -p 2 makes the active test panel deterministic.
    # Quotes keep paths with spaces safe for Salamander's command-line parser.
    $startupArgs = '-l "{0}" -r "{0}" -p 2' -f $source
    # The first Salamander instance searches %TEMP% for SAL*.tmp left by
    # previous sessions. A test must neither prompt about nor delete files
    # belonging to the user or an earlier application run.
    $processTemp = Join-Path $root 'process-temp'
    if ($processTemp.Length -ge 240) {
        throw 'GUI test TEMP path is too long for native Salamander disk-cache paths.'
    }
    [void][IO.Directory]::CreateDirectory($processTemp)
    $process = Start-Process -FilePath $SalamanderExe -ArgumentList $startupArgs `
        -WorkingDirectory (Split-Path -Parent $SalamanderExe) `
        -Environment @{ TEMP = $processTemp; TMP = $processTemp } -PassThru
    # Process.MainWindowHandle/MainWindowTitle may select an auxiliary
    # window. The GUI driver must use the HWND found by Win32 enumeration.
    try {
        Wait-Until {
            $process.Refresh()
            if ($process.HasExited) {
                throw 'Test Salamander exited before its main window became ready.'
            }
            $script:mainWindowHandle = [SalamanderGuiNative]::FindMainWindow([uint32]$process.Id)
            if ($script:mainWindowHandle -eq [IntPtr]::Zero) {
                foreach ($window in [SalamanderGuiNative]::GetProcessWindows([uint32]$process.Id)) {
                    if ($window.Visible -and $window.Title -ceq 'Error Loading Configuration') {
                        throw ('Salamander startup configuration dialog: ' +
                            [SalamanderGuiNative]::DescribeWindow($window.Handle))
                    }
                }
            }
            return $script:mainWindowHandle -ne [IntPtr]::Zero
        } 'visible Open Salamander top-level window owned by launched process'
    }
    catch {
        $process.Refresh()
        $windowSummary = Get-ProcessWindowSummary -OwnerProcessId ([uint32]$process.Id)
        throw (("GUI startup failed: {0}; launched PID={1}; .NET MainWindowHandle=0x{2:X}; " +
            ".NET title='{3}'; process windows: {4}") -f
            $_.Exception.Message, $process.Id, $process.MainWindowHandle.ToInt64(),
            $process.MainWindowTitle, $windowSummary)
    }
    # A visible top-level window is not evidence that startup has finished.
    # Do not begin clipboard navigation or keyboard simulation until the
    # launched GUI process has reached its initial input-idle state.
    if (-not $process.WaitForInputIdle(10000)) {
        throw "Test Salamander did not become input-idle within 10 seconds (PID $($process.Id))."
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
    Restore-FilePanelFocus -ExpectedPath $source
    # Go-ToPath already verified the observed panel path. A duplicate
    # WM_COMMAND 711 adds no coverage and can race with GUI processing.
    Write-Host 'PASS: GUI driver can navigate a normal short directory'
    if ($TemporaryDirectoryDeletionOnly) {
        # Act: delete the exact test-owned directory through Salamander's F8
        # command. Merely deleting it with .NET would not test the reported bug.
        Assert-True ((Read-PanelPath) -ceq $source) 'Disposable parent panel verified before F8 directory delete'
        Focus-DirectoryRow -Name $temporaryDirectoryName
        Assert-True ((Read-FocusedFilename) -ceq $temporaryDirectoryName) 'Exact temporary directory selected for F8'
        Send-Keys '{F8}'
        Start-Sleep -Milliseconds 350
        Send-Keys '{ENTER}'
        # Assert: disappearance on disk (not just a refreshed panel row)
        # is required, and the adjacent fixture must remain untouched.
        try {
            Wait-Until { -not [IO.Directory]::Exists($temporaryDirectory) } 'F8 recursive long-path directory deletion'
        }
        catch {
            throw ("F8 did not delete the long-path directory: {0}; dialog='{1}'" -f
                $_.Exception.Message, (Get-TestDialog))
        }
        Assert-True ([IO.Directory]::Exists($source)) 'Parent fixture survives F8 directory deletion'
        Assert-True (Test-Content $unicodeShortFile) 'Unrelated Unicode fixture survives F8 directory deletion'
        $passed = $true
        Write-Host 'PASS: Salamander F8 recursively deleted the real long-path temporary directory.'
        return
    }
    if ($UnicodeFindOnly) {
        Test-UnicodeFindGui
        $passed = $true
        return
    }
    if ($PluginLoadSmokeOnly) {
        Test-PluginLoadSmoke
        $passed = $true
        return
    }
    if ($MaximumPathOnly) {
        # Act: navigate using Salamander's real clipboard command, not .NET.
        # Assert both the complete panel path and the focused full filename;
        # any truncation, ANSI alias or unhandled limit is a test failure.
        Wait-ForNativeDebugger
        Go-ToPath $maximumDirectory
        Assert-True ((Read-PanelPath) -ceq $maximumDirectory) 'GUI preserves 32444-unit parent directory'
        Restore-FilePanelFocus -ExpectedPath $maximumDirectory
        Send-Keys '{END}'
        Assert-True ((Read-FocusedFilename) -ceq $maximumName) 'GUI preserves 255-unit Unicode filename at 32700-unit total path'
        Assert-True ((Read-FocusedFullname) -ceq $maximumFile) 'GUI publishes complete 32700-unit Unicode file path'
        Assert-True (Test-Content $maximumFile) 'GUI read-only checks did not change near-limit bytes'
        $passed = $true
        Write-Host 'PASS: REAL Salamander GUI 32700-unit path with a 255-unit Unicode filename.'
        return
    }
    if ($BaselineOnly) {
        $focusBeforeEnd = [SalamanderGuiNative]::GetInputFocusSummary(
            $mainWindowHandle, [uint32]$process.Id)
        Send-Keys '{END}'
        try {
            Recover-BaselineReadFocus
            $focusedName = Read-FocusedFilename
        }
        catch {
            $focusAfterEnd = [SalamanderGuiNative]::GetInputFocusSummary(
                $mainWindowHandle, [uint32]$process.Id)
            $failureFormat = "Short-path GUI focus probe failed: {0}; focus before End=[{1}]; " +
                             "focus after End=[{2}]; test file exists={3}. No extra keys were sent."
            throw ($failureFormat -f $_.Exception.Message, $focusBeforeEnd,
                   $focusAfterEnd, [IO.File]::Exists((Join-Path $source $focusProbeName)))
        }
        Assert-True ($focusedName -ceq $focusProbeName) 'Unattended keyboard focus reaches the test file panel'
        $passed = $true
        Write-Host 'PASS: GUI automation driver works with short ASCII paths and verified keyboard focus.'
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
        Assert-True ((Read-FocusedFullname) -ceq $bestFitFile) 'Best-fit Unicode full path recovered without question mark'
        Assert-True (Test-Content $bestFitFile) 'Best-fit Unicode file content remains intact'
        $passed = $true
        Write-Host 'PASS: Unicode GUI filename round-trip survives non-question-mark ANSI best-fit mapping.'
        return
    }

    if ($ShortUnicodeRecycleOnly) {
        # Arrange: a single disposable source file, not a selected directory.
        Send-Keys '{END}'
        Assert-True ((Read-FocusedFilename) -ceq $utfName) 'Unicode F8 source identity verified'
        # Act: the shell Recycle Bin path must never silently delete a file.
        Send-Keys '{F8}'
        $observed = @{ Dialog = $null }
        Wait-Until {
            $observed.Dialog = Get-TestDialog
            return $observed.Dialog -match 'Recycle Unicode file|legacy ANSI file-operation engine'
        } 'Unicode F8 recycle or safe refusal'
        if ($observed.Dialog -match 'legacy ANSI file-operation engine') {
            Send-Keys '{ESC}'
            Assert-True (Test-Content $unicodeShortFile) 'Unicode F8 refusal preserves file bytes'
            if ($VerifyRecycleRestore) {
                throw 'Explicit Recycle Bin restore integration cannot run: Salamander refused recycling.'
            }
            $passed = $true
            Write-Host 'SKIP: Recycle Bin is not enabled or file is not eligible for wide-shell recycling.'
            return
        }
        Send-Keys '{ENTER}'
        Wait-Until { -not [IO.File]::Exists($unicodeShortFile) } 'Unicode F8 moves fixture to Recycle Bin'
        if ($VerifyRecycleRestore) {
            # Arrange: resolve only our specific Unicode filename and its
            # GUID-scoped original directory via shell metadata, never by
            # a Recycle Bin list index or a partial filename match.
            $shell = New-Object -ComObject Shell.Application
            $recycleFolder = $shell.NameSpace(10) # CSIDL_BITBUCKET
            if ($null -eq $recycleFolder) { throw 'Windows Recycle Bin shell folder is unavailable.' }
            $found = @{ Item = $null }
            Wait-Until {
                $found.Item = Find-VerifiedRecycledFixtureItem -RecycleFolder $recycleFolder -OriginalFullPath $unicodeShortFile
                return $null -ne $found.Item
            } 'exact Unicode file and original directory appear in the Recycle Bin'
            Assert-True ($null -ne $found.Item) 'Recycle Bin retains exact Unicode filename and original directory'

            # Act: execute only the verified item's explicitly named Restore
            # verb. Refuse any unknown localization or existing destination.
            Restore-VerifiedRecycledFixtureItem -Item $found.Item -OriginalFullPath $unicodeShortFile

            # Assert: restoration must produce exactly the original file bytes.
            Wait-Until {
                try { return (Test-Content $unicodeShortFile) }
                catch [IO.IOException] { return $false }
            } 'Unicode Recycle Bin restore completes with identical bytes'
            Assert-True (Test-Content $unicodeShortFile) 'Unicode Recycle Bin restore preserves exact UTF-8 file bytes'
            Wait-Until {
                return $null -eq (Find-VerifiedRecycledFixtureItem -RecycleFolder $recycleFolder -OriginalFullPath $unicodeShortFile)
            } 'restored fixture disappears from Recycle Bin'
            Write-Host 'PASS: verified Unicode F8 Recycle Bin round trip and original content.'
        }
        else {
            Write-Host 'PASS: Unicode F8 source removed; restore remains unverified in the regular GUI suite.'
        }
        $passed = $true

        return
    }

    if ($ShortUnicodeDirectoryRenameOnly) {
        # Directory sorting precedes files; the first non-".." entry is
        # the disposable Unicode folder.
        Send-Keys '{HOME}'
        Send-Keys '{DOWN}'
        Assert-True ((Read-FocusedFilename) -ceq $unicodeDirectoryName) 'Unicode directory row selected for F2'
        Set-ClipboardText $renamedUnicodeDirectoryName
        Send-Keys '{F2}'
        Start-Sleep -Milliseconds 250
        Send-Keys '^a'
        Send-Keys '^v'
        Send-Keys '{ENTER}'
        $renamedDirectory = Join-Path $source $renamedUnicodeDirectoryName
        Wait-Until { [IO.Directory]::Exists($renamedDirectory) -and
            -not [IO.Directory]::Exists($unicodeDirectoryPath) } 'Unicode F2 directory rename'
        Assert-True (Test-Content (Join-Path $renamedDirectory 'child.txt')) 'Unicode F2 directory child bytes retained'
        $passed = $true
        Write-Host 'PASS: Unicode F2 directory rename preserves nested contents.'
        return
    }

    if ($ShortUnicodeMultiSelectOnly) {
        # Arrange: existing, distinct source and destination directories.
        Send-Keys '{TAB}'
        Go-ToPath $destination
        Send-Keys '{TAB}'
        Assert-True ((Read-PanelPath) -ceq $source) 'Multi-file source panel verified'
        Select-TwoRegularFiles -ExpectedNames @($utfName, $secondName)
        Send-Keys '{F5}'
        $observed = @{ Dialog = $null }
        Wait-Until {
            $observed.Dialog = Get-TestDialog
            return -not [string]::IsNullOrEmpty($observed.Dialog)
        } 'Unicode F5 multi-selection confirmation dialog'
        if ($observed.Dialog -notmatch 'Copy 2 selected Unicode/ASCII disk files') {
            throw "Expected two-file Unicode F5 batch confirmation; observed: $($observed.Dialog)"
        }
        Send-Keys '{ENTER}'
        $unicodeCopy = Join-Path $destination $utfName
        $asciiCopy = Join-Path $destination $secondName
        Wait-Until { (Test-Content $unicodeCopy) -and
            [IO.File]::Exists($asciiCopy) -and
            [Linq.Enumerable]::SequenceEqual[byte](
                [IO.File]::ReadAllBytes($asciiCopy), $secondBytes) } 'Unicode F5 copies both selected files'
        Assert-True (Test-Content $unicodeShortFile) 'Unicode F5 multiselect preserved original'

        # Arrange: right panel is now the source, left panel the new target.
        Send-Keys '{TAB}'
        Go-ToPath $destination
        Send-Keys '{TAB}'
        Go-ToPath $moveDir
        Send-Keys '{TAB}'
        Assert-True ((Read-PanelPath) -ceq $destination) 'Unicode F6 multi-file source panel verified'
        Select-TwoRegularFiles -ExpectedNames @($utfName, $secondName)
        Send-Keys '{F6}'
        $observed = @{ Dialog = $null }
        Wait-Until {
            $observed.Dialog = Get-TestDialog
            return -not [string]::IsNullOrEmpty($observed.Dialog)
        } 'Unicode F6 multi-selection confirmation dialog'
        if ($observed.Dialog -notmatch 'Move 2 selected Unicode/ASCII disk files') {
            throw "Expected two-file Unicode F6 batch confirmation; observed: $($observed.Dialog)"
        }
        Send-Keys '{ENTER}'
        $unicodeMoved = Join-Path $moveDir $utfName
        $asciiMoved = Join-Path $moveDir $secondName
        Wait-Until { (Test-Content $unicodeMoved) -and
            [IO.File]::Exists($asciiMoved) -and
            [Linq.Enumerable]::SequenceEqual[byte](
                [IO.File]::ReadAllBytes($asciiMoved), $secondBytes) -and
            -not [IO.File]::Exists($unicodeCopy) -and
            -not [IO.File]::Exists($asciiCopy) } 'Unicode F6 moves both selected files'
        Assert-True (Test-Content $unicodeShortFile) 'Original Unicode source retained'
        $passed = $true
        Write-Host 'PASS: multi-selection Unicode F5/F6 transfers every selected regular file.'
        return
    }

    if ($ShortUnicodeRowIdentityOnly) {
        # Arrange: two distinct Unicode source entries with an identical
        # ANSI alias on non-UTF-8 code pages, present simultaneously.
        Send-Keys '{END}'
        $lastName = Read-FocusedFilename
        $lastFull = Read-FocusedFullname
        Send-Keys '{UP}'
        $previousName = Read-FocusedFilename
        $previousFull = Read-FocusedFullname
        $actualNames = @($lastName, $previousName) | Sort-Object
        $expectedNames = @($utfName, $utfCollisionName) | Sort-Object
        Assert-True (($actualNames -join [char]0) -ceq ($expectedNames -join [char]0)) 'Distinct per-row Unicode names survive ANSI alias collision'
        Assert-True (($lastFull -ceq (Join-Path $source $lastName)) -and
            ($previousFull -ceq (Join-Path $source $previousName))) 'Distinct full Unicode clipboard paths follow selected panel row'
        Assert-True ((Test-Content $unicodeShortFile) -and
            ([Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($collisionFile)) -ceq 'DISTINCT-OSAKA-FILE')) 'Both Unicode collision fixture contents preserved'
        $passed = $true
        Write-Host 'PASS: both colliding ANSI alias rows retain their independent UTF-16 names and full paths.'
        return
    }

    if ($ShortUnicodeTransferCollisionOnly) {
        # Arrange: two distinct payloads under the same UTF-16 name.
        $protected = Join-Path $destination $utfName
        $marker = [Text.Encoding]::UTF8.GetBytes('TARGET-MUST-STAY-IN-PLACE')
        [IO.File]::WriteAllBytes($protected, $marker)
        Send-Keys '{TAB}'
        Go-ToPath $destination
        Send-Keys '{TAB}'
        Send-Keys '{END}'
        Assert-True ((Read-FocusedFilename) -ceq $utfName) 'Unicode collision source selected'
        foreach ($operation in @('{F5}', '{F6}')) {
            # Act: a name collision must never silently overwrite.
            Send-Keys $operation
            Wait-Until { (Get-TestDialog) -match 'Unicode file to the other panel' } 'Unicode transfer confirmation'
            Send-Keys '{ENTER}'
            Wait-Until { (Get-TestDialog) -match 'Unicode operation failed' } 'Unicode transfer overwrite refusal'
            Send-Keys '{ESC}'
            Wait-Until { -not (Get-TestDialog) } 'Unicode collision error dismissal'
            # Assert: both files retain their independent bytes.
            Assert-True (Test-Content $unicodeShortFile) 'Unicode transfer collision source intact'
            Assert-True ([Linq.Enumerable]::SequenceEqual[byte](
                [IO.File]::ReadAllBytes($protected), $marker)) 'Unicode transfer collision target intact'
        }
        $passed = $true
        Write-Host 'PASS: UTF-16 F5/F6 do not overwrite existing Unicode destinations.'
        return
    }

    if ($ShortUnicodeTransferOnly) {
        # Arrange: separate source and target panels, both below MAX_PATH.
        Send-Keys '{TAB}'
        Go-ToPath $destination
        Send-Keys '{TAB}'
        Assert-True ((Read-PanelPath) -ceq $source) 'Unicode F5 source panel verified'
        Send-Keys '{END}'
        Assert-True ((Read-FocusedFilename) -ceq $utfName) 'Unicode F5 source identity verified'
        # Act: F5 must use the exact UTF-16 source name and copy to destination.
        Send-Keys '{F5}'
        Wait-Until { (Get-TestDialog) -match 'Copy the Unicode file' } 'Unicode F5 confirmation'
        Send-Keys '{ENTER}'
        $copied = Join-Path $destination $utfName
        Wait-Until { Test-Content $copied } 'Unicode F5 copy to other disk panel'
        # Assert: original remains, payload matches.
        Assert-True (Test-Content $unicodeShortFile) 'Unicode F5 preserves source bytes'

        # Arrange: move the copy to a distinct disposable directory.
        Send-Keys '{TAB}'
        Assert-True ((Read-PanelPath) -ceq $destination) 'Unicode F6 source panel verified'
        Send-Keys '{TAB}'
        Go-ToPath $moveDir
        Send-Keys '{TAB}'
        Send-Keys '{END}'
        Assert-True ((Read-FocusedFilename) -ceq $utfName) 'Unicode F6 source identity verified'
        # Act: F6 must not leave a duplicate in the source directory.
        Send-Keys '{F6}'
        Wait-Until { (Get-TestDialog) -match 'Move the Unicode file' } 'Unicode F6 confirmation'
        Send-Keys '{ENTER}'
        $moved = Join-Path $moveDir $utfName
        Wait-Until { (Test-Content $moved) -and -not [IO.File]::Exists($copied) } 'Unicode F6 move to other disk panel'
        # Assert: both source-of-truth and moved content are intact.
        Assert-True (Test-Content $unicodeShortFile) 'Unicode F6 leaves original fixture intact'
        Assert-True (Test-Content $moved) 'Unicode F6 preserves moved content'
        $passed = $true
        Write-Host 'PASS: real Unicode F5 and F6 file transfer without ANSI narrowing.'
        return
    }

    if ($ShortUnicodeRenameOnly) {
        Send-Keys '{END}'
        Assert-True ((Read-FocusedFilename) -ceq $utfName) 'Unicode source filename selected for F2'
        Set-ClipboardText $renamedName
        Send-Keys '{F2}'
        Start-Sleep -Milliseconds 350
        Send-Keys '^a'
        Send-Keys '^v'
        Send-Keys '{ENTER}'
        $renamedPath = Join-Path $source $renamedName
        Wait-Until { [IO.File]::Exists($renamedPath) -and
            -not [IO.File]::Exists($unicodeShortFile) } 'UTF-16 F2 rename without ANSI narrowing'
        Assert-True (Test-Content $renamedPath) 'Unicode F2 renamed file preserves original bytes'
        $passed = $true
        Write-Host 'PASS: genuine Unicode F2 rename works without ANSI conversion or overwrite.'
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

            # The test must never send a destructive shortcut unless the
            # disposable source panel and a known Unicode row are active.
            Assert-True ((Read-PanelPath) -ceq $source) "Unicode source panel verified before $($operation.Name)"
            $focusedName = Read-FocusedFilename
            Assert-True (($focusedName -ceq $utfName) -or
                ($focusedName -ceq $utfCollisionName)) "Disposable Unicode row verified before $($operation.Name)"

            Send-Keys $operation.Key
            $blocked = @{ Dialog = '<none>' }
            Wait-Until {
                $blocked.Dialog = Get-TestDialog
                return $blocked.Dialog -match 'legacy ANSI file-operation engine'
            } "safe refusal dialog for $($operation.Name)"
            Write-Host "PASS: $($operation.Name) refused unsafe Unicode identity"
            Send-Keys '{ESC}'
            Wait-Until { -not (Get-TestDialog) } "dismissal of $($operation.Name) refusal dialog"
            # The shell may hand foreground focus back to PowerShell after a
            # modal dialog. Restore only the PID/HWND verified at startup.
            # Send-Keys must continue to refuse unowned foreground windows.
            Focus-TestProcess

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

        # The new W-backed per-row identity is allowed to export both
        # source names, but destructive legacy operations still fail closed.
        Send-Keys '{END}'
        $lastName = Read-FocusedFilename
        $lastPath = Read-FocusedFullname
        Send-Keys '{UP}'
        $previousName = Read-FocusedFilename
        $previousPath = Read-FocusedFullname
        $actualNames = @($lastName, $previousName) | Sort-Object
        $expectedNames = @($utfName, $utfCollisionName) | Sort-Object
        Assert-True (($actualNames -join [char]0) -ceq ($expectedNames -join [char]0)) 'Unicode aliases retain distinct per-row names'
        Assert-True (($lastPath -ceq (Join-Path $source $lastName)) -and
            ($previousPath -ceq (Join-Path $source $previousName))) 'Unicode aliases retain distinct full paths'
        Assert-True ((Test-Content $unicodeShortFile) -and
            [Linq.Enumerable]::SequenceEqual[byte](
                [IO.File]::ReadAllBytes($collisionFile), $collisionPayload
            )) 'Collision retained both original file contents'
        $passed = $true
        Write-Host 'PASS: Unicode ANSI alias collision preserves two independently addressable panel identities.'
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
        Assert-True ((Read-FocusedFullname) -ceq $unicodeShortFile) 'Short Unicode full path preserved in clipboard'
        Assert-True (Test-Content $unicodeShortFile) 'Unicode-only file bytes preserved'
        $passed = $true
        Write-Host 'PASS: Salamander GUI supports a Unicode name on a short path.'
        return
    }

    # ACT + ASSERT: a 255-character directory row from an ordinary short
    # panel must open normally. The Windows filesystem created both paths;
    # this test exercises the actual Enter navigation in Salamander instead
    # of jumping directly to the long absolute path through the clipboard.
    Go-ToPath $source
    Restore-FilePanelFocus -ExpectedPath $source
    Focus-DirectoryRow -Name $maxDirectoryName
    Send-Keys '{ENTER}'
    Wait-Until { (Read-PanelPath) -ceq $maxDirectoryPath } 'Enter 255-unit directory from a short panel'
    Assert-True (Test-Content (Join-Path $maxDirectoryPath 'max-directory-marker.bin')) '255-unit directory opened without losing file bytes'
    Send-Keys '{BACKSPACE}'
    Wait-Until { (Read-PanelPath) -ceq $source } 'Backspace from 255-unit directory to short parent'

    # ACT + ASSERT: entering Ordner-C crosses MAX_PATH, while Ordner-A/B
    # remain short. Continue with Ordner-D while the panel is already long.
    Go-ToPath $source
    Restore-FilePanelFocus -ExpectedPath $source
    for ($part = 0; $part -lt $boundaryDirectoryNames.Count; $part++) {
        Focus-DirectoryRow -Name $boundaryDirectoryNames[$part]
        Send-Keys '{ENTER}'
        $expectedDirectory = $boundaryDirectoryPaths[$part]
        Wait-Until { (Read-PanelPath) -ceq $expectedDirectory } "Enter nested directory component $($part + 1)"
        Write-Host "PASS: Enter navigated nested directory component $($part + 1)"
    }
    Assert-True (Test-Content (Join-Path $boundaryDirectoryPaths[-1] 'nested-directory-marker.bin')) 'Nested path crossing MAX_PATH preserves file bytes'

    # ACT + ASSERT: actual GUI long directory change and filename retrieval.
    Go-ToPath $deep
    Send-Keys '{END}'
    Assert-True ((Read-FocusedFilename) -ceq $utfName) 'Salamander panel preserves Unicode filename'

    # ACT + ASSERT: Entering a directory and navigating up from a long
    # panel must not copy the long panel path into fixed MAX_PATH buffers.
    Send-Keys '{HOME}'
    Send-Keys '{DOWN}'
    Assert-True ((Read-FocusedFilename) -ceq 'nested-child') 'Long-path child directory selected'
    # A focused filename copied by WM_COMMAND 710 does not prove that
    # SendKeys reached the file panel. Capture read-only focus information
    # and the last observed panel path; never retry Enter blindly.
    $focusBeforeEnter = [SalamanderGuiNative]::GetInputFocusSummary(
        $mainWindowHandle, [uint32]$process.Id)
    # Wait-Until invokes its condition with &, in a child PowerShell scope.
    # Store the observed path in a shared reference-type object, not in a
    # scalar local that would disappear when the polling scriptblock returns.
    $enterDiagnostics = @{
        PanelPath = '<not read>'
        PanelReadError = '<none>'
    }
    Send-Keys '{ENTER}'
    try {
        Wait-Until {
            $dialogText = Get-TestDialog
            if (-not [string]::IsNullOrEmpty($dialogText)) {
                throw "Salamander raised a dialog after Enter: $dialogText"
            }
            try {
                $enterDiagnostics.PanelPath = Read-PanelPath
                $enterDiagnostics.PanelReadError = '<none>'
            }
            catch {
                $enterDiagnostics.PanelReadError = $_.Exception.Message
                return $false
            }
            return $enterDiagnostics.PanelPath -ceq $nestedLongDirectory
        } 'Enter child directory from long panel'
    }
    catch {
        $failure = $_.Exception.Message
        $focusAfterEnter = [SalamanderGuiNative]::GetInputFocusSummary(
            $mainWindowHandle, [uint32]$process.Id)
        $dialogText = Get-TestDialog
        throw ("Long-path Enter navigation failed: {0}; last observed path='{1}'; " +
            "path read error='{2}'; focus before Enter=[{3}]; focus after Enter=[{4}]; " +
            "foreground={5}; dialog='{6}'; child directory exists={7}. " +
            "No additional Enter was sent." -f
            $failure, $enterDiagnostics.PanelPath, $enterDiagnostics.PanelReadError, $focusBeforeEnter,
            $focusAfterEnter, (Get-ForegroundWindowSummary), $dialogText,
            [IO.Directory]::Exists($nestedLongDirectory))
    }
    Assert-True ($enterDiagnostics.PanelPath -ceq $nestedLongDirectory) 'Long-path child directory opened'
    Send-Keys '{BACKSPACE}'
    Wait-Until { (Read-PanelPath) -ceq $deep } 'Backspace to long directory parent'
    Assert-True ((Read-PanelPath) -ceq $deep) 'Backspace restores long directory'
    Send-Keys '{BACKSPACE}'
    $shorterParent = Split-Path -Parent $deep
    Wait-Until { (Read-PanelPath) -ceq $shorterParent } 'Backspace to next parent of long directory'
    Assert-True ((Read-PanelPath) -ceq $shorterParent) 'Backspace navigates up from a long directory'
    Go-ToPath $deep
    Send-Keys '{END}'
    Assert-True ((Read-FocusedFilename) -ceq $utfName) 'Unicode file identity preserved after parent traversal'

    # The old ClipboardPastePath had a fixed 2*MAX_PATH temporary. Exercise
    # a genuine longer absolute path and then restore the Unicode source.
    Go-ToPath $beyondClipboardLimit
    Assert-True ((Read-PanelPath) -ceq $beyondClipboardLimit) 'GUI clipboard navigation accepts path beyond 2*MAX_PATH'
    Go-ToPath $deep
    Send-Keys '{END}'
    Assert-True ((Read-FocusedFilename) -ceq $utfName) 'Unicode identity survives >2*MAX_PATH clipboard traversal'

    # Test the same disposable fixture through an existing local SMB share.
    # Never create or alter a system share. Missing administrative shares
    # are explicitly reported as an untested integration, not as success.
    if ($deep -match '^[A-Za-z]:\\') {
        $drive = $deep.Substring(0, 1)
        $uncDeep = '\\localhost\' + $drive + [char]36 + $deep.Substring(2)
        $uncAvailable = $false
        try { $uncAvailable = [IO.Directory]::Exists($uncDeep) } catch { }
        if ($uncAvailable) {
            Go-ToPath $uncDeep
            Send-Keys '{END}'
            Assert-True ((Read-FocusedFilename) -ceq $utfName) 'SMB UNC long path preserves Unicode row'
            Go-ToPath $deep
            Assert-True ((Read-PanelPath) -ceq $deep) 'UNC to drive long-path navigation restores source'
        }
        else {
            Write-Host 'SKIP: local administrative SMB share inaccessible; UNC GUI integration unverified.'
        }
    }

    # ACT + ASSERT: switching away from a long source panel must preserve
    # the process and both panel paths. This regressed when UpdateDefaultDir
    # copied the inactive 411-unit path into a fixed MAX_PATH buffer.
    Send-Keys '{TAB}'
    Assert-True ((Read-PanelPath) -cne $deep) 'TAB switches away from long path without terminating Salamander'
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

    # ACT + ASSERT: an F6 directory move from a long source path uses
    # one W-backed same-volume move, not the legacy recursive ANSI engine.
    # Both panel destinations are explicitly verified before touching data.
    Go-ToPath $destination
    Send-Keys '{TAB}'
    Go-ToPath $deep
    Assert-True ((Read-PanelPath) -ceq $deep) 'Long directory panel active before tree move'
    Send-Keys '{HOME}'
    Send-Keys '{DOWN}'
    Send-Keys '{DOWN}'
    Assert-True ((Read-FocusedFilename) -ceq $treeMoveName) 'Disposable source tree selected for F6'
    Send-Keys '{F6}'
    # Confirm the exact action before sending Enter. Otherwise an early
    # refusal may be dismissed unnoticed and reported only as a timeout.
    Wait-Until {
        $dialog = Get-TestDialog
        $expectedPrompt = 'Move this directory and its entire contents within the same volume'
        if (-not [string]::IsNullOrEmpty($dialog) -and
            $dialog -notmatch [regex]::Escape($expectedPrompt)) {
            throw "F6 directory move refused before confirmation: $dialog"
        }
        return $dialog -match [regex]::Escape($expectedPrompt)
    } 'F6 directory move confirmation'
    Write-Host 'PASS: F6 opened native Unicode directory move confirmation'
    Send-Keys '{ENTER}'
    $treeMoveTarget = Join-Path $destination $treeMoveName
    $treeTargetLeaf = Join-Path (Join-Path $treeMoveTarget 'nested') 'payload.bin'
    try {
        Wait-Until {
            $dialog = Get-TestDialog
            if (-not [string]::IsNullOrEmpty($dialog)) {
                throw "F6 directory move displayed a modal error: $dialog"
            }
            return (Test-Content $treeTargetLeaf) -and
                   -not [IO.Directory]::Exists($treeMoveSource)
        } 'F6 atomic nested tree move'
    }
    catch {
        $cause = $_.Exception.Message
        $sourceExists = [IO.Directory]::Exists($treeMoveSource)
        $targetExists = [IO.Directory]::Exists($treeMoveTarget)
        $leafExists = [IO.File]::Exists($treeTargetLeaf)
        $dialog = Get-TestDialog
        $windowSummary = Get-ProcessWindowSummary -OwnerProcessId ([uint32]$process.Id)
        $failureFormat = "F6 directory move failed: {0}; sourceExists={1}; targetExists={2}; " +
                         "targetLeafExists={3}; dialog='{4}'; Salamander windows={5}"
        throw ($failureFormat -f $cause, $sourceExists, $targetExists,
               $leafExists, $dialog, $windowSummary)
    }
    Assert-True ((Test-Content $treeTargetLeaf) -and
                 -not [IO.Directory]::Exists($treeMoveSource)) 'F6 directory move retains nested file bytes'

    # ACT + ASSERT: copying a normal short-path file INTO a long directory
    # must also avoid the ANSI engine. Only the disposable fixture is used.
    $shortSourceName = 'short-to-long.txt'
    $shortSourceFile = Join-Path $destination $shortSourceName
    [IO.File]::WriteAllBytes($shortSourceFile, $payload)
    Send-Keys '{TAB}'
    Go-ToPath $destination
    Assert-True ((Read-PanelPath) -ceq $destination) 'Short source active before F5 to long target'
    Send-Keys '{END}'
    Assert-True ((Read-FocusedFilename) -ceq $shortSourceName) 'Short source file selected for long target'
    Send-Keys '{F5}'
    Start-Sleep -Milliseconds 400
    Send-Keys '{ENTER}'
    $longTargetFile = Join-Path $deep $shortSourceName
    Wait-Until { Test-Content $longTargetFile } 'F5 short source into long target'
    Assert-True ((Test-Content $longTargetFile) -and (Test-Content $shortSourceFile)) 'F5 short-to-long bytes intact at both paths'

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
            $process.Refresh()
            if (-not $process.HasExited) {
                # CloseMainWindow invokes Salamander's SaveConfig, persisting
                # paths into the soon-to-be-deleted disposable fixture and
                # overwriting the user's saved panel paths. The process belongs
                # exclusively to this test; terminate it without invoking that
                # normal configuration-save path.
                $process.Kill()
                if (-not $process.WaitForExit(4000)) {
                    Write-Warning "Test Salamander PID $($process.Id) did not exit after termination."
                }
            }
        }
        catch { Write-Warning "Could not stop isolated test app: $($_.Exception.Message)" }
        $process.Dispose()
    }

    # A failed search may retain its screenshot and small fixtures, but it
    # must not leave a large cancellation stress file on the user's disk.
    # This deletion is limited to the exact GUID-scoped test fixture.
    if ($UnicodeFindOnly -and
        -not [string]::IsNullOrEmpty($script:findCancelProbePath)) {
        $expectedProbe = Join-Path $findRoot 'cancel-probe.bin'
        if ($script:findCancelProbePath -ceq $expectedProbe -and
            $expectedProbe.StartsWith(
                $root + [IO.Path]::DirectorySeparatorChar,
                [StringComparison]::OrdinalIgnoreCase)) {
            try { [IO.File]::Delete($expectedProbe) }
            catch { Write-Warning "Could not clean large Find cancellation fixture: $($_.Exception.Message)" }
        }
    }
    if ($oldClipboard) {
        try { [Windows.Forms.Clipboard]::SetDataObject($oldClipboard, $true) }
        catch { Write-Warning 'Original clipboard could not be restored.' }
    }
    if ($null -ne $script:clipboardOwner) {
        try { $script:clipboardOwner.Dispose() }
        catch { Write-Warning "Clipboard owner shutdown failed: $($_.Exception.Message)" }
    }
    # A failed F8 regression must not leave another GUID-owned temp tree.
    if (($passed -or $TemporaryDirectoryDeletionOnly) -and -not $KeepFixture) {
        try { [IO.Directory]::Delete($root, $true) }
        catch { Write-Warning "Test fixture cleanup failed: $root - $($_.Exception.Message)" }
    }
    else {
        Write-Host "Diagnostic fixture retained: $root"
    }
}
