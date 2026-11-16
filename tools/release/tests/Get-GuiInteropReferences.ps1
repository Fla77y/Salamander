#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
    Resolve complete, compatible .NET C# compiler references for GUI tests.
.DESCRIPTION
    -ReferencedAssemblies replaces Add-Type's implicit runtime references.
    PowerShell's PSHOME/ref facades do not include the runtime implementation
    System.Private.CoreLib, so combining those facades only with WinForms
    produces CS1069 for System.Threading.Thread. Use the host's trusted
    platform assemblies (TPA) instead, and merge the managed Windows Desktop
    assemblies from the same runtime as the loaded WinForms Control type.
#>
function Get-GuiInteropReferences {
    $trustedAssemblies = [AppContext]::GetData('TRUSTED_PLATFORM_ASSEMBLIES')
    if ([string]::IsNullOrWhiteSpace([string]$trustedAssemblies)) {
        throw 'The .NET host did not expose TRUSTED_PLATFORM_ASSEMBLIES.'
    }

    $assemblies = [Collections.Generic.Dictionary[string,string]]::new(
        [StringComparer]::OrdinalIgnoreCase)

    # These are the runtime's own compiler references, including
    # System.Private.CoreLib.dll, System.Runtime.dll and threading types.
    # Mixing PSHOME/ref facades and runtime assemblies can cause type identity
    # conflicts; do not read PSHOME/ref here.
    foreach ($path in ([string]$trustedAssemblies).Split(
        [IO.Path]::PathSeparator, [StringSplitOptions]::RemoveEmptyEntries)) {
        if (-not [IO.File]::Exists($path)) {
            throw "Trusted .NET reference does not exist: $path"
        }
        $name = [IO.Path]::GetFileNameWithoutExtension($path)
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $assemblies[$name] = $path
        }
    }

    $windowsFormsPath = [Windows.Forms.Control].Assembly.Location
    if ([string]::IsNullOrWhiteSpace($windowsFormsPath) -or
        -not [IO.File]::Exists($windowsFormsPath)) {
        throw "Windows Forms compiler reference is unavailable: $windowsFormsPath"
    }
    $desktopDirectory = [IO.Path]::GetDirectoryName($windowsFormsPath)

    # WinForms on .NET 11 uses multiple managed WindowsDesktop assemblies,
    # including System.Windows.Forms.Primitives and System.Private.Windows.Core.
    # Include the entire managed set from exactly this desktop runtime.
    foreach ($path in [IO.Directory]::GetFiles($desktopDirectory, '*.dll')) {
        try {
            $assemblyName = [Reflection.AssemblyName]::GetAssemblyName($path)
        }
        catch [BadImageFormatException] {
            continue # Native DLLs are not valid C# metadata references.
        }
        if ([string]::IsNullOrWhiteSpace($assemblyName.Name)) {
            throw "Windows Desktop assembly has no name: $path"
        }
        $assemblies[$assemblyName.Name] = $path
    }

    foreach ($required in @(
        'System.Private.CoreLib',
        'System.Runtime',
        'System.Windows.Forms',
        'System.Windows.Forms.Primitives',
        'System.Private.Windows.Core'
    )) {
        if (-not $assemblies.ContainsKey($required)) {
            throw "Required .NET C# compiler reference is absent: $required"
        }
    }
    foreach ($required in @(
        'System.Windows.Forms',
        'System.Windows.Forms.Primitives',
        'System.Private.Windows.Core'
    )) {
        if (-not [string]::Equals(
            [IO.Path]::GetDirectoryName($assemblies[$required]),
            $desktopDirectory, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Windows Desktop C# compiler reference has a mismatched runtime: $required"
        }
    }
    return @($assemblies.Values)
}
