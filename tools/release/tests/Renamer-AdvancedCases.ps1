#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
# Actual plugin host failure/clipboard tests confined to GUID-owned fixtures.

function Get-RenamerAdvancedPlan {
    $nl=[Environment]::NewLine
    $p=@{
        Old=@('a.txt','b.txt'); Proposed=@('new-a.txt','new-b.txt')
        Final=@('new-a.txt','new-b.txt'); Indices=@(0,1)
        Rule='new-$(OriginalName)'; Sort=602; Manual=$false
        Clip=''; Text=$null; Action='Rename'; Lock=@()
        Attributes=@(); Tie=$false
    }
    switch ($RenamerHostCase) {
        AdvancedValidateOnly { $p.Action='Validate'; $p.Final=$p.Old }
        AdvancedNoOp { $p.Action='NoOp'; $p.Rule='$(OriginalName)'; $p.Proposed=$p.Old; $p.Final=$p.Old }
        AdvancedManualFew { $p.Manual=$true; $p.Text='new-a.txt'; $p.Action='LineCount'; $p.Final=$p.Old }
        AdvancedManualMany { $p.Manual=$true; $p.Text=@('new-a.txt','new-b.txt','extra.txt') -join $nl; $p.Action='LineCount'; $p.Final=$p.Old }
        AdvancedManualTrailingBlank { $p.Manual=$true; $p.Text=@('new-a.txt','new-b.txt','','') -join $nl }
        AdvancedManualInteriorBlank { $p.Manual=$true; $p.Text=@('new-a.txt','','new-b.txt') -join $nl; $p.Action='LineCount'; $p.Final=$p.Old }
        AdvancedReservedName { $p.Manual=$true; $p.Proposed=@('CON.txt','new-b.txt'); $p.Action='InvalidName'; $p.Final=$p.Old }
        AdvancedInvalidCharacter { $p.Manual=$true; $p.Proposed=@('a?.txt','new-b.txt'); $p.Action='InvalidName'; $p.Final=$p.Old }
        AdvancedClipboardExportOriginal { $p.Manual=$true; $p.Clip='ExportOriginal'; $p.Proposed=$p.Old; $p.Action='PreviewOnly'; $p.Final=$p.Old }
        AdvancedClipboardExportEdited { $p.Manual=$true; $p.Clip='ExportEdited'; $p.Action='PreviewOnly'; $p.Final=$p.Old }
        AdvancedClipboardImport { $p.Manual=$true; $p.Clip='Import' }
        AdvancedClipboardRoundTrip { $p.Manual=$true; $p.Clip='RoundTrip' }
        AdvancedClipboardUndo { $p.Manual=$true; $p.Clip='Import'; $p.Action='Undo'; $p.Final=$p.Old }
        AdvancedClipboardMalformed { $p.Manual=$true; $p.Clip='Import'; $p.Text='new-a.txt'; $p.Action='LineCount'; $p.Final=$p.Old }
        AdvancedClipboardUnicode { $p.Manual=$true; $p.Clip='Import'; $p.Proposed=@('東京-😀.txt','大阪-🦎.txt'); $p.Final=$p.Proposed }
        AdvancedSortSize { $p.Sort=604; $p.Rule='$(Counter)-$(OriginalName)'; $p.Proposed=@('1-a.txt','0-b.txt'); $p.Final=$p.Proposed }
        AdvancedSortTime { $p.Sort=605; $p.Rule='$(Counter)-$(OriginalName)'; $p.Proposed=@('1-a.txt','0-b.txt'); $p.Final=$p.Proposed }
        AdvancedSortSizeTie { $p.Sort=604; $p.Tie=$true; $p.Rule='$(Counter)-$(OriginalName)'; $p.Proposed=@('0-a.txt','1-b.txt'); $p.Final=$p.Proposed }
        AdvancedReadOnly { $p.Attributes=@(0,1) }
        AdvancedLockCancel { $p.Lock=@(0,1); $p.Action='LockCancel'; $p.Final=$p.Old }
        AdvancedLockSkipAll { $p.Lock=@(0,1); $p.Action='LockSkipAll'; $p.Final=$p.Old }
        AdvancedLockOneSkip { $p.Lock=@(1); $p.Action='LockSkip'; $p.Final=@('new-a.txt','b.txt') }
        AdvancedLockRetry { $p.Lock=@(0,1); $p.Action='LockRetry' }
        AdvancedUndoLockCancel { $p.Action='UndoLockCancel'; $p.Lock=@(0,1) }
        AdvancedUndoLockRetry { $p.Action='UndoLockRetry'; $p.Lock=@(0,1); $p.Final=$p.Old }
        AdvancedUndoDecline { $p.Action='UndoDecline' }
        { $_ -in @('AdvancedOverwriteCancel','AdvancedOverwriteSuccess','AdvancedOverwriteLockedSource','AdvancedOverwriteLockedTarget','AdvancedOverwriteReadOnlyTarget') } {
            $p.Old=@('a-target.txt','z-source.txt'); $p.Indices=@(1); $p.Rule='a-target.txt'
            $p.Proposed=@('a-target.txt','a-target.txt'); $p.Action=$_
            if ($_ -in @('AdvancedOverwriteSuccess','AdvancedOverwriteReadOnlyTarget')) {
                # No assumption that Undo restores an overwritten destination.
                $p.Final=@($null,'a-target.txt')
            } else { $p.Final=$p.Old }
            if ($_ -eq 'AdvancedOverwriteLockedSource') { $p.Lock=@(1) }
            if ($_ -eq 'AdvancedOverwriteLockedTarget') { $p.Lock=@(0) }
            if ($_ -eq 'AdvancedOverwriteReadOnlyTarget') { $p.Attributes=@(0) }
        }
        default { throw "Unknown advanced Renamer case: $RenamerHostCase" }
    }
    return $p
}

