<#
.SYNOPSIS
    Seeds Azure App Configuration with required key structure for QWiser University.

.DESCRIPTION
    This script populates App Configuration with:
    - Infrastructure values (from Bicep outputs)
    - Key Vault references for secrets
    - Default configuration values for all application parameters
    - Placeholder values for AI endpoints (IT configures after AI deployment)
    - Sentinel key for configuration refresh

.PARAMETER AppConfigName
    Name of the Azure App Configuration store.

.PARAMETER KeyVaultUri
    URI of the Key Vault (e.g., https://myvault.vault.azure.net/).

.PARAMETER Label
    Label for all configuration keys (e.g., "production", "staging").

.PARAMETER MysqlHost
    MySQL server FQDN (from Bicep output).

.PARAMETER MysqlPort
    MySQL server port (default: 3306).

.PARAMETER RedisHost
    Redis cache hostname (from Bicep output).

.PARAMETER RedisPort
    Redis cache port (default: 10000 for Azure Managed Redis).

.PARAMETER StorageQueueUrl
    Storage queue URL (from Bicep output).

.PARAMETER Force
    If specified, overwrites existing keys. Otherwise skips if key exists.

.EXAMPLE
    ./seed-appconfig.ps1 `
        -AppConfigName "qwiser-prod-appconfig" `
        -KeyVaultUri "https://qwiser-prod-kv.vault.azure.net/" `
        -Label "production" `
        -MysqlHost "qwiser-prod-mysql.mysql.database.azure.com" `
        -RedisHost "qwiser-prod-redis.redis.cache.windows.net" `
        -StorageQueueUrl "https://qwiserprodstorage.queue.core.windows.net/"

.NOTES
    Prerequisites:
    - Azure CLI installed and logged in
    - App Configuration Data Owner role on the App Configuration store
    - Network access to App Configuration (Cloud Shell with VNet injection or VPN)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$AppConfigName,

    [Parameter(Mandatory = $true)]
    [string]$KeyVaultUri,

    [Parameter(Mandatory = $true)]
    [string]$Label,

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

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# Ensure KeyVaultUri ends with /
if (-not $KeyVaultUri.EndsWith("/")) {
    $KeyVaultUri = "$KeyVaultUri/"
}

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "QWiser App Configuration Seeding" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "App Configuration: $AppConfigName"
Write-Host "Key Vault URI: $KeyVaultUri"
Write-Host "Label: $Label"
Write-Host "Force overwrite: $Force"
Write-Host ""

# Function to set a regular key-value
function Set-AppConfigKey {
    param(
        [string]$ConfigName,
        [string]$Key,
        [string]$Value,
        [string]$ConfigLabel,
        [bool]$ForceOverwrite
    )

    Write-Host "  [Setting] $Key = $Value" -ForegroundColor Gray

    az appconfig kv set `
        -n $ConfigName `
        --key $Key `
        --value $Value `
        --label $ConfigLabel `
        --yes `
        --only-show-errors

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to set key: $Key"
    }

    Write-Host "  [OK] $Key" -ForegroundColor Green
}

# Function to set a Key Vault reference
function Set-AppConfigKeyVaultRef {
    param(
        [string]$ConfigName,
        [string]$Key,
        [string]$SecretName,
        [string]$VaultUri,
        [string]$ConfigLabel,
        [bool]$ForceOverwrite
    )

    $secretUri = "${VaultUri}secrets/$SecretName"

    Write-Host "  [Setting KV Ref] $Key -> $secretUri" -ForegroundColor Gray

    az appconfig kv set-keyvault `
        -n $ConfigName `
        --key $Key `
        --secret-identifier $secretUri `
        --label $ConfigLabel `
        --yes `
        --only-show-errors

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to set Key Vault reference: $Key"
    }

    Write-Host "  [OK] $Key" -ForegroundColor Green
}

# ============================================================================
# Infrastructure Configuration (from Bicep outputs)
# ============================================================================

Write-Host ""
Write-Host "Infrastructure Configuration:" -ForegroundColor White
Write-Host "------------------------------"

# Database
Set-AppConfigKey -ConfigName $AppConfigName -Key "db:host" -Value $MysqlHost -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "db:port" -Value $MysqlPort.ToString() -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "db:name" -Value "qwiser" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent

# Redis (note: hyphen in max-connections, not underscore)
Set-AppConfigKey -ConfigName $AppConfigName -Key "redis:host" -Value $RedisHost -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "redis:port" -Value $RedisPort.ToString() -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "redis:max-connections" -Value "100" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "redis:socket_timeout" -Value "300" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "redis:socket_connect_timeout" -Value "20" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "redis:health_check_interval" -Value "20" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent

