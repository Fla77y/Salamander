#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later

# Loaded by the isolated GUI driver. The tests use deterministic disposable
# files and the original dialog's controls and search commands.

function Open-TestLegacyFind {
    param(
        [string]$ShortcutPanelPath,
        [ValidateSet('^f','%{F7}')][string]$Shortcut = '^f'
    )

    $pidOfTest = [uint32]$process.Id
    if ($ShortcutPanelPath) {
        Restore-FilePanelFocus -ExpectedPath $ShortcutPanelPath
        Send-Keys $Shortcut
    }
    else {
        [SalamanderGuiNative]::LegacyFindCommand($mainWindowHandle, $pidOfTest, 741, $true)
    }
    $windows = @{ Legacy = [IntPtr]::Zero; Unicode = [IntPtr]::Zero }
    Wait-Until {
        $windows.Legacy = [SalamanderGuiNative]::FindLegacySearchWindow($pidOfTest)
        $windows.Unicode = [SalamanderGuiNative]::FindUnicodeSearchWindow($pidOfTest)
        return $windows.Legacy -ne [IntPtr]::Zero -or $windows.Unicode -ne [IntPtr]::Zero
    } 'Find command opened a dialog owned by the isolated process'
    Assert-True ($windows.Legacy -ne [IntPtr]::Zero -and $windows.Unicode -eq [IntPtr]::Zero) (
        'Find opens the original IDD_FIND directly with Look in (2501) and legacy results (2510)')
    return $windows.Legacy
}

function Set-LegacyFindQuery {
    param(
        [string]$SearchRoot,
        [string]$Mask,
        [bool]$Recursive = $false,
        [string]$Content = '',
        [ValidateSet('Plain','Case','Whole','Regex','Hex')][string]$Mode = 'Plain'
    )

    $pidOfTest = [uint32]$process.Id
    [SalamanderGuiNative]::SetFindText($legacyWindow, $pidOfTest, 2501, $SearchRoot)
    [SalamanderGuiNative]::SetFindText($legacyWindow, $pidOfTest, 2505, $Mask)
    [SalamanderGuiNative]::SetLegacyFindCheck($legacyWindow, $pidOfTest, 2503, [uint32]$Recursive)
    # Collapse before each query so the original dialog resets every grep flag.
    [SalamanderGuiNative]::SetLegacyFindCheck($legacyWindow, $pidOfTest, 2508, 0)
    if ($Content -ne '') {
        [SalamanderGuiNative]::SetLegacyFindCheck($legacyWindow, $pidOfTest, 2508, 1)
        $checkId = @{ Case = 2515; Whole = 2514; Regex = 2513; Hex = 2516 }[$Mode]
        if ($null -ne $checkId) {
            [SalamanderGuiNative]::SetLegacyFindCheck($legacyWindow, $pidOfTest, $checkId, 1)
        }
        [SalamanderGuiNative]::SetFindText($legacyWindow, $pidOfTest, 2504, $Content)
    }
}

function Assert-LegacyFindCount {
    param([int]$Expected, [string]$Description)

    $pidOfTest = [uint32]$process.Id
    Wait-Until {
        if ($process.HasExited) { throw "Original Find process exited with $($process.ExitCode)." }
        $errorDialog = [SalamanderGuiNative]::FindLegacyModal($legacyWindow, $pidOfTest, 'Error')
        if ($errorDialog -ne [IntPtr]::Zero) {
            throw "Original Find rejected the query: $Description"
        }
        return [SalamanderGuiNative]::OwnedControlEnabled($legacyWindow, $pidOfTest, 2505)
    } 'original Find completed and re-enabled query controls'
    $actual = [SalamanderGuiNative]::LegacyFindResultCount($legacyWindow, $pidOfTest)
    Assert-True ($actual -eq $Expected) "${Description} (expected $Expected results, got $actual)"
}

function Invoke-LegacyFindQuery {
    param([int]$Expected, [string]$Description, [uint32]$Command = 2288)

    $ownerPid = [uint32]$process.Id
    try {
        [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, $ownerPid, $Command, $false)
    }
    catch {
        if ([SalamanderGuiNative]::FindLegacyModal($legacyWindow, $ownerPid, 'Error') -ne [IntPtr]::Zero) {
            throw "Original Find rejected the query before enumeration: $Description"
        }
        throw
    }
    Assert-LegacyFindCount -Expected $Expected -Description $Description
}

function Read-LegacyFindResult {
    param([int]$Index, [uint32]$CopyCommand = 2283)

    $pidOfTest = [uint32]$process.Id
    $sentinel = 'Legacy Find has not published a result'
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        [SalamanderGuiNative]::SelectLegacyFindRow($legacyWindow, $pidOfTest, $Index)
        Set-ClipboardText $sentinel
        if ((Get-ClipboardText) -cne $sentinel) { continue }
        $sequence = [SalamanderGuiNative]::GetClipboardSequenceNumber()
        [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, $pidOfTest, $CopyCommand, $false)
        for ($poll = 0; $poll -lt 4; $poll++) {
            $observed = Get-ClipboardText
            if ([SalamanderGuiNative]::GetClipboardSequenceNumber() -ne $sequence -and
                $observed -and $observed -cne $sentinel) {
                return $observed
            }
            Start-Sleep -Milliseconds 100
        }
        # Only the read-only result-copy command is ever retried.
    }
    throw "Original Find command $CopyCommand did not publish verified row $Index to the clipboard."
}

function Assert-LegacyFindNotice {
    param([IntPtr]$Owner, [string]$Title, [string]$ExpectedText)

    $ownerPid = [uint32]$process.Id
    $notice = @{ Handle = [IntPtr]::Zero }
    Wait-Until {
        $notice.Handle = [SalamanderGuiNative]::FindLegacyModal($Owner, $ownerPid, $Title)
        return $notice.Handle -ne [IntPtr]::Zero
    } "validation shows the owned $Title dialog"
    if ($ExpectedText) {
        Assert-True ([SalamanderGuiNative]::HasVerifiedStaticText($notice.Handle, $ownerPid, $ExpectedText)) (
            "Validation explains the rejected input: $ExpectedText")
    }
    [SalamanderGuiNative]::PostFindButton($notice.Handle, $ownerPid, 1)
    Wait-Until { -not [SalamanderGuiNative]::IsWindowVisible($notice.Handle) } 'validation message dismissed'
    Assert-True ([SalamanderGuiNative]::IsWindowVisible($Owner)) 'Validation leaves the owning dialog open'
}

function Edit-LegacyFindAdvanced {
    param([scriptblock]$Configure, [int]$FinishButton = 1)

    $pidOfTest = [uint32]$process.Id
    [SalamanderGuiNative]::PostFindButton($legacyWindow, $pidOfTest, 2506)
    $window = @{ Handle = [IntPtr]::Zero }
    Wait-Until {
        $window.Handle = [SalamanderGuiNative]::FindLegacyModal($legacyWindow, $pidOfTest, 'Advanced Options')
        return $window.Handle -ne [IntPtr]::Zero
    } 'owned Advanced Options dialog'
    & $Configure $window.Handle $pidOfTest
    [SalamanderGuiNative]::PostFindButton($window.Handle, $pidOfTest, $FinishButton)
    Wait-Until {
        -not [SalamanderGuiNative]::IsWindowVisible($window.Handle)
    } 'Advanced Options closed after validation'
}

