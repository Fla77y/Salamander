#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
    Static regression checks for the GUI driver's Win32 message contract.
.DESCRIPTION
    Parses the driver without launching Salamander or requiring a desktop.
    The real interactive GUI tests remain mandatory.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$driverPath = Join-Path $PSScriptRoot 'Test-SalamanderGui-LongPaths.ps1'
$tokens = $null
$errors = $null
$tree = [System.Management.Automation.Language.Parser]::ParseFile(
    $driverPath, [ref]$tokens, [ref]$errors)
if (@($errors).Count -gt 0) {
    throw "GUI driver contains PowerShell parse errors: $($errors -join '; ')"
}

function Get-FunctionSource {
    param([Parameter(Mandatory)][string]$Name)

    $matches = @($tree.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -ceq $Name
    }, $true))
    if ($matches.Count -ne 1) {
        throw "Expected exactly one GUI driver function '$Name'; found $($matches.Count)."
    }
    return $matches[0]
}

$navigate = Get-FunctionSource 'Go-ToPath'
$reads = @($navigate.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.CommandAst] -and
    $node.GetCommandName() -ceq 'Read-PanelPath'
}, $true))
if ($reads.Count -ne 1) {
    throw "Go-ToPath must read the panel path once per polling iteration, not again after success; found $($reads.Count) call sites."
}
if ($navigate.Extent.Text -notmatch 'Assert-True\s+\(\$diagnostics\.PanelPath\s+-ceq\s+\$Path\)') {
    throw 'Go-ToPath must assert the path already observed in the successful polling iteration.'
}
# The baseline's Go-ToPath invocation already establishes the panel path.
# Do not repeat Read-PanelPath immediately outside that function either.
$driverText = $tree.Extent.Text
# Read-PanelPath after a later panel switch is legitimate: prohibit only
# the immediate extra assertion following the *initial* Go-ToPath $source.
if ($driverText -match 'Go-ToPath\s+\$source\s+Assert-True\s+\(\(Read-PanelPath\)\s+-ceq\s+\$source\)') {
    throw 'Initial baseline must reuse the verified navigation result, not issue a second WM_COMMAND 711.'
}
if ($driverText -notmatch 'Go-ToPath\s+\$source') {
    throw 'Baseline must still navigate and verify its short ASCII source path.'
}
Write-Host 'PASS: GUI baseline has no redundant read after verified navigation.'

Write-Host 'PASS: GUI navigation reuses the observed path without a redundant WM_COMMAND.'

# Navigation must never consume an unverified clipboard value. Retrying
# SetText/GetText is safe; retrying WM_COMMAND with wrong data is not.
$navigationSource = $navigate.Extent.Text
$verifiedClipboard = Get-FunctionSource 'Set-VerifiedNavigationClipboard'
$clipboardSource = $verifiedClipboard.Extent.Text
$verifyPosition = $navigationSource.IndexOf('Set-VerifiedNavigationClipboard', [StringComparison]::Ordinal)
$dispatchPosition = $navigationSource.IndexOf('Invoke-SalamanderCommand -CommandId 775', [StringComparison]::Ordinal)
if ($verifyPosition -lt 0 -or $dispatchPosition -lt 0 -or
    $verifyPosition -ge $dispatchPosition -or
    $navigationSource -match 'Set-ClipboardText\s+\$Path' -or
    $clipboardSource -notmatch '\[StringComparison\]::Ordinal' -or
    $clipboardSource -notmatch '\$maxAttempts\s*=\s*4' -or
    $clipboardSource -notmatch 'No navigation command was sent' -or
    $clipboardSource -notmatch '\$warningFormat\s+-f\s+\$attempt' -or
    $clipboardSource -match 'Invoke-SalamanderCommand') {
    throw 'GUI navigation must verify exact clipboard round-trip before dispatching WM_COMMAND 775.'
}
Write-Host 'PASS: GUI navigation verifies exact clipboard content and retries only safe clipboard writes.'

# The former generic timeout concealed a disappearing main window during
# the second (Debug x64) maximum-length GUI test. Poll for a terminated process or lost HWND BEFORE
# treating a foreign foreground PID as a transient focus issue.
$processState = (Get-FunctionSource 'Get-TestProcessState').Extent.Text
if ($navigationSource -notmatch '\$process\.HasExited' -or
    $navigationSource -notmatch '\$currentMainOwner\s+-ne\s+\[uint32\]\$process\.Id' -or
    $navigationSource -notmatch 'Get-TestProcessState' -or
    $navigationSource -notmatch 'Get-ForegroundWindowSummary' -or
    $processState -notmatch 'exitCodeHex' -or
    $processState -notmatch 'Get-ProcessWindowSummary') {
    throw 'Navigation failure must distinguish process exit, destroyed HWND, and foreground loss.'
}

