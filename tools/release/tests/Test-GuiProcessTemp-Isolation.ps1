#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
    Verify that GUI acceptance launches Salamander with a private TEMP/TMP.
.DESCRIPTION
    Regression for a stale SAL*.tmp dialog during --test-all. Checks both
    GUI launch sites and executes a harmless child PowerShell process to
    verify -Environment isolation without modifying the parent environment.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'GUI TEMP-isolation regression requires Windows.' }

foreach ($name in @('Test-SalamanderGui-LongPaths.ps1', 'Test-PictView-Host.ps1')) {
    $source = Get-Content -LiteralPath (Join-Path $PSScriptRoot $name) -Raw
    if (-not $source.Contains('Join-Path $root ''process-temp''') -or
        -not $source.Contains('[IO.Directory]::CreateDirectory($processTemp)') -or
        -not $source.Contains('-Environment @{ TEMP = $processTemp; TMP = $processTemp }')) {
        throw "GUI runner $name must isolate TEMP/TMP for its own Salamander child process."
    }
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('OpenSal-EnvProbe-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$childTemp = Join-Path $root 'child-temp'
[void][IO.Directory]::CreateDirectory($childTemp)
$probe = Join-Path $root 'probe.ps1'
$result = Join-Path $root 'result.txt'

try {
    $originalTemp = [Environment]::GetEnvironmentVariable('TEMP', 'Process')
    $originalTmp = [Environment]::GetEnvironmentVariable('TMP', 'Process')
    @'
param([Parameter(Mandatory)][string]$Destination)
$values = @(
    [Environment]::GetEnvironmentVariable('TEMP', 'Process'),
    [Environment]::GetEnvironmentVariable('TMP', 'Process'),
    [IO.Path]::GetTempPath()
)
[IO.File]::WriteAllLines($Destination, [string[]]$values)
'@ | Set-Content -LiteralPath $probe -Encoding utf8

    $arguments = @('-NoLogo', '-NoProfile', '-NonInteractive',
                   '-File', ('"' + $probe + '"'), ('"' + $result + '"'))
    $process = Start-Process -FilePath (Join-Path $PSHOME 'pwsh.exe') `
        -ArgumentList $arguments -WindowStyle Hidden -Environment @{ TEMP = $childTemp; TMP = $childTemp } `
        -PassThru
    try {
        # Only this probe matters. Start-Process -Wait can get stuck waiting
        # on its Windows job after the probe has already exited.
        if (!$process.WaitForExit(15000)) {
            if (!$process.HasExited) { $process.Kill() }
            [void]$process.WaitForExit(5000)
            throw 'TEMP isolation child did not exit within 15 seconds.'
        }
        if ($process.ExitCode -ne 0) {
            throw "TEMP isolation child exited with $($process.ExitCode)."
        }
    }
    finally { $process.Dispose() }

    $values = [IO.File]::ReadAllLines($result)
    if ($values.Count -ne 3 -or
        $values[0] -cne $childTemp -or $values[1] -cne $childTemp -or
        [IO.Path]::TrimEndingDirectorySeparator($values[2]) -cne $childTemp) {
        throw 'Child process did not resolve the isolated TEMP via GetTempPath.'
    }
    if ([Environment]::GetEnvironmentVariable('TEMP', 'Process') -cne $originalTemp -or
        [Environment]::GetEnvironmentVariable('TMP', 'Process') -cne $originalTmp) {
        throw 'TEMP isolation unexpectedly modified the parent process.'
    }
    Write-Host 'PASS: GUI launchers isolate TEMP/TMP and Windows child GetTempPath; parent is unchanged.'
}
finally {
    Remove-Item -LiteralPath $root -Force -Recurse -ErrorAction SilentlyContinue
}
