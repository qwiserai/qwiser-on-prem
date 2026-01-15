<#
.SYNOPSIS
    Seeds remaining secrets in Azure Key Vault for QWiser University deployment.

.DESCRIPTION
    This script creates secrets that are NOT handled by Bicep deployment:
    - Auto-generated: JWT-SECRET, INTERNAL-SECRET-KEY, QDRANT-API-KEY
    - Placeholders: AI-FOUNDRY-API-KEY, LTI-PRIVATE-KEY

    Secrets handled by Bicep (DO NOT seed here):
    - DB-USER, DB-PASSWORD (from mysql.bicep)
    - STORAGE-ACCOUNT-KEY, STORAGE-CONNECTION-STRING (from storage-account.bicep)
    - APPLICATIONINSIGHTS-CONNECTION-STRING (from monitoring.bicep)

.PARAMETER KeyVaultName
    Name of the Key Vault to seed.

.PARAMETER Force
    If specified, overwrites existing secrets. Otherwise skips if secret exists.

.EXAMPLE
    ./seed-keyvault.ps1 -KeyVaultName "qwiser-prod-kv"

.EXAMPLE
    ./seed-keyvault.ps1 -KeyVaultName "qwiser-prod-kv" -Force

.NOTES
    Prerequisites:
    - Azure CLI installed and logged in
    - Key Vault Secrets Officer role on the Key Vault
    - Network access to Key Vault (Cloud Shell with VNet injection or VPN)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$KeyVaultName,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "QWiser Key Vault Secret Seeding" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Key Vault: $KeyVaultName"
Write-Host "Force overwrite: $Force"
Write-Host ""

# Function to check if secret exists
function Test-SecretExists {
    param([string]$VaultName, [string]$SecretName)

    $existing = az keyvault secret show --vault-name $VaultName --name $SecretName --query "name" -o tsv 2>$null
    return -not [string]::IsNullOrEmpty($existing)
}

# Function to generate cryptographically secure random string
function New-SecureRandomString {
    param([int]$Length = 64)

    $bytes = New-Object byte[] ($Length / 2)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    return [BitConverter]::ToString($bytes) -replace '-', '' | ForEach-Object { $_.ToLower() }
}

# Function to set a secret
function Set-KeyVaultSecret {
    param(
        [string]$VaultName,
        [string]$SecretName,
        [string]$SecretValue,
        [string]$Description,
        [bool]$ForceOverwrite
    )

    $exists = Test-SecretExists -VaultName $VaultName -SecretName $SecretName

    if ($exists -and -not $ForceOverwrite) {
        Write-Host "  [SKIP] $SecretName - already exists (use -Force to overwrite)" -ForegroundColor Yellow
        return $false
    }

    $action = if ($exists) { "Updating" } else { "Creating" }
    Write-Host "  [$action] $SecretName - $Description" -ForegroundColor Gray

    az keyvault secret set `
        --vault-name $VaultName `
        --name $SecretName `
        --value $SecretValue `
        --output none

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to set secret: $SecretName"
    }

    Write-Host "  [OK] $SecretName" -ForegroundColor Green
    return $true
}

# ============================================================================
# Auto-Generated Secrets
# ============================================================================

Write-Host ""
Write-Host "Auto-Generated Secrets:" -ForegroundColor White
Write-Host "------------------------"

# JWT-SECRET - Used for signing JWT tokens
$jwtSecret = New-SecureRandomString -Length 64
Set-KeyVaultSecret -VaultName $KeyVaultName -SecretName "JWT-SECRET" `
    -SecretValue $jwtSecret -Description "JWT signing secret (auto-generated)" `
    -ForceOverwrite $Force.IsPresent

# INTERNAL-SECRET-KEY - Used for internal service authentication
$internalSecret = New-SecureRandomString -Length 64
Set-KeyVaultSecret -VaultName $KeyVaultName -SecretName "INTERNAL-SECRET-KEY" `
    -SecretValue $internalSecret -Description "Internal service auth key (auto-generated)" `
    -ForceOverwrite $Force.IsPresent

# QDRANT-API-KEY - Used for Qdrant vector database authentication
$qdrantApiKey = New-SecureRandomString -Length 64
Set-KeyVaultSecret -VaultName $KeyVaultName -SecretName "QDRANT-API-KEY" `
    -SecretValue $qdrantApiKey -Description "Qdrant API key (auto-generated)" `
    -ForceOverwrite $Force.IsPresent

# ============================================================================
# Placeholder Secrets (IT must update after deployment)
# ============================================================================

Write-Host ""
Write-Host "Placeholder Secrets (IT must update these):" -ForegroundColor White
Write-Host "--------------------------------------------"

# AI-FOUNDRY-API-KEY - IT configures after Azure AI deployment
Set-KeyVaultSecret -VaultName $KeyVaultName -SecretName "AI-FOUNDRY-API-KEY" `
    -SecretValue "PLACEHOLDER-UPDATE-AFTER-AI-DEPLOYMENT" `
    -Description "Azure AI Foundry API key (IT must update)" `
    -ForceOverwrite $Force.IsPresent

# LTI-PRIVATE-KEY - IT configures for LMS integration
Set-KeyVaultSecret -VaultName $KeyVaultName -SecretName "LTI-PRIVATE-KEY" `
    -SecretValue "PLACEHOLDER-UPDATE-FOR-LTI-INTEGRATION" `
    -Description "LTI 1.3 private key (IT must update)" `
    -ForceOverwrite $Force.IsPresent

# ============================================================================
# Summary
# ============================================================================

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "Key Vault seeding complete!" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. Update AI-FOUNDRY-API-KEY after deploying Azure AI Foundry" -ForegroundColor Gray
Write-Host "  2. Update LTI-PRIVATE-KEY when configuring LMS integration" -ForegroundColor Gray
Write-Host ""