# Huge (32k-unit) paths must not flood error logs or hide the exit status.
$pathFormatter = Get-FunctionSource 'Format-GuiDiagnosticPath'
. ([scriptblock]::Create($pathFormatter.Extent.Text))
$hugePath = 'C:\fixture\' + ('x' * 32680) + '\end'
$compact = Format-GuiDiagnosticPath $hugePath
if ($compact.Length -ge 250 -or
    $compact -notmatch [regex]::Escape("length=$($hugePath.Length) UTF-16 units") -or
    $compact -notmatch 'omitted=' -or
    $compact -notmatch "suffix='") {
    throw 'Navigation diagnostics must summarize extreme paths without losing their length.'
}
if ($navigationSource -match 'Salamander navigation to \$Path' -or
    $navigationSource -notmatch 'Salamander navigation to \$pathSummary') {
    throw 'Navigation timeout must use compact path diagnostics.'
}
Write-Host 'PASS: extreme GUI navigation failures preserve crash/focus diagnostics without dumping 32k-unit paths.'


# Long-directory Enter navigation needs a read-only GUI focus snapshot and
# the exact last observed path. Retrying Enter after a timeout could execute
# an unrelated focused row, so retries must remain forbidden.
$mainGuiSource = $tree.Extent.Text
if ($mainGuiSource -notmatch 'GetGUIThreadInfo' -or
    $mainGuiSource -notmatch 'GetInputFocusSummary' -or
    $mainGuiSource -notmatch '\$focusBeforeEnter\s*=\s*\[SalamanderGuiNative\]::GetInputFocusSummary' -or
    $mainGuiSource -notmatch '\$enterDiagnostics\.PanelPath\s*=\s*Read-PanelPath' -or
    $mainGuiSource -notmatch 'Assert-True\s+\(\$enterDiagnostics\.PanelPath\s+-ceq\s+\$nestedLongDirectory\)' -or
    $mainGuiSource -match '\$pathAfterEnter\s*=\s*Read-PanelPath' -or
    $mainGuiSource -notmatch 'No additional Enter was sent' -or
    $mainGuiSource -match 'Wait-Until\s*\{\s*Send-Keys\s+''\{ENTER\}''') {
    throw 'Long-directory Enter test must capture focus/path and never retry an unconfirmed Enter.'
}
Write-Host 'PASS: long-directory Enter failure captures actual GUI focus and observed path.'

# Wait-Until invokes a supplied scriptblock using &, which creates a
# child scope. A scalar assignment within the poll must not be used after
# Wait-Until returns; only the shared hashtable's mutation survives.
$enterStart = $mainGuiSource.IndexOf('$enterDiagnostics = @{', [StringComparison]::Ordinal)
$enterEnd = if ($enterStart -ge 0) {
    $mainGuiSource.IndexOf("Send-Keys '{BACKSPACE}'", $enterStart, [StringComparison]::Ordinal)
} else { -1 }
if ($enterStart -lt 0 -or $enterEnd -le $enterStart) {
    throw 'Long-directory Enter diagnostics or the following Backspace operation were not found.'
}
$enterNavigation = $mainGuiSource.Substring($enterStart, $enterEnd - $enterStart)
if ($enterNavigation -notmatch '\$enterDiagnostics\.PanelPath\s*=\s*Read-PanelPath' -or
    $enterNavigation -notmatch 'return\s+\$enterDiagnostics\.PanelPath\s+-ceq\s+\$nestedLongDirectory' -or
    $enterNavigation -notmatch 'Assert-True\s+\(\$enterDiagnostics\.PanelPath\s+-ceq\s+\$nestedLongDirectory\)' -or
    $enterNavigation -match 'Assert-True\s+\(\(Read-PanelPath\)') {
    throw 'Long-directory Enter must assert the same path observed by Wait-Until through a reference-type diagnostic object.'
}
Write-Host 'PASS: Enter navigation preserves the successful poll result across PowerShell scopes.'




