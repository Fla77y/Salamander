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
# The host GUI is opt-in, but its embedded Win32 interop code must compile
# on every ordinary Windows CI invocation. Syntax-only parsing does not
# validate the C# here-string passed to Add-Type at runtime.
$hostInterop = [regex]::Match(
    $hostText, "(?s)Add-Type -TypeDefinition @'\r?\n(?<code>.*?)\r?\n'@")
if (-not $hostInterop.Success) {
    throw 'PictView host Win32 interop here-string was not found.'
}
Add-Type -TypeDefinition $hostInterop.Groups['code'].Value -ErrorAction Stop
foreach ($required in @('PictViewHostWindows', 'GetWindowThreadProcessId',
                       'OpenSalamander.PictView.WIC', 'pictview.spl',
                       "SendWait('{F3}')", 'Stop-Process -Id $process.Id',
                       '[IO.File]::ReadAllBytes($fixture)',
                       'GetGUIThreadInfo', 'GetDlgCtrlID', 'IsFileListFocused',
                       'GetInputFocusSummary', 'WM_ACTIVATE', 'Administrator',
                       'Get-PictViewHostFailureHint', 'PictView-HostDiagnostics.ps1',
                       'Test-owned windows', 'before sending F3',
                       'EnumChildWindows', 'GetDialogDetails',
                       'Error dialog after F3', 'single BMP fixture',
                       'GetDialogDetails')) {
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
# Regression: WaitForInputIdle only proves that a window can process input.
# The asynchronous startup/configuration phase applies -l/-r panel paths later.
# Never read a one-time title snapshot as proof of final navigation.
if (-not $hostText.Contains("'-l ""{0}"" -r ""{0}"" -p 2'") -or
    -not $hostText.Contains("Wait-For -Description 'Salamander command-line panel paths applied'") -or
    -not $hostText.Contains("[PictViewHostWindows]::GetWindowCaption(") -or
    $hostText.Contains('if ($main.Title -notmatch [regex]::Escape((Split-Path -Leaf $root)))')) {
    throw 'Host GUI test must wait for the configured active-panel path to be applied before F3.'
}
# The missing X8D variable is a deterministic regression fixture, not a
# real dependency and never an environment variable created by the tests.
$diagnosticFile = Join-Path $root 'tools\release\tests\PictView-HostDiagnostics.ps1'
$parseErrors = $null
$tokens = $null
$diagnosticAst = [Management.Automation.Language.Parser]::ParseFile(
    $diagnosticFile, [ref]$tokens, [ref]$parseErrors)
if (-not $diagnosticAst -or $parseErrors.Count -gt 0) {
    throw "PictView diagnostics script has syntax errors: $($parseErrors -join '; ')"
}
. $diagnosticFile

$externalViewerDialog = '[Error] [Static] Environment variable "X8D_BIN_TOOLS_PATH" was not found. | [Button] &Ignore | [Button] Cancel'
$externalHint = Get-PictViewHostFailureHint -DialogText $externalViewerDialog -PictViewResident $false
if (-not $externalHint.Contains('X8D_BIN_TOOLS_PATH') -or
    -not $externalHint.Contains('*.bmp') -or
    -not $externalHint.Contains('PictView') -or
    -not $externalHint.Contains('external Viewer') -or
    -not $externalHint.Contains('Do not create a placeholder') -or
    [Environment]::GetEnvironmentVariable('X8D_BIN_TOOLS_PATH') -ne $null) {
    # The environment variable must NOT be fabricated in this test.
    # A host running with this variable already configured is legitimate;
    # test only the returned diagnostic in that case.
    if (-not $externalHint.Contains('X8D_BIN_TOOLS_PATH') -or
        -not $externalHint.Contains('*.bmp') -or
        -not $externalHint.Contains('Do not create a placeholder')) {
        throw 'Missing external viewer variable must produce a precise non-mutating diagnosis.'
    }
}
$genericHint = Get-PictViewHostFailureHint -DialogText '[Error] [Static] Unable to decode BMP' -PictViewResident $true
if ($genericHint.Contains('X8D_BIN_TOOLS_PATH') -or
    $genericHint.Contains('external Viewer') -or
    -not $genericHint.Contains('WIC viewer window')) {
    throw 'Unrelated WIC viewer failures must not be misdiagnosed as external viewer configuration.'
}
$unloadedHint = Get-PictViewHostFailureHint -DialogText '' -PictViewResident $false
if (-not $unloadedHint.Contains('PictView SPL is not resident')) {
    throw 'Unloaded PictView requires an explicit non-committal diagnostic.'
}
Write-Host 'PASS: manage and local PictView MSVC test registry/AST contracts.'
