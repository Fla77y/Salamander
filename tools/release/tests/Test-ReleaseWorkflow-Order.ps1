#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
    Prevent staging public artifacts after a step that already consumes them.
.DESCRIPTION
    Static, side-effect-free check of the actual Windows release job order.
    Ensures the smoke installer uses built dist artifacts, while the upload
    consumes only the strictly checked public staging directory.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$workflowPath = Join-Path $PSScriptRoot '..\..\..\.github\workflows\pr-release-package.yml'
$source = [IO.File]::ReadAllText([IO.Path]::GetFullPath($workflowPath))

# Arrange: obtain exact step blocks from the tracked release workflow.
$smokeStart = $source.IndexOf('      - name: Smoke-test silent Release installer and uninstaller', [StringComparison]::Ordinal)
$stagingStart = $source.IndexOf('      - name: Stage and verify exact public Release files', [StringComparison]::Ordinal)
$uploadStart = $source.IndexOf('      - name: Upload redistributable Release outputs only', [StringComparison]::Ordinal)
if ($smokeStart -lt 0 -or $stagingStart -le $smokeStart -or $uploadStart -le $stagingStart) {
    throw 'Release smoke, public staging and upload steps must exist in the correct order.'
}
$smoke = $source.Substring($smokeStart, $stagingStart - $smokeStart)
$staging = $source.Substring($stagingStart, $uploadStart - $stagingStart)
$upload = $source.Substring($uploadStart)

# Act / Assert: the smoke must use an existing installer; staging is checked
# before upload, and uploaded files must only come from the verified directory.
if ($smoke -notmatch 'OpenSal\\dist\\OpenSalamander-Release-x64-Setup\.exe' -or
    $smoke -match 'public-release' -or
    $staging -notmatch '\-RequirePublicOnly' -or
    $upload -notmatch 'OpenSal\\public-release\\OpenSalamander-Release-x64-Setup\.exe' -or
    $upload -match 'OpenSal\\dist\\') {
    throw 'Release workflow must install from built dist and upload only exact validated public artifacts.'
}
Write-Host 'PASS: release pipeline smoke, public staging and upload use correct artifact paths.'
