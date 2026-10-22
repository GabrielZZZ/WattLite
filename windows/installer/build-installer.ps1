[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PublishDir,

    [string]$Version = "0.1.0",

    [string]$OutputDir,

    [string]$Iscc
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$resolvedPublish = (Resolve-Path $PublishDir).Path

if (-not (Test-Path (Join-Path $resolvedPublish "WattLite.exe"))) {
    throw "PublishDir does not contain WattLite.exe: $resolvedPublish"
}

if (-not $OutputDir) {
    $OutputDir = Join-Path $root "dist"
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$resolvedOutput = (Resolve-Path $OutputDir).Path

if (-not $Iscc) {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe"),
        "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
        "C:\Program Files\Inno Setup 6\ISCC.exe"
    )
    $Iscc = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if (-not $Iscc -or -not (Test-Path $Iscc)) {
    throw "ISCC.exe not found. Install Inno Setup 6 or pass -Iscc <path>."
}

& $Iscc "/DPublishDir=$resolvedPublish" "/DAppVersion=$Version" "/DOutputDir=$resolvedOutput" (Join-Path $PSScriptRoot "WattLite.iss")
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup failed with exit code $LASTEXITCODE"
}

$setup = Join-Path $resolvedOutput "WattLite-$Version-windows-x64-setup.exe"
if (-not (Test-Path $setup)) {
    throw "Installer was not produced: $setup"
}

$hash = (Get-FileHash $setup -Algorithm SHA256).Hash.ToLowerInvariant()
$hashFile = "$setup.sha256"
[System.IO.File]::WriteAllText(
    $hashFile,
    "$hash  $([System.IO.Path]::GetFileName($setup))`n",
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host "Installer: $setup"
Write-Host "SHA-256:   $hash"
Write-Host "Checksum:  $hashFile"
