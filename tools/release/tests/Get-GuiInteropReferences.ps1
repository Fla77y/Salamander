#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
    Resolve C# reference assemblies for the WinForms-based GUI test interop.
.DESCRIPTION
    In PowerShell 7, Add-Type -ReferencedAssemblies replaces its implicit
    framework reference set. Include the PowerShell reference assemblies and
    the complete set of managed Windows Desktop runtime assemblies from
    the SAME runtime directory as System.Windows.Forms.Control. This avoids
    recurring CS0012 failures as WinForms types depend on Primitives, Core,
    and other split assemblies.
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

    # WinForms on .NET 11 exposes transitive interop types from assemblies
    # such as System.Windows.Forms.Primitives and System.Private.Windows.Core.
    # Keep the entire SAME WindowsDesktop runtime dependency set together.
    # Do not pass native DLLs (such as D3DCompiler) to the C# compiler:
    # they are not valid metadata references and cause CS0009.
    foreach ($path in [IO.Directory]::GetFiles($desktopDirectory, '*.dll')) {
        try {
            $assemblyName = [Reflection.AssemblyName]::GetAssemblyName($path)
        }
        catch [BadImageFormatException] {
            continue # Native DLL, not a managed compiler reference.
        }
        if ([string]::IsNullOrWhiteSpace($assemblyName.Name)) {
            throw "Windows Desktop assembly has no name: $path"
        }
        # WindowsDesktop implementations take precedence over similarly
        # named PowerShell framework references. Every dependency stays on
        # exactly the same WindowsDesktop runtime version as WinForms.
        $assemblies[$assemblyName.Name] = $path
    }

    foreach ($required in @(
        'System.Windows.Forms',
        'System.Windows.Forms.Primitives',
        'System.Private.Windows.Core'
    )) {
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
