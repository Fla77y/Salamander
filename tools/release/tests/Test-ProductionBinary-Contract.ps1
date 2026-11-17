#requires -Version 7.4
param([string]$InstrumentedBinary)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
if (-not [string]::IsNullOrEmpty($InstrumentedBinary)) {
    # Arrange / Act: use the real version/release validator and a built EXE.
    $output = @(& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Test-ProductVersion.ps1') -BinaryPath $InstrumentedBinary 2>&1)
    $status = $LASTEXITCODE
    # Assert: rejection must specifically identify the instrumented build.
    if ($status -eq 0 -or ($output -join "`n") -notmatch 'Isolated GUI test executable') {
        throw ("Instrumented GUI executable was accepted or rejected for the wrong reason (exit $status). " + ($output -join "`n"))
    }
}

. (Join-Path $PSScriptRoot '..\Production-Binary-Contract.ps1')
$parent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$root = Join-Path $parent ('OpenSal-ProductionBinary-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
try {
    # Arrange: synthetic bytes test only the marker gate, not PE validity.
    $ordinary = Join-Path $root 'ordinary.exe'
    $instrumented = Join-Path $root 'instrumented.exe'
    [IO.File]::WriteAllBytes($ordinary, [byte[]](0x4d,0x5a,0,0))
    [IO.File]::WriteAllBytes($instrumented, [byte[]](
        [byte[]](0x4d,0x5a,0,0) + [Text.Encoding]::ASCII.GetBytes('OpenSalamander-IsolatedGUI-Config-v1') + [byte[]](0,0)))
    # Act / Assert
    Assert-ProductionBinary -Path $ordinary
    $rejected = $false
    try { Assert-ProductionBinary -Path $instrumented }
    catch {
        if ($_.Exception.Message -notmatch 'Isolated GUI test executable') { throw }
        $rejected = $true
    }
    if (-not $rejected) { throw 'Instrumented marker must be refused.' }
    # Arrange: packaging must refuse before deleting an existing staging tree.
    . (Join-Path $PSScriptRoot '..\Package-Helpers.ps1')
    $built = Join-Path $root 'built'
    $stage = Join-Path $root 'existing-stage'
    [void][IO.Directory]::CreateDirectory($built)
    [void][IO.Directory]::CreateDirectory($stage)
    [IO.File]::Copy($instrumented, (Join-Path $built 'salamand.exe'))
    $sentinel = Join-Path $stage 'preserve.txt'
    [IO.File]::WriteAllText($sentinel, 'preserved stage')
    $rejected = $false
    # Act
    try {
        New-DistributionStage -BuiltDirectory $built -Stage $stage -Repository $root -Configuration Release -CrtFolders @{}
    }
    catch {
        if ($_.Exception.Message -notmatch 'Isolated GUI test executable') { throw }
        $rejected = $true
    }
    # Assert
    if (-not $rejected -or -not [IO.File]::Exists($sentinel) -or
        [IO.File]::ReadAllText($sentinel) -cne 'preserved stage') {
        throw 'Packaging must reject instrumented binaries before changing staging content.'
    }
    Write-Host 'PASS: release validation refuses isolated test executables.'
}
finally {
    $resolved = [IO.Path]::GetFullPath($root)
    if (-not $resolved.StartsWith($parent + '\OpenSal-ProductionBinary-', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Refusing unsafe fixture cleanup.'
    }
    [IO.Directory]::Delete($resolved, $true)
}
