# QWiser University - Deployment Guide

---

## Table of Contents

1. [Prerequisites Checklist](#prerequisites-checklist)
2. [Deployment Overview](#deployment-overview)
3. [Phase 1: Infrastructure Deployment](#phase-1-infrastructure-deployment)
4. [Phase 2: Post-Deployment Configuration](#phase-2-post-deployment-configuration)
5. [Phase 3: AI Models Setup](#phase-3-ai-models-setup)
6. [Phase 4: ML Models Setup](#phase-4-ml-models-setup)
7. [Phase 5: Connect to AKS](#phase-5-connect-to-aks)
8. [Phase 6: Container Image Import](#phase-6-container-image-import)
9. [Phase 7: Kubernetes Deployment](#phase-7-kubernetes-deployment)
10. [Phase 8: DNS & Front Door Configuration](#phase-8-dns--front-door-configuration)
11. [Phase 9: Verification](#phase-9-verification)
12. [Phase 10: Performance Tuning](#phase-10-performance-tuning)
13. [Troubleshooting](#troubleshooting)
14. [Cleanup](#cleanup)

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

Deploy AI models in Azure AI Foundry

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

See [APPCONFIG_REFERENCE.md](./APPCONFIG_REFERENCE.md) for the full list of configuration options.

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

> **Note**: You can skip this step if you are not using the ML models (chat functionality). This step is **still untested** and is provided as a scaffold for future reference. QWiser is expected to migrate to an Azure AI Search based chat functionality which will not require the ML models.

### Required Models

| Model                                  |
| -------------------------------------- |
| philipchung/bge-m3-onnx                |
| sentence-transformers/all-MiniLM-L6-v2 |
| jinaai/jina-colbert-v2                 |

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

### 7.1 Enable VPA (Vertical Pod Autoscaler)

VPA collects resource usage metrics and provides recommendations for CPU/memory requests. QWiser uses VPA in **recommendation-only mode** (`updateMode: Off`) - it won't modify pods automatically. KEDA handles actual autoscaling. VPA recommendations help with capacity planning and tuning; see [Phase 10: Performance Tuning](#phase-10-performance-tuning) for how to use them.

```bash
AKS_NAME=$(jq -r '.aksClusterName.value' deployment-outputs.json)
RESOURCE_GROUP=$(jq -r '.resourceGroupName.value' deployment-outputs.json)

# Enable VPA addon on existing cluster
az aks update \
    --resource-group "$RESOURCE_GROUP" \
    --name "$AKS_NAME" \
    --enable-vpa
```

> **Note**: This may take a few minutes. The command runs against the AKS control plane, not inside the cluster.

**Verification**:
```bash
az aks command invoke -g $RESOURCE_GROUP -n $AKS_NAME \
    --command "kubectl get pods -n kube-system | grep vpa"
```

Expected output shows VPA pods running:
```
vpa-admission-controller-xxxxx   1/1     Running   0          2m
vpa-recommender-xxxxx            1/1     Running   0          2m
vpa-updater-xxxxx                1/1     Running   0          2m
```

### 7.2 Install KEDA

KEDA (Kubernetes Event-Driven Autoscaling) enables autoscaling based on resource utilization andexternal metrics like queue length. AKS has a built-in KEDA addon.

```bash
# Enable KEDA addon on existing cluster
az aks update \
    --resource-group "$RESOURCE_GROUP" \
    --name "$AKS_NAME" \
    --enable-keda
```

> **Note**: This may take a few minutes. The KEDA version installed depends on your AKS Kubernetes version.

**Verification**:
```bash
# Check KEDA is enabled
az aks show -g $RESOURCE_GROUP -n $AKS_NAME \
    --query "workloadAutoScalerProfile.keda.enabled"

# Check KEDA pods are running
az aks command invoke -g $RESOURCE_GROUP -n $AKS_NAME \
    --command "kubectl get pods -n kube-system | grep keda"
```

Expected output shows KEDA pods running:
```
keda-admission-webhooks-xxxxx    1/1     Running   0          2m
keda-operator-xxxxx              1/1     Running   0          2m
keda-operator-metrics-xxxxx      1/1     Running   0          2m
```

### 7.3 Install Qdrant - Skip if you are not using the chat functionality. 

> **Note**: This step is **still untested** and is provided as a scaffold for future reference. QWiser is expected to migrate to an Azure AI Search based chat functionality which will not require Qdrant.

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

### 7.4 Apply QWiser Manifests

```bash
# For private AKS (recommended):
./scripts/apply.sh --invoke -g $RESOURCE_GROUP -n $AKS_NAME

# Or with direct kubectl access (requires VPN):
./scripts/apply.sh

# Preview what will be applied (dry run):
./scripts/apply.sh --invoke -g $RESOURCE_GROUP -n $AKS_NAME --dry-run
```

### 7.5 Verify Deployment

After `apply.sh` completes, verify all pods are running:

**Via `az aks command invoke`** (for private AKS):
```bash
# Check all pods are Running
az aks command invoke -g $RESOURCE_GROUP -n $AKS_NAME \
    --command "kubectl get pods -n default"

# Check deployments are ready
az aks command invoke -g $RESOURCE_GROUP -n $AKS_NAME \
    --command "kubectl get deployments -n default"

# Check ingress is configured
az aks command invoke -g $RESOURCE_GROUP -n $AKS_NAME \
    --command "kubectl get ingress -n default"
```

**With direct kubectl** (if VPN connected):
```bash
kubectl get pods -l app.kubernetes.io/part-of=qwiser-on-prem
kubectl get deployments
kubectl get ingress
```

Expected pod status - all should show `Running` (or `Completed` for jobs):
```
NAME                                READY   STATUS    RESTARTS   AGE
frontend-xxxxx                      1/1     Running   0          2m
internal-db-xxxxx                   1/1     Running   0          2m
other-generation-xxxxx              1/1     Running   0          2m
public-api-xxxxx                    1/1     Running   0          2m
smart-quiz-xxxxx                    1/1     Running   0          2m
text-loading-xxxxx                  1/1     Running   0          2m
topic-modeling-xxxxx                1/1     Running   0          2m
```

If any pods show `ImagePullBackOff` or `ErrImagePull`, see [Troubleshooting](#troubleshooting).

---

## Phase 8: DNS Configuration

The Bicep deployment already created the custom domain in Front Door and associated it with the route. You just need to configure DNS records for validation and routing.

### 8.1 Get Configuration Values

```bash
FRONTDOOR_HOSTNAME=$(jq -r '.frontDoorHostname.value' deployment-outputs.json | tr -d '\r')
RESOURCE_GROUP=$(jq -r '.resourceGroupName.value' deployment-outputs.json | tr -d '\r')
FRONTDOOR_NAME=$(jq -r '.frontDoorName.value' deployment-outputs.json | tr -d '\r')
CUSTOM_DOMAIN_NAME=$(jq -r '.customDomainName.value' deployment-outputs.json | tr -d '\r')

echo "Front Door hostname: $FRONTDOOR_HOSTNAME"
echo "Front Door name: $FRONTDOOR_NAME"
echo "Custom domain name: $CUSTOM_DOMAIN_NAME"
```

### 8.2 Create DNS CNAME Record

In your DNS provider, create a CNAME record pointing your custom domain to Front Door:

```
qwiser.myuniversity.edu  CNAME  <frontdoor-hostname>
```

**If using Azure DNS Zone:**

```bash
# Replace with your DNS zone resource group and zone name
DNS_ZONE_RG="your-dns-zone-resource-group"
DNS_ZONE_NAME="myuniversity.edu"

az network dns record-set cname set-record \
    --resource-group "$DNS_ZONE_RG" \
    --zone-name "$DNS_ZONE_NAME" \
    --record-set-name "qwiser" \
    --cname "$FRONTDOOR_HOSTNAME"

# Verify the record
nslookup qwiser.$DNS_ZONE_NAME
```

### 8.3 Create DNS TXT Record for Validation

Get the validation token:

```bash
VALIDATION_TOKEN=$(az afd custom-domain show \
    --resource-group "$RESOURCE_GROUP" \
    --profile-name "$FRONTDOOR_NAME" \
    --custom-domain-name "$CUSTOM_DOMAIN_NAME" \
    --query "validationProperties.validationToken" -o tsv | tr -d '\r')

echo "Validation token: $VALIDATION_TOKEN"
```

Create a TXT record in your DNS provider:

```
_dnsauth.qwiser.myuniversity.edu  TXT  <validation-token>
```

**If using Azure DNS Zone:**

```bash
az network dns record-set txt add-record \
    --resource-group "$DNS_ZONE_RG" \
    --zone-name "$DNS_ZONE_NAME" \
    --record-set-name "_dnsauth.qwiser" \
    --value "$VALIDATION_TOKEN"

# Verify the record was created correctly
az network dns record-set txt show \
    --resource-group "$DNS_ZONE_RG" \
    --zone-name "$DNS_ZONE_NAME" \
    --name "_dnsauth.qwiser" \
    --query "txtRecords[0].value[0]" -o tsv
```

### 8.4 Wait for Validation and Certificate Provisioning

Front Door's validation polling slows down over time. Trigger an immediate re-check by sending an update request:

```bash
az afd custom-domain update \
    --resource-group "$RESOURCE_GROUP" \
    --profile-name "$FRONTDOOR_NAME" \
    --custom-domain-name "$CUSTOM_DOMAIN_NAME" \
    --minimum-tls-version TLS12
```

Certificate provisioning takes 5-15 minutes after DNS records propagate:

```bash
# Check validation and certificate status
az afd custom-domain show \
    --resource-group "$RESOURCE_GROUP" \
    --profile-name "$FRONTDOOR_NAME" \
    --custom-domain-name "$CUSTOM_DOMAIN_NAME" \
    --query "{domain: hostName, validation: domainValidationState, provisioning: provisioningState, certificate: tlsSettings.certificateType}" -o table
```

Wait until:
- `deploymentStatus` = `Succeeded`
- `domainValidationState` = `Approved`
- `provisioningState` = `Succeeded`

---

## Phase 9: Verification

### 9.1 Check All Pods Running

```bash
az aks command invoke -g $RESOURCE_GROUP -n $AKS_NAME \
    --command "kubectl get pods -n default"
```

Expected: All pods should be in `Running` state with `1/1` Ready.

> **Note**: If pods are Running, database and Redis connections are already verified - the services won't start without them.

### 9.2 Verify External Access

```bash
# Via Front Door (external) - this is the primary test
curl https://qwiser.myuniversity.edu/ready
```

Expected response: HTTP 200

### 9.3 Configure LTI Integration

Now configure LTI to enable single sign-on from your LMS (Moodle, Canvas, etc.):

**See [LTI_INTEGRATION.md](./LTI_INTEGRATION.md)** for complete instructions.

### 9.4 Application Tests

Verify core functionality works end-to-end:

| Test                | How to Verify                               |
| ------------------- | ------------------------------------------- |
| LTI launch          | Launch from LMS, verify SSO                 |
| Content upload      | Upload a PDF document                       |
| Tree generation     | Create knowledge tree from uploaded content |
| Question generation | Generate questions from tree                |
| Chat functionality  | Start a chat session with content           |

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

## Phase 10: Performance Tuning

After the system has been running for a few days with real usage, use VPA recommendations to optimize resource allocation.

### 10.1 View VPA Recommendations

VPA analyzes actual resource usage and provides recommendations for CPU and memory requests:

```bash
# View all VPA recommendations
az aks command invoke -g $RESOURCE_GROUP -n $AKS_NAME \
    --command "kubectl get vpa -o custom-columns='NAME:.metadata.name,CPU-REQ:.status.recommendation.containerRecommendations[0].target.cpu,MEM-REQ:.status.recommendation.containerRecommendations[0].target.memory'"
```

For detailed recommendations including lower/upper bounds:
```bash
az aks command invoke -g $RESOURCE_GROUP -n $AKS_NAME \
    --command "kubectl describe vpa public-api-vpa"
```

Example output:
```
Recommendation:
  Container Recommendations:
    Container Name:  public-api
    Lower Bound:
      Cpu:     250m
      Memory:  384Mi
    Target:
      Cpu:     500m
      Memory:  512Mi
    Upper Bound:
      Cpu:     1
      Memory:  1Gi
```

### 10.2 Adjust Resource Requests

If VPA recommendations differ significantly from current settings, update the deployment manifests.

**Option A: Edit manifests directly**

Edit the resource requests in `k8s/base/deployments/*.yaml`:

```yaml
resources:
  requests:
    cpu: "500m"      # Update based on VPA target
    memory: "512Mi"  # Update based on VPA target
  limits:
    cpu: "1000m"
    memory: "1Gi"
```

Then re-apply:
```bash
./scripts/apply.sh --invoke -g $RESOURCE_GROUP -n $AKS_NAME
```

**Option B: Patch specific deployments**

For quick adjustments without modifying files:
```bash
az aks command invoke -g $RESOURCE_GROUP -n $AKS_NAME \
    --command "kubectl set resources deployment/public-api --requests=cpu=500m,memory=512Mi --limits=cpu=1000m,memory=1Gi"
```

### 10.3 Adjust Replica Counts

KEDA handles autoscaling, but you may want to adjust minimum replicas for high-availability or cost optimization.

**View current KEDA ScaledObjects:**
```bash
az aks command invoke -g $RESOURCE_GROUP -n $AKS_NAME \
    --command "kubectl get scaledobjects -o custom-columns='NAME:.metadata.name,MIN:.spec.minReplicaCount,MAX:.spec.maxReplicaCount,CURRENT:.status.scaleTargetRef.deploymentSize'"
```

**Adjust min/max replicas:**

Edit `k8s/base/keda/*.yaml` and update:
```yaml
spec:
  minReplicaCount: 2   # Minimum pods (for HA)
  maxReplicaCount: 10  # Maximum pods (cost control)
```

Then re-apply manifests.

### 10.4 Monitor Resource Usage

Track resource utilization over time:

```bash
# Current resource usage vs requests
az aks command invoke -g $RESOURCE_GROUP -n $AKS_NAME \
    --command "kubectl top pods -l app.kubernetes.io/part-of=qwiser-on-prem"

# Node-level utilization
az aks command invoke -g $RESOURCE_GROUP -n $AKS_NAME \
    --command "kubectl top nodes"
```

### 10.5 Recommended Review Schedule

| Timeframe | Action                                                       |
| --------- | ------------------------------------------------------------ |
| Day 1-3   | Monitor for crashes, OOMKills, throttling                    |
| Week 1    | Review VPA recommendations, adjust obvious misconfigurations |
| Month 1   | Fine-tune based on actual usage patterns                     |
| Quarterly | Review and optimize for cost/performance balance             |

---

## Next Steps

After successful deployment:

1. **Configure LTI** - See [LTI_INTEGRATION.md](./LTI_INTEGRATION.md)
2. **Plan secret rotation** - See [SECRET_ROTATION.md](./SECRET_ROTATION.md)
3. **Performance tuning** - See [Phase 10](#phase-10-performance-tuning) after system has real usage data
