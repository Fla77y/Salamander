#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
# Checks the product release label without changing the independent plugin SDK ABI.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$versionHeader = Get-Content -LiteralPath (Join-Path $repository 'src\plugins\shared\spl_vers.h') -Raw
$shellResource = Get-Content -LiteralPath (Join-Path $repository 'src\shellext\shellext.rc') -Raw
$installer = Get-Content -LiteralPath (Join-Path $repository 'tools\release\OpenSalamander.iss') -Raw
$sharedResource = Get-Content -LiteralPath (Join-Path $repository 'src\plugins\shared\versinfo.rc2') -Raw

# Arrange: authoritative product version and all active distribution consumers.
$expectedMajor = 5
$expectedMinor = 1

# Act: inspect the actual release macros and packaging resource declarations.
$major = [regex]::Match($versionHeader, '(?m)^#define\s+VERSINFO_SALAMANDER_MAJOR\s+(\d+)\s*$')
$minor = [regex]::Match($versionHeader, '(?m)^#define\s+VERSINFO_SALAMANDER_MINORA\s+(\d+)\s*$')
$installerVersion = [regex]::Match($installer, '(?m)^AppVersion\s*=\s*([^\r\n]+)\s*$')

# Assert: the EXE, plug-in resources, shell extension and installer agree.
if (-not $major.Success -or -not $minor.Success -or
    [int]$major.Groups[1].Value -ne $expectedMajor -or
    [int]$minor.Groups[1].Value -ne $expectedMinor) {
    throw 'Core product version must be 5.1.'
}
if (-not $installerVersion.Success -or $installerVersion.Groups[1].Value.Trim() -cne '5.1') {
    throw 'Inno Setup AppVersion must be 5.1.'
}
if ($shellResource -notmatch '(?m)^#define\s+FILE_SALVER\s+VERSINFO_xstr\(VERSINFO_SALAMANDER_MAJOR\)\s+"\."\s+VERSINFO_xstr\(VERSINFO_SALAMANDER_MINORA\)' -or
    $shellResource -match '(?m)^#define\s+FILE_SALVER\s+"5\.0"') {
    throw 'Shell extension description must derive the product version from the shared macros.'
}
if ($sharedResource -notmatch '(?m)^\s*PRODUCTVERSION\s+VERSINFO_SALAMANDER_MAJOR,VERSINFO_SALAMANDER_MINORA,VERSINFO_SALAMANDER_MINORB,VERSINFO_BUILDNUMBER') {
    throw 'Win32 VERSIONINFO product metadata must continue to use shared product macros.'
}
# The plugin API level is not the marketing/product version. No plugin ABI change was made.
if ($versionHeader -notmatch '(?m)^#define\s+LAST_VERSION_OF_SALAMANDER\s+103\s*$' -or
    $versionHeader -notmatch 'This plugin requires Open Salamander 5\.0') {
    throw 'Do not raise the minimum compatible plug-in SDK version for a product-label-only change.'
}
Write-Host 'PASS: Open Salamander 5.1 product, installer, shell extension and preserved plugin SDK compatibility.'
