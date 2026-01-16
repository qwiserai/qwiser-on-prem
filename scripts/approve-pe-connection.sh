#!/bin/bash
# ==============================================================================
# approve-pe-connection.sh - Approves Front Door Private Endpoint to Private Link Service
# ==============================================================================
# This script approves the pending private endpoint connection from Azure Front Door
# to the Private Link Service (PLS) that fronts the AKS internal load balancer.
#
# Background:
# - Front Door creates a PE connection to the PLS during deployment
# - The connection is initially in "Pending" state
# - This script approves the connection to enable traffic flow
#
# Prerequisites:
# - Azure CLI installed and logged in
# - Network Contributor role on the resource group containing the PLS
#
# Usage:
#   ./approve-pe-connection.sh \
#       --resource-group <rg-name> \
#       --pls-name <private-link-service-name>
#
# Options:
#   -g, --resource-group   Resource group containing the PLS (required)
#   -p, --pls-name         Name of the Private Link Service (required)
#   -h, --help             Show this help message
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
PLS_NAME=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -p|--pls-name)
            PLS_NAME="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 -g <resource-group> -p <pls-name>"
            echo ""
            echo "Options:"
            echo "  -g, --resource-group   Resource group containing the PLS (required)"
            echo "  -p, --pls-name         Name of the Private Link Service (required)"
            echo "  -h, --help             Show this help message"
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
[[ -z "$PLS_NAME" ]] && missing_params+=("--pls-name")

if [[ ${#missing_params[@]} -gt 0 ]]; then
    echo -e "${RED}Error: Missing required parameters: ${missing_params[*]}${NC}"
    echo "Usage: $0 -g <resource-group> -p <pls-name>"
    exit 1
fi

echo -e "${CYAN}======================================${NC}"
echo -e "${CYAN}Private Endpoint Connection Approval${NC}"
echo -e "${CYAN}======================================${NC}"
echo ""
echo "Resource Group: $RESOURCE_GROUP"
echo "Private Link Service: $PLS_NAME"
echo ""

# Get pending connections
echo -e "${GRAY}Fetching pending PE connections...${NC}"

error_output=""
if ! pending_connections=$(az network private-link-service show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$PLS_NAME" \
    --query "privateEndpointConnections[?privateLinkServiceConnectionState.status=='Pending'].name" \
    -o tsv 2>&1); then
    echo -e "${RED}[ERROR] Failed to fetch Private Link Service${NC}"
    echo -e "${RED}$pending_connections${NC}"
    exit 1
fi

if [[ -z "$pending_connections" ]]; then
    echo -e "${YELLOW}No pending connections found.${NC}"
    echo ""

    # Check for already approved connections
    approved_connections=$(az network private-link-service show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$PLS_NAME" \
        --query "privateEndpointConnections[?privateLinkServiceConnectionState.status=='Approved'].name" \
        -o tsv 2>/dev/null || echo "")

    if [[ -n "$approved_connections" ]]; then
        echo -e "${GREEN}Found approved connections:${NC}"
        echo "$approved_connections" | while read -r conn; do
            echo -e "  ${GREEN}✓${NC} $conn"
        done
    else
        echo -e "${YELLOW}No connections found on this PLS.${NC}"
        echo "The Front Door may not have completed its PE connection yet."
        echo "Wait a few minutes and try again."
    fi
    exit 0
fi

# Approve each pending connection
echo -e "${GRAY}Found pending connections:${NC}"
while IFS= read -r conn; do
    echo "  - $conn"
done <<< "$pending_connections"
echo ""

approved_count=0
failed_count=0

# Use here-string to avoid subshell issue with pipe
while IFS= read -r connection_name; do
    if [[ -z "$connection_name" ]]; then
        continue
    fi

    echo -e "${GRAY}[Approving] $connection_name${NC}"

    error_output=""
    if ! error_output=$(az network private-link-service connection update \
        --resource-group "$RESOURCE_GROUP" \
        --name "$connection_name" \
        --service-name "$PLS_NAME" \
        --connection-status "Approved" \
        --description "Approved by post-deploy script" \
        --output none 2>&1); then
        echo -e "${RED}[FAILED]${NC} Failed to approve $connection_name"
        echo -e "${RED}$error_output${NC}"
        ((failed_count++)) || true
    else
        echo -e "${GREEN}[OK]${NC} $connection_name approved"
        ((approved_count++)) || true
    fi
done <<< "$pending_connections"

# Summary
echo ""
echo -e "${CYAN}======================================${NC}"
echo -e "${GREEN}PE Connection Approval Complete${NC}"
echo -e "${CYAN}======================================${NC}"
echo ""

# Verify final state
echo "Final connection states:"
az network private-link-service show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$PLS_NAME" \
    --query "privateEndpointConnections[].{Name:name, Status:privateLinkServiceConnectionState.status}" \
    -o table

echo ""
echo "Next steps:"
echo -e "  ${GRAY}1. Verify Front Door health probes are passing${NC}"
echo -e "  ${GRAY}2. Test connectivity through Front Door endpoint${NC}"
echo ""
