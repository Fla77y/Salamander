#requires -Version 7.4
# Read-only source contract; does not launch a GUI or access the registry.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).ProviderPath
# Arrange
$driver = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Test-SalamanderGui-LongPaths.ps1') -Raw
# Act / Assert
if ($driver -notmatch '\[switch\]\$IsolatedConfiguration' -or
    $driver -notmatch 'OpenSalamander-IsolatedGUI-Config-v1' -or
    $driver -notmatch 'OPENSAL_GUI_TEST_ID' -or
    $driver -notmatch 'DeleteSubKeyTree\(\$testConfigurationKey, \$false\)') {
    throw 'GUI acceptance lacks an explicit isolated configuration mode, build preflight or scoped cleanup.'
}
$startup = Get-Content -LiteralPath (Join-Path $root 'src\salamdr1.cpp') -Raw
$entry = $startup.IndexOf('int WinMainBody(')
$isolate = $startup.IndexOf('if (!InitializeIsolatedTestConfiguration())', $entry)
$discover = $startup.IndexOf('if (!GetUpgradeInfo(', $entry)
if ($isolate -lt $entry -or $isolate -ge $discover -or
    $startup -notmatch 'SalamanderConfigurationRoots\[i\] = roots\[i\]\.c_str\(\)') {
    throw 'Test builds must redirect every version root before configuration discovery.'
}
$props = Get-Content -LiteralPath (Join-Path $root 'src\vcxproj\sal_base.props') -Raw
if ($props -notmatch 'OpenSalamanderIsolatedGuiTest' -or
    $props -notmatch 'OPENSAL_ENABLE_ISOLATED_TEST_CONFIG') {
    throw 'The isolated GUI hook must be an explicit opt-in MSBuild property.'
}
Write-Host 'PASS: GUI acceptance can require a dedicated test configuration namespace.'
if ($driver -notmatch 'function Initialize-IsolatedGuiConfiguration' -or
    $driver -notmatch "SetValue\('Language', 'english.slg'" -or
    $driver -notmatch "SetValue\('Configuration', 59" -or
    $driver -notmatch '\[ValidateRange\(5,120\)\]\[int\]\$StartupReadyTimeoutSeconds = 90' -or
    ([regex]::Matches($driver, '-TimeoutSecondsOverride \$StartupReadyTimeoutSeconds')).Count -ne 2 -or
    $driver -notmatch "\`$version = \[int\]\`$key\.GetValue\('Configuration', 0\)" -or
    $driver -notmatch '\$version -le 59' -or
    $driver -notmatch 'GetValue\(''Save In Progress'', \$null\)' -or
    $driver -notmatch 'startup wait chain' -or
    $driver -notmatch 'Primary GUI failure:') {
    throw 'Isolated first-run acceptance needs a deterministic language, real upgrade/plugin initialization, startup wait diagnostics and preserved primary failure.'
}
if ($IsWindows) {
    Add-Type -Path (Join-Path $PSScriptRoot 'Clipboard-Snapshot.cs')
    Write-Host 'PASS: native clipboard snapshot helper compiles without accessing the clipboard.'
}