# A synchronous WM_COMMAND 709/710 may return even when the focused row
# was not exported. Never treat command dispatch as clipboard success, and
# never change row selection merely to make a failed read pass.
$focusedRead = Get-FunctionSource 'Read-FocusedClipboardValue'
$focusedReadSource = $focusedRead.Extent.Text
$focusedShort = (Get-FunctionSource 'Read-FocusedFilename').Extent.Text
$focusedFull = (Get-FunctionSource 'Read-FocusedFullname').Extent.Text
if ($focusedReadSource -notmatch '\$maxAttempts\s*=\s*2' -or
    $focusedReadSource -notmatch 'GetClipboardSequenceNumber' -or
    $focusedReadSource -notmatch 'GetInputFocusSummary' -or
    $focusedReadSource -notmatch '\$retryFormat\s+-f\s+\$CommandId' -or
    $focusedReadSource -notmatch '\$failureFormat\s+-f\s+\$CommandId' -or
    $focusedReadSource -notmatch 'return \$observed\.TrimEnd' -or
    $focusedReadSource -notmatch 'Read-PanelPath' -or
    $focusedReadSource -match 'Send-Keys|\{END\}|\{HOME\}|\{DOWN\}|\{UP\}' -or
    $focusedShort -notmatch 'Read-FocusedClipboardValue -CommandId 710' -or
    $focusedFull -notmatch 'Read-FocusedClipboardValue -CommandId 709') {
    throw 'Focused-name clipboard reads must retry bounded, read-only requests and report the panel state on failure.'
}
Write-Host 'PASS: focused clipboard reads are bounded, non-destructive, and diagnostic.'

# A focused filename read is not proof that SendKeys reached the file-list
# control. On failure, retain the pre-/post-key focus and the source fixture
# existence, without retrying or forcing a new focus target.
$baselineProbe = [regex]::Match(
    $driverText,
    '(?s)if \(\$BaselineOnly\) \{\s*\$focusBeforeEnd.*?No extra keys were sent.*?\$focusedName -ceq \$focusProbeName'
)
if (-not $baselineProbe.Success -or
    $baselineProbe.Value -notmatch 'GetInputFocusSummary' -or
    $baselineProbe.Value -notmatch '\[IO.File\]::Exists' -or
    $baselineProbe.Value -notmatch 'Send-Keys ''\{END\}''' -or
    $baselineProbe.Value -match 'Focus-TestProcess|Send-Keys ''\{END\}''.*Send-Keys ''\{END\}''') {
    throw 'Short ASCII baseline must diagnose focused HWND and fixture without masking lost keyboard focus.'
}
Write-Host 'PASS: short GUI focus baseline captures keyboard target and never retries input blindly.'

# Every GUI mode shares the initial short-path navigation. WM_ACTIVATE
# restores focus using Salamander's own FocusPanel(GetActivePanel()) path;
# it is permitted only for the verified foreground HWND, never a guessed
# left/right child window or a modal popup. Verify file-list focus and path
# before any file-operation keystrokes.
$focusRecovery = (Get-FunctionSource 'Restore-FilePanelFocus').Extent.Text
$guiInterop = $driverText
if ($focusRecovery -notmatch 'IsFileListFocused' -or
    $focusRecovery -notmatch 'Get-ActiveProcessId' -or
    $focusRecovery -notmatch 'Get-TestDialog' -or
    $focusRecovery -notmatch 'GetForegroundWindow\(\)\s+-ne\s+\$mainWindowHandle' -or
    $focusRecovery -notmatch 'GetWindowThreadProcessId' -or
    $focusRecovery -notmatch 'SendMessageTimeout' -or
    $focusRecovery -notmatch '\[uint32\]0x0006' -or
    $focusRecovery -notmatch '\[uint32\]1' -or
    $focusRecovery -notmatch '\$activationError\s*=\s*\[Runtime\.InteropServices\.Marshal\]::GetLastWin32Error\(\)' -or
    $focusRecovery -notmatch '\$observedPath\s*=\s*Read-PanelPath' -or
    $focusRecovery -notmatch '\$observedPath\s+-cne\s+\$ExpectedPath' -or
    $focusRecovery -notmatch '\$failureFormat\s+-f\s+\$focusBefore' -or
    $focusRecovery -match 'Send-Keys|Focus-TestProcess|AttachThreadInput' -or
    $guiInterop -notmatch 'GetDlgCtrlID\(info\.hwndFocus\)\s*==\s*950' -or
    $guiInterop -notmatch 'Go-ToPath\s+\$source\s+Restore-FilePanelFocus\s+-ExpectedPath\s+\$source') {
    throw 'GUI baseline must restore and verify file-list focus via the native activation handler, never through blind keystrokes.'
}
Write-Host 'PASS: GUI scenarios verify file-list focus through a safe native activation notification.'

