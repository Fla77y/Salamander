#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Vcvars64,
    [Parameter(Mandatory)][string]$BuildRoot,
    [Parameter(Mandatory)][ValidateSet('Debug','Release')][string]$Configuration
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
if (-not $IsWindows) { throw 'Renamer native contracts require the Windows MSVC toolchain.' }
if (-not (Test-Path -LiteralPath $Vcvars64 -PathType Leaf)) { throw "MSVC toolchain missing: $Vcvars64" }
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$work = Join-Path ([IO.Path]::GetFullPath($BuildRoot)) ('tests\renamer-native-' + $Configuration + '-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)

# Compile verbatim product definitions, not frozen copies or a second parser.
# These are intentionally isolated source-fragment contracts, NOT a link test
# of the complete product translation units or the installed plugin.
# Legacy source formatting is an explicit extraction prerequisite. Ambiguous
# or missing signatures/terminators fail the test rather than silently skipping.
function Get-ProductDefinition {
    param([string]$Relative,[string]$Signature,[string]$Terminator = '}')
    $source = [IO.File]::ReadAllText((Join-Path $repository $Relative)).Replace([string][char]13 + [char]10,[string][char]10)
    $signature = [regex]::Escape($Signature.Replace([string][char]13 + [char]10,[string][char]10))
    $pattern = '(?ms)^' + $signature + '[ \t]*\n\{.*?^' + [regex]::Escape($Terminator) + '[ \t]*(?=\n|\z)'
    $found = [regex]::Matches($source,$pattern)
    if ($found.Count -ne 1) { throw "Expected one exact product definition: $Relative / $Signature; found $($found.Count)." }
    $match = $found[0]
    $line = 1 + [regex]::Matches($source.Substring(0,$match.Index),'\n').Count
    return ('#line {0} "{1}"' -f $line,$Relative.Replace('\','/')) + [Environment]::NewLine + $match.Value
}

$utils = 'src/plugins/renamer/utils.cpp'
$rename = 'src/plugins/renamer/crenamer.cpp'
$header = 'src/plugins/renamer/crenamer.h'
$counter = 'src/plugins/renamer/crename2.cpp'
$nl = [string][char]10
$types = @(
    Get-ProductDefinition $header 'enum CChangeCase' '};'
    Get-ProductDefinition $header 'enum CRenameSpec' '};'
    Get-ProductDefinition $header 'enum CRenamerErrorType' '};'
    Get-ProductDefinition $header 'struct CExecuteNewNameParam' '};'
)
$definitions = @(
    Get-ProductDefinition $utils ('const char*' + $nl + 'StrQChr(const char* start, const char* end, char q, char c)')
    Get-ProductDefinition $utils 'BOOL IsValidInt(const char* begin, const char* end, BOOL isSigned)'
    Get-ProductDefinition $utils 'BOOL IsValidFloat(const char* begin, const char* end)'
    Get-ProductDefinition $utils 'char* StripRoot(char* path, int rootLen)'
    Get-ProductDefinition $utils 'int CutTrailingDots(char* name, int len, CRenameSpec spec)'
    Get-ProductDefinition $utils 'char* Replace(char* string, char s, char d)'
    Get-ProductDefinition 'src/plugins/renamer/rendlg4.cpp' 'BOOL EscapeQuotes(const char* string, char* escaped)'
    Get-ProductDefinition $rename ('void ChangeCase(CChangeCase change, char* dst, const char* src,' + $nl + '                const char* start, const char* end)')
    Get-ProductDefinition $rename 'BOOL SafeCopy(char* dest, int max, int& pos, const char* source, int count)'
    Get-ProductDefinition $rename ('BOOL SafeCopy(char* dest, int max, int& pos, const char* source, int count,' + $nl + '              CChangeCase changeCase)')
    Get-ProductDefinition $rename 'BOOL CRenamer::ValidetaReplacePattern()'
    Get-ProductDefinition $rename 'BOOL CRenamer::SafeSubst(char* dest, int max, int& pos)'
    Get-ProductDefinition 'src/plugins/renamer/renamer.cpp' 'int SalPrintf(char* buffer, unsigned count, const char* format, ...)'
    Get-ProductDefinition 'src/plugins/renamer/varstr.cpp' ('BOOL CVarString::CVariable::SetArguments(const char* argStart, const char* argEnd,' + $nl + '                                         int& error, const char*& errorPos1, const char*& errorPos2)')
    Get-ProductDefinition $counter 'class CVariableEx : public CVarString::CVariable' '};'
    Get-ProductDefinition $counter 'class CVarCounter : public CVariableEx' '};'
)
$generatedTypes = Join-Path $work 'renamer_native_types.inc'
[IO.File]::WriteAllText($generatedTypes,($types -join ($nl + $nl)) + $nl,[Text.UTF8Encoding]::new($false))
$generated = Join-Path $work 'renamer_native_product.inc'
[IO.File]::WriteAllText($generated,($definitions -join ($nl + $nl)) + $nl,[Text.UTF8Encoding]::new($false))
$test = Join-Path $repository 'tools\tests\renamer_native_contracts.cpp'
$shared = Join-Path $repository 'src\plugins\shared'
$flags = if ($Configuration -eq 'Debug') { '/MDd /Od /Zi /D_DEBUG' } else { '/MD /O2 /DNDEBUG' }
# Warning-as-error is deliberately not enabled for verbatim legacy fragments:
# the known discarded FALSE expression must reach the runtime RED assertions.
# No compiler errors or executable exit codes are suppressed.
$cmd = Join-Path $work 'compile.cmd'
@(
    '@echo off'
    'call "%~1" >nul'
    'if errorlevel 1 exit /b 1'
    ('cl.exe /nologo /W4 /std:c++17 /EHsc /utf-8 /D_CRT_SECURE_NO_WARNINGS ' + $flags +
        ' /I"' + $work + '" /I"' + $shared + '" /Fo"renamer_native_contracts.obj" /Fd"renamer_native_contracts.pdb" /Fe"renamer_native_contracts.exe" "' + $test + '" user32.lib')
    'exit /b %errorlevel%'
) | Set-Content -LiteralPath $cmd -Encoding Ascii

Write-Host "Renamer native source contracts: $Configuration x64, $($definitions.Count + $types.Count) exact current definitions."
Write-Host "Diagnostic build directory: $work"
Push-Location -LiteralPath $work
try {
    & cmd.exe /d /c compile.cmd $Vcvars64
    if ($LASTEXITCODE -ne 0) { throw "Renamer native compilation failed: $LASTEXITCODE" }
    & (Join-Path $work 'renamer_native_contracts.exe')
    if ($LASTEXITCODE -ne 0) { throw "Renamer native contracts failed: $LASTEXITCODE" }
    Write-Host "PASS: Renamer native $Configuration x64."
}
finally { Pop-Location }
