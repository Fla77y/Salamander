#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
    Resolve C# reference assemblies for the WinForms-based GUI test interop.
.DESCRIPTION
    In PowerShell 7, Add-Type -ReferencedAssemblies replaces its implicit
    framework reference set. Include the PowerShell reference assemblies and
    all relevant Windows Desktop assemblies from the SAME runtime directory
    as System.Windows.Forms.Control. In .NET 11 the control class also needs
    System.Windows.Forms.Primitives (CS0012), not just System.Windows.Forms.
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

    $windowsFormsPath = [Windows.Forms.Control].Assembly.Location
    if ([string]::IsNullOrWhiteSpace($windowsFormsPath) -or
        -not (Test-Path -LiteralPath $windowsFormsPath -PathType Leaf)) {
        throw "Windows Forms compiler reference is unavailable: $windowsFormsPath"
    }
    $desktopDirectory = [IO.Path]::GetDirectoryName($windowsFormsPath)

    # The desktop shared framework splits WinForms into multiple assemblies.
    # Include the complete Forms/Drawing families plus their Windows Desktop
    # helpers; deduplicate by assembly name, with desktop versions taking
    # precedence over any identically named PowerShell reference assembly.
    foreach ($pattern in @(
        'System.Windows.Forms*.dll',
        'System.Drawing*.dll',
        'Accessibility.dll',
        'Microsoft.Win32.SystemEvents.dll',
        'System.Windows.Extensions.dll'
    )) {
        foreach ($path in [IO.Directory]::GetFiles($desktopDirectory, $pattern)) {
            $assemblies[[IO.Path]::GetFileNameWithoutExtension($path)] = $path
        }
    }

    foreach ($required in @('System.Windows.Forms', 'System.Windows.Forms.Primitives')) {
        if (-not $assemblies.ContainsKey($required) -or
            -not [string]::Equals(
                [IO.Path]::GetDirectoryName($assemblies[$required]),
                $desktopDirectory, [StringComparison]::OrdinalIgnoreCase)) {
            throw ("Required Windows Desktop C# reference '{0}' was not found " +
                   "alongside {1}." -f $required, $windowsFormsPath)
        }
    }
    return @($assemblies.Values)
}
