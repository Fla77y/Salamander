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
# A visible HWND and WaitForInputIdle do not prove that Salamander's main
# GUI thread pumps messages. Require a bounded, side-effect-free WM_NULL
# readiness check before focus, clipboard mutation or any file operation.
$readiness = Get-FunctionSource 'Wait-ForGuiResponsive'
$readinessText = $readiness.Extent.Text
$startupStart = $driverText.IndexOf(
    '    # A visible top-level window is not evidence', [StringComparison]::Ordinal)
if ($startupStart -lt 0) { throw 'GUI startup acceptance block is missing.' }
$navigationStart = $driverText.IndexOf(
    '    Go-ToPath $source', $startupStart, [StringComparison]::Ordinal)
if ($navigationStart -le $startupStart) {
    throw 'GUI startup acceptance block is missing.'
}
$startupText = $driverText.Substring($startupStart, $navigationStart - $startupStart)
if ($startupText -notmatch '(?s)WaitForInputIdle\(10000\).*?Wait-ForGuiResponsive.*?Focus-TestProcess' -or
    $readinessText -notmatch 'SendMessageTimeout' -or
    $readinessText -notmatch 'GetLastWin32Error' -or
    $readinessText -notmatch 'Get-TestDialog' -or
    $readinessText -notmatch 'Get-ProcessWindowSummary' -or
    $readinessText -notmatch 'SalamanderGuiWaitChain' -or
    $readinessText -notmatch 'Start-Sleep' -or
    $readinessText -notmatch 'GUI startup remained unresponsive') {
    throw 'GUI must prove bounded message-loop readiness and preserve hang diagnostics before clipboard navigation.'
}
# A failure screenshot is diagnostic evidence. The new temp-directory test
# removes its fixture after failure, so evidence must be stored outside it.
$screenshot = (Get-FunctionSource 'Save-FailureScreenshot').Extent.Text
if ($screenshot.Contains('Join-Path $root ''gui-failure.png''') -or
    $screenshot -notmatch 'GetTempPath' -or
    $screenshot -notmatch 'gui-failure') {
    throw 'Failed GUI test must retain a screenshot outside its deleted disposable fixture.'
}
# Regression for a visible, empty-caption Salamander window during WM_CREATE/
# LoadConfig. The real application first creates CMAINWINDOW_CLASSNAME with
# an empty title. Identifying it by caption alone loses the wait-chain evidence.
$mainClassSource = Get-Content -LiteralPath (
    Join-Path $PSScriptRoot '..\..\..\src\salamdr1.cpp') -Raw
$expectedMainClass = [regex]::Match(
    $mainClassSource, 'CMAINWINDOW_CLASSNAME\s*=\s*"([^"]+)"').Groups[1].Value
if ([string]::IsNullOrEmpty($expectedMainClass)) {
    throw 'Main window class is not declared in src/salamdr1.cpp.'
}
$mainWindowMethod = [regex]::Match($driverText,
    '(?s)public static IntPtr FindMainWindow\(uint processId\).*?^    }',
    [Text.RegularExpressions.RegexOptions]::Multiline)
$titleGate = Get-FunctionSource 'Wait-ForGuiTitle'
if (-not $mainWindowMethod.Success -or
    -not $mainWindowMethod.Value.Contains('ClassName(window.Handle)') -or
    -not $mainWindowMethod.Value.Contains('GetProcessWindows(processId)') -or
    -not $mainWindowMethod.Value.Contains($expectedMainClass) -or
    $mainWindowMethod.Value.Contains('Title.IndexOf("Open Salamander"') -or
    $startupText -notmatch '(?s)Wait-ForGuiResponsive.*?Wait-ForGuiTitle.*?Focus-TestProcess' -or
    $titleGate.Extent.Text -notmatch 'GetWindowCaption' -or
    $titleGate.Extent.Text -notmatch 'Get-TestDialog' -or
    $titleGate.Extent.Text -notmatch 'SalamanderGuiWaitChain' -or
    $titleGate.Extent.Text -notmatch 'GUI startup did not publish its main window title' -or
    $startupText -notmatch '(?s)WaitForInputIdle\(10000\).*?SalamanderGuiWaitChain.*?Wait-ForGuiResponsive') {
    throw 'GUI startup must identify the exact app class without a caption, then require verified title and responsiveness before input.'
}
Write-Host 'PASS: empty-caption startup window is identified by app class and diagnosed before any destructive input.'

