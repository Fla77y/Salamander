#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
# Independent expectations; actual Renamer SPL, native dialog and disk operations.
# No product source is reimplemented and no live user file is selected.
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class RenamerHostNative
{
    private delegate bool EnumProc(IntPtr hwnd, IntPtr arg);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc callback, IntPtr arg);
    [DllImport("user32.dll")] private static extern bool EnumChildWindows(IntPtr hwnd, EnumProc callback, IntPtr arg);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] private static extern IntPtr GetDlgItem(IntPtr hwnd, int id);
    [DllImport("user32.dll")] private static extern IntPtr GetParent(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr hwnd);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="GetClassNameW")]
    private static extern int GetClassName(IntPtr hwnd, StringBuilder name, int size);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="SendMessageTimeoutW")]
    private static extern IntPtr ReadText(IntPtr hwnd, uint msg, UIntPtr w, StringBuilder text, uint flags, uint timeout, out UIntPtr result);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="SendMessageTimeoutW")]
    private static extern IntPtr WriteText(IntPtr hwnd, uint msg, UIntPtr w, string text, uint flags, uint timeout, out UIntPtr result);
    [DllImport("user32.dll", EntryPoint="SendMessageTimeoutW")]
    private static extern IntPtr SendNumber(IntPtr hwnd, uint msg, UIntPtr w, IntPtr l, uint flags, uint timeout, out UIntPtr result);
    [DllImport("user32.dll", EntryPoint="PostMessageW", SetLastError=true)]
    private static extern bool PostMessage(IntPtr hwnd, uint msg, IntPtr w, IntPtr l);
    private const uint Flags = 0x23;
    private static bool Owned(IntPtr hwnd, uint pid)
    {
        uint actual;
        return hwnd != IntPtr.Zero && GetWindowThreadProcessId(hwnd, out actual) != 0 && actual == pid;
    }
    private static bool ClassIs(IntPtr hwnd, string cls)
    {
        var b = new StringBuilder(128);
        return GetClassName(hwnd, b, b.Capacity) > 0 && String.Equals(b.ToString(), cls, StringComparison.OrdinalIgnoreCase);
    }
    private static string Text(IntPtr hwnd)
    {
        var b = new StringBuilder(4096);
        UIntPtr result;
        if (ReadText(hwnd, 0xD, new UIntPtr(4096), b, Flags, 1500, out result) == IntPtr.Zero)
            throw new InvalidOperationException("Renamer control text timeout.");
        return b.ToString();
    }
    private static IntPtr Control(IntPtr dlg, uint pid, int id, string cls)
    {
        var hwnd = GetDlgItem(dlg, id);
        return Owned(hwnd,pid) && GetParent(hwnd)==dlg && ClassIs(hwnd,cls) ? hwnd : IntPtr.Zero;
    }
    private static bool Match(IntPtr dlg, uint pid)
    {
        return Owned(dlg,pid) && IsWindowVisible(dlg) && ClassIs(dlg,"#32770") &&
            Text(dlg)=="Batch Rename" && Control(dlg,pid,104,"SysListView32")!=IntPtr.Zero &&
            Control(dlg,pid,106,"ComboBox")!=IntPtr.Zero && Control(dlg,pid,108,"ComboBox")!=IntPtr.Zero &&
            Control(dlg,pid,109,"ComboBox")!=IntPtr.Zero && Control(dlg,pid,1,"Button")!=IntPtr.Zero;
    }
    public static IntPtr Find(uint pid)
    {
        var windows = new List<IntPtr>();
        if (!EnumWindows((hwnd,arg)=> { if (Owned(hwnd,pid) && IsWindowVisible(hwnd) && ClassIs(hwnd,"#32770")) windows.Add(hwnd); return true; },IntPtr.Zero))
            throw new InvalidOperationException("Renamer window enumeration failed.");
        IntPtr found=IntPtr.Zero;
        foreach(var hwnd in windows)
        {
            if(!Match(hwnd,pid)) continue;
            if(found!=IntPtr.Zero) throw new InvalidOperationException("Ambiguous Batch Rename window.");
            found=hwnd;
        }
        return found;
    }
    private static void Require(IntPtr dlg,uint pid)
    {
        if(!Match(dlg,pid) || !IsWindowEnabled(dlg)) throw new InvalidOperationException("Renamer window no longer verified and enabled.");
    }
    private static IntPtr RequiredControl(IntPtr dlg,uint pid,int id,string cls)
    {
        Require(dlg,pid);
        var hwnd=Control(dlg,pid,id,cls);
        if(hwnd==IntPtr.Zero || !IsWindowVisible(hwnd) || !IsWindowEnabled(hwnd))
            throw new InvalidOperationException("Missing or disabled Renamer control "+id);
        return hwnd;
    }
    private static ulong Number(IntPtr hwnd,uint msg,uint w,IntPtr l)
    {
        UIntPtr result;
        if(SendNumber(hwnd,msg,new UIntPtr(w),l,Flags,2500,out result)==IntPtr.Zero)
            throw new InvalidOperationException("Renamer native command timeout.");
        return result.ToUInt64();
    }
    private static void Notify(IntPtr dlg,uint pid,int id,int code,IntPtr ctrl)
    {
        Require(dlg,pid);
        Number(dlg,0x111,(uint)id|((uint)code<<16),ctrl);
    }
    private static void SetText(IntPtr hwnd,string text)
    {
        UIntPtr result;
        if(WriteText(hwnd,0xC,UIntPtr.Zero,text,Flags,2500,out result)==IntPtr.Zero || result==UIntPtr.Zero || Text(hwnd)!=text)
            throw new InvalidOperationException("Renamer control rejected exact text.");
    }
    public static void Combo(IntPtr dlg,uint pid,int id,string text)
    {
        var hwnd=RequiredControl(dlg,pid,id,"ComboBox");
        SetText(hwnd,text);
        Notify(dlg,pid,id,5,hwnd); // CBN_EDITCHANGE
    }
    public static void Check(IntPtr dlg,uint pid,int id,bool state)
    {
        var hwnd=RequiredControl(dlg,pid,id,"Button");
        Number(hwnd,0xF1,state?1u:0u,IntPtr.Zero);
        if(Number(hwnd,0xF0,0,IntPtr.Zero)!=(state?1u:0u)) throw new InvalidOperationException("Renamer checkbox state mismatch.");
        Notify(dlg,pid,id,0,hwnd);
    }
    public static void Case(IntPtr dlg,uint pid,int id,uint index)
    {
        var hwnd=RequiredControl(dlg,pid,id,"ComboBox");
        if(Number(hwnd,0x14E,index,IntPtr.Zero)!=index || Number(hwnd,0x147,0,IntPtr.Zero)!=index)
            throw new InvalidOperationException("Renamer case selection failed.");
        Notify(dlg,pid,id,9,hwnd); // CBN_SELENDOK
    }
    public static void Manual(IntPtr dlg,uint pid,string text)
    {
        var hwnd=RequiredControl(dlg,pid,125,"Edit");
        SetText(hwnd,text);
        Notify(dlg,pid,125,0x300,hwnd); // EN_CHANGE
    }
    public static string ReadManual(IntPtr dlg,uint pid)
    {
        return Text(RequiredControl(dlg,pid,125,"Edit"));
    }
    public static IntPtr Preview(IntPtr dlg,uint pid)
    {
        return RequiredControl(dlg,pid,104,"SysListView32");
    }
    public static int Count(IntPtr dlg,uint pid)
    {
        return checked((int)Number(Preview(dlg,pid),0x1004,0,IntPtr.Zero)); // LVM_GETITEMCOUNT
    }

    // LVM_GETITEMTEXT is unsupported for LVS_OWNERDATA. LVM_GETITEMW
    // requests LVIF_TEXT from the real control, including its owner callback.
    // Messages above WM_USER are not marshalled by USER32.
    [StructLayout(LayoutKind.Sequential)]
    private struct ListItem
    {
        public uint mask;
        public int item, subItem;
        public uint state, stateMask;
        public IntPtr text;
        public int textMax, image;
        public IntPtr param;
        public int indent, groupId;
        public uint columns;
        public IntPtr columnIndices, columnFormats;
        public int group;
    }
    [DllImport("kernel32.dll", SetLastError=true)] private static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
    [DllImport("kernel32.dll", SetLastError=true)] private static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll", SetLastError=true)] private static extern bool IsWow64Process2(IntPtr handle, out ushort processMachine, out ushort nativeMachine);
    [DllImport("kernel32.dll", SetLastError=true)] private static extern IntPtr VirtualAllocEx(IntPtr handle, IntPtr address, UIntPtr size, uint allocation, uint protection);
    [DllImport("kernel32.dll", SetLastError=true)] private static extern bool VirtualFreeEx(IntPtr handle, IntPtr address, UIntPtr size, uint freeType);
    [DllImport("kernel32.dll", SetLastError=true)] private static extern bool WriteProcessMemory(IntPtr handle, IntPtr address, byte[] bytes, UIntPtr size, out UIntPtr written);
    [DllImport("kernel32.dll", SetLastError=true)] private static extern bool ReadProcessMemory(IntPtr handle, IntPtr address, byte[] bytes, UIntPtr size, out UIntPtr read);

    public static string[][] ReadPreview(IntPtr dlg, uint pid, int expectedCount)
    {
        const int chars = 4096;
        var hwnd = Preview(dlg,pid);
        if (expectedCount < 0 || Count(dlg,pid) != expectedCount) return null;
        var header = new IntPtr(checked((long)Number(hwnd,0x101F,0,IntPtr.Zero))); // LVM_GETHEADER
        if (!Owned(header,pid) || GetParent(header)!=hwnd || !ClassIs(header,"SysHeader32") ||
            Number(header,0x1200,0,IntPtr.Zero)<6) // HDM_GETITEMCOUNT
            throw new InvalidOperationException("Renamer preview column identity not verified.");
        if (IntPtr.Size!=8) throw new InvalidOperationException("Renamer preview reader requires x64 test host.");
        var handle = OpenProcess(0x1038,false,pid); // QUERY_LIMITED_INFORMATION | VM_OPERATION | VM_READ | VM_WRITE
        if (handle==IntPtr.Zero) throw new InvalidOperationException("Cannot open verified Renamer test process.");
        IntPtr remote=IntPtr.Zero;
        bool pending=false;
        try
        {
            ushort machine,native;
            if (!IsWow64Process2(handle,out machine,out native) || (machine!=0 && machine!=0x8664) ||
                (machine==0 && native!=0x8664))
                throw new InvalidOperationException("Renamer preview reader requires x64 target.");
            int size=Marshal.SizeOf<ListItem>();
            if(size!=88) throw new InvalidOperationException("Unexpected x64 LVITEM layout.");
            var bytes=new byte[size+chars*2];
            remote=VirtualAllocEx(handle,IntPtr.Zero,new UIntPtr((uint)bytes.Length),0x3000,0x04);
            if(remote==IntPtr.Zero) throw new InvalidOperationException("Renamer preview buffer allocation failed.");
            var buffer=IntPtr.Add(remote,size);
            var rows=new string[expectedCount][];
            int[] columns={0,1,5};
            for(int row=0;row<expectedCount;row++)
            {
                rows[row]=new string[columns.Length];
                for(int c=0;c<columns.Length;c++)
                {
                    if(Preview(dlg,pid)!=hwnd || Count(dlg,pid)!=expectedCount)
                        return null;
                    // Non-NUL sentinel detects an unwritten or unterminated reply.
                    Array.Fill(bytes,(byte)0xFF);
                    var item=new ListItem{mask=1,item=row,subItem=columns[c],text=buffer,textMax=chars};
                    var local=Marshal.AllocHGlobal(size);
                    try { Marshal.StructureToPtr(item,local,false); Marshal.Copy(local,bytes,0,size); }
                    finally { Marshal.FreeHGlobal(local); }
                    UIntPtr transferred;
                    if(!WriteProcessMemory(handle,remote,bytes,new UIntPtr((uint)bytes.Length),out transferred) ||
                       transferred.ToUInt64()!=(ulong)bytes.Length)
                        throw new InvalidOperationException("Renamer preview request write failed.");
                    // Do not free the remote allocation if a timed-out message might still use it.
                    pending=true;
                    UIntPtr result;
                    if(SendNumber(hwnd,0x104B,UIntPtr.Zero,remote,Flags,2500,out result)==IntPtr.Zero)
                        throw new InvalidOperationException("Renamer LVM_GETITEMW timed out or failed; buffer retained until test process exits.");
                    pending=false;
                    if(result==UIntPtr.Zero)
                        throw new InvalidOperationException("Renamer LVM_GETITEMW rejected row "+row+", column "+columns[c]+".");
                    if(!ReadProcessMemory(handle,remote,bytes,new UIntPtr((uint)bytes.Length),out transferred) ||
                       transferred.ToUInt64()!=(ulong)bytes.Length)
                        throw new InvalidOperationException("Renamer preview reply read failed.");
                    // Never follow a returned pointer outside the test-owned allocation.
                    if(BitConverter.ToInt64(bytes,24)!=buffer.ToInt64())
                        throw new InvalidOperationException("Renamer list returned a different text pointer.");
                    int end=size;
                    while(end<bytes.Length && (bytes[end]!=0 || bytes[end+1]!=0)) end+=2;
                    if(end==bytes.Length || end==bytes.Length-2)
                        throw new InvalidOperationException("Renamer preview text missing terminator or truncated.");
                    rows[row][c]=new UnicodeEncoding(false,false,true).GetString(bytes,size,end-size);
                }
            }
            return Preview(dlg,pid)==hwnd && Count(dlg,pid)==expectedCount ? rows : null;
        }
        finally
        {
            try
            {
                if(remote!=IntPtr.Zero && !pending && !VirtualFreeEx(handle,remote,UIntPtr.Zero,0x8000))
                    throw new InvalidOperationException("Renamer preview buffer release failed.");
            }
            finally { CloseHandle(handle); }
        }
    }

    public static void Command(IntPtr dlg,uint pid,int command)
    {
        Require(dlg,pid);
        if(command!=611 && command!=607 && command!=608 && command!=609 && command!=602 && command!=604 && command!=605 && command!=624 && command!=625 && command!=600 && command!=621 && command!=1)
            throw new InvalidOperationException("Unexpected Renamer command.");
        // Reset, filenames and sort are synchronous; potentially modal actions are posted.
        if(command==611 || command==607 || command==608 || command==609 || command==602 || command==604 || command==605 || command==624 || command==625) Number(dlg,0x111,(uint)command,IntPtr.Zero);
        else if(!PostMessage(dlg,0x111,new IntPtr(command),IntPtr.Zero))
            throw new InvalidOperationException("Renamer command post failed.");
    }
    public static void Close(IntPtr dlg,uint pid)
    {
        Require(dlg,pid);
        if(!PostMessage(dlg,0x10,IntPtr.Zero,IntPtr.Zero)) throw new InvalidOperationException("Renamer close failed.");
    }
    public static bool ModalAction(IntPtr renamer,uint pid,string[] required,int buttonId,string buttonText)
    {
        return MatchModal(renamer,pid,required,buttonId,buttonText,true);
    }
    public static bool ObserveModal(IntPtr renamer,uint pid,string[] required,int buttonId,string buttonText)
    {
        return MatchModal(renamer,pid,required,buttonId,buttonText,false);
    }
    private static bool MatchModal(IntPtr renamer,uint pid,string[] required,int buttonId,string buttonText,bool act)
    {
        if(!Match(renamer,pid)) throw new InvalidOperationException("Renamer dialog identity lost.");
        var candidates=new List<IntPtr>();
        if(!EnumWindows((hwnd,arg)=>{
            if(hwnd!=renamer && Owned(hwnd,pid) && IsWindowVisible(hwnd) && IsWindowEnabled(hwnd) &&
               ClassIs(hwnd,"#32770") && GetAncestor(hwnd,3)==renamer) candidates.Add(hwnd);
            return true;
        },IntPtr.Zero)) throw new InvalidOperationException("Renamer modal enumeration failed.");
        IntPtr found=IntPtr.Zero;
        foreach(var dlg in candidates)
        {
            var controls=new List<IntPtr>();
            EnumChildWindows(dlg,(hwnd,arg)=>{if(Owned(hwnd,pid) && ClassIs(hwnd,"Static")) controls.Add(hwnd);return true;},IntPtr.Zero);
            var parts=new List<string>();
            parts.Add(Text(dlg));
            foreach(var ctrl in controls) parts.Add(Text(ctrl));
            string message=String.Join("\n",parts);
            bool matches=true;
            foreach(var part in required) if(message.IndexOf(part,StringComparison.Ordinal)<0) matches=false;
            if(!matches) continue;
            var button=Control(dlg,pid,buttonId,"Button");
            if(button==IntPtr.Zero || !IsWindowEnabled(button) || !IsWindowVisible(button) ||
               Text(button).Replace("&","")!=buttonText) continue;
            if(found!=IntPtr.Zero) throw new InvalidOperationException("Ambiguous Renamer confirmation.");
            found=dlg;
        }
        if(found==IntPtr.Zero) return false;
        var target=Control(found,pid,buttonId,"Button");
        if(!Owned(found,pid) || GetAncestor(found,3)!=renamer || !IsWindowEnabled(found) ||
           target==IntPtr.Zero || !IsWindowEnabled(target) || !IsWindowVisible(target) ||
           Text(target).Replace("&","")!=buttonText || (act && !PostMessage(found,0x111,new IntPtr(buttonId),target)))
            throw new InvalidOperationException("Verified Renamer modal action failed.");
        return true;
    }
}
'@

