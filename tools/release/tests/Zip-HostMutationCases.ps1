#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
# Independent ASCII short-path ZIP write scenarios, using the existing GUI driver.
function Initialize-ZipHostMutation {
    if ($root -match '[^\x20-\x7e]' -or $root.Length -ge 200) {
        throw 'ZIP mutation baseline requires a short ASCII temporary path.'
    }
    $module = Join-Path (Split-Path -Parent $SalamanderExe) 'plugins\zip\zip.spl'
    if (-not (Test-Path -LiteralPath $module -PathType Leaf)) { throw "Missing built ZIP plugin: $module" }
    $null = [IO.Directory]::CreateDirectory($destination)
    $seed = [IO.Directory]::CreateDirectory((Join-Path $root 'zip-seed')).FullName
    $member = 'payload.txt'
    $keep = 'keep.txt'
    $archive = if ($ZipHostMutation -eq 'Delete') { Join-Path $source 'fixture.zip' } else { Join-Path $destination 'fixture.zip' }
    $disk = Join-Path $source $member
    $keepPath = Join-Path $seed $keep
    $old = Join-Path $seed $member
    [IO.File]::WriteAllText($keepPath, ('KEEP-UNCHANGED-0123456789' * 512), [Text.Encoding]::ASCII)
    [IO.File]::WriteAllText($old, ('OLD-PAYLOAD-abcdef' * 512), [Text.Encoding]::ASCII)
    $expected = [ordered]@{}
    if ($ZipHostMutation -ne 'Create') {
        $args7z = @('a','-tzip','-mm=Deflate','-bd',$archive,$keep)
        if ($ZipHostMutation -in @('Replace','Delete')) { $args7z += $member }
        $null = Invoke-ZipHostFixtureTool -Arguments $args7z -Directory $seed
        $null = Invoke-ZipHostFixtureTool -Arguments @('t','-bd',$archive) -Directory $seed
        $expected[$keep] = (Get-FileHash -LiteralPath $keepPath -Algorithm SHA256).Hash
    }
    if ($ZipHostMutation -ne 'Delete') {
        [IO.File]::WriteAllText($disk, ('NEW-PAYLOAD-9876543210' * 1024), [Text.Encoding]::ASCII)
        $expected[$member] = (Get-FileHash -LiteralPath $disk -Algorithm SHA256).Hash
    }
    $before = if ([IO.File]::Exists($archive)) { (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash } else { '' }
    [pscustomobject]@{
        Archive = $archive; Member = $member; Disk = $disk; Plugin = [IO.Path]::GetFullPath($module)
        Expected = $expected; Before = $before; Seed = $seed
        KeepHash = (Get-FileHash -LiteralPath $keepPath -Algorithm SHA256).Hash
        OldHash = (Get-FileHash -LiteralPath $old -Algorithm SHA256).Hash
    }
}

function Assert-ZipMutationContents {
    param([Parameter(Mandatory)]$Fixture)
    $null = Invoke-ZipHostFixtureTool -Arguments @('t','-bd',$Fixture.Archive) -Directory $Fixture.Seed
    $listing = Invoke-ZipHostFixtureTool -Arguments @('l','-slt',$Fixture.Archive) -Directory $Fixture.Seed
    # Exclude the archive header, then require exactly the expected member
    # names (including duplicate detection); do not trust extraction alone.
    $parts = @($listing -split '(?m)^----------\r?$')
    if ($parts.Count -ne 2) { throw '7-Zip member listing is not recognized.' }
    $members = @([regex]::Matches($parts[1], '(?m)^Path = ([^\r\n]+)') | ForEach-Object { $_.Groups[1].Value })
    $expectedNames = @($Fixture.Expected.Keys | Sort-Object)
    Assert-True ($members.Count -eq $expectedNames.Count -and
        (($members | Sort-Object) -join [char]0) -ceq ($expectedNames -join [char]0)) 'Exact ZIP member set without duplicates'
    $verify = [IO.Directory]::CreateDirectory((Join-Path $root 'zip-verify')).FullName
    $null = Invoke-ZipHostFixtureTool -Arguments @('x','-bd','-y',"-o$verify",$Fixture.Archive) -Directory $Fixture.Seed
    foreach ($name in $expectedNames) {
        $path = Join-Path $verify $name
        Assert-True ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ceq $Fixture.Expected[$name]) "ZIP member SHA-256: $name"
    }
    Assert-True (@(Get-ChildItem -LiteralPath $verify -Force).Count -eq $expectedNames.Count) 'Only intended members independently extracted'
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $Fixture.Seed 'keep.txt') -Algorithm SHA256).Hash -ceq $Fixture.KeepHash) 'Independent keep fixture unchanged'
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $Fixture.Seed 'payload.txt') -Algorithm SHA256).Hash -ceq $Fixture.OldHash) 'Independent old payload unchanged'
    if ($ZipHostMutation -ne 'Delete') {
        Assert-True ((Get-FileHash -LiteralPath $Fixture.Disk -Algorithm SHA256).Hash -ceq $Fixture.Expected[$Fixture.Member]) 'Original disk source preserved'
    }
}

