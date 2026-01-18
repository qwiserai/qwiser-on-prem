#!/bin/bash
# ==============================================================================
# seed-appconfig.sh - Seeds Azure App Configuration for QWiser University
# ==============================================================================
# This script populates App Configuration with:
# - Infrastructure values (from Bicep outputs)
# - Key Vault references for secrets
# - Default configuration values for all application parameters
# - Placeholder values for AI endpoints (IT configures after AI deployment)
# - Sentinel key for configuration refresh
#
# Prerequisites:
# - Azure CLI installed and logged in
# - App Configuration Data Owner role on the App Configuration store
# - Network access to App Configuration (Cloud Shell with VNet injection or VPN)
#
# Usage:
#   ./seed-appconfig.sh \
#       --appconfig-name <name> \
#       --keyvault-uri <uri> \
#       --label <label> \
#       --mysql-host <host> \
#       --redis-host <host> \
#       --storage-queue-url <url> \
#       [-f|--force]
# ==============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Default values
APPCONFIG_NAME=""
RESOURCE_GROUP=""
KEYVAULT_URI=""
LABEL=""
MYSQL_HOST=""
MYSQL_PORT="3306"
REDIS_HOST=""
REDIS_PORT="10000"
STORAGE_QUEUE_URL=""
FORCE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --appconfig-name)
            APPCONFIG_NAME="$2"
            shift 2
            ;;
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --keyvault-uri)
            KEYVAULT_URI="$2"
            shift 2
            ;;
        --label)
            LABEL="$2"
            shift 2
            ;;
        --mysql-host)
            MYSQL_HOST="$2"
            shift 2
            ;;
        --mysql-port)
            MYSQL_PORT="$2"
            shift 2
            ;;
        --redis-host)
            REDIS_HOST="$2"
            shift 2
            ;;
        --redis-port)
            REDIS_PORT="$2"
            shift 2
            ;;
        --storage-queue-url)
            STORAGE_QUEUE_URL="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 --appconfig-name <name> -g <resource-group> --keyvault-uri <uri> --label <label> ..."
            echo ""
            echo "Required options:"
            echo "  --appconfig-name         Name of the App Configuration store"
            echo "  -g, --resource-group     Resource group name"
            echo "  --keyvault-uri           Key Vault URI (e.g., https://myvault.vault.azure.net/)"
            echo "  --label                  Label for configuration keys"
            echo "  --mysql-host             MySQL server FQDN"
            echo "  --redis-host             Redis cache hostname"
            echo "  --storage-queue-url      Storage queue URL"
            echo ""
            echo "Optional:"
            echo "  --mysql-port             MySQL port (default: 3306)"
            echo "  --redis-port             Redis port (default: 10000)"
            echo "  -f, --force              Overwrite existing keys"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate required parameters
missing_params=()
[[ -z "$APPCONFIG_NAME" ]] && missing_params+=("--appconfig-name")
[[ -z "$RESOURCE_GROUP" ]] && missing_params+=("--resource-group")
[[ -z "$KEYVAULT_URI" ]] && missing_params+=("--keyvault-uri")
[[ -z "$LABEL" ]] && missing_params+=("--label")
[[ -z "$MYSQL_HOST" ]] && missing_params+=("--mysql-host")
[[ -z "$REDIS_HOST" ]] && missing_params+=("--redis-host")
[[ -z "$STORAGE_QUEUE_URL" ]] && missing_params+=("--storage-queue-url")

