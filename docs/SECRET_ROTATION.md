# QWiser University - Secret Rotation Guide

> **Last Updated**: 2026-01-14
> **Version**: 1.0.0
> **Audience**: University IT Infrastructure Teams

---

## Overview

This guide covers procedures for rotating secrets in the QWiser University deployment. Proper secret rotation is essential for security compliance and should be performed periodically or after suspected compromise.

---

## Secret Inventory

### Key Vault Secrets

| Secret Name | Type | Rotation Impact | Recommended Frequency |
|-------------|------|-----------------|----------------------|
| JWT-SECRET | Auto-generated | Pod restart required | Quarterly |
| INTERNAL-SECRET-KEY | Auto-generated | Pod restart required | Quarterly |
| QDRANT-API-KEY | Auto-generated | Pod + Qdrant restart | Quarterly |
| AI-FOUNDRY-API-KEY | Azure AI Foundry | Hot-reload | As needed |
| LTI-PRIVATE-KEY | RSA key | Hot-reload + LMS update | Annually |
| DB-USER | MySQL | N/A (managed) | N/A |
| DB-PASSWORD | MySQL | Pod restart required | Annually |
| STORAGE-ACCOUNT-KEY | Azure Storage | Hot-reload | Annually |
| STORAGE-CONNECTION-STRING | Azure Storage | Hot-reload | Annually |
| APPLICATIONINSIGHTS-CONNECTION-STRING | Azure | Hot-reload | N/A |

### Hot-Reload vs Pod Restart

| Type | Description | User Impact |
|------|-------------|-------------|
| Hot-reload | Update sentinel key, services refresh automatically | None |
| Pod restart | Rolling deployment restart required | Minimal (rolling) |

---

## Rotation Procedures

### JWT-SECRET

Used for signing user authentication tokens. Rotation invalidates all active sessions.

**Impact**: All users logged out, must re-authenticate.

**Procedure**:

```bash
KEYVAULT_NAME="qwiser-prod-kv"

# 1. Generate new secret
NEW_SECRET=$(openssl rand -hex 64)

# 2. Update Key Vault
az keyvault secret set \
    --vault-name "$KEYVAULT_NAME" \
    --name "JWT-SECRET" \
    --value "$NEW_SECRET"

# 3. Restart pods to pick up new secret
kubectl rollout restart deployment/public-api
kubectl rollout restart deployment/internal-db

# 4. Verify rollout complete
kubectl rollout status deployment/public-api
kubectl rollout status deployment/internal-db
```

**Verification**:
- Existing sessions invalidated (users redirected to login)
- New logins work correctly
- No errors in pod logs

---

### INTERNAL-SECRET-KEY

Used for service-to-service authentication.

**Impact**: Brief service communication disruption during rollout.

**Procedure**:

```bash
# 1. Generate new secret
NEW_SECRET=$(openssl rand -hex 64)

# 2. Update Key Vault
az keyvault secret set \
    --vault-name "$KEYVAULT_NAME" \
    --name "INTERNAL-SECRET-KEY" \
    --value "$NEW_SECRET"

# 3. Restart ALL services (they must all use same key)
for DEPLOYMENT in public-api internal-db text-loading other-generation topic-modeling smart-quiz embeddings-worker-msgs embeddings-worker-hybrid; do
    kubectl rollout restart deployment/$DEPLOYMENT
done

# 4. Wait for all rollouts
kubectl get deployments -w
```

**Important**: All services must be restarted together to maintain communication.

---

### QDRANT-API-KEY

Used for Qdrant vector database authentication.

**Impact**: Brief Qdrant access disruption.

**Procedure**:

```bash
# 1. Generate new API key
NEW_KEY=$(openssl rand -hex 32)

# 2. Update Key Vault
az keyvault secret set \
    --vault-name "$KEYVAULT_NAME" \
    --name "QDRANT-API-KEY" \
    --value "$NEW_KEY"

# 3. Update K8s secret for Qdrant pod
kubectl delete secret qdrant-apikey
kubectl create secret generic qdrant-apikey --from-literal=api-key="$NEW_KEY"

# 4. Restart Qdrant StatefulSet
kubectl rollout restart statefulset/qdrant -n qdrant

# 5. Wait for Qdrant to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=qdrant -n qdrant --timeout=300s

# 6. Trigger App Config refresh (services get new key)
APPCONFIG_NAME="qwiser-prod-appconfig"
az appconfig kv set \
    -n "$APPCONFIG_NAME" \
    --key "sentinel" \
    --value "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --label production \
    --yes

# 7. Wait for services to refresh (~45 seconds)
sleep 60

# 8. Restart services using Qdrant
kubectl rollout restart deployment/public-api
kubectl rollout restart deployment/embeddings-worker-hybrid
```