function Test-ZipHostMutation {
    param([Parameter(Mandatory)]$Fixture)
    Assert-True ((Read-PanelPath) -ceq $source) 'ZIP mutation source panel'
    Send-Keys '{TAB}'
    Assert-True ((Read-PanelPath) -ceq $destination) 'ZIP mutation destination panel'
    Send-Keys '{TAB}'
    Assert-True ((Read-PanelPath) -ceq $source) 'ZIP mutation source active'
    Send-Keys '{END}'
    if ($ZipHostMutation -eq 'Delete') {
        Assert-True ((Read-FocusedFullname) -ceq $Fixture.Archive) 'Exact disposable ZIP selected for deletion test'
        Send-Keys '{ENTER}'
        Wait-Until {
            if ($process.HasExited) { throw 'Host exited opening ZIP.' }
            if (Get-TestDialog) { throw "ZIP open dialog: $(Get-TestDialog)" }
            (Read-PanelPath).TrimEnd([char]92) -ceq $Fixture.Archive
        } 'exact ZIP archive panel'
        Send-Keys '{END}'
        Assert-True ((Read-FocusedFilename) -ceq $Fixture.Member) 'Exact disposable archive member selected'
        Assert-True ((Read-PanelPath).TrimEnd([char]92) -ceq $Fixture.Archive) 'Exact ZIP archive before F8'
        [SalamanderGuiNative]::PostVerifiedDirectoryDeleteCommand($mainWindowHandle, [uint32]$process.Id)
        $phases = @('Delete')
    }
    else {
        Assert-True ((Read-FocusedFullname) -ceq $Fixture.Disk) 'Exact source file before pack'
        Assert-True ((Read-FocusedFilename) -ceq $Fixture.Member) 'Exact source leaf before pack'
        [ZipHostDialogs]::PostPack($mainWindowHandle, [uint32]$process.Id)
        Wait-Until {
            if ($process.HasExited) { throw 'Host exited before Pack dialog.' }
            [ZipHostDialogs]::TryMutation($mainWindowHandle, [uint32]$process.Id, 'Pack', $Fixture.Archive, $Fixture.Member, $Fixture.Disk)
        } 'verified Pack dialog with ZIP plugin and exact destination'
        $phases = @('Options')
        if ($ZipHostMutation -in @('Add','Replace')) { $phases = @('Add') + $phases }
        if ($ZipHostMutation -eq 'Replace') { $phases += 'Replace' }
    }
    $seen = [Collections.Generic.HashSet[string]]::new()
    Wait-Until {
        if ($process.HasExited) { throw 'Host exited during ZIP mutation.' }
        foreach ($phase in $phases) {
            if (-not $seen.Contains($phase) -and
                [ZipHostDialogs]::TryMutation($mainWindowHandle, [uint32]$process.Id, $phase, $Fixture.Archive, $Fixture.Member, $Fixture.Disk)) {
                [void]$seen.Add($phase)
                Write-Host "ZIP mutation confirmed: $phase"
            }
        }
        if (-not [SalamanderGuiNative]::IsWindowEnabled($mainWindowHandle) -or
            -not [IO.File]::Exists($Fixture.Archive)) { return $false }
        try {
            (Get-FileHash -LiteralPath $Fixture.Archive -Algorithm SHA256).Hash -cne $Fixture.Before
        }
        catch [IO.IOException] { return $false }
    } "ZIP $ZipHostMutation archive change and enabled host" -TimeoutSecondsOverride 60
    Wait-ForGuiResponsive
    $process.Refresh()
    Assert-True (@($process.Modules | Where-Object {
        [string]::Equals($_.FileName, $Fixture.Plugin, [StringComparison]::OrdinalIgnoreCase)
    }).Count -eq 1) 'Exact built ZIP plugin loaded'
    Assert-ZipMutationContents -Fixture $Fixture
    Write-Host "PASS: real ZIP plugin $ZipHostMutation with independent member and SHA-256 verification."
}
