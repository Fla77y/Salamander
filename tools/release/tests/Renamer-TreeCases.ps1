#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
# Additional tree-level Renamer acceptance, using the same verified host and
# original preview. Expected trees are constructed BEFORE launching Salamander.
# No assertion from the existing short-path rule matrix is replaced.
function Get-RenamerTreePlan {
    $plan = @{
        Panel=''; Select=@('a.txt','b.txt'); Rule='new-$(OriginalName)'
        Spec=607; Mask='*.*'; Recursive=$false; Undo=$false; Ads=$false
        Files=@(@{Old='a.txt';New='new-a.txt'},@{Old='b.txt';New='new-b.txt'})
        Dirs=@(); Preview=@(@{Old='a.txt';New='new-a.txt';Parent=''},@{Old='b.txt';New='new-b.txt';Parent=''})
    }
    switch ($RenamerHostCase) {
        { $_ -in @('TreeDirectory','TreeDirectoryUndo') } {
            $plan.Select=@('folder.old')
            $plan.Files=@(@{Old='folder.old\child.txt';New='new-folder.old\child.txt'},@{Old='folder.old\sub\deep.bin';New='new-folder.old\sub\deep.bin'})
            $plan.Dirs=@(@{Old='folder.old\empty';New='new-folder.old\empty'})
            $plan.Preview=@(@{Old='folder.old';New='new-folder.old';Parent=''})
            $plan.Undo=$_ -eq 'TreeDirectoryUndo'
        }
        TreeEmptyDirectory {
            $plan.Select=@('empty.dir')
            $plan.Files=@()
            $plan.Dirs=@(@{Old='empty.dir';New='new-empty.dir'})
            $plan.Preview=@(@{Old='empty.dir';New='new-empty.dir';Parent=''})
        }
        { $_ -in @('TreeRecursiveMask','TreeRecursiveUndo') } {
            $plan.Select=@('tree')
            $plan.Mask='*.txt'
            $plan.Recursive=$true
            $plan.Files=@(@{Old='tree\a.txt';New='tree\new-a.txt'},@{Old='tree\sub\b.txt';New='tree\sub\new-b.txt'},@{Old='tree\sub\guard.bin';New='tree\sub\guard.bin'})
            $plan.Dirs=@(@{Old='tree\empty';New='tree\empty'})
            $plan.Preview=@(@{Old='a.txt';New='new-a.txt';Parent='tree'},@{Old='b.txt';New='new-b.txt';Parent='tree\sub'})
            $plan.Undo=$_ -eq 'TreeRecursiveUndo'
        }
        { $_ -in @('TreeRelativeMove','TreeRelativeUndo','TreeFullPathMove','TreeFullPathUndo') } {
            $plan.Spec=608
            $plan.Rule='target\$(OriginalName)'
            $plan.Files=@(@{Old='a.txt';New='target\a.txt'},@{Old='b.txt';New='target\b.txt'})
            $plan.Preview=@(@{Old='a.txt';New='target\a.txt';Parent=''},@{Old='b.txt';New='target\b.txt';Parent=''})
            $plan.Undo=$_ -in @('TreeRelativeUndo','TreeFullPathUndo')
            if ($_ -in @('TreeFullPathMove','TreeFullPathUndo')) {
                $plan.Spec=609
                # Dollar signs in a temporary root are literal, not variables.
                $plan.Rule=(Join-Path $source 'target').Replace('$','$$') + '\$(Name)'
                $plan.Preview=@(@{Old=(Join-Path $source 'a.txt');New=(Join-Path $source 'target\a.txt');Parent=$null},@{Old=(Join-Path $source 'b.txt');New=(Join-Path $source 'target\b.txt');Parent=$null})
            }
        }
        TreeUnicodeNames {
            $plan.Select=@('a-東京-😀.txt','b-大阪-🦎.txt')
            $plan.Files=@(@{Old='a-東京-😀.txt';New='new-a-東京-😀.txt'},@{Old='b-大阪-🦎.txt';New='new-b-大阪-🦎.txt'})
            $plan.Preview=@(@{Old='a-東京-😀.txt';New='new-a-東京-😀.txt';Parent=''},@{Old='b-大阪-🦎.txt';New='new-b-大阪-🦎.txt';Parent=''})
        }
        TreeNormalization {
            # Windows NTFS does not normalize filenames. Distinct original
            # code-unit sequences must retain separate content identities.
            $one='caf' + [char]0x00e9 + '.txt'
            $two='cafe' + [char]0x0301 + '.txt'
            $plan.Select=@($one,$two)
            $plan.Files=@(@{Old=$one;New=('new-'+$one)},@{Old=$two;New=('new-'+$two)})
            $plan.Preview=@(@{Old=$one;New=('new-'+$one);Parent=''},@{Old=$two;New=('new-'+$two);Parent=''})
        }
        { $_ -in @('TreeUnicodeRoot','TreeLongRoot') } {
            $panel='東京-😀'
            if ($_ -eq 'TreeLongRoot') {
                $panel=@(('a'*70),('b'*70),('c'*70),('d'*70)) -join '\'
            }
            $plan.Panel=$panel
            $plan.Files=@(@{Old=(Join-Path $panel 'a.txt');New=(Join-Path $panel 'new-a.txt')},@{Old=(Join-Path $panel 'b.txt');New=(Join-Path $panel 'new-b.txt')})
            $plan.Preview=@(@{Old='a.txt';New='new-a.txt';Parent=$panel},@{Old='b.txt';New='new-b.txt';Parent=$panel})
        }
        TreeLongLeaf {
            $one='a'+('x'*245)+'.txt'
            $two='b'+('y'*245)+'.txt'
            $plan.Select=@($one,$two)
            $plan.Rule='1234-$(OriginalName)'
            $plan.Files=@(@{Old=$one;New=('1234-'+$one)},@{Old=$two;New=('1234-'+$two)})
            $plan.Preview=@(@{Old=$one;New=('1234-'+$one);Parent=''},@{Old=$two;New=('1234-'+$two);Parent=''})
        }
        { $_ -in @('TreeAds','TreeAdsUndo') } {
            $plan.Ads=$true
            $plan.Undo=$_ -eq 'TreeAdsUndo'
        }
        TreeMetadataVariables {
            # Fixed local write timestamps and known byte lengths are set by
            # fixture creation, not read from the Renamer's preview.
            $plan.Rule='$(Date:yyyyMMdd)-$(Time:HHmmss)-$(Size)-$(Name)'
            $plan.Files=@(@{Old='a.txt';New='20240229-123456-3-a.txt'},@{Old='b.txt';New='20240301-010203-7-b.txt'})
            $plan.Preview=@(@{Old='a.txt';New='20240229-123456-3-a.txt';Parent=''},@{Old='b.txt';New='20240301-010203-7-b.txt';Parent=''})
        }
        default { throw "Unknown Renamer tree case: $RenamerHostCase" }
    }
    return $plan
}

