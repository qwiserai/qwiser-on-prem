#!/bin/bash
# =============================================================================
# QWiser University - K8s Manifest Apply Script
# =============================================================================
#
# This script applies K8s manifests with automatic placeholder substitution.
# It reads all values from the qwiser-config ConfigMap (created by Bicep).
#
# Usage:
#   Direct kubectl (requires VPN/network access to private AKS):
#     ./apply.sh
#
#   Via az aks command invoke (for private AKS without VPN):
#     ./apply.sh --invoke --resource-group <RG> --aks-name <AKS>
#
# Options:
#   --invoke              Use az aks command invoke (required for private AKS)
#   --resource-group, -g  Azure resource group name (required with --invoke)
#   --aks-name, -n        AKS cluster name (required with --invoke)
#   --namespace           Kubernetes namespace (default: default)
#   --dry-run             Show what would be applied without applying
#   -h, --help            Show this help message
#
# What it does:
#   1. Reads values from qwiser-config ConfigMap
#   2. Builds manifests with kustomize
#   3. Substitutes REPLACE_WITH_* placeholders with actual values
#   4. Applies to cluster
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
NAMESPACE="default"
USE_INVOKE=false
RESOURCE_GROUP=""
AKS_NAME=""
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --invoke)
            USE_INVOKE=true
            shift
            ;;
        --resource-group|-g)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --aks-name|-n)
            AKS_NAME="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            head -35 "$0" | tail -30
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# =============================================================================
# Helper Functions
# =============================================================================

# Run kubectl command - either directly or via az aks command invoke
run_kubectl() {
    local cmd="$1"
    if [ "$USE_INVOKE" = true ]; then
        az aks command invoke \
            --resource-group "$RESOURCE_GROUP" \
            --name "$AKS_NAME" \
            --command "$cmd" \
            --query "logs" -o tsv 2>/dev/null
    else
        eval "$cmd"
    fi
}

# Check if kubectl can reach the cluster
check_cluster_access() {
    if [ "$USE_INVOKE" = true ]; then
        # Using invoke mode - check az cli is logged in
        if ! az account show &>/dev/null; then
            echo "[ERROR] Not logged in to Azure CLI"
            echo ""
            echo "Run: az login"
            exit 1
        fi
        return 0
    fi

    # Direct mode - check if kubectl can reach cluster
    if ! kubectl cluster-info &>/dev/null 2>&1; then
        echo "[ERROR] Cannot connect to Kubernetes cluster"
        echo ""
        echo "This is a private AKS cluster. You have two options:"
        echo ""
        echo "Option 1: Use --invoke flag (recommended for private AKS)"
        echo ""
        echo "  ./apply.sh --invoke -g <RESOURCE_GROUP> -n <AKS_NAME>"
        echo ""
        echo "  Example:"
        echo "  ./apply.sh --invoke -g \$RESOURCE_GROUP -n \$AKS_NAME"
        echo ""
        echo "Option 2: Connect via VPN/Bastion to the Azure VNet"
        echo ""
        echo "  Then run: ./apply.sh"
        echo ""
        exit 1
    fi
}

# =============================================================================
# Main Script
# =============================================================================

echo "=============================================="
echo "QWiser University K8s Deployment"
echo "=============================================="
echo ""

# Validate invoke mode requirements
if [ "$USE_INVOKE" = true ]; then
    if [ -z "$RESOURCE_GROUP" ]; then
        echo "[ERROR] --resource-group is required when using --invoke"
        exit 1
    fi
    if [ -z "$AKS_NAME" ]; then
        echo "[ERROR] --aks-name is required when using --invoke"
        exit 1
    fi
    echo "Mode:           az aks command invoke"
    echo "Resource Group: $RESOURCE_GROUP"
    echo "AKS Cluster:    $AKS_NAME"
else
    echo "Mode:           Direct kubectl"
fi
echo "Namespace:      $NAMESPACE"
echo ""

# Check cluster access
check_cluster_access

# Check if ConfigMap exists
echo "Reading configuration from qwiser-config ConfigMap..."
CONFIG_CHECK=$(run_kubectl "kubectl get cm qwiser-config -n $NAMESPACE -o jsonpath='{.metadata.name}'" 2>&1) || true

if [ -z "$CONFIG_CHECK" ] || [ "$CONFIG_CHECK" = "" ]; then
    echo "[ERROR] qwiser-config ConfigMap not found in namespace $NAMESPACE"
    echo ""
    echo "This ConfigMap is created by Bicep during deployment."
    echo "Please ensure the Bicep deployment completed successfully."
    echo ""
    echo "To check if it exists:"
    if [ "$USE_INVOKE" = true ]; then
        echo "  az aks command invoke -g $RESOURCE_GROUP -n $AKS_NAME \\"
        echo "      --command \"kubectl get cm qwiser-config -n $NAMESPACE\""
    else
        echo "  kubectl get cm qwiser-config -n $NAMESPACE"
    fi
    exit 1
fi

echo "[OK] ConfigMap found"
echo ""

