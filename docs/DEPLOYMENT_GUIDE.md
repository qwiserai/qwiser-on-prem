# QWiser University - Deployment Guide

> **Last Updated**: 2026-01-15
> **Version**: 1.1.0
> **Audience**: University IT Infrastructure Teams

---

## Table of Contents

1. [Prerequisites Checklist](#prerequisites-checklist)
2. [Deployment Overview](#deployment-overview)
3. [Phase 1: Infrastructure Deployment](#phase-1-infrastructure-deployment)
4. [Phase 2: Post-Deployment Configuration](#phase-2-post-deployment-configuration)
5. [Phase 3: AI Models Setup](#phase-3-ai-models-setup)
6. [Phase 4: ML Models Setup](#phase-4-ml-models-setup)
7. [Phase 5: Container Image Import](#phase-5-container-image-import)
8. [Phase 6: Kubernetes Deployment](#phase-6-kubernetes-deployment)
9. [Phase 7: DNS & Front Door Configuration](#phase-7-dns--front-door-configuration)
10. [Phase 8: Verification](#phase-8-verification)
11. [Troubleshooting](#troubleshooting)
12. [Cleanup](#cleanup)

---

## Prerequisites Checklist

See [PREREQUISITES.md](./PREREQUISITES.md) for details.

- [ ] QWiser ACR pull credentials
- [ ] Azure subscription with Owner or Contributor + UAA
- [ ] Azure CLI, kubectl, Helm, Git, jq installed

---

## Deployment Overview

### Architecture Summary

```
Internet
    │
    ▼
Azure Front Door (Premium)
    │ WAF + TLS
    ▼
Private Link Service ──► Private Endpoint
    │
    ▼
NGINX Ingress Controller (Internal LB)
    │
    ▼
AKS Cluster (Private)
    │
    ├─► MySQL Flexible Server (Private Endpoint)
    ├─► Azure Managed Redis (Private Endpoint)
    ├─► Azure Blob Storage (Private Endpoint)
    ├─► Azure Key Vault (Private Endpoint)
    ├─► Azure App Configuration (Private Endpoint)
    └─► Azure Container Registry (Private Endpoint)
```

---

## Phase 1: Infrastructure Deployment

Use the **Deploy to Azure** button in the [README](../README.md). It provides guided configuration with built-in validation.

If you prefer CLI, see `bicep/main.bicep` and `bicep/main.bicepparam` if you know what you're doing.

### Capture Outputs

After deployment completes, capture the outputs for use in all subsequent phases.

**Find your deployment name:**
```bash
az deployment sub list --query "sort_by([?properties.provisioningState=='Succeeded'].{Name:name, State:properties.provisioningState, Timestamp:properties.timestamp}, &Timestamp)" -o table
```

**Save outputs to file:**
```bash
# Replace <deployment-name> with your actual deployment name from above
az deployment sub show \
    --name <deployment-name> \
    --query "properties.outputs" \
    -o json > deployment-outputs.json
```

**Verify the file was created:**
```bash
# Should show all output values
jq 'keys' deployment-outputs.json
```

> **Important**: Keep `deployment-outputs.json` in your working directory. All subsequent commands reference this file.

---

## Phase 2: Post-Deployment Configuration

Seeds Key Vault secrets and App Configuration values.

**Linux/WSL users**: Fix line endings and make scripts executable:
```bash
find . -name "*.sh" -exec sed -i 's/\r$//' {} \;
find . -name "*.sh" -exec chmod +x {} \;
```

```bash
# Load values from deployment outputs
RESOURCE_GROUP=$(jq -r '.resourceGroupName.value' deployment-outputs.json)
KEYVAULT_NAME=$(jq -r '.keyVaultName.value' deployment-outputs.json)
APPCONFIG_NAME=$(jq -r '.appConfigName.value' deployment-outputs.json)
PLS_NAME=$(jq -r '.privateLinkServiceName.value' deployment-outputs.json)
MYSQL_HOST=$(jq -r '.mysqlServerFqdn.value' deployment-outputs.json)
REDIS_HOST=$(jq -r '.redisHostName.value' deployment-outputs.json)
STORAGE_ACCOUNT=$(jq -r '.storageAccountName.value' deployment-outputs.json)

./scripts/post-deploy.sh \
    --resource-group "$RESOURCE_GROUP" \
    --keyvault-name "$KEYVAULT_NAME" \
    --appconfig-name "$APPCONFIG_NAME" \
    --pls-name "$PLS_NAME" \
    --mysql-host "$MYSQL_HOST" \
    --redis-host "$REDIS_HOST" \
    --storage-queue-url "https://${STORAGE_ACCOUNT}.queue.core.windows.net" \
    --label production
```

---

## Phase 3: AI Models Setup

Deploy AI models in Azure AI Foundry. See [AI_MODELS_SETUP.md](./AI_MODELS_SETUP.md) for detailed instructions.

### Required Models

| Model                  | Purpose                                    |
| ---------------------- | ------------------------------------------ |
| gpt-4.1-mini           | Chat name generation, standalone questions |
| gpt-5.2                | Main generation (questions, chat, trees)   |
| text-embedding-3-large | Vector embeddings                          |
| mistral-document-ai    | OCR/Document processing                    |

### Update App Configuration

After deploying AI models, update the endpoint values:

```bash
APPCONFIG_NAME=$(jq -r '.appConfigName.value' deployment-outputs.json)

# Example for gpt-4.1-mini
az appconfig kv set \
    -n "$APPCONFIG_NAME" \
    --key "ai:gpt-4.1-mini:endpoint" \
    --value "https://YOUR-AI-FOUNDRY.openai.azure.com/openai/deployments/gpt-4.1-mini/chat/completions?api-version=2025-01-01-preview" \
    --label production \
    --yes

az appconfig kv set \
    -n "$APPCONFIG_NAME" \
    --key "ai:gpt-4.1-mini:rpm" \
    --value "2700" \
    --label production \
    --yes

az appconfig kv set \
    -n "$APPCONFIG_NAME" \
    --key "ai:gpt-4.1-mini:tpm" \
    --value "450000" \
    --label production \
    --yes
```

### Update API Key in Key Vault

```bash
KEYVAULT_NAME=$(jq -r '.keyVaultName.value' deployment-outputs.json)

az keyvault secret set \
    --vault-name "$KEYVAULT_NAME" \
    --name "AI-FOUNDRY-API-KEY" \
    --value "YOUR_ACTUAL_API_KEY"
```

---

## Phase 4: ML Models Setup

Download HuggingFace models and mount to Azure Files. See [ML_MODELS_SETUP.md](./ML_MODELS_SETUP.md) for detailed instructions.

### Required Models

| Model                                  | Size    | Purpose                   |
| -------------------------------------- | ------- | ------------------------- |
| BAAI/bge-large-en-v1.5                 | ~1.3 GB | FastEmbed text embeddings |
| sentence-transformers/all-MiniLM-L6-v2 | ~90 MB  | Sentence similarity       |

### Upload to Azure Files

```bash
STORAGE_ACCOUNT=$(jq -r '.storageAccountName.value' deployment-outputs.json)

# Upload models to Azure Files share
az storage file upload-batch \
    --account-name "$STORAGE_ACCOUNT" \
    --destination ml-models \
    --source ./downloaded-models \
    --auth-mode login
```

---

## Phase 5: Connect to AKS

Before importing images or deploying workloads, connect to your AKS cluster.

### 5.1 Install kubectl

```bash
# Install kubectl if not already installed
az aks install-cli
```

### 5.2 Get AKS Credentials

```bash
AKS_NAME=$(jq -r '.aksClusterName.value' deployment-outputs.json)
RESOURCE_GROUP=$(jq -r '.resourceGroupName.value' deployment-outputs.json)

az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$AKS_NAME"
```

> **WSL users**: The Windows `az` CLI writes kubeconfig to Windows paths. Fix with:
> ```bash
> az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$AKS_NAME" --file "C:\Users\$USER\.kube\config" --overwrite-existing
> export KUBECONFIG=/mnt/c/Users/$USER/.kube/config
> ```

### 5.3 Verify Connection

The AKS cluster has a **private API server** - it's only accessible from within the Azure VNet.

**Option A: Use `az aks command invoke`** (recommended for initial setup):
```bash
az aks command invoke \
    --resource-group "$RESOURCE_GROUP" \
    --name "$AKS_NAME" \
    --command "kubectl get nodes"
```

**Option B: Use Azure Cloud Shell** - Has private endpoint access via Azure backbone.

**Option C: Connect via VPN/Bastion** - If your organization has VPN access to the Azure VNet.

You should see your AKS nodes listed:
```
NAME                                STATUS   ROLES    AGE   VERSION
aks-system-12345678-vmss000000      Ready    <none>   1h    v1.30.x
```

---

## Phase 6: Container Image Import

Import QWiser container images into your ACR. See [IMAGE_IMPORT_GUIDE.md](./IMAGE_IMPORT_GUIDE.md) for detailed instructions.

### 6.1 Import Images

```bash
ACR_NAME=$(jq -r '.acrLoginServer.value' deployment-outputs.json | cut -d'.' -f1)

# Use the import script with credentials from QWiser
./scripts/import-images.sh \
    --source-user "customer-youruni-pull" \
    --source-password "<provided-by-qwiser>" \
    --target-acr $ACR_NAME
```

### 6.2 Verify Import

```bash
az acr repository list --name $ACR_NAME -o table
```

### 6.3 Verify AKS Can Pull Images

```bash
# Test that AKS can pull from your ACR (If you have VPN access to the cluster. Otherwise use invoke as shown in IMAGE_IMPORT_GUIDE.md)
kubectl run test-pull --image=$ACR_NAME.azurecr.io/qwiser/public-api:v0.0.2 --restart=Never --command -- sleep 10
kubectl get pod test-pull  # Should be Running, not ImagePullBackOff
kubectl delete pod test-pull
```

If pull fails with `ImagePullBackOff`, verify ACR attachment:
```bash
az aks check-acr --resource-group "$RESOURCE_GROUP" --name "$AKS_NAME" --acr $ACR_NAME.azurecr.io
```

---

## Phase 7: Kubernetes Deployment

> **Note**: All kubectl/helm commands below use `az aks command invoke` for private AKS clusters.
> If you have VPN access to the cluster, or the cluster is not private, you can run commands directly.

### 7.1 Install KEDA

```bash
# Add Helm repos locally (runs on your machine)
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

# Install KEDA via az aks command invoke
az aks command invoke -g $RESOURCE_GROUP -n $AKS_NAME \
    --command "helm repo add kedacore https://kedacore.github.io/charts && helm repo update && helm install keda kedacore/keda --namespace keda --create-namespace --version 2.16.1"
```

**Verification**:
```bash
az aks command invoke -g $RESOURCE_GROUP -n $AKS_NAME \
    --command "kubectl get pods -n keda"
```

### 7.2 Install Qdrant

```bash
KEYVAULT_NAME=$(jq -r '.keyVaultName.value' deployment-outputs.json)

# Get Qdrant API key from Key Vault
QDRANT_API_KEY=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "QDRANT-API-KEY" --query "value" -o tsv)

# Create secret and install Qdrant
az aks command invoke -g $RESOURCE_GROUP -n $AKS_NAME \
    --command "kubectl create secret generic qdrant-apikey --from-literal=api-key='$QDRANT_API_KEY' --dry-run=client -o yaml | kubectl apply -f - && \
               helm repo add qdrant https://qdrant.github.io/qdrant-helm && \
               helm repo update && \
               helm install qdrant qdrant/qdrant --namespace qdrant --create-namespace -f qdrant-values.yaml" \
    --file k8s/base/qdrant-values.yaml
```

**Verification**:
```bash
az aks command invoke -g $RESOURCE_GROUP -n $AKS_NAME \
    --command "kubectl get pods -n qdrant && kubectl get pvc -n qdrant"
```

### 7.3 Apply QWiser Manifests

```bash
cd k8s/base

# For private AKS:
./scripts/apply.sh --invoke -g $RESOURCE_GROUP -n $AKS_NAME

# Or preview what will be applied:
./scripts/apply.sh --invoke -g $RESOURCE_GROUP -n $AKS_NAME --dry-run
```

**Verification**:
```bash
az aks command invoke -g $RESOURCE_GROUP -n $AKS_NAME \
    --command "kubectl get pods && kubectl get deployments && kubectl get ingress"
```

---

## Phase 8: DNS & Front Door Configuration

### 8.1 Get Front Door Hostname

```bash
FRONTDOOR_HOSTNAME=$(jq -r '.frontDoorHostname.value' deployment-outputs.json)
RESOURCE_GROUP=$(jq -r '.resourceGroupName.value' deployment-outputs.json)
FRONTDOOR_NAME=$(jq -r '.frontDoorName.value' deployment-outputs.json)

echo "Front Door hostname: $FRONTDOOR_HOSTNAME"
```

### 8.2 Create DNS CNAME Record

In your DNS provider, create a CNAME record:

```
qwiser.myuniversity.edu  CNAME  <frontdoor-hostname>.azurefd.net
```

### 8.3 Add Custom Domain to Front Door

```bash
az afd custom-domain create \
    --resource-group "$RESOURCE_GROUP" \
    --profile-name "$FRONTDOOR_NAME" \
    --custom-domain-name "qwiser-custom" \
    --host-name "qwiser.myuniversity.edu" \
    --certificate-type ManagedCertificate \
    --minimum-tls-version TLS12
```

### 8.4 Validate Domain Ownership

Get the validation token:

```bash
az afd custom-domain show \
    --resource-group "$RESOURCE_GROUP" \
    --profile-name "$FRONTDOOR_NAME" \
    --custom-domain-name "qwiser-custom" \
    --query "validationProperties.validationToken" -o tsv
```

Create a TXT record in your DNS provider:

```
_dnsauth.qwiser.myuniversity.edu  TXT  <validation-token>
```

Wait for validation (can take a few minutes after DNS propagates):

```bash
az afd custom-domain show \
    --resource-group "$RESOURCE_GROUP" \
    --profile-name "$FRONTDOOR_NAME" \
    --custom-domain-name "qwiser-custom" \
    --query "validationProperties.validationState" -o tsv
```

Proceed when validation state is `Approved`.

### 8.5 Associate Domain with Route

```bash
ENDPOINT_NAME=$(jq -r '.frontDoorEndpointName.value' deployment-outputs.json)

az afd route update \
    --resource-group "$RESOURCE_GROUP" \
    --profile-name "$FRONTDOOR_NAME" \
    --endpoint-name "$ENDPOINT_NAME" \
    --route-name "default-route" \
    --custom-domains "qwiser-custom"
```

### 8.6 Verify Certificate Provisioning

Certificate provisioning takes 5-15 minutes after domain validation:

```bash
az afd custom-domain show \
    --resource-group "$RESOURCE_GROUP" \
    --profile-name "$FRONTDOOR_NAME" \
    --custom-domain-name "qwiser-custom" \
    --query "{domain: hostName, validation: validationProperties.validationState, certificate: tlsSettings.certificateType}"
```

---

## Phase 9: Verification

> **Note**: All commands use `az aks command invoke` for private AKS.

### 9.1 Check All Pods Running

```bash
az aks command invoke -g $RESOURCE_GROUP -n $AKS_NAME \
    --command "kubectl get pods --all-namespaces | grep -E '^(default|keda|qdrant|ingress-nginx)'"
```

Expected: All pods should be in `Running` state.

### 9.2 Verify Health Endpoints

```bash
# Via Front Door (external) - this is the primary test
curl https://qwiser.myuniversity.edu/ready
```

Expected response: `{"status": "ready"}`

### 9.3 Verify Database Connection

```bash
az aks command invoke -g $RESOURCE_GROUP -n $AKS_NAME \
    --command "kubectl exec deployment/internal-db -- python -c \"
from sqlalchemy import create_engine, text
import os
engine = create_engine(os.environ['DATABASE_URL'])
with engine.connect() as conn:
    result = conn.execute(text('SELECT 1'))
    print('Database: OK')
\""
```

### 9.4 Verify Redis Connection

```bash
az aks command invoke -g $RESOURCE_GROUP -n $AKS_NAME \
    --command "kubectl exec deployment/public-api -- python -c \"
import asyncio
from QWiserCommons.redis import AsyncRedisConnector
async def test():
    client = await AsyncRedisConnector.get_instance()
    print('PING:', await client.ping())
asyncio.run(test())
\""
```

### 9.5 Verify AI Models

```bash
az aks command invoke -g $RESOURCE_GROUP -n $AKS_NAME \
    --command "kubectl exec deployment/other-generation -- python -c \"
from QWiserCommons.config import Config
import asyncio
async def test():
    await Config.load()
    ai_config = Config.get_ai_config('gpt-4.1-mini')
    print(f'Endpoint: {ai_config.endpoint[:50]}...')
    print(f'RPM: {ai_config.rpm}')
asyncio.run(test())
\""
```

---

## Troubleshooting

### Common Issues

| Issue                                 | Cause                            | Solution                                                 |
| ------------------------------------- | -------------------------------- | -------------------------------------------------------- |
| kubectl: `localhost:8080 refused`     | Kubeconfig not found/loaded      | WSL: `export KUBECONFIG=/mnt/c/Users/$USER/.kube/config` |
| kubectl: `no such host` (privatelink) | Private AKS, can't resolve DNS   | Use `az aks command invoke` or Cloud Shell               |
| Pods stuck in `Pending`               | Node pool not ready              | Check node pools: `kubectl get nodes`                    |
| `ImagePullBackOff`                    | ACR auth or image not found      | Verify ACR import and AKS-ACR attachment                 |
| Database connection refused           | Private endpoint issue           | Check MySQL private endpoint status                      |
| Redis auth failed                     | Workload Identity not configured | Verify federated credentials                             |
| Config not loading                    | App Config network access        | Use Cloud Shell or enable public access                  |

### Diagnostic Commands

```bash
# Pod logs
az aks command invoke -g $RESOURCE_GROUP -n $AKS_NAME \
    --command "kubectl logs deployment/public-api"

# Describe pod (events)
az aks command invoke -g $RESOURCE_GROUP -n $AKS_NAME \
    --command "kubectl describe pod <pod-name>"

# Check node status
az aks command invoke -g $RESOURCE_GROUP -n $AKS_NAME \
    --command "kubectl get nodes -o wide"

# Check PVCs
az aks command invoke -g $RESOURCE_GROUP -n $AKS_NAME \
    --command "kubectl get pvc --all-namespaces"

# Check ingress
az aks command invoke -g $RESOURCE_GROUP -n $AKS_NAME \
    --command "kubectl describe ingress qwiser-ingress"
```

### Support

If issues persist:
1. Collect diagnostic logs:
   ```bash
   az aks command invoke -g $RESOURCE_GROUP -n $AKS_NAME \
       --command "kubectl logs --all-containers -l app.kubernetes.io/part-of=qwiser-on-prem"
   ```
2. Check Azure resource health in Portal
3. Contact QWiser support with deployment outputs and logs

---

## Cleanup

### Redeploying After Failure

If deployment fails mid-way (wrong SKU, quota issues, etc.), use the **Redeploy** button in Azure Portal.

> **Important**: Azure Portal may reset some inputs to defaults in the redeploy menu. Verify all parameters match your original choices before redeploying.

### Full Cleanup (Start Fresh)

If you need to delete everything and start over:

```bash
# 1. Delete the main resource group
az group delete --name qwiser-prod-rg --yes

# 2. Delete the MC_ resource group (AKS node resources)
az group delete --name MC_qwiser-prod-rg_qwiser-prod-aks_eastus --yes
```

**Wait 15-20 minutes** for both resource groups to fully delete before redeploying.

### App Configuration Soft-Delete

App Configuration has soft-delete enabled. After deleting the resource group:

**If `enablePurgeProtection` was `true` (default):**
- Cannot reuse the same name for 7 days
- Either wait 7 days, or change `namePrefix`/`environmentName` for redeployment

**If `enablePurgeProtection` was `false`:**
```bash
# Purge immediately and reuse the same name
az appconfig purge --name qwiser-prod-appconfig --location eastus --yes
```

> **Tip**: For test/dev deployments, set `enablePurgeProtection: false` to simplify cleanup.

---

## Next Steps

After successful deployment:

1. **Configure LTI and test** - See [POST_DEPLOYMENT.md](./POST_DEPLOYMENT.md)
2. **Plan secret rotation** - See [SECRET_ROTATION.md](./SECRET_ROTATION.md)
