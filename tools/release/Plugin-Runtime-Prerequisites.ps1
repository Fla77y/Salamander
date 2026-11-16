#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later

# Find absent x64 PictView helper files without loading any DLL.
# Only a built pictview.spl activates this optional prerequisite check.
# Empty output means "no missing files", NOT "plug-in initialized".
function Get-MissingPictViewRuntimeFiles {
    param([Parameter(Mandatory)][string]$BuildDirectory)

    $pluginDir = Join-Path ([IO.Path]::GetFullPath($BuildDirectory)) 'plugins\pictview'
    if (-not [IO.File]::Exists((Join-Path $pluginDir 'pictview.spl'))) {
        return
    }

    foreach ($filename in @('SalPVEnv.exe', 'PVW32Cnv.dll')) {
        $candidate = Join-Path $pluginDir $filename
        if (-not [IO.File]::Exists($candidate)) {
            Write-Output $candidate
        }
    }
}
