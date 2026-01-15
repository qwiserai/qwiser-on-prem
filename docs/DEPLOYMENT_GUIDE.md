# QWiser University - Deployment Guide

> **Last Updated**: 2026-01-14
> **Version**: 1.0.0
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

---

## Prerequisites Checklist

See [PREREQUISITES.md](./PREREQUISITES.md) for details.

- [ ] QWiser ACR pull credentials
- [ ] Azure subscription with Owner or Contributor + UAA
- [ ] Azure CLI, kubectl, Helm, Git installed

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

If you prefer CLI, see `bicep/main.bicep` and `bicep/main.bicepparam`. If you know what you're doing.

### Capture Outputs

After deployment completes, save the outputs for later phases:

```bash
az deployment sub show \
    --name <your-deployment-name> \
    --query "properties.outputs" \
    -o json > deployment-outputs.json
```

---

## Phase 2: Post-Deployment Configuration

### 2.1 Run Post-Deployment Script

The post-deployment script seeds Key Vault secrets and App Configuration values.

**From Azure Cloud Shell** (recommended for network access):

```bash
cd infrastructure/bicep/scripts

# Get values from deployment outputs
RESOURCE_GROUP="qwiser-prod-rg"
KEYVAULT_NAME=$(az deployment sub show --name qwiser-university-YYYYMMDD-HHMMSS --query "properties.outputs.keyVaultName.value" -o tsv)
APPCONFIG_NAME=$(az deployment sub show --name qwiser-university-YYYYMMDD-HHMMSS --query "properties.outputs.appConfigName.value" -o tsv)
PLS_NAME=$(az deployment sub show --name qwiser-university-YYYYMMDD-HHMMSS --query "properties.outputs.privateLinkServiceName.value" -o tsv)
MYSQL_HOST=$(az deployment sub show --name qwiser-university-YYYYMMDD-HHMMSS --query "properties.outputs.mysqlServerFqdn.value" -o tsv)
REDIS_HOST=$(az deployment sub show --name qwiser-university-YYYYMMDD-HHMMSS --query "properties.outputs.redisHostName.value" -o tsv)
STORAGE_QUEUE_URL="https://$(az deployment sub show --name qwiser-university-YYYYMMDD-HHMMSS --query "properties.outputs.storageAccountName.value" -o tsv).queue.core.windows.net"

# Run post-deployment script
./post-deploy.sh \
    --resource-group "$RESOURCE_GROUP" \
    --keyvault-name "$KEYVAULT_NAME" \
    --appconfig-name "$APPCONFIG_NAME" \
    --pls-name "$PLS_NAME" \
    --mysql-host "$MYSQL_HOST" \
    --redis-host "$REDIS_HOST" \
    --storage-queue-url "$STORAGE_QUEUE_URL" \
    --label production
```

**Verification**:
```bash
# Check Key Vault secrets were created
az keyvault secret list --vault-name "$KEYVAULT_NAME" -o table

# Check App Config keys were created
az appconfig kv list -n "$APPCONFIG_NAME" --label production --top 10 -o table
```

---

## Phase 3: AI Models Setup

Deploy AI models in Azure AI Foundry. See [AI_MODELS_SETUP.md](./AI_MODELS_SETUP.md) for detailed instructions.

### Required Models

| Model | Purpose | Minimum TPM |
|-------|---------|-------------|
| gpt-4.1-mini | Chat name generation, standalone questions | 100K |
| gpt-5.2 | Main generation (questions, chat, trees) | 200K |
| text-embedding-3-large | Vector embeddings | 500K |
| mistral-document-ai | OCR/Document processing | 50K |

### Update App Configuration

After deploying AI models, update the endpoint values:

```bash
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
az keyvault secret set \
    --vault-name "$KEYVAULT_NAME" \
    --name "AI-FOUNDRY-API-KEY" \
    --value "YOUR_ACTUAL_API_KEY"
```

---

