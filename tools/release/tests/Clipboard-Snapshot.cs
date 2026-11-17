// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Threading;

// Owns native copies rather than delayed OLE IDataObject references. Capture
// never empties the clipboard. Unsupported owner/private GDI formats fail
// before a GUI test can change it. No clipboard contents are logged or saved.
public sealed class SalamanderClipboardSnapshot : IDisposable
{
    private sealed class Entry
    {
        public uint Format;
        public IntPtr Handle;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Medium
    {
        public int Type;
        public IntPtr Handle;
        public IntPtr Release;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool OpenClipboard(IntPtr owner);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool CloseClipboard();
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool EmptyClipboard();
    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint EnumClipboardFormats(uint format);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr GetClipboardData(uint format);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetClipboardData(uint format, IntPtr handle);
    [DllImport("kernel32.dll", ExactSpelling = true)]
    private static extern void SetLastError(uint error);
    [DllImport("ole32.dll")]
    private static extern IntPtr OleDuplicateData(IntPtr source, ushort format, uint flags);
    [DllImport("ole32.dll")]
    private static extern void ReleaseStgMedium(ref Medium medium);
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CopyEnhMetaFileW(IntPtr source, string filename);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateWindowExW(uint extendedStyle, string className,
        string title, uint style, int x, int y, int width, int height,
        IntPtr parent, IntPtr menu, IntPtr instance, IntPtr parameter);
    [DllImport("user32.dll")]
    private static extern bool DestroyWindow(IntPtr window);

    private readonly List<Entry> entries = new List<Entry>();
    private IntPtr window;
    private bool disposed;
    public int FormatCount { get { return entries.Count; } }

    private static void Acquire(IntPtr owner)
    {
        for (int attempt = 0; attempt < 16; ++attempt)
        {
            if (OpenClipboard(owner)) return;
            int error = Marshal.GetLastWin32Error();
            if (error != 5 || attempt == 15)
                throw new Win32Exception(error, "Cannot acquire clipboard for snapshot/restore.");
            Thread.Sleep(75);
        }
    }

    private static IntPtr Duplicate(uint format, IntPtr source)
    {
        if (format == 0x80 || (format >= 0x300 && format <= 0x3ff))
            throw new InvalidOperationException("Clipboard contains an unsupported owner/private GDI format.");
        IntPtr copy;
        if (format == 14 || format == 0x8e)
            copy = CopyEnhMetaFileW(source, null);
        else
        {
            uint nativeFormat = format == 0x82 ? 2u : format == 0x83 ? 3u : format;
            copy = OleDuplicateData(source, checked((ushort)nativeFormat), 0);
        }
        if (copy == IntPtr.Zero)
            throw new InvalidOperationException("Cannot duplicate a native clipboard format.");
        return copy;
    }

    private static void Free(Entry entry)
    {
        if (entry.Handle == IntPtr.Zero) return;
        int type = entry.Format == 2 || entry.Format == 9 || entry.Format == 0x82 ? 16 :
            entry.Format == 3 || entry.Format == 0x83 ? 32 :
            entry.Format == 14 || entry.Format == 0x8e ? 64 : 1;
        Medium medium = new Medium { Type = type, Handle = entry.Handle, Release = IntPtr.Zero };
        ReleaseStgMedium(ref medium);
        entry.Handle = IntPtr.Zero;
    }

    public static SalamanderClipboardSnapshot Capture()
    {
        var snapshot = new SalamanderClipboardSnapshot();
        try
        {
            // A message-only window gives restoration a valid clipboard owner.
            snapshot.window = CreateWindowExW(0, "STATIC", "", 0, 0, 0, 0, 0,
                new IntPtr(-3), IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
            if (snapshot.window == IntPtr.Zero)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot create snapshot owner.");
            Acquire(IntPtr.Zero);
            try
            {
                uint format = 0;
                for (;;)
                {
                    SetLastError(0);
                    format = EnumClipboardFormats(format);
                    if (format == 0)
                    {
                        int error = Marshal.GetLastWin32Error();
                        if (error != 0) throw new Win32Exception(error, "Cannot enumerate clipboard formats.");
                        break;
                    }
                    IntPtr source = GetClipboardData(format);
                    if (source == IntPtr.Zero)
                        throw new InvalidOperationException("A clipboard format could not be rendered for capture.");
                    var entry = new Entry { Format = format, Handle = Duplicate(format, source) };
                    try { snapshot.entries.Add(entry); }
                    catch { Free(entry); throw; }
                }
            }
            finally { CloseClipboard(); }
            return snapshot;
        }
        catch { snapshot.Dispose(); throw; }
    }

    public void Restore()
    {
        if (disposed) throw new ObjectDisposedException("SalamanderClipboardSnapshot");
        // Retain the originals so a failed restoration can be retried. Prepare
        // every transferable copy before EmptyClipboard changes any data.
        var copies = new List<Entry>();
        try
        {
            foreach (Entry original in entries)
            {
                var entry = new Entry { Format = original.Format, Handle = Duplicate(original.Format, original.Handle) };
                try { copies.Add(entry); }
                catch { Free(entry); throw; }
            }
            Acquire(window);
            try
            {
                if (!EmptyClipboard()) throw new Win32Exception(Marshal.GetLastWin32Error());
                foreach (Entry entry in copies)
                {
                    if (SetClipboardData(entry.Format, entry.Handle) == IntPtr.Zero)
                        throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot restore clipboard format.");
                    entry.Handle = IntPtr.Zero; // Windows now owns this copy.
                }
            }
            finally { CloseClipboard(); }
        }
        finally { foreach (Entry entry in copies) Free(entry); }
    }

    public void Dispose()
    {
        if (disposed) return;
        foreach (Entry entry in entries) Free(entry);
        entries.Clear();
        if (window != IntPtr.Zero) DestroyWindow(window);
        window = IntPtr.Zero;
        disposed = true;
    }
}
