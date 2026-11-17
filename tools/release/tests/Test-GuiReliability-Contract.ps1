#requires -Version 7.4
# Regression contract for repeatable isolated-vs-preconditioned GUI comparisons.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repository = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).ProviderPath
$driver = [IO.File]::ReadAllText(
    (Join-Path $repository 'tools\release\tests\Test-SalamanderGui-LongPaths.ps1'))
$runnerPath = Join-Path $repository 'tools\release\tests\Invoke-GuiReliability.ps1'
if (-not (Test-Path -LiteralPath $runnerPath -PathType Leaf)) {
    throw 'A/B GUI reliability runner must exist.'
}
$runner = [IO.File]::ReadAllText($runnerPath)
$manager = [IO.File]::ReadAllText(
    (Join-Path $repository 'tools\Manage-Salamander.ps1'))

# Arrange: an empty clipboard is a valid starting state, different from a
# failure to read the clipboard. Tests must not leave their own data there.
# Act/Assert: both captured states have explicit, guarded restoration paths.
if ($driver -notmatch '\$clipboardSnapshotValid\s*=\s*\$false' -or
    $driver -notmatch '\$clipboardSnapshotValid\s*=\s*\$true' -or
    $driver -notmatch '(?s)if \(\$clipboardSnapshotValid\s+-and.*?Clipboard\]::Clear\(' -or
    $driver -notmatch 'Clipboard\]::SetDataObject\(\$oldClipboard, \$true\)') {
    throw 'GUI test must restore the originally empty or populated clipboard, without clearing on failed snapshot.'
}

# Arrange: two scenarios must use the same GUI mode, test binary, and test
# handler. The preconditioned scenario adds the same test groups that precede
# GUI tests in --test-all. A missing/failed process guard cannot be ignored.
foreach ($literal in @('--test-gui-temp-delete', '--test-plugin-exports',
        '--test-pictview', '--test-pictview-window', '--test', '--release',
        '--debug', 'CaptureHangDump', 'OPENSAL_GUI_CAPTURE_HANG_DUMP',
        'ExitCode', 'Get-Process salamand', 'Iterations', 'Summary')) {
    if (-not $runner.Contains($literal)) {
        throw "GUI A/B comparison is missing a mandatory reliability contract: $literal"
    }
}
if (-not $manager.Contains("'--diagnose-gui'") -or
    -not $manager.Contains('Invoke-GuiReliability.ps1') -or
    -not $manager.Contains('OPENSAL_MANAGE_SKIP_CLIPBOARD') -or
    -not $runner.Contains('OPENSAL_MANAGE_SKIP_CLIPBOARD') -or
    -not $runner.Contains('Get-FileHash') -or
    $runner -notmatch '(?s)try\s*\{.*?finally\s*\{' -or
    $runner -notmatch 'ExitCode\s*-ne\s*0' -or
    $runner -notmatch 'Exit\s+1') {
    throw 'Comparison must propagate failures and restore temporary environment overrides.'
}
Write-Host 'PASS: GUI A/B comparison keeps the mode constant, reports failures and restores the clipboard.'
