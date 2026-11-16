#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
# Arrange / Act / Assert: fixture-only checks for incomplete PictView runtime.
# Does not execute any plug-in or use a real build directory.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\Plugin-Runtime-Prerequisites.ps1')

$root = Join-Path ([IO.Path]::GetTempPath()) ("OpenSal-PictView-Prerequisites-" + [guid]::NewGuid().ToString('N'))
$pictView = Join-Path $root 'plugins\pictview'
try {
    # Arrange: the exact reported failure - the SPL exists but neither
    # the x86 helper nor the converter DLL is distributed.
    [void][IO.Directory]::CreateDirectory($pictView)
    [IO.File]::WriteAllBytes((Join-Path $pictView 'pictview.spl'), [byte[]]@(0))
    # Act
    $missing = @(Get-MissingPictViewRuntimeFiles -BuildDirectory $root)
    # Assert
    if ($missing.Count -ne 2 -or
        -not ($missing -contains (Join-Path $pictView 'SalPVEnv.exe')) -or
        -not ($missing -contains (Join-Path $pictView 'PVW32Cnv.dll'))) {
        throw "FAIL: missing PictView sidecars not detected exactly: $($missing -join '; ')"
    }
    Write-Host 'PASS: incomplete x64 PictView runtime is detected before Test All.'

    # Arrange: the helper executable exists but the closed-source engine does not.
    [IO.File]::WriteAllBytes((Join-Path $pictView 'SalPVEnv.exe'), [byte[]]@(0))
    # Act
    $missing = @(Get-MissingPictViewRuntimeFiles -BuildDirectory $root)
    # Assert
    if ($missing.Count -ne 1 -or
        $missing[0] -ne (Join-Path $pictView 'PVW32Cnv.dll')) {
        throw 'FAIL: incomplete PictView converter runtime not reported precisely.'
    }
    Write-Host 'PASS: single absent PictView converter is distinguished from helper absence.'

    # Arrange: all three files are present (not proof they are valid).
    [IO.File]::WriteAllBytes((Join-Path $pictView 'PVW32Cnv.dll'), [byte[]]@(0))
    # Act
    $missing = @(Get-MissingPictViewRuntimeFiles -BuildDirectory $root)
    # Assert
    if ($missing.Count -ne 0) {
        throw 'FAIL: present PictView sidecars were reported missing.'
    }
    Write-Host 'PASS: prerequisite presence check distinguishes complete file set.'

    # Arrange: PictView isn't installed. Do not require its optional sidecars.
    [IO.File]::Delete((Join-Path $pictView 'pictview.spl'))
    # Act
    $missing = @(Get-MissingPictViewRuntimeFiles -BuildDirectory $root)
    # Assert
    if ($missing.Count -ne 0) {
        throw 'FAIL: optional absent PictView was treated as installed.'
    }
    Write-Host 'PASS: absent optional PictView is not a forced dependency.'
}
finally {
    if ([IO.Directory]::Exists($root)) {
        [IO.Directory]::Delete($root, $true)
    }
}
