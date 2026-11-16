#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later

# Recognize an exact *public* export name in a dumpbin /exports table row.
# C++ exports can have "PublicName = ?DecoratedInternalName@@" suffixes;
# that internal symbol must never be mistaken for the public ABI name.
function Test-PeNamedExport {
    param(
        [Parameter(Mandatory)][string]$Report,
        [Parameter(Mandatory)][string]$Name
    )
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }

    # Only a real "ordinal hint RVA public-name" row qualifies.
    # MSVC may append "= ?DecoratedName@@ (human-readable C++ signature)".
    # Accept the complete demangled signature (with nested parentheses),
    # but not partial names, free-form annotations or forwarded exports.
    $pattern = '(?m)^[ \t]*[0-9]+[ \t]+[0-9A-Fa-f]+[ \t]+[0-9A-Fa-f]+[ \t]+' +
               [regex]::Escape($Name) +
               '(?:[ \t]+=[ \t]+\S+(?:[ \t]+\([^\r\n]*\))?)?[ \t]*\r?
    return [regex]::IsMatch($Report, $pattern)
}

    return [regex]::IsMatch($Report, $pattern)
}
