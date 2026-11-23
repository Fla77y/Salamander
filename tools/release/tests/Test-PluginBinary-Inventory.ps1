#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
# Offline, deterministic tests for discovery of built Salamander plug-ins.
# No actual binary is loaded, executed or modified.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\Plugin-Binary-Inventory.ps1')

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('salamander-plugin-inventory-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory((Join-Path $testRoot 'plugins'))
try {
    # Arrange: no built modules.
    # Act
    $empty = @(Get-BuiltPluginNames -BuildDirectory $testRoot)
    # Assert
    if ($empty.Count -ne 0) { throw 'An empty plug-in inventory must return no names.' }

    # Arrange: conventional modules, plus one whose real project uses a
    # differently located module-definition file (DiskMapPlugin.def).
    foreach ($name in @('pictview','diskmap')) {
        $folder = Join-Path $testRoot "plugins\$name"
        [void][IO.Directory]::CreateDirectory($folder)
        [IO.File]::WriteAllBytes((Join-Path $folder "$name.spl"), [byte[]](0, 1, 2))
    }
    # Act
    $found = @(Get-BuiltPluginNames -BuildDirectory $testRoot | Sort-Object)
    # Assert
    if (($found -join ';') -cne 'diskmap;pictview') {
        throw "Built modules were omitted or misidentified: $($found -join ',')"
    }

    # Arrange: an extra SPL in an unexpected directory must not be ignored.
    $unexpected = Join-Path $testRoot 'plugins\unrelated\wrong.spl'
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $unexpected))
    [IO.File]::WriteAllBytes($unexpected, [byte[]](0, 1, 2))
    # Act / Assert
    $rejected = $false
    try { $null = @(Get-BuiltPluginNames -BuildDirectory $testRoot) }
    catch [InvalidOperationException] { $rejected = $true }
    if (-not $rejected) { throw 'Mismatched SPL filename and plug-in directory was accepted.' }

    # Arrange: a nested module cannot silently be skipped.
    [IO.File]::Delete($unexpected)
    $nested = Join-Path $testRoot 'plugins\pictview\nested\extra.spl'
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $nested))
    [IO.File]::WriteAllBytes($nested, [byte[]](0, 1, 2))
    # Act / Assert
    $rejected = $false
    try { $null = @(Get-BuiltPluginNames -BuildDirectory $testRoot) }
    catch [InvalidOperationException] { $rejected = $true }
    if (-not $rejected) { throw 'Nested unexpected SPL file was silently accepted.' }

    Write-Host 'PASS: complete built SPL inventory, alternate .def paths, unexpected path rejection.'
}
finally {
    if (Test-Path -LiteralPath $testRoot -PathType Container) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