# Regression: a successfully initialized Salamander may stop pumping messages
# while the clipboard is published. A one-off 2500 ms WM_NULL is not a
# conclusive hang. Observe the GUI before clipboard publication, and retry
# read-only WM_NULL after publication for a bounded interval; never dispatch
# clipboard navigation unless the GUI is responsive again.
$command = (Get-FunctionSource 'Invoke-SalamanderCommand').Extent.Text
$goto = (Get-FunctionSource 'Go-ToPath').Extent.Text
if ($goto -notmatch '(?s)Focus-TestProcess.*?Wait-ForGuiResponsive\s+-Context\s+''BeforeClipboard''.*?Set-VerifiedNavigationClipboard.*?Invoke-SalamanderCommand\s+-CommandId\s+775' -or
    $command -notmatch "Wait-ForGuiResponsive\s+-Context\s+'PreCommand775'" -or
    $command -match '2500,\s*\[ref\]\$preflightResult' -or
    $readinessText -notmatch '\[ValidateSet\(''Startup'', ''BeforeClipboard'', ''PreCommand775''\)\]' -or
    $readinessText -notmatch 'GUI startup remained unresponsive' -or
    $readinessText -notmatch 'wait chain' -or
    $readinessText -notmatch 'Context') {
    throw 'GUI pre-navigation readiness must be bounded and measured before and after clipboard publication.'
}
Write-Host 'PASS: GUI clipboard navigation waits for verified responsiveness before and after clipboard publication.'

Write-Host 'PASS: GUI startup readiness is bounded and failure screenshot survives fixture cleanup.'

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
# A successful first F8 must not count as proof for the second ASCII-GUID
# fixture. Verify it and its payload still exist before refreshing the panel,
# and require a round-trip through the test-owned parent before re-selection.
$deleteStart = $driverText.IndexOf(
    '        # Act: delete the exact test-owned directory through Salamander', [StringComparison]::Ordinal)
$deleteEnd = $driverText.IndexOf(
    "        Write-Host 'PASS: Salamander F8 recursively deleted", $deleteStart,
    [StringComparison]::Ordinal)
if ($deleteStart -lt 0 -or $deleteEnd -le $deleteStart) {
    throw 'GUI F8 temporary-directory scenario is missing.'
}
$deleteCase = $driverText.Substring($deleteStart, $deleteEnd - $deleteStart)
$firstDelete = $deleteCase.IndexOf(
    "Wait-Until { -not [IO.Directory]::Exists(" + '$temporaryDirectory)',
    [StringComparison]::Ordinal)
$verifySibling = $deleteCase.IndexOf(
    "Assert-True ([IO.Directory]::Exists(" + '$asciiTemporaryDirectory)',
    [StringComparison]::Ordinal)
$verifyPayload = $deleteCase.IndexOf(
    'Assert-True (Test-Content $asciiLeaf)', [StringComparison]::Ordinal)
$parentRoundtrip = $deleteCase.IndexOf('Go-ToPath $root', [StringComparison]::Ordinal)
$sourceRoundtrip = $deleteCase.IndexOf('Go-ToPath $source', $parentRoundtrip + 1,
    [StringComparison]::Ordinal)
$secondDelete = $deleteCase.IndexOf(
    'Focus-DirectoryRow -Name $asciiTemporaryName', [StringComparison]::Ordinal)
if ($firstDelete -lt 0 -or $verifySibling -le $firstDelete -or
    $verifyPayload -le $verifySibling -or
    $parentRoundtrip -le $verifyPayload -or
    $sourceRoundtrip -le $parentRoundtrip -or
    $secondDelete -le $sourceRoundtrip) {
    throw 'F8 GUI test must preserve the ASCII sibling and reload its source panel before selecting the second folder.'
}
Write-Host 'PASS: F8 GUI test verifies sibling integrity and refreshes the panel before the next selection.'

Write-Host 'PASS: GUI navigation verifies exact clipboard content and retries only safe clipboard writes.'

