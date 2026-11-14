#requires -Version 7.4
# Small deterministic regression suite for package validation.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$toolsDir = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).ProviderPath
$scriptFiles = @(
    (Join-Path $toolsDir 'Package-Helpers.ps1'),
    (Join-Path $toolsDir 'Update-Build-Test-Package.ps1'),
    (Join-Path $toolsDir '..\Manage-Salamander.ps1'),
    (Join-Path $toolsDir 'tests\Test-FilenamesAndPaths.ps1'),
    (Join-Path $toolsDir 'tests\Test-SalamanderGui-LongPaths.ps1')
)
foreach ($file in $scriptFiles) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        throw "PowerShell parser errors in $file : $($errors -join '; ')"
    }
}

# The GUI driver dispatches the exact synchronous WM_COMMAND messages handled
# by Salamander. Prevent accidental drift of command IDs in resource.rh2.
$resourceCommands = Get-Content -LiteralPath (
    Join-Path $toolsDir '..\..\src\resource.rh2') -Raw
$guiDriver = Get-Content -LiteralPath (
    Join-Path $toolsDir 'tests\Test-SalamanderGui-LongPaths.ps1') -Raw
foreach ($command in @(
    @{ Name = 'CM_CLIPPASTE'; Id = 775 }
    @{ Name = 'CM_CLIPCOPYFULLPATH'; Id = 711 }
    @{ Name = 'CM_CLIPCOPYNAME'; Id = 710 }
)) {
    $pattern = '(?m)^\s*#define\s+' + $command.Name +
               '\s+' + $command.Id + '(?:\s|$)'
    if ($resourceCommands -notmatch $pattern) {
        throw "GUI test command ID no longer matches src/resource.rh2: $($command.Name)"
    }
}
if ($guiDriver -notmatch 'SendMessageTimeout' -or
    $guiDriver -notmatch 'Invoke-SalamanderCommand') {
    throw 'GUI test must synchronize clipboard commands with the main window.'
}



# A single Shift+Up marks only the previously focused row in Salamander.
# Both F5 and F6 fixtures must explicitly mark two verified regular files.
$multiSelectBlock = [regex]::Match(
    $guiDriver,
    '(?s)if \(\$ShortUnicodeMultiSelectOnly\) \{\s*# Arrange: existing, distinct source and destination directories\.(.*?)if \(\$ShortUnicodeRowIdentityOnly\) \{'
).Groups[1].Value
if ([string]::IsNullOrEmpty($multiSelectBlock) -or
    $multiSelectBlock -match "Send-Keys '\+\{UP\}'" -or
    ([regex]::Matches($multiSelectBlock, 'Select-TwoRegularFiles')).Count -ne 2 -or
    $guiDriver -notmatch '(?s)function Select-TwoRegularFiles\s*\{.*?Send-Keys ''\{INSERT\}''.*?Send-Keys ''\{INSERT\}''') {
    throw 'GUI F5/F6 multiselect must mark two verified file rows using Insert, not a single Shift+Up.'
}


# The GUI driver must recover safely from a transient clipboard/navigation
# stall without repeating commands after success or hiding real modal errors.
$navigationBlock = [regex]::Match(
    $guiDriver,
    '(?s)function Go-ToPath\s*\{(.*?)\nfunction Read-FocusedFilename'
).Groups[1].Value
if ([string]::IsNullOrEmpty($navigationBlock) -or
    $navigationBlock -notmatch 'maxNavigationAttempts\s*=\s*2' -or
    $navigationBlock -notmatch 'TimeoutSecondsOverride' -or
    $navigationBlock -notmatch 'Get-TestDialog' -or
    $guiDriver -notmatch '(?s)function Read-PanelPath\s*\{.*?Invoke-SalamanderCommand -CommandId 711.*?for \(\$attempt') {
    throw 'GUI navigation must bound clipboard retries, reject modal errors and verify an idempotent retry.'
}
foreach ($prefix in @(
    'Cannot activate verified test Salamander',
    'Salamander command {0} did not complete',
    'GUI navigation failed: {0}',
    'GUI startup failed: {0}'
)) {
    if ($guiDriver -notmatch [regex]::Escape('throw (("' + $prefix)) {
        throw "GUI diagnostics must format the entire error message: $prefix"
    }
}


# Closing a refusal dialog can return foreground focus to another process.
# The test must restore its own verified main HWND before any next SendKeys,
# while retaining Send-Keys' strict foreign-process input refusal.
$unsafeOperationBlock = [regex]::Match(
    $guiDriver,
    '(?s)if \(\$ShortUnicodeUnsafeOperationsOnly\) \{\s*# Destructive shortcuts(.*?)\n    if \(\$ShortUnicodeCollisionOnly\) \{'
).Groups[1].Value
if ([string]::IsNullOrEmpty($unsafeOperationBlock) -or
    $unsafeOperationBlock -notmatch "(?s)Send-Keys '\{ESC\}'\s*Wait-Until \{ -not \(Get-TestDialog\) \}[^\r\n]*\r?\n(?:\s*#[^\r\n]*\r?\n)*\s*Focus-TestProcess" -or
    $unsafeOperationBlock -notmatch 'Assert-True \(\(Read-PanelPath\) -ceq \$source\)' -or
    $guiDriver -notmatch 'Refusing to send input to a window owned by another process') {
    throw 'Unicode unsafe-operation GUI test must restore verified app focus after modal refusal and validate source panel.'
}

