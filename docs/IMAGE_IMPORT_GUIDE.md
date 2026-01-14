# QWiser University - Container Image Import Guide

> **Last Updated**: 2026-01-14
> **Version**: 1.0.0
> **Audience**: University IT Infrastructure Teams

---

## Overview

QWiser container images must be imported into your Azure Container Registry (ACR) before Kubernetes deployment. This guide covers the import process.

---

## Prerequisites

- [ ] ACR deployed (from Bicep deployment)
- [ ] Azure CLI with ACR extension
- [ ] Access to source registry (QWiser ACR or export files)
- [ ] AKS cluster attached to ACR (configured by Bicep)

---

## Required Images

| Image | Version | Size (approx) | Purpose |
|-------|---------|---------------|---------|
| qwiser/public-api | v0.1.0 | ~500 MB | API Gateway |
| qwiser/internal-db | v0.1.0 | ~400 MB | Database API |
| qwiser/text-loading | v0.1.0 | ~600 MB | Content processing |
| qwiser/other-generation | v0.1.0 | ~450 MB | AI generation |
| qwiser/topic-modeling | v0.1.0 | ~800 MB | Knowledge tree coordinator |
| qwiser/smart-quiz | v0.1.0 | ~400 MB | Quiz engine |
| qwiser/embeddings-worker | v0.1.0 | ~2.5 GB | GPU embeddings (CUDA) |
| qwiser/frontend | v0.1.0 | ~100 MB | React frontend |

---

## Import Methods

### Decision Table

| Situation | Recommended Method |
|-----------|-------------------|
| Access to QWiser source ACR | Method A: Direct Import |
| Received .tar export files | Method B: Import from Tarball |
| Building from source | Method C: Build Locally |

---

## Method A: Direct Import from QWiser ACR

Contact QWiser to obtain ACR access credentials.

### Step 1: Get Your ACR Name

```bash
ACR_NAME=$(az deployment sub show \
    --name qwiser-university-YYYYMMDD-HHMMSS \
    --query "properties.outputs.acrLoginServer.value" -o tsv | cut -d'.' -f1)

echo "Your ACR: $ACR_NAME"
```

### Step 2: Import Images

```bash
SOURCE_REGISTRY="qwiser.azurecr.io"
SOURCE_USERNAME="provided-by-qwiser"
SOURCE_PASSWORD="provided-by-qwiser"

# Import all images
for IMAGE in public-api internal-db text-loading other-generation topic-modeling smart-quiz embeddings-worker frontend; do
    echo "Importing $IMAGE..."
    az acr import \
        --name $ACR_NAME \
        --source $SOURCE_REGISTRY/qwiser/$IMAGE:v0.1.0 \
        --image qwiser/$IMAGE:v0.1.0 \
        --username $SOURCE_USERNAME \
        --password $SOURCE_PASSWORD
done
```

### Step 3: Verify Import

```bash
az acr repository list --name $ACR_NAME -o table
```

Expected output:
```
Result
---------------------
qwiser/public-api
qwiser/internal-db
qwiser/text-loading
qwiser/other-generation
qwiser/topic-modeling
qwiser/smart-quiz
qwiser/embeddings-worker
qwiser/frontend
```

---

## Method B: Import from Tarball

If you received exported .tar files:

### Step 1: Login to Your ACR

```bash
az acr login --name $ACR_NAME
```

### Step 2: Load and Push Each Image

```bash
# For each tarball
for TARBALL in *.tar; do
    echo "Loading $TARBALL..."

    # Load image to local Docker
    docker load -i $TARBALL

    # Get the image name from load output
    # (or use consistent naming: qwiser/<service>:v0.1.0)
done

# Tag and push to your ACR
docker tag qwiser/public-api:v0.1.0 $ACR_NAME.azurecr.io/qwiser/public-api:v0.1.0
docker push $ACR_NAME.azurecr.io/qwiser/public-api:v0.1.0

# Repeat for all images
```

### Batch Script

