# QWiser University - AI Models Setup

> **Last Updated**: 2026-01-14
> **Version**: 1.0.0
> **Audience**: University IT Infrastructure Teams

---

## Prerequisites

- [ ] Azure subscription with Azure AI Foundry access
- [ ] Resource group created (from Bicep deployment)
- [ ] Key Vault deployed and accessible
- [ ] App Configuration deployed and accessible
- [ ] Network access to Azure services (Cloud Shell or VPN)

---

## Required AI Models

QWiser requires the following AI models deployed in Azure AI Foundry:

| Model | Model ID | Purpose | Min TPM | Min RPM |
|-------|----------|---------|---------|---------|
| GPT-4.1 Mini | gpt-4.1-mini | Chat summaries, name generation | 100,000 | 1,000 |
| GPT-5.2 | gpt-5.2 | Main generation (questions, chat, trees) | 200,000 | 2,000 |
| Text Embedding 3 Large | text-embedding-3-large | Vector embeddings | 500,000 | 1,000 |
| Mistral Document AI | mistral-document-ai-2505 | OCR/Document processing | 50,000 | 500 |

---

## Step 1: Create Azure AI Foundry Resource

### Via Azure Portal

1. Navigate to Azure Portal > Create a resource
2. Search for "Azure AI Foundry"
3. Configure:
   - **Subscription**: Your subscription
   - **Resource group**: Your QWiser resource group
   - **Region**: Same as your deployment (check model availability)
   - **Name**: `{namePrefix}-{env}-ai` (e.g., `qwiser-prod-ai`)
   - **Pricing tier**: Standard S0

### Via Azure CLI

```bash
RESOURCE_GROUP="qwiser-prod-rg"
LOCATION="eastus"
AI_NAME="qwiser-prod-ai"

az cognitiveservices account create \
    --name "$AI_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --kind OpenAI \
    --sku S0 \
    --location "$LOCATION" \
    --custom-domain "$AI_NAME" \
    --yes
```

**Verification:**
```bash
az cognitiveservices account show \
    --name "$AI_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "{name:name, state:properties.provisioningState, endpoint:properties.endpoint}" \
    -o table
```

---

## Step 2: Deploy Models

### Deploy GPT-4.1 Mini

```bash
az cognitiveservices account deployment create \
    --name "$AI_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --deployment-name "gpt-4.1-mini" \
    --model-name "gpt-4.1-mini" \
    --model-version "2025-04-14" \
    --model-format OpenAI \
    --sku-capacity 100 \
    --sku-name "Standard"
```

### Deploy GPT-5.2

```bash
az cognitiveservices account deployment create \
    --name "$AI_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --deployment-name "gpt-5.2" \
    --model-name "gpt-5.2" \
    --model-version "2025-11-01" \
    --model-format OpenAI \
    --sku-capacity 200 \
    --sku-name "Standard"
```

### Deploy Text Embedding 3 Large

```bash
az cognitiveservices account deployment create \
    --name "$AI_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --deployment-name "text-embedding-3-large" \
    --model-name "text-embedding-3-large" \
    --model-version "1" \
    --model-format OpenAI \
    --sku-capacity 500 \
    --sku-name "Standard"
```

### Deploy Mistral Document AI (OCR)

```bash
az cognitiveservices account deployment create \
    --name "$AI_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --deployment-name "mistral-document-ai" \
    --model-name "mistral-document-ai-2505" \
    --model-version "2505" \
    --model-format OpenAI \
    --sku-capacity 50 \
    --sku-name "Standard"
```

**Verification:**
```bash
az cognitiveservices account deployment list \
    --name "$AI_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    -o table
```

---

## Step 3: Get API Key

```bash
# Get the API key
API_KEY=$(az cognitiveservices account keys list \
    --name "$AI_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "key1" -o tsv)

# Get the endpoint
ENDPOINT=$(az cognitiveservices account show \
    --name "$AI_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "properties.endpoint" -o tsv)

echo "Endpoint: $ENDPOINT"
echo "API Key: ${API_KEY:0:8}..."
```

> **Note**: The endpoint URL from Azure includes a trailing slash (e.g., `https://resource.openai.azure.com/`). The commands in Step 5 expect this format. If you're manually constructing URLs, ensure the trailing slash is present.

---

## Step 4: Update Key Vault

Store the API key in Key Vault:

```bash
KEYVAULT_NAME="qwiser-prod-kv"  # From deployment outputs

az keyvault secret set \
    --vault-name "$KEYVAULT_NAME" \
    --name "AI-FOUNDRY-API-KEY" \
    --value "$API_KEY"
```

**Verification:**
```bash
az keyvault secret show \
    --vault-name "$KEYVAULT_NAME" \
    --name "AI-FOUNDRY-API-KEY" \
    --query "value" | head -c 20
```

---

## Step 5: Update App Configuration

Update AI model configuration in Azure App Configuration:

### GPT-4.1 Mini

