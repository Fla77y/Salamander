#requires -Version 7.4
# Read-only integration regression; never execute the management entry point.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).ProviderPath
$manager = Join-Path $root 'tools\Manage-Salamander.ps1'
$source = [IO.File]::ReadAllText($manager)
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($manager, [ref]$tokens, [ref]$errors)
if (@($errors).Count) { throw 'Management script contains parse errors.' }
# Arrange: load only the actual pure option-selection functions.
foreach ($name in @('Expand-AutomatedTestActions', 'Get-AutomatedGuiModes')) {
    $definition = @($ast.FindAll({ param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name
    }, $true))
    if ($definition.Count -ne 1) { throw "Missing management selector: $name" }
    . ([scriptblock]::Create($definition[0].Extent.Text))
}
$options = @([regex]::Matches(
    [regex]::Match($source, '(?s)\$validOptions\s*=\s*@\((.*?)\)').Groups[1].Value,
    "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
$selected = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
[void]$selected.Add('--test-all')
# Act
Expand-AutomatedTestActions -RequestedSet $selected -AvailableOptions $options
# Assert
foreach ($option in @('--test-gui-large-unicode-copy', '--test-clipboard-snapshot')) {
    if ($options -notcontains $option -or -not $selected.Contains($option)) {
        throw "--test-all does not include $option"
    }
}
foreach ($name in @('worker_copy_paths', 'worker_copy_io', 'win32_utf16_static_text')) {
    if (-not $source.Contains("tools\tests\$name.cpp")) { throw "Missing native regression: $name" }
}
if ($source -notmatch "Contains\('--test-gui-large-unicode-copy'\)" -or
    $source -notmatch 'Invoke-IsolatedUnicodeCopy.ps1' -or
    $source -notmatch '''-Configuration'', \$guiMode' -or
    $source -notmatch 'Test-ClipboardSnapshot.ps1') {
    throw 'Management dispatch is missing an isolated GUI or clipboard test invocation.'
}
# Arrange: the Unicode-copy runner delegates MSBuild to the shared,
# guarded isolated-GUI builder (also used by the Legacy Find GUI suite).
$runner = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Invoke-IsolatedUnicodeCopy.ps1'))
$builder = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Build-IsolatedGuiTest.ps1'))

# Act/Assert: dispatch must retain its private output name, configuration and
# all four real GUI acceptance cases.
foreach ($required in @('Build-IsolatedGuiTest.ps1', '-Configuration $Configuration',
    "-OutputName 'isolated-unicode-copy'", '-IsolatedConfiguration',
    '-LargeUnicodeCopyOnly', '-LargeUnicodeCopyCase',
    "'Copy', 'Cancel', 'Collision', 'LockedSource'")) {
    if (-not $runner.Contains($required)) { throw "Isolated runner missing contract: $required" }
}

# Act/Assert: delegation must not weaken test instrumentation or allow the
# MSBuild intermediate/output paths to escape the isolated build root.
foreach ($required in @('OpenSalamanderIsolatedGuiTest=true', '/getProperty:OutDir,IntDir',
    'Properties.OutDir', 'Properties.IntDir', 'ReparsePoint',
    'OPENSAL_BUILD_DIR', 'UserRootDir=', 'Isolated GUI build failed')) {
    if (-not $builder.Contains($required)) { throw "Shared isolated GUI builder missing contract: $required" }
}
Write-Host 'PASS: --test-all includes native regressions, four isolated large-copy GUI cases and native clipboard snapshot tests.'
