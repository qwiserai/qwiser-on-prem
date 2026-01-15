#!/bin/bash
# ============================================================================
# check_role.sh - Verify Azure permissions for QWiser University deployment
# ============================================================================
# Checks if the current az CLI user has sufficient permissions to deploy
# the qwiser-on-prem Bicep template at subscription scope.
#
# Required permissions:
#   - Microsoft.Resources/* (create resource groups, deploy resources)
#   - Microsoft.Authorization/roleAssignments/* (assign roles to managed identities)
#   - Microsoft.Security/pricings/* (enable Defender for Containers)
#
# Typically satisfied by: Owner, or Contributor + User Access Administrator,
# or classic Service Administrator/Co-Administrator roles.
# ============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Required role definition IDs (built-in Azure roles)
OWNER_ROLE="8e3af657-a8ff-443c-a75c-2fe8c4bcb635"
CONTRIBUTOR_ROLE="b24988ac-6180-42a0-ab88-20f7382dd24c"
USER_ACCESS_ADMIN_ROLE="18d7d88d-d35e-4fb5-a5c3-7773c20a72d9"

echo -e "${CYAN}============================================================================${NC}"
echo -e "${CYAN}QWiser University Deployment - Permission Check${NC}"
echo -e "${CYAN}============================================================================${NC}"
echo ""

# Check if logged in
echo -e "${CYAN}[1/6] Checking Azure CLI login status...${NC}"
if ! az account show &>/dev/null; then
    echo -e "${RED}ERROR: Not logged in to Azure CLI.${NC}"
    echo "Run 'az login' first."
    exit 1
fi

# Get current user info
ACCOUNT_INFO=$(az account show --output json)
SUBSCRIPTION_ID=$(echo "$ACCOUNT_INFO" | jq -r '.id')
SUBSCRIPTION_NAME=$(echo "$ACCOUNT_INFO" | jq -r '.name')
USER_TYPE=$(echo "$ACCOUNT_INFO" | jq -r '.user.type')
USER_NAME=$(echo "$ACCOUNT_INFO" | jq -r '.user.name')

echo -e "  User:         ${GREEN}$USER_NAME${NC}"
echo -e "  Type:         $USER_TYPE"
echo -e "  Subscription: ${GREEN}$SUBSCRIPTION_NAME${NC}"
echo -e "  ID:           $SUBSCRIPTION_ID"
echo ""

# Get the signed-in user's object ID
echo -e "${CYAN}[2/6] Resolving user principal ID...${NC}"
if [[ "$USER_TYPE" == "servicePrincipal" ]]; then
    PRINCIPAL_ID=$(az ad sp show --id "$USER_NAME" --query id -o tsv 2>/dev/null || echo "")
    PRINCIPAL_TYPE="ServicePrincipal"
else
    PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "")
    PRINCIPAL_TYPE="User"
fi

if [[ -z "$PRINCIPAL_ID" ]]; then
    echo -e "${YELLOW}WARNING: Could not resolve principal ID. Falling back to UPN.${NC}"
    PRINCIPAL_ID="$USER_NAME"
fi
echo -e "  Principal ID: $PRINCIPAL_ID"
echo -e "  Type:         $PRINCIPAL_TYPE"
echo ""

# Check for classic administrator roles
echo -e "${CYAN}[3/6] Checking classic administrator roles...${NC}"
IS_CLASSIC_ADMIN=false
CLASSIC_ADMIN_ROLE=""

CLASSIC_ADMINS=$(az role assignment list \
    --include-classic-administrators \
    --scope "/subscriptions/$SUBSCRIPTION_ID" \
    --output json 2>/dev/null || echo "[]")

# Look for current user in classic admins
while IFS= read -r admin; do
    ADMIN_NAME=$(echo "$admin" | jq -r '.principalName // .name // ""')
    ADMIN_ROLE=$(echo "$admin" | jq -r '.roleDefinitionName // ""')

    # Classic admins have roles like "ServiceAdministrator", "AccountAdministrator", "CoAdministrator"
    if [[ "$ADMIN_ROLE" == *"Administrator"* ]] || [[ "$ADMIN_ROLE" == *"CoAdmin"* ]]; then
        # Check if this is our user (case-insensitive comparison)
        if [[ "${ADMIN_NAME,,}" == "${USER_NAME,,}" ]]; then
            IS_CLASSIC_ADMIN=true
            CLASSIC_ADMIN_ROLE="$ADMIN_ROLE"
            echo -e "  ${GREEN}✓ Classic role: $ADMIN_ROLE${NC}"
        fi
    fi