function New-RenamerAdvancedState {
    param($Fixture,[object[]]$Names)
    $state=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    for ($i=0; $i -lt $Names.Count; $i++) {
        if ($null -eq $Names[$i]) { continue }
        Add-RenamerExpectedFile $state ([string]$Names[$i]) $Fixture.Records[$i]
    }
    return ,$state
}

function Initialize-RenamerAdvancedFixture {
    if ($root -match '[^\x20-\x7e]' -or $root.Length -ge 180) { throw 'Advanced Renamer fixture requires short ASCII root.' }
    $plan=Get-RenamerAdvancedPlan
    $records=[Collections.Generic.List[object]]::new()
    for ($i=0; $i -lt $plan.Old.Count; $i++) {
        $path=Get-RenamerOwnedPath $plan.Old[$i]
        [byte[]]$bytes=if ($i -eq 0) { 1,2,3,4,5,6,7 } elseif ($plan.Tie) { 7,6,5,4,3,2,1 } else { 9,8,7 }
        [IO.File]::WriteAllBytes($path,$bytes)
        $stamp=[datetime]::new(2024,3,(2-$i),12,0,0,[DateTimeKind]::Utc)
        [IO.File]::SetLastWriteTimeUtc($path,$stamp)
        if ($i -in $plan.Attributes) { [IO.File]::SetAttributes($path,[IO.File]::GetAttributes($path) -bor [IO.FileAttributes]::ReadOnly) }
        $records.Add(@{Directory=$false;Hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
            WriteUtc=[IO.File]::GetLastWriteTimeUtc($path);Streams=$null;Attributes=[IO.File]::GetAttributes($path)})
    }
    $null=[IO.Directory]::CreateDirectory($destination)
    $guard=Join-Path $destination 'untouched.bin'
    [IO.File]::WriteAllText($guard,'Independent Renamer advanced guard',[Text.Encoding]::ASCII)
    $plugin=Join-Path (Split-Path -Parent $SalamanderExe) 'plugins\renamer\renamer.spl'
    if (-not [IO.File]::Exists($plugin)) { throw "Missing built Renamer SPL: $plugin" }
    $fixture=[pscustomobject]@{Plan=$plan;Records=$records;Before=$null;After=$null
        Plugin=[IO.Path]::GetFullPath($plugin);Guard=$guard;GuardHash=(Get-FileHash -LiteralPath $guard -Algorithm SHA256).Hash}
    $fixture.Before=New-RenamerAdvancedState $fixture $plan.Old
    $fixture.After=New-RenamerAdvancedState $fixture $plan.Final
    return $fixture
}