function Test-LegacyFindMasksAndContents {
    param([string]$Fixture)

    # Arrange: each option changes the set of matches observably.
    $first = [IO.Directory]::CreateDirectory((Join-Path $Fixture 'a')).FullName
    $nested = [IO.Directory]::CreateDirectory((Join-Path $first 'nested')).FullName
    $second = [IO.Directory]::CreateDirectory((Join-Path $Fixture 'b')).FullName
    $semicolon = [IO.Directory]::CreateDirectory((Join-Path $Fixture 'with;semi')).FullName
    [IO.File]::WriteAllText((Join-Path $first 'alpha-hit.txt'), 'Needle token-42')
    [IO.File]::WriteAllText((Join-Path $first 'alpha-log.log'), 'needle token-xy')
    [IO.File]::WriteAllText((Join-Path $first 'skip-alpha.txt'), 'needlex token-77')
    [IO.File]::WriteAllText((Join-Path $nested 'alpha-deep.txt'), 'needle token-123')
    [IO.File]::WriteAllText((Join-Path $second 'outside.txt'), 'unrelated')
    [IO.File]::WriteAllText((Join-Path $semicolon 'escaped.txt'), 'unrelated')
    [IO.File]::WriteAllBytes((Join-Path $first 'bytes.bin'), [byte[]]@(0, 0xDE, 0xAD, 0, 0xBE, 0xEF))

    $combinedRoots = (@($first, $second) * 4) -join ';'
    Assert-True ($combinedRoots.Length -gt 260 -and $first.Length -lt 260 -and $second.Length -lt 260) (
        'Root list exceeds the former input limit while its individual roots are short')
    $queries = @(
        @{ Root = $first; Mask = '*.txt'; Count = 2; Label = 'Name mask without recursion' }
        @{ Root = $first; Mask = '*.txt'; Recursive = $true; Count = 3; Label = 'Name mask with recursion' }
        @{ Root = $first; Mask = '*.txt;*.log|skip*'; Recursive = $true; Count = 3; Label = 'Multiple include masks and exclusion mask' }
        @{ Root = $first; Mask = 'alpha'; Count = 3; Label = 'Bare names match substrings' }
        @{ Root = "$first;$second"; Mask = '*.txt'; Count = 3; Label = 'Separate roots are searched in one query' }
        @{ Root = $combinedRoots; Mask = '*.txt'; Count = 12; Label = 'Every root is searched when the root list exceeds MAX_PATH' }
        @{ Root = $semicolon.Replace(';', ';;'); Mask = 'escaped.txt'; Count = 1; Label = 'Escaped semicolon in search root' }
        @{ Root = $first; Mask = 'missing-?.txt'; Count = 0; Label = 'No-match query clears earlier results' }
        @{ Root = $first; Mask = '*.txt;*.log'; Content = 'needle'; Count = 3; Label = 'Default grep is case-insensitive and matches substrings' }
        @{ Root = $first; Mask = '*.txt;*.log'; Content = 'needle'; Mode = 'Case'; Count = 2; Label = 'Case-sensitive grep rejects uppercase initial' }
        @{ Root = $first; Mask = '*.txt;*.log'; Content = 'needle'; Mode = 'Whole'; Count = 2; Label = 'Whole words reject a trailing word character' }
        @{ Root = $first; Mask = '*.txt;*.log|skip*'; Recursive = $true; Content = 'token-[0-9][0-9]$'; Mode = 'Regex'; Count = 1; Label = 'Regex, recursive enumeration and exclusions compose' }
        @{ Root = $first; Mask = '*.bin'; Content = 'DE AD 00 BE'; Mode = 'Hex'; Count = 1; Label = 'Hex matches across an embedded zero byte' }
        @{ Root = $first; Mask = '*.bin'; Content = 'DE AD FF BE'; Mode = 'Hex'; Count = 0; Label = 'Hex rejects a differing byte' }
    )
    foreach ($case in $queries) {
        # Act
        Set-LegacyFindQuery -SearchRoot $case.Root -Mask $case.Mask -Recursive ([bool]$case['Recursive']) `
            -Content ([string]$case['Content']) -Mode ($case['Mode'] ?? 'Plain')
        # Assert
        Invoke-LegacyFindQuery -Expected $case.Count -Description $case.Label
    }
    $ownerPid = [uint32]$process.Id
    Assert-True ([SalamanderGuiNative]::ReadLegacyFindHistory($legacyWindow, $ownerPid, 2505, 0) -ceq '*.bin') (
        'Name history uses the most recent distinct accepted mask')
    Assert-True ([SalamanderGuiNative]::ReadLegacyFindHistory($legacyWindow, $ownerPid, 2501, 0) -ceq $first) (
        'Root history uses the most recent distinct accepted directory')
    Assert-True ([SalamanderGuiNative]::ReadLegacyFindHistory($legacyWindow, $ownerPid, 2504, 0) -ceq 'DE AD FF BE') (
        'Content history retains the most recent accepted hex pattern verbatim')
}

function Test-LegacyFindContentControls {
    param([string]$Fixture)

    $pidOfTest = [uint32]$process.Id
    Set-LegacyFindQuery -SearchRoot $Fixture -Mask '*.txt'
    Assert-True (-not [SalamanderGuiNative]::IsLegacyFindControlVisible($legacyWindow, $pidOfTest, 2504)) (
        'Content input collapses when Search file content is unchecked')
    [SalamanderGuiNative]::SetLegacyFindCheck($legacyWindow, $pidOfTest, 2508, 1)
    Assert-True ([SalamanderGuiNative]::IsLegacyFindControlVisible($legacyWindow, $pidOfTest, 2504)) (
        'Content input expands when Search file content is checked')
    [SalamanderGuiNative]::SetLegacyFindCheck($legacyWindow, $pidOfTest, 2516, 1)
    Assert-True ([SalamanderGuiNative]::ReadLegacyFindCheck($legacyWindow, $pidOfTest, 2515) -eq 1) (
        'Hex selection enables case-sensitive matching by default')
    [SalamanderGuiNative]::SetLegacyFindCheck($legacyWindow, $pidOfTest, 2513, 1)
    Assert-True ([SalamanderGuiNative]::ReadLegacyFindCheck($legacyWindow, $pidOfTest, 2516) -eq 0 -and
        -not [SalamanderGuiNative]::OwnedControlEnabled($legacyWindow, $pidOfTest, 2516)) (
        'Regex selection clears and disables Hex mode')
    [SalamanderGuiNative]::SetFindText($legacyWindow, $pidOfTest, 2504, 'token[0-9]+')
    [SalamanderGuiNative]::SetLegacyFindCheck($legacyWindow, $pidOfTest, 2508, 0)
    [SalamanderGuiNative]::SetLegacyFindCheck($legacyWindow, $pidOfTest, 2508, 1)
    Assert-True ([SalamanderGuiNative]::ReadFindText($legacyWindow, $pidOfTest, 2504) -ceq '' -and
        [SalamanderGuiNative]::ReadLegacyFindCheck($legacyWindow, $pidOfTest, 2513) -eq 0) (
        'Disabling content search clears the query and Regex checkbox')
}

function Test-LegacyFindAdvanced {
    param([string]$Fixture)

    # Arrange: identical masks but distinguishable attributes, sizes and times.
    $folder = [IO.Directory]::CreateDirectory((Join-Path $Fixture 'filters')).FullName
    $attributes = @('Archive','ReadOnly','Hidden','System')
    foreach ($attribute in $attributes) {
        $file = Join-Path $folder "$attribute.dat"
        [IO.File]::WriteAllText($file, 'attr')
        [IO.File]::SetAttributes($file, [IO.FileAttributes]$attribute)
    }
    [void][IO.Directory]::CreateDirectory((Join-Path $folder 'Directory.dat'))
    foreach ($size in @(31,32,33,63,64,65,1024)) {
        [IO.File]::WriteAllBytes((Join-Path $folder "size-$size.bin"), [byte[]]::new($size))
    }
    $now = [DateTime]::UtcNow
    foreach ($age in @(1,30,365)) {
        $file = Join-Path $folder "time-$age.dat"
        [IO.File]::WriteAllText($file, 'time')
        [IO.File]::SetLastWriteTimeUtc($file, $now.AddDays(-$age))
    }
    try {
        foreach ($attr in @(
            @{ Id = 2561; File = 'Archive' }, @{ Id = 2562; File = 'ReadOnly' },
            @{ Id = 2563; File = 'Hidden' }, @{ Id = 2564; File = 'System' },
            @{ Id = 2566; File = 'Directory' }
        )) {
            Set-LegacyFindQuery -SearchRoot $folder -Mask "$($attr.File).dat"
            foreach ($state in @(0,1,2)) {
                # Act / assert: absent, required, and ignored respectively.
                Edit-LegacyFindAdvanced -Configure {
                    param($dialog, $ownerPid)
                    [SalamanderGuiNative]::SetLegacyFindCheck($dialog, $ownerPid, $attr.Id, $state)
                }
                Invoke-LegacyFindQuery -Expected ([int]($state -ne 0)) `
                    -Description "$($attr.File) attribute tri-state $state"
            }
        }
        foreach ($id in @(2565,2586)) {
            # The clean fixture carries neither compression nor encryption.
            Set-LegacyFindQuery -SearchRoot $folder -Mask 'Archive.dat'
            Edit-LegacyFindAdvanced -Configure {
                param($dialog, $ownerPid)
                [SalamanderGuiNative]::SetLegacyFindCheck($dialog, $ownerPid, $id, 1)
            }
            Invoke-LegacyFindQuery -Expected 0 -Description "Required attribute $id excludes an ordinary file"
            Edit-LegacyFindAdvanced -Configure {
                param($dialog, $ownerPid)
                [SalamanderGuiNative]::SetLegacyFindCheck($dialog, $ownerPid, $id, 0)
            }
            Invoke-LegacyFindQuery -Expected 1 -Description "Excluded attribute $id accepts an ordinary file"
            Edit-LegacyFindAdvanced -Configure {
                param($dialog, $ownerPid)
                [SalamanderGuiNative]::SetLegacyFindCheck($dialog, $ownerPid, $id, 2)
            }
        }
        Set-LegacyFindQuery -SearchRoot $folder -Mask 'size-*.bin'
        Edit-LegacyFindAdvanced -Configure {
            param($dialog, $ownerPid)
            [SalamanderGuiNative]::SetLegacyFindCheck($dialog, $ownerPid, 2567, 1)
            [SalamanderGuiNative]::SetFindText($dialog, $ownerPid, 2568, '32')
            [SalamanderGuiNative]::SetLegacyFindComboIndex($dialog, $ownerPid, 2570, 0)
            [SalamanderGuiNative]::SetLegacyFindCheck($dialog, $ownerPid, 2571, 1)
            [SalamanderGuiNative]::SetFindText($dialog, $ownerPid, 2572, '64')
            [SalamanderGuiNative]::SetLegacyFindComboIndex($dialog, $ownerPid, 2574, 0)
        }
        Invoke-LegacyFindQuery -Expected 4 -Description 'Advanced min and max size include both endpoints'
        Edit-LegacyFindAdvanced -Configure {
            param($dialog, $ownerPid)
            [SalamanderGuiNative]::SetFindText($dialog, $ownerPid, 2572, '1')
            [SalamanderGuiNative]::SetLegacyFindComboIndex($dialog, $ownerPid, 2574, 1)
        }
        Invoke-LegacyFindQuery -Expected 6 -Description 'Advanced maximum uses binary kilobytes'
        foreach ($unit in @(
            @{ Name = 'MB'; Index = 2 }, @{ Name = 'GB'; Index = 3 }, @{ Name = 'TB'; Index = 4 },
            @{ Name = 'PB'; Index = 5 }, @{ Name = 'EB'; Index = 6 }
        )) {
            Edit-LegacyFindAdvanced -Configure {
                param($dialog, $ownerPid)
                [SalamanderGuiNative]::SetFindText($dialog, $ownerPid, 2572, '1')
                [SalamanderGuiNative]::SetLegacyFindComboIndex($dialog, $ownerPid, 2574, $unit.Index)
            }
            Invoke-LegacyFindQuery -Expected 6 -Description "Advanced maximum accepts a 1 $($unit.Name) boundary"
        }
        Edit-LegacyFindAdvanced -Configure {
            param($dialog, $ownerPid)
            [SalamanderGuiNative]::SetFindText($dialog, $ownerPid, 2572, '31')
            [SalamanderGuiNative]::SetLegacyFindComboIndex($dialog, $ownerPid, 2574, 0)
            [SalamanderGuiNative]::PostFindButton($dialog, $ownerPid, 1)
            Assert-LegacyFindNotice -Owner $dialog -Title 'Error' -ExpectedText 'Second size cannot be less than first size.'
        } -FinishButton 2
        Invoke-LegacyFindQuery -Expected 6 -Description 'Rejecting inverted size bounds leaves applied criteria intact'
        Edit-LegacyFindAdvanced -Configure {
            param($dialog, $ownerPid)
            [SalamanderGuiNative]::SetLegacyFindCheck($dialog, $ownerPid, 2571, 0)
        } -FinishButton 2
        Invoke-LegacyFindQuery -Expected 6 -Description 'Cancelling Advanced preserves the previously applied filter'
        Edit-LegacyFindAdvanced -Configure {
            param($dialog, $ownerPid)
            [SalamanderGuiNative]::ClickFindButton($dialog, $ownerPid, 2585)
        }
        Invoke-LegacyFindQuery -Expected 7 -Description 'Advanced Reset removes both size bounds'

        Set-LegacyFindQuery -SearchRoot $folder -Mask 'time-*.dat'
        Edit-LegacyFindAdvanced -Configure {
            param($dialog, $ownerPid)
            [SalamanderGuiNative]::SetLegacyFindCheck($dialog, $ownerPid, 2575, 0)
            [SalamanderGuiNative]::SetLegacyFindCheck($dialog, $ownerPid, 2576, 1)
            [SalamanderGuiNative]::SetFindText($dialog, $ownerPid, 2578, '7')
            [SalamanderGuiNative]::SetLegacyFindComboIndex($dialog, $ownerPid, 2580, 3)
        }
        Invoke-LegacyFindQuery -Expected 1 -Description 'Modified during the last seven days'
        foreach ($unit in @(
            @{ Index = 0; Text = 'seconds'; Value = 7; Count = 0 }
            @{ Index = 1; Text = 'minutes'; Value = 7; Count = 0 }
            @{ Index = 2; Text = 'hours'; Value = 7; Count = 0 }
            @{ Index = 4; Text = 'weeks'; Value = 7; Count = 2 }
            @{ Index = 5; Text = 'months'; Value = 7; Count = 2 }
            @{ Index = 6; Text = 'years'; Value = 2; Count = 3 }
        )) {
            Edit-LegacyFindAdvanced -Configure {
                param($dialog, $ownerPid)
                [SalamanderGuiNative]::SetFindText($dialog, $ownerPid, 2578, [string]$unit.Value)
                [SalamanderGuiNative]::SetLegacyFindComboIndex($dialog, $ownerPid, 2580, $unit.Index)
            }
            Invoke-LegacyFindQuery -Expected $unit.Count -Description "Modified during the last $($unit.Value) $($unit.Text)"
        }
        Edit-LegacyFindAdvanced -Configure {
            param($dialog, $ownerPid)
            [SalamanderGuiNative]::ClickFindButton($dialog, $ownerPid, 2585)
        }
        Invoke-LegacyFindQuery -Expected 3 -Description 'Ignore date and time after Advanced Reset'
    }
    finally {
        [IO.File]::SetAttributes((Join-Path $folder 'ReadOnly.dat'), [IO.FileAttributes]::Normal)
    }
}

function Test-LegacyFindRefinement {
    param([string]$Fixture)

    $folder = [IO.Directory]::CreateDirectory((Join-Path $Fixture 'refine')).FullName
    foreach ($file in @('first-a.txt','second-a.txt','second-b.txt','third-b.txt')) {
        [IO.File]::WriteAllText((Join-Path $folder $file), $file)
    }
    Set-LegacyFindQuery -SearchRoot $folder -Mask '*-a.txt'
    Invoke-LegacyFindQuery -Expected 2 -Description 'Refinement seed'
    Set-LegacyFindQuery -SearchRoot $folder -Mask 'second-*'
    Invoke-LegacyFindQuery -Expected 1 -Description 'Intersect retains only matching previous results' -Command 2289
    Set-LegacyFindQuery -SearchRoot $folder -Mask 'second-*'
    Invoke-LegacyFindQuery -Expected 3 -Description 'Append retains prior rows and adds all new matches, including overlap' -Command 2291
    Set-LegacyFindQuery -SearchRoot $folder -Mask '*-b.txt'
    Invoke-LegacyFindQuery -Expected 2 -Description 'Subtract removes matching prior rows and preserves the two overlapping rows' -Command 2290
    [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, [uint32]$process.Id, 2287, $false)
    Assert-LegacyFindCount -Expected 1 -Description 'Hide Duplicate Names collapses identical path/name rows'
    Assert-True ((Read-LegacyFindResult -Index 0) -ceq (Join-Path $folder 'second-a.txt')) (
        'Refinement and duplicate hiding retain the correct file')
}

