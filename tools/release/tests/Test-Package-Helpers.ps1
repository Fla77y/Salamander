#requires -Version 7.4
# Small deterministic regression suite for package validation.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$toolsDir = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).ProviderPath

# Release downloads must carry an externally verifiable manifest for only
# public Release artifacts, not paths to nonredistributable Debug packages.
$releaseWorkflow = Get-Content -LiteralPath (
    Join-Path $toolsDir '..\..\.github\workflows\pr-release-package.yml') -Raw
$packagingScript = Get-Content -LiteralPath (
    Join-Path $toolsDir 'Update-Build-Test-Package.ps1') -Raw

# All public packages must contain the GPL license and the third-party notices.
# The source notices live in doc/third_party.txt; the staged copy is renamed.
$packageHelperSource = Get-Content -LiteralPath (Join-Path $toolsDir 'Package-Helpers.ps1') -Raw
if (-not $packageHelperSource.Contains('Join-Path $Repository ''doc\third_party.txt''') -or
    -not $packageHelperSource.Contains('Join-Path $Stage ''THIRD_PARTY_LICENSES.txt''') -or
    -not $packageHelperSource.Contains("'LICENSE', 'THIRD_PARTY_LICENSES.txt'")) {
    throw 'Release stage must copy and require both GPL and third-party license notices.'
}
$notices = Join-Path $toolsDir '..\..\doc\third_party.txt'
if (-not (Test-Path -LiteralPath $notices -PathType Leaf) -or
    (Get-Item -LiteralPath $notices).Length -lt 100) {
    throw 'Third-party license notices source is absent or empty.'
}

# PKG-01: a checked build-to-stage SPL manifest gate must run before
# any Release or Debug archive/installer is produced.
# Arrange: inspect the packaging entrypoint (the suite below uses synthetic payloads).
$stageCall = $packagingScript.IndexOf('New-DistributionStage -BuiltDirectory', [StringComparison]::Ordinal)
$payloadGate = $packagingScript.IndexOf('Invoke-PluginCoverageInventory.ps1', [StringComparison]::Ordinal)
$archiveCreation = $packagingScript.IndexOf("Invoke-Checked `$sevenZipExe", [StringComparison]::Ordinal)
$requiredToken = "-RequiredShippedModules @('7zip','checksum','filecomp','renamer','pictview')"
# Act / Assert: missing/bypassed/late gates are a release contract error.
if ($stageCall -lt 0 -or $payloadGate -le $stageCall -or
    $archiveCreation -le $payloadGate -or
    -not $packagingScript.Contains('-RequireMatchingPayloads') -or
    -not $packagingScript.Contains('-RequireSolutionPluginPayloads') -or
    -not $packagingScript.Contains($requiredToken)) {
    throw 'PKG-01: package creation must validate byte-identical mandatory staged SPL modules before archiving.'
}

if (-not $releaseWorkflow.Contains('OpenSal\public-release\SHA256SUMS-Release.txt') -or
    -not $packagingScript.Contains("'SHA256SUMS-Release.txt'") -or
    -not $packagingScript.Contains('OpenSalamander-Release-x64.7z') -or
    -not $packagingScript.Contains('OpenSalamander-Release-x64-Setup.exe') -or
    -not $releaseWorkflow.Contains('Test-ReleaseInstaller.ps1')) {
    throw 'Public Release workflow must verify checksums, run a silent setup/uninstall smoke, and upload the release manifest.'
}


# Pure PE export parser regression: runs in CI without dumpbin, Windows GUI
# or plug-in binaries; it also detects malformed public-name matching.
& (Join-Path $PSScriptRoot 'Test-PluginExport-Parser.ps1')

# Synthetic exact-public-artifact regression (no installer execution).
& (Join-Path $PSScriptRoot 'Test-ReleasePublicArtifact.ps1')
& (Join-Path $PSScriptRoot 'Test-PortableManifest-Regression.ps1')
& (Join-Path $PSScriptRoot 'Test-ReleaseWorkflow-Order.ps1')
& (Join-Path $PSScriptRoot 'Test-InstalledPayload-Regression.ps1')

# Verify child-process-only TEMP isolation against the stale SAL*.tmp dialog.
& (Join-Path $PSScriptRoot 'Test-GuiProcessTemp-Isolation.ps1')
# Prove that an independent clipboard reader can obtain the navigation text
# while the writer's STA thread is synchronously waiting on another process.
& (Join-Path $PSHOME 'pwsh.exe') -Sta -NoLogo -NoProfile -File (Join-Path $PSScriptRoot 'Test-GuiClipboard-Isolation.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Cross-process GUI clipboard isolation regression failed.' }


# Detect a broken optional PictView installation without loading or
# distributing its unavailable proprietary converter components.
& (Join-Path $PSScriptRoot 'Test-PictViewRuntime-Prerequisites.ps1')
# If payload validation fails after installation, the smoke must attempt
# only its test-owned Inno uninstaller before deleting the temporary directory.
$installerSmokeSource = Get-Content -LiteralPath (
    Join-Path $toolsDir 'tests\Test-ReleaseInstaller.ps1') -Raw
if (-not $installerSmokeSource.Contains('$uninstallAttempted') -or
    -not $installerSmokeSource.Contains('Invoke-BoundedSetup -Executable $cleanupUninstaller.FullName')) {
    throw 'Release installer smoke must attempt test-owned uninstall on early validation failures.'
}
$scriptFiles = @(
    (Join-Path $toolsDir 'Package-Helpers.ps1'),
    (Join-Path $toolsDir 'Update-Build-Test-Package.ps1'),
    (Join-Path $toolsDir 'Invoke-PluginCoverageInventory.ps1'),
    (Join-Path $toolsDir 'Plugin-CoverageInventory.ps1'),
    (Join-Path $toolsDir 'Plugin-Export-Parser.ps1'),
    (Join-Path $toolsDir 'tests\Test-PluginCoverageInventory.ps1'),
    (Join-Path $toolsDir 'tests\Test-PluginExport-Parser.ps1'),
    (Join-Path $toolsDir 'tests\Test-PluginBinary-Contract.ps1'),
    (Join-Path $toolsDir 'tests\Test-VS2026-ProjectMetadata.ps1'),
    (Join-Path $toolsDir 'tests\LegacyConfig-Canary.ps1'),
    (Join-Path $toolsDir 'tests\Test-LegacyConfig-Canary.ps1'),
    (Join-Path $toolsDir 'tests\LegacyFind-GuiCases.ps1'),
    (Join-Path $toolsDir 'tests\Test-LegacyFind-UiContract.ps1'),
    (Join-Path $toolsDir 'tests\Test-GuiConfig-Isolation.ps1'),
    (Join-Path $toolsDir '..\Manage-Salamander.ps1'),
    (Join-Path $toolsDir 'tests\Test-ReleaseChecksumManifest.ps1'),
    (Join-Path $toolsDir 'tests\Test-ReleaseInstaller.ps1'),
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

# Arrange: inspect the actual management CLI and load only its pure
# --test-all selection helpers. Never run the manager or launch a GUI here.
$managerPath = Join-Path $toolsDir '..\Manage-Salamander.ps1'
$managerTokens = $null
$managerErrors = $null
$managerAst = [System.Management.Automation.Language.Parser]::ParseFile(
    $managerPath, [ref]$managerTokens, [ref]$managerErrors)
if (@($managerErrors).Count -gt 0) {
    throw "Management CLI parse errors: $($managerErrors -join '; ')"
}
foreach ($name in @('Expand-AutomatedTestActions', 'Get-AutomatedGuiModes')) {
    $definition = @($managerAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -ceq $name
    }, $true))
    if ($definition.Count -ne 1) {
        throw "Expected one pure management test selector '$name'."
    }
    . ([scriptblock]::Create($definition[0].Extent.Text))
}

