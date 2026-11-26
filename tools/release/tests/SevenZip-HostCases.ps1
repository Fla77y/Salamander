#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
# Real 7-Zip SPL host baseline, using the archive GUI driver's verified
# process, clipboard, panel and native copy-dialog helpers.
function Initialize-SevenZipHostFixture {
    if ($root -match '[^\x20-\x7e]' -or $root.Length -ge 200) {
        throw '7-Zip host baseline requires a short ASCII temporary path.'
    }
    $module = Join-Path (Split-Path -Parent $SalamanderExe) 'plugins\7zip\7zip.spl'
    if (-not (Test-Path -LiteralPath $module -PathType Leaf)) { throw "Missing built 7-Zip plugin: $module" }
    if (-not (Test-Path -LiteralPath $ZipHostSevenZip -PathType Leaf)) { throw 'Missing independent 7-Zip fixture tool.' }
    $null = [IO.Directory]::CreateDirectory($destination)
    $seed = [IO.Directory]::CreateDirectory((Join-Path $root '7z-input')).FullName
    $keep = Join-Path $seed 'keep.txt'
    $payloadPath = Join-Path $seed 'payload.txt'
    [IO.File]::WriteAllText($keep, ('UNSELECTED-0123456789' * 256), [Text.Encoding]::ASCII)
    [IO.File]::WriteAllText($payloadPath, ('SELECTED-abcdef98765' * 1024), [Text.Encoding]::ASCII)
    $archive = Join-Path $source 'fixture.7z'
    $null = Invoke-ZipHostFixtureTool -Arguments @('a','-t7z','-m0=LZMA2','-bd','-y',$archive,'keep.txt','payload.txt') -Directory $seed
    $null = Invoke-ZipHostFixtureTool -Arguments @('t','-bd',$archive) -Directory $seed
    $listing = Invoke-ZipHostFixtureTool -Arguments @('l','-slt',$archive) -Directory $seed
    $parts = @($listing -split '(?m)^----------\r?$')
    if ($parts.Count -ne 2) { throw 'Independent 7-Zip listing not recognized.' }
    $members = @([regex]::Matches($parts[1], '(?m)^Path = ([^\r\n]+)') | ForEach-Object { $_.Groups[1].Value })
    Assert-True ($members.Count -eq 2 -and (($members | Sort-Object) -join [char]0) -ceq (@('keep.txt','payload.txt') -join [char]0)) 'Independent 7z fixture contains exactly two distinct members'
    $hashes = [ordered]@{}
    foreach ($name in @('keep.txt','payload.txt')) {
        $hashes[$name] = (Get-FileHash -LiteralPath (Join-Path $seed $name) -Algorithm SHA256).Hash
    }
    Assert-True ($hashes['keep.txt'] -cne $hashes['payload.txt']) 'Independent 7z member payloads differ'
    [pscustomobject]@{
        Archive = $archive
        ArchiveHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
        Seed = $seed
        Hashes = $hashes
        Plugin = [IO.Path]::GetFullPath($module)
    }
}