function Test-LegacyFindDuplicates {
    param([string]$Fixture)

    $folder = [IO.Directory]::CreateDirectory((Join-Path $Fixture 'duplicates')).FullName
    foreach ($directory in @('first','second','third')) {
        [void][IO.Directory]::CreateDirectory((Join-Path $folder $directory))
    }
    [IO.File]::WriteAllText((Join-Path $folder 'first\same.txt'), 'original')
    [IO.File]::WriteAllText((Join-Path $folder 'second\same.txt'), 'original')
    [IO.File]::WriteAllText((Join-Path $folder 'third\same.txt'), 'longer variant')
    [IO.File]::WriteAllText((Join-Path $folder 'other.txt'), 'difftext')
    $ownerPid = [uint32]$process.Id
    $cases = @(
        @{ Name = 1; Size = 1; Content = 1; Count = 2; Description = 'Duplicate name, size and exact content' }
        @{ Name = 0; Size = 1; Content = 0; Count = 3; Description = 'Duplicate size with different names and contents' }
        @{ Name = 1; Size = 0; Content = 0; Count = 3; Description = 'Duplicate names with different sizes' }
        @{ Name = 0; Size = 1; Content = 1; Count = 2; Description = 'Duplicate content without the name criterion' }
    )
    foreach ($case in $cases) {
        Set-LegacyFindQuery -SearchRoot $folder -Mask '*.txt' -Recursive $true
        [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, $ownerPid, 2292, $true)
        $owned = @{ Handle = [IntPtr]::Zero }
        Wait-Until {
            $owned.Handle = [SalamanderGuiNative]::FindLegacyModal(
                $legacyWindow, $ownerPid, 'Find Duplicate Files')
            return $owned.Handle -ne [IntPtr]::Zero
        } 'owned duplicate criteria dialog'
        [SalamanderGuiNative]::SetLegacyFindCheck($owned.Handle, $ownerPid, 2751, $case.Name)
        [SalamanderGuiNative]::SetLegacyFindCheck($owned.Handle, $ownerPid, 2752, $case.Size)
        if ($case.Size) {
            [SalamanderGuiNative]::SetLegacyFindCheck($owned.Handle, $ownerPid, 2753, $case.Content)
        } else {
            Assert-True (-not [SalamanderGuiNative]::OwnedControlEnabled($owned.Handle, $ownerPid, 2753)) (
                'Duplicate content is unavailable without the size criterion')
        }
        [SalamanderGuiNative]::PostFindButton($owned.Handle, $ownerPid, 1)
        Wait-Until { -not [SalamanderGuiNative]::IsWindowVisible($owned.Handle) } 'duplicate criteria dialog closed'

        # EndDialog hides the modal before StartSearch resumes in its owning
        # GUI thread. A read-only WM_NULL message synchronizes that dispatch:
        # otherwise the still-enabled query controls can make an unstarted
        # duplicate search look like a completed zero-result search.
        if ([SalamanderGuiNative]::FindLegacySearchWindow($ownerPid) -ne $legacyWindow) {
            throw 'Original Find window changed during duplicate criteria confirmation.'
        }
        [IntPtr]$barrierResult = [IntPtr]::Zero
        $barrier = [SalamanderGuiNative]::SendMessageTimeout(
            $legacyWindow, [uint32]0, [UIntPtr]::Zero, [IntPtr]::Zero,
            [uint32]2, [uint32]5000, [ref]$barrierResult)
        $barrierError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        if ($barrier -eq [IntPtr]::Zero) {
            throw "Duplicate search modal dispatch did not complete (Win32 error $barrierError)."
        }

        Assert-LegacyFindCount -Expected $case.Count -Description $case.Description
    }
}

