#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later

# Preserve the original Ctrl+F dialog and all existing search capabilities
# throughout the staged UTF-16 migration. Source contract only: this does
# not claim that the current dialog supports Unicode or long paths yet.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).ProviderPath
$source1 = Get-Content -LiteralPath (Join-Path $root 'src\finddlg1.cpp') -Raw
$source2 = Get-Content -LiteralPath (Join-Path $root 'src\finddlg2.cpp') -Raw
$header = Get-Content -LiteralPath (Join-Path $root 'src\find.h') -Raw
$worker = Get-Content -LiteralPath (Join-Path $root 'src\find.cpp') -Raw
$dispatch = Get-Content -LiteralPath (Join-Path $root 'src\fileswn5.cpp') -Raw
$mainDispatch = Get-Content -LiteralPath (Join-Path $root 'src\mainwnd3.cpp') -Raw
$ctrlLetters = Get-Content -LiteralPath (Join-Path $root 'src\mainwnd4.cpp') -Raw
$accelerators = Get-Content -LiteralPath (Join-Path $root 'src\salamand.rc') -Raw
$resource = Get-Content -LiteralPath (Join-Path $root 'src\resource.rh2') -Raw

$checks = [ordered]@{
    OriginalDialog = $source1 -match 'CCommonDialog\(HLanguage, IDD_FIND,'
    AdvancedControls = $source1 -match 'case IDC_FIND_ADVANCED:' -and
        $source1 -match 'IDC_FIND_ADVANCED_TEXT'
    Regex = $source1 -match 'IDC_FIND_REGULAR' -and
        $source1 -match 'GrepData\.RegExp\.Set'
    GrepAndHex = $source1 -match 'IDC_FIND_GREP' -and
        $source1 -match 'IDC_FIND_HEX' -and
        $source1 -match 'IDC_FIND_WHOLE'
    Subdirectories = $source1 -match 'IDC_FIND_INCLUDE_SUBDIR'
    FilterCriteria = $source1 -match 'memmove\(&GrepData\.Criteria, &Data\.Criteria'
    FindDuplicates = $source1 -match 'case CM_FIND_DUPLICATES:'
    FindRefinement = ($source1 -match 'case CM_FIND_INTERSECT:' -and
                      $source1 -match 'case CM_FIND_SUBTRACT:' -and
                      $source1 -match 'case CM_FIND_APPEND:')
    FindOptionsAndIgnore = $header -match 'class CFindAdvancedDialog' -and
        $source1 -match 'FindOptions\.InitMenu' -and
        $source2 -match 'CFindIgnoreDialog::'
    DialogActions = $resource -match 'CM_FIND_DELETE' -and
        $resource -match 'CM_FIND_FOCUS' -and
        $resource -match 'CM_FIND_CLIPCOPYFULLPATH'
    LegacyWorkerPresent = $worker -match 'GrepThreadFBody' -and
        $worker -match 'SearchDirectory\('
    OriginalDialogDefault = $ctrlLetters -match "case 'F':\s+cmd = CM_FINDFILE;" -and
        $mainDispatch -match 'activePanel->FindFile\(LOWORD\(wParam\) == CM_FINDUNICODEFILE\)' -and
        $dispatch -match 'if \(!unicodeDialog\)\s*\{\s*OpenFindDialog\(owner, wideRoot\);\s*return;'
    FindAccelerators = $accelerators -match 'VK_F7,\s+CM_FINDFILE,\s+VIRTKEY,\s+ALT\s*\r?\n' -and
        $accelerators -match 'VK_F7,\s+CM_FINDUNICODEFILE,\s+VIRTKEY,\s+ALT,\s+SHIFT'
    UnicodeIdentityModel = $header -match 'LegacyFindUtf16Identity UnicodeIdentity'
}
foreach ($check in $checks.Keys) {
    $value = $checks[$check]
    if (-not $value) { throw "Legacy Ctrl+F feature contract missing: $check" }
}
Write-Host 'PASS: original Find dispatch, Advanced, regex, grep, filters and result contracts.'

# Inspect the real manager CLI and dispatch, without executing a build or GUI.
$managerPath = Join-Path $root 'tools\Manage-Salamander.ps1'
$managerSource = Get-Content -LiteralPath $managerPath -Raw
$registry = [regex]::Match($managerSource, '(?s)\$validOptions\s*=\s*@\((.*?)\)')
if (!$registry.Groups[1].Value.Contains("'--test-gui-legacy-find'") -or
    $managerSource -notmatch '(?s)\$requestedSet\.Contains\(''--test-gui-legacy-find''\).*?Invoke-IsolatedLegacyFind\.ps1.*?-Configuration'', \$guiMode') {
    throw 'Legacy Find GUI scenarios must run through the automated manager dispatch.'
}

# Regression: closing the duplicate-criteria modal does not guarantee that
# its owner has finished dispatching the search. Require a bounded, read-only
# window-message barrier before reading the results.
$legacyGuiCases = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'LegacyFind-GuiCases.ps1') -Raw
$duplicateCase = [regex]::Match($legacyGuiCases,
    '(?s)function Test-LegacyFindDuplicates\s*\{(.*?)\n\}\s*\nfunction Test-LegacyFindDirectoryLinkCycle').Groups[1].Value
