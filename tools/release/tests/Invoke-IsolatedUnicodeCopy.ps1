#requires -Version 7.4
[CmdletBinding()]
param([ValidateSet('Release', 'Debug')][string]$Configuration = 'Release',
      [switch]$UnicodeParentDirectories)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$binary = & (Join-Path $PSScriptRoot 'Build-IsolatedGuiTest.ps1') -Configuration $Configuration -OutputName 'isolated-unicode-copy'
$repository = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).ProviderPath
$previousTemp = $env:TEMP
$previousTmp = $env:TMP
$parentArgs = @()
if ($UnicodeParentDirectories) { $parentArgs += '-UnicodeParentDirectories' }
try {
    $env:TEMP = Join-Path $repository '.Build\isolated-unicode-copy\temp'
    $env:TMP = $env:TEMP
    foreach ($case in @('Copy', 'Cancel', 'Collision', 'LockedSource')) {
        Write-Host "=== ISOLATED LARGE UNICODE COPY: $Configuration x64 $case ==="
        & pwsh -Sta -NoProfile -File (Join-Path $PSScriptRoot 'Test-SalamanderGui-LongPaths.ps1') `
            -SalamanderExe $binary -IsolatedConfiguration -LargeUnicodeCopyOnly -LargeUnicodeCopyCase $case @parentArgs
        if ($LASTEXITCODE -ne 0) { throw "Large Unicode GUI case failed: $Configuration x64 $case" }
    }
}
finally {
    $env:TEMP = $previousTemp
    $env:TMP = $previousTmp
}
