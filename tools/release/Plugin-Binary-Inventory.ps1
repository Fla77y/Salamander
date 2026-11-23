#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later

# Discover every built SPL without assuming that the source .def file has
# the same name or location as the DLL output (e.g. DiskMapPlugin.def).
# Unexpected layouts fail closed; otherwise a plug-in could escape ABI tests.
function Get-BuiltPluginNames {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$BuildDirectory)

    $pluginRoot = Join-Path $BuildDirectory 'plugins'
    if (-not (Test-Path -LiteralPath $pluginRoot -PathType Container)) {
        throw [InvalidOperationException]::new("Built plug-in directory is missing: $pluginRoot")
    }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($module in @(Get-ChildItem -LiteralPath $pluginRoot -Recurse -File -Filter '*.spl')) {
        $relative = [IO.Path]::GetRelativePath($pluginRoot, $module.FullName)
        $parts = @($relative -split '[\\/]')
        if ($parts.Count -ne 2 -or
            -not [string]::Equals($parts[0], [IO.Path]::GetFileNameWithoutExtension($parts[1]),
                                 [StringComparison]::OrdinalIgnoreCase) -or
            -not $seen.Add($parts[0])) {
            throw [InvalidOperationException]::new(
                "Unexpected or duplicate built plug-in binary: $($module.FullName)")
        }
        $parts[0]
    }
}