function Test-LegacyFindDirectoryLinkCycle {
    param([string]$Fixture)

    $needle = Join-Path $Fixture 'needle.txt'
    $linkTarget = [IO.Directory]::CreateDirectory((Join-Path $root 'junction-target')).FullName
    $loop = Join-Path $Fixture 'loop'
    $forward = Join-Path $Fixture 'forward'
    $junctions = [Collections.Generic.List[string]]::new()
    [IO.File]::WriteAllText($needle, 'needle42')
    [IO.File]::WriteAllText((Join-Path $linkTarget 'needle.txt'), 'needle99')
    try {
        New-Item -ItemType Junction -Path $loop -Target $Fixture | Out-Null
        $junctions.Add($loop)
        New-Item -ItemType Junction -Path $forward -Target $linkTarget | Out-Null
        $junctions.Add($forward)
        Set-LegacyFindQuery -SearchRoot $Fixture -Mask 'needle.txt' -Recursive $true
        Invoke-LegacyFindQuery -Expected 2 -Description 'Search follows an ordinary junction and skips a cycle'
        $results = @(Read-LegacyFindResult -Index 0; Read-LegacyFindResult -Index 1)
        Assert-True ($results -ccontains $needle -and $results -ccontains (Join-Path $forward 'needle.txt')) (
            'Junction traversal preserves both original result paths')
    }
    finally {
        foreach ($junction in $junctions) {
            if (([IO.File]::GetAttributes($junction) -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
                throw 'Refusing to remove a path that no longer identifies the test junction.'
            }
            [IO.Directory]::Delete($junction, $false)
        }
    }
}

function Test-LegacyFindResultActions {
    param([string]$Fixture)

    # Arrange: different sort keys identify a misrouted column.
    $folder = [IO.Directory]::CreateDirectory((Join-Path $Fixture 'results')).FullName
    foreach ($case in @(
        @{ Dir = 'm-dir'; Name = 'alpha.txt'; Size = 30; Day = 15 }
        @{ Dir = 'a-dir'; Name = 'bravo.txt'; Size = 10; Day = 16 }
        @{ Dir = 'z-dir'; Name = 'charlie.txt'; Size = 20; Day = 14 }
    )) {
        $path = [IO.Directory]::CreateDirectory((Join-Path $folder $case.Dir)).FullName
        $file = Join-Path $path $case.Name
        [IO.File]::WriteAllBytes($file, [byte[]]::new($case.Size))
        [IO.File]::SetLastWriteTimeUtc($file, [DateTime]::new(2024, 1, $case.Day, 12, 0, 0, [DateTimeKind]::Utc))
    }
    $ownerPid = [uint32]$process.Id
    Set-LegacyFindQuery -SearchRoot $folder -Mask '*.txt' -Recursive $true
    Invoke-LegacyFindQuery -Expected 3 -Description 'Results fixture'
    foreach ($sort in @(
        @{ Command = 2237; Column = 'Name'; Order = 'alpha.txt|bravo.txt|charlie.txt' }
        @{ Command = 2241; Column = 'Path'; Order = 'bravo.txt|alpha.txt|charlie.txt' }
        @{ Command = 2240; Column = 'Size'; Order = 'bravo.txt|charlie.txt|alpha.txt' }
        @{ Command = 2239; Column = 'Modified'; Order = 'charlie.txt|alpha.txt|bravo.txt' }
    )) {
        [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, $ownerPid, $sort.Command, $false)
        $names = foreach ($row in 0..2) { Read-LegacyFindResult -Index $row -CopyCommand 2284 }
        Assert-True (($names -join '|') -ceq $sort.Order) "$($sort.Column) sorts the actual rows"
    }

    [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, $ownerPid, 2231, $false)
    Assert-True ([SalamanderGuiNative]::LegacyFindSelectionCount($legacyWindow, $ownerPid) -eq 3) (
        'Select All selects every actual result')
    [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, $ownerPid, 2232, $false)
    Assert-True ([SalamanderGuiNative]::LegacyFindSelectionCount($legacyWindow, $ownerPid) -eq 0) (
        'Invert Selection clears a complete selection')
    $fileToHide = Read-LegacyFindResult -Index 0
    Assert-True ((Read-LegacyFindResult -Index 0 -CopyCommand 2285) -ceq (Split-Path -Parent $fileToHide)) (
        'Copy Full Path publishes the selected directory')
    [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, $ownerPid, 2225, $false)
    Assert-True ((Read-PanelPath) -ceq (Split-Path -Parent $fileToHide)) (
        'Focus File navigates the real panel to the selected result directory')
    [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, $ownerPid, 2281, $false)
    Assert-LegacyFindCount -Expected 2 -Description 'Hide Selection removes one row'
    Assert-True ([IO.File]::Exists($fileToHide)) 'Hide Selection leaves the file intact'
}

function Test-LegacyFindErrorLog {
    param([string]$Fixture)

    $existing = [IO.Directory]::CreateDirectory((Join-Path $Fixture 'log-valid')).FullName
    $absent = Join-Path $Fixture 'log-missing'
    [IO.File]::WriteAllText((Join-Path $existing 'surviving.txt'), 'retained result')
    Set-LegacyFindQuery -SearchRoot "$existing;$absent" -Mask '*.txt'
    Invoke-LegacyFindQuery -Expected 1 -Description 'Missing root does not suppress results from another root'

    $ownerPid = [uint32]$process.Id
    $window = @{ Handle = [SalamanderGuiNative]::FindLegacyModal($legacyWindow, $ownerPid, 'Find Log') }
    if ($window.Handle -eq [IntPtr]::Zero) {
        [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, $ownerPid, 2233, $true)
    }
    Wait-Until {
        $window.Handle = [SalamanderGuiNative]::FindLegacyModal($legacyWindow, $ownerPid, 'Find Log')
        return $window.Handle -ne [IntPtr]::Zero
    } 'Find Log opens for the failed enumeration'
    Assert-True ([SalamanderGuiNative]::LegacyFindListCount($window.Handle, $ownerPid, 2756) -gt 0) (
        'Find Log contains a row for the inaccessible search root')
    [SalamanderGuiNative]::PostFindButton($window.Handle, $ownerPid, 1)
    Wait-Until { -not [SalamanderGuiNative]::IsWindowVisible($window.Handle) } 'Find Log closed'
    Assert-True ((Read-LegacyFindResult -Index 0) -ceq (Join-Path $existing 'surviving.txt')) (
        'Find Log leaves the successful result usable')
}

function Test-LegacyFindValidation {
    param([string]$Fixture)

    $folder = [IO.Directory]::CreateDirectory((Join-Path $Fixture 'validation')).FullName
    [IO.File]::WriteAllText((Join-Path $folder 'found.txt'), 'token-42')
    $ownerPid = [uint32]$process.Id
    foreach ($case in @(
        @{ Root = ''; Mask = '*.txt'; Content = ''; Mode = 'Plain'; Title = 'Error'; Text = 'Empty string is not allowed here.' }
        @{ Root = $folder; Mask = '*|x|y'; Content = ''; Mode = 'Plain'; Title = 'Error'; Text = 'File mask is syntactically incorrect.' }
        @{ Root = $folder; Mask = '*.txt'; Content = 'GG'; Mode = 'Hex'; Title = 'Error'; Text = 'String is not valid hexadecimal pattern.' }
        @{ Root = $folder; Mask = '*.txt'; Content = '('; Mode = 'Regex'; Title = 'Error Finding File'; Text = '' }
    )) {
        Set-LegacyFindQuery -SearchRoot $case.Root -Mask $case.Mask -Content $case.Content -Mode $case.Mode
        [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, $ownerPid, 2288, $true)
        Assert-LegacyFindNotice -Owner $legacyWindow -Title $case.Title -ExpectedText $case.Text
    }
    Set-LegacyFindQuery -SearchRoot $folder -Mask '*.txt' -Content 'token-[0-9]+' -Mode Regex
    Invoke-LegacyFindQuery -Expected 1 -Description 'Corrected regex works after validation failure'
}

function Initialize-LegacyFindBaseline {
    # The parent already owns this GUID-scoped key and deletes it on exit.
    if ($testConfigurationKey -cnotmatch '^Software\\Open Salamander\\CodexTests\\[0-9a-f]{32}$') {
        throw 'Refusing to seed Find settings outside the isolated profile.'
    }
    foreach ($case in @(@{ Path = 'ignore-active'; Enabled = 1 }, @{ Path = 'ignore-inactive'; Enabled = 0 })) {
        $itemNumber = if ($case.Enabled) { 1 } else { 2 }
        $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey(
            "$testConfigurationKey\Config0\Configuration\Find Ignore\$itemNumber")
        try {
            $key.SetValue('Path', $case.Path, [Microsoft.Win32.RegistryValueKind]::String)
            $key.SetValue('Enabled', $case.Enabled, [Microsoft.Win32.RegistryValueKind]::DWord)
        } finally { $key.Dispose() }
    }
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey(
        "$testConfigurationKey\Config0\Configuration\Find Options\1")
    try {
        $key.SetValue('ItemName', 'Legacy absolute range', [Microsoft.Win32.RegistryValueKind]::String)
        $key.SetValue('LookIn', (Join-Path $root 'find\calendar'), [Microsoft.Win32.RegistryValueKind]::String)
        $key.SetValue('Named', 'calendar-*.txt', [Microsoft.Win32.RegistryValueKind]::String)
        $key.SetValue('Grep', 'calendar', [Microsoft.Win32.RegistryValueKind]::String)
        $key.SetValue('TimeMode', 2, [Microsoft.Win32.RegistryValueKind]::DWord)
        foreach ($bound in @(@{ Prefix = 'From'; Hour = 11 }, @{ Prefix = 'To'; Hour = 13 })) {
            $value = [DateTime]::new(2023, 10, 10, $bound.Hour, 0, 0, [DateTimeKind]::Utc).ToFileTimeUtc()
            $bytes = [BitConverter]::GetBytes($value)
            foreach ($part in @(@{ Suffix = 'Lo'; Offset = 0 }, @{ Suffix = 'Hi'; Offset = 4 })) {
                $key.SetValue($bound.Prefix + $part.Suffix, [BitConverter]::ToInt32($bytes, $part.Offset),
                    [Microsoft.Win32.RegistryValueKind]::DWord)
            }
            foreach ($unit in @('Date','Time')) {
                $key.SetValue("Use$($bound.Prefix)$unit", 1, [Microsoft.Win32.RegistryValueKind]::DWord)
            }
        }
    } finally { $key.Dispose() }
}

function Test-LegacyFindSavedOptionsAndIgnore {
    param([string]$Fixture)

    $ownerPid = [uint32]$process.Id
    $calendar = [IO.Directory]::CreateDirectory((Join-Path $Fixture 'calendar')).FullName
    foreach ($case in @(
        @{ Day = 9; Hour = 12 }, @{ Day = 10; Hour = 10 }, @{ Day = 10; Hour = 11 },
        @{ Day = 10; Hour = 12 }, @{ Day = 10; Hour = 13 }, @{ Day = 10; Hour = 14 }, @{ Day = 11; Hour = 12 }
    )) {
        $file = Join-Path $calendar "calendar-$($case.Day)-$($case.Hour).txt"
        [IO.File]::WriteAllText($file, 'calendar')
        [IO.File]::SetLastWriteTimeUtc($file, [SalamanderGuiNative]::LegacyFindFixtureUtc(
            [DateTime]::new(2023, 10, $case.Day, $case.Hour, 0, 0)))
    }
    [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, $ownerPid, 2250, $false)
    Assert-True ([SalamanderGuiNative]::ReadFindText($legacyWindow, $ownerPid, 2505) -ceq 'calendar-*.txt') (
        'Saved option restores the name mask')
    Assert-True ([SalamanderGuiNative]::ReadFindText($legacyWindow, $ownerPid, 2501) -ceq $calendar) (
        'Saved option restores the search root')
    Assert-True ([SalamanderGuiNative]::ReadFindText($legacyWindow, $ownerPid, 2504) -ceq 'calendar') (
        'Saved option restores the content expression')
    Invoke-LegacyFindQuery -Expected 3 -Description 'Saved Modified From/To dates and times include both boundaries'
    Edit-LegacyFindAdvanced -Configure {
        param($dialog, $testPid)
        foreach ($picker in 2581..2584) {
            Assert-True ([SalamanderGuiNative]::OwnedControlEnabled($dialog, $testPid, $picker)) (
                "Saved absolute range enables date/time control $picker")
        }
    }
    Invoke-LegacyFindQuery -Expected 3 -Description 'Advanced date/time controls round-trip saved interval'
    Edit-LegacyFindAdvanced -Configure {
        param($dialog, $testPid)
        [SalamanderGuiNative]::ClickFindButton($dialog, $testPid, 2585)
    }

    $ignoreRoot = [IO.Directory]::CreateDirectory((Join-Path $Fixture 'ignore')).FullName
    foreach ($directory in @('visible','ignore-active','ignore-inactive')) {
        $path = [IO.Directory]::CreateDirectory((Join-Path $ignoreRoot $directory)).FullName
        [IO.File]::WriteAllText((Join-Path $path "$directory.txt"), 'ignore')
    }
    Set-LegacyFindQuery -SearchRoot $ignoreRoot -Mask '*.txt' -Recursive $true
    Invoke-LegacyFindQuery -Expected 2 -Description 'Only the enabled Ignore Directory List entry excludes a subtree'
    $results = @(Read-LegacyFindResult -Index 0; Read-LegacyFindResult -Index 1)
    Assert-True ($results -ccontains (Join-Path $ignoreRoot 'visible\visible.txt') -and
        $results -ccontains (Join-Path $ignoreRoot 'ignore-inactive\ignore-inactive.txt')) (
        'Result clipboard proves the enabled ignore rule did not substitute an equal-count result')

    [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, $ownerPid, 2293, $true)
    $ignoreDialog = @{ Handle = [IntPtr]::Zero }
    Wait-Until {
        $ignoreDialog.Handle = [SalamanderGuiNative]::FindLegacyModal($legacyWindow, $ownerPid, 'Ignore Directory List')
        return $ignoreDialog.Handle -ne [IntPtr]::Zero
    } 'owned Ignore Directory List opens'
    [SalamanderGuiNative]::ToggleFirstLegacyFindIgnoreItem($ignoreDialog.Handle, $ownerPid)
    [SalamanderGuiNative]::PostFindButton($ignoreDialog.Handle, $ownerPid, 1)
    Wait-Until { -not [SalamanderGuiNative]::IsWindowVisible($ignoreDialog.Handle) } 'edited ignore rule is accepted'
    Invoke-LegacyFindQuery -Expected 3 -Description 'Disabling the active ignore rule restores the excluded subtree'

    [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, $ownerPid, 2247, $false)
    Set-LegacyFindQuery -SearchRoot $calendar -Mask 'changed'
    [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, $ownerPid, 2251, $false)
    Assert-True ([SalamanderGuiNative]::ReadFindText($legacyWindow, $ownerPid, 2501) -ceq $ignoreRoot) (
        'Add Current persists the active root in the in-session saved option')
    Invoke-LegacyFindQuery -Expected 3 -Description 'Reloaded in-session option preserves the mask and recursion'

    [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, $ownerPid, 2248, $true)
    $manager = @{ Handle = [IntPtr]::Zero }
    Wait-Until {
        $manager.Handle = [SalamanderGuiNative]::FindLegacyModal($legacyWindow, $ownerPid, 'Settings Manager')
        return $manager.Handle -ne [IntPtr]::Zero
    } 'owned Settings Manager'
    Assert-True ([SalamanderGuiNative]::ReadFindText($manager.Handle, $ownerPid, 2545) -ceq 'calendar-*.txt') (
        'Settings Manager previews the stored name mask')
    [SalamanderGuiNative]::SetLegacyFindCheck($manager.Handle, $ownerPid, 2549, 1)
    [SalamanderGuiNative]::PostFindButton($manager.Handle, $ownerPid, 1)
    Wait-Until { -not [SalamanderGuiNative]::IsWindowVisible($manager.Handle) } 'Settings Manager saved automatic loading'
    [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, $ownerPid, 2, $true)
    Wait-Until { [SalamanderGuiNative]::FindLegacySearchWindow($ownerPid) -eq [IntPtr]::Zero } (
        'closing the original dialog before reopening it')
    $legacyWindow = Open-TestLegacyFind
    Assert-True ([SalamanderGuiNative]::ReadFindText($legacyWindow, $ownerPid, 2505) -ceq 'calendar-*.txt') (
        'Automatic settings load restores the selected saved option when Find reopens')
    Invoke-LegacyFindQuery -Expected 3 -Description 'Reopened Find applies the saved date/time and content filters'
}

function Test-LegacyFindEditedDateTime {
    param([string]$Fixture)

    # Arrange: two inclusive endpoints, an interior match and two false positives.
    foreach ($hour in @(10,11,12,13,14)) {
        $file = Join-Path $Fixture "calendar-$hour.txt"
        [IO.File]::WriteAllText($file, 'calendar')
        [IO.File]::SetLastWriteTimeUtc($file, [SalamanderGuiNative]::LegacyFindFixtureUtc(
            [DateTime]::new(2023,10,10,$hour,0,0)))
    }
    Set-LegacyFindQuery -SearchRoot $Fixture -Mask 'calendar-*.txt'

    # Act: enter both date and time limits in the original Advanced controls.
    Edit-LegacyFindAdvanced -Configure {
        param($dialog, $ownerPid)
        [SalamanderGuiNative]::SetLegacyFindCheck($dialog, $ownerPid, 2575, 0)
        [SalamanderGuiNative]::SetLegacyFindCheck($dialog, $ownerPid, 2577, 1)
        $from = [DateTime]::new(2023,10,10,11,0,0)
        $to = $from.AddHours(2)
        [SalamanderGuiNative]::SetLegacyFindDateTime($dialog, $process, 2581, $from)
        [SalamanderGuiNative]::SetLegacyFindDateTime($dialog, $process, 2582, $from)
        [SalamanderGuiNative]::SetLegacyFindDateTime($dialog, $process, 2583, $to)
        [SalamanderGuiNative]::SetLegacyFindDateTime($dialog, $process, 2584, $to)
    }

    # Assert: the actual selected-file identities match the interval.
    Invoke-LegacyFindQuery -Expected 3 -Description 'Edited absolute date/time limits include both endpoints'
    [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, [uint32]$process.Id, 2237, $false)
    $names = foreach ($row in 0..2) { Read-LegacyFindResult -Index $row -CopyCommand 2284 }
    Assert-True (($names -join '|') -ceq 'calendar-11.txt|calendar-12.txt|calendar-13.txt') (
        "Edited timestamps select the three exact documents inside the interval. Actual: $($names -join ', ')")
}

function Test-LegacyFindCompressedAttribute {
    param([string]$Fixture)

    $plain = Join-Path $Fixture 'plain.bin'
    $compressed = Join-Path $Fixture 'compressed.bin'
    [IO.File]::WriteAllBytes($plain, [byte[]]::new(4096))
    [IO.File]::WriteAllBytes($compressed, [byte[]]::new(4096))
    $stream = [IO.File]::Open($compressed, 'Open', 'ReadWrite', 'None')
    try { [SalamanderGuiNative]::CompressLegacyFindFixture($stream) }
    finally { $stream.Dispose() }
    Assert-True (([IO.File]::GetAttributes($compressed) -band [IO.FileAttributes]::Compressed) -ne 0) (
        'NTFS fixture reports the compressed attribute')
    Assert-True (([IO.File]::GetAttributes($plain) -band [IO.FileAttributes]::Compressed) -eq 0) (
        'Control fixture reports no compressed attribute')
    Set-LegacyFindQuery -SearchRoot $Fixture -Mask '*.bin'
    foreach ($case in @(@{ State = 1; File = $compressed }, @{ State = 0; File = $plain })) {
        Edit-LegacyFindAdvanced -Configure {
            param($dialog, $ownerPid)
            [SalamanderGuiNative]::SetLegacyFindCheck($dialog, $ownerPid, 2565, $case.State)
        }
        Invoke-LegacyFindQuery -Expected 1 -Description "Compressed attribute state $($case.State) selects one file"
        Assert-True ((Read-LegacyFindResult -Index 0) -ceq $case.File) 'Compression filter selects the expected file'
    }
}

function Test-LegacyFindEncryptedAttribute {
    param([string]$ExistingFixture)

    # Read an explicitly supplied disposable EFS fixture. Creating the first
    # encrypted file can provision keys in the active Windows user profile.
    if (-not [IO.Path]::IsPathFullyQualified($ExistingFixture)) {
        throw 'EFS test fixture must be an absolute path.'
    }
    $testRoot = 'C:\Test'
    $fullPath = [IO.Path]::GetFullPath($ExistingFixture)
    if (-not $fullPath.StartsWith($testRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
        $fullPath.Length -ge 260) {
        throw 'EFS test fixture must be a short disposable path below C:\Test.'
    }
    for ($component = $fullPath; $component.Length -ge $testRoot.Length; $component = Split-Path -Parent $component) {
        $item = Get-Item -LiteralPath $component -Force
        if ($item.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) {
            throw 'EFS test fixture must not traverse a reparse point.'
        }
    }
    $file = Get-Item -LiteralPath $fullPath -Force
    if ($file -isnot [IO.FileInfo] -or $file.Name -cnotmatch '^[a-zA-Z0-9_-]+\.txt$' -or
        -not $file.Attributes.HasFlag([IO.FileAttributes]::Encrypted)) {
        throw 'EFS test fixture must be an existing encrypted .txt file with a simple ASCII name.'
    }

    Set-LegacyFindQuery -SearchRoot ($file.DirectoryName.Replace(';',';;')) -Mask $file.Name
    foreach ($case in @(@{ State = 1; Count = 1 }, @{ State = 0; Count = 0 })) {
        Edit-LegacyFindAdvanced -Configure {
            param($dialog, $ownerPid)
            [SalamanderGuiNative]::SetLegacyFindCheck($dialog, $ownerPid, 2586, $case.State)
        }
        Invoke-LegacyFindQuery -Expected $case.Count -Description "Encrypted attribute state $($case.State) matches the EFS fixture"
        if ($case.Count -eq 1) {
            Assert-True ((Read-LegacyFindResult -Index 0) -ceq $file.FullName) 'EFS filter returns exactly the supplied path'
        }
    }
}

function Test-LegacyFindShellClipboard {
    param([string]$Fixture)

    $first = Join-Path $Fixture 'first.txt'
    $second = Join-Path $Fixture 'second.txt'
    [IO.File]::WriteAllText($first, 'first result')
    [IO.File]::WriteAllText($second, 'second result')
    Set-LegacyFindQuery -SearchRoot $Fixture -Mask '*.txt'
    Invoke-LegacyFindQuery -Expected 2 -Description 'Shell clipboard search fixture'

    $ownerPid = [uint32]$process.Id
    [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, $ownerPid, 2231, $false)
    Assert-True ([SalamanderGuiNative]::LegacyFindSelectionCount($legacyWindow, $ownerPid) -eq 2) (
        'Shell clipboard action has both disposable results selected')
    foreach ($case in @(
        @{ Command = 2230; Label = 'Copy'; Effect = 5 }
        @{ Command = 2229; Label = 'Cut'; Effect = 2 }
    )) {
        Set-ClipboardText 'No Find file-drop selection yet'
        $sequence = [SalamanderGuiNative]::GetClipboardSequenceNumber()
        [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, $ownerPid, $case.Command, $false)
        $published = @{ Paths = @(); Effect = -1 }
        Wait-Until {
            if ([SalamanderGuiNative]::GetClipboardSequenceNumber() -eq $sequence) { return $false }
            try {
                $data = [Windows.Forms.Clipboard]::GetDataObject()
                if ($null -eq $data) { return $false }
                $published.Paths = @($data.GetData([Windows.Forms.DataFormats]::FileDrop, $false))
                $effectData = $data.GetData('Preferred DropEffect', $false)
                if ($effectData -is [IO.MemoryStream] -and $effectData.Length -ge 4) {
                    $published.Effect = [BitConverter]::ToInt32($effectData.ToArray(), 0)
                }
                return $published.Paths.Count -eq 2 -and $published.Effect -ge 0
            }
            catch [Runtime.InteropServices.ExternalException] { return $false }
        } "$($case.Label) publishes a file-drop list and preferred drop effect"
        Assert-True ($published.Paths -ccontains $first -and $published.Paths -ccontains $second) (
            "$($case.Label) publishes both exact selected paths")
        Assert-True ($published.Effect -eq $case.Effect) (
            "$($case.Label) publishes its expected Shell drop effect")
        Assert-True ([IO.File]::ReadAllText($first) -ceq 'first result' -and
            [IO.File]::ReadAllText($second) -ceq 'second result') "$($case.Label) preserves both sources before paste"
    }
}

function Test-LegacyFindFocus {
    param([string]$Fixture, [string]$Scenario)

    $directory = $Fixture
    if ($Scenario -eq 'FocusLong') {
        foreach ($step in 1..3) {
            $directory = [IO.Directory]::CreateDirectory((Join-Path $directory ("$step-" + ('x' * 78)))).FullName
        }
        Assert-True ($directory.Length -gt 260) 'Focus target directory exceeds MAX_PATH'
    }
    $name = if ($Scenario -eq 'FocusStale') { 'gone.txt' } else { 'focus-東京-😀.txt' }
    $decoy = Join-Path $directory 'focus-大阪-😺.txt'
    $target = Join-Path $directory $name
    [IO.File]::WriteAllText($decoy, 'decoy')
    [IO.File]::WriteAllText($target, 'target')
    Set-LegacyFindQuery -SearchRoot $directory -Mask $name
    Invoke-LegacyFindQuery -Expected 1 -Description 'Focus search identifies the intended result'
    Assert-True ([string]::Equals((Read-LegacyFindResult -Index 0), $target, [StringComparison]::Ordinal)) (
        'The selected Find row is the exact target')

    $ownerPid = [uint32]$process.Id
    if ($Scenario -eq 'FocusStale') {
        $originalPanel = Read-PanelPath
        [IO.File]::Delete($target)
        [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, $ownerPid, 2225, $true)
        Assert-LegacyFindNotice -Owner $legacyWindow -Title 'Error' -ExpectedText "Some selected file or directory is not available.`nPress the Find Now button to refresh list of found items."
        Assert-True ([string]::Equals((Read-PanelPath), $originalPanel, [StringComparison]::Ordinal)) (
            'A stale result leaves the active panel where it was')
    } else {
        [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, $ownerPid, 2225, $true)
        Wait-Until {
            if ([SalamanderGuiNative]::FindLegacyModal($legacyWindow, $ownerPid, 'Error') -ne [IntPtr]::Zero) {
                throw 'Focus File rejected an existing exact Unicode result.'
            }
            return [string]::Equals((Read-PanelPath), $directory, [StringComparison]::OrdinalIgnoreCase)
        } 'Focus File navigates the panel to the exact result directory'
        Assert-True ([string]::Equals((Read-FocusedFullname -AllowVerifiedBackground), $target,
            [StringComparison]::Ordinal)) 'Focus File selects the W-backed row instead of its ACP lookalike'
    }
    Assert-True ([IO.File]::ReadAllText($decoy) -ceq 'decoy') 'The similarly spelled decoy retains its original bytes'
}

function Assert-LegacyViewerContents {
    param([IntPtr]$Viewer, [uint32]$OwnerPid, [string]$Path, [string]$Expected)

    $sentinel = 'Viewer has not copied any bytes'
    Set-ClipboardText $sentinel
    $sequence = [SalamanderGuiNative]::GetClipboardSequenceNumber()
    [SalamanderGuiNative]::LegacyResultViewerCommand($Viewer, $OwnerPid, $Path, 6066)
    [SalamanderGuiNative]::LegacyResultViewerCommand($Viewer, $OwnerPid, $Path, 6062)

    # Wait-Until invokes the predicate in another PowerShell scope.
    # Mutate one reference object so diagnostics survive that scope.
    $observed = @{ Sequence = $sequence; Kind = 'not-read'; Utf16Length = -1 }
    try {
        Wait-Until {
            $observed.Sequence = [SalamanderGuiNative]::GetClipboardSequenceNumber()
            if ($observed.Sequence -eq $sequence) { return $false }
            $actual = Get-ClipboardText
            $observed.Utf16Length = $actual.Length
            if ($actual -ceq $Expected) {
                $observed.Kind = 'expected'
                return $true
            }
            $observed.Kind = if ($actual -ceq $sentinel) { 'sentinel' }
                             elseif ($actual.Length -eq 0) { 'empty' }
                             else { 'different' }
            return $false
        } 'Viewer copied the exact bytes from the named result'
    }
    catch {
        if ($_.Exception.Message -cne 'Timeout waiting for Viewer copied the exact bytes from the named result') {
            throw
        }
        # Window ownership is verified again only for diagnostics. Never
        # replay Copy/Select All or expose the clipboard text in the log.
        $viewerStillMatches = 'unknown'
        try {
            $matched = [SalamanderGuiNative]::FindLegacyResultViewer($OwnerPid, $Path)
            $viewerStillMatches = [string]($matched -eq $Viewer)
        }
        catch {
            $viewerStillMatches = 'lookup-failed'
        }
        $clipboardChanged = $observed.Sequence -ne $sequence
        $foreground = Get-ForegroundWindowSummary
        $diagnostic = [string]::Format(
            'Viewer Copy timed out: ClipboardSequenceChanged={0}; ClipboardTextKind={1}; ObservedUtf16Length={2}; ExpectedUtf16Length={3}; ViewerStillMatches={4}; Foreground={5}.',
            $clipboardChanged, $observed.Kind, $observed.Utf16Length,
            $Expected.Length, $viewerStillMatches, $foreground)
        throw $diagnostic
    }
    Write-Host 'PASS: Viewer copied the exact bytes from the named result'
}

function Test-LegacyFindWideViewer {
    param([string]$Fixture, [string]$Scenario)

    $directory = $Fixture
    if ($Scenario -eq 'ViewLong') {
        foreach ($step in 1..3) {
            $directory = [IO.Directory]::CreateDirectory((Join-Path $directory ("$step-" + ('x' * 78)))).FullName
        }
        $directory = [IO.Directory]::CreateDirectory((Join-Path $directory 'viewer-東京-😀')).FullName
        Assert-True ($directory.Length -gt 260) 'Unicode viewer target directory exceeds MAX_PATH'
    }
    $firstName = if ($Scenario -eq 'ViewMixed') { 'focus-a.txt' } else { 'focus-東京-😀.txt' }
    $first = Join-Path $directory $firstName
    $second = Join-Path $directory 'focus-大阪-😺.txt'
    [IO.File]::WriteAllText($first, 'first Unicode result')
    [IO.File]::WriteAllText($second, 'second Unicode result')
    Set-LegacyFindQuery -SearchRoot $directory -Mask 'focus-*.txt'
    Invoke-LegacyFindQuery -Expected 2 -Description 'Viewer search finds both exact Unicode results'

    $ownerPid = [uint32]$process.Id
    [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, $ownerPid, 2237, $false)
    $shown = Read-LegacyFindResult -Index 0
    if ($Scenario -eq 'ViewMixed') {
        Assert-True ([string]::Equals($shown, $first, [StringComparison]::Ordinal)) (
            'The mixed result list starts with the short ACP file')
    }
    $other = if ([string]::Equals($shown, $first, [StringComparison]::Ordinal)) { $second } else { $first }
    Assert-True ([string]::Equals((Read-LegacyFindResult -Index 1), $other, [StringComparison]::Ordinal)) (
        'The two rows keep their distinct UTF-16 names')
    [SalamanderGuiNative]::SelectLegacyFindRow($legacyWindow, $ownerPid, 0)
    if ($Scenario -eq 'ViewStale') {
        [IO.File]::Delete($shown)
        [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, $ownerPid, 2221, $true)
        Assert-LegacyFindNotice -Owner $legacyWindow -Title 'Error' -ExpectedText "Some selected file or directory is not available.`nPress the Find Now button to refresh list of found items."
        Assert-True ([IO.File]::Exists($other)) 'A stale View result leaves the other file intact'
        return
    }

    [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, $ownerPid, 2221, $true)
    $observed = @{ Viewer = [IntPtr]::Zero }
    Wait-Until {
        if ($process.HasExited) {
            throw ('Salamander exited while opening Unicode View (0x{0:X8}).' -f $process.ExitCode)
        }
        if ([SalamanderGuiNative]::FindLegacyModal($legacyWindow, $ownerPid, 'Error') -ne [IntPtr]::Zero) {
            throw 'View rejected an existing exact Unicode result.'
        }
        $observed.Viewer = [SalamanderGuiNative]::FindLegacyResultViewer($ownerPid, $shown)
        return $observed.Viewer -ne [IntPtr]::Zero
    } 'View opens the selected Unicode result in the internal viewer'
    Assert-LegacyViewerContents $observed.Viewer $ownerPid $shown ([IO.File]::ReadAllText($shown))
    [SalamanderGuiNative]::LegacyResultViewerCommand($observed.Viewer, $ownerPid, $shown, 6086)
    Wait-Until { [SalamanderGuiNative]::FindLegacyResultViewer($ownerPid, $other) -eq $observed.Viewer } (
        'Next File opens the distinct Unicode result in the same viewer')
    Assert-LegacyViewerContents $observed.Viewer $ownerPid $other ([IO.File]::ReadAllText($other))
    [SalamanderGuiNative]::LegacyResultViewerCommand($observed.Viewer, $ownerPid, $other, 6085)
    Wait-Until { [SalamanderGuiNative]::FindLegacyResultViewer($ownerPid, $shown) -eq $observed.Viewer } (
        'Previous File returns to the exact Unicode result')
    [SalamanderGuiNative]::LegacyResultViewerCommand($observed.Viewer, $ownerPid, $shown, 0)
    Wait-Until { -not [SalamanderGuiNative]::IsWindowVisible($observed.Viewer) } 'the test-owned Unicode viewer closed'
    Write-Host 'PASS: Next and Previous preserve the exact Find result order'
}

function Test-LegacyFindViewer {
    param([string]$Fixture)

    $first = Join-Path $Fixture 'first.txt'
    $second = Join-Path $Fixture 'second.txt'
    [IO.File]::WriteAllText($first, 'first result')
    [IO.File]::WriteAllText($second, 'second result')
    Set-LegacyFindQuery -SearchRoot $Fixture -Mask '*.txt'
    Invoke-LegacyFindQuery -Expected 2 -Description 'Viewer search fixture'
    $ownerPid = [uint32]$process.Id
    [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, $ownerPid, 2237, $false)
    Assert-True ((Read-LegacyFindResult -Index 0) -ceq $first) 'Viewer action targets the first exact Find row'

    [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, $ownerPid, 2221, $true)
    $observed = @{ Viewer = [IntPtr]::Zero }
    Wait-Until {
        $observed.Viewer = [SalamanderGuiNative]::FindLegacyResultViewer($ownerPid, $first)
        return $observed.Viewer -ne [IntPtr]::Zero
    } 'Find opens the exact first result in the internal viewer'
    $viewer = $observed.Viewer

    [SalamanderGuiNative]::LegacyResultViewerCommand($viewer, $ownerPid, $first, 6086)
    Wait-Until {
        [SalamanderGuiNative]::FindLegacyResultViewer($ownerPid, $second) -eq $viewer
    } 'Next File uses the result list as the viewing order'
    [SalamanderGuiNative]::LegacyResultViewerCommand($viewer, $ownerPid, $second, 6085)
    Wait-Until {
        [SalamanderGuiNative]::FindLegacyResultViewer($ownerPid, $first) -eq $viewer
    } 'Previous File returns to the first Find result'
    [SalamanderGuiNative]::LegacyResultViewerCommand($viewer, $ownerPid, $first, 0)
    Wait-Until { -not [SalamanderGuiNative]::IsWindowVisible($viewer) } 'the test-owned viewer closed'
    Assert-True ([IO.File]::ReadAllText($first) -ceq 'first result' -and
        [IO.File]::ReadAllText($second) -ceq 'second result') 'Viewer navigation preserves both fixture files'
}

function Test-LegacyFindShellProperties {
    param([string]$Fixture)

    $name = 'fixture-' + [guid]::NewGuid().ToString('N') + '.txt'
    $target = Join-Path $Fixture $name
    [IO.File]::WriteAllText($target, 'properties fixture')
    Set-LegacyFindQuery -SearchRoot $Fixture -Mask $name
    Invoke-LegacyFindQuery -Expected 1 -Description 'Shell properties search fixture'
    $ownerPid = [uint32]$process.Id
    [SalamanderGuiNative]::SelectLegacyFindRow($legacyWindow, $ownerPid, 0)
    [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, $ownerPid, 2249, $true)

    $observed = @{ Window = [IntPtr]::Zero }
    $stem = [IO.Path]::GetFileNameWithoutExtension($name)
    Wait-Until {
        $observed.Window = [SalamanderGuiNative]::FindLegacyShellProperties($ownerPid, $stem)
        return $observed.Window -ne [IntPtr]::Zero
    } 'Shell properties opens the exact selected fixture in a test-owned window'
    [SalamanderGuiNative]::CloseLegacyShellProperties($observed.Window, $ownerPid, $stem)
    Wait-Until { -not [SalamanderGuiNative]::IsWindowVisible($observed.Window) } 'the verified properties window closed'
    Assert-True ([IO.File]::ReadAllText($target) -ceq 'properties fixture') 'Properties preserves the exact fixture'
}

function Test-LegacyFindShellOpen {
    param([string]$Fixture)

    $probe = Join-Path $Fixture 'shell-open-probe.ps1'
    $marker = Join-Path $Fixture 'selected.opened'
    @'
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'selected.opened'), 'opened by the shell')
'@ | Set-Content -LiteralPath $probe -Encoding utf8
    $launcher = New-Object -ComObject WScript.Shell
    $shortcut = $launcher.CreateShortcut((Join-Path $Fixture 'open fixture.lnk'))
    $shortcut.TargetPath = Join-Path $PSHOME 'pwsh.exe'
    $shortcut.Arguments = '-NoProfile -NonInteractive -File "{0}"' -f $probe
    $shortcut.WorkingDirectory = $Fixture
    $shortcut.WindowStyle = 7 # Minimized, without activating another window.
    $shortcut.Save()
    Set-LegacyFindQuery -SearchRoot $Fixture -Mask 'open fixture.lnk'
    Invoke-LegacyFindQuery -Expected 1 -Description 'Shell Open shortcut fixture'

    $ownerPid = [uint32]$process.Id
    [SalamanderGuiNative]::SelectLegacyFindRow($legacyWindow, $ownerPid, 0)
    [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, $ownerPid, 2228, $true)
    Wait-Until {
        try { return [IO.File]::ReadAllText($marker) -ceq 'opened by the shell' }
        catch [IO.IOException] { return $false }
    } 'Find Shell Open launched the selected shortcut'
    Assert-True ([IO.File]::Exists($marker)) 'Only the fixture shortcut can write the test marker'
}