# A live Salamander can lose foreground focus to a browser while a
# synchronous navigation completes. Recover its verified HWND once, then
# verify the actual panel path without resending an unconfirmed WM_COMMAND.
$recoverFocus = (Get-FunctionSource 'Recover-NavigationForeground').Extent.Text
if ($recoverFocus -notmatch 'Get-TestDialog' -or
    $recoverFocus -notmatch 'Focus-TestProcess' -or
    $recoverFocus -notmatch 'FocusRecoveryAttempted' -or
    $recoverFocus -match 'Invoke-SalamanderCommand|Send-Keys|Set-ClipboardText' -or
    $navigationSource -notmatch 'Recover-NavigationForeground -Diagnostics \$diagnostics' -or
    $navigationSource -notmatch '-not \$diagnostics\.FocusRecoveryAttempted') {
    throw 'Navigation must recover verified foreground once, without re-dispatching on focus loss.'
}

# Exercise the recovery policy without a desktop or invoking Salamander.
& {
    $probe = @{ Foreground = 99; RecoveryCalls = 0; Dialog = $null }
    $process = [pscustomobject]@{ Id = 42 }
    function Get-ActiveProcessId { return [uint32]$probe.Foreground }
    function Get-TestDialog { return $probe.Dialog }
    function Get-ForegroundWindowSummary { return ('PID={0}' -f $probe.Foreground) }
    function Focus-TestProcess {
        $probe.RecoveryCalls++
        $probe.Foreground = 42
    }
    . ([scriptblock]::Create($recoverFocus))
    $state = @{ FocusRecoveryAttempted = $false }
    Recover-NavigationForeground -Diagnostics $state
    if ($probe.RecoveryCalls -ne 1 -or
        -not $state.FocusRecoveryAttempted -or
        $probe.Foreground -ne 42) {
        throw 'First foreground loss must recover the known test window once.'
    }
    $probe.Foreground = 99
    $refused = $false
    try { Recover-NavigationForeground -Diagnostics $state }
    catch { $refused = $_.Exception.Message -match 'repeated external foreground' }
    if (-not $refused -or $probe.RecoveryCalls -ne 1) {
        throw 'A second foreground loss must abort without repeating focus recovery.'
    }
    $state.FocusRecoveryAttempted = $false
    $probe.Dialog = 'Error Changing Directory'
    $refused = $false
    try { Recover-NavigationForeground -Diagnostics $state }
    catch { $refused = $_.Exception.Message -match 'displayed a dialog' }
    if (-not $refused -or $probe.RecoveryCalls -ne 1) {
        throw 'A modal dialog must prevent GUI navigation focus recovery.'
    }
}
Write-Host 'PASS: navigation focus recovers only the verified process once; repeat loss or modal dialog aborts safely.'


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
# PowerShell's -match is case-insensitive, and a pattern ending at
# '$Path' also matches the prefix of '$pathSummary'. Assert whole variable
# tokens with case-sensitive matching to avoid this false positive.
$legacyTimeoutPattern = 'Salamander navigation to \$Path\b'
$compactTimeoutPattern = 'Salamander navigation to \$pathSummary\b'
if ('Salamander navigation to $pathSummary' -cmatch $legacyTimeoutPattern -or
    'Salamander navigation to $Path' -cnotmatch $legacyTimeoutPattern -or
    'Salamander navigation to $pathSummary' -cnotmatch $compactTimeoutPattern -or
    'Salamander navigation to $Path' -cmatch $compactTimeoutPattern) {
    throw 'GUI timeout variable matching must distinguish $Path from $pathSummary.'
}
if ($navigationSource -cmatch $legacyTimeoutPattern -or
    $navigationSource -cnotmatch $compactTimeoutPattern) {
    throw 'Navigation timeout must use compact path diagnostics.'
}
Write-Host 'PASS: extreme GUI navigation failures preserve crash/focus diagnostics without dumping 32k-unit paths.'