function Get-RenamerCase {
    $cases = @{
        'Prefix' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='pre-$(OriginalName)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('pre-a-Ab.txt','pre-b-Ab.txt') }
        'Suffix' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(NamePart)-end.$(ExtPart)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('a-Ab-end.txt','b-Ab-end.txt') }
        'Extension' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(NamePart).bin'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('a-Ab.bin','b-Ab.bin') }
        'LiteralDollar' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$$-$(OriginalName)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('$-a-Ab.txt','$-b-Ab.txt') }
        'LowerName' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(OriginalName)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=1; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('a-ab.txt','b-ab.txt') }
        'UpperExtension' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(OriginalName)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=2; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('a-Ab.TXT','b-Ab.TXT') }
        'CaseSensitive' = @{ Old=@('a-Ab.txt','b-ab.txt'); NewName='$(OriginalName)'; Search='Ab'; Replace='X'; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('a-X.txt','b-ab.txt') }
        'CaseInsensitive' = @{ Old=@('a-Ab.txt','b-ab.txt'); NewName='$(OriginalName)'; Search='Ab'; Replace='X'; Mask='*.*'; Sensitive=$false; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('a-X.txt','b-X.txt') }
        'ReplaceOnce' = @{ Old=@('a-cat-cat.txt','b-cat-cat.txt'); NewName='$(OriginalName)'; Search='cat'; Replace='dog'; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('a-dog-cat.txt','b-dog-cat.txt') }
        'ReplaceAll' = @{ Old=@('a-cat-cat.txt','b-cat-cat.txt'); NewName='$(OriginalName)'; Search='cat'; Replace='dog'; Mask='*.*'; Sensitive=$true; Once=$false; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('a-dog-dog.txt','b-dog-dog.txt') }
        'WholeWords' = @{ Old=@('cat-catfish.txt','bobcat-cat.txt'); NewName='$(OriginalName)'; Search='cat'; Replace='dog'; Mask='*.*'; Sensitive=$true; Once=$false; Whole=$true; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('dog-catfish.txt','bobcat-dog.txt') }
        'ExcludeExtension' = @{ Old=@('a-txt.txt','b-txt.txt'); NewName='$(OriginalName)'; Search='txt'; Replace='bin'; Mask='*.*'; Sensitive=$true; Once=$false; Whole=$false; Regex=$false; Exclude=$true; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('a-bin.txt','b-bin.txt') }
        'RegexCapture' = @{ Old=@('a-Ab-12.txt','b-Ab-34.txt'); NewName='$(OriginalName)'; Search='(Ab)-([0-9]+)'; Replace='$2-$1'; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$true; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('a-12-Ab.txt','b-34-Ab.txt') }
        'RegexLower' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(OriginalName)'; Search='(Ab)'; Replace='$(1:lower)'; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$true; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('a-ab.txt','b-ab.txt') }
        'RegexUpper' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(OriginalName)'; Search='(Ab)'; Replace='$(1:upper)'; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$true; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('a-AB.txt','b-AB.txt') }
        'RegexUpperCapital' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(OriginalName)'; Search='(Ab)'; Replace='$(1:UPPER)'; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$true; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('a-AB.txt','b-AB.txt') }
        'RegexUpperMixed' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(OriginalName)'; Search='(Ab)'; Replace='$(1:UpPeR)'; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$true; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('a-AB.txt','b-AB.txt') }
        'RegexBrace' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(OriginalName)'; Search='(Ab)'; Replace='${1:upper}'; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$true; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('a-AB.txt','b-AB.txt') }
        'Counter' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(Counter:1,2,d,3,0)-$(OriginalName)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('001-a-Ab.txt','003-b-Ab.txt') }
        'CounterDescending' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(Counter:9,-2)-$(OriginalName)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('9-a-Ab.txt','7-b-Ab.txt') }
        'CounterFraction' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(Counter:3,1.5)-$(OriginalName)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('3-a-Ab.txt','4-b-Ab.txt') }
        'CounterMalformed' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(Counter:1,1.5x)-$(OriginalName)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Invalid'; Manual=$false; Error='Expecting counter step (floating point number).'; ErrorType='New name error'; New=@('a-Ab.txt','b-Ab.txt') }
        'CounterMultipleDots' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(Counter:1,1.2.3)-$(OriginalName)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Invalid'; Manual=$false; Error='Expecting counter step (floating point number).'; ErrorType='New name error'; New=@('a-Ab.txt','b-Ab.txt') }
        'CounterDotOnly' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(Counter:1,.)-$(OriginalName)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Invalid'; Manual=$false; Error='Expecting counter step (floating point number).'; ErrorType='New name error'; New=@('a-Ab.txt','b-Ab.txt') }
        'InvalidVariable' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(UnknownRenamerVariable)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Invalid'; Manual=$false; Error='Variable was not found.'; ErrorType='New name error'; New=@('a-Ab.txt','b-Ab.txt') }
        'InvalidRegex' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(OriginalName)'; Search='('; Replace='x'; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$true; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Invalid'; Manual=$false; Error='Unmatched ().'; ErrorType='Regular expression error'; New=@('a-Ab.txt','b-Ab.txt') }
        'InvalidReference' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(OriginalName)'; Search='(Ab)'; Replace='$9'; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$true; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Invalid'; Manual=$false; Error='Reference to undefined sub-expression.'; ErrorType='Replace pattern error'; New=@('a-Ab.txt','b-Ab.txt') }
        'InvalidModifier' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(OriginalName)'; Search='(Ab)'; Replace='$(1:bogus)'; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$true; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Invalid'; Manual=$false; Error='Expecting closing parenthesis or case specification (''lower'', ''upper'', ''mixed'', or ''stripdia'').'; ErrorType='Replace pattern error'; New=@('a-Ab.txt','b-Ab.txt') }
        'DuplicateCancel' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='duplicate.txt'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='DuplicateCancel'; Manual=$false; Error=''; ErrorType=''; New=@('duplicate.txt','duplicate.txt') }
        'CollisionCancel' = @{ Old=@('a-target.txt','z-source.txt'); NewName='a-target.txt'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(1); Preview=@(1); Action='CollisionCancel'; Manual=$false; Error=''; ErrorType=''; New=@('a-target.txt','a-target.txt') }
        'Cancel' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='cancel-$(OriginalName)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Cancel'; Manual=$false; Error=''; ErrorType=''; New=@('cancel-a-Ab.txt','cancel-b-Ab.txt') }
        'Undo' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='undo-$(OriginalName)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Undo'; Manual=$false; Error=''; ErrorType=''; New=@('undo-a-Ab.txt','undo-b-Ab.txt') }
        'SingleSelection' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='single-$(OriginalName)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(1); Preview=@(1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('a-Ab.txt','single-b-Ab.txt') }
        'MaskFilter' = @{ Old=@('a-Ab.txt','b-Ab.bin'); NewName='mask-$(OriginalName)'; Search=''; Replace=''; Mask='*.txt'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('mask-a-Ab.txt','b-Ab.bin') }
        'Manual' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(OriginalName)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$true; Error=''; ErrorType=''; New=@('manual-a.txt','manual-b.txt') }
        'VariableLower' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(NamePart:lower).$(ExtPart)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('a-ab.txt','b-ab.txt') }
        'VariableUpper' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(NamePart:upper).$(ExtPart)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('A-AB.txt','B-AB.txt') }
        'VariableMixed' = @{ Old=@('a-HELLO.txt','b-wORLD.txt'); NewName='$(NamePart:mixed).$(ExtPart)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('A-Hello.txt','B-World.txt') }
        'VariableCaseInsensitive' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='new-$(oRiGiNaLnAmE)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('new-a-Ab.txt','new-b-Ab.txt') }
        'SubstringLeft' = @{ Old=@('alpha-123.txt','bravo-456.txt'); NewName='$(NamePart:0,5).bin'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('alpha.bin','bravo.bin') }
        'SubstringRight' = @{ Old=@('alpha-123.txt','bravo-456.txt'); NewName='$(NamePart:-3).bin'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('123.bin','456.bin') }
        'SubstringMiddle' = @{ Old=@('alpha-123.txt','bravo-456.txt'); NewName='$(NamePart:2,5)-$(OriginalName)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('pha-alpha-123.txt','avo-bravo-456.txt') }
        'SubstringClamp' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='cut-$(NamePart:0,99).$(ExtPart)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('cut-a-Ab.txt','cut-b-Ab.txt') }
        'SubstringCase' = @{ Old=@('alpha-123.txt','bravo-456.txt'); NewName='$(NamePart:0,5,upper).bin'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('ALPHA.bin','BRAVO.bin') }
        'MultipleDots' = @{ Old=@('alpha.part.one.txt','bravo.part.two.txt'); NewName='$(NamePart).bak'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('alpha.part.one.bak','bravo.part.two.bak') }
        'NoExtension' = @{ Old=@('alpha','bravo'); NewName='$(NamePart).txt'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('alpha.txt','bravo.txt') }
        'DotfileExtension' = @{ Old=@('.alpha','.bravo'); NewName='dot-$(ExtPart).txt'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('dot-alpha.txt','dot-bravo.txt') }
        'DeleteSubstring' = @{ Old=@('a-drop-cat.txt','b-drop-dog.txt'); NewName='$(OriginalName)'; Search='drop-'; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('a-cat.txt','b-dog.txt') }
        'ReplaceExtensionToo' = @{ Old=@('a-txt.txt','b-txt.txt'); NewName='$(OriginalName)'; Search='txt'; Replace='bin'; Mask='*.*'; Sensitive=$true; Once=$false; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('a-bin.bin','b-bin.bin') }
        'RegexWholeMatch' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(OriginalName)'; Search='Ab'; Replace='[$0]'; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$true; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('a-[Ab].txt','b-[Ab].txt') }
        'RegexCaseInsensitive' = @{ Old=@('a-Ab.txt','b-ab.txt'); NewName='$(OriginalName)'; Search='AB'; Replace='X'; Mask='*.*'; Sensitive=$false; Once=$true; Whole=$false; Regex=$true; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('a-X.txt','b-X.txt') }
        'RegexAll' = @{ Old=@('a-12-34.txt','b-56-78.txt'); NewName='$(OriginalName)'; Search='[0-9]+'; Replace='n'; Mask='*.*'; Sensitive=$true; Once=$false; Whole=$false; Regex=$true; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('a-n-n.txt','b-n-n.txt') }
        'RegexAnchored' = @{ Old=@('a-12.txt','b-34.txt'); NewName='$(OriginalName)'; Search='^([ab])-'; Replace='$1_'; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$true; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('a_12.txt','b_34.txt') }
        'RegexEscapedDollar' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(OriginalName)'; Search='Ab'; Replace='$$'; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$true; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('a-$.txt','b-$.txt') }
        'RegexEmptyReplacement' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(OriginalName)'; Search='-Ab'; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$true; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('a.txt','b.txt') }
        'CounterDefault' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(Counter)-$(OriginalName)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('0-a-Ab.txt','1-b-Ab.txt') }
        'CounterHexLower' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(Counter:15,1,x)-$(OriginalName)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('f-a-Ab.txt','10-b-Ab.txt') }
        'CounterHexUpper' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(Counter:15,1,X)-$(OriginalName)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('F-a-Ab.txt','10-b-Ab.txt') }
        'CounterLeftAlign' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(Counter:3,2,d,l,3,_)-$(OriginalName)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('3__-a-Ab.txt','5__-b-Ab.txt') }
        'CounterZeroStep' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(Counter:8,0)-$(OriginalName)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('8-a-Ab.txt','8-b-Ab.txt') }
        'CounterNegativeFraction' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(Counter:4,-.5)-$(OriginalName)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('4-a-Ab.txt','3-b-Ab.txt') }
        'CounterTrailingPoint' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(Counter:4,1.)-$(OriginalName)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$false; Error=''; ErrorType=''; New=@('4-a-Ab.txt','5-b-Ab.txt') }
        'CounterInvalidStart' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(Counter:x,1)-$(OriginalName)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Invalid'; Manual=$false; Error='Expecting counter start (integer number).'; ErrorType='New name error'; New=@('a-Ab.txt','b-Ab.txt') }
        'CounterInvalidBase' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(Counter:1,1,q)-$(OriginalName)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Invalid'; Manual=$false; Error='Expecting base (one of ''dxX''), alignment (''l'') or width (positive integer number) specification.'; ErrorType='New name error'; New=@('a-Ab.txt','b-Ab.txt') }
        'CounterInvalidFill' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(Counter:1,1,d,3,ab)-$(OriginalName)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Invalid'; Manual=$false; Error='Expecting filler specification (one letter)'; ErrorType='New name error'; New=@('a-Ab.txt','b-Ab.txt') }
        'TrailingDollar' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(OriginalName)$'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Invalid'; Manual=$false; Error='Unexpected end of string, character ''$'' must be followed by variable name or ''$'' character.'; ErrorType='New name error'; New=@('a-Ab.txt','b-Ab.txt') }
        'UnclosedVariable' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(OriginalName'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Invalid'; Manual=$false; Error='Variable name must be terminated by '')''.'; ErrorType='New name error'; New=@('a-Ab.txt','b-Ab.txt') }
        'EmptyVariable' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$()'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Invalid'; Manual=$false; Error='Empty string is not allowed here.'; ErrorType='New name error'; New=@('a-Ab.txt','b-Ab.txt') }
        'WrongRegexBracket' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(OriginalName)'; Search='(Ab)'; Replace='$(1:upper}'; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$true; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Invalid'; Manual=$false; Error='Expecting closing parenthesis.'; ErrorType='Replace pattern error'; New=@('a-Ab.txt','b-Ab.txt') }
        'ManualSwap' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(OriginalName)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Rename'; Manual=$true; Error=''; ErrorType=''; New=@('b-Ab.txt','a-Ab.txt') }
        'ManualSwapUndo' = @{ Old=@('a-Ab.txt','b-Ab.txt'); NewName='$(OriginalName)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Undo'; Manual=$true; Error=''; ErrorType=''; New=@('b-Ab.txt','a-Ab.txt') }
        'ManualChainUndo' = @{ Old=@('a.txt','b.txt'); NewName='$(OriginalName)'; Search=''; Replace=''; Mask='*.*'; Sensitive=$true; Once=$true; Whole=$false; Regex=$false; Exclude=$false; NameCase=0; ExtCase=0; Selected=@(0,1); Preview=@(0,1); Action='Undo'; Manual=$true; Error=''; ErrorType=''; New=@('b.txt','c.txt') }
    }
    if (-not $cases.ContainsKey($RenamerHostCase)) { throw "Unregistered Renamer scenario: $RenamerHostCase" }
    return $cases[$RenamerHostCase]
}

