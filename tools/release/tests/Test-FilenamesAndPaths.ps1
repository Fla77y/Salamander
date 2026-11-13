#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
    Tests long paths, Unicode filenames, maximum component lengths and integrity.
.DESCRIPTION
    Exercises the Windows filesystem using .NET APIs. This DOES NOT prove that
    Salamander's GUI/plugins can handle these paths. Use -KeepFixture to conduct
    the accompanying manual acceptance tests in a disposable directory.
#>
[CmdletBinding()]
param([switch]$KeepFixture)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Requires Windows.' }

$root = Join-Path ([IO.Path]::GetTempPath()) (
    'OpenSal-Names-' + [Guid]::NewGuid().ToString('N'))
$source = Join-Path $root 'source'
$destination = Join-Path $root 'destination'
$utf8 = [Text.UTF8Encoding]::new($false)
$payload = [Text.Encoding]::UTF8.GetBytes(
    ('Salamander-RGB-テスト-äöü-😀' * 1024))
$checks = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:checks++
    Write-Host "PASS: $Message"
}

function Assert-FileBytes {
    param([string]$Path, [byte[]]$Expected, [string]$Message)
    # Arrange
    $actual = [IO.File]::ReadAllBytes($Path)
    # Assert
    $same = [System.Linq.Enumerable]::SequenceEqual[byte]($actual, $Expected)
    Assert-True $same $Message
}

try {
    [IO.Directory]::CreateDirectory($source) | Out-Null
    [IO.Directory]::CreateDirectory($destination) | Out-Null

    # Arrange: a path beyond MAX_PATH built from individually valid components.
    $longDir = $source
    foreach ($component in @(
        ('Ordner-A-' + ('a' * 68))
        ('Ordner-B-' + ('b' * 68))
        ('Ordner-C-' + ('c' * 68))
        ('Ordner-D-' + ('d' * 68))
    )) {
        $longDir = Join-Path $longDir $component
        [IO.Directory]::CreateDirectory($longDir) | Out-Null
    }
    $unicodeName = 'Größe_中文_日本_😀_é.txt'
    $longPath = Join-Path $longDir $unicodeName

    # Act
    [IO.File]::WriteAllBytes($longPath, $payload)
    # Assert
    Assert-True ($longPath.Length -gt 260) 'Absolute path exceeds 260 UTF-16 units'
    Assert-True ([IO.File]::Exists($longPath)) 'Create Unicode file in long directory'
    Assert-FileBytes $longPath $payload 'Read back all bytes without corruption'
    Assert-True ((@([IO.Directory]::EnumerateFiles($longDir))).Count -eq 1) 'Enumerate long directory'

    # Arrange: NTFS normally permits exactly 255 UTF-16 code units per name.
    $maximumName = ('n' * 251) + '.txt'
    $maximumFile = Join-Path $source $maximumName
    # Act
    [IO.File]::WriteAllBytes($maximumFile, $payload)
    # Assert
    Assert-True ($maximumName.Length -eq 255) 'Max filename is 255 UTF-16 code units'
    Assert-FileBytes $maximumFile $payload '255-unit file name created and readable'

    $unicodeMaximumName = ('x' * 249) + '😀' + '.txt'
    $unicodeMaximumFile = Join-Path $source $unicodeMaximumName
    # Act
    [IO.File]::WriteAllBytes($unicodeMaximumFile, $payload)
    # Assert
    Assert-True ($unicodeMaximumName.Length -eq 255) 'Surrogate pair counts as two UTF-16 units'
    Assert-FileBytes $unicodeMaximumFile $payload '255-unit Unicode filename created and readable'

    $maximumDirectory = Join-Path $source ('d' * 255)
    # Act
    [IO.Directory]::CreateDirectory($maximumDirectory) | Out-Null
    # Assert
    Assert-True ([IO.Directory]::Exists($maximumDirectory)) '255-unit directory component created'

    # Arrange: single component beyond NTFS limit (not a total-path issue).
    $oversizedName = ('f' * 252) + '.txt'
    $oversizedFile = Join-Path $source $oversizedName
    $rejected = $false
    # Act
    try { [IO.File]::WriteAllText($oversizedFile, 'invalid', $utf8) }
    catch [IO.IOException] { $rejected = $true }
    catch [System.ArgumentException] { $rejected = $true }
    # Assert
    Assert-True ($rejected -and -not [IO.File]::Exists($oversizedFile)) '256-unit filename rejected'

    # Arrange: destination is distinct and disposable.
    $copy = Join-Path $destination $unicodeName
    $renamed = Join-Path $destination 'umbenannt_東京_😀.txt'
    # Act
    [IO.File]::Copy($longPath, $copy)
    # Assert
    Assert-FileBytes $copy $payload 'Copy bytes from >260-character path to destination'

    # Act
    [IO.File]::Move($copy, $renamed)
    # Assert
    Assert-True (-not [IO.File]::Exists($copy)) 'Old name disappears after move'
    Assert-FileBytes $renamed $payload 'Unicode rename preserves bytes'

    # Act
    [IO.File]::Delete($renamed)
    # Assert
    Assert-True (-not [IO.File]::Exists($renamed)) 'Delete Unicode-named file'

    # Arrange: collision must never overwrite destination silently.
    $collision = Join-Path $destination 'collision.txt'
    $other = Join-Path $destination 'other.txt'
    [IO.File]::WriteAllText($collision, 'original', $utf8)
    [IO.File]::WriteAllText($other, 'other', $utf8)
    $collisionRejected = $false
    # Act
    try { [IO.File]::Move($other, $collision) }
    catch [IO.IOException] { $collisionRejected = $true }
    # Assert
    Assert-True $collisionRejected 'Collision without overwrite rejected'
    Assert-True ([IO.File]::ReadAllText($collision, $utf8) -ceq 'original') 'Collision preserves destination data'
    Assert-True ([IO.File]::ReadAllText($other, $utf8) -ceq 'other') 'Collision preserves source data'

    # Ensure any file creation that falsely reports success is detected.
    Assert-True (@([IO.Directory]::EnumerateFiles($source)).Count -eq 2) 'Exact source file count'
    Write-Host "SUCCESS: $checks filesystem assertions passed."
    Write-Warning 'These are Windows/.NET tests, NOT Salamander GUI/plug-in integration tests.'
    if ($KeepFixture) {
        Write-Host "Test directory retained: $root"
        Write-Host "Long directory: $longDir"
        Write-Host 'Manual Salamander acceptance: navigate, view, F5 copy, F6 move,'
        Write-Host 'F2 rename, F8 delete (only on copies), search, plugin access and F1.'
    }
}
finally {
    if (-not $KeepFixture -and [IO.Directory]::Exists($root)) {
        [IO.Directory]::Delete($root, $true)
    }
}