function Initialize-LegacyFindExternalEditor {
    # Preserve the original external-editor regression using the PowerShell
    # executable chosen by the current test host. Record whether it was
    # launched, without changing the configured editor or its file argument.
    $probe = Join-Path $root 'editor-probe.ps1'
    @'
param([string]$Target)
$state = Join-Path $PSScriptRoot 'editor-probe-pwsh.status'
[IO.File]::WriteAllText($state, 'STARTED')
$expected = Join-Path $PSScriptRoot 'find\editor fixture.salfindtest'
if ($Target -cne $expected) {
    [IO.File]::WriteAllText($state, 'WRONG_ARGUMENT')
    exit 1
}
if ([IO.File]::ReadAllText($expected) -cne 'original text') {
    [IO.File]::WriteAllText($state, 'ORIGINAL_CONTENT_CHANGED')
    exit 1
}
[IO.File]::WriteAllText($expected, 'saved by the external editor')
[IO.File]::WriteAllText($state, 'SAVED')
'@ | Set-Content -LiteralPath $probe -Encoding utf8

    $editorKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($testConfigurationKey + '\Config0\Editors\1')
    try {
        $editorKey.SetValue('Masks', '*.salfindtest')
        $editorKey.SetValue('Command', (Join-Path $PSHOME 'pwsh.exe'))
        # -File receives the exact absolute, quoted test-owned script path.
        # Do not bypass the user's PowerShell execution policy merely to
        # make a regression pass; report an actual policy failure instead.
        $editorKey.SetValue('Arguments',
            ('-NoProfile -NonInteractive -File "{0}" "$(FullName)"' -f $probe))
        $editorKey.SetValue('Initial Directory', $root)
    }
    finally { $editorKey.Dispose() }
}