function Initialize-RenamerFixture {
    if ($root -match '[^\x20-\x7e]' -or $root.Length -ge 180) { throw 'Renamer baseline requires short ASCII fixture paths.' }
    $case = Get-RenamerCase
    $plugin = Join-Path (Split-Path -Parent $SalamanderExe) 'plugins\renamer\renamer.spl'
    if (-not [IO.File]::Exists($plugin)) { throw "Missing built Renamer SPL: $plugin" }
    $null = [IO.Directory]::CreateDirectory($destination)
    $guard = Join-Path $destination 'untouched.bin'
    [IO.File]::WriteAllBytes($guard,[Text.Encoding]::ASCII.GetBytes('Independent guard outside source panel'))
    $before = [ordered]@{}
    $after = [ordered]@{}
    $preview = [ordered]@{}
    for ($i=0; $i -lt $case.Old.Count; $i++) {
        $name = $case.Old[$i]
        if ([IO.Path]::GetFileName($name) -cne $name -or [IO.Path]::GetFileName($case.New[$i]) -cne $case.New[$i]) { throw 'Non-leaf fixture name.' }
        $file = Join-Path $source $name
        [IO.File]::WriteAllBytes($file,[Text.Encoding]::ASCII.GetBytes(("Independent Renamer payload $i $name " * (128+$i))))
        $before[$name] = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
        if ($case.Action -in @('Rename','Undo')) { $after.Add($case.New[$i],$before[$name]) }
        if ($i -in $case.Preview) {
            $preview[$name] = if ($case.Error) { "<$($case.ErrorType): $($case.Error)>" } else { $case.New[$i] }
        }
    }
    if ($before[$case.Old[0]] -ceq $before[$case.Old[1]]) { throw 'Fixture payloads must be distinct.' }
    [pscustomobject]@{ Case=$case; Before=$before; After=$after; Preview=$preview
        Plugin=[IO.Path]::GetFullPath($plugin); Guard=$guard
        GuardHash=(Get-FileHash -LiteralPath $guard -Algorithm SHA256).Hash }
}

