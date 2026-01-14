#!/bin/bash
# QWiser University - Container Image Import Script
# Imports images from QWiser ACR to customer's ACR
#
# Prerequisites:
#   - Azure CLI installed and logged in
#   - QWiser ACR credentials (provided by QWiser)
#   - Target ACR already deployed (via Bicep)
#
# Usage:
#   ./import-images.sh --source-user <username> --source-password <password> --target-acr <acr-name>
#
# Or with environment variables:
#   export QWISER_ACR_USERNAME="..."
#   export QWISER_ACR_PASSWORD="..."
#   ./import-images.sh --target-acr <acr-name>

set -e

# Configuration
SOURCE_REGISTRY="qwiser.azurecr.io"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSIONS_FILE="$SCRIPT_DIR/../VERSIONS.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
print_error() { echo -e "${RED}ERROR: $1${NC}" >&2; }
print_success() { echo -e "${GREEN}$1${NC}"; }
print_warning() { echo -e "${YELLOW}$1${NC}"; }
print_info() { echo "$1"; }

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Import QWiser container images to your Azure Container Registry.

Required:
    --target-acr NAME       Target ACR name (without .azurecr.io)

Credentials (or use environment variables QWISER_ACR_USERNAME / QWISER_ACR_PASSWORD):
    --source-user USER      QWiser ACR username (provided by QWiser)
    --source-password PASS  QWiser ACR password (provided by QWiser)

Optional:
    --versions-file PATH    Path to VERSIONS.txt (default: ../VERSIONS.txt)
    --dry-run               Show what would be imported without importing
    --help                  Show this help message

Examples:
    # Using command line arguments
    $(basename "$0") --source-user customer-exampleuni-pull --source-password xxx --target-acr qwiser-prod-acr

    # Using environment variables
    export QWISER_ACR_USERNAME="customer-exampleuni-pull"
    export QWISER_ACR_PASSWORD="xxx"
    $(basename "$0") --target-acr qwiser-prod-acr

EOF
    exit 1
}

# Parse arguments
SOURCE_USER="${QWISER_ACR_USERNAME:-}"
SOURCE_PASSWORD="${QWISER_ACR_PASSWORD:-}"
TARGET_ACR=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --source-user)
            SOURCE_USER="$2"
            shift 2
            ;;
        --source-password)
            SOURCE_PASSWORD="$2"
            shift 2
            ;;
        --target-acr)
            TARGET_ACR="$2"
            shift 2
            ;;
        --versions-file)
            VERSIONS_FILE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate required arguments
if [[ -z "$TARGET_ACR" ]]; then
    print_error "Missing required argument: --target-acr"
    usage
fi

if [[ -z "$SOURCE_USER" ]]; then
    print_error "Missing QWiser ACR username. Provide --source-user or set QWISER_ACR_USERNAME"
    usage
fi

if [[ -z "$SOURCE_PASSWORD" ]]; then
    print_error "Missing QWiser ACR password. Provide --source-password or set QWISER_ACR_PASSWORD"
    usage
fi

if [[ ! -f "$VERSIONS_FILE" ]]; then
    print_error "VERSIONS.txt not found at: $VERSIONS_FILE"
    exit 1
fi

# Parse VERSIONS.txt (skip comments and empty lines)
IMAGES=()
while IFS= read -r line; do
    # Skip comments and empty lines
    [[ "$line" =~ ^#.*$ ]] && continue
    [[ -z "$line" ]] && continue
    IMAGES+=("$line")
done < "$VERSIONS_FILE"

if [[ ${#IMAGES[@]} -eq 0 ]]; then
    print_error "No images found in VERSIONS.txt"
    exit 1
fi

# Display plan
echo "=============================================="
echo "QWiser Image Import"
echo "=============================================="
echo "Source registry:  $SOURCE_REGISTRY"
echo "Target ACR:       $TARGET_ACR"
echo "Images to import: ${#IMAGES[@]}"
echo ""
echo "Images:"
for img in "${IMAGES[@]}"; do
    echo "  - $img"
done
echo ""

if [[ "$DRY_RUN" == true ]]; then
    print_warning "DRY RUN - No images will be imported"
    echo ""
    echo "Commands that would be executed:"
    for img in "${IMAGES[@]}"; do
        echo "  az acr import --name $TARGET_ACR --source $SOURCE_REGISTRY/$img --image $img --username ****** --password ******"
    done
    exit 0
fi

# Verify Azure CLI is logged in
if ! az account show &>/dev/null; then
    print_error "Azure CLI not logged in. Run 'az login' first."
    exit 1
fi

# Verify target ACR exists
print_info "Verifying target ACR exists..."
if ! az acr show --name "$TARGET_ACR" &>/dev/null; then
    print_error "Target ACR '$TARGET_ACR' not found. Ensure the Bicep deployment completed successfully."
    exit 1
fi
print_success "Target ACR verified: $TARGET_ACR"
echo ""

# Import images
FAILED=()
SUCCEEDED=()

for img in "${IMAGES[@]}"; do
    print_info "Importing $img..."

    if az acr import \
        --name "$TARGET_ACR" \
        --source "$SOURCE_REGISTRY/$img" \
        --image "$img" \
        --username "$SOURCE_USER" \
        --password "$SOURCE_PASSWORD" \
        --force 2>&1; then
        print_success "  Imported: $img"
        SUCCEEDED+=("$img")
    else
        print_error "  Failed: $img"
        FAILED+=("$img")
    fi
    echo ""
done

# Summary
echo "=============================================="
echo "Import Summary"
echo "=============================================="
print_success "Succeeded: ${#SUCCEEDED[@]}"
if [[ ${#FAILED[@]} -gt 0 ]]; then
    print_error "Failed: ${#FAILED[@]}"
    for img in "${FAILED[@]}"; do
        echo "  - $img"
    done
    exit 1
fi

echo ""
print_success "All images imported successfully!"
echo ""
echo "Next steps:"
echo "  1. Verify images: az acr repository list --name $TARGET_ACR -o table"
echo "  2. Deploy K8s manifests: see docs/DEPLOYMENT_GUIDE.md"