# Get values from ConfigMap
echo "Extracting configuration values..."
CUSTOM_DOMAIN=$(run_kubectl "kubectl get cm qwiser-config -n $NAMESPACE -o jsonpath='{.data.CUSTOM_DOMAIN}'")
ACR_LOGIN_SERVER=$(run_kubectl "kubectl get cm qwiser-config -n $NAMESPACE -o jsonpath='{.data.ACR_LOGIN_SERVER}'")
UAMI_CLIENT_ID=$(run_kubectl "kubectl get cm qwiser-config -n $NAMESPACE -o jsonpath='{.data.UAMI_CLIENT_ID}'")
KEY_VAULT_NAME=$(run_kubectl "kubectl get cm qwiser-config -n $NAMESPACE -o jsonpath='{.data.KEY_VAULT_NAME}'")
TENANT_ID=$(run_kubectl "kubectl get cm qwiser-config -n $NAMESPACE -o jsonpath='{.data.TENANT_ID}'")
STORAGE_ACCOUNT_NAME=$(run_kubectl "kubectl get cm qwiser-config -n $NAMESPACE -o jsonpath='{.data.STORAGE_ACCOUNT_NAME}'")

# Validate required values
MISSING_VALUES=()
[ -z "$CUSTOM_DOMAIN" ] && MISSING_VALUES+=("CUSTOM_DOMAIN")
[ -z "$ACR_LOGIN_SERVER" ] && MISSING_VALUES+=("ACR_LOGIN_SERVER")
[ -z "$UAMI_CLIENT_ID" ] && MISSING_VALUES+=("UAMI_CLIENT_ID")
[ -z "$KEY_VAULT_NAME" ] && MISSING_VALUES+=("KEY_VAULT_NAME")
[ -z "$TENANT_ID" ] && MISSING_VALUES+=("TENANT_ID")
[ -z "$STORAGE_ACCOUNT_NAME" ] && MISSING_VALUES+=("STORAGE_ACCOUNT_NAME")

if [ ${#MISSING_VALUES[@]} -gt 0 ]; then
    echo "[ERROR] Missing values in qwiser-config ConfigMap:"
    for val in "${MISSING_VALUES[@]}"; do
        echo "  - $val"
    done
    echo ""
    echo "The Bicep deployment may not have completed correctly."
    exit 1
fi

echo ""
echo "Configuration:"
echo "  Custom Domain:     $CUSTOM_DOMAIN"
echo "  ACR Login Server:  $ACR_LOGIN_SERVER"
echo "  UAMI Client ID:    ${UAMI_CLIENT_ID:0:8}..."
echo "  Key Vault Name:    $KEY_VAULT_NAME"
echo "  Tenant ID:         ${TENANT_ID:0:8}..."
echo "  Storage Account:   $STORAGE_ACCOUNT_NAME"
echo ""

# Build manifests with kustomize
echo "Building manifests with kustomize..."
cd "$SCRIPT_DIR"

# Generate the substituted manifests
MANIFESTS=$(kubectl kustomize . | \
    sed "s/REPLACE_WITH_CUSTOM_DOMAIN/$CUSTOM_DOMAIN/g" | \
    sed "s/REPLACE_WITH_ACR_LOGIN_SERVER/${ACR_LOGIN_SERVER//\//\\/}/g" | \
    sed "s/REPLACE_WITH_UAMI_CLIENT_ID/$UAMI_CLIENT_ID/g" | \
    sed "s/REPLACE_WITH_KEY_VAULT_NAME/$KEY_VAULT_NAME/g" | \
    sed "s/REPLACE_WITH_TENANT_ID/$TENANT_ID/g" | \
    sed "s/REPLACE_WITH_STORAGE_ACCOUNT_NAME/$STORAGE_ACCOUNT_NAME/g")

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo "=== DRY RUN - Manifests that would be applied ==="
    echo ""
    echo "$MANIFESTS"
    echo ""
    echo "=== End of dry run ==="
    exit 0
fi

# Apply manifests
echo "Applying manifests to cluster..."
echo ""

if [ "$USE_INVOKE" = true ]; then
    # For invoke mode, we need to pass the manifests as stdin via a heredoc in the command
    # Create a temporary approach: base64 encode and decode
    MANIFESTS_B64=$(echo "$MANIFESTS" | base64 -w 0)
    
    run_kubectl "echo '$MANIFESTS_B64' | base64 -d | kubectl apply -f -"
else
    echo "$MANIFESTS" | kubectl apply -f -
fi

echo ""
echo "=============================================="
echo "Deployment Complete"
echo "=============================================="
echo ""
echo "Verify deployments:"
if [ "$USE_INVOKE" = true ]; then
    echo "  az aks command invoke -g $RESOURCE_GROUP -n $AKS_NAME \\"
    echo "      --command \"kubectl get pods -n $NAMESPACE\""
    echo ""
    echo "  az aks command invoke -g $RESOURCE_GROUP -n $AKS_NAME \\"
    echo "      --command \"kubectl get ingress -n $NAMESPACE\""
else
    echo "  kubectl get pods -n $NAMESPACE"
    echo "  kubectl get ingress -n $NAMESPACE"
fi
echo ""