function Test-RenamerDisk {
    param($Expected,$Fixture)
    $entries = @(Get-ChildItem -LiteralPath $source -Force)
    if ($entries.Count -ne $Expected.Count) { return $false }
    $expectedNames = @($Expected.Keys | Sort-Object)
    $actualNames = @($entries.Name | Sort-Object)
    if (($actualNames -join [char]0) -cne ($expectedNames -join [char]0)) { return $false }
    foreach ($item in $entries) {
        if ($item.PSIsContainer -or $item.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) { return $false }
        try { if ((Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash -cne $Expected[$item.Name]) { return $false } }
        catch [IO.IOException] { return $false }
    }
    $guards = @(Get-ChildItem -LiteralPath $destination -Force)
    return $guards.Count -eq 1 -and $guards[0].FullName -ceq $Fixture.Guard -and
        (Get-FileHash -LiteralPath $Fixture.Guard -Algorithm SHA256).Hash -ceq $Fixture.GuardHash
}

function Get-RenamerPreview {
    param([IntPtr]$Dialog,[uint32]$PidExpected,[int]$ExpectedCount)
    $hwnd = [RenamerHostNative]::Preview($Dialog,$PidExpected)
    if ([RenamerHostNative]::Count($Dialog,$PidExpected) -ne $ExpectedCount) { return $null }
    $element = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
    if ($element.Current.ProcessId -ne $PidExpected) { throw 'Preview automation element belongs to another process.' }
    $pattern = $null
    if (-not $element.TryGetCurrentPattern([System.Windows.Automation.GridPattern]::Pattern,[ref]$pattern)) {
        $nativeRows = [RenamerHostNative]::ReadPreview($Dialog,$PidExpected,$ExpectedCount)
        if ($null -eq $nativeRows -or $nativeRows.Length -ne $ExpectedCount) { return $null }
        $rows = [Collections.Generic.List[object]]::new()
        for ($i=0; $i -lt $ExpectedCount; $i++) {
            $values = $nativeRows[$i]
            if ($null -eq $values -or $values.Length -ne 3) { throw 'Incomplete native Renamer preview row.' }
            $rows.Add([pscustomobject]@{ Old=$values[0]; New=$values[1]; Path=$values[2] })
        }
        return ,($rows.ToArray())
    }
    if ($pattern.Current.RowCount -ne $ExpectedCount -or $pattern.Current.ColumnCount -lt 6) { return $null }
    $rows = [Collections.Generic.List[object]]::new()
    for ($i=0; $i -lt $ExpectedCount; $i++) {
        $values = @(
            foreach ($column in @(0,1,5)) {
                $cell = $pattern.GetItem($i,$column)
                if ($null -eq $cell -or $cell.Current.ProcessId -ne $PidExpected) { throw 'Unverified Renamer preview cell.' }
                $value = $null
                if ($cell.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern,[ref]$value)) {
                    [string]$value.Current.Value
                }
                else { [string]$cell.Current.Name }
            }
        )
        $rows.Add([pscustomobject]@{ Old=$values[0]; New=$values[1]; Path=$values[2] })
    }
    return ,($rows.ToArray())
}

