# QWiser On-Premises Deployment

Deploy QWiser to your own Azure infrastructure.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fqwiserai%2Fqwiser-on-prem%2Fv0.0.5%2Fbicep%2Fmain.json/createUIDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Fqwiserai%2Fqwiser-on-prem%2Fv0.0.5%2Fbicep%2FcreateUiDefinition.json)

---

## What is QWiser?

QWiser is an AI-powered learning platform that transforms educational content (PDFs, videos, YouTube, Wikipedia) into interactive knowledge trees, study materials, quizzes, and exams.

---

## Prerequisites

Before deploying, ensure you have:

- [ ] Azure subscription with **Owner** or **Contributor + User Access Administrator** access
- [ ] Required resource providers registered ([see PREREQUISITES.md](docs/PREREQUISITES.md))
- [ ] **ACR pull credentials** (provided by QWiser — contact jonathan@qwiser.io)
- [ ] Azure OpenAI access approved (or existing deployments)
- [ ] A domain you control with ability to create DNS records (e.g., `yourdomain.com`)

**Estimated deployment time**: 30-45 minutes for Azure resources, plus configuration.

---

## Quick Start

### Option A: One-Click Deploy (Recommended)

Click the button at the top of this page, fill in the parameters, and deploy. Recommended for built-in validations and guided configuration.

After deployment completes, clone this repo for post-deployment scripts:

```bash
git clone https://github.com/qwiserai/qwiser-on-prem.git
cd qwiser-on-prem
```

