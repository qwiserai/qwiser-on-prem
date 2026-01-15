#!/bin/bash
# =============================================================================
# QWiser University - K8s Manifest Apply Script
# =============================================================================
#
# This script applies K8s manifests with automatic placeholder substitution.
# It reads all values from the qwiser-config ConfigMap (created by Bicep).
#
# Prerequisites:
#   - kubectl configured with cluster access
#   - Bicep deployment completed (ConfigMap exists with required values)
#
# Usage:
#   ./apply.sh
#
# What it does:
#   1. Reads values from qwiser-config ConfigMap:
#      - CUSTOM_DOMAIN (e.g., qwiser.myuniversity.edu)
#      - ACR_LOGIN_SERVER (e.g., myunivacr.azurecr.io)
#      - UAMI_CLIENT_ID (User-Assigned Managed Identity client ID)
#      - KEY_VAULT_NAME (Azure Key Vault name)
#      - TENANT_ID (Azure AD tenant ID)
#      - STORAGE_ACCOUNT_NAME (Storage account for ML models)
#   2. Builds manifests with kustomize
#   3. Substitutes REPLACE_WITH_* placeholders with actual values
#   4. Applies to cluster
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${NAMESPACE:-default}"

echo "=== QWiser University K8s Deployment ==="
echo "Namespace: $NAMESPACE"
echo ""

# Check if ConfigMap exists
echo "Reading configuration from qwiser-config ConfigMap..."
if ! kubectl get cm qwiser-config -n "$NAMESPACE" &>/dev/null; then
    echo "ERROR: qwiser-config ConfigMap not found in namespace $NAMESPACE"
    echo "Please ensure Bicep deployment completed successfully."
    exit 1
fi

# Get values from ConfigMap
CUSTOM_DOMAIN=$(kubectl get cm qwiser-config -n "$NAMESPACE" -o jsonpath='{.data.CUSTOM_DOMAIN}')
ACR_LOGIN_SERVER=$(kubectl get cm qwiser-config -n "$NAMESPACE" -o jsonpath='{.data.ACR_LOGIN_SERVER}')
UAMI_CLIENT_ID=$(kubectl get cm qwiser-config -n "$NAMESPACE" -o jsonpath='{.data.UAMI_CLIENT_ID}')
KEY_VAULT_NAME=$(kubectl get cm qwiser-config -n "$NAMESPACE" -o jsonpath='{.data.KEY_VAULT_NAME}')
TENANT_ID=$(kubectl get cm qwiser-config -n "$NAMESPACE" -o jsonpath='{.data.TENANT_ID}')
STORAGE_ACCOUNT_NAME=$(kubectl get cm qwiser-config -n "$NAMESPACE" -o jsonpath='{.data.STORAGE_ACCOUNT_NAME}')

# Validate required values
if [ -z "$CUSTOM_DOMAIN" ]; then
    echo "ERROR: CUSTOM_DOMAIN not found in qwiser-config ConfigMap"
    exit 1
fi

if [ -z "$ACR_LOGIN_SERVER" ]; then
    echo "ERROR: ACR_LOGIN_SERVER not found in qwiser-config ConfigMap"
    exit 1
fi

if [ -z "$UAMI_CLIENT_ID" ]; then
    echo "ERROR: UAMI_CLIENT_ID not found in qwiser-config ConfigMap"
    exit 1
fi

if [ -z "$KEY_VAULT_NAME" ]; then
    echo "ERROR: KEY_VAULT_NAME not found in qwiser-config ConfigMap"
    exit 1
fi

if [ -z "$TENANT_ID" ]; then
    echo "ERROR: TENANT_ID not found in qwiser-config ConfigMap"
    exit 1
fi

if [ -z "$STORAGE_ACCOUNT_NAME" ]; then
    echo "ERROR: STORAGE_ACCOUNT_NAME not found in qwiser-config ConfigMap"
    exit 1
fi

echo "Custom Domain:       $CUSTOM_DOMAIN"
echo "ACR Login Server:    $ACR_LOGIN_SERVER"
echo "UAMI Client ID:      ${UAMI_CLIENT_ID:0:8}..."
echo "Key Vault Name:      $KEY_VAULT_NAME"
echo "Tenant ID:           ${TENANT_ID:0:8}..."
echo "Storage Account:     $STORAGE_ACCOUNT_NAME"
echo ""

# Build with kustomize and apply substitutions
echo "Building manifests with kustomize..."
cd "$SCRIPT_DIR"

# Use kustomize build, then substitute placeholders, then apply
kubectl kustomize . | \
    sed "s/REPLACE_WITH_CUSTOM_DOMAIN/$CUSTOM_DOMAIN/g" | \
    sed "s/REPLACE_WITH_ACR_LOGIN_SERVER/${ACR_LOGIN_SERVER//\//\\/}/g" | \
    sed "s/REPLACE_WITH_UAMI_CLIENT_ID/$UAMI_CLIENT_ID/g" | \
    sed "s/REPLACE_WITH_KEY_VAULT_NAME/$KEY_VAULT_NAME/g" | \
    sed "s/REPLACE_WITH_TENANT_ID/$TENANT_ID/g" | \
    sed "s/REPLACE_WITH_STORAGE_ACCOUNT_NAME/$STORAGE_ACCOUNT_NAME/g" | \
    kubectl apply -f -

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Verify deployments:"
echo "  kubectl get pods -n $NAMESPACE"
echo "  kubectl get ingress -n $NAMESPACE"
echo ""