## Phase 4: ML Models Setup

Download HuggingFace models and mount to Azure Files. See [ML_MODELS_SETUP.md](./ML_MODELS_SETUP.md) for detailed instructions.

### Required Models

| Model | Size | Purpose |
|-------|------|---------|
| BAAI/bge-large-en-v1.5 | ~1.3 GB | FastEmbed text embeddings |
| sentence-transformers/all-MiniLM-L6-v2 | ~90 MB | Sentence similarity |

### Upload to Azure Files

```bash
STORAGE_ACCOUNT=$(az deployment sub show --name qwiser-university-YYYYMMDD-HHMMSS --query "properties.outputs.storageAccountName.value" -o tsv)

# Upload models to Azure Files share
az storage file upload-batch \
    --account-name "$STORAGE_ACCOUNT" \
    --destination ml-models \
    --source ./downloaded-models \
    --auth-mode login
```

---

## Phase 5: Container Image Import

Import QWiser container images into your ACR. See [IMAGE_IMPORT_GUIDE.md](./IMAGE_IMPORT_GUIDE.md) for detailed instructions.

### Required Images

```bash
ACR_NAME=$(az deployment sub show --name qwiser-university-YYYYMMDD-HHMMSS --query "properties.outputs.acrLoginServer.value" -o tsv | cut -d'.' -f1)

# Import images from source registry
az acr import --name $ACR_NAME --source qwiser.azurecr.io/qwiser/public-api:v0.1.0 --image qwiser/public-api:v0.1.0
az acr import --name $ACR_NAME --source qwiser.azurecr.io/qwiser/internal-db:v0.1.0 --image qwiser/internal-db:v0.1.0
# ... (see IMAGE_IMPORT_GUIDE.md for complete list)
```

**Verification**:
```bash
az acr repository list --name $ACR_NAME -o table
```

---

## Phase 6: Kubernetes Deployment

### 6.1 Get AKS Credentials

```bash
AKS_NAME=$(az deployment sub show --name qwiser-university-YYYYMMDD-HHMMSS --query "properties.outputs.aksClusterName.value" -o tsv)
RESOURCE_GROUP="qwiser-prod-rg"

az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$AKS_NAME"
```

### 6.2 Install KEDA

```bash
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

helm install keda kedacore/keda \
    --namespace keda \
    --create-namespace \
    --version 2.16.1
```

**Verification**:
```bash
kubectl get pods -n keda
```

### 6.3 Install Qdrant

```bash
# Create Qdrant API key secret first
QDRANT_API_KEY=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "QDRANT-API-KEY" --query "value" -o tsv)
kubectl create secret generic qdrant-apikey --from-literal=api-key="$QDRANT_API_KEY"

# Install Qdrant via Helm
helm repo add qdrant https://qdrant.github.io/qdrant-helm
helm repo update

helm install qdrant qdrant/qdrant \
    --namespace qdrant \
    --create-namespace \
    -f k8s-university/k8s/base/qdrant-values.yaml
```

**Verification**:
```bash
kubectl get pods -n qdrant
kubectl get pvc -n qdrant
```

### 6.4 Apply QWiser Manifests

```bash
cd k8s-university/k8s/base
./apply.sh
```

**Verification**:
```bash
kubectl get pods
kubectl get deployments
kubectl get ingress
```

---

## Phase 7: DNS & Front Door Configuration

### 7.1 Create DNS CNAME Record

Get the Front Door hostname:
```bash
FRONTDOOR_HOSTNAME=$(az deployment sub show --name qwiser-university-YYYYMMDD-HHMMSS --query "properties.outputs.frontDoorHostname.value" -o tsv)
echo "Create CNAME record: qwiser.myuniversity.edu -> $FRONTDOOR_HOSTNAME"
```

Create the CNAME record in your DNS provider:
```
qwiser.myuniversity.edu CNAME qwiser-prod-fd-XXXXX.z01.azurefd.net
```