$managerSource = Get-Content -LiteralPath $managerPath -Raw
# Local acceptance logs must capture the actual checkout revision and whether
# tracked source changes are present; do not mistake a checkout SHA for an
# attestation of the pre-existing built binaries.
if (-not $managerSource.Contains('Source checkout git HEAD:') -or
    -not $managerSource.Contains('Source tracked working tree clean:') -or
    -not $managerSource.Contains('rev-parse --verify HEAD') -or
    -not $managerSource.Contains('status --porcelain --untracked-files=no')) {
    throw 'Management transcript must identify the source checkout revision and tracked changes.'
}
$optionDeclaration = [regex]::Match($managerSource, '(?s)\$validOptions\s*=\s*@\((.*?)\)')
if (-not $optionDeclaration.Success) { throw 'Management CLI option registry is missing.' }
$registeredOptions = @([regex]::Matches($optionDeclaration.Groups[1].Value, "'([^']+)'") |
    ForEach-Object { $_.Groups[1].Value })
$guiModes = @($registeredOptions | Where-Object {
    $_.StartsWith('--test-gui', [StringComparison]::OrdinalIgnoreCase) -and
    $_ -ne '--test-gui-manual'
})
if ($guiModes.Count -lt 1 -or $registeredOptions -notcontains '--test-all') {
    throw '--test-all and automated GUI options must be registered.'
}