function Initialize-LegacyFindExternalEditorNative {
    # Compare with a built-in Windows editor stand-in. This test keeps the
    # same registry configuration, exact Find selection and $(FullName)
    # expansion, while removing packaged PowerShell from the child process.
    $probe = Join-Path $root 'editor-probe-native.cmd'
    $before = Join-Path $root 'editor-native-before.bin'
    $after = Join-Path $root 'editor-native-after.bin'
    [IO.File]::WriteAllText($before, 'original text')
    [IO.File]::WriteAllText($after, 'saved by the external editor')
    $batch = @'
@echo off
setlocal DisableDelayedExpansion
>"%~dp0editor-probe-native.status" echo STARTED
if not "%~1"=="%~dp0find\editor fixture.salfindtest" (
    >"%~dp0editor-probe-native.status" echo WRONG_ARGUMENT
    exit /b 2
)
fc /b "%~1" "%~dp0editor-native-before.bin" >nul
if errorlevel 1 (
    >"%~dp0editor-probe-native.status" echo ORIGINAL_CONTENT_CHANGED
    exit /b 3
)
copy /y /b "%~dp0editor-native-after.bin" "%~1" >nul
if errorlevel 1 (
    >"%~dp0editor-probe-native.status" echo COPY_FAILED
    exit /b 4
)
>"%~dp0editor-probe-native.status" echo SAVED
'@
    [IO.File]::WriteAllText(
        $probe, (($batch -split '\r?\n') -join [Environment]::NewLine), [Text.Encoding]::ASCII)

    $editorExecutable = Join-Path $env:SystemRoot 'System32\cmd.exe'
    if (-not [IO.File]::Exists($editorExecutable)) {
        throw 'The built-in Windows command processor is unavailable for the editor test.'
    }
    $editorKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($testConfigurationKey + '\Config0\Editors\1')
    try {
        $editorKey.SetValue('Masks', '*.salfindtest')
        $editorKey.SetValue('Command', $editorExecutable)
        $editorKey.SetValue('Arguments', '/D /C call editor-probe-native.cmd "$(FullName)"')
        $editorKey.SetValue('Initial Directory', $root)
    }
    finally { $editorKey.Dispose() }
}

function Test-LegacyFindExternalEditor {
    param([string]$Fixture, [switch]$Native)

    # Arrange: both independent cases demand exact source identity and bytes.
    $target = Join-Path $Fixture 'editor fixture.salfindtest'
    $neighbor = Join-Path $Fixture 'neighbor.txt'
    $stateName = if ($Native) { 'editor-probe-native.status' }
                 else { 'editor-probe-pwsh.status' }
    $statusFile = Join-Path $root $stateName
    [IO.File]::WriteAllText($target, 'original text')
    [IO.File]::WriteAllText($neighbor, 'keep this')
    Set-LegacyFindQuery -SearchRoot $Fixture -Mask '*.salfindtest'
    Invoke-LegacyFindQuery -Expected 1 -Description 'External editor fixture'
    Assert-True ((Read-LegacyFindResult -Index 0) -ceq $target) (
        'External editor targets the exact verified Find result')

    # Act: use the real legacy Find Edit handler. No retry of this command.
    $ownerPid = [uint32]$process.Id
    [SalamanderGuiNative]::SelectLegacyFindRow($legacyWindow, $ownerPid, 0)
    [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, $ownerPid, 2223, $true)

    # Assert: require exact output and positive confirmation that the
    # configured editor received the correct argument and original bytes.
    try {
        Wait-Until {
            try {
                return [IO.File]::ReadAllText($target) -ceq 'saved by the external editor' -and
                    [IO.File]::Exists($statusFile) -and
                    [IO.File]::ReadAllText($statusFile).Trim() -ceq 'SAVED'
            }
            catch [IO.IOException] { return $false }
        } 'The configured external editor received and saved the exact fixture with spaces'
    }
    catch {
        $state = if ([IO.File]::Exists($statusFile)) {
            [IO.File]::ReadAllText($statusFile).Trim()
        } else {
            'NOT_STARTED'
        }
        throw ("Legacy Find external editor did not modify the selected fixture. " +
               "Test editor state=$state; $($_.Exception.Message)")
    }
    Assert-True ([IO.File]::ReadAllText($neighbor) -ceq 'keep this') 'External editor preserves the unselected file'
}

function Test-LegacyFindRecycleRestore {
    param([string]$Fixture)

    $target = Join-Path $Fixture ('recycle-' + [guid]::NewGuid().ToString('N') + '.txt')
    $neighbor = Join-Path $Fixture 'keep.txt'
    [IO.File]::WriteAllText($target, 'recycle fixture contents')
    [IO.File]::WriteAllText($neighbor, 'keep this')
    $shell = New-Object -ComObject Shell.Application
    $recycleFolder = $shell.NameSpace(10)
    if ($null -eq $recycleFolder) { throw 'Windows Recycle Bin shell folder is unavailable.' }
    Set-LegacyFindQuery -SearchRoot $Fixture -Mask (Split-Path -Leaf $target)
    Invoke-LegacyFindQuery -Expected 1 -Description 'Find recycle fixture'
    Assert-True ((Read-LegacyFindResult -Index 0) -ceq $target) 'Find recycle selection is the exact disposable file'

    $ownerPid = [uint32]$process.Id
    [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, $ownerPid, 2282, $true)
    $state = @{ Confirmed = $false; Item = $null }
    Wait-Until {
        if (-not $state.Confirmed) {
            $state.Confirmed = [SalamanderGuiNative]::ConfirmLegacyFindRecycle($legacyWindow, $ownerPid)
        }
        return -not [IO.File]::Exists($target)
    } 'the original Find Delete command removes the selected fixture'
    Wait-Until {
        $state.Item = Find-VerifiedRecycledFixtureItem -RecycleFolder $recycleFolder -OriginalFullPath $target
        return $null -ne $state.Item
    } 'the exact selected path appears in the Recycle Bin'
    Assert-LegacyFindCount -Expected 0 -Description 'Find removes the deleted result from the list'
    Restore-VerifiedRecycledFixtureItem -Item $state.Item -OriginalFullPath $target
    Wait-Until {
        try { return [IO.File]::ReadAllText($target) -ceq 'recycle fixture contents' }
        catch [IO.IOException] { return $false }
    } 'Recycle Bin restores the fixture with intact contents'
    Assert-True ([IO.File]::ReadAllText($neighbor) -ceq 'keep this') 'Recycle and restore preserve the unselected file'
}

