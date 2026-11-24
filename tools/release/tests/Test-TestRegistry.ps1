#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$registry = Get-Content -LiteralPath (Join-Path $repository 'tools\release\Test-Registry.json') -Raw | ConvertFrom-Json
if ($registry.SchemaVersion -ne 1) { throw 'Unsupported test registry schema.' }

function Assert-TestInventory {
    param([string[]]$Actual, [object[]]$Entries)
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $Entries) {
        if (-not $seen.Add([string]$entry.Path)) { throw "Duplicate test registry path: $($entry.Path)" }
        if ($entry.Kind -notin @('Automatic','OptIn','ArtifactValidator','Helper')) {
            throw "Unknown test classification: $($entry.Path)"
        }
        if ($entry.Kind -ne 'Automatic' -and [string]::IsNullOrWhiteSpace($entry.Reason)) {
            throw "Nonautomatic test must document its scope: $($entry.Path)"
        }
        if ($entry.Path -notin $Actual) { throw "Registered test missing: $($entry.Path)" }
    }
    foreach ($path in $Actual) {
        if (-not $seen.Contains($path)) { throw "Unregistered test source: $path" }
    }
}
$actual = @(
    foreach ($directory in @('tools/tests','tools/release/tests','src/vcxproj/tests')) {
        Get-ChildItem -LiteralPath (Join-Path $repository $directory) -Recurse -File |
            Where-Object Extension -in @('.ps1','.cpp','.c','.cs','.cmd','.bat','.py') |
            ForEach-Object { [IO.Path]::GetRelativePath($repository, $_.FullName).Replace('\','/') }
    }
)
Assert-TestInventory -Actual $actual -Entries $registry.Entries
foreach ($fixture in @('unregistered','missing','duplicate')) {
    $caught = $false
    try {
        switch ($fixture) {
            unregistered { Assert-TestInventory -Actual ($actual + 'tools/tests/future.cpp') -Entries $registry.Entries }
            missing { Assert-TestInventory -Actual @($actual | Where-Object { $_ -ne $registry.Entries[0].Path }) -Entries $registry.Entries }
            duplicate { Assert-TestInventory -Actual $actual -Entries @($registry.Entries + $registry.Entries[0]) }
        }
    }
    catch {
        if ($_.Exception.Message -notmatch 'Unregistered test source|Registered test missing|Duplicate test registry path') { throw }
        $caught = $true
    }
    if (-not $caught) { throw "Registry failed to detect $fixture inventory drift." }
}
# Verify references in executable AST string literals, never comments.
$literalCache = @{}
foreach ($entry in $registry.Entries) {
    if (-not $entry.Owner) {
        if ($entry.Kind -ne 'OptIn') { throw "Missing test owner: $($entry.Path)" }
        continue
    }
    if (-not $literalCache.ContainsKey($entry.Owner)) {
        $ownerPath = Join-Path $repository $entry.Owner
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($ownerPath, [ref]$tokens, [ref]$errors)
        if (@($errors).Count) { throw "Invalid registry owner: $($entry.Owner)" }
        $literalCache[$entry.Owner] = @($ast.FindAll({
            param($node)
            $node -is [Management.Automation.Language.StringConstantExpressionAst]
        }, $true) | ForEach-Object { $_.Value.Replace('\','/') })
    }
    $leaf = [IO.Path]::GetFileName($entry.Path)
    $references = @($literalCache[$entry.Owner] | Where-Object {
        $_ -ceq $leaf -or $_.EndsWith('/' + $leaf, [StringComparison]::Ordinal)
    })
    if ($references.Count -eq 0) { throw "No executable-source reference to $($entry.Path) in $($entry.Owner)" }
}
$managerPath = Join-Path $repository 'tools\Manage-Salamander.ps1'
$manager = Get-Content -LiteralPath $managerPath -Raw
$options = @([regex]::Matches(
    [regex]::Match($manager, '(?s)\$validOptions\s*=\s*@\((.*?)\)').Groups[1].Value,
    "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
if (@($options | Sort-Object -Unique).Count -ne $options.Count) { throw 'Duplicate CLI test option.' }
$names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$classified = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($option in $registry.AutomaticOptions) {
    if (-not $classified.Add($option)) { throw "Duplicate automatic test option: $option" }
}
foreach ($excluded in $registry.ScopeExclusions) {
    if (-not $names.Add($excluded.Name) -or [string]::IsNullOrWhiteSpace($excluded.Reason)) {
        throw "Invalid scope exclusion: $($excluded.Name)"
    }
    if ($excluded.Option) {
        if ($excluded.Option -notin $options -or $excluded.Option -in $registry.AutomaticOptions) {
            throw "Unknown or automatically selected opt-in: $($excluded.Option)"
        }
        [void]$classified.Add($excluded.Option)
    }
}
$testOptions = @($options | Where-Object { $_ -like '--test*' -and $_ -ne '--test-all' })
if (-not $classified.SetEquals([string[]]$testOptions)) { throw 'CLI test option registry drift.' }
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($managerPath, [ref]$tokens, [ref]$errors)
$selector = @($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Expand-AutomatedTestActions'
}, $true))
if ($selector.Count -ne 1) { throw 'Missing or duplicate test selector.' }
. ([scriptblock]::Create($selector[0].Extent.Text))
$selected = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
[void]$selected.Add('--test-all')
Expand-AutomatedTestActions -RequestedSet $selected -AvailableOptions $options
[void]$selected.Remove('--test-all')
if (-not $selected.SetEquals([string[]]$registry.AutomaticOptions)) { throw 'Test-All selection does not match automatic registry.' }
foreach ($option in $testOptions) {
    if (-not $manager.Contains(('$requestedSet.Contains(''{0}'')' -f $option))) {
        throw "No manager dispatch for $option"
    }
}
# Planned exclusions remain visible SKIPs. Required skips still fail.
. (Join-Path $PSScriptRoot '..\Test-RunCollection.ps1')
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('OpenSal-Registry-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
try {
    Initialize-TestRun -CollectFailures
    Skip-TestCase -Name 'planned' -Reason 'explicit opt-in' -Planned 3>$null
    Invoke-TestCase -Name 'required pass' -Action { }
    $log = Join-Path $temporary 'planned.log'
    Complete-TestRun -LogPath $log 3>$null 6>$null
    $report = Get-Content -LiteralPath ([IO.Path]::ChangeExtension($log,'.results.json')) -Raw | ConvertFrom-Json
    if ($report.Skipped -ne 1 -or $report.PlannedExclusions -ne 1 -or $report.RequiredSkipped -ne 0 -or $report.Passed -ne 1) {
        throw 'Planned exclusion lost its SKIP status or scope metadata.'
    }
    Initialize-TestRun -CollectFailures
    Invoke-TestCase -Name 'required skip' -Action {
        $script:CurrentTestSkipReason = 'missing required prerequisite'
    } 3>$null
    if ($script:TestOutcomes.Count -ne 1 -or $script:TestOutcomes[0].Status -ne 'SKIP') {
        throw 'A direct GUI refusal must not be reported as PASS.'
    }
    $caught = $false
    try { Complete-TestRun -LogPath (Join-Path $temporary 'required.log') 6>$null }
    catch { if ($_.Exception.Message -notmatch '1 übersprungen') { throw }; $caught = $true }
    if (-not $caught) { throw 'A required skip must still fail the aggregate.' }
}
finally { Remove-Item -LiteralPath $temporary -Recurse -Force }
Write-Host "PASS: $($actual.Count) classified test sources, unique CLI options, inventory drift and exclusion reporting."