**Verification**:
```bash
kubectl exec -it deployment/public-api -- python -c "
from qdrant_client import QdrantClient
from QWiserCommons.config import Config
import asyncio
async def test():
    await Config.load()
    client = QdrantClient(url='http://qdrant:6333', api_key=Config.get('qdrant:api_key'))
    print('Collections:', client.get_collections())
asyncio.run(test())
"
```

---

### AI-FOUNDRY-API-KEY

Used for Azure AI Foundry API access.

**Impact**: None (hot-reload).

**Procedure**:

```bash
# 1. Regenerate key in Azure AI Foundry
az cognitiveservices account keys regenerate \
    --name "qwiser-prod-ai" \
    --resource-group "qwiser-prod-rg" \
    --key-name key1

# 2. Get new key
NEW_KEY=$(az cognitiveservices account keys list \
    --name "qwiser-prod-ai" \
    --resource-group "qwiser-prod-rg" \
    --query "key1" -o tsv)

# 3. Update Key Vault
az keyvault secret set \
    --vault-name "$KEYVAULT_NAME" \
    --name "AI-FOUNDRY-API-KEY" \
    --value "$NEW_KEY"

# 4. Trigger config refresh (hot-reload)
az appconfig kv set \
    -n "$APPCONFIG_NAME" \
    --key "sentinel" \
    --value "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --label production \
    --yes
```

**Verification**:
- Wait 60 seconds for refresh
- Test AI generation in application

---

### LTI-PRIVATE-KEY

Used for LTI 1.3 authentication with LMS.

**Impact**: LTI launches fail until LMS updated with new public key.

**Procedure**:

```bash
# 1. Generate new RSA key pair
openssl genrsa -out lti-private-key-new.pem 2048
openssl rsa -in lti-private-key-new.pem -pubout -out lti-public-key-new.pem

# 2. Update Key Vault
az keyvault secret set \
    --vault-name "$KEYVAULT_NAME" \
    --name "LTI-PRIVATE-KEY" \
    --file lti-private-key-new.pem

# 3. Trigger config refresh
az appconfig kv set \
    -n "$APPCONFIG_NAME" \
    --key "sentinel" \
    --value "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --label production \
    --yes

# 4. Update LMS with new public key
cat lti-public-key-new.pem
# (copy to LMS external tool configuration)

# 5. Clean up local files
rm lti-private-key-new.pem lti-public-key-new.pem
```

**Important**: Coordinate with LMS administrator for minimal disruption.

---

### DB-PASSWORD

MySQL admin password rotation.

**Impact**: Pod restart required. Database connections briefly interrupted.

**Procedure**:

```bash
# 1. Generate new password
NEW_PASSWORD=$(openssl rand -base64 32)

# 2. Update MySQL server
az mysql flexible-server update \
    --resource-group "qwiser-prod-rg" \
    --name "qwiser-prod-mysql" \
    --admin-password "$NEW_PASSWORD"

# 3. Update Key Vault
az keyvault secret set \
    --vault-name "$KEYVAULT_NAME" \
    --name "DB-PASSWORD" \
    --value "$NEW_PASSWORD"

# 4. Restart database-connected services
kubectl rollout restart deployment/internal-db
kubectl rollout restart deployment/public-api

# 5. Verify database connectivity
kubectl logs deployment/internal-db | grep "Database connection"
```

---

### STORAGE-ACCOUNT-KEY

Azure Storage account key rotation.

**Impact**: Hot-reload. Workers may briefly fail blob operations.

**Procedure**:

