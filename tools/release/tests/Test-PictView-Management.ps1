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
    'pictview_wic_formats.cpp',
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
# Prevent PictView from advertising an extension without an executable
# decoder test. Check that the advertised viewer and thumbnail extensions
# are precisely the extensions in the native codec regression.
$pluginSource = Get-Content -LiteralPath (Join-Path $root 'src\plugins\pictview\pictview.cpp') -Raw
$formatsSource = Get-Content -LiteralPath (Join-Path $root 'tools\tests\pictview_wic_formats.cpp') -Raw
$viewer = [regex]::Match($pluginSource, 'AddViewer\("(?<extensions>\*\.[^"]+)", FALSE\)')
$thumbnails = [regex]::Match($pluginSource, 'SetThumbnailLoader\("(?<extensions>\*\.[^"]+)"\)')
if (-not $viewer.Success -or -not $thumbnails.Success) {
    throw 'PictView WIC viewer or thumbnail format registration was not found.'
}
$viewExtensions = @($viewer.Groups['extensions'].Value -split ';' | ForEach-Object {
    $match = [regex]::Match($_, '^\*\.([a-z0-9]+)$')
    if (-not $match.Success) { throw "Invalid PictView extension: $_" }
    $match.Groups[1].Value
})
$thumbExtensions = @($thumbnails.Groups['extensions'].Value -split ';' | ForEach-Object {
    $match = [regex]::Match($_, '^\*\.([a-z0-9]+)$')
    if (-not $match.Success) { throw "Invalid thumbnail extension: $_" }
    $match.Groups[1].Value
})
$testedExtensions = @([regex]::Matches($formatsSource, '(?m)^\s*\{L"(?<extension>[a-z0-9]+)",') |
    ForEach-Object { $_.Groups['extension'].Value })
$viewSorted = @($viewExtensions | Sort-Object)
$thumbSorted = @($thumbExtensions | Sort-Object)
$testedSorted = @($testedExtensions | Sort-Object)
if ($viewExtensions.Count -eq 0 -or
    @($viewExtensions | Select-Object -Unique).Count -ne $viewExtensions.Count -or
    @($testedExtensions | Select-Object -Unique).Count -ne $testedExtensions.Count -or
    ($viewSorted -join ';') -cne ($thumbSorted -join ';') -or
    ($viewSorted -join ';') -cne ($testedSorted -join ';')) {
    throw ('PictView advertised WIC format coverage differs from native tests: ' +
           "Viewer=$($viewSorted -join ','); Thumbnail=$($thumbSorted -join ','); " +
           "Tests=$($testedSorted -join ',')")
}
Write-Host "PASS: PictView WIC codec regressions cover all $($testedExtensions.Count) advertised extensions."

# Format acceptance must also reject damaged input, invalid arguments and
# out-of-range frames without leaking the prior decode or frame count.
foreach ($required in @(
    'TestDecodeFailuresAreAtomic',
    'TestInvalidFrameDoesNotReturnPixels',
    'TestAnimatedGifFrameNavigation',
    'second animated GIF frame has green pixels',
    'truncated WIC image',
    'missing WIC image',
    'invalid WIC filename',
    'out-of-range WIC frame',
    'ReadFixtureBytes(file, before)',
    'ReadFixtureBytes(file, after)',
    'before == after'
)) {
    if (-not $formatsSource.Contains($required)) {
        throw "PictView native format matrix lacks fail-closed regression: $required"
    }
}


