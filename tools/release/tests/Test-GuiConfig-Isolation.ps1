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
# A0-02: original version-5.0 state is verified only inside the owned
# CodexTests\GUID\Config1 namespace, never against the actual user 5.0 key.
$canary = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'LegacyConfig-Canary.ps1') -Raw
$canaryTest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Test-LegacyConfig-Canary.ps1') -Raw
$seed = $driver.IndexOf('New-IsolatedLegacyConfigCanary -TestConfigurationKey $testConfigurationKey')
$launch = $driver.IndexOf('Start-Process -FilePath $SalamanderExe', $seed)
$ready = $driver.IndexOf('    Wait-ForGuiResponsive', $launch)
$verify = $driver.IndexOf('Assert-IsolatedLegacyConfigPreserved -TestConfigurationKey $testConfigurationKey', $ready)
$dispatch = $driver.IndexOf('    if ($LegacyFindScenario) {', $verify)
if ($driver -notmatch "if \(\`$LegacyFindScenario -eq 'Baseline'\)" -or
    $seed -lt 0 -or $launch -le $seed -or $ready -le $launch -or
    $verify -le $ready -or $dispatch -le $verify -or
    $canary -notmatch 'CodexTests' -or
    $canary -notmatch 'Get-IsolatedLegacyConfigDigest' -or
    $canary -notmatch 'ExpectedNewConfigVersion = 105' -or
    $canaryTest -notmatch 'Alt-5.0-' -or
    $canaryTest -notmatch 'Expected independent 5\.2 configuration version') {
    throw 'A0-02: isolated real-GUI canary must seed old Config1 before launch and verify its full content after 5.2 startup.'
}
Write-Host 'PASS: existing isolated Legacy Find baseline protects old configuration before GUI startup and after 5.2 migration.'

if ($IsWindows) {
    Add-Type -Path (Join-Path $PSScriptRoot 'Clipboard-Snapshot.cs')
    Write-Host 'PASS: native clipboard snapshot helper compiles without accessing the clipboard.'
}
