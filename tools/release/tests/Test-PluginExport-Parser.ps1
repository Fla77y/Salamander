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
