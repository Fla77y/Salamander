#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
    Regression-test the exact-file contract for a downloaded public Release artifact.
.DESCRIPTION
    Uses synthetic, non-executable package fixtures. Never installs or launches code.
    The ordinary build directory may include private Debug packages; a downloaded
    public artifact must contain only the two Release files and the manifest.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$verifier = Join-Path $PSScriptRoot 'Test-ReleaseChecksumManifest.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('OpenSal-PublicArtifact-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)

function Assert-Rejected {
    <#
    .SYNOPSIS
        Require verification to fail for a deliberately invalid public artifact.
    #>
    param([Parameter(Mandatory)][string]$Reason)

    $rejected = $false
    try {
        & $verifier -DistributionDirectory $root -RequirePublicOnly *> $null
    }
    catch {
        $rejected = $true
    }
    if (-not $rejected) {
        throw "Public artifact verifier accepted invalid fixture: $Reason"
    }
}

try {
    # Arrange: an exact three-file public artifact, with two synthetic payloads.
    $names = @('OpenSalamander-Release-x64.7z', 'OpenSalamander-Release-x64-Setup.exe')
    foreach ($name in $names) {
        [IO.File]::WriteAllBytes((Join-Path $root $name), [byte[]](1, 42, 127))
    }
    $lines = foreach ($name in $names) {
        '{0} *{1}' -f (Get-FileHash -LiteralPath (Join-Path $root $name) -Algorithm SHA256).Hash.ToLowerInvariant(), $name
    }
    Set-Content -LiteralPath (Join-Path $root 'SHA256SUMS-Release.txt') -Value $lines -Encoding ascii

    # Act / Assert: a valid artifact passes strict verification.
    & $verifier -DistributionDirectory $root -RequirePublicOnly

    # The internal build directory is allowed to retain private Debug packages,
    # but a downloaded public artifact must categorically reject them.
    $extra = Join-Path $root 'OpenSalamander-Debug-x64.7z'
    [IO.File]::WriteAllBytes($extra, [byte[]](1, 2, 3))
    & $verifier -DistributionDirectory $root *> $null
    Assert-Rejected 'Debug package present'
    Remove-Item -LiteralPath $extra -Force

    $hidden = Join-Path $root '.unexpected-hidden'
    [IO.File]::WriteAllBytes($hidden, [byte[]](4))
    Assert-Rejected 'hidden unlisted file'
    Remove-Item -LiteralPath $hidden -Force

    $unexpectedDirectory = Join-Path $root 'unlisted'
    [void][IO.Directory]::CreateDirectory($unexpectedDirectory)
    Assert-Rejected 'unexpected directory'
    Remove-Item -LiteralPath $unexpectedDirectory -Recurse -Force

    # A corrupt public package is rejected regardless of the exact-file check.
    [IO.File]::WriteAllBytes((Join-Path $root $names[0]), [byte[]](9))
    Assert-Rejected 'altered checksum'

    Write-Host 'PASS: public Release artifact accepts exactly two intact packages and one manifest.'
}
finally {
    # Only the unique test-owned fixture is deleted.
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