function Test-RenamerAdvancedState {
    param($Expected,$Fixture)
    if (-not (Test-RenamerTreeState $Expected $Fixture)) { return $false }
    foreach ($name in $Expected.Keys) {
        if ([IO.File]::GetAttributes((Get-RenamerOwnedPath $name)) -ne $Expected[$name].Attributes) { return $false }
    }
    return $true
}

function Assert-RenamerAdvancedPreview {
    param([IntPtr]$Dialog,[uint32]$Owner,$Fixture,[switch]$Identity)
    $expected=[Collections.Generic.List[object]]::new()
    foreach ($i in $Fixture.Plan.Indices) {
        $name=$Fixture.Plan.Old[$i]
        $new=if ($Identity) { $name } else { $Fixture.Plan.Proposed[$i] }
        $expected.Add(@{Old=$name;New=$new;Parent=''})
    }
    Assert-RenamerTreePreview $Dialog $Owner ([pscustomobject]@{Plan=@{Preview=$expected.ToArray()}})
}

function Set-RenamerAdvancedClipboard {
    param([string]$Text)
    Set-VerifiedNavigationClipboard -Text $Text
    Assert-True ([string]::Equals((Get-ClipboardText),$Text,[StringComparison]::Ordinal)) 'Exact fixture-only clipboard text'
}

function Export-RenamerAdvancedClipboard {
    param([IntPtr]$Dialog,[uint32]$Owner,[string]$Expected)
    Set-RenamerAdvancedClipboard ('renamer-export-sentinel-'+[guid]::NewGuid().ToString('N'))
    $seq=[SalamanderGuiNative]::GetClipboardSequenceNumber()
    [RenamerHostNative]::Command($Dialog,$Owner,624)
    Wait-Until {
        [SalamanderGuiNative]::GetClipboardSequenceNumber() -ne $seq -and
        [string]::Equals((Get-ClipboardText),$Expected,[StringComparison]::Ordinal)
    } 'Actual Renamer clipboard export, exact text and new sequence'
}

function Import-RenamerAdvancedClipboard {
    param([IntPtr]$Dialog,[uint32]$Owner,[string]$Text)
    Set-RenamerAdvancedClipboard $Text
    [RenamerHostNative]::Command($Dialog,$Owner,625)
    Assert-True ([string]::Equals([RenamerHostNative]::ReadManual($Dialog,$Owner),$Text,[StringComparison]::Ordinal)) 'Actual clipboard import preserves every code unit and line'
}

function Wait-RenamerAdvancedModal {
    param([IntPtr]$Dialog,[uint32]$Owner,[string[]]$Required,[int]$Id,[string]$Button)
    Wait-Until {
        if ($process.HasExited) { throw 'Host exited waiting for Renamer modal.' }
        [RenamerHostNative]::ModalAction($Dialog,$Owner,$Required,$Id,$Button)
    } ("verified Renamer modal: "+($Required -join ' | ')+" / "+$Button)
}

function Wait-RenamerAdvancedState {
    param([IntPtr]$Dialog,$Fixture,$Expected,[string]$Description)
    Wait-Until {
        if ($process.HasExited) { throw 'Host exited during advanced Renamer operation.' }
        [RenamerHostNative]::IsWindowEnabled($Dialog) -and (Test-RenamerAdvancedState $Expected $Fixture)
    } $Description -TimeoutSecondsOverride 60
}

