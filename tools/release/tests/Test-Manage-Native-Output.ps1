#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
    Regression test for logging native child process output in Manage-Salamander.
.DESCRIPTION
    Loads only Invoke-Native from the management script's parsed AST.
    Checks that stdout and stderr are forwarded through Write-Host's
    information stream and that a nonzero exit code still fails.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$managerPath = Join-Path $PSScriptRoot '..\..\Manage-Salamander.ps1'
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    $managerPath, [ref]$tokens, [ref]$parseErrors)
if (@($parseErrors).Count -gt 0) {
    throw "Management script contains PowerShell parse errors: $($parseErrors -join '; ')"
}

$functions = @($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -ceq 'Invoke-Native'
}, $true))
if ($functions.Count -ne 1) {
    throw "Expected exactly one Invoke-Native function; got $($functions.Count)."
}
. ([scriptblock]::Create($functions[0].Extent.Text))

$successScript = @'
[Console]::Out.WriteLine('MANAGE_NATIVE_STDOUT_OK')
[Console]::Error.WriteLine('MANAGE_NATIVE_STDERR_OK')
exit 0
'@
$successOutput = @(
    & { Invoke-Native 'pwsh.exe' @('-NoLogo', '-NoProfile', '-Command', $successScript) } 6>&1 |
        ForEach-Object { [string]$_ }
)
if ($successOutput -notcontains 'MANAGE_NATIVE_STDOUT_OK' -or
    $successOutput -notcontains 'MANAGE_NATIVE_STDERR_OK') {
    throw ('Invoke-Native lost a child stream: ' + ($successOutput -join ' | '))
}
Write-Host 'PASS: native child stdout and stderr are forwarded to the management transcript.'

$failureScript = @'
[Console]::Out.WriteLine('MANAGE_NATIVE_STDOUT_FAIL')
[Console]::Error.WriteLine('MANAGE_NATIVE_STDERR_FAIL')
exit 17
'@
$seen = [Collections.Generic.List[string]]::new()
$failure = $null
try {
    & { Invoke-Native 'pwsh.exe' @('-NoLogo', '-NoProfile', '-Command', $failureScript) } 6>&1 |
        ForEach-Object { [void]$seen.Add([string]$_) }
}
catch {
    $failure = $_.Exception.Message
}
if ($seen -notcontains 'MANAGE_NATIVE_STDOUT_FAIL' -or
    $seen -notcontains 'MANAGE_NATIVE_STDERR_FAIL' -or
    $null -eq $failure -or $failure -notmatch 'Exitcode 17') {
    throw ("Invoke-Native did not preserve output and exit code 17: " +
           "messages=[$($seen -join ' | ')]; error=[$failure]")
}
Write-Host 'PASS: native child output survives a nonzero exit code and the failure propagates.'
