#requires -Version 7.4
# Regression: an active VS 2026 Developer PowerShell must be usable even when
# vswhere's component registration does not include Microsoft.Component.MSBuild.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repository = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).ProviderPath
. (Join-Path $repository 'tools\release\Package-Helpers.ps1')

# Arrange
$oldInstallDir = $env:VSINSTALLDIR
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('sal-vs-discovery-' + [guid]::NewGuid().ToString('N'))
$fakeVs = Join-Path $fixture 'Microsoft Visual Studio\18\Community'
$fakeMsbuild = Join-Path $fakeVs 'MSBuild\Current\Bin\MSBuild.exe'
try {
    New-Item -ItemType Directory -Path (Split-Path -Parent $fakeMsbuild) -Force | Out-Null
    [IO.File]::WriteAllText($fakeMsbuild, 'test-only')
    $env:VSINSTALLDIR = $fakeVs

    # Act
    $actual = Get-VisualStudio2026

    # Assert
    if ($actual -cne $fakeVs) { throw "Active Visual Studio 2026 was ignored: $actual" }

    # Arrange: a missing executable must never be accepted just from the env var.
    Remove-Item -LiteralPath $fakeMsbuild -Force
    $env:VSINSTALLDIR = (Join-Path $fixture 'missing\Microsoft Visual Studio\18\Community')

    # Act/Assert: the invalid path must not be returned (vswhere may find a real VS).
    $invalid = $env:VSINSTALLDIR
    try {
        $actual = Get-VisualStudio2026
        if ($actual -ceq $invalid) { throw 'Invalid VSINSTALLDIR was accepted.' }
    }
    catch {
        if ($_.Exception.Message -like 'Invalid VSINSTALLDIR was accepted.*') { throw }
    }
    Write-Host 'PASS: VS 2026 active developer environment discovery and missing executable fallback.'
}
finally {
    $env:VSINSTALLDIR = $oldInstallDir
    if (Test-Path -LiteralPath $fixture) {
        Remove-Item -LiteralPath $fixture -Recurse -Force
    }
}