function Open-RenamerFixtureLocks {
    param($Fixture,[string[]]$Names,$Handles)
    foreach ($index in $Fixture.Plan.Lock) {
        $path=Get-RenamerOwnedPath $Names[$index]
        # Genuine OS sharing restriction, not a mocked product return.
        $Handles.Add([IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read))
    }
}

function Release-RenamerFixtureLocks {
    param($Handles)
    foreach ($handle in $Handles) { $handle.Dispose() }
    $Handles.Clear()
}

function Wait-RenamerLockDialog {
    param([IntPtr]$Dialog,[uint32]$Owner,$Fixture,[string[]]$Names,[int]$Id,[string]$Button,[switch]$Observe)
    Wait-Until {
        if ($process.HasExited) { throw 'Host exited before lock error.' }
        foreach ($index in $Fixture.Plan.Lock) {
            $parts=[string[]]@('Unable to rename file: ',(Get-RenamerOwnedPath $Names[$index]))
            $matched=if ($Observe) { [RenamerHostNative]::ObserveModal($Dialog,$Owner,$parts,$Id,$Button) }
                     else { [RenamerHostNative]::ModalAction($Dialog,$Owner,$parts,$Id,$Button) }
            if ($matched) { return $true }
        }
        return $false
    } "actual locked fixture error / $Button"
}

