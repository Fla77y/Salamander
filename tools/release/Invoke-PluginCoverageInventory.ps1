#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
    Produce an evidence-only plug-in inventory and operation matrix.
.DESCRIPTION
    Reads the solution, plug-in source folders, and optional build/staging
    trees. Does not load DLLs, change configurations or modify input files.
    An output directory is created only with explicit -ReportRoot.
#>
[CmdletBinding()]
param(
    [string]$Repository = [IO.Path]::GetFullPath(
        (Join-Path $PSScriptRoot '..\..')),
    [string]$BuiltDirectory,
    [string]$StagedDirectory,
    [string]$ReportRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Plugin-CoverageInventory.ps1')

$options = @{ Repository = $Repository }
if (-not [string]::IsNullOrWhiteSpace($BuiltDirectory)) {
    $options.BuiltDirectory = $BuiltDirectory
}
if (-not [string]::IsNullOrWhiteSpace($StagedDirectory)) {
    $options.StagedDirectory = $StagedDirectory
}

$inventory = @(Get-SalamanderPluginInventory @options)
$operations = @($inventory | Get-SalamanderPluginOperationMatrix)
if ($inventory.Count -eq 0 -or $operations.Count -ne (12 * $inventory.Count)) {
    throw 'Plug-in coverage inventory or operation matrix is incomplete.'
}

$inventory | Select-Object Plugin,SourceDirectory,SolutionProject,BuiltModule,StagedModule,Capabilities | Format-Table -AutoSize | Out-String | Write-Host

$sourceOnly = @($inventory | Where-Object {
    $_.SourceDirectory -and -not $_.SolutionProject
})
$noBuild = @($inventory | Where-Object {
    $_.SolutionProject -and $_.BuiltModule -eq 'ABSENT'
})
Write-Host "Inventory: $($inventory.Count) modules, $($operations.Count) operation slots; source-only=$($sourceOnly.Count), project-without-build=$($noBuild.Count)."
Write-Warning 'NOT_ASSESSED / NOT_TESTED entries are open tests, never PASS results.'

if (-not [string]::IsNullOrWhiteSpace($ReportRoot)) {
    # Never overwrite an existing report, even if the caller chooses a
    # non-disposable parent. The GUID directory is owned by this invocation.
    $report = Join-Path $ReportRoot (
        'Salamander-PluginCoverage-' + [Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($report)
    $inventory | Export-Csv -LiteralPath (Join-Path $report 'plugins.csv') -NoTypeInformation -Encoding UTF8
    $operations | Export-Csv -LiteralPath (Join-Path $report 'operations.csv') -NoTypeInformation -Encoding UTF8
    Write-Host "Generated read-only inventory reports: $report"
}