# Native debugger attachment is opt-in. This allows Visual Studio to catch
# the original exception before Salamander handles it and exits with code 1.
$attachFunction = Get-FunctionSource 'Wait-ForNativeDebugger'
$attachSource = $attachFunction.Extent.Text
if ($driverText -notmatch 'CheckRemoteDebuggerPresent' -or
    $attachSource -notmatch 'SALAMANDER_GUI_ATTACH_DEBUGGER' -or
    $attachSource -notmatch 'CheckRemoteDebuggerPresent' -or
    $attachSource -notmatch '\$process\.HasExited' -or
    $attachSource -notmatch 'DateTime\]::UtcNow\.AddMinutes\(5\)' -or
    $driverText -notmatch 'Wait-ForNativeDebugger\s+Go-ToPath\s+\$maximumDirectory') {
    throw 'Maximum-path GUI test must support bounded, opt-in native debugger attachment before risky navigation.'
}
if ($attachSource -match 'Invoke-SalamanderCommand|Send-Keys|Set-ClipboardText') {
    throw 'Native debugger attach gate must not mutate GUI input.'
}
Write-Host 'PASS: native debugger can attach before maximum-path navigation without changing ordinary test runs.'



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

# The foreground may be stolen after SendKeys.SendWait('{END}') but before
# the read-only focused filename query. Recover the verified app once without
# replaying END or sending any other keyboard/file-action command.
$baselineRecovery = (Get-FunctionSource 'Recover-BaselineReadFocus').Extent.Text
$baselineBody = [regex]::Match(
    $driverText,
    '(?s)if \(\$BaselineOnly\) \{\s*\$focusBeforeEnd.*?\$passed = \$true').Value
if ($baselineRecovery -notmatch 'Get-TestDialog' -or
    $baselineRecovery -notmatch 'Focus-TestProcess' -or
    $baselineRecovery -notmatch 'Restore-FilePanelFocus -ExpectedPath \$source' -or
    $baselineRecovery -match 'Send-Keys|Invoke-SalamanderCommand|Set-ClipboardText' -or
    $baselineBody -notmatch "Send-Keys '\{END\}'\s+try\s*\{\s*Recover-BaselineReadFocus\s+\`$focusedName = Read-FocusedFilename" -or
    ([regex]::Matches($baselineBody, "Send-Keys '\{END\}'")).Count -ne 1) {
    throw 'Short GUI baseline must recover verified focus read-only, without replaying END.'
}

& {
    $process = [pscustomobject]@{ Id = 42 }
    $source = 'C:\fixture'
    $probe = @{ Foreground = 99; Dialog = $null; ActivationCount = 0; PanelChecks = 0 }
    function Get-ActiveProcessId { return [uint32]$probe.Foreground }
    function Get-TestDialog { return $probe.Dialog }
    function Get-ForegroundWindowSummary { return "PID=$($probe.Foreground)" }
    function Focus-TestProcess { $probe.ActivationCount++; $probe.Foreground = 42 }
    function Restore-FilePanelFocus {
        param([string]$ExpectedPath)
        if ($ExpectedPath -cne $source) { throw 'Wrong panel path.' }
        $probe.PanelChecks++
    }
    . ([scriptblock]::Create($baselineRecovery))

    Recover-BaselineReadFocus
    if ($probe.ActivationCount -ne 1 -or $probe.PanelChecks -ne 1) {
        throw 'External foreground should trigger exactly one verified read-only focus recovery.'
    }

    Recover-BaselineReadFocus
    if ($probe.ActivationCount -ne 1 -or $probe.PanelChecks -ne 1) {
        throw 'Already-focused baseline must not repeat recovery.'
    }

    $probe.Foreground = 99
    $probe.Dialog = 'Error Changing Directory'
    $refused = $false
    try { Recover-BaselineReadFocus }
    catch { $refused = $_.Exception.Message -match 'modal' }
    if (-not $refused -or $probe.ActivationCount -ne 1) {
        throw 'A modal Salamander dialog must block baseline focus recovery.'
    }
}
Write-Host 'PASS: baseline observation tolerates one external focus interruption without replaying input.'


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

