# QWiser University - Container Image Import Script
# Imports images from QWiser ACR to customer's ACR
#
# Prerequisites:
#   - Azure CLI installed and logged in
#   - QWiser ACR credentials (provided by QWiser)
#   - Target ACR already deployed (via Bicep)
#
# Usage:
#   .\import-images.ps1 -SourceUser <username> -SourcePassword <password> -TargetAcr <acr-name>
#
# Or with environment variables:
#   $env:QWISER_ACR_USERNAME = "..."
#   $env:QWISER_ACR_PASSWORD = "..."
#   .\import-images.ps1 -TargetAcr <acr-name>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SourceUser = $env:QWISER_ACR_USERNAME,

    [Parameter(Mandatory = $false)]
    [string]$SourcePassword = $env:QWISER_ACR_PASSWORD,

    [Parameter(Mandatory = $true)]
    [string]$TargetAcr,

    [Parameter(Mandatory = $false)]
    [string]$VersionsFile = "",

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# Configuration
$SourceRegistry = "qwiser.azurecr.io"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if ([string]::IsNullOrEmpty($VersionsFile)) {
    $VersionsFile = Join-Path (Split-Path -Parent $ScriptDir) "VERSIONS.txt"
}

# Validate required parameters
if ([string]::IsNullOrEmpty($SourceUser)) {
    Write-Error "Missing QWiser ACR username. Provide -SourceUser or set `$env:QWISER_ACR_USERNAME"
    exit 1
}

if ([string]::IsNullOrEmpty($SourcePassword)) {
    Write-Error "Missing QWiser ACR password. Provide -SourcePassword or set `$env:QWISER_ACR_PASSWORD"
    exit 1
}

if (-not (Test-Path $VersionsFile)) {
    Write-Error "VERSIONS.txt not found at: $VersionsFile"
    exit 1
}

# Parse VERSIONS.txt (skip comments and empty lines)
$Images = Get-Content $VersionsFile | Where-Object {
    $_ -notmatch "^#" -and $_.Trim() -ne ""
}

if ($Images.Count -eq 0) {
    Write-Error "No images found in VERSIONS.txt"
    exit 1
}

# Display plan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "QWiser Image Import" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "Source registry:  $SourceRegistry"
Write-Host "Target ACR:       $TargetAcr"
Write-Host "Images to import: $($Images.Count)"
Write-Host ""
Write-Host "Images:"
foreach ($img in $Images) {
    Write-Host "  - $img"
}
Write-Host ""

if ($DryRun) {
    Write-Host "DRY RUN - No images will be imported" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Commands that would be executed:"
    foreach ($img in $Images) {
        Write-Host "  az acr import --name $TargetAcr --source $SourceRegistry/$img --image $img --username ****** --password ******"
    }
    exit 0
}

# Verify Azure CLI is logged in
try {
    $null = az account show 2>&1
}
catch {
    Write-Error "Azure CLI not logged in. Run 'az login' first."
    exit 1
}

# Verify target ACR exists
Write-Host "Verifying target ACR exists..."
try {
    $null = az acr show --name $TargetAcr 2>&1
}
catch {
    Write-Error "Target ACR '$TargetAcr' not found. Ensure the Bicep deployment completed successfully."
    exit 1
}
Write-Host "Target ACR verified: $TargetAcr" -ForegroundColor Green
Write-Host ""

# Import images
$Failed = @()
$Succeeded = @()

foreach ($img in $Images) {
    Write-Host "Importing $img..."

    try {
        az acr import `
            --name $TargetAcr `
            --source "$SourceRegistry/$img" `
            --image $img `
            --username $SourceUser `
            --password $SourcePassword `
            --force 2>&1 | Out-Null

        Write-Host "  Imported: $img" -ForegroundColor Green
        $Succeeded += $img
    }
    catch {
        Write-Host "  Failed: $img" -ForegroundColor Red
        Write-Host "  Error: $_" -ForegroundColor Red
        $Failed += $img
    }
    Write-Host ""
}

# Summary
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "Import Summary" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "Succeeded: $($Succeeded.Count)" -ForegroundColor Green

if ($Failed.Count -gt 0) {
    Write-Host "Failed: $($Failed.Count)" -ForegroundColor Red
    foreach ($img in $Failed) {
        Write-Host "  - $img" -ForegroundColor Red
    }
    exit 1
}

Write-Host ""
Write-Host "All images imported successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Verify images: az acr repository list --name $TargetAcr -o table"
Write-Host "  2. Deploy K8s manifests: see docs/DEPLOYMENT_GUIDE.md"