# Azure Storage (key and queue_url expected by config code)
Set-AppConfigKey -ConfigName $AppConfigName -Key "azure:storage:queue_url" -Value $StorageQueueUrl -ConfigLabel $Label -ForceOverwrite $Force.IsPresent

# Qdrant (deployed via Helm - internal K8s service URL)
Set-AppConfigKey -ConfigName $AppConfigName -Key "qdrant:cluster_url" -Value "http://qdrant.qdrant.svc.cluster.local:6333" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent

# ============================================================================
# Key Vault References (Secrets)
# ============================================================================

Write-Host ""
Write-Host "Key Vault References:" -ForegroundColor White
Write-Host "---------------------"

# Database credentials
Set-AppConfigKeyVaultRef -ConfigName $AppConfigName -Key "db:user" -SecretName "DB-USER" -VaultUri $KeyVaultUri -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKeyVaultRef -ConfigName $AppConfigName -Key "db:password" -SecretName "DB-PASSWORD" -VaultUri $KeyVaultUri -ConfigLabel $Label -ForceOverwrite $Force.IsPresent

# Application secrets
Set-AppConfigKeyVaultRef -ConfigName $AppConfigName -Key "jwt_secret" -SecretName "JWT-SECRET" -VaultUri $KeyVaultUri -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKeyVaultRef -ConfigName $AppConfigName -Key "internal_secret_key" -SecretName "INTERNAL-SECRET-KEY" -VaultUri $KeyVaultUri -ConfigLabel $Label -ForceOverwrite $Force.IsPresent

# Qdrant
Set-AppConfigKeyVaultRef -ConfigName $AppConfigName -Key "qdrant:api_key" -SecretName "QDRANT-API-KEY" -VaultUri $KeyVaultUri -ConfigLabel $Label -ForceOverwrite $Force.IsPresent

# Application Insights
Set-AppConfigKeyVaultRef -ConfigName $AppConfigName -Key "azure:applicationinsights_connection_string" -SecretName "APPLICATIONINSIGHTS-CONNECTION-STRING" -VaultUri $KeyVaultUri -ConfigLabel $Label -ForceOverwrite $Force.IsPresent

# Storage key and connection string
Set-AppConfigKeyVaultRef -ConfigName $AppConfigName -Key "azure:storage:key" -SecretName "STORAGE-ACCOUNT-KEY" -VaultUri $KeyVaultUri -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKeyVaultRef -ConfigName $AppConfigName -Key "azure:storage:connection_string" -SecretName "STORAGE-CONNECTION-STRING" -VaultUri $KeyVaultUri -ConfigLabel $Label -ForceOverwrite $Force.IsPresent

# LTI (placeholder - IT configures)
Set-AppConfigKeyVaultRef -ConfigName $AppConfigName -Key "lti:private_key" -SecretName "LTI-PRIVATE-KEY" -VaultUri $KeyVaultUri -ConfigLabel $Label -ForceOverwrite $Force.IsPresent

# ============================================================================
# Default Values
# ============================================================================

Write-Host ""
Write-Host "Default Values:" -ForegroundColor White
Write-Host "---------------"

# Environment
Set-AppConfigKey -ConfigName $AppConfigName -Key "environment" -Value "production" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent

# Logging
Set-AppConfigKey -ConfigName $AppConfigName -Key "logging:level" -Value "INFO" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent

# Worker settings
Set-AppConfigKey -ConfigName $AppConfigName -Key "worker:polling_time" -Value "5" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent

# ============================================================================
# Maintenance Configuration
# ============================================================================

Write-Host ""
Write-Host "Maintenance Configuration:" -ForegroundColor White
Write-Host "--------------------------"

Set-AppConfigKey -ConfigName $AppConfigName -Key "maintenance:scheduled" -Value "false" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "maintenance:message" -Value "We'll be back soon!" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "maintenance:bypass_whitelist" -Value "" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "maintenance:scheduled_time" -Value "2024-01-15T10:00:00Z" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent

# ============================================================================
# Text Configuration (used by get_text_config)
# ============================================================================

Write-Host ""
Write-Host "Text Configuration:" -ForegroundColor White
Write-Host "-------------------"

Set-AppConfigKey -ConfigName $AppConfigName -Key "text:min_paragraph_chars" -Value "200" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "text:min_chunk_words" -Value "10" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "text:robust_loader_headless" -Value "true" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "text:robust_loader_timeout" -Value "30" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "text:robust_loader_max_retries" -Value "3" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "text:robust_loader_user_agent" -Value "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent

# ============================================================================
# Embedding Configuration (used by get_embedding_config)
# ============================================================================

Write-Host ""
Write-Host "Embedding Configuration:" -ForegroundColor White
Write-Host "------------------------"

Set-AppConfigKey -ConfigName $AppConfigName -Key "embedding:window_size" -Value "5" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "embedding:overlap" -Value "2" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "embedding:colbert_batch_size" -Value "8" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "embedding:qdrant_batch_size" -Value "20" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent

# ============================================================================
# Chat Configuration (used by get_chat_config)
# ============================================================================

Write-Host ""
Write-Host "Chat Configuration:" -ForegroundColor White
Write-Host "-------------------"

# Chat message settings
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:chat:message:model" -Value "gpt-5.2" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:chat:message:temperature" -Value "1" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:chat:message:context_limit" -Value "3000" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:chat:message:response_limit" -Value "5000" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:chat:message:reasoning_effort" -Value "low" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent

# Chat summary settings
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:chat:summary:model" -Value "gpt-5.2" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:chat:summary:temperature" -Value "1" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:chat:summary:context_limit" -Value "5000" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:chat:summary:response_limit" -Value "5000" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:chat:summary:reasoning_effort" -Value "low" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent

# Chat name generation settings
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:chat:name:model" -Value "gpt-4.1-mini" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:chat:name:temperature" -Value "0.7" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:chat:name:max_tokens" -Value "100" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent

# Chat standalone question settings
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:chat:standalone_question:model" -Value "gpt-4.1-mini" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:chat:standalone_question:temperature" -Value "0.7" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent

# Chat general settings
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:chat:user_message_max_tokens" -Value "2000" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:chat:keep_recent_turns_min" -Value "2" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:chat:summary_update_trigger_turns" -Value "6" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:chat:semantic_search_min_tokens" -Value "1000" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:chat:system_prompt_tokens" -Value "500" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent

# ============================================================================
# Questions Configuration
# ============================================================================

Write-Host ""
Write-Host "Questions Configuration:" -ForegroundColor White
Write-Host "------------------------"

Set-AppConfigKey -ConfigName $AppConfigName -Key "params:questions:model" -Value "gpt-5.2" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:questions:temperature" -Value "0.5" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:questions:max_tokens" -Value "3000" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:questions:reasoning_effort" -Value "low" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent

# ============================================================================
# Answers Configuration
# ============================================================================

Write-Host ""
Write-Host "Answers Configuration:" -ForegroundColor White
Write-Host "----------------------"

Set-AppConfigKey -ConfigName $AppConfigName -Key "params:answers:model" -Value "gpt-5.2" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:answers:temperature" -Value "0.5" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:answers:max_tokens" -Value "3000" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:answers:reasoning_effort" -Value "low" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent

# ============================================================================
# Study Notes Configuration
# ============================================================================

Write-Host ""
Write-Host "Study Notes Configuration:" -ForegroundColor White
Write-Host "--------------------------"

Set-AppConfigKey -ConfigName $AppConfigName -Key "params:study_notes:model" -Value "gpt-4.1-mini" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:study_notes:temperature" -Value "0.5" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:study_notes:max_tokens" -Value "10000" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent

# ============================================================================
# Tree Configuration
# ============================================================================

Write-Host ""
Write-Host "Tree Configuration:" -ForegroundColor White
Write-Host "-------------------"

# Token threshold for short vs long tree algorithm
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:tree:token_threshold" -Value "8000" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent

# Short tree settings (for documents under token_threshold)
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:tree:short:model" -Value "gpt-5.2" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:tree:short:temperature" -Value "0.5" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:tree:short:max_tokens" -Value "8000" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:tree:short:reasoning_effort" -Value "low" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent

# Long tree settings (for documents over token_threshold)
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:tree:long:model" -Value "gpt-5.2" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:tree:long:temperature" -Value "0.5" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:tree:long:max_tokens" -Value "10000" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:tree:long:reasoning_effort" -Value "low" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:tree:long:diversity" -Value "0.5" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:tree:long:n_gram_range_low" -Value "1" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:tree:long:n_gram_range_high" -Value "2" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:tree:long:nr_docs" -Value "10" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:tree:long:nr_topics" -Value "8" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:tree:long:overlap" -Value "3" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:tree:long:window_size" -Value "5" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:tree:long:remove_stopwords" -Value "true" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:tree:long:token_split_threshold" -Value "8000" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "params:tree:long:verbose" -Value "false" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent

# ============================================================================
# AI Model Placeholders (IT configures after Azure AI deployment)
# ============================================================================

Write-Host ""
Write-Host "AI Model Placeholders (IT must configure endpoints):" -ForegroundColor White
Write-Host "-----------------------------------------------------"