# A 775 timeout may originate in Salamander's startup state or in its
# clipboard/file-paste path. Verify a harmless WM_NULL preflight and read-only
# Windows Wait Chain Traversal diagnostics; do not mutate app state on failure.
$dispatchSource = $dispatch.Extent.Text
if ($dispatchSource -notmatch '\$CommandId -eq 775' -or
    $dispatchSource -notmatch "Wait-ForGuiResponsive -Context 'PreCommand775'" -or
    $readinessText -notmatch 'GUI startup remained unresponsive' -or
    $readinessText -notmatch 'GUI responds to WM_NULL' -or
    $readinessText -notmatch 'SalamanderGuiWaitChain\]::Describe' -or
    $readinessText -notmatch 'wait chain=\[' -or
    $driverText -notmatch 'OpenThreadWaitChainSession' -or
    $driverText -notmatch 'GetThreadWaitChain' -or
    $driverText -notmatch 'GetWindowThreadProcessId') {
    throw 'GUI timeout must distinguish pre-existing unresponsiveness and report the UI thread wait chain.'
}
Write-Host 'PASS: GUI command 775 preflights UI responsiveness and captures read-only wait chains.'


# A synchronous CM_CLIPPASTE (775) calls OleGetClipboard and may message the
# clipboard owner's HWND. The owner must have its OWN STA message loop; a
# WinForms Control on the dispatching PowerShell STA can deadlock there.
$ownerClass = [regex]::Match($driverText,
    '(?s)public sealed class SalamanderGuiClipboardOwner : IDisposable.*?^}', 
    [Text.RegularExpressions.RegexOptions]::Multiline)
$navigationClipboard = (Get-FunctionSource 'Set-NativeNavigationClipboard').Extent.Text
if (-not $ownerClass.Success -or
    $ownerClass.Value -notmatch 'System.Threading.Thread' -or
    $ownerClass.Value -notmatch 'SetApartmentState\(System.Threading.ApartmentState.STA\)' -or
    $ownerClass.Value -notmatch 'GetMessage\(' -or
    $ownerClass.Value -notmatch 'PostThreadMessage\(' -or
    $ownerClass.Value -notmatch 'PumpCallerMessages' -or
    $ownerClass.Value -notmatch 'CreateWindowEx\(' -or
    $ownerClass.Value -match 'System.Windows.Forms\.' -or
    $navigationClipboard -notmatch '\[SalamanderGuiClipboardOwner\]::new\(\)' -or
    $navigationClipboard -notmatch '\$script:clipboardOwner.SetText\(\$Text\)' -or
    $navigationClipboard -match '\[Windows.Forms.Control\]::new\(\)') {
    throw 'GUI clipboard owner must pump Win32 messages on a separate STA without WinForms compiler dependencies.'
}
Write-Host 'PASS: GUI clipboard owner pumps native Win32 messages on a dedicated STA.'


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
# The C# Win32 interop deliberately has no static WinForms dependency.
# Keep PowerShell's complete default .NET reference set for its BCL types.
if ($interopSource.Groups[1].Value -match 'System.Windows.Forms\.') {
    throw 'GUI C# interop must not depend on WinForms compiler assemblies.'
}
Add-Type -TypeDefinition $interopSource.Groups[1].Value -ErrorAction Stop
if ($driverText -match 'Get-GuiInteropReferences|guiInteropReferences|ReferencedAssemblies') {
    throw 'GUI driver must retain the default Add-Type framework references.'
}
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

# Unicode Find's modeless search window has different control identities
# than Salamander's file panels. Check the live GUI test wiring without
# claiming a successful interactive run from these static assertions.
$findGui = (Get-FunctionSource 'Test-UnicodeFindGui').Extent.Text
$findSelection = (Get-FunctionSource 'Select-VerifiedFindResult').Extent.Text
$findQuery = (Get-FunctionSource 'Start-FindQuery').Extent.Text
$manager = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\Manage-Salamander.ps1') -Raw
if ($driverText -notmatch '\[switch\]\$UnicodeFindOnly' -or
    $driverText -notmatch 'FindUnicodeSearchWindow' -or
    $driverText -notmatch 'GetWindowThreadProcessId\(child' -or
    $driverText -notmatch 'SelectSingleFindResult' -or
    $driverText -notmatch 'WindowFromPoint\(point\) != list' -or
    $driverText -notmatch 'LVM_GETSELECTEDCOUNT' -or
    $driverText -notmatch 'LVM_ENSUREVISIBLE' -or
    $driverText -notmatch 'WaitForFindSelection' -or
    $driverText -notmatch 'WM_KEYDOWN / VK_HOME' -or
    $driverText -notmatch 'Unicode Find selected result via safe ListView keyboard fallback' -or
    $findQuery -notmatch 'Wait-FindCompleted' -or
    $findSelection -notmatch 'SENTINEL_NOT_A_FIND_PATH' -or
    $findGui -notmatch 'Restore-FilePanelFocus' -or
    $findGui -notmatch 'unique-utf16-probe' -or
    $findGui -notmatch 'Unicode Find refuses destination overwrite' -or
    $findGui -notmatch 'PostFindButton.*5113' -or
    $findGui -notmatch 'Closing an active Unicode Find search leaves Salamander alive' -or
    $manager -notmatch "'--test-gui-unicode-find'" -or
    $manager -notmatch "'-UnicodeFindOnly'") {
    throw 'Unicode Find real GUI test must preserve HWND ownership, UTF-16 identity, operation safety and CLI/test-all integration.'
}
Write-Host 'PASS: Unicode Find modeless GUI test is registered and guards UTF-16 search, result selection and no-overwrite actions.'