if [[ ${#missing_params[@]} -gt 0 ]]; then
    echo -e "${RED}Error: Missing required parameters: ${missing_params[*]}${NC}"
    echo "Run '$0 --help' for usage information."
    exit 1
fi

# Ensure KeyVaultUri ends with /
[[ "$KEYVAULT_URI" != */ ]] && KEYVAULT_URI="$KEYVAULT_URI/"

echo -e "${CYAN}======================================${NC}"
echo -e "${CYAN}QWiser App Configuration Seeding${NC}"
echo -e "${CYAN}======================================${NC}"
echo ""
echo "App Configuration: $APPCONFIG_NAME"
echo "Resource Group: $RESOURCE_GROUP"
echo "Key Vault URI: $KEYVAULT_URI"
echo "Label: $LABEL"
echo "Force overwrite: $FORCE"
echo ""

# Pre-flight check: verify App Configuration access
echo -e "${GRAY}Checking App Configuration access...${NC}"

# First check if public network access is disabled (management plane works even when data plane is blocked)
public_access=$(az appconfig show --name "$APPCONFIG_NAME" --resource-group "$RESOURCE_GROUP" --query "publicNetworkAccess" -o tsv 2>/dev/null || echo "unknown")

# Use --auth-mode login to force RBAC auth and avoid access key fallback noise
# Temporarily disable set -e to capture the error properly
set +e
error_output=$(az appconfig kv list -n "$APPCONFIG_NAME" --auth-mode login --top 1 -o none 2>&1)
exit_code=$?
set -e
if [[ $exit_code -ne 0 ]]; then
    echo ""
    echo -e "${RED}[ERROR] Cannot access App Configuration '$APPCONFIG_NAME'${NC}"
    echo ""
    echo -e "${GRAY}Azure CLI output:${NC}"
    echo -e "${RED}$error_output${NC}"
    echo ""
    
    # Check network access first - "Forbidden" with public access disabled = network issue, not RBAC
    if echo "$public_access" | grep -qi "disabled" || echo "$error_output" | grep -qi "public network access\|private endpoint\|private link\|ConnectionError\|connection was refused"; then
        echo -e "${YELLOW}App Configuration has public network access disabled (private endpoint only).${NC}"
        echo ""
        echo "Options:"
        echo "  1. Use Azure Cloud Shell (has private endpoint access)"
        echo "  2. Temporarily enable public access:"
        echo ""
        echo "     az appconfig update --name $APPCONFIG_NAME --resource-group $RESOURCE_GROUP --enable-public-network true"
        echo ""
        echo -e "${YELLOW}After seeding completes, re-secure App Configuration by disabling public access:${NC}"
        echo ""
        echo "     az appconfig update --name $APPCONFIG_NAME --resource-group $RESOURCE_GROUP --enable-public-network false"
        echo ""
    elif echo "$error_output" | grep -qi "Forbidden\|AuthorizationFailed\|not authorized\|does not have authorization\|access key"; then
        echo -e "${YELLOW}You need 'App Configuration Data Owner' role. Run:${NC}"
        echo ""
        echo "  az role assignment create \\"
        echo "      --role \"App Configuration Data Owner\" \\"
        echo "      --assignee-object-id \$(az ad signed-in-user show --query id -o tsv) \\"
        echo "      --assignee-principal-type User \\"
        echo "      --scope \$(az appconfig show --name $APPCONFIG_NAME --resource-group $RESOURCE_GROUP --query id -o tsv)"
        echo ""
        echo -e "${YELLOW}Wait 30-60 seconds, then verify access:${NC}"
        echo ""
        echo "  az appconfig kv list -n $APPCONFIG_NAME --auth-mode login --top 1 -o table"
        echo ""
    fi
    echo ""
    echo -e "${RED}[FAILED] App Configuration seeding failed${NC}"
    exit 1
fi
echo -e "${GREEN}[OK]${NC} App Configuration access verified"
echo ""

# Function to set a regular key-value
set_key() {
    local key=$1
    local value=$2

    echo -e "  ${GRAY}[Setting] $key = $value${NC}"

    local error_output
    if ! error_output=$(az appconfig kv set \
        -n "$APPCONFIG_NAME" \
        --auth-mode login \
        --key "$key" \
        --value "$value" \
        --label "$LABEL" \
        --yes \
        --only-show-errors 2>&1); then
        echo -e "  ${RED}[ERROR]${NC} $key - Failed to set value"
        echo -e "  ${RED}$error_output${NC}"
        return 1
    fi

    echo -e "  ${GREEN}[OK]${NC} $key"
}

# Function to set a Key Vault reference
set_keyvault_ref() {
    local key=$1
    local secret_name=$2

    local secret_uri="${KEYVAULT_URI}secrets/$secret_name"

    echo -e "  ${GRAY}[Setting KV Ref] $key -> $secret_uri${NC}"

    local error_output
    if ! error_output=$(az appconfig kv set-keyvault \
        -n "$APPCONFIG_NAME" \
        --auth-mode login \
        --key "$key" \
        --secret-identifier "$secret_uri" \
        --label "$LABEL" \
        --yes \
        --only-show-errors 2>&1); then
        echo -e "  ${RED}[ERROR]${NC} $key - Failed to set Key Vault reference"
        echo -e "  ${RED}$error_output${NC}"
        return 1
    fi

    echo -e "  ${GREEN}[OK]${NC} $key"
}

# ============================================================================
# Infrastructure Configuration (from Bicep outputs)
# ============================================================================

echo ""
echo "Infrastructure Configuration:"
echo "------------------------------"

# Database
set_key "db:host" "$MYSQL_HOST"
set_key "db:port" "$MYSQL_PORT"
set_key "db:name" "qwiser"

# Redis (note: hyphen in max-connections, not underscore)
set_key "redis:host" "$REDIS_HOST"
set_key "redis:port" "$REDIS_PORT"
set_key "redis:max-connections" "100"
set_key "redis:socket_timeout" "300"
set_key "redis:socket_connect_timeout" "20"
set_key "redis:health_check_interval" "20"

# Azure Storage (key and queue_url expected by config code)
set_key "azure:storage:queue_url" "$STORAGE_QUEUE_URL"

# Qdrant (deployed via Helm - internal K8s service URL)
set_key "qdrant:cluster_url" "http://qdrant.qdrant.svc.cluster.local:6333"

# ============================================================================
# Key Vault References (Secrets)
# ============================================================================

echo ""
echo "Key Vault References:"
echo "---------------------"

# Database credentials
set_keyvault_ref "db:user" "DB-USER"
set_keyvault_ref "db:password" "DB-PASSWORD"

# Application secrets
set_keyvault_ref "jwt_secret" "JWT-SECRET"
set_keyvault_ref "internal_secret_key" "INTERNAL-SECRET-KEY"

# Qdrant
set_keyvault_ref "qdrant:api_key" "QDRANT-API-KEY"

# Application Insights
set_keyvault_ref "azure:applicationinsights_connection_string" "APPLICATIONINSIGHTS-CONNECTION-STRING"

# Storage key and connection string
set_keyvault_ref "azure:storage:key" "STORAGE-ACCOUNT-KEY"
set_keyvault_ref "azure:storage:connection_string" "STORAGE-CONNECTION-STRING"

# LTI (RSA key auto-generated by seed-keyvault.sh)
set_keyvault_ref "lti:private_key" "LTI-PRIVATE-KEY"

# ============================================================================
# Default Values
# ============================================================================

echo ""
echo "Default Values:"
echo "---------------"

# Environment
set_key "environment" "production"

# Logging
set_key "logging:level" "INFO"

# Worker settings
set_key "worker:polling_time" "5"

# ============================================================================
# Maintenance Configuration
# ============================================================================

echo ""
echo "Maintenance Configuration:"
echo "--------------------------"

set_key "maintenance:scheduled" "false"
set_key "maintenance:message" "We'll be back soon!"
set_key "maintenance:bypass_whitelist" ""
set_key "maintenance:scheduled_time" "2024-01-15T10:00:00Z"

# ============================================================================
# Text Configuration (used by get_text_config)
# ============================================================================

echo ""
echo "Text Configuration:"
echo "-------------------"

set_key "text:min_paragraph_chars" "200"
set_key "text:min_chunk_words" "10"
set_key "text:robust_loader_headless" "true"
set_key "text:robust_loader_timeout" "30"
set_key "text:robust_loader_max_retries" "3"
set_key "text:robust_loader_user_agent" "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# ============================================================================
# Embedding Configuration (used by get_embedding_config)
# ============================================================================

echo ""
echo "Embedding Configuration:"
echo "------------------------"

set_key "embedding:window_size" "5"
set_key "embedding:overlap" "2"
set_key "embedding:colbert_batch_size" "8"
set_key "embedding:qdrant_batch_size" "20"

# ============================================================================
# Chat Configuration (used by get_chat_config)
# ============================================================================

echo ""
echo "Chat Configuration:"
echo "-------------------"

# Chat message settings
set_key "params:chat:message:model" "gpt-5.2"
set_key "params:chat:message:temperature" "1"
set_key "params:chat:message:context_limit" "3000"
set_key "params:chat:message:response_limit" "5000"
set_key "params:chat:message:reasoning_effort" "low"

# Chat summary settings
set_key "params:chat:summary:model" "gpt-5.2"
set_key "params:chat:summary:temperature" "1"
set_key "params:chat:summary:context_limit" "5000"
set_key "params:chat:summary:response_limit" "5000"
set_key "params:chat:summary:reasoning_effort" "low"

# Chat name generation settings
set_key "params:chat:name:model" "gpt-4.1-mini"
set_key "params:chat:name:temperature" "0.7"
set_key "params:chat:name:max_tokens" "100"

# Chat standalone question settings
set_key "params:chat:standalone_question:model" "gpt-4.1-mini"
set_key "params:chat:standalone_question:temperature" "0.7"

# Chat general settings
set_key "params:chat:user_message_max_tokens" "2000"
set_key "params:chat:keep_recent_turns_min" "2"
set_key "params:chat:summary_update_trigger_turns" "6"
set_key "params:chat:semantic_search_min_tokens" "1000"
set_key "params:chat:system_prompt_tokens" "500"

# ============================================================================
# Questions Configuration
# ============================================================================

echo ""
echo "Questions Configuration:"
echo "------------------------"

set_key "params:questions:model" "gpt-5.2"
set_key "params:questions:temperature" "0.5"
set_key "params:questions:max_tokens" "3000"
set_key "params:questions:reasoning_effort" "low"

# ============================================================================
# Answers Configuration
# ============================================================================

echo ""
echo "Answers Configuration:"
echo "----------------------"

set_key "params:answers:model" "gpt-5.2"
set_key "params:answers:temperature" "0.5"
set_key "params:answers:max_tokens" "3000"
set_key "params:answers:reasoning_effort" "low"

# ============================================================================
# Study Notes Configuration
# ============================================================================

echo ""
echo "Study Notes Configuration:"
echo "--------------------------"

set_key "params:study_notes:model" "gpt-4.1-mini"
set_key "params:study_notes:temperature" "0.5"
set_key "params:study_notes:max_tokens" "10000"

# ============================================================================
# Tree Configuration
# ============================================================================

echo ""
echo "Tree Configuration:"
echo "-------------------"

# Token threshold for short vs long tree algorithm
set_key "params:tree:token_threshold" "8000"

# Short tree settings (for documents under token_threshold)
set_key "params:tree:short:model" "gpt-5.2"
set_key "params:tree:short:temperature" "0.5"
set_key "params:tree:short:max_tokens" "8000"
set_key "params:tree:short:reasoning_effort" "low"

# Long tree settings (for documents over token_threshold)
set_key "params:tree:long:model" "gpt-5.2"
set_key "params:tree:long:temperature" "0.5"
set_key "params:tree:long:max_tokens" "10000"
set_key "params:tree:long:reasoning_effort" "low"
set_key "params:tree:long:diversity" "0.5"
set_key "params:tree:long:n_gram_range_low" "1"
set_key "params:tree:long:n_gram_range_high" "2"
set_key "params:tree:long:nr_docs" "10"
set_key "params:tree:long:nr_topics" "8"
set_key "params:tree:long:overlap" "3"
set_key "params:tree:long:window_size" "5"
set_key "params:tree:long:remove_stopwords" "true"
set_key "params:tree:long:token_split_threshold" "8000"
set_key "params:tree:long:verbose" "false"

# ============================================================================
# AI Model Placeholders (IT configures after Azure AI deployment)
# ============================================================================

echo ""
echo "AI Model Placeholders (IT must configure endpoints):"
echo "-----------------------------------------------------"

# GPT-4.1-mini
set_key "ai:gpt-4.1-mini:endpoint" "PLACEHOLDER-CONFIGURE-AFTER-AI-DEPLOYMENT"
set_keyvault_ref "ai:gpt-4.1-mini:api_key" "AI-FOUNDRY-API-KEY"
set_key "ai:gpt-4.1-mini:rpm" "PLACEHOLDER-SET-BASED-ON-DEPLOYMENT-QUOTA"
set_key "ai:gpt-4.1-mini:tpm" "PLACEHOLDER-SET-BASED-ON-DEPLOYMENT-QUOTA"
set_key "ai:gpt-4.1-mini:context_window" "1047576"
set_key "ai:gpt-4.1-mini:max_output_tokens" "32768"

# GPT-5.2
set_key "ai:gpt-5.2:endpoint" "PLACEHOLDER-CONFIGURE-AFTER-AI-DEPLOYMENT"
set_keyvault_ref "ai:gpt-5.2:api_key" "AI-FOUNDRY-API-KEY"
set_key "ai:gpt-5.2:rpm" "PLACEHOLDER-SET-BASED-ON-DEPLOYMENT-QUOTA"
set_key "ai:gpt-5.2:tpm" "PLACEHOLDER-SET-BASED-ON-DEPLOYMENT-QUOTA"
set_key "ai:gpt-5.2:context_window" "400000"
set_key "ai:gpt-5.2:max_output_tokens" "128000"

# Text Embedding
set_key "ai:text-embedding-3-large:endpoint" "PLACEHOLDER-CONFIGURE-AFTER-AI-DEPLOYMENT"
set_keyvault_ref "ai:text-embedding-3-large:api_key" "AI-FOUNDRY-API-KEY"
set_key "ai:text-embedding-3-large:rpm" "PLACEHOLDER-SET-BASED-ON-DEPLOYMENT-QUOTA"
set_key "ai:text-embedding-3-large:tpm" "PLACEHOLDER-SET-BASED-ON-DEPLOYMENT-QUOTA"

# OCR (Mistral Document AI)
set_key "ai:ocr:endpoint" "PLACEHOLDER-CONFIGURE-AFTER-AI-DEPLOYMENT"
set_keyvault_ref "ai:ocr:api_key" "AI-FOUNDRY-API-KEY"
set_key "ai:ocr:model" "mistral-document-ai-2505"
set_key "ai:ocr:rpm" "PLACEHOLDER-SET-BASED-ON-DEPLOYMENT-QUOTA"
set_key "ai:ocr:max_concurrent" "8"  # Mistral has strict concurrency limits

# ============================================================================
# LTI Configuration
# ============================================================================

echo ""
echo "LTI Configuration:"
echo "------------------"

set_key "lti:key_id" "qwiser-lti-key-1"
set_key "lti:platform:issuer" "PLACEHOLDER-LMS-ISSUER-URL"
set_key "lti:platform:client_id" "PLACEHOLDER-LTI-CLIENT-ID"
set_key "lti:platform:deployment_id" "PLACEHOLDER-LTI-DEPLOYMENT-ID"
set_key "lti:platform:oidc_auth_url" "PLACEHOLDER-LMS-OIDC-AUTH-URL"
set_key "lti:platform:oauth_token_url" "PLACEHOLDER-LMS-OAUTH-TOKEN-URL"
set_key "lti:platform:jwks_url" "PLACEHOLDER-LMS-JWKS-URL"

# ============================================================================
# Sentinel Key (for configuration refresh)
# ============================================================================

echo ""
echo "Sentinel Key:"
echo "-------------"

timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
set_key "sentinel" "$timestamp"

# ============================================================================
# Summary
# ============================================================================

echo ""
echo -e "${CYAN}======================================${NC}"
echo -e "${GREEN}App Configuration seeding complete!${NC}"
echo -e "${CYAN}======================================${NC}"
echo ""
echo "Next steps:"
echo -e "  ${GRAY}1. Deploy Azure AI Foundry models and update ai:*:endpoint values${NC}"
echo -e "  ${GRAY}2. Update AI-FOUNDRY-API-KEY in Key Vault with actual API key${NC}"
echo -e "  ${GRAY}3. Configure LTI settings if LMS integration is needed${NC}"
echo -e "  ${GRAY}4. Update sentinel key to trigger config refresh in running services${NC}"
echo ""