# GPT-4.1-mini
Set-AppConfigKey -ConfigName $AppConfigName -Key "ai:gpt-4.1-mini:endpoint" -Value "PLACEHOLDER-CONFIGURE-AFTER-AI-DEPLOYMENT" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKeyVaultRef -ConfigName $AppConfigName -Key "ai:gpt-4.1-mini:api_key" -SecretName "AI-FOUNDRY-API-KEY" -VaultUri $KeyVaultUri -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "ai:gpt-4.1-mini:rpm" -Value "PLACEHOLDER-SET-BASED-ON-DEPLOYMENT-QUOTA" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "ai:gpt-4.1-mini:tpm" -Value "PLACEHOLDER-SET-BASED-ON-DEPLOYMENT-QUOTA" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "ai:gpt-4.1-mini:context_window" -Value "1047576" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "ai:gpt-4.1-mini:max_output_tokens" -Value "32768" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent

# GPT-5.2
Set-AppConfigKey -ConfigName $AppConfigName -Key "ai:gpt-5.2:endpoint" -Value "PLACEHOLDER-CONFIGURE-AFTER-AI-DEPLOYMENT" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKeyVaultRef -ConfigName $AppConfigName -Key "ai:gpt-5.2:api_key" -SecretName "AI-FOUNDRY-API-KEY" -VaultUri $KeyVaultUri -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "ai:gpt-5.2:rpm" -Value "PLACEHOLDER-SET-BASED-ON-DEPLOYMENT-QUOTA" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "ai:gpt-5.2:tpm" -Value "PLACEHOLDER-SET-BASED-ON-DEPLOYMENT-QUOTA" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "ai:gpt-5.2:context_window" -Value "400000" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "ai:gpt-5.2:max_output_tokens" -Value "128000" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent

# Text Embedding
Set-AppConfigKey -ConfigName $AppConfigName -Key "ai:text-embedding-3-large:endpoint" -Value "PLACEHOLDER-CONFIGURE-AFTER-AI-DEPLOYMENT" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKeyVaultRef -ConfigName $AppConfigName -Key "ai:text-embedding-3-large:api_key" -SecretName "AI-FOUNDRY-API-KEY" -VaultUri $KeyVaultUri -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "ai:text-embedding-3-large:rpm" -Value "PLACEHOLDER-SET-BASED-ON-DEPLOYMENT-QUOTA" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "ai:text-embedding-3-large:tpm" -Value "PLACEHOLDER-SET-BASED-ON-DEPLOYMENT-QUOTA" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent

# OCR (Mistral Document AI)
Set-AppConfigKey -ConfigName $AppConfigName -Key "ai:ocr:endpoint" -Value "PLACEHOLDER-CONFIGURE-AFTER-AI-DEPLOYMENT" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKeyVaultRef -ConfigName $AppConfigName -Key "ai:ocr:api_key" -SecretName "AI-FOUNDRY-API-KEY" -VaultUri $KeyVaultUri -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "ai:ocr:model" -Value "mistral-document-ai-2505" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "ai:ocr:rpm" -Value "PLACEHOLDER-SET-BASED-ON-DEPLOYMENT-QUOTA" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent

# ============================================================================
# LTI Configuration
# ============================================================================

Write-Host ""
Write-Host "LTI Configuration:" -ForegroundColor White
Write-Host "------------------"

Set-AppConfigKey -ConfigName $AppConfigName -Key "lti:key_id" -Value "qwiser-lti-key-1" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "lti:platform:issuer" -Value "PLACEHOLDER-LMS-ISSUER-URL" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "lti:platform:client_id" -Value "PLACEHOLDER-LTI-CLIENT-ID" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "lti:platform:deployment_id" -Value "PLACEHOLDER-LTI-DEPLOYMENT-ID" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "lti:platform:oidc_auth_url" -Value "PLACEHOLDER-LMS-OIDC-AUTH-URL" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "lti:platform:oauth_token_url" -Value "PLACEHOLDER-LMS-OAUTH-TOKEN-URL" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent
Set-AppConfigKey -ConfigName $AppConfigName -Key "lti:platform:jwks_url" -Value "PLACEHOLDER-LMS-JWKS-URL" -ConfigLabel $Label -ForceOverwrite $Force.IsPresent

# ============================================================================
# Sentinel Key (for configuration refresh)
# ============================================================================

Write-Host ""
Write-Host "Sentinel Key:" -ForegroundColor White
Write-Host "-------------"

$timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
Set-AppConfigKey -ConfigName $AppConfigName -Key "sentinel" -Value $timestamp -ConfigLabel $Label -ForceOverwrite $true

# ============================================================================
# Summary
# ============================================================================

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "App Configuration seeding complete!" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. Deploy Azure AI Foundry models and update ai:*:endpoint values" -ForegroundColor Gray
Write-Host "  2. Update AI-FOUNDRY-API-KEY in Key Vault with actual API key" -ForegroundColor Gray
Write-Host "  3. Configure LTI settings if LMS integration is needed" -ForegroundColor Gray
Write-Host "  4. Update sentinel key to trigger config refresh in running services" -ForegroundColor Gray
Write-Host ""
