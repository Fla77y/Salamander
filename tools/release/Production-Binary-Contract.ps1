# Read-only additional release gate; PE/version/payload validation stays separate.
function Assert-ProductionBinary {
    param([Parameter(Mandatory)][string]$Path)
    $bytes = [IO.File]::ReadAllBytes([IO.Path]::GetFullPath($Path))
    if ([Text.Encoding]::ASCII.GetString($bytes).Contains('OpenSalamander-IsolatedGUI-Config-v1')) {
        throw "Isolated GUI test executable must not enter a release payload: $Path"
    }
}
