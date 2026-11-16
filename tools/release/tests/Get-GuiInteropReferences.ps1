#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
    Resolve C# reference assemblies for the WinForms-based GUI test interop.
.DESCRIPTION
    In PowerShell 7, Add-Type -ReferencedAssemblies replaces its implicit
    framework reference set. Include the current PowerShell reference
    assemblies and the two Windows Forms assemblies needed by the dedicated
    clipboard owner. Loading Forms with Add-Type -AssemblyName is not enough
    to make it available to the C# compiler.
#>
function Get-GuiInteropReferences {
    $referenceDirectory = Join-Path $PSHOME 'ref'
    if (-not (Test-Path -LiteralPath $referenceDirectory -PathType Container)) {
        throw "PowerShell C# reference directory is unavailable: $referenceDirectory"
    }
    $frameworkReferences = @([IO.Directory]::GetFiles($referenceDirectory, '*.dll'))
    if ($frameworkReferences.Count -eq 0) {
        throw "PowerShell C# reference directory has no DLLs: $referenceDirectory"
    }

    $assemblies = [Collections.Generic.Dictionary[string,string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $frameworkReferences) {
        $assemblies[[IO.Path]::GetFileNameWithoutExtension($path)] = $path
    }
    foreach ($path in @(
        [Windows.Forms.Control].Assembly.Location,
        [Windows.Forms.Keys].Assembly.Location
    )) {
        if ([string]::IsNullOrWhiteSpace($path) -or
            -not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Windows Forms compiler reference is unavailable: $path"
        }
        # Prefer the loaded Windows Forms runtime version if a platform
        # reference with the same assembly identity is already present.
        $assemblies[[IO.Path]::GetFileNameWithoutExtension($path)] = $path
    }
    return @($assemblies.Values)
}
