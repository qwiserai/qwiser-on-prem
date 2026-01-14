# QWiser University - Container Image Import Guide

> **Last Updated**: 2026-01-14
> **Version**: 1.0.0
> **Audience**: University IT Infrastructure Teams

---

## Overview

QWiser container images must be imported from QWiser's Azure Container Registry (ACR) into your ACR before Kubernetes deployment. QWiser provides you with pull-only credentials for this purpose.

---

## Prerequisites

- [ ] ACR deployed (from Bicep deployment)
- [ ] Azure CLI installed and logged in (`az login`)
- [ ] QWiser ACR credentials (username and password provided by QWiser)
- [ ] AKS cluster attached to ACR (configured automatically by Bicep)

---

## Required Images

See [VERSIONS.txt](../VERSIONS.txt) for the current release. The images are:

| Image | Purpose |
|-------|---------|
| `qwiser/public-api` | API Gateway, authentication, ID masking |
| `qwiser/internal-db` | Database API layer |
| `qwiser/text-loading` | Content ingestion (PDFs, YouTube, etc.) |
| `qwiser/other-generation` | AI content generation |
| `qwiser/topic-modeling` | Knowledge tree coordinator |
| `qwiser/smart-quiz` | Quiz and exam engine |
| `qwiser/embeddings-worker` | GPU/CPU embeddings (largest image, ~2.5GB) |
| `qwiser/frontend` | React web application |
| `qwiser/cronjobs` | Scheduled maintenance tasks |

---

## Import Process

### Step 1: Get Your ACR Name

Find your ACR name from the Bicep deployment output:

```bash
# From deployment output
ACR_NAME=$(az deployment sub show \
    --name qwiser-university-YYYYMMDD-HHMMSS \
    --query "properties.outputs.acrLoginServer.value" -o tsv | cut -d'.' -f1 | tr -d '\r')

echo "Your ACR: $ACR_NAME"
```

Or find it in the Azure Portal under your resource group.

### Step 2: Run the Import Script

Use the provided import script with credentials from QWiser:

**Linux/macOS (Bash):**

```bash
cd scripts

# Option A: Using environment variables
export QWISER_ACR_USERNAME="customer-youruni-pull"
export QWISER_ACR_PASSWORD="<provided-by-qwiser>"
./import-images.sh --target-acr $ACR_NAME

# Option B: Using command line arguments
./import-images.sh \
    --source-user "customer-youruni-pull" \
    --source-password "<provided-by-qwiser>" \
    --target-acr $ACR_NAME
```

**Windows (PowerShell):**

```powershell
cd scripts

# Option A: Using environment variables
$env:QWISER_ACR_USERNAME = "customer-youruni-pull"
$env:QWISER_ACR_PASSWORD = "<provided-by-qwiser>"
.\import-images.ps1 -TargetAcr $ACR_NAME

# Option B: Using parameters
.\import-images.ps1 `
    -SourceUser "customer-youruni-pull" `
    -SourcePassword "<provided-by-qwiser>" `
    -TargetAcr $ACR_NAME
```

**Dry run (see what would happen without importing):**

```bash
./import-images.sh --target-acr $ACR_NAME --dry-run
```

### Step 3: Verify Import

```bash
# List all repositories
az acr repository list --name $ACR_NAME -o table
```

Expected output:
```
Result
------------------------
qwiser/cronjobs
qwiser/embeddings-worker
qwiser/frontend
qwiser/internal-db
qwiser/other-generation
qwiser/public-api
qwiser/smart-quiz
qwiser/text-loading
qwiser/topic-modeling
```

Verify tags for a specific image:
```bash
az acr repository show-tags --name $ACR_NAME --repository qwiser/public-api -o table
```

---

## Verify AKS Can Pull Images

The Bicep deployment automatically attaches AKS to ACR. Verify with a test pull:

```bash
# Test pull
kubectl run test-pull --image=$ACR_NAME.azurecr.io/qwiser/public-api:v1.0.0 --command -- sleep 10

# Check pod status (should be Running, not ImagePullBackOff)
kubectl get pod test-pull

# Cleanup
kubectl delete pod test-pull
```

If pull fails with `ImagePullBackOff`:

```bash
# Verify ACR attachment
az aks check-acr \
    --resource-group <your-resource-group> \
    --name <your-aks-name> \
    --acr $ACR_NAME.azurecr.io
```

---

## Image Tags in K8s Manifests

The K8s manifests use placeholder values that `apply.sh` replaces:

```yaml
# In manifests (before apply.sh):
image: REPLACE_WITH_ACR_LOGIN_SERVER/qwiser/public-api:PLACEHOLDER

# After apply.sh substitution:
image: youruni-acr.azurecr.io/qwiser/public-api:v1.0.0
```

Image versions are centralized in `k8s/base/kustomization.yaml` under the `images:` section.

---

## Updating to a New Version

When QWiser releases a new version:

### Step 1: Update VERSIONS.txt

QWiser will provide an updated `VERSIONS.txt` with new tags.

### Step 2: Re-run Import Script

```bash
./import-images.sh --target-acr $ACR_NAME
```

The `--force` flag (used internally) overwrites existing tags if they exist.

### Step 3: Update kustomization.yaml

Edit `k8s/base/kustomization.yaml` to use the new tags:

```yaml
images:
  - name: REPLACE_WITH_ACR_LOGIN_SERVER/qwiser/public-api
    newTag: v1.1.0  # Updated
  # ... update all images
```

### Step 4: Apply Updates

```bash
cd k8s/base
./apply.sh
```

Or trigger a rolling update for specific services:

```bash
kubectl rollout restart deployment/public-api -n qwiser
```

---

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| `401 Unauthorized` | Invalid or expired credentials | Contact QWiser for new credentials |
| `404 Not Found` | Image or tag doesn't exist | Verify VERSIONS.txt matches available images |
| `ImagePullBackOff` in K8s | ACR not attached to AKS | Run `az aks check-acr` |
| Slow import | Large images (embeddings-worker is ~2.5GB) | Wait patiently, or use dedicated bandwidth |

### View Import Logs

If import fails, check detailed error:

```bash
# Azure CLI shows errors inline during import
# For more detail, check ACR tasks:
az acr task logs --registry $ACR_NAME
```

### List Tags for an Image

```bash
az acr repository show-tags --name $ACR_NAME --repository qwiser/public-api -o table
```

---

## Security Notes

- Your credentials are **pull-only** - you cannot push images to QWiser's ACR
- Credentials are scoped to release images only - debug images are not accessible
- Store credentials securely - do not commit to version control
- Credentials expire after 1 year - QWiser will provide renewals

---

## Related Documentation

- [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) - Full deployment guide
- [PREREQUISITES.md](./PREREQUISITES.md) - Prerequisites checklist
