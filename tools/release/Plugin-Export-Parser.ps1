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