function Get-RenamerOwnedPath {
    param([string]$Relative)
    if ([string]::IsNullOrEmpty($Relative)) { return $source }
    if ([IO.Path]::IsPathRooted($Relative) -or @($Relative.Split('\') | Where-Object { $_ -in @('','..','.') }).Count) {
        throw "Unsafe Renamer relative fixture path: $Relative"
    }
    $full=[IO.Path]::GetFullPath((Join-Path $source $Relative))
    if (-not $full.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Renamer fixture escaped source root.' }
    return $full
}

function Add-RenamerExpectedDirectory {
    param($State,[string]$Relative)
    while (-not [string]::IsNullOrEmpty($Relative)) {
        $null=Get-RenamerOwnedPath $Relative
        if (-not $State.ContainsKey($Relative)) { $State.Add($Relative,@{Directory=$true}) }
        elseif (-not $State[$Relative].Directory) { throw 'Fixture path is both directory and file.' }
        $Relative=[IO.Path]::GetDirectoryName($Relative)
    }
}

function Add-RenamerExpectedFile {
    param($State,[string]$Relative,$Record)
    $null=Get-RenamerOwnedPath $Relative
    Add-RenamerExpectedDirectory $State ([IO.Path]::GetDirectoryName($Relative))
    $State.Add($Relative,$Record)
}

function Get-RenamerStreamHash {
    param([string]$Path,[string]$Stream)
    $reader=[IO.File]::OpenRead($Path+':'+$Stream)
    try { return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($reader)) }
    finally { $reader.Dispose() }
}

function Get-RenamerStreamInventory {
    param([string]$Path)
    $result=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    foreach ($stream in @(Get-Item -LiteralPath $Path -Stream * -ErrorAction Stop)) {
        if ($stream.Stream -eq ':$DATA') { continue }
        $result.Add([string]$stream.Stream,(Get-RenamerStreamHash $Path $stream.Stream))
    }
    return ,$result
}

function Initialize-RenamerTreeFixture {
    if ($root -match '[^\x20-\x7e]' -or $root.Length -ge 180) { throw 'Renamer tree baseline requires a short ASCII temporary root before arranging the specific fixture.' }
    $plan=Get-RenamerTreePlan
    $before=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $after=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $panel=Get-RenamerOwnedPath $plan.Panel
    foreach ($dir in $plan.Dirs) {
        [void][IO.Directory]::CreateDirectory((Get-RenamerOwnedPath $dir.Old))
        Add-RenamerExpectedDirectory $before $dir.Old
        Add-RenamerExpectedDirectory $after $dir.New
    }
    for ($i=0; $i -lt $plan.Files.Count; $i++) {
        $file=$plan.Files[$i]
        $path=Get-RenamerOwnedPath $file.Old
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
        if ([IO.File]::Exists($path)) { throw 'Fixture source filename already exists; possible alias collision.' }
        $bytes=[Text.Encoding]::UTF8.GetBytes(("Renamer tree independent payload $i " * (128+$i)))
        if ($RenamerHostCase -eq 'TreeMetadataVariables') {
            [byte[]]$bytes=if ($i -eq 0) { [byte[]](1,2,3) } else { [byte[]](4,5,6,7,8,9,10) }
        }
        [IO.File]::WriteAllBytes($path,$bytes)
        $write=if ($i -eq 0) { [datetime]::new(2024,2,29,12,34,56,[DateTimeKind]::Local) } else { [datetime]::new(2024,3,1,1,2,3,[DateTimeKind]::Local) }
        [IO.File]::SetLastWriteTime($path,$write)
        $record=@{Directory=$false;Hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes));WriteUtc=[IO.File]::GetLastWriteTimeUtc($path);Streams=$null}
        if ($plan.Ads) {
            # Both a nonempty named stream and an empty stream must survive.
            $streamBytes=[Text.Encoding]::UTF8.GetBytes("Distinct ADS payload $i")
            [IO.File]::WriteAllBytes($path+':renamer-data',$streamBytes)
            [IO.File]::WriteAllBytes($path+':renamer-empty',[byte[]]@())
            $record.Streams=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
            $record.Streams.Add('renamer-data',[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($streamBytes)))
            $record.Streams.Add('renamer-empty',[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([byte[]]@())))
            # Setting streams may update timestamps; establish a fixed final time.
            [IO.File]::SetLastWriteTime($path,$write)
            $record.WriteUtc=[IO.File]::GetLastWriteTimeUtc($path)
        }
        Add-RenamerExpectedFile $before $file.Old $record
        Add-RenamerExpectedFile $after $file.New $record
    }
    if ($RenamerHostCase -eq 'TreeLongRoot') { Assert-True ($panel.Length -gt 260) 'Renamer root exceeds MAX_PATH' }
    if ($RenamerHostCase -eq 'TreeLongLeaf') {
        foreach ($file in $plan.Files) {
            Assert-True ($file.New.Length -eq 255 -and (Get-RenamerOwnedPath $file.New).Length -gt 260) 'Exact 255 UTF-16-unit target component and long full path'
        }
    }
    $null=[IO.Directory]::CreateDirectory($destination)
    $guard=Join-Path $destination 'untouched.bin'
    [IO.File]::WriteAllText($guard,'Renamer tree independent guard',[Text.Encoding]::ASCII)
    $plugin=Join-Path (Split-Path -Parent $SalamanderExe) 'plugins\renamer\renamer.spl'
    if (-not [IO.File]::Exists($plugin)) { throw "Missing Renamer SPL: $plugin" }
    [pscustomobject]@{Plan=$plan;Panel=$panel;Before=$before;After=$after;Plugin=[IO.Path]::GetFullPath($plugin)
        Guard=$guard;GuardHash=(Get-FileHash -LiteralPath $guard -Algorithm SHA256).Hash}
}

