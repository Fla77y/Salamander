#requires -Version 7.4
# Opt-in desktop regression. Saves every supported native clipboard format,
# exercises only test text/empty payloads, and restores the original in finally.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows -or [Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    throw 'Run this explicitly authorized desktop test using pwsh -Sta.'
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Path (Join-Path $PSScriptRoot 'Clipboard-Snapshot.cs')
function Get-DibFingerprint {
    $data = [Windows.Forms.Clipboard]::GetDataObject()
    if ($null -eq $data) { return $null }
    $dib = $data.GetData([Windows.Forms.DataFormats]::Dib, $false)
    if ($dib -isnot [IO.MemoryStream]) { return $null }
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($dib.ToArray()))
}
$originalDibFingerprint = Get-DibFingerprint
$original = [SalamanderClipboardSnapshot]::Capture()
try {
    # Arrange
    $expected = 'Snapshot-äöü-東京-😀'
    [Windows.Forms.Clipboard]::SetText($expected)
    $text = [SalamanderClipboardSnapshot]::Capture()
    try {
        [Windows.Forms.Clipboard]::SetText('replacement test payload')
        # Act
        $text.Restore()
        # Assert
        if ([Windows.Forms.Clipboard]::GetText() -cne $expected) {
            throw 'Native snapshot did not restore exact UTF-16 text.'
        }
    }
    finally { $text.Dispose() }
    Write-Host 'PASS: native clipboard snapshot restores exact UTF-16 text.'

    # Arrange
    [Windows.Forms.Clipboard]::Clear()
    $empty = [SalamanderClipboardSnapshot]::Capture()
    try {
        if ($empty.FormatCount -ne 0) { throw 'Empty clipboard fixture has formats.' }
        [Windows.Forms.Clipboard]::SetText('temporary test payload')
        # Act
        $empty.Restore()
        # Assert
        $check = [SalamanderClipboardSnapshot]::Capture()
        try {
            if ($check.FormatCount -ne 0) { throw 'Empty clipboard was not restored.' }
        }
        finally { $check.Dispose() }
    }
    finally { $empty.Dispose() }
    Write-Host 'PASS: native clipboard snapshot preserves the initially empty state.'
}
finally {
    try {
        $original.Restore()
        if ($null -ne $originalDibFingerprint -and
            (Get-DibFingerprint) -cne $originalDibFingerprint) {
            throw 'Original clipboard DIB bytes changed during restoration.'
        }
        Write-Host 'PASS: original native clipboard formats restored.'
    }
    finally { $original.Dispose() }
}
