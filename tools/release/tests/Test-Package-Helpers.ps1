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
foreach ($required in @('--test', $futureOption) + $guiModes) {
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
$guiSectionStart = $managerSource.IndexOf(
    'if ($requestedSet.Contains(''--test-gui-baseline''))',
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
    $pasteBlock -notmatch 'Salamander::IsExactAnsiName\(ansi\.data\(\), value\.c_str\(\)\)' -or
    $pasteBlock -notmatch 'if \(clipboardPath\.empty\(\) && !unicodeTextPresent\)' -or
    $pasteBlock -notmatch 'clipboardPath\.assign\(text \+ begin, length - begin\)') {
    throw 'Clipboard navigation must reject incomplete Unicode and ANSI clipboard paths.'
}

# WC_NO_BEST_FIT_CHARS is invalid when the active ANSI code page is
# UTF-8 (ACP 65001). The exact Unicode round-trip identity check remains
# mandatory; Win32's CP_ACP conversion itself must use supported flags.
if ($pasteBlock -match 'WideCharToMultiByte\(CP_ACP,\s*WC_NO_BEST_FIT_CHARS' -or
    $pasteBlock -notmatch 'WideCharToMultiByte\(CP_ACP,\s*0,' -or
    $pasteBlock -notmatch 'Salamander::IsExactAnsiName') {
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
# navigation. Reject actual file payloads on long targets, but NEVER display
# a blocking dialog for plain CF_UNICODETEXT navigation. The second GUI
# navigation to the long folder explicitly exercises this distinction.
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
    $pasteBlock -notmatch 'if \(!hasFilePayload\)' -or
    $pasteBlock -notmatch 'return FALSE;' -or
    $pasteBlock -notmatch 'return TRUE;') {
    throw 'Long-target clipboard paste must distinguish file data from a text path and refuse only file transfers.'
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
    $clipboardNav -notmatch 'IsExactAnsiName' -or
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
    $startupSource -notmatch 'std::string leftPanelPath\(systemDirectory\)' -or
    $startupSource -notmatch 'std::string rightPanelPath\(systemDirectory\)' -or
    $startupSource -notmatch 'RestoreSavedPanelPath\(LeftPanel, leftPanelPath\)' -or
    $startupSource -notmatch 'RestoreSavedPanelPath\(RightPanel, rightPanelPath\)' -or
    $startupSource -notmatch 'if \(savedPath\.size\(\) >= static_cast<std::size_t>\(MAX_PATH - 2\)\)' -or
    $startupSource -notmatch 'ChangePathToDisk\(panel->HWindow, savedPath\.c_str\(\)\)') {
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