# Previously the test closed Salamander normally, saving disposable panel
# paths to HKCU. Those fixtures are deleted, so the next test could start
# with Error Changing Directory (3) and no focused list. Explicit -l/-r
# startup paths must override both restored panels, and the isolated test
# process must not execute SaveConfig on shutdown.
$startupSource = $driverText
if ($startupSource -notmatch '\$startupArgs\s*=\s*''-l "\{0\}" -r "\{0\}" -p 2'' -f \$source' -or
    $startupSource -notmatch 'Start-Process[^\r\n]*-ArgumentList \$startupArgs' -or
    $startupSource -match '\$process\.CloseMainWindow\(' -or
    $startupSource -notmatch '\$process\.Kill\(\)' -or
    $startupSource -notmatch '\$window\.Title -ceq ''Error Changing Directory''' -or
    $startupSource -notmatch 'GetProcessWindows\(\[uint32\]\$process\.Id\)') {
    throw 'GUI test must start both panels in existing fixture paths, recognize directory-error dialogs and not persist disposable paths into user configuration.'
}
Write-Host 'PASS: GUI fixture startup and shutdown protect saved panel paths from disposable directories.'



$dispatch = Get-FunctionSource 'Invoke-SalamanderCommand'
$source = $dispatch.Extent.Text
$errorCapture = $source.IndexOf(
    '$lastError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()',
    [StringComparison]::Ordinal)
$dialogLookup = $source.IndexOf('$dialog = Get-TestDialog',
    [StringComparison]::Ordinal)
if ($errorCapture -lt 0 -or $dialogLookup -lt 0 -or
    $errorCapture -gt $dialogLookup) {
    throw 'SendMessageTimeout last-error must be captured before invoking any diagnostic Win32 call.'
}
Write-Host 'PASS: GUI driver captures the original SendMessageTimeout Win32 error.'

# W-based primary enumeration associates each CFileData Name allocation
# with its original Unicode record. Clipboard identity may now be recovered
# for two rows with the same ANSI alias; destructive legacy actions remain
# independently fail-closed.
$collisionBranch = $tree.Extent.Text
if ($collisionBranch -notmatch '\[switch\]\$ShortUnicodeCollisionOnly' -or
    $collisionBranch -notmatch 'Unicode aliases retain distinct per-row names' -or
    $collisionBranch -notmatch 'Unicode aliases retain distinct full paths' -or
    $collisionBranch -notmatch 'Collision retained both original file contents') {
    throw 'GUI collision regression must check independent wide row identities and data integrity.'
}
Write-Host 'PASS: Unicode collision regression preserves distinct W-based panel identities.'

if ($driverText -notmatch '\[switch\]\$ShortUnicodeUnsafeOperationsOnly' -or
    $driverText -notmatch 'safe refusal dialog for' -or
    $driverText -notmatch 'Original Unicode files intact after' -or
    $driverText -notmatch 'No Unicode destination created by') {
    throw 'Real GUI Unicode operation guard regression must verify refusal and source/destination integrity.'
}
Write-Host 'PASS: F2/F5/F6/F8 Unicode safety GUI regression is present.'

if ($driverText -notmatch '\[switch\]\$ShortUnicodeBestFitOnly' -or
    $driverText -notmatch 'HasLossyAliasWithoutQuestionMark' -or
    $driverText -notmatch 'Unicode best-fit filename recovered without question mark' -or
    $driverText -notmatch 'Best-fit Unicode file content remains intact') {
    throw 'GUI best-fit regression must verify non-question-mark ANSI conversion and original file bytes.'
}
Write-Host 'PASS: Non-question-mark best-fit Unicode GUI regression is present.'

if ($driverText -notmatch '\[switch\]\$ShortUnicodeRenameOnly' -or
    $driverText -notmatch 'UTF-16 F2 rename without ANSI narrowing' -or
    $driverText -notmatch 'Unicode F2 renamed file preserves original bytes') {
    throw 'True Unicode F2 GUI acceptance must verify name change and content preservation.'
}
Write-Host 'PASS: interactive Unicode F2 rename regression contract is present.'

