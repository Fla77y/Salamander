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
        (Join-Path $fakePlugins 'alpha\vcxproj'),
        (Join-Path $fakePlugins 'beta\vcxproj'),
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
    $alphaProject = Join-Path $fakePlugins 'alpha\vcxproj\alpha.vcxproj'
    $betaProject = Join-Path $fakePlugins 'beta\vcxproj\beta.vcxproj'
    [IO.File]::WriteAllText($alphaProject, '<Project />')
    [IO.File]::WriteAllText($betaProject, '<Project />')
    [IO.File]::WriteAllBytes((Join-Path $build 'plugins\alpha\alpha.spl'), [byte[]](1,2,3))
    [IO.File]::WriteAllBytes((Join-Path $build 'plugins\rogue\rogue.spl'), [byte[]](4,5,6))
    [IO.File]::WriteAllBytes((Join-Path $stage 'plugins\alpha\alpha.spl'), [byte[]](1,2,3))
    [IO.File]::WriteAllBytes((Join-Path $stage 'plugins\beta\beta.spl'), [byte[]](7,8,9))

    # RED: a solution declaration does not prove its vcxproj file exists.
    [IO.File]::Delete($alphaProject)
    Assert-InventoryRejected -Action {
        Get-SalamanderPluginInventory -Repository $fake
    } -Reason 'declared vcxproj is absent' -ExpectedError 'Declared Salamander plug-in project missing'
    [IO.File]::WriteAllText($alphaProject, '<Project />')

    $inventory = @(Get-SalamanderPluginInventory -Repository $fake -BuiltDirectory $build -StagedDirectory $stage)
    Assert-EquivalentNames -Expected @('alpha','beta','winscp','rogue') -Actual @($inventory | ForEach-Object Plugin) -Description 'Merged inventory'
    $alpha = @($inventory | Where-Object Plugin -EQ 'alpha')[0]
    $beta = @($inventory | Where-Object Plugin -EQ 'beta')[0]
    $rogue = @($inventory | Where-Object Plugin -EQ 'rogue')[0]
    $winscp = @($inventory | Where-Object Plugin -EQ 'winscp')[0]
    if (-not $alpha.SourceDirectory -or -not $alpha.SolutionProject -or
        $alpha.BuiltModule -cne 'PRESENT' -or $alpha.StagedModule -cne 'PRESENT' -or
        $alpha.PayloadStatus -cne 'MATCH' -or $alpha.BuiltSHA256 -cne $alpha.StagedSHA256 -or
        $beta.BuiltModule -cne 'ABSENT' -or $beta.StagedModule -cne 'PRESENT' -or
        $beta.PayloadStatus -cne 'MISSING_BUILT' -or
        $rogue.SourceDirectory -or $rogue.SolutionProject -or
        $rogue.BuiltModule -cne 'PRESENT' -or $rogue.StagedModule -cne 'ABSENT' -or
        $rogue.PayloadStatus -cne 'MISSING_STAGED' -or
        -not $winscp.SourceDirectory -or $winscp.SolutionProject -or
        $winscp.BuiltModule -cne 'ABSENT' -or $winscp.PayloadStatus -cne 'NOT_SHIPPED') {
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
    # Explicit PKG-01 preflight fails on missing modules, byte mismatch
    # and mismatched folder identity but accepts a nonshipped source folder.
    $invoker = Join-Path $PSScriptRoot '..\Invoke-PluginCoverageInventory.ps1'
    Assert-InventoryRejected -Action {
        & $invoker -Repository $fake -BuiltDirectory $build -StagedDirectory $stage -RequireMatchingPayloads
    } -Reason 'missing built/staged SPL payloads' -ExpectedError 'SPL build/staging inventory and SHA-256 mismatch'
    Assert-InventoryRejected -Action {
        & $invoker -Repository $fake -BuiltDirectory $build -RequireMatchingPayloads
    } -Reason 'missing stage under strict integrity mode' -ExpectedError '-RequireMatchingPayloads requires'

    # UP-02: an ABI audit over "whatever was built" cannot silently skip
    # a Solution plug-in absent from the build output.
    Assert-InventoryRejected -Action {
        $builtOnly = @(Get-SalamanderPluginInventory -Repository $fake -BuiltDirectory $build)
        Assert-SalamanderBuiltPluginCompleteness -Inventory $builtOnly
    } -Reason 'missing built Solution module in ABI audit' -ExpectedError 'Missing built Solution plug-in binaries: beta'

    [IO.File]::WriteAllBytes((Join-Path $build 'plugins\beta\beta.spl'), [byte[]](7,8,9))
    Assert-SalamanderBuiltPluginCompleteness -Inventory @(
        Get-SalamanderPluginInventory -Repository $fake -BuiltDirectory $build)

    [void][IO.Directory]::CreateDirectory((Join-Path $stage 'plugins\rogue'))
    [IO.File]::WriteAllBytes((Join-Path $stage 'plugins\rogue\rogue.spl'), [byte[]](4,5,6))
    & $invoker -Repository $fake -BuiltDirectory $build -StagedDirectory $stage -RequireMatchingPayloads

    # RED: comparing two empty plug-in folders must never be reported as
    # successful release payload coverage, even though every source project
    # is classified NOT_SHIPPED in both trees.
    $emptyBuild = Join-Path $root 'empty-build'
    $emptyStage = Join-Path $root 'empty-stage'
    [void][IO.Directory]::CreateDirectory((Join-Path $emptyBuild 'plugins'))
    [void][IO.Directory]::CreateDirectory((Join-Path $emptyStage 'plugins'))
    Assert-InventoryRejected -Action {
        & $invoker -Repository $fake -BuiltDirectory $emptyBuild -StagedDirectory $emptyStage -RequireMatchingPayloads
    } -Reason 'both output trees have no plug-ins' -ExpectedError 'No matching staged SPL payloads'

    # RED: an expected release module cannot be silently omitted from both
    # sides; source-only folders are exempt only if not explicitly required.
    Assert-InventoryRejected -Action {
        & $invoker -Repository $fake -BuiltDirectory $build -StagedDirectory $stage -RequireMatchingPayloads -RequiredShippedModules @('alpha','winscp')
    } -Reason 'required source-only module absent from release' -ExpectedError 'Required shipped plug-ins missing or mismatched: winscp'

    Assert-InventoryRejected -Action {
        & $invoker -Repository $fake -BuiltDirectory $build -StagedDirectory $stage -RequireMatchingPayloads -RequiredShippedModules @('alpha','alpha')
    } -Reason 'duplicate required module name' -ExpectedError 'Duplicate required plug-in name'

    & $invoker -Repository $fake -BuiltDirectory $build -StagedDirectory $stage -RequireMatchingPayloads -RequiredShippedModules @('alpha','beta')

    # PKG-01: Release completeness is stronger than equal hashes.
    # Two matching copies of an undeclared module must be rejected.
    Assert-InventoryRejected -Action {
        & $invoker -Repository $fake -BuiltDirectory $build -StagedDirectory $stage -RequireMatchingPayloads -RequireSolutionPluginPayloads
    } -Reason 'undeclared matched SPL in release stage' -ExpectedError 'Undeclared shipped plug-ins: rogue'
    [IO.File]::Delete((Join-Path $build 'plugins\rogue\rogue.spl'))
    [IO.File]::Delete((Join-Path $stage 'plugins\rogue\rogue.spl'))

    # Source-only winscp is not a Solution project and need not ship.
    & $invoker -Repository $fake -BuiltDirectory $build -StagedDirectory $stage -RequireMatchingPayloads -RequireSolutionPluginPayloads

    # A Solution project omitted from BOTH trees previously looked like
    # NOT_SHIPPED, hiding an incomplete Release archive.
    $buildBeta = Join-Path $build 'plugins\beta\beta.spl'
    $stageBeta = Join-Path $stage 'plugins\beta\beta.spl'
    [IO.File]::Delete($buildBeta)
    [IO.File]::Delete($stageBeta)
    Assert-InventoryRejected -Action {
        & $invoker -Repository $fake -BuiltDirectory $build -StagedDirectory $stage -RequireMatchingPayloads -RequireSolutionPluginPayloads
    } -Reason 'Solution module silently omitted from build and stage' -ExpectedError 'Missing Solution plug-in payloads: beta'
    [IO.File]::WriteAllBytes($buildBeta, [byte[]](7,8,9))
    [IO.File]::WriteAllBytes($stageBeta, [byte[]](7,8,9))

    # PKG-01: a correct SPL alone is insufficient if its compiled
    # language resources or native helper DLLs disappear during staging.
    $buildLang = Join-Path $build 'plugins\alpha\lang\english.slg'
    $stageLang = Join-Path $stage 'plugins\alpha\lang\english.slg'
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $buildLang))
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $stageLang))
    [IO.File]::WriteAllBytes($buildLang, [byte[]](10,20,30))
    [IO.File]::WriteAllBytes($stageLang, [byte[]](10,20,30))
    $buildHelper = Join-Path $build 'plugins\alpha\dep.dll'
    $stageHelper = Join-Path $stage 'plugins\alpha\dep.dll'
    [IO.File]::WriteAllBytes($buildHelper, [byte[]](4,5,6))
    [IO.File]::WriteAllBytes($stageHelper, [byte[]](4,5,6))
    & $invoker -Repository $fake -BuiltDirectory $build -StagedDirectory $stage -RequireMatchingPayloads -RequireSolutionPluginPayloads

    [IO.File]::Delete($stageLang)
    Assert-InventoryRejected -Action {
        & $invoker -Repository $fake -BuiltDirectory $build -StagedDirectory $stage -RequireMatchingPayloads -RequireSolutionPluginPayloads
    } -Reason 'compiled plugin language missing from stage' -ExpectedError 'Missing staged plug-in runtime sidecar'
    [IO.File]::WriteAllBytes($stageLang, [byte[]](10,20,30))

    [IO.File]::WriteAllBytes($stageHelper, [byte[]](4,5,7))
    Assert-InventoryRejected -Action {
        & $invoker -Repository $fake -BuiltDirectory $build -StagedDirectory $stage -RequireMatchingPayloads -RequireSolutionPluginPayloads
    } -Reason 'native dependency modified after build' -ExpectedError 'Plug-in runtime sidecar SHA-256 mismatch'
    [IO.File]::WriteAllBytes($stageHelper, [byte[]](4,5,6))
    & $invoker -Repository $fake -BuiltDirectory $build -StagedDirectory $stage -RequireMatchingPayloads -RequireSolutionPluginPayloads

    # A completeness request without byte-integrity comparison is invalid.
    Assert-InventoryRejected -Action {
        & $invoker -Repository $fake -BuiltDirectory $build -StagedDirectory $stage -RequireSolutionPluginPayloads
    } -Reason 'completeness without checksums' -ExpectedError '-RequireSolutionPluginPayloads requires -RequireMatchingPayloads'

    $stageAlpha = Join-Path $stage 'plugins\alpha\alpha.spl'
    [IO.File]::WriteAllBytes($stageAlpha, [byte[]](1,2,4))
    $damaged = @(Get-SalamanderPluginInventory -Repository $fake -BuiltDirectory $build -StagedDirectory $stage |
        Where-Object Plugin -EQ 'alpha')[0]
    if ($damaged.PayloadStatus -cne 'HASH_MISMATCH' -or
        $damaged.BuiltSHA256 -ceq $damaged.StagedSHA256) {
        throw 'Byte-modified staged plugin must yield a SHA-256 mismatch.'
    }
    Assert-InventoryRejected -Action {
        & $invoker -Repository $fake -BuiltDirectory $build -StagedDirectory $stage -RequireMatchingPayloads
    } -Reason 'staged plugin tampering' -ExpectedError 'alpha:HASH_MISMATCH'
    [IO.File]::WriteAllBytes($stageAlpha, [byte[]](1,2,3))

    Write-Host 'PASS: exact SPL payload matching, missing module and tampered-byte negative regression.'

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
