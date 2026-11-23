#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
    Inspect or explicitly enable Windows Error Reporting local dumps for salamand.exe.
.DESCRIPTION
    ReadOnly status is the default. -Enable requires an elevated PowerShell
    and writes only application-specific HKLM LocalDumps entries. Existing
    entries are never overwritten; no crash is triggered and no data uploaded.
.EXAMPLE
    pwsh -NoProfile -File .\tools\release\Configure-LocalCrashDumps.ps1
.EXAMPLE
    pwsh -NoProfile -File .\tools\release\Configure-LocalCrashDumps.ps1 -Enable
#>
[CmdletBinding()]
param([switch]$Enable)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'WER local dumps require Windows.' }

$application = 'salamand.exe'
$subkey = 'SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\' + $application
$views = @([Microsoft.Win32.RegistryView]::Registry32)
if ([Environment]::Is64BitOperatingSystem) {
    $views = @([Microsoft.Win32.RegistryView]::Registry64,
               [Microsoft.Win32.RegistryView]::Registry32)
}

if (-not $Enable) {
    # ReadOnly status; does not create keys or write registry data.
    foreach ($view in $views) {
        $hive = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine, $view)
        try {
            $key = $hive.OpenSubKey($subkey, $false)
            if ($null -eq $key) {
                Write-Host "WER LocalDumps ($view): not configured for $application"
                continue
            }
            try {
                Write-Host ("WER LocalDumps ({0}): DumpType={1}; DumpCount={2}; folder={3}" -f
                    $view, $key.GetValue('DumpType', '<default>'),
                    $key.GetValue('DumpCount', '<default>'),
                    $key.GetValue('DumpFolder', '%LOCALAPPDATA%\CrashDumps'))
            }
            finally { $key.Dispose() }
        }
        finally { $hive.Dispose() }
    }
    return
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'WER LocalDumps requires elevated PowerShell. No registry changes made.'
}

# Preflight both architecture views before making any changes. Do not take over
# existing settings created by an administrator or another diagnostic tool.
foreach ($view in $views) {
    $hive = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine, $view)
    try {
        $existing = $hive.OpenSubKey($subkey, $false)
        if ($null -ne $existing) {
            $existing.Dispose()
            throw "Existing WER settings for $application ($view). Refusing to overwrite."
        }
    }
    finally { $hive.Dispose() }
}

foreach ($view in $views) {
    $hive = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine, $view)
    try {
        $key = $hive.CreateSubKey($subkey)
        if ($null -eq $key) { throw "Cannot create WER LocalDumps for $view." }
        try {
            # MiniDump (1), at most ten files. Use Windows' standard per-user
            # %LOCALAPPDATA%\CrashDumps directory, retaining its existing ACLs.
            $key.SetValue('DumpType', 1, [Microsoft.Win32.RegistryValueKind]::DWord)
            $key.SetValue('DumpCount', 10, [Microsoft.Win32.RegistryValueKind]::DWord)
        }
        finally { $key.Dispose() }
        Write-Host "Enabled local WER minidumps for $application ($view)."
    }
    finally { $hive.Dispose() }
}
Write-Host 'This tool does not configure or trigger automatic crash-report uploads.'
