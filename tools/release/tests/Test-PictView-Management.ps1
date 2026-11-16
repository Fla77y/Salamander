#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
# Static contracts ensure the local runner and manage CLI cannot drift apart.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$manager = Join-Path $root 'tools\Manage-Salamander.ps1'
$runner = Join-Path $root 'tools\release\tests\Invoke-PictViewTests.ps1'
$hostScriptPath = Join-Path $root 'tools\release\tests\Test-PictView-Host.ps1'

foreach ($path in @($manager, $runner, $hostScriptPath)) {
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
    '-InteractiveWindowTests',
    "'--test-pictview-host'",
    'Test-PictView-Host.ps1'
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
$hostText = Get-Content -LiteralPath $hostScriptPath -Raw
foreach ($required in @('PictViewHostWindows', 'GetWindowThreadProcessId',
                       'OpenSalamander.PictView.WIC', 'pictview.spl',
                       "SendWait('{F3}')", 'Stop-Process -Id $process.Id',
                       '[IO.File]::ReadAllBytes($fixture)',
                       'GetGUIThreadInfo', 'GetDlgCtrlID', 'IsFileListFocused',
                       'GetInputFocusSummary', 'WM_ACTIVATE', 'Administrator',
                       'PictView SPL was not loaded', 'Viewer associations',
                       'Test-owned windows', 'before sending F3',
                       'EnumChildWindows', 'GetDialogDetails',
                       'Error dialog after F3', 'Copy focused filename',
                       'GetClipboardSequenceNumber')) {
    if (-not $hostText.Contains($required)) {
        throw "PictView host smoke is missing safety contract: $required"
    }
}
# The PR #8 'Test All' guard must not require the unavailable PVW32
# converter after the new WIC viewer passed a real in-host acceptance.
$runtimePath = Join-Path $root 'tools\release\Plugin-Runtime-Prerequisites.ps1'
$guiDriverPath = Join-Path $root 'tools\release\tests\Test-SalamanderGui-LongPaths.ps1'
$runtimeText = Get-Content -LiteralPath $runtimePath -Raw
$guiText = Get-Content -LiteralPath $guiDriverPath -Raw
if ($managerText -notmatch "--test-plugin-load" -or
    $managerText -notmatch "Get-MissingPictViewRuntimeFiles" -or
    $managerText -notmatch "Test-PictView-Host.ps1" -or
    $managerText -notmatch "-WicViewerVerified" -or
    -not $runtimeText.Contains('[switch]$WicViewerVerified') -or
    -not $guiText.Contains('[switch]$WicViewerVerified') -or
    $guiText -notmatch "Get-MissingPictViewRuntimeFiles") {
    throw 'PR8 plugin load gate must first verify the native WIC viewer in Salamander.'
}
Write-Host 'PASS: manage and local PictView MSVC test registry/AST contracts.'
