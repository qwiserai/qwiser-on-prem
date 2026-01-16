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
#     ./scripts/apply.sh
#
#   Via az aks command invoke (for private AKS without VPN):
#     ./scripts/apply.sh --invoke -g <RG> -n <AKS>
#
# Options:
#   --invoke              Use az aks command invoke (required for private AKS)
#   --resource-group, -g  Azure resource group name (required with --invoke)
#   --aks-name, -n        AKS cluster name (required with --invoke)
#   --kustomize-dir, -k   Path to kustomization.yaml directory (default: k8s/base)
#   --namespace           Kubernetes namespace (default: default)
#   --dry-run             Show what would be applied without applying
#   --skip-version-check  Skip VERSIONS.txt vs kustomization.yaml validation (warning only)
#   -h, --help            Show this help message
#
# What it does:
#   1. Validates image tags in kustomization.yaml match VERSIONS.txt
#   2. Reads values from qwiser-config ConfigMap
#   3. Builds manifests with kustomize
#   4. Substitutes REPLACE_WITH_* placeholders with actual values
#   5. Applies to cluster
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
NAMESPACE="default"
USE_INVOKE=false
RESOURCE_GROUP=""
AKS_NAME=""
DRY_RUN=false
KUSTOMIZE_DIR=""
SKIP_VERSION_CHECK=false

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
        --kustomize-dir|-k)
            KUSTOMIZE_DIR="$2"
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
        --skip-version-check)
            SKIP_VERSION_CHECK=true
            shift
            ;;
        -h|--help)
            head -42 "$0" | tail -37
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Set default kustomize dir if not specified
if [ -z "$KUSTOMIZE_DIR" ]; then
    KUSTOMIZE_DIR="$REPO_ROOT/k8s/base"
fi

