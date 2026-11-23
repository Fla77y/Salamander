#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later

# All filesystem mutations are limited to an owned GUID-scoped temp root.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
. (Join-Path $PSScriptRoot '..\Plugin-CoverageInventory.ps1')

function Assert-EquivalentNames {
    param([string[]]$Expected, [string[]]$Actual, [string]$Description)
    $expectedSorted = [string[]]@($Expected)
    $actualSorted = [string[]]@($Actual)
    [Array]::Sort($expectedSorted, [StringComparer]::OrdinalIgnoreCase)
    [Array]::Sort($actualSorted, [StringComparer]::OrdinalIgnoreCase)
    if (($expectedSorted -join ';') -cne ($actualSorted -join ';')) {
        throw "$Description differs from baseline. Expected: $($expectedSorted -join ','); actual: $($actualSorted -join ',')."
    }
}

function Assert-InventoryRejected {
    param([scriptblock]$Action, [string]$Reason, [string]$ExpectedError)
    $rejected = $false
    try { $null = & $Action }
    catch {
        if (-not $_.Exception.Message.Contains($ExpectedError, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Inventory rejected '$Reason' for the wrong reason: $($_.Exception.Message)"
        }
        $rejected = $true
    }
    if (-not $rejected) { throw "Invalid plug-in inventory accepted: $Reason" }
}

# Frozen source-only baseline is not a proof of shipment or actual UTF-16 support.
$baselinePath = Join-Path $repository 'tools\release\plugin-source-inventory-baseline.json'
$baseline = Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json
if ($baseline.schemaVersion -ne 1) {
    throw 'Unsupported source plug-in inventory baseline schema.'
}
$actual = @(Get-SalamanderPluginInventory -Repository $repository)
$actualSources = @($actual | Where-Object SourceDirectory | ForEach-Object Plugin)
$actualProjects = @($actual | Where-Object SolutionProject | ForEach-Object Plugin)
$actualSourceOnly = @($actual | Where-Object {
    $_.SourceDirectory -and -not $_.SolutionProject
} | ForEach-Object Plugin)
Assert-EquivalentNames -Expected $baseline.sourceDirectories -Actual $actualSources -Description 'Source plug-in directories'
Assert-EquivalentNames -Expected $baseline.solutionPluginProjects -Actual $actualProjects -Description 'Solution plug-in projects'
Assert-EquivalentNames -Expected $baseline.sourceOnlyDirectories -Actual $actualSourceOnly -Description 'Source-only plug-in folders'
if ($actual.Count -ne $baseline.sourceDirectories.Count) {
    throw 'Unexpected module row count without any build.'
}
Write-Host "PASS: source inventory matches $($baseline.solutionPluginProjects.Count) projects and $($baseline.sourceDirectories.Count) source folders."

$rootPrefix = Join-Path ([IO.Path]::GetTempPath()) 'OpenSal-PluginInventory-'
$root = $rootPrefix + [Guid]::NewGuid().ToString('N')
$fake = Join-Path $root 'repository'
$fakePlugins = Join-Path $fake 'src\plugins'
$fakeSolution = Join-Path $fake 'src\vcxproj'
$build = Join-Path $root 'build'
$stage = Join-Path $root 'stage'
try {
    foreach ($directory in @(
        $fakeSolution, (Join-Path $fakePlugins 'alpha'),
        (Join-Path $fakePlugins 'beta'), (Join-Path $fakePlugins 'winscp'),
        (Join-Path $fakePlugins 'shared'),
        (Join-Path $build 'plugins\alpha'),
        (Join-Path $build 'plugins\rogue'),
        (Join-Path $stage 'plugins\alpha'),
        (Join-Path $stage 'plugins\beta')
    )) {
        [void][IO.Directory]::CreateDirectory($directory)
    }
    $solutionText = @'
Project("{8BC9CEB8-8B4A-11D0-8D11-00A0C91BC942}") = "alpha", "..\plugins\alpha\vcxproj\alpha.vcxproj", "{11111111-1111-1111-1111-111111111111}"
EndProject
Project("{8BC9CEB8-8B4A-11D0-8D11-00A0C91BC942}") = "beta", "..\plugins\beta\vcxproj\beta.vcxproj", "{22222222-2222-2222-2222-222222222222}"
EndProject
Project("{8BC9CEB8-8B4A-11D0-8D11-00A0C91BC942}") = "lang_alpha", "..\plugins\alpha\vcxproj\lang_alpha.vcxproj", "{33333333-3333-3333-3333-333333333333}"
EndProject
'@
    [IO.File]::WriteAllText((Join-Path $fakeSolution 'salamand.sln'), $solutionText)
    [IO.File]::WriteAllBytes((Join-Path $build 'plugins\alpha\alpha.spl'), [byte[]](1,2,3))
    [IO.File]::WriteAllBytes((Join-Path $build 'plugins\rogue\rogue.spl'), [byte[]](4,5,6))
    [IO.File]::WriteAllBytes((Join-Path $stage 'plugins\alpha\alpha.spl'), [byte[]](1,2,3))
    [IO.File]::WriteAllBytes((Join-Path $stage 'plugins\beta\beta.spl'), [byte[]](7,8,9))

    $inventory = @(Get-SalamanderPluginInventory -Repository $fake -BuiltDirectory $build -StagedDirectory $stage)
    Assert-EquivalentNames -Expected @('alpha','beta','winscp','rogue') -Actual @($inventory | ForEach-Object Plugin) -Description 'Merged inventory'
    $alpha = @($inventory | Where-Object Plugin -EQ 'alpha')[0]
    $beta = @($inventory | Where-Object Plugin -EQ 'beta')[0]
    $rogue = @($inventory | Where-Object Plugin -EQ 'rogue')[0]
    $winscp = @($inventory | Where-Object Plugin -EQ 'winscp')[0]
    if (-not $alpha.SourceDirectory -or -not $alpha.SolutionProject -or
        $alpha.BuiltModule -cne 'PRESENT' -or $alpha.StagedModule -cne 'PRESENT' -or
        $beta.BuiltModule -cne 'ABSENT' -or $beta.StagedModule -cne 'PRESENT' -or
        $rogue.SourceDirectory -or $rogue.SolutionProject -or
        $rogue.BuiltModule -cne 'PRESENT' -or $rogue.StagedModule -cne 'ABSENT' -or
        -not $winscp.SourceDirectory -or $winscp.SolutionProject -or
        $winscp.BuiltModule -cne 'ABSENT') {
        throw 'Built, staged, source-only or unexpected module classification is incorrect.'
    }

    $operations = @($inventory | Get-SalamanderPluginOperationMatrix)
    if ($operations.Count -ne 48 -or
        @($operations | Where-Object {
            $_.Applicable -cne 'NOT_ASSESSED' -or
            $_.UnicodeStatus -cne 'NOT_TESTED' -or
            $_.LongPathStatus -cne 'NOT_TESTED'
        }).Count -gt 0) {
        throw 'Unverified plug-in operations must not be represented as PASS.'
    }

    $wrong = Join-Path $build 'plugins\alpha\wrong.spl'
    [IO.File]::WriteAllBytes($wrong, [byte[]](0,1,2))
    Assert-InventoryRejected -Action {
        Get-SalamanderPluginInventory -Repository $fake -BuiltDirectory $build
    } -Reason 'misplaced SPL binary' -ExpectedError 'Unexpected built SPL location'
    [IO.File]::Delete($wrong)
    # A root-level SPL must not be omitted simply because it is not in
    # the conventional plugins/<name>/<name>.spl location.
    $rootSPL = Join-Path $build 'rogue-root.spl'
    [IO.File]::WriteAllBytes($rootSPL, [byte[]](4,5,6))
    Assert-InventoryRejected -Action {
        Get-SalamanderPluginInventory -Repository $fake -BuiltDirectory $build
    } -Reason 'SPL outside plugin tree' -ExpectedError 'Unexpected built SPL outside plugins tree'
    [IO.File]::Delete($rootSPL)

    Assert-InventoryRejected -Action {
        Get-SalamanderPluginInventory -Repository $fake -StagedDirectory $stage
    } -Reason 'stage without build context' -ExpectedError 'Staged plug-ins require a build directory'

    # A duplicate top-level project must be diagnosed, not de-duplicated
    # silently into a plausible-looking source inventory.
    [IO.File]::AppendAllText((Join-Path $fakeSolution 'salamand.sln'), $solutionText)
    Assert-InventoryRejected -Action {
        Get-SalamanderPluginInventory -Repository $fake
    } -Reason 'duplicate project declarations' -ExpectedError 'Duplicate Salamander plug-in project'
    [IO.File]::WriteAllText((Join-Path $fakeSolution 'salamand.sln'), $solutionText)

    $reports = Join-Path $root 'reports'
    [void][IO.Directory]::CreateDirectory($reports)
    & (Join-Path $PSScriptRoot '..\Invoke-PluginCoverageInventory.ps1') -Repository $fake -BuiltDirectory $build -StagedDirectory $stage -ReportRoot $reports
    $owned = @(Get-ChildItem -LiteralPath $reports -Directory)
    if ($owned.Count -ne 1 -or
        @(Import-Csv -LiteralPath (Join-Path $owned[0].FullName 'plugins.csv')).Count -ne 4 -or
        @(Import-Csv -LiteralPath (Join-Path $owned[0].FullName 'operations.csv')).Count -ne 48) {
        throw 'Report must include all modules and operations in a unique owned child directory.'
    }
    Write-Host 'PASS: plugin inventory, mismatched module rejection, open statuses and CSV report.'
}
finally {
    $resolved = [IO.Path]::GetFullPath($root)
    if (-not $resolved.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Refusing unknown test-fixture cleanup.'
    }
    if ([IO.Directory]::Exists($resolved)) {
        [IO.Directory]::Delete($resolved, $true)
    }
}
