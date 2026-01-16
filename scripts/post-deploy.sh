#!/bin/bash
# ==============================================================================
# post-deploy.sh - Main orchestration script for QWiser University post-deployment
# ==============================================================================
# This script orchestrates all post-deployment configuration steps:
# 1. Seed Key Vault with auto-generated and placeholder secrets
# 2. Seed App Configuration with infrastructure values and defaults
# 3. Approve Front Door PE connection to Private Link Service
#
# Prerequisites:
# - Azure CLI installed and logged in
# - Appropriate RBAC roles (Key Vault Secrets Officer, App Config Data Owner)
# - Network access (Cloud Shell with VNet injection or VPN)
# - Bicep deployment completed (outputs available)
#
# Usage:
#   ./post-deploy.sh \
#       --resource-group <rg-name> \
#       --keyvault-name <kv-name> \
#       --appconfig-name <appconfig-name> \
#       --pls-name <pls-name> \
#       --mysql-host <mysql-host> \
#       --redis-host <redis-host> \
#       --storage-queue-url <queue-url> \
#       --label <label>
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
RESOURCE_GROUP=""
KEYVAULT_NAME=""
APPCONFIG_NAME=""
PLS_NAME=""
MYSQL_HOST=""
MYSQL_PORT="3306"
REDIS_HOST=""
REDIS_PORT="10000"
STORAGE_QUEUE_URL=""
LABEL=""
FORCE=false
SKIP_KEYVAULT=false
SKIP_APPCONFIG=false
SKIP_PE=false

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --keyvault-name)
            KEYVAULT_NAME="$2"
            shift 2
            ;;
        --appconfig-name)
            APPCONFIG_NAME="$2"
            shift 2
            ;;
        --pls-name)
            PLS_NAME="$2"
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
        --label)
            LABEL="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        --skip-keyvault)
            SKIP_KEYVAULT=true
            shift
            ;;
        --skip-appconfig)
            SKIP_APPCONFIG=true
            shift
            ;;
        --skip-pe)
            SKIP_PE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Required options:"
            echo "  -g, --resource-group     Resource group name"
            echo "  --keyvault-name          Key Vault name"
            echo "  --appconfig-name         App Configuration name"
            echo "  --pls-name               Private Link Service name"
            echo "  --mysql-host             MySQL server FQDN"
            echo "  --redis-host             Redis cache hostname"
            echo "  --storage-queue-url      Storage queue URL"
            echo "  --label                  Configuration label (e.g., production)"
            echo ""
            echo "Optional:"
            echo "  --mysql-port             MySQL port (default: 3306)"
            echo "  --redis-port             Redis port (default: 10000)"
            echo "  -f, --force              Overwrite existing values"
            echo "  --skip-keyvault          Skip Key Vault seeding"
            echo "  --skip-appconfig         Skip App Configuration seeding"
            echo "  --skip-pe                Skip PE connection approval"
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
[[ -z "$RESOURCE_GROUP" ]] && missing_params+=("--resource-group")
[[ -z "$KEYVAULT_NAME" ]] && missing_params+=("--keyvault-name")
[[ -z "$APPCONFIG_NAME" ]] && missing_params+=("--appconfig-name")
[[ -z "$PLS_NAME" ]] && missing_params+=("--pls-name")
[[ -z "$MYSQL_HOST" ]] && missing_params+=("--mysql-host")
[[ -z "$REDIS_HOST" ]] && missing_params+=("--redis-host")
[[ -z "$STORAGE_QUEUE_URL" ]] && missing_params+=("--storage-queue-url")
[[ -z "$LABEL" ]] && missing_params+=("--label")

