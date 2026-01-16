#!/bin/bash
# ==============================================================================
# seed-keyvault.sh - Seeds remaining secrets in Azure Key Vault
# ==============================================================================
# This script creates secrets that are NOT handled by Bicep deployment:
# - Auto-generated: JWT-SECRET, INTERNAL-SECRET-KEY, QDRANT-API-KEY
# - Placeholders: AI-FOUNDRY-API-KEY, LTI-PRIVATE-KEY
#
# Secrets handled by Bicep (DO NOT seed here):
# - DB-USER, DB-PASSWORD (from mysql.bicep)
# - STORAGE-ACCOUNT-KEY, STORAGE-CONNECTION-STRING (from storage-account.bicep)
# - APPLICATIONINSIGHTS-CONNECTION-STRING (from monitoring.bicep)
#
# Prerequisites:
# - Azure CLI installed and logged in
# - Key Vault Secrets Officer role on the Key Vault
# - Network access to Key Vault (Cloud Shell with VNet injection or VPN)
#
# Usage:
#   ./seed-keyvault.sh -k <keyvault-name> [-f]
#
# Options:
#   -k, --keyvault-name   Name of the Key Vault (required)
#   -f, --force           Overwrite existing secrets
#   -h, --help            Show this help message
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
KEYVAULT_NAME=""
RESOURCE_GROUP=""
FORCE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -k|--keyvault-name)
            KEYVAULT_NAME="$2"
            shift 2
            ;;
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 -k <keyvault-name> -g <resource-group> [-f]"
            echo ""
            echo "Options:"
            echo "  -k, --keyvault-name   Name of the Key Vault (required)"
            echo "  -g, --resource-group  Resource group name (required)"
            echo "  -f, --force           Overwrite existing secrets"
            echo "  -h, --help            Show this help message"
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
[[ -z "$KEYVAULT_NAME" ]] && missing_params+=("--keyvault-name")
[[ -z "$RESOURCE_GROUP" ]] && missing_params+=("--resource-group")