# Resolve to absolute path if relative
if [[ "$KUSTOMIZE_DIR" != /* ]]; then
    KUSTOMIZE_DIR="$(cd "$REPO_ROOT" && cd "$KUSTOMIZE_DIR" 2>/dev/null && pwd)" || {
        echo "[ERROR] Kustomize directory not found: $KUSTOMIZE_DIR"
        exit 1
    }
fi

# Verify kustomization.yaml exists
if [ ! -f "$KUSTOMIZE_DIR/kustomization.yaml" ]; then
    echo "[ERROR] kustomization.yaml not found in: $KUSTOMIZE_DIR"
    echo ""
    echo "Use -k to specify the directory containing kustomization.yaml"
    echo "Example: ./scripts/apply.sh -k k8s/base --invoke -g \$RESOURCE_GROUP -n \$AKS_NAME"
    exit 1
fi

# =============================================================================
# Helper Functions
# =============================================================================

# Validate that kustomization.yaml image tags match VERSIONS.txt
validate_versions() {
    local versions_file="$REPO_ROOT/VERSIONS.txt"
    local kustomization_file="$KUSTOMIZE_DIR/kustomization.yaml"
    
    if [ ! -f "$versions_file" ]; then
        echo ""
        echo "[ERROR] VERSIONS.txt not found at: $versions_file"
        echo ""
        echo "This file defines the expected image versions for deployment."
        echo "It should be in the root of the qwiser-on-prem repository."
        echo ""
        if [ "$SKIP_VERSION_CHECK" = true ]; then
            echo "[WARNING] --skip-version-check specified, continuing without validation..."
            return 0
        else
            echo "To bypass this check (advanced): ./scripts/apply.sh --skip-version-check ..."
            exit 1
        fi
    fi
    
    echo "Validating image versions..."
    
    local mismatches=()
    local missing_in_kustomization=()
    
    # Parse VERSIONS.txt - extract image:tag pairs
    while IFS= read -r line || [ -n "$line" ]; do
        # Strip Windows carriage returns
        line="${line//$'\r'/}"
        
        # Skip comments and empty lines
        [[ -z "${line// /}" ]] && continue
        [[ "$line" =~ ^# ]] && continue
        
        # Extract image name and tag (format: qwiser/image-name:tag)
        local image_name="${line%%:*}"
        local expected_tag="${line##*:}"
        
        # Look for this image in kustomization.yaml
        # Format: newTag: vX.X.X after a line containing the image name
        local kustomization_tag=""
        local in_image_block=false
        
        while IFS= read -r kline; do
            # Strip Windows carriage returns
            kline="${kline//$'\r'/}"
            
            if [[ "$kline" =~ "name:".*/qwiser/${image_name##*/} ]] || [[ "$kline" =~ "name:".*"${image_name##*/}" ]]; then
                in_image_block=true
            elif [ "$in_image_block" = true ] && [[ "$kline" =~ newTag: ]]; then
                kustomization_tag=$(echo "$kline" | sed 's/.*newTag:[[:space:]]*//' | tr -d ' \r')
                break
            elif [ "$in_image_block" = true ] && [[ "$kline" =~ "- name:" ]]; then
                # Moved to next image block without finding newTag
                break
            fi
        done < "$kustomization_file"
        
        if [ -z "$kustomization_tag" ]; then
            # Image might be commented out (e.g., embeddings-worker)
            if grep -q "# *- name:.*${image_name##*/}" "$kustomization_file" 2>/dev/null; then
                # Commented out - skip silently
                continue
            fi
            missing_in_kustomization+=("$image_name:$expected_tag")
        elif [ "$kustomization_tag" != "$expected_tag" ]; then
            mismatches+=("$image_name: VERSIONS.txt=$expected_tag, kustomization.yaml=$kustomization_tag")
        fi
    done < "$versions_file"
    
    # Report results
    local has_errors=false
    
    if [ ${#mismatches[@]} -gt 0 ]; then
        has_errors=true
        echo ""
        echo "[ERROR] Version mismatch between VERSIONS.txt and kustomization.yaml:"
        for mismatch in "${mismatches[@]}"; do
            echo "  - $mismatch"
        done
    fi
    
    if [ ${#missing_in_kustomization[@]} -gt 0 ]; then
        echo ""
        echo "[WARNING] Images in VERSIONS.txt not found in kustomization.yaml:"
        for missing in "${missing_in_kustomization[@]}"; do
            echo "  - $missing (may be intentionally excluded)"
        done
    fi
    
    if [ "$has_errors" = true ]; then
        echo ""
        echo "To fix: Update k8s/base/kustomization.yaml to match VERSIONS.txt"
        echo ""
        if [ "$SKIP_VERSION_CHECK" = true ]; then
            echo "[WARNING] --skip-version-check specified, continuing anyway..."
            echo ""
        else
            echo "To bypass this check (advanced): ./scripts/apply.sh --skip-version-check ..."
            exit 1
        fi
    else
        echo "[OK] Image versions validated"
    fi
}

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
echo "Kustomize Dir:  $KUSTOMIZE_DIR"
echo ""

# Validate versions before anything slow (fail fast)
validate_versions
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

# Convert YAML files to Unix line endings before kustomize (Windows CRLF breaks YAML parsing)
# Create a temp copy with fixed line endings
TEMP_KUSTOMIZE_DIR=$(mktemp -d)
cp -r "$KUSTOMIZE_DIR"/* "$TEMP_KUSTOMIZE_DIR/"
find "$TEMP_KUSTOMIZE_DIR" -type f \( -name "*.yaml" -o -name "*.yml" \) -exec sed -i 's/\r$//' {} \;

# Generate the substituted manifests
MANIFESTS=$(kubectl kustomize "$TEMP_KUSTOMIZE_DIR" | \
    sed "s/REPLACE_WITH_CUSTOM_DOMAIN/$CUSTOM_DOMAIN/g" | \
    sed "s/REPLACE_WITH_ACR_LOGIN_SERVER/${ACR_LOGIN_SERVER//\//\\/}/g" | \
    sed "s/REPLACE_WITH_UAMI_CLIENT_ID/$UAMI_CLIENT_ID/g" | \
    sed "s/REPLACE_WITH_KEY_VAULT_NAME/$KEY_VAULT_NAME/g" | \
    sed "s/REPLACE_WITH_TENANT_ID/$TENANT_ID/g" | \
    sed "s/REPLACE_WITH_STORAGE_ACCOUNT_NAME/$STORAGE_ACCOUNT_NAME/g")

rm -rf "$TEMP_KUSTOMIZE_DIR"

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
    # For invoke mode, we need to pass the manifests via --file
    # Write manifest to a temp file in the repo root
    TEMP_FILE="$REPO_ROOT/.tmp-manifest-$$.yaml"
    echo "$MANIFESTS" > "$TEMP_FILE"
    
    # Convert WSL path to Windows path if running in WSL (az.exe needs Windows paths)
    if [[ "$TEMP_FILE" == /mnt/* ]]; then
        # Convert /mnt/c/... to C:\...  (backslashes for Windows)
        TEMP_FILE_FOR_AZ=$(echo "$TEMP_FILE" | sed 's|^/mnt/\([a-z]\)/|\U\1:\\|' | sed 's|/|\\|g')
    else
        TEMP_FILE_FOR_AZ="$TEMP_FILE"
    fi
    
    echo "Uploading manifest ($(wc -c < "$TEMP_FILE") bytes)..."
    
    # Use --file to specify the file to upload (az expects the file, not directory)
    set +e
    APPLY_OUTPUT=$(az aks command invoke \
        --resource-group "$RESOURCE_GROUP" \
        --name "$AKS_NAME" \
        --command "kubectl apply -f .tmp-manifest-$$.yaml" \
        --file "$TEMP_FILE_FOR_AZ" 2>&1)
    APPLY_EXIT=$?
    set -e
    
    rm -f "$TEMP_FILE"
    
    # Check for errors in the output (exitcode is in the output text)
    if echo "$APPLY_OUTPUT" | grep -q "exitcode=0"; then
        echo "$APPLY_OUTPUT"
    else
        echo "$APPLY_OUTPUT"
        echo ""
        echo "[ERROR] Failed to apply manifests"
        echo ""
        echo "If you see 'unexpected end of stream', the manifest may have been truncated."
        echo "Try running with --dry-run to inspect the generated manifests."
        exit 1
    fi
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
