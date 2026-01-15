<#
.SYNOPSIS
    Main orchestration script for QWiser University post-deployment setup.

.DESCRIPTION
    This script orchestrates all post-deployment configuration steps:
    1. Seed Key Vault with auto-generated and placeholder secrets
    2. Seed App Configuration with infrastructure values and defaults
    3. Approve Front Door PE connection to Private Link Service

.PARAMETER ResourceGroup
    Resource group name containing the deployed resources.

.PARAMETER KeyVaultName
    Name of the Key Vault to seed.

.PARAMETER AppConfigName
    Name of the App Configuration store to seed.

.PARAMETER PlsName
    Name of the Private Link Service.

.PARAMETER MysqlHost
    MySQL server FQDN (from Bicep output).

.PARAMETER MysqlPort
    MySQL server port (default: 3306).

.PARAMETER RedisHost
    Redis cache hostname (from Bicep output).

.PARAMETER RedisPort
    Redis cache port (default: 10000).

.PARAMETER StorageQueueUrl
    Storage queue URL (from Bicep output).

.PARAMETER Label
    Configuration label (e.g., "production", "staging").

.PARAMETER Force
    Overwrite existing values.

.PARAMETER SkipKeyVault
    Skip Key Vault seeding step.

.PARAMETER SkipAppConfig
    Skip App Configuration seeding step.

.PARAMETER SkipPE
    Skip PE connection approval step.

.EXAMPLE
    ./post-deploy.ps1 `
        -ResourceGroup "qwiser-prod-rg" `
        -KeyVaultName "qwiser-prod-kv" `
        -AppConfigName "qwiser-prod-appconfig" `
        -PlsName "qwiser-prod-pls" `
        -MysqlHost "qwiser-prod-mysql.mysql.database.azure.com" `
        -RedisHost "qwiser-prod-redis.redis.cache.windows.net" `
        -StorageQueueUrl "https://qwiserprodstorage.queue.core.windows.net/" `
        -Label "production"

.NOTES
    Prerequisites:
    - Azure CLI installed and logged in
    - Appropriate RBAC roles (Key Vault Secrets Officer, App Config Data Owner)
    - Network access (Cloud Shell with VNet injection or VPN)
    - Bicep deployment completed (outputs available)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $true)]
    [string]$KeyVaultName,

    [Parameter(Mandatory = $true)]
    [string]$AppConfigName,

    [Parameter(Mandatory = $true)]
    [string]$PlsName,

    [Parameter(Mandatory = $true)]
    [string]$MysqlHost,

    [Parameter(Mandatory = $false)]
    [int]$MysqlPort = 3306,

    [Parameter(Mandatory = $true)]
    [string]$RedisHost,

    [Parameter(Mandatory = $false)]
    [int]$RedisPort = 10000,

    [Parameter(Mandatory = $true)]
    [string]$StorageQueueUrl,

    [Parameter(Mandatory = $true)]
    [string]$Label,

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$SkipKeyVault,

    [Parameter(Mandatory = $false)]
    [switch]$SkipAppConfig,

    [Parameter(Mandatory = $false)]
    [switch]$SkipPE
)

$ErrorActionPreference = "Stop"

# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Construct Key Vault URI from name
$KeyVaultUri = "https://${KeyVaultName}.vault.azure.net/"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "        QWiser University Post-Deployment Setup             " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Configuration:"
Write-Host "  Resource Group:     $ResourceGroup"
Write-Host "  Key Vault:          $KeyVaultName"
Write-Host "  App Configuration:  $AppConfigName"
Write-Host "  Private Link Svc:   $PlsName"
Write-Host "  MySQL Host:         $MysqlHost"
Write-Host "  Redis Host:         $RedisHost"
Write-Host "  Storage Queue URL:  $StorageQueueUrl"
Write-Host "  Label:              $Label"
Write-Host "  Force overwrite:    $Force"
Write-Host ""

# Track overall success
$overallSuccess = $true

# ============================================================================
# Step 1: Seed Key Vault
# ============================================================================

if ($SkipKeyVault) {
    Write-Host "[SKIP] Key Vault seeding (--SkipKeyVault)" -ForegroundColor Yellow
} else {
    Write-Host "[STEP 1/3] Seeding Key Vault..." -ForegroundColor Cyan
    Write-Host ""

    try {
        $kvParams = @{
            KeyVaultName = $KeyVaultName
        }
        if ($Force) {
            $kvParams.Force = $true
        }

        & "$ScriptDir\seed-keyvault.ps1" @kvParams

        Write-Host "[OK] Key Vault seeding completed" -ForegroundColor Green
    } catch {
        Write-Host "[FAILED] Key Vault seeding failed: $_" -ForegroundColor Red
        $overallSuccess = $false
    }
}

Write-Host ""

# ============================================================================
# Step 2: Seed App Configuration
# ============================================================================

if ($SkipAppConfig) {
    Write-Host "[SKIP] App Configuration seeding (--SkipAppConfig)" -ForegroundColor Yellow
} else {
    Write-Host "[STEP 2/3] Seeding App Configuration..." -ForegroundColor Cyan
    Write-Host ""

    try {
        $acParams = @{
            AppConfigName = $AppConfigName
            KeyVaultUri = $KeyVaultUri
            Label = $Label
            MysqlHost = $MysqlHost
            MysqlPort = $MysqlPort
            RedisHost = $RedisHost
            RedisPort = $RedisPort
            StorageQueueUrl = $StorageQueueUrl
        }
        if ($Force) {
            $acParams.Force = $true
        }

        & "$ScriptDir\seed-appconfig.ps1" @acParams

        Write-Host "[OK] App Configuration seeding completed" -ForegroundColor Green
    } catch {
        Write-Host "[FAILED] App Configuration seeding failed: $_" -ForegroundColor Red
        $overallSuccess = $false
    }
}

Write-Host ""

# ============================================================================
# Step 3: Approve PE Connection
# ============================================================================

if ($SkipPE) {
    Write-Host "[SKIP] PE connection approval (--SkipPE)" -ForegroundColor Yellow
} else {
    Write-Host "[STEP 3/3] Approving Front Door PE Connection..." -ForegroundColor Cyan
    Write-Host ""

    try {
        & "$ScriptDir\approve-pe-connection.ps1" `
            -ResourceGroup $ResourceGroup `
            -PlsName $PlsName

        Write-Host "[OK] PE connection approval completed" -ForegroundColor Green
    } catch {
        Write-Host "[FAILED] PE connection approval failed: $_" -ForegroundColor Red
        $overallSuccess = $false
    }
}

Write-Host ""

# ============================================================================
# Summary
# ============================================================================

Write-Host "============================================================" -ForegroundColor Cyan
if ($overallSuccess) {
    Write-Host "        Post-Deployment Setup Complete!                    " -ForegroundColor Green
} else {
    Write-Host "        Post-Deployment Setup Completed with Errors         " -ForegroundColor Red
}
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. Deploy Azure AI Foundry models" -ForegroundColor Gray
Write-Host "  2. Update ai:*:endpoint values in App Configuration" -ForegroundColor Gray
Write-Host "  3. Update AI-FOUNDRY-API-KEY secret in Key Vault" -ForegroundColor Gray
Write-Host "  4. Configure LTI settings if LMS integration needed" -ForegroundColor Gray
Write-Host "  5. Verify Front Door health probes are passing" -ForegroundColor Gray
Write-Host "  6. Deploy applications to AKS cluster" -ForegroundColor Gray
Write-Host ""

if (-not $overallSuccess) {
    exit 1
}