if [[ ${#missing_params[@]} -gt 0 ]]; then
    echo -e "${RED}Error: Missing required parameters: ${missing_params[*]}${NC}"
    echo "Usage: $0 -k <keyvault-name> -g <resource-group> [-f]"
    exit 1
fi

echo -e "${CYAN}======================================${NC}"
echo -e "${CYAN}QWiser Key Vault Secret Seeding${NC}"
echo -e "${CYAN}======================================${NC}"
echo ""
echo "Key Vault: $KEYVAULT_NAME"
echo "Resource Group: $RESOURCE_GROUP"
echo "Force overwrite: $FORCE"
echo ""

# Pre-flight check: verify Key Vault access
echo -e "${GRAY}Checking Key Vault access...${NC}"

# First check if public network access is disabled (management plane works even when data plane is blocked)
public_access=$(az keyvault show --name "$KEYVAULT_NAME" --resource-group "$RESOURCE_GROUP" --query "properties.publicNetworkAccess" -o tsv 2>/dev/null || echo "unknown")

set +e
error_output=$(az keyvault secret list --vault-name "$KEYVAULT_NAME" --maxresults 1 -o none 2>&1)
exit_code=$?
set -e

if [[ $exit_code -ne 0 ]]; then
    echo ""
    echo -e "${RED}[ERROR] Cannot access Key Vault '$KEYVAULT_NAME'${NC}"
    echo ""
    echo -e "${GRAY}Azure CLI output:${NC}"
    echo -e "${RED}$error_output${NC}"
    echo ""
    
    # Check network access first - "Forbidden" with public access disabled = network issue, not RBAC
    if echo "$public_access" | grep -qi "disabled" || echo "$error_output" | grep -qi "ForbiddenByConnection\|Public network access is disabled\|private link"; then
        echo -e "${YELLOW}Key Vault has public network access disabled (private endpoint only).${NC}"
        echo ""
        echo "Options:"
        echo "  1. Use Azure Cloud Shell (has private endpoint access)"
        echo "  2. Temporarily enable public access:"
        echo ""
        echo "     az keyvault update --name $KEYVAULT_NAME --resource-group $RESOURCE_GROUP --public-network-access Enabled"
        echo ""
        echo -e "${YELLOW}After seeding completes, re-secure the Key Vault:${NC}"
        echo ""
        echo "     az keyvault update --name $KEYVAULT_NAME --resource-group $RESOURCE_GROUP --public-network-access Disabled"
        echo ""
    elif echo "$error_output" | grep -qi "ForbiddenByRbac\|Forbidden\|not authorized\|does not have authorization"; then
        echo -e "${YELLOW}You need 'Key Vault Secrets Officer' role. Run:${NC}"
        echo ""
        echo "  az role assignment create \\"
        echo "      --role \"Key Vault Secrets Officer\" \\"
        echo "      --assignee-object-id \$(az ad signed-in-user show --query id -o tsv) \\"
        echo "      --assignee-principal-type User \\"
        echo "      --scope \$(az keyvault show --name $KEYVAULT_NAME --resource-group $RESOURCE_GROUP --query id -o tsv)"
        echo ""
        echo -e "${YELLOW}Wait 30-60 seconds, then verify access:${NC}"
        echo ""
        echo "  az keyvault secret list --vault-name $KEYVAULT_NAME --maxresults 1 -o table"
        echo ""
    fi
    echo ""
    echo -e "${RED}[FAILED] Key Vault seeding failed${NC}"
    exit 1
fi
echo -e "${GREEN}[OK]${NC} Key Vault access verified"
echo ""

# Function to check if secret exists
secret_exists() {
    local vault_name=$1
    local secret_name=$2
    local error_output

    if ! error_output=$(az keyvault secret show --vault-name "$vault_name" --name "$secret_name" --query "name" -o tsv 2>&1); then
        # Check if it's a "not found" error (expected) vs other errors (network, auth, etc.)
        if echo "$error_output" | grep -qi "SecretNotFound\|not found"; then
            echo ""  # Secret doesn't exist, return empty
            return 0
        else
            # Real error - print it and exit
            echo -e "${RED}[ERROR] Failed to check secret '$secret_name':${NC}" >&2
            echo -e "${RED}$error_output${NC}" >&2
            return 1
        fi
    fi
    echo "$error_output"  # Secret exists, return its name
}

# Function to generate cryptographically secure random string (hex)
generate_random_string() {
    local length=${1:-64}
    openssl rand -hex $((length / 2))
}

# Function to set a secret
set_secret() {
    local vault_name=$1
    local secret_name=$2
    local secret_value=$3
    local description=$4

    local exists
    exists=$(secret_exists "$vault_name" "$secret_name")

    if [[ -n "$exists" ]] && [[ "$FORCE" != "true" ]]; then
        echo -e "  ${YELLOW}[SKIP]${NC} $secret_name - already exists (use -f to overwrite)"
        return 0
    fi

    local action
    if [[ -n "$exists" ]]; then
        action="Updating"
    else
        action="Creating"
    fi

    echo -e "  ${GRAY}[$action] $secret_name - $description${NC}"

    local error_output
    if ! error_output=$(az keyvault secret set \
        --vault-name "$vault_name" \
        --name "$secret_name" \
        --value "$secret_value" \
        --output none 2>&1); then
        echo -e "  ${RED}[ERROR]${NC} $secret_name - Failed to set secret"
        echo -e "  ${RED}$error_output${NC}"
        return 1
    fi

    echo -e "  ${GREEN}[OK]${NC} $secret_name"
}

# ============================================================================
# Auto-Generated Secrets
# ============================================================================

echo ""
echo "Auto-Generated Secrets:"
echo "------------------------"

# JWT-SECRET - Used for signing JWT tokens
jwt_secret=$(generate_random_string 64)
set_secret "$KEYVAULT_NAME" "JWT-SECRET" "$jwt_secret" "JWT signing secret (auto-generated)"

# INTERNAL-SECRET-KEY - Used for internal service authentication
internal_secret=$(generate_random_string 64)
set_secret "$KEYVAULT_NAME" "INTERNAL-SECRET-KEY" "$internal_secret" "Internal service auth key (auto-generated)"

# QDRANT-API-KEY - Used for Qdrant vector database authentication
qdrant_api_key=$(generate_random_string 64)
set_secret "$KEYVAULT_NAME" "QDRANT-API-KEY" "$qdrant_api_key" "Qdrant API key (auto-generated)"

# ============================================================================
# Placeholder Secrets (IT must update after deployment)
# ============================================================================

echo ""
echo "Placeholder Secrets (IT must update these):"
echo "--------------------------------------------"

# AI-FOUNDRY-API-KEY - IT configures after Azure AI deployment
set_secret "$KEYVAULT_NAME" "AI-FOUNDRY-API-KEY" \
    "PLACEHOLDER-UPDATE-AFTER-AI-DEPLOYMENT" \
    "Azure AI Foundry API key (IT must update)"

# LTI-PRIVATE-KEY - IT configures for LMS integration
set_secret "$KEYVAULT_NAME" "LTI-PRIVATE-KEY" \
    "PLACEHOLDER-UPDATE-FOR-LTI-INTEGRATION" \
    "LTI 1.3 private key (IT must update)"

# ============================================================================
# Summary
# ============================================================================

echo ""
echo -e "${CYAN}======================================${NC}"
echo -e "${GREEN}Key Vault seeding complete!${NC}"
echo -e "${CYAN}======================================${NC}"
echo ""
echo "Next steps:"
echo -e "  ${GRAY}1. Update AI-FOUNDRY-API-KEY after deploying Azure AI Foundry${NC}"
echo -e "  ${GRAY}2. Update LTI-PRIVATE-KEY when configuring LMS integration${NC}"
echo ""