# The primary UTF-16 directory enumeration returns a native find handle.
# It is not a C__Handles member; explicitly register successful opens,
# because the legacy panel closes them through HANDLES(FindClose).
$panelSource = Get-Content -LiteralPath (Join-Path $toolsDir '..\\..\\src\\fileswn3.cpp') -Raw
if ($panelSource -match 'HANDLES(?:_Q)?\s*\(\s*Salamander::FindFirstUnicodePanelFile') {
    throw 'Unicode panel enumeration must not be dispatched as a C__Handles member.'
}
if ($panelSource -notmatch 'search\s*=\s*Salamander::FindFirstUnicodePanelFile\s*\(' -or
    $panelSource -notmatch 'if\s*\(search\s*!=\s*INVALID_HANDLE_VALUE\)\s*HANDLES_ADD\s*\(\s*__htFindFile\s*,\s*__hoFindFirstFile\s*,\s*search\s*\)') {
    throw 'Unicode panel search handles must be tracked before monitored FindClose.'
}

# MSBuild writes intermediate outputs beside .vcxproj files. Those generated
# directories must not block the pipeline's safe Git fast-forward update.
$repository = (Resolve-Path -LiteralPath (Join-Path $toolsDir '..\\..')).ProviderPath
foreach ($generated in @(
    'src/vcxproj/salamander/Debug_x64/test.obj',
    'src/vcxproj/salmon/salamander/Release_x64/test.obj',
    'src/plugins/zip/vcxproj/salamander/Debug_x64/test.obj',
    'src/plugins/7zip/vcxproj/7ZA/salamander/Debug_x64/test.obj',
    'src/plugins/pictview/vcxproj/exif/salamander/Release_x64/test.obj'
)) {
    & git -C $repository check-ignore --quiet -- $generated
    if ($LASTEXITCODE -ne 0) {
        throw "Generated MSBuild output is not ignored: $generated"
    }
}
& git -C $repository check-ignore --quiet -- 'src/plugins/zip/salamander/source.cpp'
if ($LASTEXITCODE -ne 1) {
    throw "Git ignore rules unexpectedly exclude non-build source paths, or git failed (exit $LASTEXITCODE)."
}

. (Join-Path $toolsDir 'Package-Helpers.ps1')

# Prevent CHM builds that display their default page but fail F1 context lookup.
Assert-CoreHelpMappings -Repository $repository

function Assert-Throws {
    param([scriptblock]$Action, [string]$Description)
    $threw = $false
    try { & $Action } catch { $threw = $true }
    if (-not $threw) { throw "Expected failure did not occur: $Description" }
}

$root = Join-Path $env:TEMP ('OpenSal-Package-Tests-' + [guid]::NewGuid().ToString('N'))
$stage = Join-Path $root 'stage'
New-Item -ItemType Directory -Path (Join-Path $stage 'help\english') -Force | Out-Null
try {
    $fakeDumpbin = Join-Path $root 'fake-dumpbin.cmd'
    @'
@echo off
echo Image has the following dependencies:
echo     KERNEL32.dll
echo     vcruntime140.dll
exit /b 0
'@ | Set-Content -LiteralPath $fakeDumpbin -Encoding ascii

    foreach ($filename in @('salamand.exe', 'LICENSE', 'vcruntime140.dll', 'msvcp140.dll')) {
        Set-Content -LiteralPath (Join-Path $stage $filename) -Value 'test fixture' -Encoding ascii
    }
    Assert-Throws { Test-DistributionStage -Stage $stage -Configuration Release -DumpbinExe $fakeDumpbin } 'Missing CHM must fail'

    Set-Content -LiteralPath (Join-Path $stage 'help\english\salamand.chm') -Value 'test fixture' -Encoding ascii
    Test-DistributionStage -Stage $stage -Configuration Release -DumpbinExe $fakeDumpbin
    if (-not (Test-Path -LiteralPath (Join-Path $stage 'SHA256SUMS.txt'))) {
        throw 'SHA256 manifest is missing.'
    }

    Set-Content -LiteralPath (Join-Path $stage 'vcruntime140d.dll') -Value 'test fixture' -Encoding ascii
    Assert-Throws { Test-DistributionStage -Stage $stage -Configuration Release -DumpbinExe $fakeDumpbin } 'Debug runtime must be rejected from Release'

    Remove-Item -LiteralPath (Join-Path $stage 'vcruntime140d.dll')
    Assert-Throws { Test-DistributionStage -Stage $stage -Configuration Debug -DumpbinExe $fakeDumpbin } 'Missing Debug runtime must fail'
    foreach ($filename in @('vcruntime140d.dll', 'msvcp140d.dll', 'ucrtbased.dll', 'INTERNAL-TEST-ONLY.txt')) {
        Set-Content -LiteralPath (Join-Path $stage $filename) -Value 'test fixture' -Encoding ascii
    }
    Test-DistributionStage -Stage $stage -Configuration Debug -DumpbinExe $fakeDumpbin
    Write-Host 'PASS: source parses; required help/runtime checks, release safety and SHA256 manifest work.'
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