function Test-LegacyFindCancellation {
    param([string]$Fixture)

    # Arrange: the isolated worker waits before enumeration, without timing
    # assumptions about how quickly the test machine can scan a directory.
    [IO.File]::WriteAllText((Join-Path $Fixture 'candidate.txt'), 'content')
    Set-LegacyFindQuery -SearchRoot $Fixture -Mask '*.txt'
    $ownerPid = [uint32]$process.Id
    [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, $ownerPid, 2288, $false)
    Wait-Until { $findTestReached.WaitOne(0) } 'original worker reached the pre-enumeration checkpoint'
    Assert-True (-not [SalamanderGuiNative]::OwnedControlEnabled($legacyWindow, $ownerPid, 2505)) (
        'Original Find is actively searching before cancellation')

    # Act: use the same command as the original Stop toolbar button.
    [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, $ownerPid, 2521, $true)
    Wait-Until { $findTestCancelled.WaitOne(0) } 'original Stop handler requested cancellation'

    # Assert: join finishes, the controls recover and the next search works.
    Assert-LegacyFindCount -Expected 0 -Description 'Stopping before enumeration publishes no results'
    Invoke-LegacyFindQuery -Expected 1 -Description 'A new search works after an active cancellation'
}

function Test-LegacyFindDistinctUnicodeResults {
    param([string]$Fixture)

    # Canonically equivalent display text and colliding ACP substitutions
    # still name distinct files. The identical contents must match all rows.
    $names = @(
        ('needle-e' + [char]0x0301 + '.txt'),
        'needle-é.txt',
        'needle-東京-😀.txt',
        'needle-大阪-😺.txt'
    )
    $expected = foreach ($name in $names) {
        $path = Join-Path $Fixture $name
        [IO.File]::WriteAllText($path, 'needle42')
        $path
    }
    Set-LegacyFindQuery -SearchRoot $Fixture -Mask 'needle-*.txt' -Content 'needle[0-9]+$' -Mode Regex
    Invoke-LegacyFindQuery -Expected $names.Count -Description 'Distinct Unicode spellings all survive original Find'
    Invoke-LegacyFindQuery -Expected ($names.Count * 2) -Description 'Append also finds every Unicode spelling' -Command 2291
    [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, [uint32]$process.Id, 2287, $false)
    Assert-LegacyFindCount -Expected $names.Count -Description 'Hide Duplicate Names removes only repeated UTF-16 identities'

    $actual = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    for ($row = 0; $row -lt $names.Count; $row++) {
        [void]$actual.Add((Read-LegacyFindResult -Index $row))
    }
    foreach ($path in $expected) {
        Assert-True ($actual.Contains($path)) 'Exact original UTF-16 result identity is present without alias substitution'
    }
}

function Test-LegacyFindUnicodeRootIgnore {
    param([string]$Fixture)

    $directory = [IO.Directory]::CreateDirectory((Join-Path $Fixture '東京-😀')).FullName
    $subdirectories = @('visible-大阪','ignore-active','ignore-inactive')
    foreach ($name in $subdirectories) {
        $child = [IO.Directory]::CreateDirectory((Join-Path $directory $name)).FullName
        [IO.File]::WriteAllText((Join-Path $child 'needle.txt'), 'needle42')
    }
    Set-LegacyFindQuery -SearchRoot $directory -Mask '*.txt' -Recursive $true
    Invoke-LegacyFindQuery -Expected 2 -Description 'A Unicode root honors enabled and disabled relative Ignore rules'
    $actual = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($row in 0..1) {
        [void]$actual.Add((Read-LegacyFindResult -Index $row))
    }
    foreach ($name in 'visible-大阪','ignore-inactive') {
        Assert-True ($actual.Contains((Join-Path $directory "$name\needle.txt"))) (
            'The Unicode root search returned the intended unignored subtree')
    }

    $explicit = Join-Path $directory 'ignore-active'
    Set-LegacyFindQuery -SearchRoot $explicit -Mask '*.txt' -Recursive $true
    Invoke-LegacyFindQuery -Expected 1 -Description 'An explicitly chosen root still overrides a matching Ignore rule'
    Assert-True ([string]::Equals((Read-LegacyFindResult -Index 0 -CopyCommand 2285), $explicit,
        [StringComparison]::Ordinal)) 'Copy Path keeps the exact Unicode directory'
}

function Test-LegacyFindUnicodeMasks {
    param([string]$Fixture)

    $expected = Join-Path $Fixture 'Ä-東京;報告-😀.txt'
    foreach ($name in @('Ä-東京;報告-😀.txt', 'Ä-東京;報告-😺.txt', 'Ä-東京;報告-😀x.txt', 'Ä-大阪.dat')) {
        [IO.File]::WriteAllText((Join-Path $Fixture $name), 'match')
    }
    Set-LegacyFindQuery -SearchRoot $Fixture -Mask ' ä-東京;;報告-?.txt ; *.dat | *😺* ; *.dat '
    Invoke-LegacyFindQuery -Expected 1 -Description 'Unicode masks preserve case folding, wildcards, literal semicolons and exclusions'
    Assert-True ((Read-LegacyFindResult -Index 0) -ceq $expected) (
        'A question mark consumes one complete supplementary character')
    $displayName = [SalamanderGuiNative]::LegacyFindDisplayedName($legacyWindow, [uint32]$process.Id, 0)
    Assert-True ([string]::Equals($displayName, [IO.Path]::GetFileName($expected),
        [StringComparison]::Ordinal)) 'The result list exposes the original Unicode name as its displayed label'
}

function Test-LegacyFindUnicodeAdvancedRefinement {
    param([string]$Fixture)

    $directory = $Fixture
    foreach ($index in 1..3) {
        $directory = [IO.Directory]::CreateDirectory((Join-Path $directory ("wide-$index-" + ('x' * 77)))).FullName
    }
    Assert-True ($directory.Length -gt 260) 'Advanced/refinement fixture crosses MAX_PATH'
    $first = Join-Path $directory 'candidate-first-東京-😀.txt'
    $second = Join-Path $directory 'candidate-second-大阪-😺.txt'
    $hidden = Join-Path $directory 'candidate-hidden-京都.txt'
    $wrongContent = Join-Path $directory 'candidate-wrong-奈良.txt'
    $wrongSize = Join-Path $directory 'candidate-short-広島.txt'
    foreach ($path in @($first,$second,$hidden,$wrongContent,$wrongSize)) {
        $data = if ($path -ceq $wrongContent) { 'token-xx'.PadLeft(32, ' ') }
                elseif ($path -ceq $wrongSize) { 'token-42' }
                else { 'token-42'.PadLeft(32, ' ') }
        [IO.File]::WriteAllText($path, $data)
        [IO.File]::SetAttributes($path, [IO.FileAttributes]::Archive)
    }
    [IO.File]::SetAttributes($hidden, [IO.FileAttributes]'Archive, Hidden')

    $query = @{ SearchRoot = $Fixture; Mask = 'candidate-*.txt'; Recursive = $true; Content = 'token-[0-9]+$'; Mode = 'Regex' }
    Set-LegacyFindQuery @query
    Edit-LegacyFindAdvanced -Configure {
        param($dialog, $ownerPid)
        [SalamanderGuiNative]::SetLegacyFindCheck($dialog, $ownerPid, 2561, 1)
        [SalamanderGuiNative]::SetLegacyFindCheck($dialog, $ownerPid, 2563, 0)
        foreach ($range in @(@(2567, 2568, 2570), @(2571, 2572, 2574))) {
            [SalamanderGuiNative]::SetLegacyFindCheck($dialog, $ownerPid, $range[0], 1)
            [SalamanderGuiNative]::SetFindText($dialog, $ownerPid, $range[1], '32')
            [SalamanderGuiNative]::SetLegacyFindComboIndex($dialog, $ownerPid, $range[2], 0)
        }
    }
    Invoke-LegacyFindQuery -Expected 2 -Description 'Regex, size and attributes compose on long Unicode results'
    $actual = @(Read-LegacyFindResult -Index 0; Read-LegacyFindResult -Index 1)
    Assert-True ($actual -ccontains $first -and $actual -ccontains $second) (
        'Combined criteria select only the exact two intended wide paths')

    $query.Mask = 'candidate-first*'
    Set-LegacyFindQuery @query
    Invoke-LegacyFindQuery -Expected 1 -Description 'Intersect retains one long Unicode identity' -Command 2289
    Assert-True ((Read-LegacyFindResult -Index 0) -ceq $first) 'Refinement retains the original wide file identity'
}

function Test-LegacyFindUnicodeSavedOptions {
    param([string]$Fixture, [switch]$StorageOnly)

    $directory = [IO.Directory]::CreateDirectory((Join-Path $Fixture '東京-😀')).FullName
    $name = 'fixture-東京-😀.txt'
    $target = Join-Path $directory $name
    [IO.File]::WriteAllText($target, 'calendar')
    $roots = if ($StorageOnly) { ($directory + '; ') * 12 + $directory } else { $directory }
    Set-LegacyFindQuery -SearchRoot $roots -Mask $name -Content 'calendar'
    $ownerPid = [uint32]$process.Id
    [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, $ownerPid, 2247, $false)
    Set-LegacyFindQuery -SearchRoot $Fixture -Mask 'unrelated.txt'
    [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, $ownerPid, 2250, $false)
    Assert-True ([SalamanderGuiNative]::ReadFindText($legacyWindow, $ownerPid, 2501) -ceq $roots) (
        'Legacy saved option restores the original UTF-16 root')
    Assert-True ([SalamanderGuiNative]::ReadFindText($legacyWindow, $ownerPid, 2505) -ceq $name) (
        'Legacy saved option restores the original UTF-16 name mask')
    if ($StorageOnly) {
        Assert-True ($roots.Length -gt 260) 'Stored root list exceeds the former MAX_PATH edit limit'
        Assert-True ([SalamanderGuiNative]::ReadLegacyFindHistory($legacyWindow, $ownerPid, 2501, 0) -ceq $roots) (
            'Root history retains the original UTF-16 text')
        [SalamanderGuiNative]::LegacyFindCommand($mainWindowHandle, $ownerPid, 687, $true)
        $presetKey = $testConfigurationKey + '\Config0\Configuration\Find Options\1'
        Wait-Until {
            $saved = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($presetKey)
            if ($null -eq $saved) { return $false }
            try { return $null -ne $saved.GetValue('Named') -and $null -ne $saved.GetValue('LookIn') }
            finally { $saved.Dispose() }
        } 'saving configuration writes the isolated Find preset'
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(
            $presetKey)
        Assert-True ($null -ne $key) 'Saving configuration writes the isolated Find preset'
        try {
            Assert-True ($key.GetValue('LookIn') -ceq $roots) 'Persisted preset retains exact UTF-16 roots'
            Assert-True ($key.GetValue('Named') -ceq $name) 'Persisted preset retains the exact UTF-16 mask'
        }
        finally { $key.Dispose() }
        [SalamanderGuiNative]::SetFindText($legacyWindow, $ownerPid, 2505, '')
        [SalamanderGuiNative]::PostLegacyFindCharacters($legacyWindow, $ownerPid, 2505, $name)
        Wait-Until {
            [SalamanderGuiNative]::ReadFindText($legacyWindow, $ownerPid, 2505) -ceq $name
        } 'Legacy Find message loop preserves Unicode character input'
        Assert-True ([SalamanderGuiNative]::ReadFindText($legacyWindow, $ownerPid, 2505) -ceq $name) (
            'Unicode character input reaches the original filename edit intact')
        return
    }
    Invoke-LegacyFindQuery -Expected 1 -Description 'Restored Unicode settings still search the correct document'
    Assert-True ((Read-LegacyFindResult -Index 0) -ceq $target) 'Saved option returns the exact Unicode file identity'
}

