#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
# Loaded only by the ZIP host scenario of the existing GUI driver.
# All paths and the password belong to a fresh disposable test fixture.
function Invoke-ZipHostFixtureTool {
    param([string[]]$Arguments, [string]$Directory)
    $info = [Diagnostics.ProcessStartInfo]::new($ZipHostSevenZip)
    $info.WorkingDirectory = $Directory
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($arg in $Arguments) { $info.ArgumentList.Add($arg) }
    $child = [Diagnostics.Process]::Start($info)
    if ($null -eq $child) { throw 'Could not start fixture 7-Zip.' }
    try {
        $stdout = $child.StandardOutput.ReadToEndAsync()
        $stderr = $child.StandardError.ReadToEndAsync()
        if (-not $child.WaitForExit(30000)) { throw '7-Zip fixture timeout.' }
        if (-not $stdout.Wait(5000) -or -not $stderr.Wait(5000)) { throw '7-Zip output did not close.' }
        $text = $stdout.GetAwaiter().GetResult()
        $errorText = $stderr.GetAwaiter().GetResult()
        if ($text) { Write-Host $text.TrimEnd() }
        if ($errorText) { Write-Host $errorText.TrimEnd() }
        if ($child.ExitCode -ne 0) { throw "7-Zip fixture exited $($child.ExitCode)." }
        return $text
    }
    finally {
        try {
            if (-not $child.HasExited) {
                $child.Kill()
                if (-not $child.WaitForExit(5000)) { throw '7-Zip fixture process did not terminate.' }
            }
        }
        finally { $child.Dispose() }
    }
}

function Initialize-ZipHostFixture {
    if ($root -match '[^\x20-\x7e]' -or $root.Length -ge 200) {
        throw 'ZIP host ASCII baseline requires a short ASCII temporary path.'
    }
    $module = Join-Path (Split-Path -Parent $SalamanderExe) 'plugins\zip\zip.spl'
    if (-not (Test-Path -LiteralPath $module -PathType Leaf)) { throw "Missing built ZIP plugin: $module" }
    if (-not (Test-Path -LiteralPath $ZipHostSevenZip -PathType Leaf)) { throw 'Missing 7-Zip fixture tool.' }
    $null = [IO.Directory]::CreateDirectory($destination)
    $fixtureDir = [IO.Directory]::CreateDirectory((Join-Path $root 'zip-input')).FullName
    $file = Join-Path $fixtureDir 'payload.txt'
    [IO.File]::WriteAllText($file, ('OpenSalamander ZIP host regression 0123456789' * 4096), [Text.Encoding]::ASCII)
    $archive = Join-Path $source 'fixture.zip'
    $password = 'SfxTest123'
    $encrypted = $ZipHostEncryption -eq 'ZipCrypto'
    $args7z = @('a','-tzip','-mm=Deflate','-bd','-y')
    if ($encrypted) { $args7z += @('-mem=ZipCrypto', "-p$password") }
    $args7z += @($archive,'payload.txt')
    $null = Invoke-ZipHostFixtureTool -Arguments $args7z -Directory $fixtureDir
    $listing = Invoke-ZipHostFixtureTool -Arguments @('l','-slt',$archive) -Directory $fixtureDir
    $method = if ($encrypted) { 'ZipCrypto Deflate' } else { 'Deflate' }
    $flag = if ($encrypted) { '+' } else { '-' }
    $lines = @($listing -split '\r?\n')
    if ($lines -cnotcontains "Method = $method" -or $lines -cnotcontains "Encrypted = $flag") {
        throw 'Unexpected ZIP host fixture method or encryption.'
    }
    $testArgs = @('t','-bd')
    if ($encrypted) { $testArgs += "-p$password" }
    $testArgs += $archive
    $null = Invoke-ZipHostFixtureTool -Arguments $testArgs -Directory $fixtureDir
    [pscustomobject]@{
        Archive = $archive
        ArchiveHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
        PayloadHash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
        SourceFile = $file
        Plugin = [IO.Path]::GetFullPath($module)
        Password = $password
        Encrypted = $encrypted
    }
}

