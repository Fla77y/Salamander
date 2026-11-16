#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
# Static contracts ensure the local runner and manage CLI cannot drift apart.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$manager = Join-Path $root 'tools\Manage-Salamander.ps1'
$runner = Join-Path $root 'tools\release\tests\Invoke-PictViewTests.ps1'

foreach ($path in @($manager, $runner)) {
    # Arrange: parse the exact files that manage.cmd runs.
    $errors = $null
    $tokens = $null
    # Act
    $ast = [Management.Automation.Language.Parser]::ParseFile(
        $path, [ref]$tokens, [ref]$errors)
    # Assert: tests must fail for syntax errors instead of reporting success.
    if ($errors.Count -gt 0 -or -not $ast) {
        throw "PowerShell parse failure in $path : $($errors -join '; ')"
    }
}

$managerText = Get-Content -LiteralPath $manager -Raw
$runnerText = Get-Content -LiteralPath $runner -Raw
$requiredManager = @(
    "'--test-pictview'",
    "'--test-pictview-window'",
    'Invoke-PictViewTests.ps1',
    '-InteractiveWindowTests'
)
foreach ($required in $requiredManager) {
    if (-not $managerText.Contains($required)) {
        throw "manage.ps1 integration lacks required entry: $required"
    }
}

$requiredTests = @(
    'pictview_wic_decode.cpp',
    'pictview_wic_presenter.cpp',
    'pictview_wic_viewer_path.cpp',
    'pictview_wic_transforms.cpp',
    'pictview_wic_writer.cpp',
    'pictview_wic_clipboard.cpp',
    'pictview_wic_window.cpp'
)
foreach ($test in $requiredTests) {
    # Arrange: each native test must be present in the runner and source tree.
    $path = Join-Path $root ('tools\tests\' + $test)
    # Act
    $isRegistered = $runnerText.Contains($test)
    # Assert
    if (-not $isRegistered -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Local runner missing native regression: $test"
    }
}
if ($runnerText -notmatch '/W4 /WX' -or
    $runnerText -notmatch "'x64','x86'" -or
    $runnerText -notmatch '\$LASTEXITCODE -ne 0' -or
    $runnerText -notmatch 'InteractiveWindowTests') {
    throw 'Native PictView runner must enforce MSVC warning-free build, both architectures and proper exit codes.'
}
Write-Host 'PASS: manage and local PictView MSVC test registry/AST contracts.'