$barrierAt = $duplicateCase.IndexOf('::SendMessageTimeout(', [StringComparison]::Ordinal)
$assertAt = $duplicateCase.IndexOf('Assert-LegacyFindCount', [StringComparison]::Ordinal)
if ([string]::IsNullOrEmpty($duplicateCase) -or $barrierAt -lt 0 -or
    $assertAt -le $barrierAt -or
    $duplicateCase -notmatch '\[uint32\]0,\s*\[UIntPtr\]::Zero' -or
    $duplicateCase -notmatch '\[uint32\]5000') {
    throw 'Legacy Find duplicate GUI test must synchronize modal owner dispatch before reading results.'
}

# A failed row-selection preflight must identify whether the row vanished or
# the keyboard modifier guard prevented injecting navigation keys. Do not
# weaken that guard merely to make flaky integration tests pass.
$driverText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Test-SalamanderGui-LongPaths.ps1') -Raw
$selectInterop = [regex]::Match($driverText,
    '(?s)public static void SelectLegacyFindRow\(.*?\r?\n    \}').Value
foreach ($required in @('LegacyFindResultCount(window, pid)', 'shiftState',
    'controlState', 'altState', '0x8000', 'resultCount=', 'shift=0x',
    'control=0x', 'alt=0x')) {
    if (-not $selectInterop.Contains($required)) {
        throw "Legacy Find selection preflight lacks diagnostic contract: $required"
    }
}
Write-Host 'PASS: Legacy Find result selection preserves its modifier guard and diagnoses rejected indexes.'

$driver = Get-Command -Name (Join-Path $PSScriptRoot 'Test-SalamanderGui-LongPaths.ps1')
$driverCases = ($driver.Parameters['LegacyFindScenario'].Attributes |
    Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).ValidValues
$runner = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Invoke-IsolatedLegacyFind.ps1') -Raw
if (!$runner.Contains("Parameters['LegacyFindScenario'].Attributes") -or
    !$runner.Contains('-IsolatedConfiguration -LegacyFindScenario $case') -or
    !$runner.Contains('if ($LASTEXITCODE -ne 0)')) {
    throw 'The Legacy Find runner must discover driver scenarios, isolate config and propagate failures.'
}
foreach ($case in 'Baseline','UnicodeMasks','UnicodeRootIgnore','FocusLong','ViewMixed','ViewStale') {
    if ($case -notin $driverCases -or $runner -match ("'{0}'" -f $case)) {
        throw "Expected '$case' in the automatically discovered Legacy Find suite."
    }
}
# A timeout in the viewer Copy check must distinguish a command that did
# not change the clipboard from a changed but byte-incorrect selection.
# The diagnostic must not retry input, emit clipboard contents or mark a
# mismatch as PASS; this protects user data and preserves the failure.
$viewerCopyAssert = [regex]::Match($legacyGuiCases,
    '(?s)function Assert-LegacyViewerContents\s*\{(.*?)\r?\n\}\s*\r?\nfunction Test-LegacyFindWideViewer').Groups[1].Value
foreach ($required in @('ClipboardSequenceChanged=', 'ClipboardTextKind=',
                        'ObservedUtf16Length=', 'ExpectedUtf16Length=',
                        'ViewerStillMatches=', 'Viewer copied the exact bytes from the named result')) {
    if (-not $viewerCopyAssert.Contains($required)) {
        throw "Legacy Find Viewer Copy timeout lacks safe diagnosis: $required"
    }
}
if ($viewerCopyAssert -notmatch '(?s)catch\s*\{.*?if \(\$_.Exception.Message -cne' -or
    $viewerCopyAssert -notmatch '\$observed\s*=\s*@\{' -or
    $viewerCopyAssert -notmatch '\$observed\.Sequence' -or
    $viewerCopyAssert -notmatch 'Wait-Until\s*\{' -or
    $viewerCopyAssert -notmatch "GetClipboardSequenceNumber\(\)" -or
    $viewerCopyAssert -notmatch 'Get-ClipboardText') {
    throw 'Viewer Copy diagnostics must preserve exact, bounded clipboard verification.'
}
Write-Host 'PASS: failed Viewer Copy distinguishes unchanged clipboard, mismatched text and lost viewer without replay.'


# QA-03: the targeted ViewUnicode reliability runner must preserve per-run
# logs, a machine-readable summary, binary identity, and orphan detection.
# A single successful rerun does not establish stability.
$reliabilityPath = Join-Path $PSScriptRoot 'Invoke-LegacyViewerReliability.ps1'
if (-not (Test-Path -LiteralPath $reliabilityPath -PathType Leaf)) {
    throw 'QA-03 ViewUnicode repeatability runner missing.'
}
$reliabilitySource = Get-Content -LiteralPath $reliabilityPath -Raw
foreach ($required in @(
    '[ValidateRange(1, 20)]', 'Build-IsolatedGuiTest.ps1',
    'Get-FileHash -LiteralPath $binary', 'Get-Process salamand',
    '-IsolatedConfiguration', '-LegacyFindScenario ViewUnicode',
    'Tee-Object -FilePath $log', 'Export-Csv -LiteralPath $summary',
    'SurvivingProcesses', 'SourceSha', 'BinarySha256',
    'if ($failed -or $orphaned)', 'exit 1'
)) {
    if (-not $reliabilitySource.Contains($required)) {
        throw "QA-03 repeatability runner lacks contract: $required"
    }
}
Write-Host 'PASS: targeted ViewUnicode reliability runner records independent pass/fail evidence.'

Write-Host 'PASS: --test-all dispatches isolated, automatically discovered Legacy Find GUI scenarios.'