# Dialog resources are from src/lang/lang.rh, lang.rc and
# src/plugins/zip/lang/lang.rh, lang.rc. No localized caption is assumed.
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class ZipHostDialogs
{
    private delegate bool Callback(IntPtr window, IntPtr arg);
    [DllImport("user32.dll")] private static extern bool EnumWindows(Callback callback, IntPtr arg);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] private static extern bool IsWindowEnabled(IntPtr window);
    [DllImport("user32.dll")] private static extern IntPtr GetDlgItem(IntPtr window, int id);
    [DllImport("user32.dll")] private static extern IntPtr GetParent(IntPtr window);
    [DllImport("user32.dll")] private static extern IntPtr GetAncestor(IntPtr window, uint flags);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="GetClassNameW")]
    private static extern int GetClassName(IntPtr window, StringBuilder name, int capacity);
    [DllImport("user32.dll", EntryPoint="GetWindowLongW")]
    private static extern int GetWindowLong(IntPtr window, int index);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="SendMessageTimeoutW", SetLastError=true)]
    private static extern IntPtr ReadText(IntPtr window, uint msg, UIntPtr w, StringBuilder text,
        uint flags, uint timeout, out UIntPtr result);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="SendMessageTimeoutW", SetLastError=true)]
    private static extern IntPtr WriteText(IntPtr window, uint msg, UIntPtr w, string text,
        uint flags, uint timeout, out UIntPtr result);
    [DllImport("user32.dll", EntryPoint="PostMessageW", SetLastError=true)]
    private static extern bool PostMessage(IntPtr window, uint msg, IntPtr w, IntPtr l);
    private const uint Flags = 0x23;
    private static bool Owned(IntPtr hwnd, uint pid)
    {
        uint actual;
        return hwnd != IntPtr.Zero && GetWindowThreadProcessId(hwnd, out actual) != 0 && actual == pid;
    }
    private static bool IsClass(IntPtr hwnd, string expected)
    {
        var text = new StringBuilder(128);
        return GetClassName(hwnd, text, text.Capacity) > 0 &&
            String.Equals(text.ToString(), expected, StringComparison.OrdinalIgnoreCase);
    }
    private static IntPtr Control(IntPtr dialog, int id, uint pid, string cls)
    {
        var hwnd = GetDlgItem(dialog, id);
        return Owned(hwnd, pid) && GetParent(hwnd) == dialog && IsClass(hwnd, cls) ? hwnd : IntPtr.Zero;
    }
    private static string Text(IntPtr hwnd)
    {
        var text = new StringBuilder(4096);
        UIntPtr result;
        if (ReadText(hwnd, 0x000D, new UIntPtr(4096), text, Flags, 1000, out result) == IntPtr.Zero)
            throw new InvalidOperationException("ZIP host dialog text read timed out.");
        return text.ToString();
    }
    private static bool Dialog(IntPtr hwnd, IntPtr main, uint pid)
    {
        return Owned(main, pid) && IsClass(main, "SalamanderMainWindowVer25") &&
            Owned(hwnd, pid) && IsWindowVisible(hwnd) && IsWindowEnabled(hwnd) &&
            IsClass(hwnd, "#32770") && GetAncestor(hwnd, 3) == main; // GA_ROOTOWNER
    }
    private static bool Match(IntPtr dlg, IntPtr main, uint pid, bool password, string target)
    {
        if (!Dialog(dlg, main, pid) || Control(dlg, 1, pid, "Button") == IntPtr.Zero ||
            Control(dlg, 2, pid, "Button") == IntPtr.Zero) return false;
        if (password)
        {
            var edit = Control(dlg, 120, pid, "Edit");
            var file = Control(dlg, 121, pid, "Static");
            if (edit == IntPtr.Zero || file == IntPtr.Zero ||
                Control(dlg, 118, pid, "Button") == IntPtr.Zero ||
                Control(dlg, 119, pid, "Button") == IntPtr.Zero ||
                (GetWindowLong(edit, -16) & 0x20) == 0 || !IsWindowEnabled(edit)) return false;
            string member = Text(file);
            return member == "payload.txt" || member.EndsWith("\\payload.txt", StringComparison.Ordinal);
        }
        var combo = Control(dlg, 210, pid, "ComboBox");
        var subject = Control(dlg, 209, pid, "Static");
        if (combo == IntPtr.Zero || subject == IntPtr.Zero ||
            Control(dlg, 362, pid, "Button") == IntPtr.Zero) return false;
        return String.Equals(Text(combo).TrimEnd('\\'), target.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase) &&
            Text(subject).Contains("payload.txt", StringComparison.Ordinal);
    }
    public static bool TryConfirm(IntPtr main, uint pid, bool password, string target, string fixturePassword)
    {
        var candidates = new List<IntPtr>();
        if (!EnumWindows((hwnd, arg) => {
            // Avoid propagating managed exceptions across a native callback.
            if (Dialog(hwnd, main, pid)) candidates.Add(hwnd);
            return true;
        }, IntPtr.Zero)) throw new InvalidOperationException("ZIP host window enumeration failed.");
        IntPtr found = IntPtr.Zero;
        foreach (IntPtr hwnd in candidates)
        {
            if (!Match(hwnd, main, pid, password, target)) continue;
            if (found != IntPtr.Zero) throw new InvalidOperationException("Ambiguous ZIP host dialog.");
            found = hwnd;
        }
        if (found == IntPtr.Zero) return false;
        if (!Match(found, main, pid, password, target))
            throw new InvalidOperationException("ZIP host dialog changed before confirmation.");
        if (password)
        {
            var edit = Control(found, 120, pid, "Edit");
            UIntPtr result;
            if (edit == IntPtr.Zero ||
                WriteText(edit, 0x000C, UIntPtr.Zero, fixturePassword, Flags, 2000, out result) == IntPtr.Zero ||
                result == UIntPtr.Zero) throw new InvalidOperationException("ZIP host password rejected.");
        }
        var ok = Control(found, 1, pid, "Button");
        if (!Match(found, main, pid, password, target) || ok == IntPtr.Zero ||
            !IsWindowEnabled(ok) || !PostMessage(found, 0x0111, new IntPtr(1), ok))
            throw new InvalidOperationException("ZIP host verified IDOK failed.");
        return true;
    }
    [DllImport("user32.dll")] private static extern bool EnumChildWindows(IntPtr window, Callback callback, IntPtr arg);
    [DllImport("user32.dll", EntryPoint="SendMessageTimeoutW", SetLastError=true)]
    private static extern IntPtr SendNumber(IntPtr window, uint msg, UIntPtr w, IntPtr l,
        uint flags, uint timeout, out UIntPtr result);
    [DllImport("user32.dll")] private static extern short GetKeyState(int key);

    private static ulong Number(IntPtr hwnd, uint msg, uint value)
    {
        UIntPtr result;
        if (SendNumber(hwnd, msg, new UIntPtr(value), IntPtr.Zero, Flags, 2000, out result) == IntPtr.Zero)
            throw new InvalidOperationException("ZIP mutation control message timed out.");
        return result.ToUInt64();
    }
    private static void SetText(IntPtr hwnd, string value)
    {
        UIntPtr result;
        if (WriteText(hwnd, 0x000C, UIntPtr.Zero, value, Flags, 2000, out result) == IntPtr.Zero ||
            result == UIntPtr.Zero || Text(hwnd) != value)
            throw new InvalidOperationException("ZIP mutation destination rejected.");
    }
    private static string Caption(IntPtr dialog)
    {
        return Text(dialog);
    }
    private static bool HasPrompt(IntPtr dialog, uint pid, string first, string second)
    {
        var controls = new List<IntPtr>();
        EnumChildWindows(dialog, (hwnd, arg) => {
            if (Owned(hwnd, pid) && !IsClass(hwnd, "Button") && IsWindowVisible(hwnd)) controls.Add(hwnd);
            return true;
        }, IntPtr.Zero);
        foreach (var hwnd in controls)
        {
            string text = Text(hwnd);
            if (text.Contains(first, StringComparison.Ordinal) && text.Contains(second, StringComparison.Ordinal))
                return true;
        }
        return false;
    }
    private static bool SamePath(string a, string b)
    {
        return String.Equals(a, b, StringComparison.OrdinalIgnoreCase);
    }
    public static void PostPack(IntPtr main, uint pid)
    {
        if (!Owned(main, pid) || !IsClass(main, "SalamanderMainWindowVer25") ||
            !IsWindowEnabled(main) || !IsWindowVisible(main) ||
            (GetKeyState(0x10) & 0x8000) != 0 || (GetKeyState(0x11) & 0x8000) != 0 ||
            (GetKeyState(0x12) & 0x8000) != 0 ||
            !PostMessage(main, 0x0111, new IntPtr(850), IntPtr.Zero))
            throw new InvalidOperationException("Refusing unverified CM_PACK.");
    }
    // Each phase has distinct resources and text. Never acknowledge an
    // unknown modal, an overwrite-whole-archive button, or a foreign PID.
    private static bool MutationMatch(IntPtr dlg, IntPtr main, uint pid, string phase, string archive, string member, string disk)
    {
        if (!Dialog(dlg, main, pid)) return false;
        if (phase == "Pack")
        {
            var subject = Control(dlg, 209, pid, "Static");
            return subject != IntPtr.Zero && Control(dlg, 210, pid, "ComboBox") != IntPtr.Zero &&
                Control(dlg, 511, pid, "ComboBox") != IntPtr.Zero &&
                Control(dlg, 512, pid, "Button") != IntPtr.Zero &&
                Text(subject).Contains(member, StringComparison.Ordinal);
        }
        if (phase == "Options")
        {
            var name = Control(dlg, 101, pid, "Static");
            return name != IntPtr.Zero && SamePath(Text(name), archive) &&
                Control(dlg, 102, pid, "Button") != IntPtr.Zero &&
                Control(dlg, 104, pid, "Button") != IntPtr.Zero &&
                Control(dlg, 106, pid, "Button") != IntPtr.Zero &&
                Control(dlg, 110, pid, "Button") != IntPtr.Zero;
        }
        if (phase == "Add")
        {
            var yes = Control(dlg, 6, pid, "Button");
            var no = Control(dlg, 7, pid, "Button");
            return yes != IntPtr.Zero && no != IntPtr.Zero &&
                Text(yes).Replace("&", "") == "Add" && Text(no).Replace("&", "") == "Overwrite" &&
                HasPrompt(dlg, pid, System.IO.Path.GetFileName(archive), "into existing archive");
        }
        if (phase == "Replace")
        {
            var oldName = Control(dlg, 181, pid, "Static");
            var newName = Control(dlg, 183, pid, "Static");
            return oldName != IntPtr.Zero && newName != IntPtr.Zero &&
                SamePath(Text(oldName), archive + "\\" + member) && SamePath(Text(newName), disk) &&
                Control(dlg, 185, pid, "Button") != IntPtr.Zero &&
                Control(dlg, 173, pid, "Button") != IntPtr.Zero;
        }
        if (phase == "Delete")
            return Caption(dlg) == "Confirm Delete" && Control(dlg, 7, pid, "Button") != IntPtr.Zero &&
                HasPrompt(dlg, pid, member, "from archive?");
        throw new InvalidOperationException("Unknown ZIP mutation dialog phase.");
    }
    public static bool TryMutation(IntPtr main, uint pid, string phase, string archive, string member, string disk)
    {
        var candidates = new List<IntPtr>();
        if (!EnumWindows((hwnd, arg) => {
            if (Dialog(hwnd, main, pid)) candidates.Add(hwnd);
            return true;
        }, IntPtr.Zero)) throw new InvalidOperationException("ZIP mutation enumeration failed.");
        IntPtr found = IntPtr.Zero;
        foreach (var hwnd in candidates)
        {
            if (!MutationMatch(hwnd, main, pid, phase, archive, member, disk)) continue;
            if (found != IntPtr.Zero) throw new InvalidOperationException("Ambiguous ZIP mutation dialog.");
            found = hwnd;
        }
        if (found == IntPtr.Zero) return false;
        if (!MutationMatch(found, main, pid, phase, archive, member, disk))
            throw new InvalidOperationException("ZIP mutation dialog changed.");
        int id = 1;
        if (phase == "Pack")
        {
            var packer = Control(found, 511, pid, "ComboBox");
            UIntPtr selected;
            if (Text(packer) != "ZIP (Plugin)")
            {
                if (WriteText(packer, 0x0158, new UIntPtr(uint.MaxValue), "ZIP (Plugin)", Flags, 2000, out selected) == IntPtr.Zero ||
                    selected.ToUInt64() > 10000)
                    throw new InvalidOperationException("ZIP (Plugin) packer not available.");
                Number(packer, 0x014E, (uint)selected.ToUInt64()); // CB_SETCURSEL
                UIntPtr notification;
                if (SendNumber(found, 0x0111, new UIntPtr(511u | (1u << 16)), packer, Flags, 2000, out notification) == IntPtr.Zero)
                    throw new InvalidOperationException("ZIP packer selection notification failed.");
            }
            if (Text(packer) != "ZIP (Plugin)") throw new InvalidOperationException("Wrong selected packer.");
            var move = Control(found, 512, pid, "Button");
            Number(move, 0x00F1, 0); // BM_SETCHECK: never delete source files
            if (Number(move, 0x00F0, 0) != 0) throw new InvalidOperationException("Pack move option is checked.");
            SetText(Control(found, 210, pid, "ComboBox"), archive);
        }
        else if (phase == "Options")
        {
            // OnOK reads these exact checkbox states. Do not save preferences.
            foreach (int check in new[] {102,104,106,110})
            {
                var control = Control(found, check, pid, "Button");
                if (Number(control, 0x00F0, 0) != 0)
                    throw new InvalidOperationException("Unexpected ZIP extended option; refusing to change archive type.");
            }
        }
        else id = 6; // Add/Yes only; never Overwrite whole archive or All.
        var button = Control(found, id, pid, "Button");
        if (!MutationMatch(found, main, pid, phase, archive, member, disk) ||
            button == IntPtr.Zero || !IsWindowEnabled(button) || !IsWindowVisible(button) ||
            !PostMessage(found, 0x0111, new IntPtr(id), button))
            throw new InvalidOperationException("ZIP mutation verified confirmation failed.");
        return true;
    }

}
'@