function Test-RenamerTreeState {
    param($Expected,$Fixture)
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    # Walk without descending into unexpected/reparse-point directories.
    $pending=[Collections.Generic.Queue[string]]::new()
    $pending.Enqueue($source)
    while ($pending.Count) {
        $parent=$pending.Dequeue()
        if (-not [IO.Directory]::Exists($parent)) { return $false }
        foreach ($item in @(Get-ChildItem -LiteralPath $parent -Force)) {
            $relative=[IO.Path]::GetRelativePath($source,$item.FullName)
            if (-not $seen.Add($relative) -or -not $Expected.ContainsKey($relative) -or
                $item.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) { return $false }
            $record=$Expected[$relative]
            if ([bool]$item.PSIsContainer -ne [bool]$record.Directory) { return $false }
            if ($record.Directory) { $pending.Enqueue($item.FullName); continue }
            try {
                if ((Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash -cne $record.Hash -or
                    [IO.File]::GetLastWriteTimeUtc($item.FullName) -ne $record.WriteUtc) { return $false }
                if ($null -ne $record.Streams) {
                    $actual=Get-RenamerStreamInventory $item.FullName
                    if ($actual.Count -ne $record.Streams.Count) { return $false }
                    foreach ($stream in $record.Streams.Keys) {
                        if (-not $actual.ContainsKey($stream) -or $actual[$stream] -cne $record.Streams[$stream]) { return $false }
                    }
                }
            }
            catch [IO.IOException] { return $false }
        }
    }
    if ($seen.Count -ne $Expected.Count) { return $false }
    $guards=@(Get-ChildItem -LiteralPath $destination -Force)
    return $guards.Count -eq 1 -and $guards[0].FullName -ceq $Fixture.Guard -and
        -not $guards[0].PSIsContainer -and
        (Get-FileHash -LiteralPath $Fixture.Guard -Algorithm SHA256).Hash -ceq $Fixture.GuardHash
}

function Assert-RenamerTreePreview {
    param([IntPtr]$Dialog,[uint32]$OwnerPid,$Fixture)
    $expected=$Fixture.Plan.Preview
    $observed=@{Rows=$null}
    try {
        Wait-Until {
            $observed.Rows=Get-RenamerPreview $Dialog $OwnerPid $expected.Count
            if ($null -eq $observed.Rows -or $observed.Rows.Count -ne $expected.Count) { return $false }
            $unmatched=[Collections.Generic.List[object]]::new()
            foreach ($entry in $expected) { $unmatched.Add($entry) }
            foreach ($row in $observed.Rows) {
                $matched=-1
                for ($i=0; $i -lt $unmatched.Count; $i++) {
                    $entry=$unmatched[$i]
                    $path=if ($null -eq $entry.Parent) { '' } else { Get-RenamerOwnedPath $entry.Parent }
                    if ([string]::Equals($row.Old,$entry.Old,[StringComparison]::Ordinal) -and
                        [string]::Equals($row.New,$entry.New,[StringComparison]::Ordinal) -and
                        [string]::Equals($row.Path.TrimEnd('\'),$path.TrimEnd('\'),[StringComparison]::Ordinal)) {
                        $matched=$i
                        break
                    }
                }
                if ($matched -lt 0) { return $false }
                $unmatched.RemoveAt($matched)
            }
            return $unmatched.Count -eq 0
        } "exact Renamer tree preview rows, names and paths ($RenamerHostCase)"
    }
    catch {
        Write-Host ('Observed tree preview: '+($observed.Rows | ConvertTo-Json -Compress))
        Write-Host ('Expected tree preview: '+($expected | ConvertTo-Json -Compress))
        throw
    }
    Write-Host ('PASS: exact tree preview: '+($observed.Rows | ConvertTo-Json -Compress))
}

function Test-RenamerTreeHost {
    param([Parameter(Mandatory)]$Fixture)
    $plan=$Fixture.Plan
    Assert-True (Test-RenamerTreeState $Fixture.Before $Fixture) 'Complete independent original tree, metadata and guard'
    if (-not [string]::Equals((Read-PanelPath),$Fixture.Panel,[StringComparison]::Ordinal)) { Go-ToPath $Fixture.Panel }
    Assert-True ([string]::Equals((Read-PanelPath),$Fixture.Panel,[StringComparison]::Ordinal)) 'Exact Renamer source panel including Unicode/long root'
    Restore-FilePanelFocus -ExpectedPath $Fixture.Panel
    if ($plan.Select.Count -eq 1) {
        Focus-DirectoryRow -Name $plan.Select[0]
        Assert-True ([string]::Equals((Read-FocusedFullname),(Join-Path $Fixture.Panel $plan.Select[0]),[StringComparison]::Ordinal)) 'Exact selected directory identity'
    }
    else {
        # Ordinal identity comparison, deliberately not cultural sorting:
        # canonically equivalent Unicode filenames may coexist on NTFS.
        Send-Keys '{END}'
        $last=Read-FocusedFullname
        Send-Keys '{UP}'
        $prev=Read-FocusedFullname
        $expected=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($name in $plan.Select) { [void]$expected.Add((Join-Path $Fixture.Panel $name)) }
        Assert-True (-not [string]::Equals($prev,$last,[StringComparison]::Ordinal) -and $expected.SetEquals([string[]]@($prev,$last))) 'Both distinct exact source identities before selection'
        Send-Keys '{INSERT}'
        Assert-True ([string]::Equals((Read-FocusedFullname),$last,[StringComparison]::Ordinal)) 'Selection advanced to independently verified last file'
        Send-Keys '{INSERT}'
    }
    Assert-True ([string]::Equals((Read-PanelPath),$Fixture.Panel,[StringComparison]::Ordinal)) 'Exact panel immediately before invoking Renamer'
    Send-Keys '^+r'
    $owner=[uint32]$process.Id
    $state=@{Dialog=[IntPtr]::Zero}
    Wait-Until {
        if ($process.HasExited) { throw 'Host exited starting Renamer.' }
        $state.Dialog=[RenamerHostNative]::Find($owner)
        if ($state.Dialog -ne [IntPtr]::Zero) { return $true }
        $message=Get-TestDialog
        if ($message) { throw "Required Renamer operation refused or blocked: $message" }
        return $false
    } 'actual Batch Rename dialog (Unicode/long-path refusals are not PASS)'
    $dlg=$state.Dialog
    $process.Refresh()
    Assert-True (@($process.Modules | Where-Object {
        [string]::Equals($_.FileName,$Fixture.Plugin,[StringComparison]::OrdinalIgnoreCase)
    }).Count -eq 1) 'Exact built Renamer plugin loaded'
    Wait-Until { [RenamerHostNative]::IsWindowEnabled($dlg) -and [RenamerHostNative]::Count($dlg,$owner) -gt 0 } 'initial Renamer selection ready'
    [RenamerHostNative]::Command($dlg,$owner,611)
    [RenamerHostNative]::Command($dlg,$owner,$plan.Spec)
    [RenamerHostNative]::Combo($dlg,$owner,101,$plan.Mask)
    [RenamerHostNative]::Check($dlg,$owner,102,$plan.Recursive)
    Wait-Until { [RenamerHostNative]::IsWindowEnabled($dlg) -and [RenamerHostNative]::Count($dlg,$owner) -eq $plan.Preview.Count } 'exact intended tree selection count'
    [RenamerHostNative]::Combo($dlg,$owner,106,$plan.Rule)
    [RenamerHostNative]::Combo($dlg,$owner,108,'')
    [RenamerHostNative]::Combo($dlg,$owner,109,'')
    [RenamerHostNative]::Case($dlg,$owner,116,0)
    [RenamerHostNative]::Case($dlg,$owner,117,0)
    Assert-RenamerTreePreview $dlg $owner $Fixture
    Assert-True (Test-RenamerTreeState $Fixture.Before $Fixture) 'Tree and all data untouched by preview'
    # Validation explicitly precedes any write. Do not accept overwrite,
    # skip or error dialogs; only the successful validation message.
    [RenamerHostNative]::Command($dlg,$owner,600)
    Wait-Until { [RenamerHostNative]::ModalAction($dlg,$owner,@('Validation successfully completed.'),1,'OK') } 'real Renamer validation succeeded'
    Wait-Until { [RenamerHostNative]::IsWindowEnabled($dlg) } 'Renamer ready after validation'
    Assert-True (Test-RenamerTreeState $Fixture.Before $Fixture) 'Validation does not modify tree'
    Assert-RenamerTreePreview $dlg $owner $Fixture
    [RenamerHostNative]::Command($dlg,$owner,1)
    Wait-Until {
        if ($process.HasExited) { throw 'Host exited during tree rename.' }
        [RenamerHostNative]::IsWindowEnabled($dlg) -and (Test-RenamerTreeState $Fixture.After $Fixture)
    } 'exact renamed tree, byte hashes, timestamps and applicable stream sets' -TimeoutSecondsOverride 60
    $final=$Fixture.After
    if ($plan.Undo) {
        [RenamerHostNative]::Command($dlg,$owner,621)
        Wait-Until { [RenamerHostNative]::ModalAction($dlg,$owner,@('Undo rename operation?'),6,'Yes') } 'verified tree Undo confirmation'
        Wait-Until {
            if ($process.HasExited) { throw 'Host exited during tree Undo.' }
            [RenamerHostNative]::IsWindowEnabled($dlg) -and (Test-RenamerTreeState $Fixture.Before $Fixture)
        } 'Undo restores exact original tree including metadata and applicable stream sets' -TimeoutSecondsOverride 60
        $final=$Fixture.Before
    }
    [RenamerHostNative]::Close($dlg,$owner)
    Wait-Until {
        if ($process.HasExited) { throw 'Host exited closing Renamer tree dialog.' }
        [RenamerHostNative]::Find($owner) -eq [IntPtr]::Zero
    } 'Renamer tree dialog closed'
    Assert-True (Test-RenamerTreeState $final $Fixture) 'Final complete tree and independent guard exact'
    Write-Host "PASS: Renamer $RenamerHostCase verified preview, validation, actual disk operation and complete data integrity."
}