# Act: expand --test-all, including a hypothetical later GUI scenario.
$selected = [System.Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
[void]$selected.Add('--test-all')
$futureOption = '--test-gui-future-regression'
Expand-AutomatedTestActions -RequestedSet $selected -AvailableOptions @(
    $registeredOptions + $futureOption)
$allModes = @(Get-AutomatedGuiModes -RequestedSet $selected)

# Assert: all registered and future automated tests, but no manual/setup/run
# actions, are selected; full suite covers both binary configurations.
foreach ($required in @('--test', '--test-pictview', '--test-pictview-window',
                       '--test-plugin-exports', $futureOption) + $guiModes) {
    if (-not $selected.Contains($required)) {
        throw "--test-all failed to include automated test '$required'."
    }
}
foreach ($excluded in @('--test-gui-manual', '--setup', '--run', '--build', '--update')) {
    if ($selected.Contains($excluded)) {
        throw "--test-all unexpectedly enables non-test action '$excluded'."
    }
}
if ($allModes.Count -ne 2 -or $allModes[0] -cne 'Release' -or
    $allModes[1] -cne 'Debug') {
    throw '--test-all must exercise Release and Debug x64 by default.'
}
foreach ($variant in @('Debug', 'Release')) {
    $single = [System.Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    [void]$single.Add('--test-all')
    [void]$single.Add("--$($variant.ToLowerInvariant())")
    $modes = @(Get-AutomatedGuiModes -RequestedSet $single)
    if ($modes.Count -ne 1 -or $modes[0] -cne $variant) {
        throw "--test-all --$($variant.ToLowerInvariant()) must select only $variant."
    }
}

$withoutAll = [System.Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
[void]$withoutAll.Add('--test-gui-baseline')
Expand-AutomatedTestActions -RequestedSet $withoutAll -AvailableOptions $registeredOptions
if ($withoutAll.Count -ne 1 -or -not $withoutAll.Contains('--test-gui-baseline')) {
    throw 'Existing individual GUI test switches must not be expanded.'
}
# Include the entire automated GUI dispatch loop. Starting at a specific
# test mode would silently omit any mode registered before that mode.
$guiSectionStart = $managerSource.IndexOf(
    'foreach ($guiMode in $automatedGuiModes) {',
    [StringComparison]::Ordinal)
$manualStart = $managerSource.IndexOf(
    'if ($requestedSet.Contains(''--test-gui-manual''))',
    [StringComparison]::Ordinal)
if ($guiSectionStart -lt 0 -or $manualStart -le $guiSectionStart -or
    $managerSource -notmatch 'foreach \(\$guiMode in \$automatedGuiModes\)' -or
    $managerSource -notmatch 'Expand-AutomatedTestActions -RequestedSet \$requestedSet -AvailableOptions \$validOptions') {
    throw '--test-all must route through existing automated GUI dispatch and normal test action.'
}
$guiDispatch = $managerSource.Substring($guiSectionStart, $manualStart - $guiSectionStart)
foreach ($option in $guiModes) {
    if (-not $guiDispatch.Contains(('$requestedSet.Contains(''{0}'')' -f $option))) {
        throw "Automated GUI mode '$option' is not wired to the existing dispatcher."
    }
}
if ($guiDispatch -notmatch 'Get-VariantDirectory \$guiMode' -or
    $guiDispatch -match 'Get-VariantDirectory \$configuration') {
    throw 'Automated GUI tests must run against the selected Release/Debug binary.'
}
Write-Host 'PASS: --test-all expands all automated suites, excludes manual actions and selects both x64 modes.'


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

# The F8 deletion test must be a real GUI operation on a nested long Unicode
# fixture, not merely a .NET cleanup check after test completion.
if ($guiDriver -notmatch '\[switch\]\$TemporaryDirectoryDeletionOnly' -or
    $guiDispatch -notmatch "'-TemporaryDirectoryDeletionOnly'" -or
    $guiDriver -notmatch 'if \(\$TemporaryDirectoryDeletionOnly\)' -or
    $guiDriver -notmatch 'Wait-Until \{ -not \[IO\.Directory\]::Exists\(\$temporaryDirectory\) \}' -or
    $guiDriver -notmatch "Send-Keys '\{F8\}'") {
    throw 'GUI temporary long-path directory deletion regression is not correctly registered or asserted.'
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
# Arrange: each diagnostic belongs to the correct GUI driver function.
# Regressions must not silently lose formatted PID/HWND/error details.
$diagnostics = @(
    @{ Function = 'Focus-TestProcess'; Prefix = '{0}: Cannot activate verified Salamander HWND=0x{1:X} PID={2} ' },
    @{ Function = 'Invoke-SalamanderCommand'; Prefix = 'Salamander command {0} did not complete' },
    @{ Function = 'Go-ToPath'; Prefix = 'GUI navigation failed: {0}' },
    @{ Function = '<main>'; Prefix = 'GUI startup failed: {0}' }
)
foreach ($diagnostic in $diagnostics) {
    # Act: inspect the diagnostic throw within its own function, not another
    # unrelated error message or a comment elsewhere in the driver.
    $functionPattern = '(?ms)^function\s+' + [regex]::Escape($diagnostic.Function) +
                       '\s*\{(?<body>.*?)(?=^function\s+|\z)'
    $body = if ($diagnostic.Function -eq '<main>') {
        $guiDriver
    }
    else {
        [regex]::Match($guiDriver, $functionPattern).Groups['body'].Value
    }
    $formatPattern = '(?s)throw\s+\(\(\s*"' +
                     [regex]::Escape($diagnostic.Prefix) + '.*?\)\s*-f\s'
    # Assert: the full diagnostic is formatted before it is thrown.
    # Startup diagnostics are formatted into a variable before additional
    # isolated-startup details are appended at the throw site.
    if ($diagnostic.Function -eq '<main>') {
        $startupFormat = '(?s)\$startupMessage\s*=\s*\(\(\s*"' +
                         [regex]::Escape($diagnostic.Prefix) +
                         '.*?\)\s*-f\s+.*?\)'
        $startupThrow = 'throw\s*\(\$startupMessage\s*\+'
        if ($body -notmatch $startupFormat -or $body -notmatch $startupThrow) {
            throw 'GUI startup diagnostic must format its complete message before appending isolation details.'
        }
        continue
    }
    if ([string]::IsNullOrEmpty($body) -or $body -notmatch $formatPattern) {
        throw "GUI diagnostics must format the entire error message in $($diagnostic.Function): $($diagnostic.Prefix)"
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


# GUI tests are unattended: start only after the GUI message loop is idle,
# and never send keyboard input to another process. A lost focus may be
# restored only to the previously verified test HWND and only if no Salamander
# modal dialog is awaiting input.
$startupBlock = [regex]::Match(
    $guiDriver,
    '(?s)\$process = Start-Process(.*?)\n    Go-ToPath \$source'
).Groups[1].Value
$sendKeysBlock = [regex]::Match(
    $guiDriver,
    '(?s)function Send-Keys\s*\{(.*?)\n\}'
).Groups[1].Value
if ([string]::IsNullOrEmpty($startupBlock) -or
    $startupBlock -notmatch '\.WaitForInputIdle\(' -or
    [string]::IsNullOrEmpty($sendKeysBlock) -or
    $sendKeysBlock -notmatch 'Get-TestDialog' -or
    $sendKeysBlock -notmatch 'Focus-TestProcess' -or
    $sendKeysBlock -notmatch 'Refusing to send input' -or
    $sendKeysBlock -notmatch '\[Windows\.Forms\.SendKeys\]::SendWait') {
    throw 'Unattended GUI tests require startup idle verification and guarded foreground recovery.'
}


# The baseline must prove keyboard focus, not merely a synchronous clipboard
# WM_COMMAND. Without this assertion a user click could conceal a focus bug.
$baselineCheck = [regex]::Match(
    $guiDriver,
    '(?s)Write-Host ''PASS: GUI driver can navigate a normal short directory''(.*?)\n    if \(\$ShortOperationsOnly\) \{'
).Groups[1].Value
if ([string]::IsNullOrEmpty($baselineCheck) -or
    $baselineCheck -notmatch "Send-Keys '\{END\}'" -or
    $baselineCheck -notmatch 'Read-FocusedFilename' -or
    $guiDriver -notmatch '\$focusProbeName\s*=\s*''focus-probe.txt''') {
    throw 'GUI baseline must verify real focused-file keyboard navigation.'
}

# Unicode clipboard navigation must preserve exact ACP round-trips.
# Both text formats are scanned only within the actual HGLOBAL size;
# missing terminators or lossy conversions must be rejected, never
# truncated into a different (possibly existing) disk path.
$pasteCode = Get-Content -LiteralPath (Join-Path $toolsDir '..\\..\\src\\fileswn9.cpp') -Raw
$pasteBlock = [regex]::Match(
    $pasteCode,
    '(?s)void CFilesWindow::ClipboardPastePath\(\)(.*?)void CFilesWindow::ChangeFilter'
).Groups[1].Value
if ([string]::IsNullOrEmpty($pasteBlock) -or
    $pasteBlock -match 'buff\[0\] != 0 && GetLastError\(\) == ERROR_INSUFFICIENT_BUFFER' -or
    $pasteBlock -notmatch 'unicodeTextPresent' -or
    $pasteBlock -notmatch 'GlobalSize\(handle\)' -or
    $pasteBlock -notmatch 'while \(length < limit && text\[length\]' -or
    $pasteBlock -notmatch 'if \(length < limit\)' -or
    $pasteBlock -notmatch 'unicodePath\.assign\(text \+ begin, length - begin\)' -or
    $pasteBlock -notmatch 'if \(!unicodeTextPresent\)' -or
    $pasteBlock -notmatch 'clipboardPath\.assign\(text \+ begin, length - begin\)') {
    throw 'Clipboard navigation must reject incomplete Unicode and ANSI clipboard paths.'
}

# WC_NO_BEST_FIT_CHARS is invalid when the active ANSI code page is
# UTF-8 (ACP 65001). The exact Unicode round-trip identity check remains
# mandatory; Win32's CP_ACP conversion itself must use supported flags.
$unicodeNameSource = Get-Content -LiteralPath (Join-Path $toolsDir '..\..\src\common\win32_unicode_panel_name.h') -Raw
$ansiProjection = [regex]::Match($unicodeNameSource, '(?s)inline bool TryMakeExactAnsiPanelPath\((.*?)inline bool UnicodePanelPathAffected').Value
if ($ansiProjection -match 'WideCharToMultiByte\(CP_ACP,\s*WC_NO_BEST_FIT_CHARS' -or
    $ansiProjection -notmatch 'WideCharToMultiByte\(CP_ACP,\s*0,' -or
    $ansiProjection -notmatch 'IsExactAnsiName' -or
    $pasteBlock -notmatch 'TryMakeExactAnsiPanelPath\(unicodePath, clipboardPath\)') {
    throw 'Clipboard Unicode conversion must work with UTF-8 ACP and retain exact filename identity.'
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

# The old transfer engine uses fixed ANSI destination buffers too. A short
# source with a LONG target is as unsafe as a long source. F5/F6 must route
# both cases exclusively through the W-backed preflight or refuse.
$filesActionSource = Get-Content -LiteralPath (Join-Path $toolsDir '..\..\src\fileswn8.cpp') -Raw
$filesActionBlock = [regex]::Match($filesActionSource,
    '(?s)void CFilesWindow::FilesAction\(CActionType type, CFilesWindow\* target, int countSizeMode\)(.*?)// restore DefaultDir').Groups[1].Value
if ([string]::IsNullOrEmpty($filesActionBlock) -or
    $filesActionBlock -notmatch 'target->HasLongDiskPath\(\)' -or
    $filesActionBlock -notmatch 'TryUnicodeSingleFileTransfer' -or
    $filesActionBlock -notmatch 'TryUnicodeSingleDirectoryMove' -or
    $filesActionBlock -notmatch 'return;') {
    throw 'F5/F6 must not reach the ANSI engine with a long target panel.'
}

# CM_CLIPPASTE first checks for files, then falls back to clipboard text path
# navigation. Route supported file transfers to the Unicode transfer path.
# Plain CF_UNICODETEXT must still reach the navigation fallback without a dialog.
$pasteSource = Get-Content -LiteralPath (Join-Path $toolsDir '..\..\src\fileswn9.cpp') -Raw
$pasteBlock = [regex]::Match($pasteSource,
    '(?s)BOOL CFilesWindow::ClipboardPaste\(BOOL onlyLinks, BOOL onlyTest, const char\* pastePath\)(.*?)BOOL CFilesWindow::ClipboardPasteToArcOrFS').Groups[1].Value
if ([string]::IsNullOrEmpty($pasteBlock) -or
    $pasteBlock -notmatch 'HasLongDiskPath\(\)' -or
    $pasteBlock -notmatch 'strlen\(pastePath\) >= MAX_PATH' -or
    $pasteBlock -notmatch 'EnumFormatEtc\(DATADIR_GET' -or
    $pasteBlock -notmatch 'CF_HDROP' -or
    $pasteBlock -notmatch 'CFSTR_SHELLIDLIST' -or
    $pasteBlock -notmatch 'CFSTR_FILECONTENTS' -or
    $pasteBlock -notmatch 'IsFakeDataObject' -or
    $pasteBlock -notmatch 'if \(onlyTest \|\| !hasFilePayload\)' -or
    $pasteBlock -notmatch 'return onlyTest && canTransfer;' -or
    $pasteBlock -notmatch 'ReadUnicodeClipboardFiles\(' -or
    $pasteBlock -notmatch 'TryTransferUnicodeClipboardFiles\(' -or
    $pasteBlock -notmatch 'return TRUE;') {
    throw 'Long-target clipboard paste must keep text navigation separate from Unicode file transfers.'
}

# Long plain-text clipboard paths must not be truncated to the old
# 2*MAX_PATH scratch buffer; use exact, bounded conversion before reaching
# the dynamic disk panel. Retain the bounded legacy post-processor only for
# inputs that actually fit its contract.
$clipboardNav = [regex]::Match($pasteSource,
    '(?s)void CFilesWindow::ClipboardPastePath\(\)(.*?)void CFilesWindow::ChangeFilter').Groups[1].Value
if ([string]::IsNullOrEmpty($clipboardNav) -or
    $clipboardNav -notmatch 'GlobalSize\(handle\)' -or
    $clipboardNav -notmatch 'std::string clipboardPath' -or
    $clipboardNav -notmatch 'TryMakeExactAnsiPanelPath' -or
    $clipboardNav -notmatch 'ChangeUnicodePathToDisk\(HWindow, unicodePath\)' -or
    $clipboardNav -notmatch 'clipboardPath\.size\(\) < 2 \* MAX_PATH' -or
    $clipboardNav -notmatch 'ChangeDir\(path\.c_str\(\)\)' -or
    $clipboardNav -notmatch 'driveAbsolute \|\| uncAbsolute') {
    throw 'Unicode clipboard navigation must retain complete, verified absolute paths beyond 2*MAX_PATH.'
}

# The disk listing scratch buffer is now dynamic. Preserve its previous
# minimum size for extension processing and require explicit raw-pointer access.
# Native Windows compilation remains the authoritative check for C++ types.
if ($panelSource -notmatch 'std::vector<char>\s+fileName\s*\(\s*\(pathLen\s*>\s*MAX_PATH\s*\?\s*pathLen\s*:\s*MAX_PATH\)\s*\+\s*4\s*\)' -or
    $panelSource -match 'strlen\s*\(\s*fileName\s*\)' -or
    $panelSource -match 'char\s*\*\s*st\s*=\s*fileName\s*;' -or
    $panelSource -match '(?m)^\s*st\s*=\s*fileName\s*;') {
    throw 'Dynamic panel scratch buffer must retain its minimum capacity and expose .data() to legacy pointer APIs.'
}

# Switching away from a long disk panel updates BOTH panels' DefaultDir
# entries. The legacy entries have fixed ANSI capacity; neither panel may
# write its long path into them, even when it is the inactive panel.
$mainWindowSource = Get-Content -LiteralPath (Join-Path $toolsDir '..\..\src\mainwnd1.cpp') -Raw
$defaultDirBlock = [regex]::Match(
    $mainWindowSource,
    '(?s)void CMainWindow::UpdateDefaultDir\(BOOL activePrefered\)(.*?)BOOL CMainWindow::ToggleTopToolBar'
).Groups[1].Value
if ([string]::IsNullOrEmpty($defaultDirBlock) -or
    $defaultDirBlock -notmatch 'active->HasLongDiskPath\(\)' -or
    $defaultDirBlock -notmatch 'nonactive->HasLongDiskPath\(\)' -or
    ([regex]::Matches($defaultDirBlock, 'strcpy\(DefaultDir\[')).Count -ne 2) {
    throw 'Long panel paths must not overwrite either fixed-size DefaultDir entry during TAB switching.'
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

# Reject absent installer before creating a temporary install directory.
$missingInstaller = Join-Path $env:TEMP ('OpenSal-missing-setup-' + [Guid]::NewGuid().ToString('N') + '.exe')
Assert-Throws {
    & (Join-Path $toolsDir 'tests\Test-ReleaseInstaller.ps1') -InstallerPath $missingInstaller
} 'Installer smoke must fail closed for a nonexistent setup executable'

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

    foreach ($filename in @('salamand.exe', 'LICENSE', 'THIRD_PARTY_LICENSES.txt', 'vcruntime140.dll', 'msvcp140.dll')) {
        Set-Content -LiteralPath (Join-Path $stage $filename) -Value 'test fixture' -Encoding ascii
    }
    Assert-Throws { Test-DistributionStage -Stage $stage -Configuration Release -DumpbinExe $fakeDumpbin } 'Missing CHM must fail'

    Set-Content -LiteralPath (Join-Path $stage 'help\english\salamand.chm') -Value 'test fixture' -Encoding ascii
    $requiredPictViewFiles = @(
        'plugins\pictview\pictview.spl',
        'plugins\pictview\lang\english.slg',
        'plugins\pictview\exif.dll'
    )
    foreach ($required in $requiredPictViewFiles) {
        $fixtureFile = Join-Path $stage $required
        New-Item -ItemType Directory -Path (Split-Path -Parent $fixtureFile) -Force | Out-Null
        Set-Content -LiteralPath $fixtureFile -Value 'test fixture' -Encoding ascii
    }
    Test-DistributionStage -Stage $stage -Configuration Release -DumpbinExe $fakeDumpbin
    # Regression: a Release package without third-party notices must fail
    # before archiving even when all binaries and other resources are present.
    $noticesFixture = Join-Path $stage 'THIRD_PARTY_LICENSES.txt'
    Remove-Item -LiteralPath $noticesFixture -Force
    Assert-Throws {
        Test-DistributionStage -Stage $stage -Configuration Release -DumpbinExe $fakeDumpbin
    } 'Release stage must reject missing third-party license notices'
    Set-Content -LiteralPath $noticesFixture -Value 'test fixture' -Encoding ascii
    foreach ($required in $requiredPictViewFiles) {
        $fixtureFile = Join-Path $stage $required
        Remove-Item -LiteralPath $fixtureFile -Force
        Assert-Throws {
            Test-DistributionStage -Stage $stage -Configuration Release -DumpbinExe $fakeDumpbin
        } "Release stage must require PictView file $required"
        Set-Content -LiteralPath $fixtureFile -Value 'test fixture' -Encoding ascii
    }
    if (-not (Test-Path -LiteralPath (Join-Path $stage 'SHA256SUMS.txt'))) {
        throw 'SHA256 manifest is missing.'
    }

    # Release output must never publish link intermediates or private
    # debug symbols. Place each forbidden file in a plug-in subdirectory,
    # because checking only the stage root misses the real regression.
    $nestedPlugin = Join-Path $stage 'plugins\pictview'
    New-Item -ItemType Directory -Path $nestedPlugin -Force | Out-Null
    foreach ($extension in @('.pdb', '.lib', '.exp')) {
        $intermediate = Join-Path $nestedPlugin ('pictview' + $extension)
        Set-Content -LiteralPath $intermediate -Value 'test fixture' -Encoding ascii
        Assert-Throws {
            Test-DistributionStage -Stage $stage -Configuration Release -DumpbinExe $fakeDumpbin
        } "Release package must reject nested $extension build artifacts"
        Remove-Item -LiteralPath $intermediate -Force
    }

    Set-Content -LiteralPath (Join-Path $stage 'vcruntime140d.dll') -Value 'test fixture' -Encoding ascii
    Assert-Throws { Test-DistributionStage -Stage $stage -Configuration Release -DumpbinExe $fakeDumpbin } 'Debug runtime must be rejected from Release'

    Remove-Item -LiteralPath (Join-Path $stage 'vcruntime140d.dll')
    Assert-Throws { Test-DistributionStage -Stage $stage -Configuration Debug -DumpbinExe $fakeDumpbin } 'Missing Debug runtime must fail'
    foreach ($filename in @('vcruntime140d.dll', 'msvcp140d.dll', 'ucrtbased.dll', 'INTERNAL-TEST-ONLY.txt')) {
        Set-Content -LiteralPath (Join-Path $stage $filename) -Value 'test fixture' -Encoding ascii
    }
    Test-DistributionStage -Stage $stage -Configuration Debug -DumpbinExe $fakeDumpbin
    # Verify the distributable manifest against real fixture bytes, including
    # malicious or accidental changes after packaging.
    $public = Join-Path $root 'public'
    New-Item -ItemType Directory -Path $public -Force | Out-Null
    $archiveName = 'OpenSalamander-Release-x64.7z'
    $setupName = 'OpenSalamander-Release-x64-Setup.exe'
    $archiveFile = Join-Path $public $archiveName
    $setupFile = Join-Path $public $setupName
    Set-Content -LiteralPath $archiveFile -Value 'sample portable bytes' -Encoding ascii
    Set-Content -LiteralPath $setupFile -Value 'sample installer bytes' -Encoding ascii
    $publicHashes = @(
        '{0} *{1}' -f (Get-FileHash -LiteralPath $archiveFile -Algorithm SHA256).Hash.ToLowerInvariant(), $archiveName
        '{0} *{1}' -f (Get-FileHash -LiteralPath $setupFile -Algorithm SHA256).Hash.ToLowerInvariant(), $setupName
    )
    $publicManifest = Join-Path $public 'SHA256SUMS-Release.txt'
    $verifier = Join-Path $toolsDir 'tests\Test-ReleaseChecksumManifest.ps1'
    $publicHashes | Set-Content -LiteralPath $publicManifest -Encoding ascii
    & $verifier -DistributionDirectory $public

    # Act/Assert: tampering, duplicates, Debug references and missing files
    # are rejected rather than reported as verified public downloads.
    Set-Content -LiteralPath $archiveFile -Value 'tampered content' -Encoding ascii
    Assert-Throws { & $verifier -DistributionDirectory $public } 'Tampered public Release archive must fail'
    Set-Content -LiteralPath $archiveFile -Value 'sample portable bytes' -Encoding ascii
    @($publicHashes[0], $publicHashes[0]) |
        Set-Content -LiteralPath $publicManifest -Encoding ascii
    Assert-Throws { & $verifier -DistributionDirectory $public } 'Duplicate Release entry must fail'
    @($publicHashes[0], ('{0} *OpenSalamander-Debug-x64.7z' -f ('0' * 64))) |
        Set-Content -LiteralPath $publicManifest -Encoding ascii
    Assert-Throws { & $verifier -DistributionDirectory $public } 'Debug entry in public checksum file must fail'
    $publicHashes | Set-Content -LiteralPath $publicManifest -Encoding ascii
    Remove-Item -LiteralPath $setupFile -Force
    Assert-Throws { & $verifier -DistributionDirectory $public } 'Missing public installer must fail'
    Write-Host 'PASS: public artifact checksum validation rejects tampering, duplicates, Debug entries and missing files.'
    Write-Host 'PASS: source parses; required help/runtime checks, release safety and SHA256 manifest work.'
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}


# A legacy or imported Default Directories registry entry may exceed the
# fixed MAX_PATH storage used by DefaultDir. Its presence must not stop GUI
# startup with a modal ERROR_MORE_DATA dialog or erase the original setting
# on a subsequent configuration save.
$startupSource = Get-Content -LiteralPath (
    Join-Path $toolsDir '..\..\src\mainwnd2.cpp') -Raw
$defaultDirectoriesRead = [regex]::Match(
    $startupSource,
    '(?s)ZeroMemory\(PreserveUnsupportedDefaultDir, sizeof\(PreserveUnsupportedDefaultDir\)\);\s+if \(OpenKey\(salamander, SALAMANDER_DEFDIRS_REG, actKey\)\)(.*?)//---  password manager'
).Groups[1].Value
$defaultDirectoriesWrite = [regex]::Match(
    $startupSource,
    '(?s)//---  default directories\s+if \(CreateKey\(salamander, SALAMANDER_DEFDIRS_REG, actKey\)\)(.*?)//---  password manager'
).Groups[1].Value
if ([string]::IsNullOrEmpty($defaultDirectoriesRead) -or
    [string]::IsNullOrEmpty($defaultDirectoriesWrite) -or
    $defaultDirectoriesRead -notmatch 'ReadLegacyDefaultDirectory' -or
    $defaultDirectoriesRead -match 'RegEnumValue|RegQueryInfoKey' -or
    $defaultDirectoriesRead -notmatch 'PreserveUnsupportedDefaultDir' -or
    $defaultDirectoriesWrite -notmatch 'PreserveUnsupportedDefaultDir') {
    throw 'Default directory loading must use bounded per-drive registry reads and preserve unsupported entries.'
}
Write-Host 'PASS: default-directory startup reads use bounded per-drive access and preserve unsupported values.'


# Persisted panel paths may exceed MAX_PATH: both the read and the restore
# operation must use owned dynamic storage, bypassing fixed-size recovery.
$panelLoad = [regex]::Match(
    $startupSource,
    '(?s)void CMainWindow::LoadPanelConfig\((.*?)void LoadIconOvrlsInfo'
).Value
if ([string]::IsNullOrEmpty($panelLoad) -or
    $panelLoad -notmatch 'ReadSavedPanelPath\(actKey, panelPath\)' -or
    $panelLoad -match 'GetValue\(actKey, PANEL_PATH_REG, REG_SZ, panelPath, MAX_PATH\)' -or
    $startupSource -notmatch 'std::wstring leftPanelPath\(fallback\)' -or
    $startupSource -notmatch 'std::wstring rightPanelPath\(fallback\)' -or
    $startupSource -notmatch 'RestoreSavedPanelPath\(LeftPanel, leftPanelPath\)' -or
    $startupSource -notmatch 'RestoreSavedPanelPath\(RightPanel, rightPanelPath\)' -or
    $startupSource -notmatch 'if \(savedPath\.size\(\) >= MAX_PATH - 2 \|\|' -or
    $startupSource -notmatch 'ChangeUnicodePathToDisk\(panel->HWindow, savedPath\)' -or
    $startupSource -notmatch 'RegistryWorkerThread\.SetPanelPath\(actKey, panelPath\)') {
    throw 'Saved panel paths must load dynamically and use the long-path navigation branch.'
}
Write-Host 'PASS: saved panel paths use dynamic configuration storage and long-path startup navigation.'

# Regression: CM_CLIPCOPYNAME publishes no filename when the '..' row is
# focused. Folder discovery must skip that synthetic parent row before reading.
$guiPath = Join-Path $toolsDir 'tests\Test-SalamanderGui-LongPaths.ps1'
$guiTokens = $null
$guiErrors = $null
$guiAst = [System.Management.Automation.Language.Parser]::ParseFile(
    $guiPath, [ref]$guiTokens, [ref]$guiErrors)
if (@($guiErrors).Count -gt 0) { throw 'GUI driver has PowerShell parser errors.' }
$focusFunctions = @($guiAst.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -ceq 'Focus-DirectoryRow'
}, $true))
if ($focusFunctions.Count -ne 1) { throw 'Expected one Focus-DirectoryRow function.' }
. ([scriptblock]::Create($focusFunctions[0].Extent.Text))

# Arrange: moving Home selects the synthetic '..' row, which cannot publish a filename.
$script:focusProbeRows = @('..', 'target-directory', 'another-directory')
$script:focusProbeIndex = -1
function Send-Keys {
    param([string]$Keys)
    switch ($Keys) {
        '{HOME}' { $script:focusProbeIndex = 0; break }
        '{DOWN}' { $script:focusProbeIndex++; break }
        default { throw "Unexpected keyboard input in directory-focus regression: $Keys" }
    }
}
function Read-FocusedFilename {
    $name = $script:focusProbeRows[$script:focusProbeIndex]
    if ($name -ceq '..') {
        throw "CM_CLIPCOPYNAME did not publish a filename for '..'."
    }
    return $name
}

# Act: locate the first real directory without reading the synthetic parent row.
Focus-DirectoryRow -Name 'target-directory'

# Assert: the actual target row, not '..', is focused.
if ($script:focusProbeIndex -ne 1) {
    throw 'Directory focus must skip the synthetic parent row and select the expected folder.'
}
Write-Host 'PASS: directory row discovery skips the synthetic parent row before copying names.'

# Arrange: the actual Windows near-limit regression must be compiled/executed
# by --test, while the GUI path must remain a separate real-app check.
$maxPathCpp = Join-Path $toolsDir '..\..\tools\tests\win32_max_path.cpp'
$maxPathSource = Get-Content -LiteralPath $maxPathCpp -Raw
if ($managerSource -notmatch [regex]::Escape("'tools\tests\win32_max_path.cpp'") -or
    $maxPathSource -notmatch 'targetLength\s*=\s*32700' -or
    $maxPathSource -notmatch 'filename\.size\(\) != 255' -or
    $maxPathSource -notmatch 'TryEnumerateLongDirectory' -or
    $maxPathSource -notmatch 'TryCopyUnicodeFileNoOverwrite' -or
    $maxPathSource -notmatch 'TryMoveUnicodeFileNoOverwrite' -or
    $maxPathSource -notmatch 'TryDeleteUnicodeFile' -or
    $maxPathSource -notmatch 'DisposableFixture') {
    throw 'Near-maximum real Win32 path test must cover Unicode 255-unit names, 32700-unit paths, real I/O and cleanup.'
}

# Act / Assert: --test-all automatically includes the near-limit GUI mode
# and it must dispatch the real GUI driver, not just the .NET test fixture.
if ($registeredOptions -notcontains '--test-gui-max-path' -or
    $guiDriver -notmatch '\[switch\]\$MaximumPathOnly' -or
    $guiDriver -notmatch '\$requestedLength\s*=\s*32700' -or
    $guiDriver -notmatch 'Read-FocusedFullname' -or
    $managerSource -notmatch "'-MaximumPathOnly'") {
    throw 'Real Salamander maximum-path GUI mode is missing from --test-all.'
}
Write-Host 'PASS: near-maximum path regression is wired into the manager and real GUI gate.'

# A crash while navigating a 32K long directory must not trigger another
# buffer overrun inside the bug reporter's 1024-byte static output buffer.
$bugReportSource = Get-Content -LiteralPath (
    Join-Path $toolsDir '..\..\src\bugreprt.cpp') -Raw
$managerText = Get-Content -LiteralPath (
    Join-Path $toolsDir '..\Manage-Salamander.ps1') -Raw
if ($bugReportSource -notmatch 'FormatBugReportPanelPath\(' -or
    $bugReportSource -match 'sprintf\s*\(\s*buf\s*,\s*"Path = %s"' -or
    $managerText -notmatch [regex]::Escape("'tools\tests\bug_report_path.cpp'")) {
    throw 'Crash-report path must be bounded and its 32444-byte regression executed by --test.'
}
Write-Host 'PASS: crash-report panel-path formatting is bounded and registered for real C++ regression.'

# The Debug x64 RTC #1 regression: the directory caption previously
# truncated a potentially >65,535-pixel width to WORD, while its clickable
# breadcrumbs could copy >MAX_PATH bytes into a fixed stack buffer.
# Long disk paths must retain text measurements without unsafe hit targets.
$statusHeader = Get-Content -LiteralPath (
    Join-Path $toolsDir '..\..\src\stswnd.h') -Raw
$statusImpl = Get-Content -LiteralPath (
    Join-Path $toolsDir '..\..\src\stswnd.cpp') -Raw
$statusHotTrack = [regex]::Match($statusHeader,
    '(?s)struct CHotTrackItem\s*\{(.*?)\};').Groups[1].Value
$buildHotTrack = [regex]::Match($statusImpl,
    '(?s)void CStatusWindow::BuildHotTrackItems\(\)\s*\{(.*?)void CStatusWindow::DestroyWindow\(').Groups[1].Value
$longPathGuard = 'if\s*\(FilesWindow->Is\(ptDisk\)\s*&&\s*FilesWindow->HasLongDiskPath\(\)\)'
if ([string]::IsNullOrEmpty($statusHotTrack) -or
    [string]::IsNullOrEmpty($buildHotTrack) -or
    $statusHotTrack -notmatch 'int\s+PixelsOffset\s*;' -or
    $statusHotTrack -notmatch 'int\s+Pixels\s*;' -or
    $statusHotTrack -notmatch 'int\s+Chars\s*;' -or
    $buildHotTrack -notmatch $longPathGuard -or
    $buildHotTrack -match '\(WORD\)\s*(AlpDX|sOffset\.cx|sSub\.cx)' -or
    $buildHotTrack -notmatch 'else if\s*\(FilesWindow->Is\(ptDisk\)\s*\|\|\s*FilesWindow->Is\(ptZIPArchive\)\)') {
    throw 'Status hot-track geometry must retain full pixel widths and disable unsafe clickable long-disk paths.'
}
Write-Host 'PASS: 32700-unit GUI paths avoid 16-bit hot-track loss and unsafe MAX_PATH breadcrumbs.'


# Regression contracts for the search and plugin safety review (F1–F8).
# These are source-level safety gates; behavioral Win32 tests are separate.
$findDialog1 = Get-Content -LiteralPath (Join-Path $toolsDir '..\..\src\finddlg1.cpp') -Raw
$findDialog2 = Get-Content -LiteralPath (Join-Path $toolsDir '..\..\src\finddlg2.cpp') -Raw
$findSearch = Get-Content -LiteralPath (Join-Path $toolsDir '..\..\src\find.cpp') -Raw
$renameMenu = Get-Content -LiteralPath (Join-Path $toolsDir '..\..\src\plugins\renamer\menu.cpp') -Raw
$renameDialog = Get-Content -LiteralPath (Join-Path $toolsDir '..\..\src\plugins\renamer\rendlg.cpp') -Raw
$checksumDialogs = Get-Content -LiteralPath (Join-Path $toolsDir '..\..\src\plugins\checksum\dialogs.cpp') -Raw
$sevenZip = Get-Content -LiteralPath (Join-Path $toolsDir '..\..\src\plugins\7zip\7zip.cpp') -Raw
$panelExecute = Get-Content -LiteralPath (Join-Path $toolsDir '..\..\src\fileswn2.cpp') -Raw
$panelWideNames = Get-Content -LiteralPath (Join-Path $toolsDir '..\..\src\common\win32_unicode_primary_panel.h') -Raw
$panelTransfers = Get-Content -LiteralPath (Join-Path $toolsDir '..\..\src\fileswn8.cpp') -Raw

# F1/F8: selected search actions must reject non-unique ACP identities
# before invoking the shell, drag/drop or destructive operations.
if ($findDialog2 -notmatch 'ValidateSelectedLegacyFindResults\(' -or
    $findDialog2 -notmatch 'ResolveUnicodePanelFileName' -or
    $findDialog2 -notmatch 'IsExactAnsiName' -or
    $findDialog2 -notmatch 'void CFindDialog::OnDelete\(BOOL toRecycle\)(?s:.*?)ValidateSelectedLegacyFindResults\(' -or
    $findDialog1 -notmatch 'BOOL CFindDialog::GetFocusedFile\((?s:.*?)MAX_PATH') {
    throw 'F1/F8: search results must validate exact W identities before legacy actions.'
}

# F3: do not start plugins with an uninitialized root when GetPanelPath fails.
if ($renameMenu -notmatch 'GetPanelPath\(PANEL_SOURCE' -or
    $renameDialog -notmatch 'if \(!SG->GetPanelPath\(' -or
    $checksumDialogs -notmatch 'if \(!SalamanderGeneral->GetPanelPath\(' -or
    $sevenZip -notmatch 'if \(!SalamanderGeneral->GetPanelPath\(PANEL_SOURCE') {
    throw 'F3: ANSI plugin boundaries must fail closed for unsupported panel paths.'
}

# F4: oversize DBCS names must remain visible with a deliberately invalid
# ANSI placeholder; their true UTF-16 row identity stays separate.
if ($panelWideNames -notmatch 'MakeUnrepresentableAnsiPanelAlias' -or
    $panelWideNames -notmatch 'ERROR_INSUFFICIENT_BUFFER' -or
    $panelWideNames -notmatch 'Record\(') {
    throw 'F4: wide panel enumeration must retain too-long ACP names without truncating.'
}

# F5: short-path Unicode aliases must not enter the ANSI association handler.
if ($panelExecute -notmatch 'UnicodeDiskNames\.IsUnsafeAnsiName\(selectedFile\.Name\)') {
    throw 'F5: opening a lossy file through the legacy association path must be refused.'
}

# F7: batch preflight should use one directory identity snapshot per phase,
# not an O(selected files * directory entries) enumeration.
$multiTransfer = [regex]::Match(
    $panelTransfers,
    '(?s)BOOL CFilesWindow::TryUnicodeMultiFileTransfer\(.*?BOOL CFilesWindow::TryUnicodeSingleFileTransfer\(').Value
if ($multiTransfer -notmatch 'UnicodePanelNameCache' -or
    $multiTransfer -notmatch '\.Load\(sourceDirectory\.c_str\(\)' -or
    $multiTransfer -match 'ResolveUnicodePanelFileName\(') {
    throw 'F7: Unicode batch transfers must resolve alias uniqueness from bounded phase snapshots.'
}
# Regression: a 109-byte parent and 153-byte CP1252 name exceed
# MAX_PATH together although neither component does. The GUI F5/F6
# fallback must select the original row, not the lossy-only alias cache.
$singleTransfer = [regex]::Match(
    $panelTransfers,
    '(?s)BOOL CFilesWindow::TryUnicodeSingleFileTransfer\(.*?BOOL CFilesWindow::TryUnicodeSingleDirectoryDelete\(').Value
if ([string]::IsNullOrEmpty($singleTransfer) -or
    $singleTransfer -notmatch 'ExceedsLegacyDiskPathLimit\(\s*strlen\(GetPath\(\)\),\s*entry\.NameLen,\s*MAX_PATH\)' -or
    $singleTransfer -notmatch 'if\s*\(!UnicodeDiskNames\.TryGetRow\(entry\.Name,\s*originalName\)\)' -or
    $singleTransfer -notmatch 'else if\s*\(!UnicodeDiskNames\.TryGetLossy' -or
    $singleTransfer -notmatch 'const bool useWorker = type == atCopy && fileSize > MaxSynchronousTransferBytes' -or
    $singleTransfer -match 'if\s*\(fileSize > MaxSynchronousTransferBytes && !useWorker\)' -or
    $singleTransfer -notmatch '\(type == atCopy && !useWorker') {
    throw 'F5/F6: lossless ANSI file names over MAX_PATH and large same-volume moves must use W operations.'
}
Write-Host 'PASS: F5/F6 long lossless-name identity and large same-volume move route.'

# F2: the original Find dialog now searches full UTF-16 roots rather than
# falling back to MAX_PATH ANSI buffers. Its Look in control must accept a
# 32700-unit path (including escaped separators), but over-capacity initial
# roots must still be rejected explicitly rather than silently truncated.
$findHeader = Get-Content -LiteralPath (Join-Path $toolsDir '..\..\src\find.h') -Raw
if ($findHeader -notmatch '(?m)^#define LOOKIN_TEXT_LEN\s+65536\b' -or
    $findDialog1 -notmatch 'InitRootTooLong\s*=\s*Data\.LookInText\.size\(\)\s*>=\s*LOOKIN_TEXT_LEN' -or
    $findDialog1 -notmatch 'if \(InitRootTooLong\)\s*Data\.LookInText\.clear\(\);' -or
    $findDialog1 -notmatch 'void CFindDialog::StartSearch\(WORD command\)(?s:.*?)if \(InitRootTooLong\)' -or
    $findSearch -notmatch 'static void SearchDirectory\(const std::wstring& root,' -or
    $findSearch -notmatch 'TryResolveLegacyFindDirectory\(root, directory, error\)' -or
    $findSearch -notmatch 'FindFirstFileW\(extended\.c_str\(\), &file\)' -or
    $findSearch -notmatch 'FindNextFileW\(handle, &file\)') {
    throw 'F2: legacy Find must search full UTF-16 roots and explicitly reject over-capacity input.'
}

# F6: copied files must be fully staged before atomic, no-replace publication.
$fileOps = Get-Content -LiteralPath (
    Join-Path $toolsDir '..\..\src\common\win32_unicode_file_ops.h') -Raw
$copyImpl = [regex]::Match($fileOps,
    '(?s)inline bool TryCopyUnicodeFileNoOverwrite\(.*?inline bool TryMoveUnicodeFileNoOverwrite\(').Value
if ($copyImpl -notmatch 'CopyFileW\(sourcePath\.c_str\(\), temporary\.c_str\(\), TRUE\)' -or
    $copyImpl -notmatch 'MoveFileExW\(temporary\.c_str\(\), destinationPath\.c_str\(\), 0\)' -or
    $copyImpl -notmatch 'DeleteFileW\(temporary\.c_str\(\)\)') {
    throw 'F6: Unicode copy must use staging and no-replace publication.'
}

# Test all plug-in menu dispatch variants, including deferred and posted
# callbacks that bypass the usual CPluginData handler.
$pluginDispatch = Get-Content -LiteralPath (
    Join-Path $toolsDir '..\..\src\plugins1.cpp') -Raw
$pluginDeferred = Get-Content -LiteralPath (
    Join-Path $toolsDir '..\..\src\salamdr1.cpp') -Raw
$pluginPosted = Get-Content -LiteralPath (
    Join-Path $toolsDir '..\..\src\mainwnd3.cpp') -Raw
$hostPanel = Get-Content -LiteralPath (
    Join-Path $toolsDir '..\..\src\fileswn8.cpp') -Raw
# C++ method implementation is CFilesWindow::..., not its ancestor:
# keep its declaration in the derived class (C2509 regression, 2026-11-16).
$filesHeader = Get-Content -LiteralPath (
    Join-Path $toolsDir '..\..\src\fileswnd.h') -Raw
$derivedDeclaration = [regex]::Match($filesHeader,
    '(?s)class CFilesWindow\s*:\s*public CFilesWindowAncestor\s*\{(.*?)\bCViewTemplate\* ViewTemplate;').Groups[1].Value
if ([string]::IsNullOrEmpty($derivedDeclaration) -or
    $derivedDeclaration -notmatch '\bBOOL\s+HasUnsupportedLegacyPluginSelection\s*\(\s*\)\s*;' -or
    $filesHeader -match '(?s)BOOL HasLongDiskPath\(\).*?BOOL HasUnsupportedLegacyPluginSelection\(\).*?class CFilesWindow\s*:') {
    throw 'C2509 regression: legacy plug-in selection method must be declared in CFilesWindow, not its ancestor.'
}
# Inspect the guard itself rather than matching an unrelated use elsewhere.
# The unsafe predicate takes 'entry'; selected/caret rows are named 'item'.
$pluginGateStart = $hostPanel.IndexOf(
    'BOOL CFilesWindow::HasUnsupportedLegacyPluginSelection()', [StringComparison]::Ordinal)
$pluginGateEnd = $hostPanel.IndexOf(
    'void CFilesWindow::FilesAction(', [StringComparison]::Ordinal)
$pluginGate = if ($pluginGateStart -ge 0 -and $pluginGateEnd -gt $pluginGateStart) {
    $hostPanel.Substring($pluginGateStart, $pluginGateEnd - $pluginGateStart)
} else { '' }
if ($pluginDispatch -notmatch 'HasUnsupportedLegacyPluginSelection' -or
    $pluginDeferred -notmatch 'HasUnsupportedLegacyPluginSelection' -or
    $pluginPosted -notmatch 'HasUnsupportedLegacyPluginSelection' -or
    [string]::IsNullOrEmpty($pluginGate) -or
    $pluginGate -notmatch 'HasLongDiskPath\(\)' -or
    $pluginGate -notmatch 'pathLength\s*\+\s*entry\.NameLen\s*\+\s*1\s*>=\s*MAX_PATH' -or
    $pluginGate -notmatch 'UnicodeDiskNames\.IsUnsafeAnsiName\(entry\.Name\)' -or
    $pluginGate -notmatch 'GetCaretIndex\(\)' -or
    $pluginGate -notmatch 'GetSelCount\(\)' -or
    $pluginGate -notmatch 'item\.Selected\s*&&\s*unsafe\(item\)') {
    throw 'F3: all legacy plugin menu paths must block unsafe disk identities.'
}

# Search roots must be transferred from the complete W control value.
# Any ANSI copy used by legacy actions still requires an exact round-trip.
$findWorker = Get-Content -LiteralPath (Join-Path $toolsDir '..\..\src\find.cpp') -Raw
$findQuery = Get-Content -LiteralPath (Join-Path $toolsDir '..\..\src\common\legacy_find_query.h') -Raw
if ($findDialog1 -notmatch 'const std::wstring roots = ReadFindEdit\(lookIn\)' -or
    $findWorker -notmatch 'TryResolveLegacyFindDirectory\(root, directory, error\)' -or
    $findQuery -notmatch 'Utf16DiskPath::TryCreateAbsolute\(utf16, valid, pathError\)' -or
    $findWorker -notmatch 'TryGetFindDirectoryLabel\(directory, label\);' -or
    $findWorker -notmatch 'IsExactAnsiName\(output, text\.c_str\(\)\)' -or
    $findWorker -notmatch 'FindFirstFileW\(extended\.c_str\(\), &file\)' -or
    $findDialog1 -notmatch 'ti\.ErrorOn\(IDC_FIND_LOOKIN\)') {
    throw 'F2: search root validation must not silently truncate or best-fit Unicode.'
}

# The secondary Unicode Find command and the native near-limit fixture
# must reach the same W-owned search implementation.
$wideFind = Get-Content -LiteralPath (
    Join-Path $toolsDir '..\..\src\common\win32_unicode_find.h') -Raw
$wideFindWindow = Get-Content -LiteralPath (
    Join-Path $toolsDir '..\..\src\common\win32_unicode_find_window.h') -Raw
$findCaller = Get-Content -LiteralPath (
    Join-Path $toolsDir '..\..\src\fileswn5.cpp') -Raw
$maxPathNative = Get-Content -LiteralPath (
    Join-Path $toolsDir '..\..\tools\tests\win32_max_path.cpp') -Raw
$searchNative = Get-Content -LiteralPath (
    Join-Path $toolsDir '..\..\tools\tests\unicode_find.cpp') -Raw
if ($managerSource -notmatch [regex]::Escape("'tools\tests\unicode_find.cpp'") -or
    $wideFind -notmatch 'SearchUnicodeDirectory\(' -or
    $wideFind -notmatch 'TryEnumerateLongDirectory\(' -or
    $wideFind -notmatch 'UnicodeFindFileContains\(' -or
    $wideFind -notmatch 'CreateFileW\(' -or
    $wideFind -notmatch 'FindNextFileW|TryEnumerateLongDirectory' -or
    $wideFindWindow -notmatch 'LVM_INSERTITEMW' -or
    $wideFindWindow -notmatch 'CF_UNICODETEXT' -or
    $wideFindWindow -notmatch 'TryMoveUnicodeFileNoOverwrite' -or
    $findCaller -notmatch 'UnicodeFindWindow::Open\(owner, wideRoot' -or
    $maxPathNative -notmatch 'F2 search preserves full 32700-unit Unicode result' -or
    $searchNative -notmatch 'cross-buffer UTF-8/UTF-16 search') {
    throw 'F2: native Unicode Find search and GUI integration must preserve W paths and run the regression suite.'
}
# In this non-UNICODE build, IDC_ARROW is an ANSI resource identifier.
# The generic LoadCursor macro selects the matching API variant; using
# LoadCursorW with IDC_ARROW fails C2664, while OCR_NORMAL is not defined
# unless OEMRESOURCE is enabled (C2065). Debug also instruments ordinary new.
$precompiledHeader = Get-Content -LiteralPath (
    Join-Path $toolsDir '..\..\src\precomp.h') -Raw
if ($precompiledHeader -match '(?m)^#define new new \(_NORMAL_BLOCK' -and
    ($wideFindWindow -match 'LoadCursorW\(nullptr,\s*IDC_ARROW\)' -or
     $wideFindWindow -match 'new\s*\(\s*std::nothrow\s*\)')) {
    throw 'F2: Unicode Find window must avoid ANSI cursor resource and Debug CRT new-macro incompatibilities.'
}
if ($wideFindWindow -notmatch 'LoadCursor\(nullptr,\s*IDC_ARROW\)' -or
    $wideFindWindow -notmatch 'new UnicodeFindWindow\(') {
    throw 'F2: Unicode Find window requires matching Win32 cursor resource/API macros and project-compatible allocation.'
}
Write-Host 'PASS: F2 Unicode Find window respects non-UNICODE Win32 resources and Debug CRT allocator.'
Write-Host 'PASS: F2 Win32 W search, result actions, native tests and disk-panel GUI routing are wired.'
Write-Host 'PASS: legacy plugin menu paths and Unicode find-root input fail closed.'
Write-Host 'PASS: search and plugin fail-closed contracts; wide alias fallback and batch snapshot boundaries.'
