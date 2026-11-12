#requires -Version 7.4
<#
.SYNOPSIS
    Create and verify Windows long-path and long-name test fixtures.
.DESCRIPTION
    Exercises the Windows filesystem through .NET, not Salamander's GUI.
    Use -KeepFixture to manually test Salamander navigation, copy, move,
    rename, deletion, searching and plugins against the generated files.
    Nothing outside the uniquely named TEMP fixture is changed.
.EXAMPLE
    pwsh -File .\tools\tests\Test-LongPaths.ps1 -KeepFixture
#>
[CmdletBinding()]
param([switch]$KeepFixture)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $IsWindows) {
    throw 'This test requires Windows and an NTFS-compatible filesystem.'
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('OpenSal-LongPaths-' + [guid]::NewGuid().ToString('N'))
$source = Join-Path $root 'source'
$target = Join-Path $root 'destination'
$expectedContent = 'Open Salamander path regression: Größe 東京 😀'
$reported = @()

function Assert-Condition {
    param([bool]$Condition, [string]$Description)
    if (-not $Condition) { throw "FAIL: $Description" }
    Write-Host "PASS: $Description"
}

try {
    [void][IO.Directory]::CreateDirectory($source)
    [void][IO.Directory]::CreateDirectory($target)

    # Total path longer than MAX_PATH, but no individual component is too long.
    $deepDir = $source
    foreach ($segment in @(
        ('long-directory-one-' + ('a' * 70))
        ('long-directory-two-' + ('b' * 70))
        ('long-directory-three-' + ('c' * 70))
    )) {
        $deepDir = Join-Path $deepDir $segment
        [void][IO.Directory]::CreateDirectory($deepDir)
    }
    $deepFile = Join-Path $deepDir 'Größe_東京_😀.txt'
    Assert-Condition ($deepFile.Length -gt 260) 'Deep absolute test path exceeds MAX_PATH'
    [IO.File]::WriteAllText($deepFile, $expectedContent, [Text.Encoding]::UTF8)
    Assert-Condition ([IO.File]::ReadAllText($deepFile, [Text.Encoding]::UTF8) -ceq $expectedContent) 'Read Unicode-named file in deep directory'
    $reported += $deepFile

    # Windows paths may be long; one NTFS name component is generally <=255 UTF-16 units.
    $maxFileName = ('f' * 251) + '.txt'
    Assert-Condition ($maxFileName.Length -eq 255) 'Individual filename is 255 UTF-16 code units'
    $maxFile = Join-Path $source $maxFileName
    [IO.File]::WriteAllText($maxFile, $expectedContent, [Text.Encoding]::UTF8)
    Assert-Condition ([IO.File]::Exists($maxFile)) 'Create filename with 255 UTF-16 code units'
    $reported += $maxFile

    $maxDirectory = Join-Path $source ('d' * 255)
    [void][IO.Directory]::CreateDirectory($maxDirectory)
    Assert-Condition ([IO.Directory]::Exists($maxDirectory)) 'Create directory name with 255 UTF-16 code units'
    $reported += $maxDirectory

    # Copy, rename and enumerate through .NET to validate test fixture integrity.
    $copy = Join-Path $target 'Größe_東京_😀.txt'
    [IO.File]::Copy($deepFile, $copy)
    Assert-Condition ([IO.File]::ReadAllText($copy, [Text.Encoding]::UTF8) -ceq $expectedContent) 'Copy deep source to short destination'
    $renamed = Join-Path $target 'umbenannt_東京_😀.txt'
    [IO.File]::Move($copy, $renamed)
    Assert-Condition ([IO.File]::Exists($renamed)) 'Rename Unicode file'
    Assert-Condition (([IO.Directory]::EnumerateFiles($deepDir) | Measure-Object).Count -eq 1) 'Enumerate deep directory'
    $reported += $renamed

    # Never assume 256-character *single* components are supported on NTFS.
    $tooLongFile = Join-Path $source (('n' * 252) + '.txt')
    $unexpectedlySucceeded = $false
    try {
        [IO.File]::WriteAllText($tooLongFile, 'invalid component', [Text.Encoding]::UTF8)
        $unexpectedlySucceeded = $true
    }
    catch [IO.IOException] {}
    catch [System.ArgumentException] {}
    if ($unexpectedlySucceeded) {
        throw 'A 256-character name unexpectedly succeeded. Recheck filesystem-specific component limits.'
    }
    Assert-Condition (-not [IO.File]::Exists($tooLongFile)) 'Reject a 256-code-unit single filename'

    Write-Host ''
    Write-Host 'Filesystem fixture passed. Salamander itself has NOT been tested.'
    if ($KeepFixture) {
        Write-Host "Fixture root (kept for GUI testing): $root"
        Write-Host "Source: $source"
        Write-Host "Destination: $target"
        Write-Host 'Manual Salamander checks: navigate, F5 copy, F6 move, F2 rename,'
        Write-Host 'F8 delete (on disposable copies), search and plugin operations.'
        foreach ($item in $reported) { Write-Host "  $item" }
    }
}
finally {
    if (-not $KeepFixture -and [IO.Directory]::Exists($root)) {
        [IO.Directory]::Delete($root, $true)
    }
}