if ($runnerText -notmatch '/W4 /WX' -or
    $runnerText -notmatch "'x64','x86'" -or
    $runnerText -notmatch '\$LASTEXITCODE -ne 0' -or
    $runnerText -notmatch 'InteractiveWindowTests') {
    throw 'Native PictView runner must enforce MSVC warning-free build, both architectures and proper exit codes.'
}
# Ensure the ABI command also checks the production PictView SPL.
# Previously only four unrelated plug-ins had exact PE export verification.
$abiScript = Join-Path $root 'tools\release\tests\Test-PluginBinary-Contract.ps1'
$abiText = Get-Content -LiteralPath $abiScript -Raw
$pictviewDef = Join-Path $root 'src\plugins\pictview\pictview.def'
if (-not $abiText.Contains("'pictview'") -or
    -not (Test-Path -LiteralPath $pictviewDef -PathType Leaf)) {
    throw 'PictView x64 binary must be checked by the local plugin export ABI gate.'
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
# A rejected HWND must never activate or interact with another application.
if ([PictViewHostWindows]::TryActivateVerifiedWindow(
        [IntPtr]::Zero, [uint32]0, $true)) {
    throw 'PictView host foreground helper accepted a zero HWND/PID.'
}
foreach ($required in @('PictViewHostWindows', 'GetWindowThreadProcessId',
                       'OpenSalamander.PictView.WIC', 'pictview.spl',
                       "SendWait('{F3}')", 'Stop-Process -Id $process.Id',
                       '[IO.File]::ReadAllBytes($fixture)',
                       'GetGUIThreadInfo', 'GetDlgCtrlID', 'IsFileListFocused',
                       'GetInputFocusSummary', 'WM_ACTIVATE', 'Administrator',
                       'Get-PictViewHostFailureHint', 'PictView-HostDiagnostics.ps1',
                       'Test-owned windows', 'before sending F3',
                       'EnumChildWindows', 'GetDialogDetails',
                       'Error dialog after F3', 'exactly one isolated',
                       'TryActivateVerifiedWindow', 'AttachThreadInput',
                       'BringWindowToTop', 'GetCurrentThreadId',
                       'Focus-TestOwnedSalamander', 'useSharedInputFallback',
                       'GetForegroundOwnerSummary')) {
    if (-not $hostText.Contains($required)) {
        throw "PictView host smoke is missing safety contract: $required"
    }
}

# Ensure the actual Save Copy encoder (not just suffix selection) is exercised
# for every format the WIC viewer offers for export.
$writerSource = Get-Content -LiteralPath (Join-Path $root 'tools\tests\pictview_wic_writer.cpp') -Raw
foreach ($required in @('TestAdditionalWicExportFormats',
    'ImageFileFormat::Bmp', 'ImageFileFormat::Jpeg',
    'ImageFileFormat::Tiff', 'ERROR_FILE_EXISTS',
    'DecodeFirstFrame')) {
    if (-not $writerSource.Contains($required)) {
        throw "PictView Save Copy lacks executable format regression: $required"
    }
}

# The real F3 host smoke is deliberately opt-in and must exercise the
# common WIC formats through isolated GUI processes. No format may be skipped
# by successful native decoding alone.
foreach ($imageFormat in @('Bmp','Png','Jpeg','Gif','Tiff','Ico')) {
    if (-not $managerText.Contains("'$imageFormat'") -or
        -not $hostText.Contains("'$imageFormat'")) {
        throw "PictView opt-in F3 host acceptance omits $imageFormat."
    }
}
if (-not $hostText.Contains('[string]$ImageFormat') -or
    -not $hostText.Contains('$bitmap.Save($fixture, $imageCodec)') -or
    -not $hostText.Contains('[IO.File]::WriteAllBytes($fixture, $iconBytes)') -or
    -not $managerText.Contains('''-ImageFormat'', $imageFormat') -or
    -not $managerText.Contains('if ($requestedSet.Contains(''--test-pictview-host''))')) {
    throw 'PictView format host acceptance must use F3 with a real single-image fixture.'
}
Write-Host 'PASS: opt-in PictView F3 host smoke covers BMP, PNG, JPEG, GIF, TIFF and ICO.'

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
    -not $externalHint.Contains('Do not create a placeholder')) {
    throw 'Missing external viewer variable must produce a precise non-mutating diagnosis.'
}
$internalHint = Get-PictViewHostFailureHint -ActualViewerClass "Salamander's Viewer Window"
if (-not $internalHint.Contains('internal text viewer') -or
    -not $internalHint.Contains('*.bmp') -or
    -not $internalHint.Contains('PictView') -or
    $internalHint.Contains('X8D_BIN_TOOLS_PATH')) {
    throw 'Internal viewer selection must fail with a specific PictView association diagnosis.'
}
if (-not $hostText.Contains('Salamander''s Viewer Window')) {
    throw 'Host GUI smoke must detect the actual internal viewer HWND without timeout.'
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