if [[ ${#missing_params[@]} -gt 0 ]]; then
    echo -e "${RED}Error: Missing required parameters: ${missing_params[*]}${NC}"
    echo "Run '$0 --help' for usage information."
    exit 1
fi

# Construct Key Vault URI from name
KEYVAULT_URI="https://${KEYVAULT_NAME}.vault.azure.net/"

echo -e "${CYAN}============================================================${NC}"
echo -e "${CYAN}        QWiser University Post-Deployment Setup             ${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""
echo "Configuration:"
echo "  Resource Group:     $RESOURCE_GROUP"
echo "  Key Vault:          $KEYVAULT_NAME"
echo "  App Configuration:  $APPCONFIG_NAME"
echo "  Private Link Svc:   $PLS_NAME"
echo "  MySQL Host:         $MYSQL_HOST"
echo "  Redis Host:         $REDIS_HOST"
echo "  Storage Queue URL:  $STORAGE_QUEUE_URL"
echo "  Label:              $LABEL"
echo "  Force overwrite:    $FORCE"
echo ""

# ============================================================================
# Step 1: Seed Key Vault
# ============================================================================

if [[ "$SKIP_KEYVAULT" == "true" ]]; then
    echo -e "${YELLOW}[SKIP] Key Vault seeding (--skip-keyvault)${NC}"
else
    echo -e "${CYAN}[STEP 1/3] Seeding Key Vault...${NC}"
    echo ""

    force_arg=""
    [[ "$FORCE" == "true" ]] && force_arg="-f"

    if ! "$SCRIPT_DIR/seed-keyvault.sh" -k "$KEYVAULT_NAME" $force_arg; then
        echo -e "${RED}[FAILED] Key Vault seeding failed${NC}"
        exit 1
    fi
    echo -e "${GREEN}[OK] Key Vault seeding completed${NC}"
fi

echo ""

# ============================================================================
# Step 2: Seed App Configuration
# ============================================================================

if [[ "$SKIP_APPCONFIG" == "true" ]]; then
    echo -e "${YELLOW}[SKIP] App Configuration seeding (--skip-appconfig)${NC}"
else
    echo -e "${CYAN}[STEP 2/3] Seeding App Configuration...${NC}"
    echo ""

    force_arg=""
    [[ "$FORCE" == "true" ]] && force_arg="-f"

    if ! "$SCRIPT_DIR/seed-appconfig.sh" \
        --appconfig-name "$APPCONFIG_NAME" \
        --keyvault-uri "$KEYVAULT_URI" \
        --label "$LABEL" \
        --mysql-host "$MYSQL_HOST" \
        --mysql-port "$MYSQL_PORT" \
        --redis-host "$REDIS_HOST" \
        --redis-port "$REDIS_PORT" \
        --storage-queue-url "$STORAGE_QUEUE_URL" \
        $force_arg; then
        echo -e "${RED}[FAILED] App Configuration seeding failed${NC}"
        exit 1
    fi
    echo -e "${GREEN}[OK] App Configuration seeding completed${NC}"
fi

echo ""

# ============================================================================
# Step 3: Approve PE Connection
# ============================================================================

if [[ "$SKIP_PE" == "true" ]]; then
    echo -e "${YELLOW}[SKIP] PE connection approval (--skip-pe)${NC}"
else
    echo -e "${CYAN}[STEP 3/3] Approving Front Door PE Connection...${NC}"
    echo ""

    if ! "$SCRIPT_DIR/approve-pe-connection.sh" \
        --resource-group "$RESOURCE_GROUP" \
        --pls-name "$PLS_NAME"; then
        echo -e "${RED}[FAILED] PE connection approval failed${NC}"
        exit 1
    fi
    echo -e "${GREEN}[OK] PE connection approval completed${NC}"
fi

echo ""

# ============================================================================
# Summary
# ============================================================================

echo -e "${CYAN}============================================================${NC}"
echo -e "${GREEN}        Post-Deployment Setup Complete!                    ${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""

echo "Next steps:"
echo -e "  ${GRAY}1. Deploy Azure AI Foundry models${NC}"
echo -e "  ${GRAY}2. Update ai:*:endpoint values in App Configuration${NC}"
echo -e "  ${GRAY}3. Update AI-FOUNDRY-API-KEY secret in Key Vault${NC}"
echo -e "  ${GRAY}4. Configure LTI settings if LMS integration needed${NC}"
echo -e "  ${GRAY}5. Verify Front Door health probes are passing${NC}"
echo -e "  ${GRAY}6. Deploy applications to AKS cluster${NC}"
echo ""

exit 0