function Test-RenamerAdvancedHost {
    param([Parameter(Mandatory)]$Fixture)
    $p=$Fixture.Plan
    $nl=[Environment]::NewLine
    $handles=[Collections.Generic.List[IDisposable]]::new()
    try {
        Assert-True (Test-RenamerAdvancedState $Fixture.Before $Fixture) 'Exact original fixture, bytes, attributes, timestamps and guard'
        Assert-True ((Read-PanelPath) -ceq $source) 'Exact advanced source panel'
        Restore-FilePanelFocus -ExpectedPath $source
        if ($p.Indices.Count -eq 2) { Select-TwoRegularFiles -ExpectedNames $p.Old }
        else {
            Send-Keys '{END}'
            Assert-True ((Read-FocusedFullname) -ceq (Get-RenamerOwnedPath $p.Old[1])) 'Exact overwrite source, target not selected'
        }
        Assert-True ((Read-PanelPath) -ceq $source) 'Exact panel before invoking Renamer'
        Send-Keys '^+r'
        $owner=[uint32]$process.Id
        $state=@{Dialog=[IntPtr]::Zero}
        Wait-Until {
            if ($process.HasExited) { throw 'Host exited starting advanced Renamer.' }
            $state.Dialog=[RenamerHostNative]::Find($owner)
            $state.Dialog -ne [IntPtr]::Zero
        } 'actual Batch Rename dialog'
        $dlg=$state.Dialog
        $process.Refresh()
        Assert-True (@($process.Modules | Where-Object {
            [string]::Equals($_.FileName,$Fixture.Plugin,[StringComparison]::OrdinalIgnoreCase)
        }).Count -eq 1) 'Exact built Renamer SPL loaded'
        Wait-Until { [RenamerHostNative]::IsWindowEnabled($dlg) -and [RenamerHostNative]::Count($dlg,$owner) -eq $p.Indices.Count } 'initial exact selection count'
        [RenamerHostNative]::Command($dlg,$owner,611)
        [RenamerHostNative]::Command($dlg,$owner,607)
        [RenamerHostNative]::Check($dlg,$owner,102,$false)
        [RenamerHostNative]::Combo($dlg,$owner,101,'*.*')
        [RenamerHostNative]::Command($dlg,$owner,$p.Sort)
        if ($p.Manual) {
            Assert-RenamerAdvancedPreview $dlg $owner $Fixture -Identity
            [RenamerHostNative]::Check($dlg,$owner,105,$true)
            $text=if ($null -ne $p.Text) { $p.Text } else { $p.Proposed -join $nl }
            switch ($p.Clip) {
                ExportOriginal {
                    $original=($p.Old -join $nl)+$nl
                    Assert-True ([string]::Equals([RenamerHostNative]::ReadManual($dlg,$owner),$original,[StringComparison]::Ordinal)) 'Generated original list'
                    Export-RenamerAdvancedClipboard $dlg $owner $original
                }
                ExportEdited {
                    [RenamerHostNative]::Manual($dlg,$owner,$text)
                    Export-RenamerAdvancedClipboard $dlg $owner $text
                }
                Import { Import-RenamerAdvancedClipboard $dlg $owner $text }
                RoundTrip {
                    [RenamerHostNative]::Manual($dlg,$owner,$text)
                    Export-RenamerAdvancedClipboard $dlg $owner $text
                    [RenamerHostNative]::Manual($dlg,$owner,($p.Old -join $nl))
                    Assert-True ([string]::Equals((Get-ClipboardText),$text,[StringComparison]::Ordinal)) 'Export remains exact before round-trip'
                    [RenamerHostNative]::Command($dlg,$owner,625)
                    Assert-True ([string]::Equals([RenamerHostNative]::ReadManual($dlg,$owner),$text,[StringComparison]::Ordinal)) 'Exported list round-trips through real load command'
                }
                default { [RenamerHostNative]::Manual($dlg,$owner,$text) }
            }
        } else {
            [RenamerHostNative]::Combo($dlg,$owner,106,$p.Rule)
            [RenamerHostNative]::Combo($dlg,$owner,108,'')
            [RenamerHostNative]::Combo($dlg,$owner,109,'')
        }
        # Invalid row counts cannot have a one-to-one preview; verify original
        # rows, exact edit text and the product validation diagnostic instead.
        if ($p.Action -ne 'LineCount') { Assert-RenamerAdvancedPreview $dlg $owner $Fixture }
        Assert-True (Test-RenamerAdvancedState $Fixture.Before $Fixture) 'Rule setup and clipboard do not mutate source'
        switch ($p.Action) {
            Validate {
                [RenamerHostNative]::Command($dlg,$owner,600)
                Wait-RenamerAdvancedModal $dlg $owner @('Validation successfully completed.') 1 'OK'
            }
            PreviewOnly { }
            NoOp {
                [RenamerHostNative]::Command($dlg,$owner,1)
                Wait-RenamerAdvancedModal $dlg $owner @('Nothing to do.') 1 'OK'
            }
            LineCount {
                [RenamerHostNative]::Command($dlg,$owner,600)
                Wait-RenamerAdvancedModal $dlg $owner @('Number of entered lines must match number of files selected for rename operation.') 1 'OK'
            }
            InvalidName {
                [RenamerHostNative]::Command($dlg,$owner,600)
                Wait-RenamerAdvancedModal $dlg $owner @('Not valid filename.',$p.Proposed[0]) 2 'Cancel'
            }
            { $_ -in @('LockCancel','LockSkipAll','LockSkip','LockRetry') } {
                Open-RenamerFixtureLocks $Fixture $p.Old $handles
                [RenamerHostNative]::Command($dlg,$owner,1)
                if ($_ -eq 'LockRetry') {
                    Wait-RenamerLockDialog $dlg $owner $Fixture $p.Old 4 'Retry' -Observe
                    Release-RenamerFixtureLocks $handles
                    Wait-RenamerLockDialog $dlg $owner $Fixture $p.Old 4 'Retry'
                } else {
                    if ($_ -eq 'LockCancel') { Wait-RenamerLockDialog $dlg $owner $Fixture $p.Old 2 'Cancel' }
                    elseif ($_ -eq 'LockSkipAll') { Wait-RenamerLockDialog $dlg $owner $Fixture $p.Old 174 'Skip All' }
                    else { Wait-RenamerLockDialog $dlg $owner $Fixture $p.Old 173 'Skip' }
                    Wait-RenamerAdvancedModal $dlg $owner @('Some files have not been renamed successfully.') 1 'OK'
                    Release-RenamerFixtureLocks $handles
                }
            }
            { $_ -like 'AdvancedOverwrite*' } {
                Open-RenamerFixtureLocks $Fixture $p.Old $handles
                [RenamerHostNative]::Command($dlg,$owner,1)
                $parts=@('Confirm File Overwrite',(Get-RenamerOwnedPath $p.Old[0]),(Get-RenamerOwnedPath $p.Old[1]))
                if ($_ -eq 'AdvancedOverwriteCancel') {
                    Wait-RenamerAdvancedModal $dlg $owner $parts 2 'Cancel'
                } else {
                    Wait-RenamerAdvancedModal $dlg $owner $parts 6 'Yes'
                    if ($_ -eq 'AdvancedOverwriteLockedSource') {
                        Wait-RenamerLockDialog $dlg $owner $Fixture $p.Old 2 'Cancel'
                        Wait-RenamerAdvancedModal $dlg $owner @('Some files have not been renamed successfully.') 1 'OK'
                    }
                    elseif ($_ -eq 'AdvancedOverwriteLockedTarget') {
                        Wait-Until {
                            if ($process.HasExited) { throw 'Host exited replacing locked target.' }
                            [RenamerHostNative]::ModalAction($dlg,$owner,@('Unable to overwrite file: ',(Get-RenamerOwnedPath $p.Old[0])),2,'Cancel') -or
                            [RenamerHostNative]::ModalAction($dlg,$owner,@('Unable to rename file: ',(Get-RenamerOwnedPath $p.Old[1])),2,'Cancel')
                        } 'specific locked-target replacement failure'
                        Wait-RenamerAdvancedModal $dlg $owner @('Some files have not been renamed successfully.') 1 'OK'
                    }
                }
                Release-RenamerFixtureLocks $handles
            }
            default {
                [RenamerHostNative]::Command($dlg,$owner,1)
                $renamed=New-RenamerAdvancedState $Fixture $p.Proposed
                Wait-RenamerAdvancedState $dlg $Fixture $renamed 'Exact renamed names and original bytes/attributes'
                if ($p.Action -in @('Undo','UndoDecline','UndoLockCancel','UndoLockRetry')) {
                    if ($p.Action -like 'UndoLock*') { Open-RenamerFixtureLocks $Fixture $p.Proposed $handles }
                    [RenamerHostNative]::Command($dlg,$owner,621)
                    if ($p.Action -eq 'UndoDecline') {
                        Wait-RenamerAdvancedModal $dlg $owner @('Undo rename operation?') 7 'No'
                    } else {
                        Wait-RenamerAdvancedModal $dlg $owner @('Undo rename operation?') 6 'Yes'
                        if ($p.Action -eq 'UndoLockCancel') {
                            Wait-RenamerLockDialog $dlg $owner $Fixture $p.Proposed 2 'Cancel'
                            Release-RenamerFixtureLocks $handles
                        } elseif ($p.Action -eq 'UndoLockRetry') {
                            Wait-RenamerLockDialog $dlg $owner $Fixture $p.Proposed 4 'Retry' -Observe
                            Release-RenamerFixtureLocks $handles
                            Wait-RenamerLockDialog $dlg $owner $Fixture $p.Proposed 4 'Retry'
                        }
                    }
                }
            }
        }
        Wait-RenamerAdvancedState $dlg $Fixture $Fixture.After 'Expected final tree, no lost source or target, exact bytes, attributes and timestamps'
        [RenamerHostNative]::Close($dlg,$owner)
        Wait-Until {
            if ($process.HasExited) { throw 'Host exited closing advanced Renamer.' }
            [RenamerHostNative]::Find($owner) -eq [IntPtr]::Zero
        } 'Renamer dialog closed'
        Assert-True (Test-RenamerAdvancedState $Fixture.After $Fixture) 'Exact final state after closing dialog'
        Write-Host "PASS: Renamer $RenamerHostCase exact original GUI behavior and independent data integrity."
    } finally {
        Release-RenamerFixtureLocks $handles
    }
}