```bash
STORAGE_ACCOUNT="qwiserprodsa"

# 1. Regenerate storage key
az storage account keys renew \
    --account-name "$STORAGE_ACCOUNT" \
    --resource-group "qwiser-prod-rg" \
    --key primary

# 2. Get new key
NEW_KEY=$(az storage account keys list \
    --account-name "$STORAGE_ACCOUNT" \
    --resource-group "qwiser-prod-rg" \
    --query "[0].value" -o tsv)

# 3. Build new connection string
NEW_CONN_STRING="DefaultEndpointsProtocol=https;AccountName=$STORAGE_ACCOUNT;AccountKey=$NEW_KEY;EndpointSuffix=core.windows.net"

# 4. Update Key Vault
az keyvault secret set \
    --vault-name "$KEYVAULT_NAME" \
    --name "STORAGE-ACCOUNT-KEY" \
    --value "$NEW_KEY"

az keyvault secret set \
    --vault-name "$KEYVAULT_NAME" \
    --name "STORAGE-CONNECTION-STRING" \
    --value "$NEW_CONN_STRING"

# 5. Trigger config refresh
az appconfig kv set \
    -n "$APPCONFIG_NAME" \
    --key "sentinel" \
    --value "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --label production \
    --yes
```

---

## Emergency Rotation

In case of suspected compromise:

### Immediate Actions

1. **Identify compromised secret(s)**
2. **Rotate immediately** using procedures above
3. **Review audit logs**:
   ```bash
   az monitor activity-log list \
       --resource-group "qwiser-prod-rg" \
       --start-time $(date -d "-24 hours" -u +%Y-%m-%dT%H:%M:%SZ) \
       --query "[?authorization.action=='Microsoft.KeyVault/vaults/secrets/read']"
   ```
4. **Check for unauthorized access** in application logs
5. **Notify security team** per incident response procedures

### Rotate All Secrets

In case of major breach, rotate everything:

```bash
#!/bin/bash
# emergency-rotate-all.sh

KEYVAULT_NAME="qwiser-prod-kv"

# Generate all new secrets
JWT_SECRET=$(openssl rand -hex 64)
INTERNAL_SECRET=$(openssl rand -hex 64)
QDRANT_KEY=$(openssl rand -hex 32)

# Update Key Vault
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "JWT-SECRET" --value "$JWT_SECRET"
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "INTERNAL-SECRET-KEY" --value "$INTERNAL_SECRET"
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "QDRANT-API-KEY" --value "$QDRANT_KEY"

# Update Qdrant K8s secret
kubectl delete secret qdrant-apikey
kubectl create secret generic qdrant-apikey --from-literal=api-key="$QDRANT_KEY"

# Restart everything
kubectl rollout restart statefulset/qdrant -n qdrant
kubectl rollout restart deployment --all

echo "All secrets rotated. Monitor pod status."
```

---

## Audit & Compliance

### Key Vault Audit Logs

Enable and review Key Vault audit logs:

```bash
# Enable diagnostic logging
az monitor diagnostic-settings create \
    --name "keyvault-audit" \
    --resource "/subscriptions/.../resourceGroups/qwiser-prod-rg/providers/Microsoft.KeyVault/vaults/qwiser-prod-kv" \
    --workspace "/subscriptions/.../resourceGroups/qwiser-prod-rg/providers/Microsoft.OperationalInsights/workspaces/qwiser-prod-law" \
    --logs '[{"category": "AuditEvent", "enabled": true}]'

# Query audit logs
az monitor log-analytics query \
    --workspace "$WORKSPACE_ID" \
    --analytics-query "AzureDiagnostics | where ResourceProvider == 'MICROSOFT.KEYVAULT' | where OperationName contains 'Secret'"
```

### Rotation Schedule

| Secret | Frequency | Last Rotated | Next Due |
|--------|-----------|--------------|----------|
| JWT-SECRET | Quarterly | YYYY-MM-DD | YYYY-MM-DD |
| INTERNAL-SECRET-KEY | Quarterly | YYYY-MM-DD | YYYY-MM-DD |
| QDRANT-API-KEY | Quarterly | YYYY-MM-DD | YYYY-MM-DD |
| AI-FOUNDRY-API-KEY | As needed | YYYY-MM-DD | - |
| LTI-PRIVATE-KEY | Annually | YYYY-MM-DD | YYYY-MM-DD |
| DB-PASSWORD | Annually | YYYY-MM-DD | YYYY-MM-DD |
| STORAGE-ACCOUNT-KEY | Annually | YYYY-MM-DD | YYYY-MM-DD |

---

## Related Documentation

- [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) - Full deployment guide
- [APPCONFIG_REFERENCE.md](./APPCONFIG_REFERENCE.md) - Configuration reference
- [POST_DEPLOYMENT.md](./POST_DEPLOYMENT.md) - Post-deployment tasks