function Assert-RenamerPreview {
    param([IntPtr]$Dialog,[uint32]$PidExpected,$Expected)
    $observed = @{ Rows=$null }
    try {
        Wait-Until {
            $observed.Rows = Get-RenamerPreview $Dialog $PidExpected $Expected.Count
            if ($null -eq $observed.Rows -or $observed.Rows.Count -ne $Expected.Count) { return $false }
            $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach ($row in $observed.Rows) {
                if (-not $seen.Add($row.Old) -or @($Expected.Keys | Where-Object { $_ -ceq $row.Old }).Count -ne 1 -or
                    $Expected[$row.Old] -cne $row.New -or $row.Path.TrimEnd('\') -cne $source) { return $false }
            }
            return $true
        } "exact independent Renamer preview names and source paths ($RenamerHostCase)"
    }
    catch {
        Write-Host ('Observed Renamer preview: ' + ($observed.Rows | ConvertTo-Json -Compress))
        Write-Host ('Expected Renamer preview: ' + ($Expected | ConvertTo-Json -Compress))
        throw
    }
    Write-Host ('PASS: exact Renamer preview: ' + ($observed.Rows | ConvertTo-Json -Compress))
}

function Test-RenamerHost {
    param([Parameter(Mandatory)]$Fixture)
    $case = $Fixture.Case
    Assert-True ((Read-PanelPath) -ceq $source) 'Renamer active panel exact fixture root'
    Assert-True (Test-RenamerDisk $Fixture.Before $Fixture) 'Exact source and independent guard before Renamer'
    if ($case.Selected.Count -eq 2) {
        Select-TwoRegularFiles -ExpectedNames $case.Old
    }
    else {
        Send-Keys '{END}'
        $selected = $case.Old[$case.Selected[0]]
        Assert-True ((Read-FocusedFullname) -ceq (Join-Path $source $selected)) 'Exact single selected Renamer source'
    }
    Assert-True ((Read-PanelPath) -ceq $source) 'Exact source root before Ctrl+Shift+R'
    Send-Keys '^+r'
    $state = @{ Dialog=[IntPtr]::Zero }
    $ownerPid = [uint32]$process.Id
    Wait-Until {
        if ($process.HasExited) { throw 'Salamander exited starting Renamer.' }
        $state.Dialog = [RenamerHostNative]::Find($ownerPid)
        $state.Dialog -ne [IntPtr]::Zero
    } 'real Batch Rename dialog in verified Salamander process'
    $dlg = $state.Dialog
    $process.Refresh()
    Assert-True (@($process.Modules | Where-Object {
        [string]::Equals($_.FileName,$Fixture.Plugin,[StringComparison]::OrdinalIgnoreCase)
    }).Count -eq 1) 'Exact built Renamer SPL loaded'
    Wait-Until {
        [RenamerHostNative]::IsWindowEnabled($dlg) -and
            [RenamerHostNative]::Count($dlg,$ownerPid) -gt 0
    } 'Renamer initial source listing ready'
    [RenamerHostNative]::Command($dlg,$ownerPid,611) # CMD_RESET
    [RenamerHostNative]::Command($dlg,$ownerPid,607) # CMD_FILENAMES
    [RenamerHostNative]::Check($dlg,$ownerPid,102,$false) # no recursion
    [RenamerHostNative]::Combo($dlg,$ownerPid,101,$case.Mask)
    Wait-Until {
        [RenamerHostNative]::IsWindowEnabled($dlg) -and
            [RenamerHostNative]::Count($dlg,$ownerPid) -eq $case.Preview.Count
    } 'exact masked source row count before rule setup'
    [RenamerHostNative]::Command($dlg,$ownerPid,602) # CMD_SORTOLD, ascending original names
    [RenamerHostNative]::Combo($dlg,$ownerPid,106,$case.NewName)
    [RenamerHostNative]::Combo($dlg,$ownerPid,108,$case.Search)
    [RenamerHostNative]::Combo($dlg,$ownerPid,109,$case.Replace)
    [RenamerHostNative]::Check($dlg,$ownerPid,112,$case.Sensitive)
    [RenamerHostNative]::Check($dlg,$ownerPid,113,$case.Whole)
    [RenamerHostNative]::Check($dlg,$ownerPid,114,$case.Once)
    [RenamerHostNative]::Check($dlg,$ownerPid,115,$case.Regex)
    [RenamerHostNative]::Check($dlg,$ownerPid,123,$case.Exclude)
    [RenamerHostNative]::Case($dlg,$ownerPid,116,[uint32]$case.NameCase)
    [RenamerHostNative]::Case($dlg,$ownerPid,117,[uint32]$case.ExtCase)
    if ($case.Manual) {
        $identity = [ordered]@{}
        foreach ($index in $case.Preview) { $identity[$case.Old[$index]]=$case.Old[$index] }
        Assert-RenamerPreview $dlg $ownerPid $identity
        [RenamerHostNative]::Check($dlg,$ownerPid,105,$true)
        [RenamerHostNative]::Manual($dlg,$ownerPid,($case.New -join [Environment]::NewLine))
    }
    Assert-RenamerPreview $dlg $ownerPid $Fixture.Preview
    Assert-True (Test-RenamerDisk $Fixture.Before $Fixture) 'Preview does not modify files'
    switch ($case.Action) {
        Invalid {
            # Validation uses the actual parser but cannot mutate disk.
            [RenamerHostNative]::Command($dlg,$ownerPid,600)
            Wait-Until { [RenamerHostNative]::ModalAction($dlg,$ownerPid,@($case.Error),1,'OK') } 'specific parser error during validation'
            Wait-Until { [RenamerHostNative]::IsWindowEnabled($dlg) } 'validation error dismissed'
            Assert-True (Test-RenamerDisk $Fixture.Before $Fixture) 'Invalid rule preserves all original files'
        }
        DuplicateCancel {
            [RenamerHostNative]::Command($dlg,$ownerPid,600)
            Wait-Until { [RenamerHostNative]::ModalAction($dlg,$ownerPid,@('Duplicate name.',(Join-Path $source 'duplicate.txt')),2,'Cancel') } 'exact duplicate-target validation cancelled'
            Wait-Until { [RenamerHostNative]::IsWindowEnabled($dlg) } 'duplicate validation cancelled'
            Assert-True (Test-RenamerDisk $Fixture.Before $Fixture) 'Duplicate cancellation preserves original files'
        }
        CollisionCancel {
            [RenamerHostNative]::Command($dlg,$ownerPid,600)
            Wait-Until { [RenamerHostNative]::ModalAction($dlg,$ownerPid,@((Join-Path $source 'a-target.txt'),(Join-Path $source 'z-source.txt')),2,'Cancel') } 'exact overwrite validation cancelled'
            Wait-Until { [RenamerHostNative]::IsWindowEnabled($dlg) } 'collision validation cancelled'
            Assert-True (Test-RenamerDisk $Fixture.Before $Fixture) 'Collision cancellation preserves source and existing target bytes'
        }
        Cancel { Assert-True (Test-RenamerDisk $Fixture.Before $Fixture) 'Before cancelling unapplied rename' }
        default {
            # No destructive confirmation is accepted: only the exact independently
            # expected safe leaf names in this uniquely owned directory.
            [RenamerHostNative]::Command($dlg,$ownerPid,1)
            Wait-Until {
                if ($process.HasExited) { throw 'Salamander exited during Renamer operation.' }
                [RenamerHostNative]::IsWindowEnabled($dlg) -and (Test-RenamerDisk $Fixture.After $Fixture)
            } 'exact renamed file set and independent SHA-256 hashes' -TimeoutSecondsOverride 60
            Assert-True (Test-RenamerDisk $Fixture.After $Fixture) 'All final names, bytes and guard exact'
            if ($case.Action -eq 'Undo') {
                [RenamerHostNative]::Command($dlg,$ownerPid,621)
                Wait-Until { [RenamerHostNative]::ModalAction($dlg,$ownerPid,@('Undo rename operation?'),6,'Yes') } 'verified Undo confirmation'
                Wait-Until {
                    if ($process.HasExited) { throw 'Salamander exited during Undo.' }
                    [RenamerHostNative]::IsWindowEnabled($dlg) -and (Test-RenamerDisk $Fixture.Before $Fixture)
                } 'Undo restores exact original names and bytes' -TimeoutSecondsOverride 60
                Assert-True (Test-RenamerDisk $Fixture.Before $Fixture) 'Final Undo restored complete original file set'
            }
        }
    }
    [RenamerHostNative]::Close($dlg,$ownerPid)
    Wait-Until {
        if ($process.HasExited) { throw 'Salamander exited closing Renamer.' }
        # Do not send WM_GETTEXT to an HWND racing with DestroyWindow.
        # The exact verified dialog must cease to exist; a hung dialog still fails.
        -not [RenamerHostNative]::IsWindow($dlg)
    } 'Batch Rename window closed'
    $final = if ($case.Action -eq 'Rename') { $Fixture.After } else { $Fixture.Before }
    Assert-True (Test-RenamerDisk $final $Fixture) 'Exact final disk state after closing Renamer'
    Write-Host "PASS: Renamer $RenamerHostCase preview, real host action, exact filenames and independent SHA-256."
}
