#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
#
# A0-02: Test-only 5.0 registry-root canary in an isolated GUI namespace.
# No function ever reads or writes the user's real 5.0/5.2 keys.

function Assert-IsolatedLegacyConfigRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TestConfigurationKey)

    if ($TestConfigurationKey -cnotmatch '^Software\\Open Salamander\\CodexTests\\[0-9a-f]{32}$') {
        throw 'Legacy canary requires a GUID-owned isolated configuration root.'
    }
}

function Add-RegistryCanarySnapshot {
    param(
        [Parameter(Mandatory)][Microsoft.Win32.RegistryKey]$Key,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][Collections.Generic.List[string]]$Entries
    )

    # Registry key/value names may contain pipes and newlines. Encode names
    # before joining records so distinct snapshots cannot share a digest.
    $pathToken = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($RelativePath))
    $Entries.Add("KEY|$pathToken")
    foreach ($name in @($Key.GetValueNames() | Sort-Object -CaseSensitive)) {
        $kind = $Key.GetValueKind($name)
        $value = $Key.GetValue($name, $null,
            [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $serialized = if ($value -is [byte[]]) {
            [Convert]::ToBase64String($value)
        }
        elseif ($value -is [string[]]) {
            @($value | ForEach-Object { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($_)) }) -join ','
        }
        else {
            [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(
                [Convert]::ToString($value, [Globalization.CultureInfo]::InvariantCulture)))
        }
        $nameToken = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($name))
        $Entries.Add("VALUE|$pathToken|$nameToken|$kind|$serialized")
    }

    foreach ($child in @($Key.GetSubKeyNames() | Sort-Object -CaseSensitive)) {
        $next = $Key.OpenSubKey($child, $false)
        if ($null -eq $next) {
            throw "Canary key disappeared during snapshot: $RelativePath\$child"
        }
        try {
            Add-RegistryCanarySnapshot -Key $next -RelativePath "$RelativePath\$child" -Entries $Entries
        }
        finally { $next.Dispose() }
    }
}

function Get-IsolatedLegacyConfigDigest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TestConfigurationKey)

    Assert-IsolatedLegacyConfigRoot -TestConfigurationKey $TestConfigurationKey
    $root = "$TestConfigurationKey\Config1"
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($root, $false)
    if ($null -eq $key) {
        throw "Legacy 5.0 canary root is missing: $root"
    }
    try {
        $entries = [Collections.Generic.List[string]]::new()
        Add-RegistryCanarySnapshot -Key $key -RelativePath 'Config1' -Entries $entries
        $encoded = [Text.Encoding]::UTF8.GetBytes(($entries.ToArray() -join ([char]10)))
        return [Convert]::ToHexString(
            [Security.Cryptography.SHA256]::HashData($encoded))
    }
    finally { $key.Dispose() }
}

function New-IsolatedLegacyConfigCanary {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TestConfigurationKey)

    Assert-IsolatedLegacyConfigRoot -TestConfigurationKey $TestConfigurationKey
    $root = "$TestConfigurationKey\Config1"
    $existing = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($root, $false)
    if ($null -ne $existing) {
        $existing.Dispose()
        throw 'Refusing to overwrite an existing isolated 5.0 configuration.'
    }

    # The original Open Salamander 5.0 source uses config version 104.
    # Test only namespaced roots; Config0 is the independent 5.2 root.
    $version = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey("$root\Version")
    try {
        $version.SetValue('Configuration', 104,
            [Microsoft.Win32.RegistryValueKind]::DWord)
    }
    finally { $version.Dispose() }

    $data = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey(
        "$root\Configuration\LegacyCanary")
    try {
        $data.SetValue('Unicode', 'Alt-5.0-東京_😀',
            [Microsoft.Win32.RegistryValueKind]::String)
        $data.SetValue('Binary', [byte[]](0, 1, 2, 128, 255, 42),
            [Microsoft.Win32.RegistryValueKind]::Binary)
    }
    finally { $data.Dispose() }
    return Get-IsolatedLegacyConfigDigest -TestConfigurationKey $TestConfigurationKey
}

function Assert-IsolatedLegacyConfigPreserved {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TestConfigurationKey,
        [Parameter(Mandatory)][ValidatePattern('^[0-9A-F]{64}$')][string]$ExpectedDigest,
        [int]$ExpectedNewConfigVersion = 105
    )

    Assert-IsolatedLegacyConfigRoot -TestConfigurationKey $TestConfigurationKey
    $actualDigest = Get-IsolatedLegacyConfigDigest -TestConfigurationKey $TestConfigurationKey
    if ($actualDigest -cne $ExpectedDigest) {
        throw 'Isolated Open Salamander 5.0 configuration changed during 5.2 startup.'
    }
    $version = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(
        "$TestConfigurationKey\Config0\Version", $false)
    if ($null -eq $version) {
        throw 'Missing isolated 5.2 configuration version.'
    }
    try {
        $actualKind = $version.GetValueKind('Configuration')
        if ($actualKind -ne [Microsoft.Win32.RegistryValueKind]::DWord) {
            throw "Expected independent 5.2 configuration version as REG_DWORD; found $actualKind."
        }
        $actualVersion = [int]$version.GetValue('Configuration', 0)
    }
    finally { $version.Dispose() }
    if ($actualVersion -ne $ExpectedNewConfigVersion) {
        throw "Expected independent 5.2 configuration version $ExpectedNewConfigVersion; found $actualVersion."
    }
}
