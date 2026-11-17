#requires -Version 7.4
# Source regression for the confirmed fixed-buffer plugin loader defect.
# Runtime module/path regressions complement this guard; it is not GUI proof.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).ProviderPath
$source = Get-Content -LiteralPath (Join-Path $root 'src\plugins1.cpp') -Raw
# Arrange
$begin = $source.IndexOf('BOOL CPluginData::InitDLL(')
$end = $source.IndexOf('void CPluginData::GetDisplayName', $begin)
if ($begin -lt 0 -or $end -le $begin) { throw 'Cannot locate plugin loader.' }
$loader = $source.Substring($begin, $end - $begin)
# Act / Assert
if ($loader -match 'GetModuleFileName\(' -or $loader -match 'char buf\[MAX_PATH\]' -or
    $loader -match '\b(strcpy|strcat|sprintf)\(') {
    throw 'Plugin loader still uses unchecked fixed-capacity module paths or diagnostic formatting.'
}
if ($loader -notmatch 'TryResolvePluginModulePath' -or $loader -notmatch 'LoadLibraryW') {
    throw 'Plugin loader must consume a checked, owned UTF-16 module path.'
}
$languageBegin = $source.IndexOf('CSalamanderPluginEntry::LoadLanguageModule(')
$languageEnd = $source.IndexOf('void CSalamanderPluginEntry::SetPluginHomePageURL', $languageBegin)
$language = $source.Substring($languageBegin, $languageEnd - $languageBegin)
if ($language -match 'GetModuleFileName\(' -or $language -match 'char path\[MAX_PATH\]' -or
    $language -notmatch 'TryResolveLanguageModulePath' -or $language -notmatch 'LoadLibraryW') {
    throw 'Plugin language loading still reconstructs fixed ANSI module paths.'
}
$source2 = Get-Content -LiteralPath (Join-Path $root 'src\plugins2.cpp') -Raw
$removeBegin = $source2.IndexOf('void CPlugins::RemoveNoLongerExistingPlugins(')
$removeEnd = $source2.IndexOf('void CPlugins::AutoInstallStdPluginsDir(', $removeBegin)
$remove = $source2.Substring($removeBegin, $removeEnd - $removeBegin)
if ($remove -match 'GetModuleFileName\(' -or $remove -match 'SalGetFileAttributes\(' -or
    $remove -notmatch 'PluginModulePresence::Missing') {
    throw 'Automatic plugin removal must require a confirmed missing original W path.'
}
Write-Host 'PASS: plugin loader uses owned W paths and bounded diagnostics.'
