#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
    Classifies failures of the opt-in PictView-in-Salamander GUI smoke.
.DESCRIPTION
    Does not mutate the user environment, registry, viewer associations or
    installed plugins. Operates only on collected dialog text and module state.
#>
function Get-PictViewHostFailureHint {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$DialogText = '',
        [bool]$PictViewResident = $false,
        [AllowEmptyString()][string]$ActualViewerClass = ''
    )

    # Internal viewer is conclusive evidence that F3 did not select WIC.
    # Do not conflate a functioning internal viewer with a decode failure.
    if ($ActualViewerClass -ceq "Salamander's Viewer Window") {
        return ('F3 opened the built-in Salamander internal text viewer for the test BMP, ' +
                'not PictView. The file and keyboard navigation worked, but *.bmp is ' +
                'not currently routed to the PictView WIC plugin. Check Plugins > ' +
                'Plugins Manager for an installed PictView, then Options > ' +
                'Configuration > Viewers: add or move its *.bmp association ahead ' +
                'of the internal *.* rule. Rebuild alone will not override ' +
                'existing user Viewer settings.')
    }

    $missingVariable = [regex]::Match(
        $DialogText,
        '(?i)Environment variable\s+"(?<name>[A-Za-z_][A-Za-z0-9_]*)"\s+was not found\.?'
    )
    if ($missingVariable.Success) {
        $name = $missingVariable.Groups['name'].Value
        return ("Salamander reported missing environment variable '$name' while opening the test BMP. " +
                'This is consistent with a configured external Viewer command and is not evidence ' +
                'of a WIC decoder failure. Check Options > Configuration > Viewers: assign the ' +
                '*.bmp mask to the PictView plugin, before matching external viewer rules; ' +
                'check Plugins > Plugins Manager for the PictView installation. ' +
                'Do not create a placeholder environment variable: the test must actually run PictView.')
    }

    if (-not $PictViewResident) {
        return ('PictView SPL is not resident after F3. Check Options > Configuration > ' +
                'Viewers for the *.bmp association and Plugins > Plugins Manager. ' +
                'An initial load followed by unload is also possible; inspect the original error dialog.')
    }

    return ('PictView SPL is resident, but its WIC viewer window did not appear. ' +
            'Inspect viewer startup, CanViewFile, codec support and the original error dialog.')
}