### 7.2 Add Custom Domain to Front Door

```bash
RESOURCE_GROUP="qwiser-prod-rg"
FRONTDOOR_NAME="qwiser-prod-fd"

az afd custom-domain create \
    --resource-group "$RESOURCE_GROUP" \
    --profile-name "$FRONTDOOR_NAME" \
    --custom-domain-name "qwiser-custom" \
    --host-name "qwiser.myuniversity.edu" \
    --certificate-type ManagedCertificate \
    --minimum-tls-version TLS12
```

**Verification**:
```bash
az afd custom-domain show \
    --resource-group "$RESOURCE_GROUP" \
    --profile-name "$FRONTDOOR_NAME" \
    --custom-domain-name "qwiser-custom" \
    --query "{status: validationProperties.validationState, certificate: tlsSettings.certificateType}"
```

---

## Phase 8: Verification

### 8.1 Check All Pods Running

```bash
kubectl get pods --all-namespaces | grep -E "^(default|keda|qdrant|ingress-nginx)"
```

Expected: All pods should be in `Running` state.

### 8.2 Verify Health Endpoints

```bash
# Via kubectl port-forward (internal)
kubectl port-forward svc/public-api 8080:80
curl http://localhost:8080/ready

# Via Front Door (external)
curl https://qwiser.myuniversity.edu/ready
```

Expected response: `{"status": "ready"}`

### 8.3 Verify Database Connection

```bash
kubectl exec -it deployment/internal-db -- python -c "
from sqlalchemy import create_engine, text
import os
engine = create_engine(os.environ['DATABASE_URL'])
with engine.connect() as conn:
    result = conn.execute(text('SELECT 1'))
    print('Database: OK')
"
```

### 8.4 Verify Redis Connection

```bash
kubectl exec -it deployment/public-api -- python -c "
import asyncio
from QWiserCommons.redis import AsyncRedisConnector
async def test():
    client = await AsyncRedisConnector.get_instance()
    print('PING:', await client.ping())
asyncio.run(test())
"
```

### 8.5 Verify AI Models

```bash
# Check endpoint connectivity
kubectl exec -it deployment/other-generation -- python -c "
from QWiserCommons.config import Config
import asyncio
async def test():
    await Config.load()
    ai_config = Config.get_ai_config('gpt-4.1-mini')
    print(f'Endpoint: {ai_config.endpoint[:50]}...')
    print(f'RPM: {ai_config.rpm}')
asyncio.run(test())
"
```

---

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Pods stuck in `Pending` | Node pool not ready or GPU nodes not available | Check node pools: `kubectl get nodes` |
| `ImagePullBackOff` | ACR authentication or image not found | Verify ACR import and AKS-ACR attachment |
| Database connection refused | Private endpoint not configured | Check MySQL private endpoint status |
| Redis auth failed | Workload Identity not configured | Verify federated credentials |
| Config not loading | App Config network access | Use Cloud Shell or VPN |

### Diagnostic Commands

```bash
# Pod logs
kubectl logs deployment/public-api

# Describe pod (events)
kubectl describe pod <pod-name>

# Check node status
kubectl get nodes -o wide

# Check PVCs
kubectl get pvc --all-namespaces

# Check ingress
kubectl describe ingress qwiser-ingress
```

### Support

If issues persist:
1. Collect diagnostic logs: `kubectl logs --all-containers -l app.kubernetes.io/part-of=qwiser-university`
2. Check Azure resource health in Portal
3. Contact QWiser support with deployment outputs and logs

---

## Next Steps

After successful deployment:

1. **Configure LTI** (if using LMS integration) - See [POST_DEPLOYMENT.md](./POST_DEPLOYMENT.md)
2. **Set up monitoring alerts** - Configure Azure Monitor alerts
3. **Plan secret rotation** - See [SECRET_ROTATION.md](./SECRET_ROTATION.md)
4. **Backup configuration** - Export App Config and Key Vault secrets
