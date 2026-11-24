#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Parse all repository-managed PowerShell scripts before execution.
# This catches interpolation errors that a textual source contract misses.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))

# RED: this exact bad interpolation caused the continuity test to fail before
# its first assertion. Verify the native PowerShell parser rejects the fixture.
$invalidScript = '"Invalid variable interpolation: $id:"'
$fixtureTokens = $null
$fixtureErrors = $null
$null = [System.Management.Automation.Language.Parser]::ParseInput(
    $invalidScript, [ref]$fixtureTokens, [ref]$fixtureErrors)
if ($null -eq $fixtureErrors -or $fixtureErrors.Count -eq 0) {
    throw 'The syntax preflight did not detect the original interpolated-colon defect.'
}

$rootScripts = @(Get-ChildItem -LiteralPath $repository -Filter '*.ps1' -File)
$toolScripts = @(Get-ChildItem -LiteralPath (Join-Path $repository 'tools') -Filter '*.ps1' -File -Recurse)
$files = @($rootScripts + $toolScripts | Sort-Object FullName -Unique)
if ($files.Count -eq 0) { throw 'No PowerShell scripts found for syntax preflight.' }

$problems = [System.Collections.Generic.List[string]]::new()
foreach ($file in $files) {
    $tokens = $null
    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName, [ref]$tokens, [ref]$parseErrors)
    if ($null -ne $parseErrors) {
        foreach ($parseError in $parseErrors) {
            $relativePath = [IO.Path]::GetRelativePath($repository, $file.FullName)
            [void]$problems.Add(('{0}:{1}:{2}: {3}' -f
                $relativePath, $parseError.Extent.StartLineNumber,
                $parseError.Extent.StartColumnNumber, $parseError.Message))
        }
    }
}

if ($problems.Count -gt 0) {
    foreach ($problem in $problems) {
        Write-Host "PARSE FAIL: $problem" -ForegroundColor Red
    }
    throw "$($problems.Count) PowerShell syntax error(s) in $($files.Count) script(s)."
}
Write-Host "PASS: all $($files.Count) repository PowerShell scripts parse cleanly; interpolated-colon negative test detected."