Then continue to [Post-Deployment Steps](#post-deployment-steps).

### Option B: Deploy via CLI

Clone the repo and deploy with full control over parameters:

```bash
git clone https://github.com/qwiserai/qwiser-on-prem.git
cd qwiser-on-prem

# Review and customize parameters
cp bicep/main.bicepparam bicep/my-env.bicepparam
# Edit bicep/my-env.bicepparam with your values

# Login to Azure
az login
az account set --subscription "<your-subscription-id>"

# Deploy (subscription-scoped - creates its own resource group)
az deployment sub create \
  --location <your-region> \
  --template-file bicep/main.bicep \
  --parameters bicep/my-env.bicepparam
```

Then continue to [Post-Deployment Steps](#post-deployment-steps).

---

## Key Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `location` | Azure region | `westeurope`, `eastus` |
| `environmentName` | Environment identifier | `prod`, `staging` |
| `customDomain` | Full hostname you'll use (you create CNAME post-deploy) | `qwiser.yourdomain.com` |
| `mysqlAdminLogin` | MySQL admin username | `qwiseradmin` |
| `mysqlAdminPassword` | MySQL admin password | (secure password) |

See [DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md) for all parameters.

---

## What Gets Deployed

The Bicep deployment creates:

- **Compute**: Azure Kubernetes Service (AKS) with system and optional GPU node pools
- **Registry**: Azure Container Registry (ACR)
- **Database**: Azure Database for MySQL Flexible Server
- **Cache**: Azure Managed Redis
- **Security**: Azure Key Vault, Virtual Network with private endpoints
- **Config**: Azure App Configuration
- **Ingress**: Azure Front Door with WAF
- **Storage**: Azure Storage Account
- **Monitoring**: Log Analytics workspace, Application Insights

---

## Post-Deployment Steps

After infrastructure deployment, complete these steps:

### 1. Approve Private Endpoint Connection

Front Door's private endpoint to your Private Link Service needs approval:

```bash
./scripts/approve-pe-connection.sh --resource-group <your-rg>
```

### 2. Import Container Images

Import QWiser container images to your ACR:

```bash
./scripts/import-images.sh \
    --source-user <provided-by-qwiser> \
    --source-password <provided-by-qwiser> \
    --target-acr <your-acr-name>
```

See [IMAGE_IMPORT_GUIDE.md](docs/IMAGE_IMPORT_GUIDE.md) for details.

### 3. Seed Configuration

Populate Azure App Configuration:

```bash
./scripts/seed-appconfig.sh --app-config-name <your-appconfig-name>
```

See [APPCONFIG_REFERENCE.md](docs/APPCONFIG_REFERENCE.md) for all configuration keys.

### 4. Seed Key Vault Secrets

Add secrets to Key Vault:

```bash
./scripts/seed-keyvault.sh --key-vault-name <your-keyvault-name>
```

### 5. Deploy AI Models

Create Azure OpenAI deployments for the required models.

See [AI_MODELS_SETUP.md](docs/AI_MODELS_SETUP.md) for requirements.

### 6. Download ML Models

Download and mount ML models for the embeddings worker.

See [ML_MODELS_SETUP.md](docs/ML_MODELS_SETUP.md) for the model list.

### 7. Apply Kubernetes Manifests

Deploy QWiser services to AKS:

```bash
# Get AKS credentials
az aks get-credentials --resource-group <your-rg> --name <your-aks-name>

# Apply manifests
cd k8s/base
./apply.sh
```

See [DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md) for the full walkthrough.

### 8. Configure Custom Domain & SSL

Azure Front Door handles SSL automatically with free managed certificates.

**Step 8a: Get Front Door hostname**

```bash
# From deployment outputs, or:
az afd endpoint show \
  --resource-group <your-rg> \
  --profile-name <your-fd-profile> \
  --endpoint-name <your-endpoint> \
  --query "hostName" -o tsv
```

**Step 8b: Create CNAME record**

In your DNS provider, create:
```
qwiser.yourdomain.com  CNAME  <frontdoor-hostname>.azurefd.net
```

**Step 8c: Add custom domain to Front Door**

```bash
az afd custom-domain create \
  --resource-group <your-rg> \
  --profile-name <your-fd-profile> \
  --custom-domain-name qwiser-custom-domain \
  --host-name qwiser.yourdomain.com \
  --certificate-type ManagedCertificate
```

**Step 8d: Associate domain with route**

```bash
az afd route update \
  --resource-group <your-rg> \
  --profile-name <your-fd-profile> \
  --endpoint-name <your-endpoint> \
  --route-name default-route \
  --custom-domains qwiser-custom-domain
```

Certificate provisioning takes 5-15 minutes. Check status:
```bash
az afd custom-domain show \
  --resource-group <your-rg> \
  --profile-name <your-fd-profile> \
  --custom-domain-name qwiser-custom-domain \
  --query "{domain:hostName, certStatus:tlsSettings.certificateType, validationState:validationProperties.validationState}"
```

### 9. Configure LTI Integration

Integrate QWiser with your LMS (Moodle, Canvas, Blackboard).

See [LTI_INTEGRATION.md](docs/LTI_INTEGRATION.md) for instructions.

### 10. Verify Deployment

Run post-deployment checks:

```bash
./scripts/post-deploy.sh --resource-group <your-rg>
```

See [POST_DEPLOYMENT.md](docs/POST_DEPLOYMENT.md) for verification steps.

---

## Documentation

| Document | Description |
|----------|-------------|
| [PREREQUISITES.md](docs/PREREQUISITES.md) | Prerequisites and resource provider registration |
| [DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md) | Full deployment walkthrough |
| [IMAGE_IMPORT_GUIDE.md](docs/IMAGE_IMPORT_GUIDE.md) | Container image import process |
| [AI_MODELS_SETUP.md](docs/AI_MODELS_SETUP.md) | Azure OpenAI model deployment |
| [ML_MODELS_SETUP.md](docs/ML_MODELS_SETUP.md) | ML model download and mounting |
| [APPCONFIG_REFERENCE.md](docs/APPCONFIG_REFERENCE.md) | Configuration key reference |
| [LTI_INTEGRATION.md](docs/LTI_INTEGRATION.md) | LMS integration guide |
| [POST_DEPLOYMENT.md](docs/POST_DEPLOYMENT.md) | Post-deployment verification |
| [SECRET_ROTATION.md](docs/SECRET_ROTATION.md) | Secret rotation procedures |

---

## Architecture

```
                          ┌─────────────────┐
                          │   Front Door    │
                          │   (WAF + CDN)   │
                          └────────┬────────┘
                                   │
                          ┌────────▼────────┐
                          │   AKS Cluster   │
                          └────────┬────────┘
                                   │
        ┌──────────────────────────┼──────────────────────────┐
        │                          │                          │
┌───────▼───────┐         ┌───────▼───────┐         ┌────────▼────────┐
│   Frontend    │         │  Public API   │         │  Internal DB    │
│   (React)     │         │  (Gateway)    │         │  (MySQL API)    │
└───────────────┘         └───────┬───────┘         └─────────────────┘
                                  │
        ┌─────────────────────────┼─────────────────────────┐
        │                         │                         │
┌───────▼───────┐        ┌───────▼───────┐        ┌────────▼────────┐
│ Text Loading  │        │Other Generate │        │  Topic Modeling │
│  (Ingestion)  │        │(AI Generation)│        │  (Knowledge)    │
└───────────────┘        └───────────────┘        └────────┬────────┘
                                                           │
                                                  ┌────────▼────────┐
                                                  │Embeddings Worker│
                                                  │   (GPU/CPU)     │
                                                  └─────────────────┘
```

**Managed Services:**
- Azure Database for MySQL
- Azure Managed Redis
- Azure OpenAI
- Azure Blob Storage

---

## Versioning

See [VERSIONS.txt](VERSIONS.txt) for current image tags.

See [CHANGELOG.md](CHANGELOG.md) for version history.

---

## Support

- **Email**: support@qwiser.io
- **Issues**: Open an issue in this repository

---

## License

This deployment package is provided under license to your organization. See your license agreement for terms.