if ($driverText -notmatch '\[switch\]\$ShortUnicodeTransferOnly' -or
    $driverText -notmatch 'Unicode F5 copy to other disk panel' -or
    $driverText -notmatch 'Unicode F6 move to other disk panel' -or
    $driverText -notmatch 'Unicode F6 preserves moved content') {
    throw 'UTF-16 F5/F6 GUI regression must check source, destination and byte integrity.'
}
if ($driverText -notmatch '\[switch\]\$ShortUnicodeTransferCollisionOnly' -or
    $driverText -notmatch 'Unicode transfer collision source intact' -or
    $driverText -notmatch 'Unicode transfer collision target intact') {
    throw 'Unicode transfer destination-collision acceptance must preserve both payloads.'
}
Write-Host 'PASS: Unicode F5/F6 GUI transfer and collision assertions are present.'

if ($driverText -notmatch '\[switch\]\$ShortUnicodeRecycleOnly' -or
    $driverText -notmatch 'Unicode F8 refusal preserves file bytes' -or
    $driverText -notmatch 'Unicode F8 moves fixture to Recycle Bin') {
    throw 'Unicode F8 recycle GUI regression must require data preservation on refusal.'
}
Write-Host 'PASS: Unicode F8 GUI recycle and refusal assertions are present.'

if ($driverText -notmatch '\[switch\]\$ShortUnicodeRowIdentityOnly' -or
    $driverText -notmatch 'Distinct per-row Unicode names survive ANSI alias collision' -or
    $driverText -notmatch 'Distinct full Unicode clipboard paths follow selected panel row') {
    throw 'W-based panel regression must preserve exact name and full path per row.'
}
Write-Host 'PASS: W-backed per-row Unicode identity and clipboard regression assertions are present.'

if ($driverText -notmatch '\[switch\]\$ShortUnicodeMultiSelectOnly' -or
    $driverText -notmatch 'Unicode F5 copies both selected files' -or
    $driverText -notmatch 'Unicode F6 moves both selected files') {
    throw 'Unicode multi-selection regression must verify all selected files, not just the caret.'
}
Write-Host 'PASS: Unicode F5/F6 multi-selection contract is present.'

if ($driverText -notmatch '\[switch\]\$ShortUnicodeDirectoryRenameOnly' -or
    $driverText -notmatch 'Unicode F2 directory rename' -or
    $driverText -notmatch 'Unicode F2 directory child bytes retained') {
    throw 'UTF-16 F2 directory GUI contract must preserve nested child contents.'
}
Write-Host 'PASS: UTF-16 directory F2 rename contract is present.'

# The W-backed row identity is keyed by CFileData::Name's allocation
# address, not by the bytes of a copied std::string. The latter made the
# F6 long-path directory move decline before opening its confirmation.
$directoryMoveSource = Get-Content -LiteralPath (
    Join-Path $PSScriptRoot '..\..\..\src\fileswn8.cpp') -Raw
$directoryMove = [regex]::Match(
    $directoryMoveSource,
    '(?s)BOOL CFilesWindow::TryUnicodeSingleDirectoryMove\(.*?\r?\n\}\r?\n'
)
if (-not $directoryMove.Success -or
    $directoryMove.Value -notmatch 'UnicodeDiskNames\.TryGetRow\(entry\.Name, originalName\)' -or
    $directoryMove.Value -match 'UnicodeDiskNames\.TryGetRow\(alias\.c_str\(\), originalName\)') {
    throw 'F6 directory move must retrieve W row identity using the original CFileData::Name allocation.'
}
Write-Host 'PASS: F6 directory move uses original W-backed row identity.'

# The GUI fixture defines Test-Content(Path) to compare bytes. It is not
# Test-Path and does not accept -LiteralPath. A bad parameter binds before
# any F6 result is evaluated, even if the move succeeded.
$contentCalls = @($tree.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.CommandAst] -and
    $node.GetCommandName() -ceq 'Test-Content'
}, $true))
$invalidContentCalls = @($contentCalls | Where-Object {
    @($_.CommandElements | Where-Object {
        $_ -is [System.Management.Automation.Language.CommandParameterAst] -and
        $_.ParameterName -ceq 'LiteralPath'
    }).Count -gt 0
})
if ($invalidContentCalls.Count -gt 0) {
    throw 'Test-Content is a custom byte-comparison helper: do not pass the unsupported -LiteralPath parameter.'
}

