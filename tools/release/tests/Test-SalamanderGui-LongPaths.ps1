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
    [ValidateRange(5,120)][int]$StartupReadyTimeoutSeconds = 90,
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
    [switch]$UnicodeFindOnly,
    [ValidateSet('Baseline','Cancel','AdvancedInputs','ViewResults','ViewUnicode','ViewLong','ViewStale','ViewMixed','FocusUnicode','FocusLong','FocusStale','ShellClipboard','ShellOpen','ShellProperties','ExternalEditor','RecycleRestore',
        'EncryptedFixture','UnicodeName','UnicodeResult',
        'UnicodeDistinct','UnicodeMasks','UnicodeFeatures','UnicodeSettings','UnicodeSettingsStorage','UnicodeRoot','UnicodeRootIgnore','LongRoot','LongDescendant','LongResult',
        'ExtendedLongRoot','LongDuplicates','DirectoryLinkCycle',
        'NearLimit','DefaultDialog','DefaultDialogShortcut','DefaultDialogLongRoot','DefaultDialogAltF7',
        'UnicodeFindCommand','UnicodeFindShortcut')]
    [string]$LegacyFindScenario,
    [string]$LegacyFindEncryptedFixture,
    [switch]$LargeUnicodeCopyOnly,
    [ValidateSet('Copy','Cancel','Collision','LockedSource')][string]$LargeUnicodeCopyCase = 'Copy',
    [switch]$UnicodeParentDirectories,
    [switch]$IsolatedConfiguration
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
if ($LegacyFindScenario -and -not $IsolatedConfiguration) {
    throw 'Legacy Find GUI tests require -IsolatedConfiguration.'
}
if (($LegacyFindScenario -eq 'EncryptedFixture') -ne [bool]$LegacyFindEncryptedFixture) {
    throw 'EncryptedFixture requires -LegacyFindEncryptedFixture with an existing disposable EFS file.'
}
$testConfigurationId = $null
$testConfigurationKey = $null
if ($IsolatedConfiguration) {
    $binaryText = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($SalamanderExe))
    if (-not $binaryText.Contains('OpenSalamander-IsolatedGUI-Config-v1')) {
        throw 'Isolated configuration requires an OPENSAL_ENABLE_ISOLATED_TEST_CONFIG build.'
    }
    $testConfigurationId = [guid]::NewGuid().ToString('N')
    $testConfigurationKey = 'Software\Open Salamander\CodexTests\' + $testConfigurationId
    $existingTestKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($testConfigurationKey)
    if ($null -ne $existingTestKey) {
        $existingTestKey.Dispose()
        throw 'Refusing to reuse an existing test configuration namespace.'
    }
}
if ($VerifyRecycleRestore -and -not $ShortUnicodeRecycleOnly) {
    throw '-VerifyRecycleRestore requires -ShortUnicodeRecycleOnly.'
}
if ($UnicodeParentDirectories -and -not $LargeUnicodeCopyOnly) {
    throw '-UnicodeParentDirectories requires -LargeUnicodeCopyOnly.'
}
if ($LargeUnicodeCopyOnly -and -not $IsolatedConfiguration) {
    throw 'Large Unicode copy acceptance requires the isolated instrumented test build.'
}
if ($LargeUnicodeCopyCase -ne 'Copy' -and -not $LargeUnicodeCopyOnly) {
    throw '-LargeUnicodeCopyCase requires -LargeUnicodeCopyOnly.'
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
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint RegisterClipboardFormat(string name);
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
        if (String.IsNullOrEmpty(value) || value.IndexOf('\0') >= 0)
            throw new ArgumentException("Expected nonempty UTF-16 text without embedded nulls.", "value");
        char[] characters = (value + "\0").ToCharArray();
        byte[] bytes = new byte[checked(characters.Length * sizeof(char))];
        Buffer.BlockCopy(characters, 0, bytes, 0, bytes.Length);
        SetClipboardBytes(owner, 13, bytes); // CF_UNICODETEXT
    }

    public static void SetClipboardFileDrop(IntPtr owner, string path, bool cut)
    {
        if (String.IsNullOrEmpty(path) || path.IndexOf('\0') >= 0)
            throw new ArgumentException("Expected a nonempty file path.", "path");
        const int headerSize = 20;
        byte[] names = Encoding.Unicode.GetBytes(path + "\0\0");
        byte[] bytes = new byte[headerSize + names.Length];
        bytes[0] = headerSize; // DROPFILES.pFiles
        bytes[16] = 1; // DROPFILES.fWide
        Buffer.BlockCopy(names, 0, bytes, headerSize, names.Length);
        SetClipboardBytes(owner, 15, bytes, cut); // CF_HDROP
    }

    private static void SetClipboardBytes(IntPtr owner, uint format, byte[] bytes, bool cut = false)
    {
        if (owner == IntPtr.Zero) throw new ArgumentException("Owner HWND is required.", "owner");
        IntPtr memory = GlobalAlloc(0x0002, new UIntPtr((uint)bytes.Length)); // GMEM_MOVEABLE
        if (memory == IntPtr.Zero) throw new InvalidOperationException("GlobalAlloc failed for clipboard data.");
        bool clipboardOpened = false;
        bool transferred = false;
        try
        {
            IntPtr destination = GlobalLock(memory);
            if (destination == IntPtr.Zero)
                throw new InvalidOperationException("GlobalLock failed for clipboard data.");
            try { Marshal.Copy(bytes, 0, destination, bytes.Length); }
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
            if (SetClipboardData(format, memory) == IntPtr.Zero)
                throw new InvalidOperationException("SetClipboardData failed for format " + format + ": " + Marshal.GetLastWin32Error());
            transferred = true; // Windows owns the HGLOBAL now.
            if (cut)
                SetClipboardCutEffect();
        }
        finally
        {
            if (clipboardOpened) CloseClipboard();
            if (!transferred) GlobalFree(memory);
        }
    }

    private static void SetClipboardCutEffect()
    {
        uint format = RegisterClipboardFormat("Preferred DropEffect");
        if (format == 0)
            throw new InvalidOperationException("RegisterClipboardFormat failed for cut effect.");
        IntPtr memory = GlobalAlloc(0x0002, new UIntPtr(sizeof(uint)));
        if (memory == IntPtr.Zero)
            throw new InvalidOperationException("GlobalAlloc failed for cut effect.");
        bool transferred = false;
        try
        {
            IntPtr address = GlobalLock(memory);
            if (address == IntPtr.Zero)
                throw new InvalidOperationException("GlobalLock failed for cut effect.");
            try { Marshal.WriteInt32(address, 2); } // DROPEFFECT_MOVE
            finally { GlobalUnlock(memory); }
            if (SetClipboardData(format, memory) == IntPtr.Zero)
                throw new InvalidOperationException("SetClipboardData failed for cut effect.");
            transferred = true;
        }
        finally
        {
            if (!transferred) GlobalFree(memory);
        }
    }

    // SendMessageTimeoutW may fail without updating LastError. Clear it first
    // so the captured status cannot be inherited from another P/Invoke.
    [DllImport("kernel32.dll", ExactSpelling = true)]
    public static extern void SetLastError(uint errorCode);
    [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW", SetLastError = true)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint msg, UIntPtr wParam, IntPtr lParam,
        uint flags, uint timeoutMilliseconds, out IntPtr result);

    // Opt-in diagnostic only. MiniDumpNormal includes native thread stacks and
    // loaded modules but avoids full process memory. The caller is a separate
    // test process, not the application being inspected.
    [DllImport("dbghelp.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool MiniDumpWriteDump(
        IntPtr processHandle, uint processId,
        Microsoft.Win32.SafeHandles.SafeFileHandle fileHandle,
        uint dumpType, IntPtr exceptionInfo, IntPtr userStreamInfo,
        IntPtr callbackInfo);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowTextW(IntPtr window, StringBuilder buffer, int capacity);
    [DllImport("user32.dll")]
    public static extern IntPtr GetLastActivePopup(IntPtr window);
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")]
    public static extern bool IsWindowEnabled(IntPtr window);
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

    // Salamander's CMainWindow::Create initially uses an EMPTY caption and
    // sets the title only after configuration initialization. Identify only
    // its registered class, never an arbitrary visible window of the PID.
    public static IntPtr FindMainWindow(uint processId)
    {
        IntPtr found = IntPtr.Zero;
        foreach (TopLevelWindow window in GetProcessWindows(processId))
        {
            if (!window.Visible ||
                ClassName(window.Handle) != "SalamanderMainWindowVer25")
                continue;
            if (found != IntPtr.Zero)
                throw new InvalidOperationException(
                    "Multiple visible Salamander main windows owned by the test process");
            found = window.Handle;
        }
        return found;
    }

    public static string GetWindowCaption(IntPtr window)
    {
        StringBuilder caption = new StringBuilder(512);
        GetWindowTextW(window, caption, caption.Capacity);
        return caption.ToString();
    }

    public static bool MatchesDialogTitle(string title, string expected)
    {
        return title == expected || title == "[#] " + expected + " [#]";
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

    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr window);
    [DllImport("user32.dll")] private static extern bool BringWindowToTop(IntPtr window);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool AttachThreadInput(uint threadId, uint attachToId, bool attach);
    [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] private static extern short GetKeyState(int virtualKey);

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

    // Find precisely one native MessageBoxW confirmation created by the
    // guarded UTF-16 directory delete path. Windows may raise unrelated
    // foreground overlays after the F8 keystroke.
    public static IntPtr FindUnicodeDirectoryDeleteDialog(uint processId)
    {
        IntPtr result = IntPtr.Zero;
        foreach (TopLevelWindow window in GetProcessWindows(processId))
        {
            if (!window.Visible ||
                ClassName(window.Handle) != "#32770" ||
                window.Title != "Unicode directory deletion")
                continue;
            if (result != IntPtr.Zero)
                throw new InvalidOperationException(
                    "Multiple Unicode directory deletion dialogs owned by test process");
            result = window.Handle;
        }
        return result;
    }

    // Dispatch exactly one consent message to a verified dialog. Do not
    // assume that the foreground HWND is a Salamander modal dialog.
    public static void PostVerifiedDirectoryDeleteConfirmation(IntPtr dialog, uint processId)
    {
        if (dialog == IntPtr.Zero || processId == 0 || !IsWindowVisible(dialog))
            throw new InvalidOperationException("Directory deletion dialog is not visible");
        uint actualPid;
        if (GetWindowThreadProcessId(dialog, out actualPid) == 0 ||
            actualPid != processId || ClassName(dialog) != "#32770" ||
            GetWindowCaption(dialog) != "Unicode directory deletion")
            throw new InvalidOperationException("Directory deletion dialog identity changed");
        IntPtr button = GetDlgItem(dialog, 1); // IDOK
        if (button == IntPtr.Zero || !IsWindowVisible(button))
            throw new InvalidOperationException("Directory delete OK button unavailable");
        uint buttonPid;
        if (GetWindowThreadProcessId(button, out buttonPid) == 0 ||
            buttonPid != processId)
            throw new InvalidOperationException("Directory delete OK button belongs to another PID");
        // WM_COMMAND / IDOK / BN_CLICKED, with verified button HWND.
        if (!PostMessageW(dialog, 0x0111, new UIntPtr(1), button))
            throw new InvalidOperationException(
                "Failed to post directory delete confirmation: " +
                Marshal.GetLastWin32Error());
    }

    // Foreground-independent integration path for the directory-delete
    // regression. It uses the same CM_DELETEFILES handler as F8, but not the
    // physical F8 accelerator, which needs a separate isolated desktop test.
    public static void PostVerifiedDirectoryDeleteCommand(IntPtr mainWindow, uint processId)
    {
        uint ownerPid;
        if (mainWindow == IntPtr.Zero || processId == 0 ||
            GetWindowThreadProcessId(mainWindow, out ownerPid) == 0 ||
            ownerPid != processId || !IsWindowVisible(mainWindow) ||
            !IsWindowEnabled(mainWindow) ||
            ClassName(mainWindow) != "SalamanderMainWindowVer25")
            throw new InvalidOperationException("Refusing delete command for unverified main window");
        // Salamander uses GetKeyState(VK_SHIFT) to invert Recycle Bin policy.
        // Reject a held modifier rather than silently changing delete mode.
        if ((GetKeyState(0x10) & 0x8000) != 0 ||
            (GetKeyState(0x11) & 0x8000) != 0 ||
            (GetKeyState(0x12) & 0x8000) != 0)
            throw new InvalidOperationException("Modifier key held; refusing deletion");
        // Never SendMessage synchronously: the handler shows a modal prompt.
        if (!PostMessageW(mainWindow, 0x0111, new UIntPtr(729), IntPtr.Zero))
            throw new InvalidOperationException(
                "Could not post CM_DELETEFILES: " + Marshal.GetLastWin32Error());
    }

    // Same command handler as F5. Window-bound dispatch cannot type into an
    // unrelated foreground app; the caller verifies the exact source first.
    public static void PostVerifiedLargeCopyCommand(IntPtr mainWindow, uint processId)
    {
        uint ownerPid;
        if (mainWindow == IntPtr.Zero || processId == 0 ||
            GetWindowThreadProcessId(mainWindow, out ownerPid) == 0 || ownerPid != processId ||
            !IsWindowVisible(mainWindow) || !IsWindowEnabled(mainWindow) ||
            ClassName(mainWindow) != "SalamanderMainWindowVer25")
            throw new InvalidOperationException("Refusing copy for unverified main window");
        if ((GetKeyState(0x10) & 0x8000) != 0 || (GetKeyState(0x11) & 0x8000) != 0 ||
            (GetKeyState(0x12) & 0x8000) != 0)
            throw new InvalidOperationException("Modifier key held; refusing copy");
        if (!PostMessageW(mainWindow, 0x0111, new UIntPtr(727), IntPtr.Zero)) // CM_COPYFILES
            throw new InvalidOperationException("Could not post CM_COPYFILES: " + Marshal.GetLastWin32Error());
    }

    // MessageBoxW is owned by CFilesWindow::HWindow (a panel child), not
    // necessarily by the enabled main HWND. Get-TestDialog cannot reliably
    // identify this particular modal window.
    private static bool IsOwnedLargeCopyDialog(IntPtr dialog, IntPtr mainWindow)
    {
        IntPtr owner = GetWindow(dialog, 4); // GW_OWNER
        return owner == mainWindow ||
               (owner != IntPtr.Zero && GetAncestor(owner, 2) == mainWindow) ||
               GetAncestor(dialog, 3) == mainWindow; // GA_ROOTOWNER
    }

    public static IntPtr FindVerifiedLargeCopyConfirmation(
        IntPtr mainWindow, uint processId, string expectedName,
        string expectedTargetDirectory)
    {
        if (mainWindow == IntPtr.Zero || processId == 0 ||
            String.IsNullOrEmpty(expectedName) ||
            String.IsNullOrEmpty(expectedTargetDirectory))
            throw new InvalidOperationException("Large copy confirmation identity is missing");
        uint mainPid;
        if (GetWindowThreadProcessId(mainWindow, out mainPid) == 0 ||
            mainPid != processId ||
            ClassName(mainWindow) != "SalamanderMainWindowVer25")
            throw new InvalidOperationException("Unverified main window for Unicode copy");

        IntPtr found = IntPtr.Zero;
        foreach (TopLevelWindow window in GetProcessWindows(processId))
        {
            if (!window.Visible || ClassName(window.Handle) != "#32770" ||
                window.Title != "Unicode copy" ||
                !IsOwnedLargeCopyDialog(window.Handle, mainWindow))
                continue;

            bool matchingPrompt = false;
            WindowCallback callback = (child, ignored) =>
            {
                uint childPid;
                if (GetWindowThreadProcessId(child, out childPid) == 0 ||
                    childPid != processId || ClassName(child) != "Static")
                    return true;

                // GetWindowTextW cannot read a foreign process's child
                // control. WM_GETTEXT is system-marshalled across processes;
                // keep it bounded even if the native UI has stopped pumping.
                StringBuilder text = new StringBuilder(4096);
                IntPtr result;
                if (SendMessageTimeoutReadText(
                        child, 0x000D, new UIntPtr(4096),
                        text, 0x0002, 1000, out result) == IntPtr.Zero)
                    return true;
                string message = text.ToString();
                if (message.StartsWith(
                        "Copy the Unicode file to the other panel?",
                        StringComparison.Ordinal) &&
                    message.Contains(expectedName, StringComparison.Ordinal) &&
                    message.Contains("Destination: " + expectedTargetDirectory,
                                     StringComparison.Ordinal) &&
                    message.Contains("The existing background copy worker will be used.",
                                     StringComparison.Ordinal))
                    matchingPrompt = true;
                return true;
            };
            if (!EnumChildWindows(window.Handle, callback, IntPtr.Zero))
                throw new InvalidOperationException("Cannot enumerate Unicode copy dialog controls");
            if (!matchingPrompt) continue;

            if (found != IntPtr.Zero)
                throw new InvalidOperationException("Multiple verified Unicode copy confirmations");
            found = window.Handle;
        }
        return found;
    }

    public static void ConfirmVerifiedLargeCopy(
        IntPtr mainWindow, uint processId, IntPtr dialog,
        string expectedName, string expectedTargetDirectory)
    {
        if (dialog == IntPtr.Zero ||
            FindVerifiedLargeCopyConfirmation(
                mainWindow, processId, expectedName, expectedTargetDirectory) != dialog)
            throw new InvalidOperationException("Unicode copy confirmation changed before OK");
        PostOwnedCopyDialogButton(dialog, processId, 1); // IDOK of verified dialog
    }

    public static bool MatchesRequestedCopyDialogText(string actual, string requested)
    {
        return string.IsNullOrEmpty(requested) || actual == requested;
    }

    public static IntPtr FindOwnedDialogControl(uint processId, int controlId, string text)
    {
        IntPtr found = IntPtr.Zero;
        foreach (TopLevelWindow window in GetProcessWindows(processId))
        {
            if (!window.Visible || ClassName(window.Handle) != "#32770") continue;
            IntPtr control = GetDlgItem(window.Handle, controlId);
            // PowerShell converts $null to String.Empty for a string argument.
            // Both mean "identify by ID"; path assertions pass a nonempty value.
            if (control == IntPtr.Zero || !MatchesRequestedCopyDialogText(GetWindowCaption(control), text)) continue;
            if (found != IntPtr.Zero) throw new InvalidOperationException("Multiple matching owned dialogs");
            found = window.Handle;
        }
        return found;
    }

    [DllImport("user32.dll")]
    private static extern IntPtr GetAncestor(IntPtr window, uint flags);
    [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW",
               CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr SendMessageTimeoutReadText(
        IntPtr window, uint message, UIntPtr length, StringBuilder buffer,
        uint flags, uint timeoutMilliseconds, out IntPtr result);
    [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW",
               CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr SendMessageTimeoutWriteText(
        IntPtr window, uint message, UIntPtr unused, string text,
        uint flags, uint timeoutMilliseconds, out IntPtr result);

    public static bool HasVerifiedStaticText(IntPtr dialog, uint processId, string expected)
    {
        uint dialogPid;
        if (GetWindowThreadProcessId(dialog, out dialogPid) == 0 || dialogPid != processId)
            return false;
        bool matched = false;
        WindowCallback callback = (child, ignored) =>
        {
            uint childPid;
            if (ClassName(child) != "Static" ||
                GetWindowThreadProcessId(child, out childPid) == 0 || childPid != processId)
                return true;
            StringBuilder text = new StringBuilder(512);
            IntPtr result;
            if (SendMessageTimeoutReadText(child, 0x000D, new UIntPtr(512),
                    text, 0x0002, 1000, out result) != IntPtr.Zero &&
                text.ToString() == expected)
                matched = true;
            return true;
        };
        EnumChildWindows(dialog, callback, IntPtr.Zero);
        return matched;
    }

    private static string ReadQuickRenameText(IntPtr control)
    {
        StringBuilder text = new StringBuilder(260);
        IntPtr result;
        if (SendMessageTimeoutReadText(control, 0x000D, new UIntPtr(260),
                                       text, 0x0002, 5000, out result) == IntPtr.Zero)
            throw new InvalidOperationException(
                "Quick Rename WM_GETTEXT did not complete: " + Marshal.GetLastWin32Error());
        return text.ToString();
    }

    // F2 uses the existing CCopyMoveDialog (not the separate inline rename
    // edit). Its ComboBox IDE_PATH=210 and subject IDS_SUBJECT=209 must both
    // belong to the single visible modal dialog owned by our verified main.
    public static IntPtr FindVerifiedQuickRenameDialog(
        IntPtr mainWindow, uint processId, string expectedName)
    {
        uint mainPid;
        if (mainWindow == IntPtr.Zero || processId == 0 ||
            String.IsNullOrEmpty(expectedName) ||
            GetWindowThreadProcessId(mainWindow, out mainPid) == 0 ||
            mainPid != processId ||
            ClassName(mainWindow) != "SalamanderMainWindowVer25")
            throw new InvalidOperationException("Unverified Quick Rename main window");

        IntPtr found = IntPtr.Zero;
        foreach (TopLevelWindow window in GetProcessWindows(processId))
        {
            if (!window.Visible || ClassName(window.Handle) != "#32770" ||
                !MatchesDialogTitle(window.Title, "Quick Rename"))
                continue;
            IntPtr owner = GetWindow(window.Handle, 4); // GW_OWNER
            if (owner == IntPtr.Zero ||
                (owner != mainWindow && GetAncestor(owner, 2) != mainWindow))
                continue;

            IntPtr edit = GetDlgItem(window.Handle, 210); // IDE_PATH
            IntPtr subject = VerifiedChild(window.Handle, processId, 209); // IDS_SUBJECT
            IntPtr ok = GetDlgItem(window.Handle, 1); // IDOK
            if (edit == IntPtr.Zero || subject == IntPtr.Zero ||
                ok == IntPtr.Zero || ClassName(edit) != "ComboBox" ||
                ClassName(ok) != "Button")
                throw new InvalidOperationException("Malformed owned Quick Rename dialog");
            if (ReadQuickRenameText(subject).IndexOf(
                    expectedName, StringComparison.Ordinal) < 0)
                continue;
            if (found != IntPtr.Zero)
                throw new InvalidOperationException("Ambiguous owned Quick Rename dialog");
            found = window.Handle;
        }
        return found;
    }

    public static void ConfirmVerifiedQuickRename(
        IntPtr mainWindow, uint processId, IntPtr dialog,
        string expectedName, string newName)
    {
        if (String.IsNullOrEmpty(newName) || newName.Length >= 260 ||
            newName.IndexOf('\0') >= 0 ||
            FindVerifiedQuickRenameDialog(mainWindow, processId, expectedName) != dialog ||
            dialog == IntPtr.Zero)
            throw new InvalidOperationException("Refusing unverified Quick Rename edit");

        IntPtr edit = VerifiedChild(dialog, processId, 210);
        if (ReadQuickRenameText(edit) != expectedName)
            throw new InvalidOperationException("Quick Rename original filename changed");

        IntPtr result;
        if (SendMessageTimeoutWriteText(edit, 0x000C, UIntPtr.Zero,
                                         newName, 0x0002, 5000, out result) == IntPtr.Zero ||
            result == IntPtr.Zero ||
            ReadQuickRenameText(edit) != newName)
            throw new InvalidOperationException("Quick Rename text was not accepted");

        // Never send a global Enter: the dialog may have lost foreground to
        // another process. Revalidate the exact owned OK button before posting.
        IntPtr ok = VerifiedChild(dialog, processId, 1);
        if (ClassName(ok) != "Button" || !IsWindowVisible(ok) ||
            !IsWindowEnabled(ok) ||
            FindVerifiedQuickRenameDialog(mainWindow, processId, expectedName) != dialog)
            throw new InvalidOperationException("Quick Rename confirmation is not safe");
        if (!PostMessageW(dialog, 0x0111, new UIntPtr(1), ok)) // WM_COMMAND / IDOK
            throw new InvalidOperationException(
                "Could not confirm owned Quick Rename: " + Marshal.GetLastWin32Error());
    }

    public static string OwnedControlText(IntPtr dialog, uint processId, int controlId)
    {
        return GetWindowCaption(VerifiedChild(dialog, processId, controlId));
    }

    public static bool OwnedControlEnabled(IntPtr dialog, uint processId, int controlId)
    {
        return IsWindowEnabled(VerifiedChild(dialog, processId, controlId));
    }

    public static bool IsOwnedModalOf(IntPtr dialog, IntPtr owner)
    {
        return GetWindow(dialog, 4) == owner;
    }

    public static void PostOwnedCopyDialogButton(IntPtr dialog, uint processId, int id)
    {
        if (id != 1 && id != 2 && id != 6 && id != 158 && id != 2480)
            throw new ArgumentOutOfRangeException("id");
        uint actualPid;
        if (GetWindowThreadProcessId(dialog, out actualPid) == 0 || actualPid != processId ||
            ClassName(dialog) != "#32770" || !IsWindowVisible(dialog))
            throw new InvalidOperationException("Unverified copy dialog");
        IntPtr button = VerifiedChild(dialog, processId, id);
        if (ClassName(button) != "Button" || !IsWindowVisible(button) || !IsWindowEnabled(button))
            throw new InvalidOperationException("Copy dialog button is not available");
        if (!PostMessageW(dialog, 0x0111, new UIntPtr((uint)id), button))
            throw new InvalidOperationException("Could not post owned copy dialog button");
    }

    // The isolated test starts with '-p 2': right panel is active, and both
    // panels have the same fixture root. Direct list messages cannot hit an
    // unrelated foreground window. Caller MUST verify exact selected name
    // and parent path before posting any destructive command.
    public static void SendVerifiedFileListKey(IntPtr mainWindow, uint processId, uint virtualKey)
    {
        if (virtualKey != 0x24 && virtualKey != 0x28) // HOME / DOWN only
            throw new ArgumentOutOfRangeException("virtualKey");
        uint ownerPid;
        if (mainWindow == IntPtr.Zero || processId == 0 ||
            GetWindowThreadProcessId(mainWindow, out ownerPid) == 0 ||
            ownerPid != processId || !IsWindowEnabled(mainWindow) ||
            ClassName(mainWindow) != "SalamanderMainWindowVer25")
            throw new InvalidOperationException("Main window identity or enabled state invalid");

        List<IntPtr> lists = new List<IntPtr>();
        WindowCallback callback = (child, context) =>
        {
            uint childPid;
            if (GetDlgCtrlID(child) == 950 &&
                ClassName(child) == "SalamanderItemsBox" &&
                IsWindowVisible(child) &&
                GetWindowThreadProcessId(child, out childPid) != 0 &&
                childPid == processId)
                lists.Add(child);
            return true;
        };
        EnumChildWindows(mainWindow, callback, IntPtr.Zero);
        if (lists.Count != 2)
            throw new InvalidOperationException(
                "Expected exactly two owned visible SalamanderItemsBox controls");
        GuiRect a, b;
        if (!GetWindowRect(lists[0], out a) ||
            !GetWindowRect(lists[1], out b) ||
            (a.Left == b.Left && a.Top == b.Top))
            throw new InvalidOperationException("Cannot distinguish right active file panel");
        IntPtr list = (a.Left > b.Left || (a.Left == b.Left && a.Top > b.Top))
            ? lists[0] : lists[1];

        // Refuse modified selection while the user presses Shift/Ctrl/Alt.
        if ((GetKeyState(0x10) & 0x8000) != 0 ||
            (GetKeyState(0x11) & 0x8000) != 0 ||
            (GetKeyState(0x12) & 0x8000) != 0)
            throw new InvalidOperationException("Modifier key held; refusing list input");

        IntPtr ignored;
        if (SendMessageTimeout(list, 0x0100, new UIntPtr(virtualKey),
                               new IntPtr(1), 2, 5000, out ignored) == IntPtr.Zero)
            throw new InvalidOperationException(
                "Verified file list WM_KEYDOWN failed: " + Marshal.GetLastWin32Error());
        if (SendMessageTimeout(list, 0x0101, new UIntPtr(virtualKey),
                               new IntPtr(unchecked((int)0xC0000001u)), 2, 5000, out ignored) == IntPtr.Zero)
            throw new InvalidOperationException(
                "Verified file list WM_KEYUP failed: " + Marshal.GetLastWin32Error());
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

    public static IntPtr FindLegacySearchWindow(uint pid)
    {
        IntPtr found = IntPtr.Zero;
        foreach (TopLevelWindow window in GetProcessWindows(pid))
        {
            if (!window.Visible || ClassName(window.Handle) != "#32770" ||
                ClassName(GetDlgItem(window.Handle, 2501)) != "ComboBox" ||
                ClassName(GetDlgItem(window.Handle, 2510)) != "SysListView32")
                continue;
            if (found != IntPtr.Zero)
                throw new InvalidOperationException("Multiple original Find dialogs");
            found = window.Handle;
        }
        return found;
    }

    public static IntPtr FindLegacyModal(IntPtr owner, uint pid, string title)
    {
        IntPtr found = IntPtr.Zero;
        foreach (TopLevelWindow window in GetProcessWindows(pid))
        {
            if (!window.Visible || ClassName(window.Handle) != "#32770" ||
                GetWindow(window.Handle, 4) != owner ||
                !MatchesDialogTitle(window.Title, title))
                continue;
            if (found != IntPtr.Zero)
                throw new InvalidOperationException("Multiple owned Find dialogs named " + title);
            found = window.Handle;
        }
        return found;
    }

    public static IntPtr FindLegacyResultViewer(uint pid, string expectedPath)
    {
        IntPtr found = IntPtr.Zero;
        string prefix = expectedPath + " - ";
        foreach (TopLevelWindow window in GetProcessWindows(pid))
        {
            string className = ClassName(window.Handle);
            if (!window.Visible || (className != "Salamander's Viewer Window" &&
                                    className != "Salamander's Unicode Viewer Window") ||
                (!window.Title.StartsWith(prefix, StringComparison.Ordinal) &&
                 !window.Title.StartsWith("[#] " + prefix, StringComparison.Ordinal)))
                continue;
            if (found != IntPtr.Zero)
                throw new InvalidOperationException("Multiple viewers for the same Find result");
            found = window.Handle;
        }
        return found;
    }

    public static IntPtr FindLegacyShellProperties(uint pid, string fixtureName)
    {
        IntPtr found = IntPtr.Zero;
        foreach (TopLevelWindow window in GetProcessWindows(pid))
        {
            if (!window.Visible || ClassName(window.Handle) != "#32770" ||
                !window.Title.Contains(fixtureName))
                continue;
            if (found != IntPtr.Zero)
                throw new InvalidOperationException("Multiple test-owned property windows for " + fixtureName);
            found = window.Handle;
        }
        return found;
    }

    public static void CloseLegacyShellProperties(IntPtr window, uint pid, string fixtureName)
    {
        if (window == IntPtr.Zero || FindLegacyShellProperties(pid, fixtureName) != window)
            throw new InvalidOperationException("Find properties window is not verified");
        if (!PostMessageW(window, 0x0010, UIntPtr.Zero, IntPtr.Zero)) // WM_CLOSE
            throw new InvalidOperationException("Could not close test-owned property window: " + Marshal.GetLastWin32Error());
    }

    public static bool ConfirmLegacyFindRecycle(IntPtr find, uint pid)
    {
        if (FindLegacySearchWindow(pid) != find)
            throw new InvalidOperationException("Unverified Find window for recycle confirmation");
        IntPtr confirmation = IntPtr.Zero;
        foreach (TopLevelWindow window in GetProcessWindows(pid))
        {
            if (!window.Visible || ClassName(window.Handle) != "#32770" ||
                (!MatchesDialogTitle(window.Title, "Delete File") &&
                 !MatchesDialogTitle(window.Title, "Datei löschen")))
                continue;
            IntPtr owner = GetWindow(window.Handle, 4); // GW_OWNER
            if (owner != find &&
                (owner == IntPtr.Zero || !GetWindowCaption(owner).Contains("SEW: CFindDialog::OnDelete toRecycle=1") ||
                 GetAncestor(owner, 2) != find))
                continue;
            if (confirmation != IntPtr.Zero)
                throw new InvalidOperationException("Multiple owned Find recycle confirmations");
            confirmation = window.Handle;
        }
        if (confirmation == IntPtr.Zero)
            return false;
        PostFindButton(confirmation, pid, 6); // IDYES
        return true;
    }

    public static void LegacyResultViewerCommand(IntPtr viewer, uint pid, string expectedPath, uint command)
    {
        if (viewer == IntPtr.Zero || FindLegacyResultViewer(pid, expectedPath) != viewer ||
            (command != 0 && command != 6062 && command != 6066 && command != 6085 && command != 6086))
            throw new InvalidOperationException("Unverified viewer or unsupported Find viewer command");
        uint message = command == 0 ? 0x0010u : 0x0111u; // WM_CLOSE or WM_COMMAND
        if (!PostMessageW(viewer, message, new UIntPtr(command), IntPtr.Zero))
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    }

    public static void LegacyFindCommand(IntPtr window, uint pid, uint command, bool post)
    {
        uint owner;
        if (GetWindowThreadProcessId(window, out owner) == 0 || owner != pid ||
            !IsWindowVisible(window) ||
            (FindLegacySearchWindow(pid) != window &&
             ((command != 741 && command != 687) || ClassName(window) != "SalamanderMainWindowVer25")))
            throw new InvalidOperationException("Unverified Find command window");
        if (post)
        {
            if (!PostMessageW(window, 0x0111, new UIntPtr(command), IntPtr.Zero))
                throw new InvalidOperationException("Could not queue verified Find command " + command);
        }
        else
            SendChecked(window, 0x0111, new UIntPtr(command), IntPtr.Zero);
    }

    public static void PostUnicodeFindCommand(IntPtr mainWindow, uint pid)
    {
        if (mainWindow == IntPtr.Zero || FindMainWindow(pid) != mainWindow)
            throw new InvalidOperationException("Unverified main window for the Unicode Find command");
        if (!PostMessageW(mainWindow, 0x0111, new UIntPtr(796), IntPtr.Zero)) // CM_FINDUNICODEFILE
            throw new InvalidOperationException("Could not queue the Unicode Find command");
    }

    public static void SetLegacyFindCheck(IntPtr window, uint pid, int id, uint state)
    {
        IntPtr child = VerifiedChild(window, pid, id);
        if (ClassName(child) != "Button" || !IsWindowEnabled(child) || state > 2)
            throw new InvalidOperationException("Find checkbox is unavailable: " + id);
        SendChecked(child, 0x00F1, new UIntPtr(state), IntPtr.Zero); // BM_SETCHECK
        ClickFindButton(window, pid, id);
        if (SendChecked(child, 0x00F0, UIntPtr.Zero, IntPtr.Zero).ToInt64() != state)
            throw new InvalidOperationException("Find checkbox did not accept state: " + id);
    }

    public static void SetLegacyFindComboIndex(IntPtr window, uint pid, int id, uint index)
    {
        IntPtr child = VerifiedChild(window, pid, id);
        if (ClassName(child) != "ComboBox" || !IsWindowEnabled(child) ||
            SendChecked(child, 0x014E, new UIntPtr(index), IntPtr.Zero).ToInt64() != index)
            throw new InvalidOperationException("Find combo did not accept index: " + id);
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr VirtualAllocEx(Microsoft.Win32.SafeHandles.SafeProcessHandle process,
        IntPtr address, UIntPtr size, uint allocationType, uint protection);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool VirtualFreeEx(Microsoft.Win32.SafeHandles.SafeProcessHandle process,
        IntPtr address, UIntPtr size, uint freeType);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool WriteProcessMemory(Microsoft.Win32.SafeHandles.SafeProcessHandle process,
        IntPtr address, byte[] data, UIntPtr size, out UIntPtr written);

    public static void SetLegacyFindDateTime(IntPtr dialog, System.Diagnostics.Process process,
        int controlId, DateTime value)
    {
        uint pid = checked((uint)process.Id);
        IntPtr control = VerifiedChild(dialog, pid, controlId);
        if (controlId < 2581 || controlId > 2584 ||
            !MatchesDialogTitle(GetWindowCaption(dialog), "Advanced Options") ||
            ClassName(control) != "SysDateTimePick32" || !IsWindowEnabled(control))
            throw new InvalidOperationException("Unverified Advanced date/time picker");

        // DTM_SETSYSTEMTIME does not marshal its SYSTEMTIME argument between
        // processes. Stage just the 16-byte value in the launched test process.
        ushort[] fields = { (ushort)value.Year, (ushort)value.Month, (ushort)value.DayOfWeek,
            (ushort)value.Day, (ushort)value.Hour, (ushort)value.Minute, (ushort)value.Second, 0 };
        byte[] data = new byte[16];
        Buffer.BlockCopy(fields, 0, data, 0, data.Length);
        UIntPtr size = new UIntPtr((uint)data.Length);
        var handle = process.SafeHandle;
        IntPtr remote = VirtualAllocEx(handle, IntPtr.Zero, size, 0x3000, 0x04);
        if (remote == IntPtr.Zero)
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        bool pending = false;
        try
        {
            UIntPtr written;
            if (!WriteProcessMemory(handle, remote, data, size, out written) || written != size)
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());

            pending = true;
            IntPtr result;
            if (SendMessageTimeout(control, 0x1002, UIntPtr.Zero, remote, 3, 5000, out result) == IntPtr.Zero)
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            pending = false;
            if (result == IntPtr.Zero)
                throw new InvalidOperationException("Advanced date/time picker rejected the value");
        }
        finally
        {
            // On timeout the control may still hold the pointer. The driver
            // terminates its own test process in finally, reclaiming the page.
            if (!pending)
                VirtualFreeEx(handle, remote, UIntPtr.Zero, 0x8000);
        }
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool DeviceIoControl(Microsoft.Win32.SafeHandles.SafeFileHandle file,
        uint code, ref ushort format, uint inputSize, IntPtr output, uint outputSize,
        out uint returned, IntPtr overlapped);

    public static void CompressLegacyFindFixture(System.IO.FileStream file)
    {
        ushort format = 1; // COMPRESSION_FORMAT_DEFAULT
        uint returned;
        if (!DeviceIoControl(file.SafeFileHandle, 0x0009C040, ref format, 2,
            IntPtr.Zero, 0, out returned, IntPtr.Zero))
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool LocalFileTimeToFileTime(in long localFileTime, out long utcFileTime);

    public static DateTime LegacyFindFixtureUtc(DateTime wallClock)
    {
        // The original filter uses FileTimeToLocalFileTime, which uses the
        // current Windows offset even for a date from another DST season.
        long local = DateTime.SpecifyKind(wallClock, DateTimeKind.Utc).ToFileTimeUtc();
        long utc;
        if (!LocalFileTimeToFileTime(in local, out utc))
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        return DateTime.FromFileTimeUtc(utc);
    }

    [ComImport, Guid("618736E0-3C3D-11CF-810C-00AA00389B71"), InterfaceType(ComInterfaceType.InterfaceIsIDispatch)]
    private interface IListViewAccessibility
    {
        [DispId(-5003)] // IAccessible::accName
        string this[[MarshalAs(UnmanagedType.Struct)] object child] { [return: MarshalAs(UnmanagedType.BStr)] get; }
    }

    [DllImport("oleacc.dll", ExactSpelling = true)]
    private static extern int AccessibleObjectFromWindow(IntPtr window, uint objectId, in Guid interfaceId,
        [MarshalAs(UnmanagedType.Interface)] out IListViewAccessibility accessible);

    public static string LegacyFindDisplayedName(IntPtr window, uint pid, int index)
    {
        IntPtr list = VerifiedChild(window, pid, 2510);
        if (index < 0 || index >= LegacyFindResultCount(window, pid))
            throw new ArgumentOutOfRangeException(nameof(index));

        var interfaceId = typeof(IListViewAccessibility).GUID;
        // OBJID_CLIENT exposes the ListView rows as 1-based MSAA children.
        int result = AccessibleObjectFromWindow(list, unchecked((uint)-4), in interfaceId, out var accessible);
        Marshal.ThrowExceptionForHR(result);
        try { return accessible[index + 1]; }
        finally { Marshal.ReleaseComObject(accessible); }
    }

    public static int LegacyFindResultCount(IntPtr window, uint pid)
    {
        return LegacyFindListCount(window, pid, 2510);
    }

    public static int LegacyFindListCount(IntPtr window, uint pid, int id)
    {
        IntPtr list = VerifiedChild(window, pid, id);
        if (ClassName(list) != "SysListView32")
            throw new InvalidOperationException("Original Find control is not a ListView: " + id);
        return checked((int)SendChecked(list, 0x1004, UIntPtr.Zero, IntPtr.Zero).ToInt64());
    }

    public static int LegacyFindSelectionCount(IntPtr window, uint pid)
    {
        IntPtr list = VerifiedChild(window, pid, 2510);
        return checked((int)SendChecked(list, 0x1032, UIntPtr.Zero, IntPtr.Zero).ToInt64());
    }

    public static string ReadLegacyFindHistory(IntPtr window, uint pid, int id, uint index)
    {
        IntPtr combo = VerifiedChild(window, pid, id);
        if (ClassName(combo) != "ComboBox" || (id != 2501 && id != 2504 && id != 2505))
            throw new InvalidOperationException("Unverified original Find history control");
        long length = SendChecked(combo, 0x0149, new UIntPtr(index), IntPtr.Zero).ToInt64(); // CB_GETLBTEXTLEN
        if (length < 0 || length >= 32767)
            throw new InvalidOperationException("Missing or excessive original Find history entry");
        var text = new StringBuilder(checked((int)length + 1));
        IntPtr result;
        if (SendMessageTimeoutReadText(combo, 0x0148, new UIntPtr(index),
            text, 3, 5000, out result) == IntPtr.Zero || result.ToInt64() < 0)
            throw new InvalidOperationException("Cannot read the original Find history entry");
        return text.ToString();
    }

    public static void ToggleFirstLegacyFindIgnoreItem(IntPtr dialog, uint pid)
    {
        IntPtr list = VerifiedChild(dialog, pid, 2531);
        if (!MatchesDialogTitle(GetWindowCaption(dialog), "Ignore Directory List") ||
            ClassName(list) != "ListBox" ||
            SendChecked(list, 0x0186, UIntPtr.Zero, IntPtr.Zero) != IntPtr.Zero) // LB_SETCURSEL
            throw new InvalidOperationException("Unverified first Ignore Directory List item");
        SendChecked(dialog, 0x0028, new UIntPtr((ulong)list.ToInt64()), new IntPtr(1));
        SendChecked(list, 0x0102, new UIntPtr(0x20), new IntPtr(1)); // WM_CHAR / original Space toggle
    }

    public static bool IsLegacyFindControlVisible(IntPtr window, uint pid, int id)
    {
        return IsWindowVisible(VerifiedChild(window, pid, id));
    }

    public static uint ReadLegacyFindCheck(IntPtr window, uint pid, int id)
    {
        IntPtr child = VerifiedChild(window, pid, id);
        if (ClassName(child) != "Button")
            throw new InvalidOperationException("Unverified original Find checkbox");
        return checked((uint)SendChecked(child, 0x00F0, UIntPtr.Zero, IntPtr.Zero).ToInt64());
    }

    public static void SelectLegacyFindRow(IntPtr window, uint pid, int index)
    {
        IntPtr list = VerifiedChild(window, pid, 2510);
        if (index < 0 || index >= LegacyFindResultCount(window, pid) ||
            (GetKeyState(0x10) & 0x8000) != 0 || (GetKeyState(0x11) & 0x8000) != 0 ||
            (GetKeyState(0x12) & 0x8000) != 0)
            throw new InvalidOperationException("Cannot safely select the original Find result");
        SendChecked(window, 0x0028, new UIntPtr((ulong)list.ToInt64()), new IntPtr(1)); // WM_NEXTDLGCTL
        SendChecked(list, 0x0100, new UIntPtr(0x24), new IntPtr(1)); // VK_HOME
        for (int row = 0; row < index; ++row)
            SendChecked(list, 0x0100, new UIntPtr(0x28), new IntPtr(1)); // VK_DOWN
        if (LegacyFindSelectionCount(window, pid) != 1 || SelectedFindIndex(list) != index)
            throw new InvalidOperationException("The original Find list did not select the requested row");
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

    public static IntPtr FindRenameDialog(IntPtr findWindow, uint pid)
    {
        if (findWindow == IntPtr.Zero || FindUnicodeSearchWindow(pid) != findWindow)
            throw new InvalidOperationException("Unverified Unicode Find window for rename");
        IntPtr found = IntPtr.Zero;
        foreach (TopLevelWindow top in GetProcessWindows(pid))
        {
            if (GetWindow(top.Handle, 4) != findWindow || ClassName(top.Handle) != "#32770" ||
                !MatchesDialogTitle(top.Title, "Rename Unicode item") ||
                ClassName(GetDlgItem(top.Handle, 4101)) != "Edit" ||
                ClassName(GetDlgItem(top.Handle, 1)) != "Button")
                continue;
            if (found != IntPtr.Zero)
                throw new InvalidOperationException("Multiple Unicode Find rename dialogs");
            found = top.Handle;
        }
        return found;
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

    [DllImport("user32.dll")]
    private static extern bool IsWindowUnicode(IntPtr window);

    public static void PostLegacyFindCharacters(IntPtr window, uint pid, int id, string text)
    {
        if (FindLegacySearchWindow(pid) != window || (id != 2501 && id != 2505))
            throw new InvalidOperationException("Unverified legacy Find edit");
        IntPtr combo = VerifiedChild(window, pid, id);
        IntPtr edit = GetWindow(combo, 5); // GW_CHILD
        uint owner;
        if (GetWindowThreadProcessId(edit, out owner) == 0 || owner != pid ||
            ClassName(edit) != "Edit" || !IsWindowUnicode(edit))
            throw new InvalidOperationException("Legacy Find edit is not Unicode");
        foreach (char ch in text)
            if (!PostMessageW(edit, 0x0102, new UIntPtr(ch), new IntPtr(1))) // WM_CHAR
                throw new InvalidOperationException("Could not post a Unicode edit character");
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
        string observed = ReadFindText(window, pid, id);
        if (!String.Equals(observed, text, StringComparison.Ordinal))
            throw new InvalidOperationException("Find control " + id +
                " did not preserve UTF-16 text (requested " + text.Length +
                ", observed " + observed.Length + " units; Unicode control=" +
                IsWindowUnicode(child) + ", Unicode edit=" + IsWindowUnicode(GetWindow(child, 5)) + ")");
    }

    public static string ReadFindText(IntPtr window, uint pid, int id)
    {
        IntPtr child = VerifiedChild(window, pid, id);
        const int capacity = 65537;
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

    public static void SetFindCheckState(IntPtr window, uint pid, int id, uint state)
    {
        IntPtr child = VerifiedChild(window, pid, id);
        SendChecked(child, 0x00F1, new UIntPtr(state), IntPtr.Zero); // BM_SETCHECK
        if (SendChecked(child, 0x00F0, UIntPtr.Zero, IntPtr.Zero).ToInt64() != state)
            throw new InvalidOperationException("Find checkbox did not retain the requested state");
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

    // Send a Home key to the owned ListView and verify the selection before
    // copying its path or acting on the file. The desktop can stay in the background.
    public static int SelectSingleFindResult(IntPtr window, uint pid)
    {
        IntPtr list = VerifiedChild(window, pid, 5117);
        if (FindResultCount(window, pid) != 1 ||
            (GetKeyState(0x10) & 0x8000) != 0 || (GetKeyState(0x11) & 0x8000) != 0 ||
            (GetKeyState(0x12) & 0x8000) != 0)
            throw new InvalidOperationException(
                "Cannot safely select the only Unicode Find result");

        if (SendChecked(list, 0x1013, UIntPtr.Zero, IntPtr.Zero) ==
            IntPtr.Zero) // LVM_ENSUREVISIBLE
            throw new InvalidOperationException(
                "Unicode Find could not make its only result visible");

        SendChecked(list, 0x0100, new UIntPtr(0x24), IntPtr.Zero); // WM_KEYDOWN / VK_HOME
        SendChecked(list, 0x0101, new UIntPtr(0x24), IntPtr.Zero); // WM_KEYUP
        int selected = SelectedFindIndex(list);
        if (selected != 0)
            throw new InvalidOperationException("Unicode Find did not select its only result");
        return selected;
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
    private Action<IntPtr> pendingWrite;
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
                        pendingWrite(window);
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
        Publish(owner => SalamanderGuiNative.SetClipboardUnicodeText(owner, text));
    }

    public void SetFileDrop(string path, bool cut = false)
    {
        Publish(owner => SalamanderGuiNative.SetClipboardFileDrop(owner, path, cut));
    }

    private void Publish(Action<IntPtr> write)
    {
        lock (gate)
        {
            if (disposed || !thread.IsAlive || window == IntPtr.Zero)
                throw new ObjectDisposedException("SalamanderGuiClipboardOwner");
            pendingWrite = write;
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
$script:clipboardTouched = $false
$oldClipboard = $null
$nativeClipboardSnapshot = $null
$clipboardSnapshotValid = $false
try {
    if ($IsolatedConfiguration) {
        Add-Type -Path (Join-Path $PSScriptRoot 'Clipboard-Snapshot.cs')
        $nativeClipboardSnapshot = [SalamanderClipboardSnapshot]::Capture()
    }
    else {
        $oldClipboard = [System.Windows.Forms.Clipboard]::GetDataObject()
    }
    $clipboardSnapshotValid = $true
}
catch {
    Write-Warning ('Original clipboard could not be saved; will not overwrite unknown initial state. ' +
        $_.Exception.Message)
}
if ($IsolatedConfiguration -and -not $clipboardSnapshotValid) {
    throw 'Isolated desktop acceptance requires a complete clipboard snapshot.'
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('OpenSal-GuiLong-' + [guid]::NewGuid().ToString('N'))
$source = Join-Path $root 'source'
$destination = Join-Path $root 'destination'
$moveDir = Join-Path $root 'move-target'
$maxDir = Join-Path $root 'maximum-names'
$maxName = ('n' * 251) + '.txt'
$renamedName = 'Umbenannt_日本_😀.txt'
$deep = $source
$process = $null
$testConfigurationCleanupAllowed = $true
$clipboardRestorationFailed = $false
$primaryGuiFailure = $null
$copyTestReached = $null
$copyTestContinue = $null
$findTestReached = $null
$findTestCancelled = $null
$largeCopyLock = $null
$largeCopySourceFile = $null
$largeCopyTargetFile = $null
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

function Get-BoundaryDirectoryNames {
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ParentPath)

    # Keep the second level at 259 UTF-16 units, then cross MAX_PATH on the
    # third Enter. TEMP/worktree prefixes vary; fixed component lengths cannot
    # guarantee this transition. Trim only for separator-length accounting.
    $budget = 259 - $ParentPath.TrimEnd('\').Length - 2
    $firstPrefix = 'Ordner-A-'
    $secondPrefix = 'Ordner-B-'
    if ($budget -lt ($firstPrefix.Length + $secondPrefix.Length)) {
        throw 'GUI fixture parent is too long for two directories before the MAX_PATH transition.'
    }
    $firstLength = [int][Math]::Floor($budget / 2)
    $secondLength = $budget - $firstLength
    return @(
        $firstPrefix.PadRight($firstLength, 'a')
        $secondPrefix.PadRight($secondLength, 'b')
        'Ordner-C-' + ('c' * 68)
        'Ordner-D-' + ('d' * 68)
    )
}

function Test-LargeUnicodeCopy {
    # Arrange: both directories exceed MAX_PATH; the original UTF-16 row,
    # not its ACP compatibility alias, must reach the existing copy worker.
    Go-ToPath $largeCopySourceDirectory -NoForeground
    Focus-DirectoryRow -Name $utfName -VerifiedBackground
    Assert-True ((Read-FocusedFullname -AllowVerifiedBackground) -ceq $largeCopySourceFile) '32-MiB Unicode source identity verified'
    # Act
    [SalamanderGuiNative]::PostVerifiedLargeCopyCommand($mainWindowHandle, [uint32]$process.Id)
    $confirmation = @{ Window = [IntPtr]::Zero }
    try {
        Wait-Until {
            $dialog = Get-TestDialog
            if ($dialog -match 'legacy ANSI file-operation engine|16.*MiB|synchronous transfer limit|native Unicode file operation') {
                throw "Large Unicode F5 refused by the legacy transfer guard: $dialog"
            }
            $confirmation.Window = [SalamanderGuiNative]::FindVerifiedLargeCopyConfirmation(
                $mainWindowHandle, [uint32]$process.Id, $utfName, $largeCopyTargetDirectory)
            return $confirmation.Window -ne [IntPtr]::Zero
        } '32-MiB Unicode copy confirmation'
    }
    catch {
        $reason = $_.Exception.Message
        $windows = Get-ProcessWindowSummary -OwnerProcessId ([uint32]$process.Id)
        $foreground = Get-ForegroundWindowSummary
        $blockingDialog = Get-TestDialog
        throw (("Large Unicode F5 confirmation unavailable: {0}; windows=[{1}]; " +
                "foreground=[{2}]; generic dialog='{3}'. No second F5 command was sent.") -f
               $reason, $windows, $foreground, $blockingDialog)
    }
    [SalamanderGuiNative]::ConfirmVerifiedLargeCopy(
        $mainWindowHandle, [uint32]$process.Id, $confirmation.Window,
        $utfName, $largeCopyTargetDirectory)
    Write-Host 'PASS: verified owned Unicode copy confirmation retains complete UTF-16 identity'
    $observed = @{ Window = [IntPtr]::Zero }
    if ($LargeUnicodeCopyCase -eq 'Collision' -or $LargeUnicodeCopyCase -eq 'LockedSource') {
        $controlId = if ($LargeUnicodeCopyCase -eq 'Collision') { 181 } else { 171 }
        $expected = if ($LargeUnicodeCopyCase -eq 'Collision') { $largeCopyTargetFile } else { $largeCopySourceFile }
        Wait-Until {
            $observed.Window = [SalamanderGuiNative]::FindOwnedDialogControl([uint32]$process.Id, $controlId, $expected)
            return $observed.Window -ne [IntPtr]::Zero
        } "native $LargeUnicodeCopyCase dialog with exact UTF-16 path"
        [SalamanderGuiNative]::PostOwnedCopyDialogButton($observed.Window, [uint32]$process.Id, 2)
        Write-Host "PASS: native $LargeUnicodeCopyCase dialog preserved the complete Unicode identity and was cancelled"
    }
    else {
        Wait-Until { $copyTestReached.WaitOne(0) } 'worker reached deterministic test checkpoint'
        Wait-Until {
            $observed.Window = [SalamanderGuiNative]::FindOwnedDialogControl([uint32]$process.Id, 152, $largeCopySourceFile)
            return $observed.Window -ne [IntPtr]::Zero -and
                [SalamanderGuiNative]::OwnedControlText($observed.Window, [uint32]$process.Id, 154) -ceq $largeCopyTargetFile
        } 'existing copy progress UI displays both complete UTF-16 paths'
        Write-Host 'PASS: real copy progress dialog retains original Unicode source and target paths'
        if ($LargeUnicodeCopyCase -eq 'Cancel') {
            [SalamanderGuiNative]::PostOwnedCopyDialogButton($observed.Window, [uint32]$process.Id, 2)
            $confirmation = @{ Window = [IntPtr]::Zero; Button = 0 }
            Wait-Until {
                foreach ($button in @(6, 2480)) {
                    $candidate = [SalamanderGuiNative]::FindOwnedDialogControl([uint32]$process.Id, $button, $null)
                    if ($candidate -ne [IntPtr]::Zero -and
                        [SalamanderGuiNative]::IsOwnedModalOf($candidate, $observed.Window) -and
                        [SalamanderGuiNative]::MatchesDialogTitle([SalamanderGuiNative]::GetWindowCaption($candidate), 'Question') -and
                        [SalamanderGuiNative]::HasVerifiedStaticText($candidate, [uint32]$process.Id, 'Do you want to cancel this operation?') -and
                        ([SalamanderGuiNative]::OwnedControlText($candidate, [uint32]$process.Id, $button) -replace '&','') -match '(?i)^Yes$') {
                        $confirmation.Window = $candidate
                        $confirmation.Button = $button
                        return $true
                    }
                }
                return $false
            } 'owned copy cancellation confirmation'
            [SalamanderGuiNative]::PostOwnedCopyDialogButton($confirmation.Window, [uint32]$process.Id, $confirmation.Button)
            Wait-Until {
                return -not [SalamanderGuiNative]::OwnedControlEnabled($observed.Window, [uint32]$process.Id, 158)
            } 'copy cancellation acknowledged before releasing worker checkpoint'
            [void]$copyTestContinue.Set()
        }
        else {
            [SalamanderGuiNative]::PostOwnedCopyDialogButton($observed.Window, [uint32]$process.Id, 158)
            Wait-Until {
                [SalamanderGuiNative]::OwnedControlText($observed.Window, [uint32]$process.Id, 158) -match '(?i)resume'
            } 'existing Pause command acknowledged'
            [void]$copyTestContinue.Set()
            Assert-True ([SalamanderGuiNative]::IsWindowVisible($observed.Window)) 'Paused copy progress remains open'
            [SalamanderGuiNative]::PostOwnedCopyDialogButton($observed.Window, [uint32]$process.Id, 158)
            Write-Host 'PASS: existing Pause/Resume controls accepted through verified own HWNDs'
        }
    }
    Wait-Until {
        [SalamanderGuiNative]::FindOwnedDialogControl([uint32]$process.Id, 158, $null) -eq [IntPtr]::Zero
    } 'copy worker and existing progress dialog completed'
    if ($null -ne $largeCopyLock) { $largeCopyLock.Dispose(); $script:largeCopyLock = $null }
    if ($LargeUnicodeCopyCase -ne 'Copy') {
        if ($LargeUnicodeCopyCase -eq 'Collision') {
            Assert-True ((Get-FileHash -LiteralPath $largeCopyTargetFile -Algorithm SHA256).Hash -ceq $largeCopyCollisionHash) 'Cancelled overwrite preserved existing destination bytes'
        }
        else {
            Assert-True (-not [IO.File]::Exists($largeCopyTargetFile)) 'Cancelled or failed copy leaves no partial destination'
        }
        Assert-True ((Get-FileHash -LiteralPath $largeCopySourceFile -Algorithm SHA256).Hash -ceq $largeCopyHash) 'Negative copy case preserved original source bytes'
        Write-Host "PASS: real large Unicode copy negative case $LargeUnicodeCopyCase"
        return
    }
    # Assert: completion requires the worker to finish, not just a momentarily
    # readable main stream before ADS/attributes/security have been applied.
    Wait-Until {
        if (-not [IO.File]::Exists($largeCopyTargetFile)) { return $false }
        try {
            return ([IO.FileInfo]::new($largeCopyTargetFile).Length -eq 32MB) -and
                ((Get-FileHash -LiteralPath $largeCopyTargetFile -Algorithm SHA256).Hash -ceq $largeCopyHash)
        }
        catch { return $false }
    } '32-MiB Unicode worker copy and complete SHA256 match'
    Assert-True ((Get-FileHash -LiteralPath $largeCopySourceFile -Algorithm SHA256).Hash -ceq $largeCopyHash) 'Large Unicode copy preserved source bytes'
    Assert-True ([IO.File]::GetLastWriteTimeUtc($largeCopyTargetFile) -eq $largeCopyLastWrite) 'Worker preserved original last-write time'
    Assert-True (([IO.File]::GetAttributes($largeCopyTargetFile) -band [IO.FileAttributes]::ReadOnly) -ne 0) 'Worker preserved read-only file attribute'
    Assert-True ([Linq.Enumerable]::SequenceEqual[byte]([IO.File]::ReadAllBytes($largeCopyTargetFile + ':識別_😀'), $largeCopyAdsBytes)) 'Worker preserved exact Unicode ADS name and bytes'
    Write-Host 'PASS: the existing F5 command handler copies a 32-MiB Unicode file between long paths without the synchronous size limit.'
}

function Initialize-IsolatedGuiConfiguration {
    # Only the fresh, preflighted namespace belongs to this test. Version 59
    # permits the language setting to be read while retaining the real upgrade
    # and plugin auto-install paths (do not seed the current version or disable plugins).
    if ($testConfigurationKey -cnotmatch '^Software\\Open Salamander\\CodexTests\\[0-9a-f]{32}$') {
        throw 'Refusing unsafe isolated configuration seed.'
    }
    if (-not [IO.File]::Exists((Join-Path (Split-Path -Parent $SalamanderExe) 'lang\english.slg'))) {
        throw 'Isolated GUI acceptance requires the built english.slg language module.'
    }
    $versionKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($testConfigurationKey + '\Config0\Version')
    try { $versionKey.SetValue('Configuration', 59, [Microsoft.Win32.RegistryValueKind]::DWord) }
    finally { $versionKey.Dispose() }
    $languageKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($testConfigurationKey + '\Config0\Configuration')
    try { $languageKey.SetValue('Language', 'english.slg', [Microsoft.Win32.RegistryValueKind]::String) }
    finally { $languageKey.Dispose() }
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

function Get-ProcessThreadSummary {
    if ($null -eq $process) { return '<not launched>' }
    try {
        $process.Refresh()
        if ($process.HasExited) { return "exited; code=$($process.ExitCode)" }
        $threads = @($process.Threads)
        $descriptions = @($threads | Select-Object -First 16 | ForEach-Object {
            $state = $_.ThreadState.ToString()
            $wait = if ($_.ThreadState -eq [Diagnostics.ThreadState]::Wait) {
                try { $_.WaitReason.ToString() }
                catch { '<unavailable>' }
            } else { '-' }
            'TID={0} state={1} wait={2}' -f $_.Id, $state, $wait
        })
        return 'count={0}; {1}' -f $threads.Count, ($descriptions -join '; ')
    }
    catch { return '<unavailable: ' + $_.Exception.Message + '>' }
}

function Get-IsolatedStartupDiagnostics {
    if (-not $IsolatedConfiguration) { return '<not isolated>' }
    $version = '<missing>'
    try {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(
            $testConfigurationKey + '\Config0\Version')
        if ($null -ne $key) {
            try {
                $value = $key.GetValue('Configuration', $null)
                $version = if ($null -eq $value) { '<no Configuration value>' }
                           else { [string]$value }
            }
            finally { $key.Dispose() }
        }
    }
    catch { $version = '<read error: ' + $_.Exception.Message + '>' }
    $process.Refresh()
    $state = if ($process.HasExited) { "exited code=$($process.ExitCode)" }
             else { 'running' }
    return ('Config0.Version.Configuration={0}; process={1}; windows=[{2}]; threads=[{3}]' -f
        $version, $state, (Get-ProcessWindowSummary -OwnerProcessId ([uint32]$process.Id)),
        (Get-ProcessThreadSummary))
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
    # GetLastActivePopup remembers prior modeless windows, including a
    # Status display after successful F8. It is NOT a modal-state test.
    # An enabled main HWND plus no known error dialogs means that commands
    # addressed to its verified HWND may continue without desktop focus.
    if ([SalamanderGuiNative]::IsWindowEnabled($main)) {
        return $null
    }

    # A disabled main HWND is a genuine blocking condition even if its
    # popup has already closed or a window handle is in transition.
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
    return 'Salamander main window is disabled by an unidentified dialog'
}

function Focus-TestProcess {
    $process.Refresh()
    if ($process.HasExited) { throw 'Test Salamander process terminated unexpectedly.' }
    $h = $mainWindowHandle
    if ($h -eq [IntPtr]::Zero) { throw 'No verified main window for test Salamander.' }

    # Windows may temporarily give the foreground to a system overlay.
    # Repeated SetForegroundWindow attempts cannot override its policy and
    # risk disrupting a user at the interactive desktop. Make at most six
    # attempts, and after the initial three retry only if the foreground
    # owner changes. Do not treat an externally blocked desktop as a product
    # regression. No keypress is sent unless the exact HWND is foreground.
    $activationCount = 0
    $previousForeground = [IntPtr]::Zero
    $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Min(10, $TimeoutSeconds))
    do {
        $process.Refresh()
        if ($process.HasExited) { throw 'Test Salamander process terminated unexpectedly.' }

        [uint32]$windowPid = 0
        [void][SalamanderGuiNative]::GetWindowThreadProcessId($h, [ref]$windowPid)
        if ($windowPid -ne [uint32]$process.Id) {
            throw "Main window no longer belongs to launched Salamander PID $($process.Id)."
        }
        $dialog = Get-TestDialog
        if (-not [string]::IsNullOrEmpty($dialog)) {
            throw "Cannot focus Salamander while an application dialog is open: $dialog"
        }

        $foreground = [SalamanderGuiNative]::GetForegroundWindow()
        if ($foreground -eq $h) { return }
        $foregroundChanged = $foreground -ne $previousForeground
        if ($activationCount -lt 3 -or
            ($foregroundChanged -and $activationCount -lt 6)) {
            $activationCount++
            $useFallback = $activationCount -eq 3 -or $activationCount -eq 6
            $activated = [SalamanderGuiNative]::TryActivateVerifiedWindow(
                $h, [uint32]$process.Id, $useFallback)
            if ($activated -and [SalamanderGuiNative]::GetForegroundWindow() -eq $h) {
                return
            }
        }

        $previousForeground = [SalamanderGuiNative]::GetForegroundWindow()
        Start-Sleep -Milliseconds 350
    } while ([DateTime]::UtcNow -lt $deadline)

    $foreground = Get-ForegroundWindowSummary
    $windows = Get-ProcessWindowSummary -OwnerProcessId ([uint32]$process.Id)
    $failureCategory = if ((Get-ActiveProcessId) -ne [uint32]$process.Id) {
        'GUI_ENVIRONMENT_BLOCKED'
    }
    else {
        'GUI_FOCUS_FAILURE'
    }
    throw (("{0}: Cannot activate verified Salamander HWND=0x{1:X} PID={2} " +
           "after {3} bounded activation attempts. Foreground: {4}; " +
           "test process windows: {5}. No keys were sent. " +
           "Run destructive GUI tests in an exclusive interactive desktop session.") -f
           $failureCategory, $h.ToInt64(), $process.Id, $activationCount,
           $foreground, $windows)
}

# WaitForInputIdle can return while Salamander's main GUI thread is still
# executing startup work. Probe its verified HWND using only a read-only WM_NULL
# until it pumps messages; do not mutate the clipboard or send keys beforehand.
function Wait-ForGuiResponsive {
    param(
        [ValidateSet('Startup', 'BeforeClipboard', 'PreCommand775', 'AfterDirectoryDelete')]
        [string]$Context = 'Startup',
        [ValidateRange(1,60)][int]$StartupTimeoutSeconds = 15
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($StartupTimeoutSeconds)
    $attempts = 0
    $genericFailures = 0
    $timeoutFailures = 0
    $lastErrorCode = 0
    do {
        $process.Refresh()
        if ($process.HasExited) {
            throw "Test Salamander exited before GUI startup readiness (PID $($process.Id))."
        }
        $dialog = Get-TestDialog
        if (-not [string]::IsNullOrEmpty($dialog)) {
            throw "Salamander startup is blocked by a dialog: $dialog"
        }

        [IntPtr]$response = [IntPtr]::Zero
        $attempts++
        [SalamanderGuiNative]::SetLastError([uint32]0)
        $result = [SalamanderGuiNative]::SendMessageTimeout(
            $mainWindowHandle, [uint32]0, [UIntPtr]::Zero, [IntPtr]::Zero,
            [uint32]0x0002, [uint32]750, [ref]$response)
        # Preserve the status before any other Win32 call overwrites it.
        $lastErrorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        if ($result -ne [IntPtr]::Zero) {
            if ($Context -eq 'AfterDirectoryDelete') {
                Write-Host "PASS: Salamander GUI responsive after directory deletion ($attempts attempt(s))."
            }
            elseif ($Context -eq 'PreCommand775') {
                Write-Host "PASS: Salamander GUI responds to WM_NULL immediately before clipboard navigation ($attempts attempt(s))."
            }
            elseif ($Context -eq 'BeforeClipboard') {
                Write-Host "PASS: Salamander GUI responsive before clipboard publication ($attempts attempt(s))."
            }
            else {
                Write-Host "PASS: Salamander main GUI thread responds after startup readiness probe ($attempts attempt(s))."
            }
            return
        }
        if ($lastErrorCode -eq 0) { $genericFailures++ }
        elseif ($lastErrorCode -eq 1460) { $timeoutFailures++ }
        # SMTO_ABORTIFHUNG does not always set LastError when a blocked GUI
        # stops pumping messages. Retry only error 0 and ERROR_TIMEOUT (1460)
        # until the same bounded deadline; do not send GUI navigation input.
        if ($lastErrorCode -ne 1460 -and $lastErrorCode -ne 0) {
            # Failure may be generic (Win32 code 0), invalid HWND, or a
            # non-timeout OS failure. Never interpret it as readiness.
            $status = if ($lastErrorCode -eq 0) {
                'generic SendMessageTimeoutW failure (LastError=0)'
            }
            else {
                "Win32 error $lastErrorCode"
            }
            [uint32]$ownerPid = 0
            $guiThread = [SalamanderGuiNative]::GetWindowThreadProcessId(
                $mainWindowHandle, [ref]$ownerPid)
            $hung = [SalamanderGuiNative]::IsHungAppWindow($mainWindowHandle)
            $foreground = Get-ForegroundWindowSummary
            $windows = Get-ProcessWindowSummary -OwnerProcessId ([uint32]$process.Id)
            $waitChain = '<not collected>'
            if ($guiThread -ne 0) {
                try { $waitChain = [SalamanderGuiWaitChain]::Describe([uint32]$guiThread) }
                catch { $waitChain = "WCT unavailable: $($_.Exception.Message)" }
            }
            throw (("GUI WM_NULL readiness ({0}) failed: {1}; attempt={2}; " +
                   "HWND=0x{3:X}; test PID={4}; owner PID={5}; GUI thread={6}; " +
                   "IsHungAppWindow={7}; foreground={8}; windows=[{9}]; " +
                   "wait chain=[{10}]. No navigation command sent.") -f
                   $Context, $status, $attempts, $mainWindowHandle.ToInt64(),
                   $process.Id, $ownerPid, $guiThread, $hung,
                   $foreground, $windows, $waitChain)
        }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)

    [uint32]$ownerPid = 0
    $guiThread = [SalamanderGuiNative]::GetWindowThreadProcessId(
        $mainWindowHandle, [ref]$ownerPid)
    $waitChain = '<not collected>'
    try { $waitChain = [SalamanderGuiWaitChain]::Describe([uint32]$guiThread) }
    catch { $waitChain = "WCT unavailable: $($_.Exception.Message)" }
    $windowSummary = Get-ProcessWindowSummary -OwnerProcessId ([uint32]$process.Id)
    $hung = [SalamanderGuiNative]::IsHungAppWindow($mainWindowHandle)
    $foreground = Get-ForegroundWindowSummary
    throw (("GUI startup remained unresponsive (phase={0}) after {1} WM_NULL attempts " +
           "over {2}s; Win32 error={3}; GUI thread={4}; owner PID={5}; " +
           "windows=[{6}]; wait chain=[{7}]; IsHungAppWindow={8}; " +
           "genericFailures={9}; timeoutFailures={10}; foreground={11}. " +
           "No navigation command sent.") -f
           $Context, $attempts, $StartupTimeoutSeconds, $lastErrorCode,
           $guiThread, $ownerPid, $windowSummary, $waitChain, $hung,
           $genericFailures, $timeoutFailures, $foreground)
}

# An HWND with the registered main class is available before the window
# caption is initialized. Require the genuine application title in addition
# to responsiveness before any clipboard update or simulated keystroke.
function Wait-ForGuiTitle {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $title = ''
    do {
        $process.Refresh()
        if ($process.HasExited) {
            throw "Test Salamander exited before publishing its window title (PID $($process.Id))."
        }
        $actual = [SalamanderGuiNative]::FindMainWindow([uint32]$process.Id)
        if ($actual -ne $mainWindowHandle) {
            throw 'Salamander main window identity changed during startup.'
        }
        $dialog = Get-TestDialog
        if (-not [string]::IsNullOrEmpty($dialog)) {
            throw "Salamander startup blocked by an unexpected dialog: $dialog"
        }
        $title = [SalamanderGuiNative]::GetWindowCaption($mainWindowHandle)
        if ($title.IndexOf('Open Salamander', [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            Write-Host 'PASS: Salamander main window published its expected title before GUI input'
            return
        }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)

    [uint32]$owner = 0
    $thread = [SalamanderGuiNative]::GetWindowThreadProcessId(
        $mainWindowHandle, [ref]$owner)
    $chain = '<not collected>'
    try { $chain = [SalamanderGuiWaitChain]::Describe([uint32]$thread) }
    catch { $chain = "WCT unavailable: $($_.Exception.Message)" }
    $windows = Get-ProcessWindowSummary -OwnerProcessId ([uint32]$process.Id)
    throw ("GUI startup did not publish its main window title within {0}s; " +
           "actual title='{1}'; owner PID={2}; GUI thread={3}; " +
           "windows=[{4}]; wait chain=[{5}]. No GUI input sent." -f
           $TimeoutSeconds, $title, $owner, $thread, $windows, $chain)
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

    # A single 2500 ms WM_NULL timeout during initial clipboard processing
    # is not proof of a permanent GUI deadlock. Recheck the exact HWND using
    # side-effect-free WM_NULL with a bounded deadline; fail without WM_COMMAND
    # if it never becomes responsive.
    if ($CommandId -eq 775) {
        Wait-ForGuiResponsive -Context 'PreCommand775' -StartupTimeoutSeconds 15
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
    # A failed publication can still have cleared the system clipboard.
    $script:clipboardTouched = $true
    $script:clipboardOwner.SetText($Text)
}

function Set-ClipboardText {
    param([string]$Text)
    for ($i=0; $i -lt 10; $i++) {
        try {
            $script:clipboardTouched = $true
            [Windows.Forms.Clipboard]::SetText($Text)
            return
        }
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
    param([string]$Path, [switch]$NoForeground)

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
        if (-not $NoForeground) { Focus-TestProcess }
        Wait-ForGuiResponsive -Context 'BeforeClipboard' -StartupTimeoutSeconds 15
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
                if (-not $NoForeground -and
                    $diagnostics.ForegroundPid -ne [uint32]$process.Id) {
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
        [Parameter(Mandatory)][string]$Sentinel,
        [switch]$AllowVerifiedBackground
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
        if (-not $AllowVerifiedBackground -and
            (Get-ActiveProcessId) -ne [uint32]$process.Id) {
            throw "Cannot read focused clipboard value while Salamander is not foreground: $(Get-ForegroundWindowSummary)"
        }
        if ($AllowVerifiedBackground -and
            -not [SalamanderGuiNative]::IsWindowEnabled($mainWindowHandle)) {
            throw 'Refusing background clipboard read while Salamander main window is disabled.'
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
    param([switch]$AllowVerifiedBackground)
    Read-FocusedClipboardValue -CommandId 710 -Sentinel 'SENTINEL_NOT_FILENAME' -AllowVerifiedBackground:$AllowVerifiedBackground
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
# Wait for the exact native confirmation instead of relying on a fixed
# delay and an Enter sent to whichever window owns the global foreground.
function Confirm-DirectoryDeleteDialog {
    param([Parameter(Mandatory)][string]$ExpectedName)

    $script:directoryDeleteDialog = [IntPtr]::Zero
    Wait-Until {
        $script:directoryDeleteDialog =
            [SalamanderGuiNative]::FindUnicodeDirectoryDeleteDialog([uint32]$process.Id)
        return $script:directoryDeleteDialog -ne [IntPtr]::Zero
    } 'owned Unicode directory deletion confirmation'
    $dialogText = [SalamanderGuiNative]::DescribeWindow($script:directoryDeleteDialog)
    if (-not $dialogText.Contains($ExpectedName, [StringComparison]::Ordinal)) {
        throw ("Delete confirmation does not name the exact selected fixture " +
               "'{0}'; dialog='{1}'. No confirmation was posted." -f
               $ExpectedName, $dialogText)
    }
    [SalamanderGuiNative]::PostVerifiedDirectoryDeleteConfirmation(
        $script:directoryDeleteDialog, [uint32]$process.Id)
}

# An F8 confirmation is posted asynchronously. The directory may already
# have vanished while Salamander is still closing its modal confirmation or
# its own progress/status window. Wait for actual main-window enablement,
# not an arbitrary delay or a stale GetLastActivePopup reference.
function Wait-ForCompletedDirectoryDelete {
    param([Parameter(Mandatory)][string]$DeletedDirectory)

    Wait-Until {
        $process.Refresh()
        if ($process.HasExited) {
            throw "Salamander exited after F8 deletion."
        }
        if ([IO.Directory]::Exists($DeletedDirectory) -or
            [SalamanderGuiNative]::FindUnicodeDirectoryDeleteDialog(
                [uint32]$process.Id) -ne [IntPtr]::Zero -or
            -not [SalamanderGuiNative]::IsWindowEnabled($mainWindowHandle)) {
            return $false
        }
        $blockingDialog = Get-TestDialog
        if (-not [string]::IsNullOrEmpty($blockingDialog)) {
            throw "Unexpected blocking Salamander dialog after F8: $blockingDialog"
        }
        return $true
    } 'F8 confirmation closed and main window re-enabled'
    Wait-ForGuiResponsive -Context 'AfterDirectoryDelete' -StartupTimeoutSeconds 15
}

function Focus-DirectoryRow {
    param(
        [Parameter(Mandatory)][string]$Name,
        [switch]$VerifiedBackground
    )

    $observed = [Collections.Generic.List[string]]::new()
    if ($VerifiedBackground) {
        [SalamanderGuiNative]::SendVerifiedFileListKey(
            $mainWindowHandle, [uint32]$process.Id, [uint32]0x24) # HOME
        [SalamanderGuiNative]::SendVerifiedFileListKey(
            $mainWindowHandle, [uint32]$process.Id, [uint32]0x28) # DOWN
    }
    else {
        Send-Keys '{HOME}'
        Send-Keys '{DOWN}'
    }
    for ($row = 0; $row -lt 24; $row++) {
        $focusedName = Read-FocusedFilename -AllowVerifiedBackground:$VerifiedBackground
        if ($focusedName -ceq $Name) {
            return
        }
        $observed.Add($focusedName)
        if ($VerifiedBackground) {
            [SalamanderGuiNative]::SendVerifiedFileListKey(
                $mainWindowHandle, [uint32]$process.Id, [uint32]0x28) # DOWN
        }
        else {
            Send-Keys '{DOWN}'
        }
    }
    # A failed identity check never triggers any file-operation command.
    $uniqueObserved = ($observed | Select-Object -Unique) -join ', '
    throw ("Expected directory row was not found: '{0}'. Observed focused " +
           "names=[{1}]. No Enter or delete was sent." -f $Name, $uniqueObserved)
}

function Read-FocusedFullname {
    param([switch]$AllowVerifiedBackground)
    Read-FocusedClipboardValue -CommandId 709 -Sentinel 'SENTINEL_NOT_FULLNAME' -AllowVerifiedBackground:$AllowVerifiedBackground
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
    $ownerPid = [uint32]$process.Id
    $selected = [SalamanderGuiNative]::SelectSingleFindResult($script:findWindow, $ownerPid)
    Assert-True ($selected -eq 0) 'Unicode Find selected exactly one visible result'
    $sentinel = 'SENTINEL_NOT_A_FIND_PATH'
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        Set-NativeNavigationClipboard -Text $sentinel
        if ((Get-ClipboardText) -cne $sentinel) { continue }
        $sequence = [SalamanderGuiNative]::GetClipboardSequenceNumber()
        [SalamanderGuiNative]::ClickFindButton($script:findWindow, $ownerPid, 5109)
        $foundPath = Get-ClipboardText
        if ([SalamanderGuiNative]::GetClipboardSequenceNumber() -ne $sequence -and
            $foundPath -and $foundPath -cne $sentinel) {
            Assert-True ($foundPath -ceq $ExpectedPath) 'Unicode Find copied the exact UTF-16 result path'
            return
        }
    }
    throw 'Unicode Find copy did not publish the selected path after three attempts.'
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
    Go-ToPath $findRoot -NoForeground
    [SalamanderGuiNative]::PostUnicodeFindCommand($mainWindowHandle, [uint32]$process.Id)
    Wait-Until {
        $script:findWindow = Get-UnicodeFindWindow
        return $script:findWindow -ne [IntPtr]::Zero
    } 'modeless Unicode Find window launched by its command'
    Assert-True ([SalamanderGuiNative]::ReadFindText(
        $script:findWindow, [uint32]$process.Id, 5101) -ceq $findRoot) 'Unicode Find preserves full long-path search root'

    # Act / Assert: recursive enumeration, two original W names, two
    # different content encodings and empty-result handling.
    Start-FindQuery -Mask '*.txt' -Content '' -ExpectedCount 2
    $fileSize = [string]$findUtf8Bytes.Length
    [SalamanderGuiNative]::SetFindText($script:findWindow, [uint32]$process.Id, 5119, $fileSize)
    [SalamanderGuiNative]::SetFindText($script:findWindow, [uint32]$process.Id, 5120, $fileSize)
    Start-FindQuery -Mask '*.txt' -Content '' -ExpectedCount 1
    Select-VerifiedFindResult -ExpectedPath $findUtf8Path
    [SalamanderGuiNative]::SetFindText($script:findWindow, [uint32]$process.Id, 5120, '18446744073709551616')
    [SalamanderGuiNative]::ClickFindButton($script:findWindow, [uint32]$process.Id, 5107)
    Assert-True ([SalamanderGuiNative]::ReadFindText($script:findWindow, [uint32]$process.Id, 5118) -like
        'Enter a non-negative whole number*') 'Unicode Find rejects a file size beyond the unsigned 64-bit range'
    [SalamanderGuiNative]::SetFindText($script:findWindow, [uint32]$process.Id, 5119, '')
    [SalamanderGuiNative]::SetFindText($script:findWindow, [uint32]$process.Id, 5120, '')
    [SalamanderGuiNative]::SetFindText($script:findWindow, [uint32]$process.Id, 5123, '2024-02-29')
    [SalamanderGuiNative]::SetFindText($script:findWindow, [uint32]$process.Id, 5124, '2024-02-29')
    Start-FindQuery -Mask '*.txt' -Content '' -ExpectedCount 1
    Select-VerifiedFindResult -ExpectedPath $findUtf16Path
    [SalamanderGuiNative]::SetFindText($script:findWindow, [uint32]$process.Id, 5124, '2024-02-30')
    [SalamanderGuiNative]::ClickFindButton($script:findWindow, [uint32]$process.Id, 5107)
    Assert-True ([SalamanderGuiNative]::ReadFindText($script:findWindow, [uint32]$process.Id, 5118) -like
        'Enter a valid modification date*') 'Unicode Find rejects an invalid calendar date'
    [SalamanderGuiNative]::SetFindText($script:findWindow, [uint32]$process.Id, 5123, '')
    [SalamanderGuiNative]::SetFindText($script:findWindow, [uint32]$process.Id, 5124, '')
    $originalAttributes = [IO.File]::GetAttributes($findUtf16Path)
    [IO.File]::SetAttributes($findUtf16Path, $originalAttributes -bor [IO.FileAttributes]::Hidden)
    [SalamanderGuiNative]::SetFindCheckState($script:findWindow, [uint32]$process.Id, 5130, 1)
    Start-FindQuery -Mask '*.txt' -Content '' -ExpectedCount 1
    Select-VerifiedFindResult -ExpectedPath $findUtf16Path
    [SalamanderGuiNative]::SetFindCheckState($script:findWindow, [uint32]$process.Id, 5130, 0)
    Start-FindQuery -Mask '*.txt' -Content '' -ExpectedCount 1
    Select-VerifiedFindResult -ExpectedPath $findUtf8Path
    [SalamanderGuiNative]::SetFindCheckState($script:findWindow, [uint32]$process.Id, 5130, 2)
    [IO.File]::SetAttributes($findUtf16Path, $originalAttributes)
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
    try {
        Wait-Until {
            $script:renameWindow = [SalamanderGuiNative]::FindRenameDialog(
                $script:findWindow, [uint32]$process.Id)
            return $script:renameWindow -ne [IntPtr]::Zero
        } 'native Unicode Find rename confirmation dialog'
    }
    catch {
        $status = [SalamanderGuiNative]::ReadFindText($script:findWindow, [uint32]$process.Id, 5118)
        $windows = Get-ProcessWindowSummary -OwnerProcessId ([uint32]$process.Id)
        throw ("{0} Unicode Find status='{1}', test windows=[{2}]." -f $_.Exception.Message,$status,$windows)
    }
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
    Wait-Until { -not [SalamanderGuiNative]::IsWindow($script:findWindow) } (
        'Unicode Find closes and joins an active search worker')
    $process.Refresh()
    Assert-True (-not $process.HasExited) (
        'Closing an active Unicode Find search leaves Salamander alive')
    [IO.File]::Delete($cancelProbePath)
    Wait-Until { -not [IO.File]::Exists($cancelProbePath) } 'Windows finishes removing the cancellation fixture'
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

# Capture an opt-in, minimal native dump before the owned hung process is
# terminated. Dumps can contain private stack values and must stay local.
function Save-GuiHangMiniDump {
    if ($env:OPENSAL_GUI_CAPTURE_HANG_DUMP -ne '1') { return }
    if ($null -eq $process) { return }

    $dumpPath = Join-Path ([IO.Path]::GetTempPath()) (
        'OpenSal-GuiHang-' + [guid]::NewGuid().ToString('N') + '.dmp')
    try {
        $process.Refresh()
        if ($process.HasExited) { return }

        $stream = [IO.File]::Open(
            $dumpPath, [IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            # 0 == MiniDumpNormal. Do not capture full memory by default.
            $written = [SalamanderGuiNative]::MiniDumpWriteDump(
                $process.Handle, [uint32]$process.Id, $stream.SafeFileHandle,
                [uint32]0, [IntPtr]::Zero, [IntPtr]::Zero, [IntPtr]::Zero)
            $win32Error = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            if (-not $written) {
                throw "MiniDumpWriteDump failed: Win32 error $win32Error"
            }
        }
        finally { $stream.Dispose() }

        Write-Warning "Native GUI hang minidump (private, opt-in): $dumpPath"
        Write-Warning 'Review locally with WinDbg; minidumps can contain private stack data.'
    }
    catch {
        # Do not leave partial dumps that appear valid but cannot be analyzed.
        if (Test-Path -LiteralPath $dumpPath -PathType Leaf) {
            Remove-Item -LiteralPath $dumpPath -Force -ErrorAction SilentlyContinue
        }
        Write-Warning "Native GUI hang minidump unavailable: $($_.Exception.Message)"
    }
}

function Save-FailureScreenshot {
    try {
        # Save only the app window; other desktop windows may contain private data.
        if ($null -eq $process -or $process.HasExited) { return }
        $shotWindow = [SalamanderGuiNative]::GetForegroundWindow()
        [uint32]$ownerPid = 0
        [void][SalamanderGuiNative]::GetWindowThreadProcessId($shotWindow, [ref]$ownerPid)
        if ($ownerPid -ne [uint32]$process.Id) { return }
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
            # Store evidence outside the GUID-scoped directory because the
            # F8 deletion regression cleans that directory even on failure.
            $file = Join-Path ([IO.Path]::GetTempPath()) (
                [IO.Path]::GetFileName($root) + '-gui-failure.png')
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
    if ($LegacyFindScenario -eq 'NearLimit') {
        . (Join-Path $PSScriptRoot 'LegacyFind-GuiCases.ps1')
        $legacyNearLimitRoot = [IO.Directory]::CreateDirectory((Join-Path $root 'find')).FullName
        $legacyNearLimitFile = New-LegacyFindNearLimitFixture -SearchRoot $legacyNearLimitRoot
    }
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
        [IO.File]::SetLastWriteTime($findUtf8Path, [datetime]::new(2024, 2, 28, 23, 59, 0))
        [IO.File]::SetLastWriteTime($findUtf16Path, [datetime]::new(2024, 2, 29, 23, 59, 0))
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

        # The originally reported leftover directories have ASCII GUID names,
        # although their children may contain Unicode or exceed MAX_PATH.
        $asciiTemporaryName = 'OpenSal-GuiLong-' + [guid]::NewGuid().ToString('N')
        $asciiTemporaryDirectory = Join-Path $source $asciiTemporaryName
        $asciiChild = $asciiTemporaryDirectory
        foreach ($index in 1..4) {
            $asciiChild = Join-Path $asciiChild (
                'nested-' + $index + '-' + ('y' * 64))
            [void][IO.Directory]::CreateDirectory($asciiChild)
        }
        $asciiLeaf = Join-Path $asciiChild 'Datei_大阪_😀.dat'
        [IO.File]::WriteAllBytes($asciiLeaf, $payload)
        Assert-True ($asciiLeaf.Length -gt 260) 'ASCII temporary root contains a real Unicode long-path descendant'
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
    if (-not $BaselineOnly -and -not $ShortOperationsOnly -and -not $LegacyFindScenario -and
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
        -not $UnicodeFindOnly -and -not $LegacyFindScenario -and -not $MaximumPathOnly -and
        -not $LargeUnicodeCopyOnly -and
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
        $boundaryDirectoryNames = @(Get-BoundaryDirectoryNames -ParentPath $source)
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

    if ($LargeUnicodeCopyOnly) {
        # Arrange: bounded, deterministic payload in this test's private tree.
        $largeCopySourceDirectory = $source
        $largeCopyTargetDirectory = $destination
        foreach ($level in 1..3) {
            $prefix = if ($UnicodeParentDirectories) { '東京_😀-' } else { 'large-copy-' }
            $component = $prefix + $level + '-' + ('x' * 55)
            $largeCopySourceDirectory = Join-Path $largeCopySourceDirectory $component
            $largeCopyTargetDirectory = Join-Path $largeCopyTargetDirectory $component
        }
        [void][IO.Directory]::CreateDirectory($largeCopySourceDirectory)
        [void][IO.Directory]::CreateDirectory($largeCopyTargetDirectory)
        $largeCopySourceFile = Join-Path $largeCopySourceDirectory $utfName
        $largeCopyTargetFile = Join-Path $largeCopyTargetDirectory $utfName
        $chunk = [Text.Encoding]::UTF8.GetBytes(('Large-copy-東京-😀-' * 16384))
        $stream = [IO.File]::Create($largeCopySourceFile)
        try {
            $remaining = 32MB
            while ($remaining -gt 0) {
                $count = [Math]::Min($remaining, $chunk.Length)
                $stream.Write($chunk, 0, $count)
                $remaining -= $count
            }
        }
        finally { $stream.Dispose() }
        $largeCopyHash = (Get-FileHash -LiteralPath $largeCopySourceFile -Algorithm SHA256).Hash
        $largeCopyAdsBytes = [Text.Encoding]::UTF8.GetBytes('Exact-ADS-東京-😀')
        [IO.File]::WriteAllBytes($largeCopySourceFile + ':識別_😀', $largeCopyAdsBytes)
        [IO.File]::SetLastWriteTimeUtc($largeCopySourceFile, [DateTime]::new(2020, 1, 2, 3, 4, 6, [DateTimeKind]::Utc))
        $largeCopyLastWrite = [IO.File]::GetLastWriteTimeUtc($largeCopySourceFile)
        [IO.File]::SetAttributes($largeCopySourceFile, [IO.FileAttributes]::ReadOnly -bor [IO.FileAttributes]::Archive)
        if ($LargeUnicodeCopyCase -eq 'Collision') {
            [IO.File]::WriteAllBytes($largeCopyTargetFile, [Text.Encoding]::UTF8.GetBytes('EXISTING-TARGET-MUST-SURVIVE'))
            $largeCopyCollisionHash = (Get-FileHash -LiteralPath $largeCopyTargetFile -Algorithm SHA256).Hash
        }
        if ($LargeUnicodeCopyCase -eq 'LockedSource') {
            $largeCopyLock = [IO.FileStream]::new($largeCopySourceFile, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
        }
        Assert-True (($largeCopySourceFile.Length -gt 260) -and
            ($largeCopyTargetFile.Length -gt 260) -and
            ([IO.FileInfo]::new($largeCopySourceFile).Length -eq 32MB)) '32-MiB fixture uses long Unicode source and destination'
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
    if ($LargeUnicodeCopyOnly) {
        $startupArgs = '-l "{0}" -r "{1}" -p 2' -f $largeCopyTargetDirectory, $source
    }
    # The first Salamander instance searches %TEMP% for SAL*.tmp left by
    # previous sessions. A test must neither prompt about nor delete files
    # belonging to the user or an earlier application run.
    $processTemp = Join-Path $root 'process-temp'
    if ($processTemp.Length -ge 240) {
        throw 'GUI test TEMP path is too long for native Salamander disk-cache paths.'
    }
    [void][IO.Directory]::CreateDirectory($processTemp)
    if ($IsolatedConfiguration) {
        Initialize-IsolatedGuiConfiguration
        if ($LegacyFindScenario -in 'Baseline','UnicodeRootIgnore') {
            . (Join-Path $PSScriptRoot 'LegacyFind-GuiCases.ps1')
            Initialize-LegacyFindBaseline
        }
        if ($LegacyFindScenario -eq 'ExternalEditor') {
            . (Join-Path $PSScriptRoot 'LegacyFind-GuiCases.ps1')
            Initialize-LegacyFindExternalEditor
        }
        if ($LegacyFindScenario -eq 'Cancel') {
            $prefix = 'Local\OpenSalamander.FindTest.' + $testConfigurationId
            $created = $false
            $findTestReached = [Threading.EventWaitHandle]::new($false, 'ManualReset', "$prefix.reached", [ref]$created)
            if (-not $created) { throw 'Refusing to reuse an existing Find checkpoint.' }
            $findTestCancelled = [Threading.EventWaitHandle]::new($false, 'ManualReset', "$prefix.cancelled", [ref]$created)
            if (-not $created) { throw 'Refusing to reuse an existing Find cancellation event.' }
        }
        if ($LargeUnicodeCopyOnly) {
            $eventPrefix = 'Local\OpenSalamander.CopyTest.' + $testConfigurationId
            $created = $false
            $copyTestReached = [Threading.EventWaitHandle]::new($false, [Threading.EventResetMode]::ManualReset, $eventPrefix + '.reached', [ref]$created)
            if (-not $created) { throw 'Refusing to reuse an existing copy test checkpoint.' }
            $copyTestContinue = [Threading.EventWaitHandle]::new($false, [Threading.EventResetMode]::ManualReset, $eventPrefix + '.continue', [ref]$created)
            if (-not $created) { throw 'Refusing to reuse an existing copy test continuation.' }
        }
        $process = Start-Process -FilePath $SalamanderExe -ArgumentList $startupArgs `
            -WorkingDirectory (Split-Path -Parent $SalamanderExe) `
            -Environment @{
                TEMP = $processTemp; TMP = $processTemp; OPENSAL_GUI_TEST_ID = $testConfigurationId
                OPENSAL_GUI_COPY_TEST_GATE = $(if ($LargeUnicodeCopyOnly) { '1' } else { '0' })
                OPENSAL_GUI_FIND_TEST_GATE = $(if ($LegacyFindScenario -eq 'Cancel') { '1' } else { '0' })
            } -PassThru
    }
    else {
        $process = Start-Process -FilePath $SalamanderExe -ArgumentList $startupArgs `
            -WorkingDirectory (Split-Path -Parent $SalamanderExe) `
            -Environment @{ TEMP = $processTemp; TMP = $processTemp } -PassThru
    }
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
        } 'visible SalamanderMainWindowVer25 main-class HWND owned by launched process' -TimeoutSecondsOverride $StartupReadyTimeoutSeconds
        if ($IsolatedConfiguration) {
            Wait-Until {
                $process.Refresh()
                if ($process.HasExited) {
                    throw "Salamander exited during isolated startup upgrade (exit code $($process.ExitCode))."
                }
                $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($testConfigurationKey + '\Config0\Version')
                if ($null -eq $key) { return $false }
                try { $version = [int]$key.GetValue('Configuration', 0) }
                finally { $key.Dispose() }
                if ($version -le 59) { return $false }

                # SaveConfig writes the version before it finishes saving.
                $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($testConfigurationKey + '\Config0')
                if ($null -eq $key) { return $false }
                try { $saving = $null -ne $key.GetValue('Save In Progress', $null) }
                finally { $key.Dispose() }
                return -not $saving -and [SalamanderGuiNative]::IsWindowEnabled($mainWindowHandle)
            } 'Salamander saved its upgraded isolated configuration and enabled its main window' -TimeoutSecondsOverride $StartupReadyTimeoutSeconds
            Write-Host 'PASS: Salamander upgraded its GUID-scoped isolated configuration'
        }
    }
    catch {
        $startupFailure = $_.Exception.Message
        $process.Refresh()
        $windowSummary = Get-ProcessWindowSummary -OwnerProcessId ([uint32]$process.Id)
        $startupWindow = $mainWindowHandle
        if ($startupWindow -eq [IntPtr]::Zero) { $startupWindow = $process.MainWindowHandle }
        [uint32]$startupOwner = 0
        $startupThread = [SalamanderGuiNative]::GetWindowThreadProcessId($startupWindow, [ref]$startupOwner)
        $startupWaitChain = '<no verified startup window>'
        if ($startupOwner -eq [uint32]$process.Id) {
            try { $startupWaitChain = [SalamanderGuiWaitChain]::Describe($startupThread) }
            catch { $startupWaitChain = 'unavailable: ' + $_.Exception.Message }
        }
        $startupMessage = (("GUI startup failed: {0}; launched PID={1}; .NET MainWindowHandle=0x{2:X}; " +
            ".NET title='{3}'; process windows: {4}; startup wait chain: {5}") -f
            $startupFailure, $process.Id, $process.MainWindowHandle.ToInt64(),
            $process.MainWindowTitle, $windowSummary, $startupWaitChain)
        throw ($startupMessage + "; isolated startup: $(Get-IsolatedStartupDiagnostics)")
    }
    # A visible top-level window is not evidence that startup has finished.
    # The isolated upgrade gate above and the HWND probe below establish
    # readiness without relying on the process-wide input-idle result.
    if (-not $IsolatedConfiguration -and -not $process.WaitForInputIdle(10000)) {
        [uint32]$windowOwner = 0
        $windowThread = [SalamanderGuiNative]::GetWindowThreadProcessId(
            $mainWindowHandle, [ref]$windowOwner)
        $waitChain = '<not collected>'
        try { $waitChain = [SalamanderGuiWaitChain]::Describe([uint32]$windowThread) }
        catch { $waitChain = "WCT unavailable: $($_.Exception.Message)" }
        $windowSummary = Get-ProcessWindowSummary -OwnerProcessId ([uint32]$process.Id)
        throw ("Test Salamander did not become input-idle within 10 seconds; " +
               "PID={0}; GUI thread={1}; windows=[{2}]; wait chain=[{3}]. " +
               "No GUI input was sent." -f
               $process.Id, $windowThread, $windowSummary, $waitChain)
    }
    Wait-ForGuiResponsive
    Wait-ForGuiTitle
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
    if ($LegacyFindScenario) {
        . (Join-Path $PSScriptRoot 'LegacyFind-GuiCases.ps1')
        Test-LegacyFindGui -Scenario $LegacyFindScenario
        $passed = $true
        return
    }
    $backgroundCommandsOnly = $TemporaryDirectoryDeletionOnly -or $LargeUnicodeCopyOnly -or $UnicodeFindOnly
    if (-not $backgroundCommandsOnly) { Focus-TestProcess }

    # First validate the GUI driver against a normal short path. If this
    # fails, treat it as an automation/infrastructure problem, NOT as proof
    # that the application lacks long-path support.
    Go-ToPath $source -NoForeground:$backgroundCommandsOnly
    if (-not $backgroundCommandsOnly) {
        Restore-FilePanelFocus -ExpectedPath $source
    }
    # Go-ToPath already verified the observed panel path. A duplicate
    # WM_COMMAND 711 adds no coverage and can race with GUI processing.
    Write-Host 'PASS: GUI driver can navigate a normal short directory'
    if ($TemporaryDirectoryDeletionOnly) {
        # Act: exercise Salamander's actual F8 deletion command handler
        # (CM_DELETEFILES) through its verified HWND, without global focus.
        # The F8 accelerator binding is covered by separate keyboard tests.
        Assert-True ((Read-PanelPath) -ceq $source) 'Disposable parent panel verified before F8 directory delete'
        Focus-DirectoryRow -Name $temporaryDirectoryName -VerifiedBackground
        Assert-True ((Read-FocusedFilename -AllowVerifiedBackground) -ceq $temporaryDirectoryName) 'Exact temporary directory selected for F8'
        [SalamanderGuiNative]::PostVerifiedDirectoryDeleteCommand(
            $mainWindowHandle, [uint32]$process.Id)
        Confirm-DirectoryDeleteDialog -ExpectedName $temporaryDirectoryName
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
        # Assert sibling integrity *before* any further GUI operation. If the
        # first F8 deleted the wrong subtree, this must fail as a data-loss
        # regression rather than being misdiagnosed as a missing panel row.
        Assert-True ([IO.Directory]::Exists($asciiTemporaryDirectory)) 'ASCII temporary sibling survives Unicode folder F8'
        Assert-True (Test-Content $asciiLeaf) 'ASCII temporary sibling retains deep Unicode file bytes'
        Wait-ForCompletedDirectoryDelete -DeletedDirectory $temporaryDirectory

        # The native directory-delete handler posts an asynchronous refresh.
        # Force a verified, non-destructive parent/source navigation roundtrip
        # so that the second folder selection reads a freshly enumerated
        # panel, rather than racing a pending notification from the first F8.
        Go-ToPath $root -NoForeground
        Go-ToPath $source -NoForeground
        Assert-True ((Read-PanelPath) -ceq $source) 'Source panel reloaded after first F8 directory deletion'

        # Repeat with the original OpenSal-GuiLong-<GUID> naming scheme,
        # for which only descendants—not the selected directory name—are risky.
        Focus-DirectoryRow -Name $asciiTemporaryName -VerifiedBackground
        Assert-True ((Read-FocusedFilename -AllowVerifiedBackground) -ceq $asciiTemporaryName) 'Exact ASCII temporary root selected for F8'
        [SalamanderGuiNative]::PostVerifiedDirectoryDeleteCommand(
            $mainWindowHandle, [uint32]$process.Id)
        Confirm-DirectoryDeleteDialog -ExpectedName $asciiTemporaryName
        Wait-Until { -not [IO.Directory]::Exists($asciiTemporaryDirectory) } 'F8 deletes ASCII temp root with Unicode long descendants'
        Wait-ForCompletedDirectoryDelete -DeletedDirectory $asciiTemporaryDirectory
        Assert-True (Test-Content $unicodeShortFile) 'Other files remain intact after ASCII temporary root deletion'
        $passed = $true
        Write-Host 'PASS: Salamander F8 recursively deleted the real long-path temporary directory (CM_DELETEFILES handler; physical F8 key not tested here).'
        return
    }
    if ($UnicodeFindOnly) {
        Test-UnicodeFindGui
        $passed = $true
        return
    }
    if ($LargeUnicodeCopyOnly) {
        Test-LargeUnicodeCopy
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
        Send-Keys '{F2}'
        $quickRename = @{ Window = [IntPtr]::Zero }
        Wait-Until {
            $quickRename.Window = [SalamanderGuiNative]::FindVerifiedQuickRenameDialog(
                $mainWindowHandle, [uint32]$process.Id, $asciiName)
            return $quickRename.Window -ne [IntPtr]::Zero
        } 'owned Quick Rename dialog for exact ASCII fixture'
        [SalamanderGuiNative]::ConfirmVerifiedQuickRename(
            $mainWindowHandle, [uint32]$process.Id, $quickRename.Window,
            $asciiName, $asciiRenamedName)
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

    $clipboardName = 'clipboard-東京-😀.txt'
    $clipboardSource = Join-Path $destination $clipboardName
    $clipboardTarget = Join-Path $deep $clipboardName
    [IO.File]::WriteAllBytes($clipboardSource, $payload)
    Go-ToPath $deep
    Restore-FilePanelFocus -ExpectedPath $deep
    $script:clipboardOwner.SetFileDrop($clipboardSource)
    Send-Keys '^v'
    Wait-Until {
        $dialog = Get-TestDialog
        if ($dialog) { throw "Unicode clipboard paste displayed an error: $dialog" }
        (Test-Content $clipboardTarget) -and (Test-Content $clipboardSource)
    } 'CF_HDROP copies a Unicode filename into a long panel path without changing the source'

    $cutName = 'clipboard-cut-大阪-😀.txt'
    $cutSource = Join-Path $destination $cutName
    $cutTarget = Join-Path $deep $cutName
    [IO.File]::WriteAllBytes($cutSource, $payload)
    Restore-FilePanelFocus -ExpectedPath $deep
    $script:clipboardOwner.SetFileDrop($cutSource, $true)
    Send-Keys '^v'
    Wait-Until {
        $dialog = Get-TestDialog
        if ($dialog) { throw "Unicode clipboard move displayed an error: $dialog" }
        (Test-Content $cutTarget) -and -not [IO.File]::Exists($cutSource)
    } 'CF_HDROP moves a cut Unicode file into a long same-volume path without changing its bytes'

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
    $primaryGuiFailure = $_.Exception.Message
    Save-FailureScreenshot
    # A dump is never collected unless explicitly requested. Only inspect
    # this test's process, and only when Windows detects a hung GUI window.
    if ($null -ne $process) {
        $process.Refresh()
        if (-not $process.HasExited) {
            $startupFailure = $primaryGuiFailure -like 'GUI startup failed:*'
            if ($startupFailure -or
                ($mainWindowHandle -ne [IntPtr]::Zero -and
                 [SalamanderGuiNative]::IsHungAppWindow($mainWindowHandle))) {
                # Explicit opt-in also covers startup stalls with no main HWND.
                Save-GuiHangMiniDump
            }
        }
    }
    throw
}
finally {
    if ($null -ne $copyTestContinue) { [void]$copyTestContinue.Set() }
    if ($null -ne $process) {
        $testConfigurationCleanupAllowed = $false
        try {
            $process.Refresh()
            $testConfigurationCleanupAllowed = $process.HasExited
            if (-not $process.HasExited) {
                # CloseMainWindow invokes Salamander's SaveConfig, persisting
                # paths into the soon-to-be-deleted disposable fixture and
                # overwriting the user's saved panel paths. The process belongs
                # exclusively to this test; terminate it without invoking that
                # normal configuration-save path.
                $process.Kill()
                $testConfigurationCleanupAllowed = $process.WaitForExit(10000)
                if (-not $testConfigurationCleanupAllowed) {
                    Write-Warning "Test Salamander PID $($process.Id) did not exit after termination."
                }
            }
        }
        catch { Write-Warning "Could not stop isolated test app: $($_.Exception.Message)" }
        $process.Dispose()
    }
    if ($null -ne $largeCopyLock) { $largeCopyLock.Dispose() }
    if ($null -ne $copyTestReached) { $copyTestReached.Dispose() }
    if ($null -ne $copyTestContinue) { $copyTestContinue.Dispose() }
    if ($null -ne $findTestReached) { $findTestReached.Dispose() }
    if ($null -ne $findTestCancelled) { $findTestCancelled.Dispose() }

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
    # An empty original clipboard is a valid captured state. Unlike the old
    # truthiness check, restore it to empty after tests wrote clipboard data.
    # A failed snapshot must never be misinterpreted as "originally empty".
    if ($clipboardSnapshotValid -and $script:clipboardTouched) {
        try {
            if ($null -ne $nativeClipboardSnapshot) {
                $restored = $false
                for ($attempt = 0; $attempt -lt 3; ++$attempt) {
                    try {
                        $nativeClipboardSnapshot.Restore()
                        $restored = $true
                        break
                    }
                    catch { if ($attempt -eq 2) { throw } }
                }
                if (-not $restored) { throw 'Native clipboard restoration did not complete.' }
                Write-Host 'PASS: Native clipboard snapshot restored'
            }
            elseif ($null -eq $oldClipboard) {
                [Windows.Forms.Clipboard]::Clear()
            }
            else {
                [Windows.Forms.Clipboard]::SetDataObject($oldClipboard, $true)
            }
        }
        catch {
            $clipboardRestorationFailed = $true
            Write-Warning "Original clipboard could not be restored: $($_.Exception.Message)"
        }
    }
    if ($null -ne $script:clipboardOwner) {
        try { $script:clipboardOwner.Dispose() }
        catch { Write-Warning "Clipboard owner shutdown failed: $($_.Exception.Message)" }
    }
    if ($null -ne $nativeClipboardSnapshot) { $nativeClipboardSnapshot.Dispose() }
    if ($IsolatedConfiguration -and $testConfigurationCleanupAllowed -and
        $testConfigurationKey -cmatch '^Software\\Open Salamander\\CodexTests\\[0-9a-f]{32}$') {
        [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($testConfigurationKey, $false)
    }
    if ($IsolatedConfiguration -and -not $testConfigurationCleanupAllowed) {
        $passed = $false
        $KeepFixture = $true
    }
    # A failed F8 regression must not leave another GUID-owned temp tree.
    if (($passed -or $TemporaryDirectoryDeletionOnly) -and -not $KeepFixture) {
        try {
            if ($LargeUnicodeCopyOnly) {
                foreach ($path in @($largeCopySourceFile, $largeCopyTargetFile)) {
                    if (-not [string]::IsNullOrEmpty($path) -and
                        [IO.Path]::GetFullPath($path).StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase) -and
                        [IO.File]::Exists($path)) {
                        [IO.File]::SetAttributes($path, [IO.FileAttributes]::Normal)
                    }
                }
            }
            [IO.Directory]::Delete($root, $true)
        }
        catch { Write-Warning "Test fixture cleanup failed: $root - $($_.Exception.Message)" }
    }
    else {
        Write-Host "Diagnostic fixture retained: $root"
    }
    if ($IsolatedConfiguration -and ($clipboardRestorationFailed -or -not $testConfigurationCleanupAllowed)) {
        throw ('Isolated GUI cleanup failed; acceptance cannot be reported as passed. Primary GUI failure: ' + $primaryGuiFailure)
    }
}