```bash
#!/bin/bash
ACR_NAME="your-acr-name"
ACR_SERVER="$ACR_NAME.azurecr.io"

az acr login --name $ACR_NAME

for TARBALL in *.tar; do
    # Extract service name from tarball (assumes naming: qwiser-<service>-v0.1.0.tar)
    SERVICE=$(echo $TARBALL | sed 's/qwiser-\(.*\)-v.*/\1/')

    echo "Processing $SERVICE..."
    docker load -i $TARBALL
    docker tag qwiser/$SERVICE:v0.1.0 $ACR_SERVER/qwiser/$SERVICE:v0.1.0
    docker push $ACR_SERVER/qwiser/$SERVICE:v0.1.0
done
```

---

## Method C: Build from Source

If you have access to QWiser source code:

### Step 1: Clone Repository

```bash
git clone https://github.com/qwiser/qwiser-university.git
cd qwiser-university
```

### Step 2: Build Images

```bash
ACR_SERVER="$ACR_NAME.azurecr.io"

# Build each service
for SERVICE in public-api internal-db text-loading other-generation topic-modeling smart-quiz embeddings-worker frontend; do
    echo "Building $SERVICE..."
    docker build -t $ACR_SERVER/qwiser/$SERVICE:v0.1.0 ./services/$SERVICE
done
```

### Step 3: Push to ACR

```bash
az acr login --name $ACR_NAME

for SERVICE in public-api internal-db text-loading other-generation topic-modeling smart-quiz embeddings-worker frontend; do
    echo "Pushing $SERVICE..."
    docker push $ACR_SERVER/qwiser/$SERVICE:v0.1.0
done
```

---

## Verify ACR-AKS Integration

The Bicep deployment automatically attaches AKS to ACR. Verify:

```bash
# Check AKS can pull from ACR
kubectl run test-pull --image=$ACR_NAME.azurecr.io/qwiser/public-api:v0.1.0 --command -- sleep 10

# Check pod status
kubectl get pod test-pull

# Cleanup
kubectl delete pod test-pull
```

If pull fails with `ImagePullBackOff`:

```bash
# Verify ACR attachment
az aks check-acr --resource-group qwiser-prod-rg --name qwiser-prod-aks --acr $ACR_NAME.azurecr.io
```

---

## Image Tags in K8s Manifests

The K8s manifests use placeholder tags that are replaced during deployment:

```yaml
# In manifests:
image: REPLACE_WITH_ACR_LOGIN_SERVER/qwiser/public-api:v0.1.0

# After apply.sh substitution:
image: qwiser-prod-acr.azurecr.io/qwiser/public-api:v0.1.0
```

The `apply.sh` script reads `ACR_LOGIN_SERVER` from the qwiser-config ConfigMap and substitutes automatically.

---

## Updating Images

To deploy a new version:

### Step 1: Import New Version

```bash
az acr import \
    --name $ACR_NAME \
    --source $SOURCE_REGISTRY/qwiser/public-api:v0.2.0 \
    --image qwiser/public-api:v0.2.0
```

### Step 2: Update Manifest

Edit the Kustomization or patch to use new tag:

```yaml
# kustomization.yaml
images:
  - name: qwiser/public-api
    newTag: v0.2.0
```

### Step 3: Apply Update

```bash
kubectl apply -k .
```

Or trigger rolling update:

```bash
kubectl set image deployment/public-api public-api=$ACR_NAME.azurecr.io/qwiser/public-api:v0.2.0
```

---

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Import fails with 401 | Invalid credentials | Verify source registry credentials |
| Import fails with 404 | Image doesn't exist | Check exact image name and tag |
| Pull fails in K8s | ACR not attached to AKS | Run `az aks check-acr` |
| Slow import | Large image size | Use regional ACR or dedicated bandwidth |

### Check ACR Logs

```bash
az acr task logs --registry $ACR_NAME --run-id <run-id>
```

### List Tags for an Image

```bash
az acr repository show-tags --name $ACR_NAME --repository qwiser/public-api -o table
```

---

## Image Security Scanning

ACR has built-in vulnerability scanning (via Microsoft Defender):

```bash
# View scan results
az acr vulnerability-assessment show \
    --registry $ACR_NAME \
    --repository qwiser/public-api \
    --name v0.1.0
```

Address HIGH/CRITICAL vulnerabilities before production deployment.

---

## Related Documentation

- [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) - Full deployment guide
- [PREREQUISITES.md](./PREREQUISITES.md) - Prerequisites checklist