function New-LegacyFindNearLimitFixture {
    param([string]$SearchRoot)

    $name = 'needle-東京-😀-'
    $name += ('x' * (255 - $name.Length - 4)) + '.txt'
    $parentLength = 32700 - 1 - $name.Length
    $directory = $SearchRoot
    while ($directory.Length -lt $parentLength) {
        $remaining = $parentLength - $directory.Length
        if ($remaining -lt 2) { throw 'Cannot create the exact near-limit path.' }
        $length = if ($remaining -le 202) { $remaining - 1 } else { 200 }
        $directory = Join-Path $directory ('d' * $length)
        try { [void][IO.Directory]::CreateDirectory('\\?\' + $directory) }
        catch {
            $nativeFailure = $_.Exception.InnerException ?? $_.Exception
            throw ('Near-limit fixture setup failed at {0} UTF-16 units (Win32 {1}). No search ran.' -f
                $directory.Length, ($nativeFailure.HResult -band 0xffff))
        }
    }
    $target = Join-Path $directory $name
    Assert-True ($name.Length -eq 255 -and $target.Length -eq 32700) (
        'Near-limit fixture is a 32700-unit path with a 255-unit Unicode file name')
    try {
        [IO.File]::WriteAllText('\\?\' + $target, 'needle42')
        [IO.File]::WriteAllText('\\?\' + (Join-Path $directory 'decoy.txt'), 'needleXX')
    }
    catch {
        $nativeFailure = $_.Exception.InnerException ?? $_.Exception
        throw ('Near-limit file setup failed (Win32 {0}). No search ran.' -f ($nativeFailure.HResult -band 0xffff))
    }
    return $target
}

function Test-LegacyFindGui {
    param([string]$Scenario)

    if ($Scenario -in 'UnicodeFindCommand','UnicodeFindShortcut') {
        $ownerPid = [uint32]$process.Id
        if ($Scenario -eq 'UnicodeFindShortcut') {
            Restore-FilePanelFocus -ExpectedPath $source
            Send-Keys '%+{F7}'
        } else {
            [SalamanderGuiNative]::PostUnicodeFindCommand($mainWindowHandle, $ownerPid)
        }
        $window = @{ Unicode = [IntPtr]::Zero }
        Wait-Until {
            $window.Unicode = [SalamanderGuiNative]::FindUnicodeSearchWindow($ownerPid)
            return $window.Unicode -ne [IntPtr]::Zero
        } 'Unicode Find opens its window'
        Assert-True ([SalamanderGuiNative]::FindLegacySearchWindow($ownerPid) -eq [IntPtr]::Zero -and
            [SalamanderGuiNative]::ReadFindText($window.Unicode, $ownerPid, 5101) -ceq $source) (
            'Unicode Find opens the separate dialog with the active directory')
        return
    }
    if ($Scenario -in 'DefaultDialog','DefaultDialogShortcut','DefaultDialogLongRoot','DefaultDialogAltF7') {
        $panelPath = $source
        if ($Scenario -eq 'DefaultDialogLongRoot') {
            foreach ($index in 1..3) {
                $panelPath = [IO.Directory]::CreateDirectory(
                    (Join-Path $panelPath ("d$index-" + ('x' * 78)))).FullName
            }
            Assert-True ($panelPath.Length -gt 260) 'Shortcut fixture exceeds MAX_PATH'
            Go-ToPath -Path $panelPath -NoForeground
        }
        $shortcut = if ($Scenario -eq 'DefaultDialogAltF7') { '%{F7}' } else { '^f' }
        $legacyWindow = if ($Scenario -in 'DefaultDialog','DefaultDialogLongRoot') { Open-TestLegacyFind } else {
            Open-TestLegacyFind -ShortcutPanelPath $panelPath -Shortcut $shortcut
        }
        Assert-True ([SalamanderGuiNative]::ReadFindText(
            $legacyWindow, [uint32]$process.Id, 2501) -ceq $panelPath) (
            'Find prepopulates Look in with the complete active panel directory')
        return
    }
    $legacyWindow = Open-TestLegacyFind
    $fixture = [IO.Directory]::CreateDirectory((Join-Path $root 'find')).FullName
    if ($Scenario -eq 'EncryptedFixture') {
        Test-LegacyFindEncryptedAttribute -ExistingFixture $LegacyFindEncryptedFixture
        return
    }
    if ($Scenario -eq 'UnicodeDistinct') {
        Test-LegacyFindDistinctUnicodeResults -Fixture $fixture
        return
    }
    if ($Scenario -eq 'NearLimit') {
        Set-LegacyFindQuery -SearchRoot $fixture -Mask 'needle-*.txt' -Recursive $true -Content 'needle[0-9]+$' -Mode Regex
        Invoke-LegacyFindQuery -Expected 1 -Description 'Original Find reaches the 32700-unit Unicode result'
        Assert-True ((Read-LegacyFindResult -Index 0) -ceq $legacyNearLimitFile) (
            'Result clipboard preserves the exact 32700-unit file identity')
        return
    }
    if ($Scenario -eq 'UnicodeRootIgnore') {
        Test-LegacyFindUnicodeRootIgnore -Fixture $fixture
        return
    }
    if ($Scenario -eq 'UnicodeMasks') {
        Test-LegacyFindUnicodeMasks -Fixture $fixture
        return
    }
    if ($Scenario -eq 'UnicodeFeatures') {
        Test-LegacyFindUnicodeAdvancedRefinement -Fixture $fixture
        return
    }
    if ($Scenario -in 'UnicodeSettings','UnicodeSettingsStorage') {
        Test-LegacyFindUnicodeSavedOptions -Fixture $fixture -StorageOnly:($Scenario -eq 'UnicodeSettingsStorage')
        return
    }
    if ($Scenario -eq 'ShellClipboard') {
        Test-LegacyFindShellClipboard -Fixture $fixture
        return
    }
    if ($Scenario -eq 'ShellProperties') {
        Test-LegacyFindShellProperties -Fixture $fixture
        return
    }
    if ($Scenario -eq 'ShellOpen') {
        Test-LegacyFindShellOpen -Fixture $fixture
        return
    }
    if ($Scenario -in 'ExternalEditor','ExternalEditorNative') {
        Test-LegacyFindExternalEditor -Fixture $fixture -Native:($Scenario -eq 'ExternalEditorNative')
        return
    }
    if ($Scenario -eq 'RecycleRestore') {
        Test-LegacyFindRecycleRestore -Fixture $fixture
        return
    }
    if ($Scenario -in 'FocusUnicode','FocusLong','FocusStale') {
        Test-LegacyFindFocus -Fixture $fixture -Scenario $Scenario
        return
    }
    if ($Scenario -in 'ViewUnicode','ViewLong','ViewStale','ViewMixed') {
        Test-LegacyFindWideViewer -Fixture $fixture -Scenario $Scenario
        return
    }
    if ($Scenario -eq 'ViewResults') {
        Test-LegacyFindViewer -Fixture $fixture
        return
    }
    if ($Scenario -eq 'AdvancedInputs') {
        Test-LegacyFindEditedDateTime -Fixture $fixture
        Edit-LegacyFindAdvanced -Configure {
            param($dialog, $ownerPid)
            [SalamanderGuiNative]::ClickFindButton($dialog, $ownerPid, 2585)
        }
        Test-LegacyFindCompressedAttribute -Fixture $fixture
        return
    }
    if ($Scenario -eq 'Cancel') {
        Test-LegacyFindCancellation -Fixture $fixture
        return
    }
    if ($Scenario -eq 'Baseline') {
        Assert-True (-not [SalamanderGuiNative]::IsLegacyFindControlVisible(
            $legacyWindow, [uint32]$process.Id, 2522)) 'Reserved Search archives checkbox is hidden by the original dialog'
        Test-LegacyFindMasksAndContents -Fixture $fixture
        Test-LegacyFindContentControls -Fixture $fixture
        Test-LegacyFindAdvanced -Fixture $fixture
        Test-LegacyFindRefinement -Fixture $fixture
        Test-LegacyFindDuplicates -Fixture $fixture
        Test-LegacyFindResultActions -Fixture $fixture
        Test-LegacyFindValidation -Fixture $fixture
        Test-LegacyFindErrorLog -Fixture $fixture
        Test-LegacyFindSavedOptionsAndIgnore -Fixture $fixture
        return
    }
    if ($Scenario -eq 'LongDuplicates') {
        foreach ($index in 1..3) {
            $fixture = [IO.Directory]::CreateDirectory((Join-Path $fixture ("dup$index-" + ('d' * 78)))).FullName
        }
        Assert-True ($fixture.Length -gt 260) 'Duplicate fixtures start beyond MAX_PATH'
        Test-LegacyFindDuplicates -Fixture $fixture
        return
    }
    if ($Scenario -eq 'DirectoryLinkCycle') {
        Test-LegacyFindDirectoryLinkCycle -Fixture $fixture
        return
    }

    # Arrange each future contract independently so one failed assertion
    # cannot prevent the remaining scenarios from getting their own run.
    $searchRoot = $fixture
    $directory = $fixture
    $name = 'needle.txt'
    switch ($Scenario) {
        { $_ -in @('UnicodeName','UnicodeResult') } {
            $name = 'needle-e' + [char]0x0301 + '-東京-😀.txt'
        }
        'UnicodeRoot' {
            $directory = [IO.Directory]::CreateDirectory((Join-Path $fixture '東京-😀')).FullName
            $searchRoot = $directory
        }
        { $_ -in @('LongRoot','LongDescendant','ExtendedLongRoot') } {
            foreach ($index in 1..3) {
                $directory = [IO.Directory]::CreateDirectory((Join-Path $directory ("d$index-" + ('x' * 78)))).FullName
            }
            Assert-True ($directory.Length -gt 260) 'Test directory exceeds MAX_PATH'
            if ($Scenario -eq 'LongRoot') { $searchRoot = $directory }
            if ($Scenario -eq 'ExtendedLongRoot') { $searchRoot = '\\?\' + $directory }
        }
        'LongResult' {
            $component = 'x' * (255 - $fixture.Length - 1)
            $directory = [IO.Directory]::CreateDirectory((Join-Path $fixture $component)).FullName
            $searchRoot = $directory
            $name = 'needle-crosses-the-limit.txt'
            Assert-True ($searchRoot.Length -eq 255 -and (Join-Path $directory $name).Length -gt 260) (
                'Only the complete result path crosses MAX_PATH')
        }
    }
    [IO.File]::WriteAllText((Join-Path $directory $name), 'needle42')
    [IO.File]::WriteAllText((Join-Path $directory 'decoy.txt'), 'needleXX')

    # Act / assert: combine name and content predicates with a W-only identity.
    $mask = if ($Scenario -eq 'UnicodeResult') { 'needle-*.txt' } else { $name }
    Set-LegacyFindQuery -SearchRoot $searchRoot -Mask $mask -Recursive ($Scenario -eq 'LongDescendant') `
        -Content 'needle[0-9]+$' -Mode Regex
    if ($Scenario -eq 'LongRoot') {
        # The current validation opens a modal, so don't block the caller in
        # WM_COMMAND while waiting to observe the rejection.
        [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, [uint32]$process.Id, 2288, $true)
        Wait-Until {
            if ($process.HasExited) { throw 'Original Find exited while searching a long root.' }
            if ([SalamanderGuiNative]::FindLegacyModal($legacyWindow, [uint32]$process.Id, 'Error') -ne [IntPtr]::Zero) {
                throw 'Original Find rejected the LongRoot query before enumeration.'
            }
            return [SalamanderGuiNative]::LegacyFindResultCount($legacyWindow, [uint32]$process.Id) -gt 0
        } 'original Find returns a regex result from a long root'
        Assert-LegacyFindCount -Expected 1 -Description 'Original Find preserves the long root through regex search'
    } else {
        Invoke-LegacyFindQuery -Expected 1 -Description "Original Find preserves $Scenario through regex search"
    }
    Assert-True ((Read-LegacyFindResult -Index 0) -ceq (Join-Path $directory $name)) (
        "Result name and path preserve exact UTF-16 identity for $Scenario")
    if ($Scenario -eq 'LongDescendant') {
        Set-LegacyFindQuery -SearchRoot $searchRoot -Mask $name -Content 'needle42$' -Mode Regex
        Invoke-LegacyFindQuery -Expected 1 -Description 'Intersect can grep a long result again' -Command 2289
        Assert-True ((Read-LegacyFindResult -Index 0) -ceq (Join-Path $directory $name)) (
            'Refining a long result preserves its exact path')
    }
    if ($Scenario -eq 'LongResult') {
        [SalamanderGuiNative]::LegacyFindCommand($legacyWindow, [uint32]$process.Id, 2249, $true)
        Assert-LegacyFindNotice -Owner $legacyWindow -Title 'Error' -ExpectedText (
            'This search result cannot be identified safely by the legacy ANSI file and shell interfaces. No action was started.')
        Assert-True ([IO.File]::ReadAllText((Join-Path $directory $name)) -ceq 'needle42') (
            'Refused legacy Shell action preserves the exact long result')
    }
}
