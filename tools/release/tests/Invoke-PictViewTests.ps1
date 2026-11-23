#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
    Builds and executes PictView WIC regressions on a local Windows machine.
.DESCRIPTION
    Compiles each native test from source with MSVC /W4 /WX for both x64 and
    x86. No release binaries are modified. The optional window test creates a
    disposable HWND and requires an unlocked interactive Windows desktop.
    This is not an in-process Salamander plug-in activation test.
#>
[CmdletBinding()]
param(
    [string]$Repository = (Join-Path $PSScriptRoot '..\..\..'),
    [string]$OutputDirectory = (Join-Path $env:TEMP 'OpenSalamander\PictView-Tests'),
    [switch]$InteractiveWindowTests
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if (-not $IsWindows) { throw 'PictView WIC tests require Windows.' }
$Repository = [IO.Path]::GetFullPath($Repository)
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)

. (Join-Path $Repository 'tools\release\Package-Helpers.ps1')
$installation = Get-VisualStudio2026
$vcvars = Join-Path $installation 'VC\Auxiliary\Build\vcvarsall.bat'
if (-not (Test-Path -LiteralPath $vcvars -PathType Leaf)) {
    throw "MSVC toolchain is missing: $vcvars"
}

# Native tests are intentionally independent of Salamander's old PVW32 DLL.
# Each item names all production .cpp files necessary for its link contract.
$specs = @(
    @{ Name = 'pictview_wic_decode'; Sources = @(
        'tools\tests\pictview_wic_decode.cpp',
        'src\plugins\pictview\WicImageDecoder.cpp'
    ); Libraries = @('windowscodecs.lib','ole32.lib') },
    @{ Name = 'pictview_wic_formats'; Sources = @(
        'tools\tests\pictview_wic_formats.cpp',
        'src\plugins\pictview\WicImageDecoder.cpp'
    ); Libraries = @('windowscodecs.lib','ole32.lib') },
    @{ Name = 'pictview_wic_presenter'; Sources = @(
        'tools\tests\pictview_wic_presenter.cpp',
        'src\plugins\pictview\WicBitmapPresenter.cpp'
    ); Libraries = @('gdi32.lib') },
    @{ Name = 'pictview_wic_viewer_path'; Sources = @(
        'tools\tests\pictview_wic_viewer_path.cpp',
        'src\plugins\pictview\WicNativeViewer.cpp',
        'src\plugins\pictview\WicImageClipboard.cpp',
        'src\plugins\pictview\WicImageWriter.cpp',
        'src\plugins\pictview\WicImageTransforms.cpp',
        'src\plugins\pictview\WicImageDecoder.cpp',
        'src\plugins\pictview\WicBitmapPresenter.cpp'
    ); Libraries = @('user32.lib','gdi32.lib','comdlg32.lib','windowscodecs.lib','ole32.lib') },
    @{ Name = 'pictview_wic_transforms'; Sources = @(
        'tools\tests\pictview_wic_transforms.cpp',
        'src\plugins\pictview\WicImageTransforms.cpp'
    ); Libraries = @() },
    @{ Name = 'pictview_wic_writer'; Sources = @(
        'tools\tests\pictview_wic_writer.cpp',
        'src\plugins\pictview\WicImageWriter.cpp',
        'src\plugins\pictview\WicImageDecoder.cpp',
        'src\plugins\pictview\WicBitmapPresenter.cpp'
    ); Libraries = @('gdi32.lib','windowscodecs.lib','ole32.lib') },
    @{ Name = 'pictview_wic_clipboard'; Sources = @(
        'tools\tests\pictview_wic_clipboard.cpp',
        'src\plugins\pictview\WicImageClipboard.cpp',
        'src\plugins\pictview\WicBitmapPresenter.cpp'
    ); Libraries = @('user32.lib','gdi32.lib') }
)
$specs += @{
        Name = 'pictview_wic_window'
        Sources = @(
            'tools\tests\pictview_wic_window.cpp',
            'src\plugins\pictview\WicNativeViewer.cpp',
            'src\plugins\pictview\WicImageClipboard.cpp',
            'src\plugins\pictview\WicImageWriter.cpp',
            'src\plugins\pictview\WicImageTransforms.cpp',
            'src\plugins\pictview\WicImageDecoder.cpp',
            'src\plugins\pictview\WicBitmapPresenter.cpp'
        )
        Libraries = @('user32.lib','gdi32.lib','comdlg32.lib','windowscodecs.lib','ole32.lib')
    }

# Reject quoting syntax which cmd.exe could interpret as another command.
function Quote-CmdArgument {
    param([Parameter(Mandatory)][string]$Value)
    if ($Value.Contains('"') -or $Value.Contains([char]13) -or $Value.Contains([char]10) -or
        $Value.Contains('%') -or $Value.Contains('!')) {
        throw "Unsupported shell meta character in build argument: $Value"
    }
    return '"' + $Value + '"'
}

function Invoke-CompiledTest {
    param([string]$Architecture, [hashtable]$Spec)
    $directory = Join-Path $OutputDirectory "$Architecture\$($Spec.Name)"
    [void](New-Item -ItemType Directory -Path $directory -Force)
    $binary = Join-Path $directory ($Spec.Name + '.exe')
    $commandFile = Join-Path $directory 'build-and-run.cmd'

    $sourceFiles = @($Spec.Sources | ForEach-Object {
        $path = Join-Path $Repository $_
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "PictView test source missing: $path"
        }
        Quote-CmdArgument $path
    })

    $compilerArgs = @(
        'cl /nologo /W4 /WX /std:c++17 /EHsc /utf-8',
        ('/Fe:' + (Quote-CmdArgument $binary))
    ) + $sourceFiles + $Spec.Libraries

    $lines = @(
        '@echo off',
        ('call ' + (Quote-CmdArgument $vcvars) + ' ' + $Architecture + ' >nul'),
        'if errorlevel 1 exit /b 1',
        ('pushd ' + (Quote-CmdArgument $directory)),
        'if errorlevel 1 exit /b 1',
        ($compilerArgs -join ' '),
        'if errorlevel 1 exit /b 1'
    )
    if ($Spec.Name -ne 'pictview_wic_window' -or $InteractiveWindowTests) {
        $lines += @( (Quote-CmdArgument $binary), 'exit /b %errorlevel%' )
    } else {
        $lines += 'exit /b 0'
        Write-Host "PictView [$Architecture] window test will be compiled but not executed."
    }
    $encoding = [Text.Encoding]::GetEncoding(
        [Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
    [IO.File]::WriteAllLines($commandFile, $lines, $encoding)

    Write-Host "PictView [$Architecture] $($Spec.Name)"
    & cmd.exe /d /c $commandFile
    if ($LASTEXITCODE -ne 0) {
        throw "PictView test failed ($Architecture, $($Spec.Name)): exit $LASTEXITCODE"
    }
}

foreach ($arch in @('x64','x86')) {
    foreach ($spec in $specs) {
        Invoke-CompiledTest -Architecture $arch -Spec $spec
    }
}
Write-Host 'PASS: all native PictView tests compiled x86/x64; noninteractive tests executed successfully.'
