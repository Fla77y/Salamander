#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
    Exercise positive and fail-closed portable-package checksum verification.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$validator = Join-Path $PSScriptRoot 'Test-PortableManifest.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('OpenSal-PortableManifest-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
function Assert-InvalidPackage {
    <# .SYNOPSIS Require invalid test fixtures to be rejected. #>
    param([string]$Description)
    $rejected = $false
    try { & $validator -ExtractedDirectory $root *> $null }
    catch { $rejected = $true }
    if (-not $rejected) { throw "Accepted invalid portable fixture: $Description" }
}
try {
    # Arrange
    $dataFile = Join-Path $root 'sample.txt'
    [IO.File]::WriteAllBytes($dataFile, [byte[]](1,2,3,4))
    $hash = (Get-FileHash -LiteralPath $dataFile -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifest = Join-Path $root 'SHA256SUMS.txt'
    Set-Content -LiteralPath $manifest -Value ("$hash *sample.txt") -Encoding utf8

    # Act / Assert
    & $validator -ExtractedDirectory $root
    [IO.File]::WriteAllBytes($dataFile, [byte[]](1,2,9,4))
    Assert-InvalidPackage 'tampered content'
    [IO.File]::WriteAllBytes($dataFile, [byte[]](1,2,3,4))

    $extra = Join-Path $root '.private.pdb'
    [IO.File]::WriteAllBytes($extra, [byte[]](42))
    Assert-InvalidPackage 'unlisted hidden file'
    Remove-Item -LiteralPath $extra

    Set-Content -LiteralPath $manifest -Value @("$hash *sample.txt","$hash *sample.txt") -Encoding utf8
    Assert-InvalidPackage 'duplicate manifest entry'
    Set-Content -LiteralPath $manifest -Value ("$hash *../escape.txt") -Encoding utf8
    Assert-InvalidPackage 'path traversal'
    Write-Host 'PASS: portable manifest detects byte changes, unlisted files, duplicates and traversal.'
}
finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