function Test-SevenZipHost {
    param([Parameter(Mandatory)]$Fixture)
    Assert-True ((Read-PanelPath) -ceq $source) '7z source panel path'
    Send-Keys '{TAB}'
    Assert-True ((Read-PanelPath) -ceq $destination) '7z destination panel path'
    Send-Keys '{TAB}'
    Assert-True ((Read-PanelPath) -ceq $source) '7z source panel active'
    Send-Keys '{END}'
    Assert-True ((Read-FocusedFilename) -ceq 'fixture.7z') 'Exact 7z fixture selected'
    Assert-True ((Read-FocusedFullname) -ceq $Fixture.Archive) 'Exact 7z source archive identity'
    Send-Keys '{ENTER}'
    Wait-Until {
        if ($process.HasExited) { throw 'Salamander exited opening 7z fixture.' }
        if (Get-TestDialog) { throw "7z open displayed a dialog: $(Get-TestDialog)" }
        (Read-PanelPath).TrimEnd([char]92) -ceq $Fixture.Archive
    } '7z archive panel path'
    $process.Refresh()
    Assert-True (@($process.Modules | Where-Object {
        [string]::Equals($_.FileName, $Fixture.Plugin, [StringComparison]::OrdinalIgnoreCase)
    }).Count -eq 1) 'Exact built 7-Zip SPL loaded in host PID'
    # Prove both actual displayed member identities without selecting both.
    Send-Keys '{END}'
    Assert-True ((Read-FocusedFilename) -ceq 'payload.txt') 'Exact selected 7z member'
    Send-Keys '{UP}'
    Assert-True ((Read-FocusedFilename) -ceq 'keep.txt') 'Distinct unselected 7z member visible'
    Send-Keys '{END}'
    Assert-True ((Read-FocusedFilename) -ceq 'payload.txt') 'Exact 7z member before copy'
    Assert-True ((Read-PanelPath).TrimEnd([char]92) -ceq $Fixture.Archive) 'Exact 7z archive panel before copy'
    Assert-True (@(Get-ChildItem -LiteralPath $destination -Force).Count -eq 0) 'Fresh empty 7z extraction destination'
    [SalamanderGuiNative]::PostVerifiedLargeCopyCommand($mainWindowHandle, [uint32]$process.Id)
    if ($SevenZipHostCase -eq 'Cancel') {
        Wait-Until {
            if ($process.HasExited) { throw 'Salamander exited before 7z copy cancellation.' }
            [ZipHostDialogs]::TryCancelCopy($mainWindowHandle, [uint32]$process.Id, $destination)
        } 'verified 7z extraction dialog cancelled before copying'
        Wait-Until {
            if ($process.HasExited) { throw 'Salamander exited after 7z cancellation.' }
            [SalamanderGuiNative]::IsWindowEnabled($mainWindowHandle) -and -not (Get-TestDialog)
        } '7z copy dialog closed after cancellation'
        Wait-ForGuiResponsive
        Assert-True (@(Get-ChildItem -LiteralPath $destination -Force).Count -eq 0) '7z cancellation left target empty'
    }
    else {
        Wait-Until {
            if ($process.HasExited) { throw 'Salamander exited before 7z copy confirmation.' }
            [ZipHostDialogs]::TryConfirm($mainWindowHandle, [uint32]$process.Id, $false, $destination, '')
        } 'verified 7z archive copy dialog with exact member and target'
        $target = Join-Path $destination 'payload.txt'
        Wait-Until {
            if ($process.HasExited) { throw 'Salamander exited during 7z extraction.' }
            if (-not [SalamanderGuiNative]::IsWindowEnabled($mainWindowHandle)) { return $false }
            if (Get-TestDialog) { throw "7z extraction displayed a dialog: $(Get-TestDialog)" }
            if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { return $false }
            try { (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ceq $Fixture.Hashes['payload.txt'] }
            catch [IO.IOException] { return $false }
        } '7z selected member extraction with exact SHA-256' -TimeoutSecondsOverride 60
        Wait-ForGuiResponsive
        $entries = @(Get-ChildItem -LiteralPath $destination -Force)
        Assert-True ($entries.Count -eq 1 -and $entries[0].Name -ceq 'payload.txt' -and -not $entries[0].PSIsContainer) 'Only selected 7z member extracted'
        Assert-True ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ceq $Fixture.Hashes['payload.txt']) 'Final 7z output bytes match independent fixture'
    }
    Assert-True ((Read-PanelPath).TrimEnd([char]92) -ceq $Fixture.Archive) '7z archive remains open after operation'
    Assert-True ((Get-FileHash -LiteralPath $Fixture.Archive -Algorithm SHA256).Hash -ceq $Fixture.ArchiveHash) '7z source archive unchanged'
    foreach ($name in @('keep.txt','payload.txt')) {
        Assert-True ((Get-FileHash -LiteralPath (Join-Path $Fixture.Seed $name) -Algorithm SHA256).Hash -ceq $Fixture.Hashes[$name]) "Independent original 7z member unchanged: $name"
    }
    Write-Host "PASS: real 7-Zip plugin $SevenZipHostCase with exact member identity and SHA-256 integrity."
}
