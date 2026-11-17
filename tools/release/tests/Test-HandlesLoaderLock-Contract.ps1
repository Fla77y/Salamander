#requires -Version 7.4
# Regression: WinDbg showed the GUI thread inside LoadLibraryA during
# start-on-load plug-in initialization, with an icon thread blocked in
# C__Handles::SetInfo. Never hold the debug handle-monitor lock across
# Windows loader calls; preserve SetInfo metadata and GetLastError.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repository = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).ProviderPath
$source = [IO.File]::ReadAllText(
    (Join-Path $repository 'src\common\handles.cpp'))

function Assert-LoadLibraryDoesNotHoldMonitorLock {
    param(
        [Parameter(Mandatory)][string]$FunctionName,
        [Parameter(Mandatory)][string]$NativeCall
    )

    # Arrange: isolate only the requested C__Handles wrapper, not the
    # already-safe FreeLibrary implementation.
    $start = $source.IndexOf(
        "C__Handles::${FunctionName}(", [StringComparison]::Ordinal)
    if ($start -lt 0) { throw "Missing C__Handles::$FunctionName." }
    $open = $source.IndexOf('{', $start)
    $next = [regex]::Match($source.Substring($open + 1), '(?m)^\}')
    if (-not $next.Success) { throw "Unterminated C__Handles::$FunctionName." }
    $body = $source.Substring($open + 1, $next.Index)

    # Act: identify the real native loader call and all synchronization
    # operations in the same function body.
    $savedOutput = $body.IndexOf('C__HandlesOutputType tmpOutputType = OutputType;', [StringComparison]::Ordinal)
    $savedMetadata = $body.IndexOf('C__HandlesData tmpTemporaryHandle = TemporaryHandle;', [StringComparison]::Ordinal)
    $release = $body.IndexOf('::LeaveCriticalSection(&CriticalSection);', [StringComparison]::Ordinal)
    $native = $body.IndexOf($NativeCall, [StringComparison]::Ordinal)
    $lastError = $body.IndexOf('DWORD loadError = ::GetLastError();', [StringComparison]::Ordinal)
    $reenter = $body.IndexOf('::EnterCriticalSection(&CriticalSection);', [StringComparison]::Ordinal)
    $restoreOutput = $body.IndexOf('OutputType = tmpOutputType;', [StringComparison]::Ordinal)
    $restoreMetadata = $body.IndexOf('TemporaryHandle = tmpTemporaryHandle;', [StringComparison]::Ordinal)
    $restoreError = $body.IndexOf('::SetLastError(loadError);', [StringComparison]::Ordinal)
    $track = $body.IndexOf('CheckCreate(ret != NULL', [StringComparison]::Ordinal)

    # Assert: no lock may span the potentially re-entrant LoadLibrary call;
    # concurrent handle tracking must retain the original caller's metadata,
    # and the original Win32 status must survive re-acquiring the lock.
    if ($savedOutput -lt 0 -or $savedMetadata -lt 0 -or $release -lt 0 -or
        $native -lt 0 -or $lastError -lt 0 -or $reenter -lt 0 -or
        $restoreOutput -lt 0 -or $restoreMetadata -lt 0 -or
        $restoreError -lt 0 -or $track -lt 0 -or
        $savedOutput -ge $release -or $savedMetadata -ge $release -or
        $release -ge $native -or $native -ge $lastError -or
        $lastError -ge $reenter -or $reenter -ge $restoreOutput -or
        $reenter -ge $restoreMetadata -or
        $restoreOutput -ge $restoreError -or
        $restoreMetadata -ge $restoreError -or $restoreError -ge $track) {
        throw "C__Handles::$FunctionName must release the monitor before $NativeCall and preserve metadata and Win32 status."
    }
    Write-Host "PASS: C__Handles::$FunctionName does not hold the handle monitor across Windows DLL loading."
}

Assert-LoadLibraryDoesNotHoldMonitorLock -FunctionName 'LoadLibrary' -NativeCall '::LoadLibrary(lpLibFileName)'
Assert-LoadLibraryDoesNotHoldMonitorLock -FunctionName 'LoadLibraryEx' -NativeCall '::LoadLibraryEx(lpLibFileName, hFile, dwFlags)'