$treeMoveStart = $driverText.IndexOf('# ACT + ASSERT: an F6 directory move',
    [StringComparison]::Ordinal)
$treeMoveEnd = if ($treeMoveStart -ge 0) {
    $driverText.IndexOf('# ACT + ASSERT: copying a normal short-path file',
        $treeMoveStart, [StringComparison]::Ordinal)
} else { -1 }
if ($treeMoveStart -lt 0 -or $treeMoveEnd -le $treeMoveStart) {
    throw 'F6 nested directory move GUI regression block is missing.'
}
$treeMoveText = $driverText.Substring($treeMoveStart, $treeMoveEnd - $treeMoveStart)
if ($treeMoveText -notmatch 'Test-Content\s+\$treeTargetLeaf' -or
    $treeMoveText -notmatch '\[IO\.Directory\]::Exists\(\$treeMoveSource\)' -or
    $treeMoveText -notmatch '\$failureFormat\s+-f\s+\$cause') {
    throw 'F6 tree move must verify nested bytes and removed source with working formatted diagnostics.'
}
Write-Host 'PASS: F6 directory GUI assertions use the valid byte-comparison helper and formatted diagnostics.'



# Compile the embedded C# Win32 interop in the headless Windows test process.
# PowerShell's AST check alone would not catch invalid P/Invoke signatures.
$interopSource = [regex]::Match(
    $driverText, '(?s)Add-Type -TypeDefinition @''\r?\n(.*?)\r?\n''@')
if (-not $interopSource.Success) {
    throw 'GUI driver C# Win32 interop here-string not found.'
}
Add-Type -TypeDefinition $interopSource.Groups[1].Value -ErrorAction Stop
if ([SalamanderGuiNative]::GetLegacyFilenameAliasHex('plain.txt') -cne
    '70-6C-61-69-6E-2E-74-78-74') {
    throw 'Win32 ACP alias encoder did not preserve a simple ASCII filename.'
}
if ([SalamanderGuiNative]::HasLossyAliasWithoutQuestionMark('plain.txt')) {
    throw 'Win32 best-fit detection misclassified an ASCII filename.'
}
Write-Host 'PASS: embedded GUI Win32 interop compiles and preserves ASCII ACP identity.'

# Focus recovery must never send keystrokes before checking ownership and
# must re-verify the actual target HWND, not merely any window of the PID.
$focus = Get-FunctionSource 'Focus-TestProcess'
$focusText = $focus.Extent.Text
if ($focusText -notmatch 'TryActivateVerifiedWindow' -or
    $focusText -notmatch 'GetForegroundWindow' -or
    $focusText -notmatch 'Get-ForegroundWindowSummary' -or
    $focusText -notmatch 'window no longer belongs to launched Salamander' -or
    $focusText -notmatch 'attempts') {
    throw 'Focus recovery must retry only a verified Salamander HWND and report foreground ownership.'
}
$sendKeys = (Get-FunctionSource 'Send-Keys').Extent.Text
if ($sendKeys -notmatch 'Get-ActiveProcessId' -or
    $sendKeys -notmatch 'Refusing to send input') {
    throw 'Keystroke dispatch must refuse input when the test process is not foreground.'
}
if ([SalamanderGuiNative]::TryActivateVerifiedWindow([IntPtr]::Zero, 42, $true) -or
    [SalamanderGuiNative]::TryActivateVerifiedWindow([IntPtr]::Zero, 0, $false)) {
    throw 'Focus helper must refuse an invalid HWND without changing foreground.'
}
# On a real Windows desktop, a valid foreground HWND owned by a *different*
# PID must also be refused before any focus operation is attempted.
$foreground = [SalamanderGuiNative]::GetForegroundWindow()
if ($foreground -ne [IntPtr]::Zero) {
    [uint32]$foregroundPid = 0
    [void][SalamanderGuiNative]::GetWindowThreadProcessId($foreground, [ref]$foregroundPid)
    $wrongPid = if ($foregroundPid -eq [uint32]::MaxValue) {
        [uint32]([uint32]::MaxValue - 1)
    } else {
        [uint32]::MaxValue
    }
    if ([SalamanderGuiNative]::TryActivateVerifiedWindow($foreground, $wrongPid, $true)) {
        throw 'Focus recovery incorrectly accepted a window from another PID.'
    }
}
Write-Host 'PASS: GUI activation recovery validates HWND ownership, retries and preserves input safety.'
