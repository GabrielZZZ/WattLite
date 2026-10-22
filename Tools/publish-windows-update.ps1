[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Setup,

    [Parameter(Mandatory = $true)]
    [string]$Version,

    [Parameter(Mandatory = $true)]
    [string]$KeyFile,

    [string]$Tag = "v$Version-windows",
    [string]$NotesZh = "",
    [string]$NotesEn = "",
    [string]$OutDir,
    [string]$AssetUrl,
    [string]$MirrorUrl,
    [string]$MinOs = "10.0.17763",
    [switch]$SkipUrlCheck
)

$ErrorActionPreference = "Stop"

$root = Split-Path $PSScriptRoot -Parent
$setupPath = (Resolve-Path $Setup).Path
$keyPath = (Resolve-Path $KeyFile).Path

if (-not $OutDir) {
    $OutDir = Join-Path $root "docs\updates"
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$resolvedOut = (Resolve-Path $OutDir).Path

$fileName = Split-Path $setupPath -Leaf
$url = if ($AssetUrl) { $AssetUrl } else {
    "https://github.com/GabrielZZZ/WattLite/releases/download/$Tag/$fileName"
}
$mirror = if ($MirrorUrl) { $MirrorUrl } elseif ($AssetUrl) { "" } else { "https://ghfast.top/$url" }
$hash = (Get-FileHash $setupPath -Algorithm SHA256).Hash.ToLowerInvariant()

if (-not $SkipUrlCheck) {
    try {
        $head = Invoke-WebRequest -Uri $url -Method Head -MaximumRedirection 5 -TimeoutSec 30 -UseBasicParsing
        if ($head.StatusCode -ne 200) {
            throw "HTTP $($head.StatusCode)"
        }
    }
    catch {
        throw "Release asset is not reachable yet: $url`n$($_.Exception.Message)`nUpload the asset first, or pass -SkipUrlCheck for a local test manifest."
    }
}

$manifest = [ordered]@{
    version   = $Version
    url       = $url
    mirror    = $mirror
    sha256    = $hash
    min_os    = $MinOs
    published = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    notes_zh  = $NotesZh
    notes_en  = $NotesEn
}
# Sign the exact bytes that will be committed. Git EOL conversion would invalidate
# a signature over CRLF, so normalize to LF and mark the feed as binary in .gitattributes.
$json = ($manifest | ConvertTo-Json -Depth 4) -replace "`r`n", "`n"
$manifestPath = Join-Path $resolvedOut "windows.json"
$signaturePath = Join-Path $resolvedOut "windows.json.sig"
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($manifestPath, $json, $utf8)

& dotnet run --project (Join-Path $root "Tools\UpdateSigner\UpdateSigner.csproj") -- `
    sign --key $keyPath --in $manifestPath --out $signaturePath
if ($LASTEXITCODE -ne 0) {
    throw "Signing failed with exit code $LASTEXITCODE"
}

Write-Host "Manifest:  $manifestPath"
Write-Host "Signature: $signaturePath"
Write-Host "SHA-256:   $hash"
Write-Host "Commit and push docs/updates only after the release asset is live."