done < <(echo "$CLASSIC_ADMINS" | jq -c '.[]' 2>/dev/null)

if ! $IS_CLASSIC_ADMIN; then
    echo -e "  No classic administrator role found"
fi
echo ""

# Get RBAC role assignments at subscription scope
echo -e "${CYAN}[4/6] Fetching RBAC role assignments...${NC}"
ROLE_ASSIGNMENTS=$(az role assignment list \
    --assignee "$PRINCIPAL_ID" \
    --scope "/subscriptions/$SUBSCRIPTION_ID" \
    --include-inherited \
    --output json 2>/dev/null || echo "[]")

if [[ "$ROLE_ASSIGNMENTS" == "[]" ]]; then
    ROLE_ASSIGNMENTS=$(az role assignment list \
        --assignee "$USER_NAME" \
        --scope "/subscriptions/$SUBSCRIPTION_ID" \
        --include-inherited \
        --output json 2>/dev/null || echo "[]")
fi

ROLE_COUNT=$(echo "$ROLE_ASSIGNMENTS" | jq 'length')
echo -e "  Found ${GREEN}$ROLE_COUNT${NC} RBAC role assignment(s)"

HAS_OWNER=false
HAS_CONTRIBUTOR=false
HAS_USER_ACCESS_ADMIN=false

while IFS= read -r assignment; do
    [[ -z "$assignment" ]] && continue
    ROLE_DEF_ID=$(echo "$assignment" | jq -r '.roleDefinitionId' | sed 's|.*/||')
    ROLE_NAME=$(echo "$assignment" | jq -r '.roleDefinitionName')
    SCOPE=$(echo "$assignment" | jq -r '.scope')

    if [[ "$SCOPE" == "/subscriptions/$SUBSCRIPTION_ID" ]] || [[ "$SCOPE" == "/" ]] || [[ "$SCOPE" == "/subscriptions/$SUBSCRIPTION_ID/"* ]]; then
        echo -e "  • ${GREEN}$ROLE_NAME${NC} (scope: $SCOPE)"

        case "$ROLE_DEF_ID" in
            "$OWNER_ROLE")
                HAS_OWNER=true
                ;;
            "$CONTRIBUTOR_ROLE")
                HAS_CONTRIBUTOR=true
                ;;
            "$USER_ACCESS_ADMIN_ROLE")
                HAS_USER_ACCESS_ADMIN=true
                ;;
        esac
    fi
done < <(echo "$ROLE_ASSIGNMENTS" | jq -c '.[]' 2>/dev/null)
echo ""

# Practical permission test - check actual permissions via ARM
echo -e "${CYAN}[5/6] Testing actual permissions (ARM API)...${NC}"
CAN_CREATE_RG=false
CAN_WRITE_ROLE_ASSIGNMENTS=false