# Only one mouse click is allowed: repeating a physical click on the same
# row could be interpreted as a double-click and open the selected file.
# The fallback is a non-destructive Home key sent to the verified ListView.
$selectInterop = [regex]::Match(
    $driverText, '(?s)public static int SelectSingleFindResult\(.*?\r?\n    \}')
if (-not $selectInterop.Success -or
    [regex]::Matches($selectInterop.Value, 'mouse_event\(').Count -ne 2 -or
    $selectInterop.Value -notmatch 'VerifiedChild\(window, pid, 5117\)' -or
    $selectInterop.Value -notmatch 'WaitForFindSelection' -or
    $selectInterop.Value -notmatch '0x0100' -or
    $selectInterop.Value -notmatch '0x0101') {
    throw 'Unicode Find selection must use a single checked click and a safe keyboard fallback.'
}
Write-Host 'PASS: Unicode Find selection is bounded, diagnosed and never retries a potentially opening mouse click.'


# The new Find GUI gate covers explicitly unsupported shell and legacy
# actions without invoking the external association/plug-in boundary.
# It also exercises stale-result refusal, cancellation and window disposal.
$findNotice = (Get-FunctionSource 'Assert-FindNotice').Extent.Text
$findGui = (Get-FunctionSource 'Test-UnicodeFindGui').Extent.Text
if ($driverText -notmatch 'FindUnicodeNotice' -or
    $findNotice -notmatch 'DescribeWindow' -or
    $findNotice -notmatch 'PostVerifiedFindNoticeClose' -or
    $findNotice -match 'PostVerifiedFindNoticeOk' -or
    $driverText -notmatch 'GetWindow\(notice, 4\) != findWindow' -or
    $driverText -notmatch 'ClassName\(notice\) != "#32770"' -or
    $driverText -notmatch 'noticePid != pid' -or
    $driverText -notmatch 'PostMessageW\(notice, 0x0010, UIntPtr\.Zero, IntPtr\.Zero\)' -or
    $driverText -match 'PostMessageW\(notice, 0x0111, new UIntPtr\(1\)' -or
    $findGui -notmatch 'Assert-FindNotice -ExpectedText' -or
    $findGui -notmatch 'Refused shell open preserves long-path file content' -or
    $findGui -notmatch 'Legacy advanced Find refusal preserves' -or
    $findGui -notmatch 'Unicode Find refuses long-path recycling' -or
    $findGui -notmatch 'modified result before file operations' -or
    $findGui -notmatch '5108' -or
    $findGui -notmatch 'Search cancelled:' -or
    $findGui -notmatch 'joins an active search worker' -or
    $findGui -notmatch 'cancelProbePath' -or
    $findGui -notmatch '\[IO\.File\]::Delete\(\$cancelProbePath\)') {
    throw 'Unicode Find GUI integration must preserve safe refusals, stale-hit protection and observable cancellation.'
}
Write-Host 'PASS: Unicode Find GUI scenarios cover shell/legacy/recycle refusals, stale hits and active worker cancellation.'


