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
    OriginalDialogAvailable = $dispatch -match 'OpenFindDialog\(owner, ansi\.c_str\(\)\)'
    UnicodeIdentityModel = $header -match 'LegacyFindUtf16Identity UnicodeIdentity'
}
foreach ($check in $checks.Keys) {
    $value = $checks[$check]
    if (-not $value) { throw "Legacy Ctrl+F feature contract missing: $check" }
}
Write-Host 'PASS: original Find dialog, Advanced, regex, grep, filters, results and W identity scaffolding retained.'
