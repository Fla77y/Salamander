#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
    Static regression checks for the GUI driver's Win32 message contract.
.DESCRIPTION
    Parses the driver without launching Salamander or requiring a desktop.
    The real interactive GUI tests remain mandatory.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$driverPath = Join-Path $PSScriptRoot 'Test-SalamanderGui-LongPaths.ps1'
$tokens = $null
$errors = $null
$tree = [System.Management.Automation.Language.Parser]::ParseFile(
    $driverPath, [ref]$tokens, [ref]$errors)
if (@($errors).Count -gt 0) {
    throw "GUI driver contains PowerShell parse errors: $($errors -join '; ')"
}

function Get-FunctionSource {
    param([Parameter(Mandatory)][string]$Name)

    $matches = @($tree.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -ceq $Name
    }, $true))
    if ($matches.Count -ne 1) {
        throw "Expected exactly one GUI driver function '$Name'; found $($matches.Count)."
    }
    return $matches[0]
}

$navigate = Get-FunctionSource 'Go-ToPath'
$reads = @($navigate.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.CommandAst] -and
    $node.GetCommandName() -ceq 'Read-PanelPath'
}, $true))
if ($reads.Count -ne 1) {
    throw "Go-ToPath must read the panel path once per polling iteration, not again after success; found $($reads.Count) call sites."
}
if ($navigate.Extent.Text -notmatch 'Assert-True\s+\(\$diagnostics\.PanelPath\s+-ceq\s+\$Path\)') {
    throw 'Go-ToPath must assert the path already observed in the successful polling iteration.'
}
# The baseline's Go-ToPath invocation already establishes the panel path.
# Do not repeat Read-PanelPath immediately outside that function either.
$driverText = $tree.Extent.Text
# Read-PanelPath after a later panel switch is legitimate: prohibit only
# the immediate extra assertion following the *initial* Go-ToPath $source.
if ($driverText -match 'Go-ToPath\s+\$source\s+Assert-True\s+\(\(Read-PanelPath\)\s+-ceq\s+\$source\)') {
    throw 'Initial baseline must reuse the verified navigation result, not issue a second WM_COMMAND 711.'
}
if ($driverText -notmatch 'Go-ToPath\s+\$source') {
    throw 'Baseline must still navigate and verify its short ASCII source path.'
}
Write-Host 'PASS: GUI baseline has no redundant read after verified navigation.'

Write-Host 'PASS: GUI navigation reuses the observed path without a redundant WM_COMMAND.'

$dispatch = Get-FunctionSource 'Invoke-SalamanderCommand'
$source = $dispatch.Extent.Text
$errorCapture = $source.IndexOf(
    '$lastError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()',
    [StringComparison]::Ordinal)
$dialogLookup = $source.IndexOf('$dialog = Get-TestDialog',
    [StringComparison]::Ordinal)
if ($errorCapture -lt 0 -or $dialogLookup -lt 0 -or
    $errorCapture -gt $dialogLookup) {
    throw 'SendMessageTimeout last-error must be captured before invoking any diagnostic Win32 call.'
}
Write-Host 'PASS: GUI driver captures the original SendMessageTimeout Win32 error.'
