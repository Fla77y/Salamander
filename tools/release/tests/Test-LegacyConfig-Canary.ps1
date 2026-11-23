#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later

# A0-02: synthetic, real-registry RED/GREEN test in a GUID-owned HKCU tree.
# It never opens the user's actual Open Salamander 5.0/5.2 keys.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Registry canary regression requires Windows.' }
. (Join-Path $PSScriptRoot 'LegacyConfig-Canary.ps1')

function Assert-Rejected {
    param([Parameter(Mandatory)][scriptblock]$Action,
          [Parameter(Mandatory)][string]$ExpectedText)
    $rejected = $false
    try { $null = & $Action }
    catch {
        if (-not $_.Exception.Message.Contains(
            $ExpectedText, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Unexpected canary failure: $($_.Exception.Message)"
        }
        $rejected = $true
    }
    if (-not $rejected) { throw "Canary accepted invalid operation: $ExpectedText" }
}

$root = 'Software\Open Salamander\CodexTests\' + [Guid]::NewGuid().ToString('N')
$created = $false
try {
    # Reject unsafe registry paths before even creating a test fixture.
    foreach ($invalid in @('Software\Open Salamander\5.0',
                           'Software\Open Salamander\5.2',
                           'Software\Open Salamander\CodexTests\not-a-guid')) {
        Assert-Rejected -Action {
            Assert-IsolatedLegacyConfigRoot -TestConfigurationKey $invalid
        } -ExpectedText 'GUID-owned isolated'
    }
    $existing = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($root, $false)
    if ($null -ne $existing) {
        $existing.Dispose()
        throw 'Refusing to reuse an existing registry test key.'
    }

    # The GUID namespace belongs to this invocation even if seeding fails
    # halfway through; cleanup must then remove that partial fixture.
    $created = $true
    $digest = New-IsolatedLegacyConfigCanary -TestConfigurationKey $root
    if ($digest -cnotmatch '^[0-9A-F]{64}$') {
        throw 'Legacy registry canary SHA-256 fingerprint is invalid.'
    }
    $newVersion = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey("$root\Config0\Version")
    try {
        $newVersion.SetValue('Configuration', 105,
            [Microsoft.Win32.RegistryValueKind]::DWord)
    }
    finally { $newVersion.Dispose() }

    Assert-IsolatedLegacyConfigPreserved -TestConfigurationKey $root -ExpectedDigest $digest
    # A0-02 RED: registry names containing record separators or newlines
    # must not inject ambiguous records into the canonical snapshot.
    $separatorName = "Pipe|and`nnewline"
    $canary = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(
        "$root\Config1\Configuration\LegacyCanary", $true)
    try {
        $canary.SetValue($separatorName, 'unchanged',
            [Microsoft.Win32.RegistryValueKind]::String)
    }
    finally { $canary.Dispose() }
    $snapshotEntries = [Collections.Generic.List[string]]::new()
    $snapshotRoot = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("$root\Config1", $false)
    try {
        Add-RegistryCanarySnapshot -Key $snapshotRoot -RelativePath 'Config1' -Entries $snapshotEntries
    }
    finally { $snapshotRoot.Dispose() }
    if (@($snapshotEntries | Where-Object { $_.Contains("`n") }).Count -gt 0) {
        throw 'Registry canary snapshot contains unescaped record separators.'
    }
    Assert-Rejected -Action {
        Assert-IsolatedLegacyConfigPreserved -TestConfigurationKey $root -ExpectedDigest $digest
    } -ExpectedText 'configuration changed'
    $canary = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(
        "$root\Config1\Configuration\LegacyCanary", $true)
    try { $canary.DeleteValue($separatorName) }
    finally { $canary.Dispose() }
    Assert-IsolatedLegacyConfigPreserved -TestConfigurationKey $root -ExpectedDigest $digest

    Assert-Rejected -Action {
        $null = New-IsolatedLegacyConfigCanary -TestConfigurationKey $root
    } -ExpectedText 'overwrite an existing isolated'

    # Changing an arbitrary persisted Unicode value must invalidate the
    # entire Config1 snapshot. Never accept a partial/sentinel-only compare.
    $canary = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(
        "$root\Config1\Configuration\LegacyCanary", $true)
    if ($null -eq $canary) { throw 'Missing test-owned legacy canary.' }
    try {
        $canary.SetValue('Unicode', 'changed_日本',
            [Microsoft.Win32.RegistryValueKind]::String)
    }
    finally { $canary.Dispose() }
    Assert-Rejected -Action {
        Assert-IsolatedLegacyConfigPreserved -TestConfigurationKey $root -ExpectedDigest $digest
    } -ExpectedText 'configuration changed'
    $canary = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(
        "$root\Config1\Configuration\LegacyCanary", $true)
    try {
        $canary.SetValue('Unicode', 'Alt-5.0-東京_😀',
            [Microsoft.Win32.RegistryValueKind]::String)
        $canary.SetValue('Binary', [byte[]](0, 1, 2, 128, 255, 43),
            [Microsoft.Win32.RegistryValueKind]::Binary)
    }
    finally { $canary.Dispose() }
    Assert-Rejected -Action {
        Assert-IsolatedLegacyConfigPreserved -TestConfigurationKey $root -ExpectedDigest $digest
    } -ExpectedText 'configuration changed'
    $canary = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(
        "$root\Config1\Configuration\LegacyCanary", $true)
    try {
        $canary.SetValue('Binary', [byte[]](0, 1, 2, 128, 255, 42),
            [Microsoft.Win32.RegistryValueKind]::Binary)
    }
    finally { $canary.Dispose() }

    # Adding a new key must also be detected.
    $unexpected = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey(
        "$root\Config1\Configuration\UnexpectedKey")
    $unexpected.Dispose()
    Assert-Rejected -Action {
        Assert-IsolatedLegacyConfigPreserved -TestConfigurationKey $root -ExpectedDigest $digest
    } -ExpectedText 'configuration changed'
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKey(
        "$root\Config1\Configuration\UnexpectedKey", $false)

    # A numeric-looking REG_SZ must not be accepted as REG_DWORD 105.
    $newVersion = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(
        "$root\Config0\Version", $true)
    try {
        $newVersion.SetValue('Configuration', '105',
            [Microsoft.Win32.RegistryValueKind]::String)
    }
    finally { $newVersion.Dispose() }
    Assert-Rejected -Action {
        Assert-IsolatedLegacyConfigPreserved -TestConfigurationKey $root -ExpectedDigest $digest
    } -ExpectedText 'REG_DWORD'
    $newVersion = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(
        "$root\Config0\Version", $true)
    try {
        $newVersion.SetValue('Configuration', 105,
            [Microsoft.Win32.RegistryValueKind]::DWord)
    }
    finally { $newVersion.Dispose() }

    # Config0 must have its own version number; a downgraded or missing
    # current version must fail even while every 5.0 value remains intact.
    $newVersion = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(
        "$root\Config0\Version", $true)
    try {
        $newVersion.SetValue('Configuration', 104,
            [Microsoft.Win32.RegistryValueKind]::DWord)
    }
    finally { $newVersion.Dispose() }
    Assert-Rejected -Action {
        Assert-IsolatedLegacyConfigPreserved -TestConfigurationKey $root -ExpectedDigest $digest
    } -ExpectedText 'Expected independent 5.2 configuration version'
    $newVersion = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(
        "$root\Config0\Version", $true)
    try {
        $newVersion.SetValue('Configuration', 105,
            [Microsoft.Win32.RegistryValueKind]::DWord)
    }
    finally { $newVersion.Dispose() }

    Assert-IsolatedLegacyConfigPreserved -TestConfigurationKey $root -ExpectedDigest $digest

    # A0-02 release-gate negative: the legacy root itself is deleted.
    # This deliberately mutates only the fresh GUID-owned fake Config1.
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree("$root\Config1", $false)
    Assert-Rejected -Action {
        Assert-IsolatedLegacyConfigPreserved -TestConfigurationKey $root -ExpectedDigest $digest
    } -ExpectedText 'Legacy 5.0 canary root is missing'
    $recreated = New-IsolatedLegacyConfigCanary -TestConfigurationKey $root
    if ($recreated -cne $digest) {
        throw 'Recreated isolated legacy configuration differs from original snapshot.'
    }
    Assert-IsolatedLegacyConfigPreserved -TestConfigurationKey $root -ExpectedDigest $digest
    Write-Host 'PASS: canary detects deletion of 5.0 configuration and restored synthetic snapshot.'
    Write-Host 'PASS: GUID-owned legacy config SHA-256 detects Unicode, binary, structural and version changes without touching user 5.0/5.2 keys.'
}
finally {
    if ($created -and $root -cmatch '^Software\\Open Salamander\\CodexTests\\[0-9a-f]{32}$') {
        [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($root, $false)
    }
}
