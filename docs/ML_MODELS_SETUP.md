# QWiser University - ML Models Setup

> **Last Updated**: 2026-01-14
> **Version**: 1.0.0
> **Audience**: University IT Infrastructure Teams

---

## Overview

QWiser uses local ML models for embedding generation on GPU nodes. These models are pre-downloaded and mounted as a read-only Azure Files share to avoid download time during pod startup.

### Why Pre-Download?

| Without Pre-Download | With Pre-Download |
|---------------------|-------------------|
| 5-10 min cold start per pod | < 30 sec cold start |
| Downloads on every pod restart | Read from shared storage |
| Network bandwidth consumed | No download needed |
| Model version drift risk | Consistent versions |

---

## Prerequisites

- [ ] Azure Storage Account created (from Bicep deployment)
- [ ] Azure Files share `ml-models` exists
- [ ] Network access to storage (Cloud Shell or VPN)
- [ ] Python 3.11+ with pip (for local download)
- [ ] ~3 GB free disk space for model download

---

## Required Models

| Model | Framework | Size | Purpose |
|-------|-----------|------|---------|
| BAAI/bge-large-en-v1.5 | FastEmbed | ~1.3 GB | Primary text embeddings |
| sentence-transformers/all-MiniLM-L6-v2 | Sentence Transformers | ~90 MB | Fallback embeddings |

---

## Step 1: Download Models Locally

### Option A: Using Download Script

```bash
# Create download directory
mkdir -p ./ml-models/{fastembed,huggingface,sentence_transformers}
cd ./ml-models

# Download FastEmbed model
pip install fastembed
python -c "
from fastembed import TextEmbedding
import os
os.environ['FASTEMBED_CACHE_PATH'] = './fastembed'
model = TextEmbedding('BAAI/bge-large-en-v1.5')
print('FastEmbed model downloaded')
"

# Download Sentence Transformers model
pip install sentence-transformers
python -c "
from sentence_transformers import SentenceTransformer
import os
os.environ['SENTENCE_TRANSFORMERS_HOME'] = './sentence_transformers'
model = SentenceTransformer('all-MiniLM-L6-v2')
print('Sentence Transformer model downloaded')
"
```

### Option B: Using HuggingFace CLI

```bash
pip install huggingface_hub

# Download models
huggingface-cli download BAAI/bge-large-en-v1.5 --local-dir ./huggingface/BAAI/bge-large-en-v1.5
huggingface-cli download sentence-transformers/all-MiniLM-L6-v2 --local-dir ./sentence_transformers/all-MiniLM-L6-v2
```

**Verification:**
```bash
du -sh ./ml-models/*
# Expected:
# 1.3G    ./ml-models/fastembed
# 90M     ./ml-models/sentence_transformers
```

---

## Step 2: Upload to Azure Files

### Get Storage Account Details

```bash
# From deployment outputs
STORAGE_ACCOUNT=$(az deployment sub show \
    --name qwiser-university-YYYYMMDD-HHMMSS \
    --query "properties.outputs.storageAccountName.value" -o tsv)

RESOURCE_GROUP="qwiser-prod-rg"
SHARE_NAME="ml-models"

echo "Storage Account: $STORAGE_ACCOUNT"
```

### Upload Models

**Option A: Azure CLI (Recommended)**

```bash
# Upload entire directory
az storage file upload-batch \
    --account-name "$STORAGE_ACCOUNT" \
    --destination "$SHARE_NAME" \
    --source ./ml-models \
    --auth-mode login \
    --pattern "*"
```

**Option B: AzCopy (Faster for large files)**

```bash
# Get storage account key
STORAGE_KEY=$(az storage account keys list \
    --account-name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --query "[0].value" -o tsv)

# Upload with AzCopy
azcopy copy "./ml-models/*" \
    "https://${STORAGE_ACCOUNT}.file.core.windows.net/${SHARE_NAME}?${SAS_TOKEN}" \
    --recursive
```

**Verification:**
```bash
az storage file list \
    --account-name "$STORAGE_ACCOUNT" \
    --share-name "$SHARE_NAME" \
    --auth-mode login \
    -o table
```

---

## Step 3: Verify Directory Structure

The Azure Files share should have this structure:

```
ml-models/
├── fastembed/
│   └── models--BAAI--bge-large-en-v1.5/
│       ├── config.json
│       ├── model.onnx
│       ├── tokenizer.json
│       └── ...
├── huggingface/
│   └── hub/
│       └── models--BAAI--bge-large-en-v1.5/
│           └── ...
└── sentence_transformers/
    └── all-MiniLM-L6-v2/
        ├── config.json
        ├── pytorch_model.bin
        └── ...
```

**List files to verify:**
```bash
az storage file list \
    --account-name "$STORAGE_ACCOUNT" \
    --share-name "$SHARE_NAME" \
    --path "fastembed" \
    --auth-mode login \
    -o table
```

---

## Step 4: Kubernetes PVC Configuration

The Bicep deployment creates an Azure Files PVC. The K8s manifests reference it:

### PVC Definition (Already in manifests)

```yaml
# ml-models-pvc.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ml-models-pv
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadOnlyMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: azurefile-csi
  csi:
    driver: file.csi.azure.com
    volumeHandle: ml-models-pv
    volumeAttributes:
      resourceGroup: REPLACE_WITH_RESOURCE_GROUP
      storageAccount: REPLACE_WITH_STORAGE_ACCOUNT_NAME
      shareName: ml-models
    nodeStageSecretRef:
      name: azure-storage-secret
      namespace: default
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ml-models-pvc
spec:
  accessModes:
    - ReadOnlyMany
  storageClassName: azurefile-csi
  volumeName: ml-models-pv
  resources:
    requests:
      storage: 10Gi
```

### Volume Mount in Pods

The embeddings-worker pods mount this PVC:

```yaml
# In embeddings-worker manifests
volumeMounts:
  - name: ml-models
    mountPath: /mnt/models
    readOnly: true

volumes:
  - name: ml-models
    persistentVolumeClaim:
      claimName: ml-models-pvc
      readOnly: true
```

### Environment Variables

```yaml
env:
  - name: FASTEMBED_CACHE_PATH
    value: "/mnt/models/fastembed"
  - name: HF_HOME
    value: "/mnt/models/huggingface"
  - name: SENTENCE_TRANSFORMERS_HOME
    value: "/mnt/models/sentence_transformers"
```

---

## Step 5: Verify in Cluster

After K8s deployment, verify the PVC and mount:

```bash
# Check PVC status
kubectl get pvc ml-models-pvc

# Expected: STATUS = Bound

# Check PV binding
kubectl get pv ml-models-pv

# Verify mount in pod
kubectl exec -it deployment/embeddings-worker-msgs -- ls -la /mnt/models/

# Expected:
# drwxr-xr-x  fastembed
# drwxr-xr-x  huggingface
# drwxr-xr-x  sentence_transformers
```

---

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| PVC stuck in Pending | Storage account not accessible | Check private endpoint connectivity |
| Mount fails with permission error | Wrong storage credentials | Recreate azure-storage-secret |
| Pod can't read models | Wrong directory structure | Verify upload path matches expected structure |
| Model loading slow | Azure Files latency | Pre-warm by running test inference |
| "Model not found" error | Wrong environment variable | Check FASTEMBED_CACHE_PATH value |

### Check Storage Secret

```bash
kubectl get secret azure-storage-secret -o yaml
```

### Check Pod Events

```bash
kubectl describe pod -l app=embeddings-worker-msgs | grep -A 20 Events
```

---

## Model Update Procedure

To update models without downtime:

1. **Download new model version locally**
2. **Upload to a new directory** (e.g., `fastembed-v2/`)
3. **Test in staging** with new path
4. **Update PV/PVC** to point to new directory
5. **Rolling restart** pods: `kubectl rollout restart deployment/embeddings-worker-msgs`

---

## GPU Optimization

For optimal GPU utilization with FastEmbed:

| Setting | Value | Purpose |
|---------|-------|---------|
| ONNX GPU Provider | CUDAExecutionProvider | Use GPU for inference |
| Batch Size | 32-128 | Balance throughput/latency |
| Max Seq Length | 512 | Truncate long texts |

These are configured in the embeddings-worker application code and don't require infrastructure changes.

---

## Next Steps

After ML models are set up:
1. Continue with [IMAGE_IMPORT_GUIDE.md](./IMAGE_IMPORT_GUIDE.md)
2. Deploy K8s manifests (includes PVC setup)
3. Verify embeddings-worker pods can access models