# Explicit acceptance gates must remain separate from --test-all until the
# native shell-restore and built plug-in checks have passed on real Windows.
$recycleLookup = (Get-FunctionSource 'Find-VerifiedRecycledFixtureItem').Extent.Text
$recycleRestore = (Get-FunctionSource 'Restore-VerifiedRecycledFixtureItem').Extent.Text
$pluginContractPath = Join-Path $PSScriptRoot 'Test-PluginBinary-Contract.ps1'
$pluginTokens = $null
$pluginErrors = $null
$pluginAst = [System.Management.Automation.Language.Parser]::ParseFile(
    $pluginContractPath, [ref]$pluginTokens, [ref]$pluginErrors)
if ($null -eq $pluginAst -or @($pluginErrors).Count -gt 0) {
    throw 'Plug-in PE ABI test script contains PowerShell syntax errors.'
}
$pluginText = Get-Content -LiteralPath $pluginContractPath -Raw
if ($driverText -notmatch '\[switch\]\$VerifyRecycleRestore' -or
    $recycleLookup -notmatch 'System\.Recycle\.DeletedFrom' -or
    $recycleLookup -notmatch 'OrdinalIgnoreCase' -or
    $recycleRestore -notmatch 'destination already exists' -or
    $recycleRestore -notmatch '\$restoreVerb\.DoIt\(\)' -or
    $recycleRestore -notmatch "Wiederherstellen" -or
    $driverText -notmatch 'Unicode Recycle Bin restore preserves exact UTF-8 file bytes' -or
    $manager -notmatch "'--test-recycle-restore'" -or
    $manager -notmatch "'-VerifyRecycleRestore'" -or
    $manager -notmatch "'--test-plugin-exports'" -or
    $pluginText -notmatch 'SalamanderPluginEntry' -or
    $pluginText -notmatch 'SalamanderPluginGetReqVer' -or
    $pluginText -notmatch '8664' -or
    $pluginText -match 'LoadLibrary|Add-Type') {
    throw 'Opt-in Unicode Recycle Bin restore or non-executing plug-in ABI acceptance gate has regressed.'
}
Write-Host 'PASS: opt-in Recycle Bin restoration checks exact Unicode identity; plug-in ABI audit reads binaries without loading them.'


# The opt-in plug-in load test exercises Salamander's own Plugin Manager,
# not an arbitrary DLL LoadLibrary call or a guessed menu accelerator.
# It must verify the dialog's HWND/PID/controls before any WM_COMMAND and
# assert exact paths for all four target modules in the child process.
$pluginLoadFixture = $driverText
if ($pluginLoadFixture -notmatch '\[switch\]\$PluginLoadSmokeOnly' -or
    $pluginLoadFixture -notmatch 'FindPluginManagerWindow' -or
    $pluginLoadFixture -notmatch 'PostVerifiedPluginManagerOpen' -or
    $pluginLoadFixture -notmatch 'PostVerifiedPluginTestAll' -or
    $pluginLoadFixture -notmatch 'GetBlockingPluginDialog' -or
    $pluginLoadFixture -notmatch 'Blocking plug-in initialization dialog' -or
    $pluginLoadFixture -notmatch 'Missing target plug-in modules' -or
    $pluginLoadFixture -notmatch 'Get-MissingPictViewRuntimeFiles' -or
    $manager -notmatch 'Get-MissingPictViewRuntimeFiles' -or
    $pluginLoadFixture -notmatch 'GetWindow\(top.Handle, 4\) != mainWindow' -or
    $pluginLoadFixture -notmatch 'GetDlgItem\(top.Handle, 2601\)' -or
    $pluginLoadFixture -notmatch 'VerifiedChild\(dialog, pid, 2616\)' -or
    $pluginLoadFixture -notmatch '\$process\.Modules' -or
    $pluginLoadFixture -notmatch 'OrdinalIgnoreCase' -or
    $pluginLoadFixture -notmatch 'Plugin test preserved original Unicode fixture bytes' -or
    $manager -notmatch "'--test-plugin-load'" -or
    $manager -notmatch "'-PluginLoadSmokeOnly'") {
    throw 'Opt-in plug-in load test must verify UI ownership, all four real modules, and unchanged source bytes.'
}
Write-Host 'PASS: opt-in plug-in initialization smoke is owned, bounded and excluded from automatic GUI mode selection.'