```bash
APPCONFIG_NAME="qwiser-prod-appconfig"  # From deployment outputs

# Endpoint
az appconfig kv set \
    -n "$APPCONFIG_NAME" \
    --key "ai:gpt-4.1-mini:endpoint" \
    --value "${ENDPOINT}openai/deployments/gpt-4.1-mini/chat/completions?api-version=2025-01-01-preview" \
    --label production \
    --yes

# Rate limits (adjust based on your deployment quota)
az appconfig kv set -n "$APPCONFIG_NAME" --key "ai:gpt-4.1-mini:rpm" --value "1000" --label production --yes
az appconfig kv set -n "$APPCONFIG_NAME" --key "ai:gpt-4.1-mini:tpm" --value "100000" --label production --yes
```

### GPT-5.2

```bash
az appconfig kv set \
    -n "$APPCONFIG_NAME" \
    --key "ai:gpt-5.2:endpoint" \
    --value "${ENDPOINT}openai/deployments/gpt-5.2/chat/completions?api-version=2025-01-01-preview" \
    --label production \
    --yes

az appconfig kv set -n "$APPCONFIG_NAME" --key "ai:gpt-5.2:rpm" --value "2000" --label production --yes
az appconfig kv set -n "$APPCONFIG_NAME" --key "ai:gpt-5.2:tpm" --value "200000" --label production --yes
```

### Text Embedding 3 Large

```bash
az appconfig kv set \
    -n "$APPCONFIG_NAME" \
    --key "ai:text-embedding-3-large:endpoint" \
    --value "${ENDPOINT}openai/deployments/text-embedding-3-large/embeddings?api-version=2023-05-15" \
    --label production \
    --yes

az appconfig kv set -n "$APPCONFIG_NAME" --key "ai:text-embedding-3-large:rpm" --value "1000" --label production --yes
az appconfig kv set -n "$APPCONFIG_NAME" --key "ai:text-embedding-3-large:tpm" --value "500000" --label production --yes
```

### Mistral Document AI (OCR)

```bash
az appconfig kv set \
    -n "$APPCONFIG_NAME" \
    --key "ai:ocr:endpoint" \
    --value "${ENDPOINT}openai/deployments/mistral-document-ai/completions?api-version=2025-01-01-preview" \
    --label production \
    --yes

az appconfig kv set -n "$APPCONFIG_NAME" --key "ai:ocr:rpm" --value "500" --label production --yes
```

---

## Step 6: Trigger Config Refresh

Update the sentinel key to trigger configuration refresh in running services:

```bash
az appconfig kv set \
    -n "$APPCONFIG_NAME" \
    --key "sentinel" \
    --value "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --label production \
    --yes
```

---

## Verification

### Verify App Configuration Values

```bash
az appconfig kv list \
    -n "$APPCONFIG_NAME" \
    --label production \
    --key "ai:*" \
    -o table
```

Expected output:
```
Key                                  Value
-----------------------------------  -----------------------------------------------
ai:gpt-4.1-mini:endpoint             https://qwiser-prod-ai.openai.azure.com/...
ai:gpt-4.1-mini:rpm                  1000
ai:gpt-4.1-mini:tpm                  100000
ai:gpt-5.2:endpoint                  https://qwiser-prod-ai.openai.azure.com/...
...
```

### Test API Connectivity (Optional)

```bash
curl -X POST "${ENDPOINT}openai/deployments/gpt-4.1-mini/chat/completions?api-version=2025-01-01-preview" \
    -H "Content-Type: application/json" \
    -H "api-key: $API_KEY" \
    -d '{
        "messages": [{"role": "user", "content": "Say hello"}],
        "max_tokens": 50
    }'
```

---

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Model deployment fails | Region doesn't support model | Try different region or model version |
| Quota exceeded | TPM/RPM limit reached | Request quota increase in Azure Portal |
| 401 Unauthorized | Invalid API key | Regenerate key and update Key Vault |
| 404 Not Found | Wrong endpoint URL | Check deployment name matches URL path |
| Rate limited | Too many requests | Reduce concurrent requests or increase quota |

### Check Model Availability by Region

```bash
az cognitiveservices model list \
    --location eastus \
    --query "[?kind=='OpenAI'].{name:model.name, version:model.version}" \
    -o table
```

---

## Cost Estimation

| Model | TPM | Est. Monthly Cost (USD) |
|-------|-----|-------------------------|
| gpt-4.1-mini @ 100K TPM | 100,000 | ~$50-100 |
| gpt-5.2 @ 200K TPM | 200,000 | ~$200-400 |
| text-embedding-3-large @ 500K TPM | 500,000 | ~$50-100 |
| mistral-document-ai @ 50K TPM | 50,000 | ~$25-50 |

**Total estimated**: $325-650/month (varies by actual usage)

---

## Next Steps

After AI models are configured:
1. Proceed to [ML_MODELS_SETUP.md](./ML_MODELS_SETUP.md) for local embedding models
2. Continue with [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) Phase 5
