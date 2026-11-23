#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later

# Recognize an exact public export name in a dumpbin /exports table row.
# C++ exports can have a decorated internal name and demangled signature;
# these must not be mistaken for the public ABI name.
function Test-PeNamedExport {
    param(
        [Parameter(Mandatory)][string]$Report,
        [Parameter(Mandatory)][string]$Name
    )
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }

    # A real row begins with ordinal, hint, RVA and exact public name.
    # MSVC may append "= ?DecoratedName@@ (human-readable C++ signature)".
    # Reject partial names, forwarded entries and non-export diagnostic text.
    $pattern = '(?m)^[ \t]*[0-9]+[ \t]+[0-9A-Fa-f]+[ \t]+[0-9A-Fa-f]+[ \t]+' +
               [regex]::Escape($Name) +
               '(?:[ \t]+=[ \t]+\S+(?:[ \t]+\([^\r\n]*\))?)?[ \t]*\r?$'
    return [regex]::IsMatch($Report, $pattern)
}


# Read the public names declared in a linker module-definition file.
# Supports legacy one-line "EXPORTS Foo" and conventional EXPORTS sections
# with ordinals, PRIVATE flags and internal aliases. This is source evidence,
# not a guarantee that the linker produced the corresponding PE export.
function Test-ModuleDefinitionExport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Definition,
        [Parameter(Mandatory)][string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    $inExports = $false
    foreach ($rawLine in ($Definition -split '\r?\n')) {
        # .def semicolon comments must never count as declarations.
        $line = ($rawLine -split ';', 2)[0].Trim()
        if ($line.Length -eq 0) { continue }

        if ($line -match '^EXPORTS(?:\s+(.*))?$') {
            $inExports = $true
            $candidate = [string]$Matches[1]
        }
        elseif (-not $inExports) { continue }
        elseif ($line -match '^(LIBRARY|NAME|DESCRIPTION|VERSION|SECTIONS|STACKSIZE|HEAPSIZE)(\s|$)') {
            $inExports = $false
            continue
        }
        else {
            $candidate = $line
        }

        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $token = [regex]::Match($candidate.Trim(), '^(?<public>[^\s=]+)(?:\s|=|$)')
        if ($token.Success -and
            [string]::Equals($token.Groups['public'].Value,
                             $Name, [StringComparison]::Ordinal)) {
            return $true
        }
    }
    return $false
}