function Test-ZipHostExtraction {
    param([Parameter(Mandatory)]$Fixture)
    # The existing driver has already navigated the active right panel to
    # source. Verify both panels and exact focused row before opening ZIP.
    Assert-True ((Read-PanelPath) -ceq $source) 'ZIP source panel path'
    Send-Keys '{TAB}'
    Assert-True ((Read-PanelPath) -ceq $destination) 'ZIP destination panel path'
    Send-Keys '{TAB}'
    Assert-True ((Read-PanelPath) -ceq $source) 'ZIP source panel active'
    Send-Keys '{END}'
    Assert-True ((Read-FocusedFilename) -ceq 'fixture.zip') 'Exact ZIP fixture selected'
    Assert-True ((Read-FocusedFullname) -ceq $Fixture.Archive) 'Exact ZIP source archive identity'
    Send-Keys '{ENTER}'
    Wait-Until {
        if ($process.HasExited) { throw 'Salamander exited opening ZIP fixture.' }
        $dialog = Get-TestDialog
        if ($dialog) { throw "ZIP open displayed a dialog: $dialog" }
        (Read-PanelPath).TrimEnd([char]92) -ceq $Fixture.Archive
    } 'ZIP archive panel path'
    $process.Refresh()
    $modules = @($process.Modules | Where-Object {
        [string]::Equals($_.FileName, $Fixture.Plugin, [StringComparison]::OrdinalIgnoreCase)
    })
    Assert-True ($modules.Count -eq 1) 'Exact built ZIP plugin loaded in host PID'
    Send-Keys '{END}'
    Assert-True ((Read-FocusedFilename) -ceq 'payload.txt') 'Exact archive member selected'
    Assert-True ((Read-PanelPath).TrimEnd([char]92) -ceq $Fixture.Archive) 'Archive panel identity before copy'
    Assert-True (@(Get-ChildItem -LiteralPath $destination -Force).Count -eq 0) 'Fresh empty ZIP extraction destination'
    [SalamanderGuiNative]::PostVerifiedLargeCopyCommand($mainWindowHandle, [uint32]$process.Id)
    Wait-Until {
        if ($process.HasExited) { throw 'Salamander exited before ZIP extraction confirmation.' }
        [ZipHostDialogs]::TryConfirm($mainWindowHandle, [uint32]$process.Id, $false, $destination, '')
    } 'verified archive copy dialog with exact fixture member and target'
    if ($Fixture.Encrypted) {
        Wait-Until {
            if ($process.HasExited) { throw 'Salamander exited before ZIP password dialog.' }
            [ZipHostDialogs]::TryConfirm($mainWindowHandle, [uint32]$process.Id, $true, $destination, $Fixture.Password)
        } 'verified ZIP plugin password dialog'
        Write-Host 'PASS: ZIP plugin fixture password submitted automatically'
    }
    $target = Join-Path $destination 'payload.txt'
    Wait-Until {
        if ($process.HasExited) { throw 'Salamander exited during ZIP extraction.' }
        if (-not [SalamanderGuiNative]::IsWindowEnabled($mainWindowHandle)) { return $false }
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { return $false }
        try { (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ceq $Fixture.PayloadHash }
        catch [System.IO.IOException] { return $false }
    } 'ZIP plugin extraction with exact SHA-256' -TimeoutSecondsOverride 60
    Assert-True (@(Get-ChildItem -LiteralPath $destination -Force).Count -eq 1) 'Only intended ZIP member extracted'
    Assert-True ((Get-FileHash -LiteralPath $Fixture.Archive -Algorithm SHA256).Hash -ceq $Fixture.ArchiveHash) 'ZIP source archive unchanged'
    Assert-True ((Get-FileHash -LiteralPath $Fixture.SourceFile -Algorithm SHA256).Hash -ceq $Fixture.PayloadHash) 'Independent original ZIP payload unchanged'
    Write-Host "PASS: real ZIP plugin Deflate extraction ($ZipHostEncryption) with SHA-256 integrity."
}
