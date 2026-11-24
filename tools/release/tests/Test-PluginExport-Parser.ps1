#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
# Offline dumpbin regression without VS, plugin binaries or DLL loading.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\Plugin-Export-Parser.ps1')

function Assert-Export {
    param(
        [Parameter(Mandatory)][string]$Report,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Expected,
        [Parameter(Mandatory)][string]$Scenario
    )
    # Act
    $actual = Test-PeNamedExport -Report $Report -Name $Name

    # Assert
    if ($actual -ne $Expected) {
        throw "FAIL: $Scenario (expected $Expected, received $actual)"
    }
    Write-Host "PASS: $Scenario"
}

# Arrange: the public name is left of '='; the internal symbol is C++ decorated.
$decorated = @'
    ordinal hint RVA      name
          1    0 00007F40 SalamanderPluginEntry = ?SalamanderPluginEntry@@YAPEAVCPluginInterfaceAbstract@@PEAVCSalamanderPluginEntryAbstract@@@Z
          2    1 0000AB00 SalamanderPluginGetReqVer = ?SalamanderPluginGetReqVer@@YAHXZ
          3    2 00001000 AddCallStackObject
'@
Assert-Export $decorated 'SalamanderPluginEntry' $true 'C++ decorated internal alias'
Assert-Export $decorated 'SalamanderPluginGetReqVer' $true 'second C++ decorated alias'

# Arrange: actual VS2026 dumpbin /exports output from the user's
# 2026-11-16 Release x64 7zip.spl run. The C++ decorated symbol includes
# a separate human-readable signature containing nested parentheses.
$real7Zip = @'
    ordinal hint RVA      name
          2    1 00008A50 SalamanderPluginEntry = ?SalamanderPluginEntry@@YAPEAVCPluginInterfaceAbstract@@PEAVCSalamanderPluginEntryAbstract@@@Z (class CPluginInterfaceAbstract * __cdecl SalamanderPluginEntry(class CSalamanderPluginEntryAbstract *))
          3    2 00008A10 SalamanderPluginGetReqVer = ?SalamanderPluginGetReqVer@@YAHXZ (int __cdecl SalamanderPluginGetReqVer(void))
'@
Assert-Export $real7Zip 'SalamanderPluginEntry' $true 'actual x64 7zip export with demangled C++ signature'
Assert-Export $real7Zip 'SalamanderPluginGetReqVer' $true 'actual x64 7zip required-version export'
Assert-Export $real7Zip 'SalamanderPluginEntryExtra' $false 'avoid partial match in demangled signature'

# A demangled name must not make an unrelated public alias pass.
$internalOnly = @'
    ordinal hint RVA      name
          2    1 00008A50 InternalOnly = ?SalamanderPluginEntry@@YAPEAXXZ (class CPluginInterfaceAbstract * __cdecl SalamanderPluginEntry(void))
'@
Assert-Export $internalOnly 'SalamanderPluginEntry' $false 'internal-only decorated/demangled symbol is not an export'

# Arrange: simple C exports appear with no alias.
$plain = @'
    ordinal hint RVA      name
          1    0 00001120 SalamanderPluginEntry
          2    1 00001240 SalamanderPluginGetReqVer
'@
Assert-Export $plain 'SalamanderPluginEntry' $true 'plain export without alias'

# Arrange: a substring, internal symbol or report text must not count.
$missing = @'
    ordinal hint RVA      name
          1    0 00001120 SalamanderPluginEntryExtra
          2    1 00001240 InternalOnly = ?SalamanderPluginEntry@@YAXXZ
    message: SalamanderPluginEntry was expected but not exported
'@
Assert-Export $missing 'SalamanderPluginEntry' $false 'reject partial and non-export text'

$forwarded = @'
    ordinal hint RVA      name
          1    0          SalamanderPluginEntry (forwarded to external.dll)
'@
Assert-Export $forwarded 'SalamanderPluginEntry' $false 'reject forwarded or invalid record'

Write-Host 'PASS: dumpbin parser accepts only exact public names in valid export rows.'


# UP-02 RED: source .def files may use either "EXPORTS Name" or a
# conventional EXPORTS section with ordinal/private attributes.
function Assert-DefinitionExport {
    param([string]$Definition, [string]$Name, [bool]$Expected)
    $actual = Test-ModuleDefinitionExport -Definition $Definition -Name $Name
    if ($actual -ne $Expected) {
        throw "Definition export mismatch for '$Name': expected $Expected; actual $actual."
    }
}
$singleLine = @'
LIBRARY 7zip.spl
EXPORTS SalamanderPluginEntry
EXPORTS SalamanderPluginGetReqVer
'@
$multiline = @'
LIBRARY automation.spl
; EXPORTS ForgedExport
EXPORTS
  SalamanderPluginEntry @1 PRIVATE
  SalamanderPluginGetReqVer @2 PRIVATE
  ExtraSymbol=DecoratedName
'@
Assert-DefinitionExport $singleLine 'SalamanderPluginEntry' $true
Assert-DefinitionExport $multiline 'SalamanderPluginEntry' $true
Assert-DefinitionExport $multiline 'SalamanderPluginGetReqVer' $true
Assert-DefinitionExport $multiline 'ForgedExport' $false
Assert-DefinitionExport $multiline 'SalamanderPluginEntryExtra' $false
Assert-DefinitionExport $multiline 'DecoratedName' $false

# The actual Solution sources must all declare the immutable SDK entry
# points. This does not load the DLLs or prove that binaries were shipped.
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$baseline = Get-Content -LiteralPath (
    Join-Path $repository 'tools\release\plugin-source-inventory-baseline.json') -Raw |
    ConvertFrom-Json
$names = [string[]]@($baseline.solutionPluginProjects)
if ($names.Count -ne 33) {
    throw 'Unexpected source plug-in export inventory size.'
}
foreach ($plugin in $names) {
    $relative = if ($plugin -eq 'diskmap') {
        'src\plugins\diskmap\DiskMapPlugin\DiskMapPlugin.def'
    } else {
        "src\plugins\$plugin\$plugin.def"
    }
    $definitionPath = Join-Path $repository $relative
    if (-not (Test-Path -LiteralPath $definitionPath -PathType Leaf)) {
        throw "Missing plug-in .def source: $relative"
    }
    $definition = Get-Content -LiteralPath $definitionPath -Raw -Encoding UTF8
    foreach ($symbol in @('SalamanderPluginEntry',
                          'SalamanderPluginGetReqVer')) {
        if (-not (Test-ModuleDefinitionExport -Definition $definition -Name $symbol)) {
            throw "Missing source SDK export $symbol in $relative"
        }
    }
}
Write-Host "PASS: $($names.Count) declared plug-ins contain both required SDK exports in their .def files."


# UP-02 / RED: release ABI verification must discover every built SPL,
# not silently retain the historic five-module whitelist as complete coverage.
$binaryContract = Get-Content -LiteralPath (
    Join-Path $PSScriptRoot 'Test-PluginBinary-Contract.ps1') -Raw
if (-not $binaryContract.Contains('Get-SalamanderPluginInventory') -or
    -not $binaryContract.Contains('Assert-SalamanderBuiltPluginCompleteness -Inventory $inventory') -or
    -not $binaryContract.Contains('$plugin.BuiltPath') -or
    -not $binaryContract.Contains('Missing required built plug-in binary')) {
    throw 'UP-02: binary ABI audit does not enumerate every built SPL and enforce mandatory plug-ins.'
}
Write-Host 'PASS: built ABI scanner is inventory-driven and preserves mandatory modules.'
