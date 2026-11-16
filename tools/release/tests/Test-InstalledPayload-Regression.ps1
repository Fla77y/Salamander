#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
    Verify installer-content comparison with disposable synthetic fixtures.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$validator = Join-Path $PSScriptRoot 'Test-InstalledPayload.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('OpenSal-InstalledPayload-' + [Guid]::NewGuid().ToString('N'))
$portable = Join-Path $root 'portable'
$installed = Join-Path $root 'installed'
[void][IO.Directory]::CreateDirectory($portable)
[void][IO.Directory]::CreateDirectory($installed)

function Assert-Rejected {
    <#
    .SYNOPSIS
        Require invalid installed-content fixtures to fail.
    #>
    param([Parameter(Mandatory)][string]$Reason)
    $rejected = $false
    try { & $validator -PortableDirectory $portable -InstalledDirectory $installed *> $null }
    catch { $rejected = $true }
    if (-not $rejected) { throw "Invalid installed payload accepted: $Reason" }
}

try {
    # Arrange: exact source files plus Inno Setup's expected uninstall pair.
    $name = 'Café_日本語.txt'
    foreach ($directory in @($portable, $installed)) {
        [IO.File]::WriteAllBytes((Join-Path $directory $name), [byte[]](1, 2, 3, 255))
    }
    [IO.File]::WriteAllBytes((Join-Path $installed 'unins000.exe'), [byte[]](4))
    [IO.File]::WriteAllBytes((Join-Path $installed 'unins000.dat'), [byte[]](5))

    # Act / Assert
    & $validator -PortableDirectory $portable -InstalledDirectory $installed
    [IO.File]::WriteAllBytes((Join-Path $installed $name), [byte[]](8))
    Assert-Rejected 'modified byte content'
    [IO.File]::WriteAllBytes((Join-Path $installed $name), [byte[]](1, 2, 3, 255))

    Remove-Item -LiteralPath (Join-Path $installed $name)
    Assert-Rejected 'missing application file'
    [IO.File]::WriteAllBytes((Join-Path $installed $name), [byte[]](1, 2, 3, 255))

    [IO.File]::WriteAllBytes((Join-Path $installed 'unlisted.dll'), [byte[]](6))
    Assert-Rejected 'unlisted binary'
    Remove-Item -LiteralPath (Join-Path $installed 'unlisted.dll')

    Remove-Item -LiteralPath (Join-Path $installed 'unins000.dat')
    Assert-Rejected 'incomplete uninstall metadata'
    Write-Host 'PASS: installed payload integrity accepts exact source files and rejects tampering.'
}
finally {
    Remove-Item -LiteralPath $root -Force -Recurse -ErrorAction SilentlyContinue
}
