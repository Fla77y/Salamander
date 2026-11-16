#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
    Smoke-test Release x64 Inno Setup installation and uninstallation.
.DESCRIPTION
    Executes the trusted Release installer on a disposable CI runner, using
    a GUID-scoped directory under TEMP and no shortcuts. This is a non-GUI
    integration check, NOT a substitute for clean Windows 11 VM acceptance.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InstallerPath,
    [ValidateRange(10, 300)][int]$TimeoutSeconds = 180
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) {
    throw 'Release installer smoke requires Windows.'
}
$installer = [IO.Path]::GetFullPath($InstallerPath)
if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
    throw "Release installer missing: $installer"
}
if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'Release installer smoke requires x64 Windows.'
}

# Keep all paths under a new, test-owned root; never attempt to uninstall a
# developer's installed Salamander or reuse an existing installation folder.
$root = Join-Path ([IO.Path]::GetTempPath()) ('OpenSal-SetupSmoke-' + [Guid]::NewGuid().ToString('N'))
$target = Join-Path $root 'application'
[void][IO.Directory]::CreateDirectory($root)

function Invoke-BoundedSetup {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$Description
    )
    $process = Start-Process -FilePath $Executable -ArgumentList $Arguments -WorkingDirectory $root -PassThru -ErrorAction Stop
    try {
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            # Only kill the exact process tree started by this smoke.
            $process.Kill($true)
            throw "$Description exceeded $TimeoutSeconds seconds."
        }
        if ($process.ExitCode -ne 0) {
            throw "$Description failed with exit code $($process.ExitCode)."
        }
    }
    finally {
        $process.Dispose()
    }
}

try {
    $installLog = Join-Path $root 'setup.log'
    $installArguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART',
                          '/NOICONS', ('/DIR="' + $target + '"'),
                          ('/LOG="' + $installLog + '"'))
    Invoke-BoundedSetup -Executable $installer -Arguments $installArguments -Description 'Release Setup'

    foreach ($required in @('salamand.exe',
                             'help\english\salamand.chm',
                             'plugins\pictview\pictview.spl',
                             'plugins\pictview\lang\english.slg',
                             'plugins\pictview\exif.dll')) {
        if (-not (Test-Path -LiteralPath (Join-Path $target $required) -PathType Leaf)) {
            throw "Installed Release distribution is missing $required"
        }
    }

    $uninstallers = @(Get-ChildItem -LiteralPath $target -File -Filter 'unins*.exe')
    if ($uninstallers.Count -ne 1) {
        throw "Expected one Inno Setup uninstaller under test-owned directory; found $($uninstallers.Count)."
    }

    $uninstallLog = Join-Path $root 'uninstall.log'
    $uninstallArguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART',
                            ('/LOG="' + $uninstallLog + '"'))
    Invoke-BoundedSetup -Executable $uninstallers[0].FullName -Arguments $uninstallArguments -Description 'Release uninstaller'

    $installedExe = Join-Path $target 'salamand.exe'
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    while ((Test-Path -LiteralPath $installedExe -PathType Leaf) -and
           [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 200
    }
    if (Test-Path -LiteralPath $installedExe -PathType Leaf) {
        throw 'Release uninstaller left salamand.exe in the test installation directory.'
    }
    Write-Host 'PASS: Release x64 Inno Setup installed required files and removed the executable.'
}
finally {
    # The GUID-scoped temporary root is exclusively owned by this script.
    # Do not hide installation errors when cleaning up a failed test.
    if (Test-Path -LiteralPath $root -PathType Container) {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}