# Test: Can create resource groups?
RG_PERM_CHECK=$(az rest --method POST \
    --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Authorization/permissions?api-version=2022-04-01" \
    2>/dev/null || echo "{}")

# Simpler check: try to validate we can write to the subscription
# Check permissions for Microsoft.Resources/subscriptions
PERMISSIONS=$(az rest --method GET \
    --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Authorization/permissions?api-version=2022-04-01" \
    --output json 2>/dev/null || echo '{"value":[]}')

# Parse permissions
PERM_ACTIONS=$(echo "$PERMISSIONS" | jq -r '.value[].actions[]' 2>/dev/null | sort -u)
PERM_NOT_ACTIONS=$(echo "$PERMISSIONS" | jq -r '.value[].notActions[]' 2>/dev/null | sort -u)

# Check for resource creation permission
if echo "$PERM_ACTIONS" | grep -qE '^\*$|^Microsoft\.Resources/\*|^Microsoft\.Resources/subscriptions/resourceGroups/write'; then
    CAN_CREATE_RG=true
    echo -e "  ${GREEN}✓ Can create resource groups${NC}"
else
    echo -e "  ${RED}✗ Cannot create resource groups${NC}"
fi

# Check for role assignment permission
if echo "$PERM_ACTIONS" | grep -qE '^\*$|^Microsoft\.Authorization/\*|^Microsoft\.Authorization/roleAssignments/write'; then
    # Check it's not in notActions
    if ! echo "$PERM_NOT_ACTIONS" | grep -qE '^Microsoft\.Authorization/\*|^Microsoft\.Authorization/roleAssignments'; then
        CAN_WRITE_ROLE_ASSIGNMENTS=true
        echo -e "  ${GREEN}✓ Can create role assignments${NC}"
    else
        echo -e "  ${RED}✗ Cannot create role assignments (in notActions)${NC}"
    fi
else
    echo -e "  ${RED}✗ Cannot create role assignments${NC}"
fi
echo ""

# Final evaluation
echo -e "${CYAN}[6/6] Permission evaluation...${NC}"
echo ""

CAN_DEPLOY=false

# Classic admin with Service/Account Administrator has full access
if $IS_CLASSIC_ADMIN; then
    if [[ "$CLASSIC_ADMIN_ROLE" == *"ServiceAdministrator"* ]] || \
       [[ "$CLASSIC_ADMIN_ROLE" == *"AccountAdministrator"* ]] || \
       [[ "$CLASSIC_ADMIN_ROLE" == *"CoAdministrator"* ]]; then
        echo -e "  ${GREEN}✓ Classic $CLASSIC_ADMIN_ROLE role${NC}"
        echo "    → Full permissions via classic administrator role"
        CAN_DEPLOY=true
    fi
fi

# RBAC Owner
if $HAS_OWNER; then
    echo -e "  ${GREEN}✓ Owner role (RBAC)${NC}"
    echo "    → Full permissions for deployment"
    CAN_DEPLOY=true
fi

# RBAC Contributor + User Access Admin
if $HAS_CONTRIBUTOR && $HAS_USER_ACCESS_ADMIN; then
    echo -e "  ${GREEN}✓ Contributor + User Access Administrator (RBAC)${NC}"
    echo "    → Sufficient permissions for deployment"
    CAN_DEPLOY=true
fi

# Practical test result
if $CAN_CREATE_RG && $CAN_WRITE_ROLE_ASSIGNMENTS; then
    if ! $CAN_DEPLOY; then
        echo -e "  ${GREEN}✓ Practical permission test passed${NC}"
        echo "    → ARM API confirms sufficient permissions"
        CAN_DEPLOY=true
    fi
fi

# Partial permissions
if ! $CAN_DEPLOY; then
    if $HAS_CONTRIBUTOR || $CAN_CREATE_RG; then
        echo -e "  ${YELLOW}⚠ Partial permissions detected${NC}"
        echo -e "  ${GREEN}✓ Can create resources${NC}"
        echo -e "  ${RED}✗ Cannot create role assignments${NC}"
        echo "    → Deployment will FAIL when creating role assignments for managed identity"
    else
        echo -e "  ${RED}✗ Insufficient permissions${NC}"
    fi
fi

echo ""
echo -e "${CYAN}============================================================================${NC}"

if $CAN_DEPLOY; then
    echo -e "${GREEN}RESULT: You CAN deploy the QWiser University infrastructure.${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Review/customize bicep/main.bicepparam"
    echo "  2. Deploy with:"
    echo "     az deployment sub create \\"
    echo "       --location <region> \\"
    echo "       --template-file bicep/main.bicep \\"
    echo "       --parameters bicep/main.bicepparam"
    exit 0
else
    echo -e "${RED}RESULT: You CANNOT deploy the QWiser University infrastructure.${NC}"
    echo ""
    echo "Required: One of the following at subscription scope:"
    echo "  • Owner role"
    echo "  • Contributor + User Access Administrator roles"
    echo "  • Classic Service Administrator or Account Administrator"
    echo ""
    echo "Command to grant Owner role:"
    echo "  az role assignment create \\"
    echo "    --assignee \"$USER_NAME\" \\"
    echo "    --role \"Owner\" \\"
    echo "    --scope \"/subscriptions/$SUBSCRIPTION_ID\""
    exit 1
fi
