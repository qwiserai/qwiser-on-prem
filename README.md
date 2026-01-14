# QWiser University Deployment

One-click deployment of QWiser to your Azure subscription.

---

## What is QWiser?

QWiser is an AI-powered learning platform that transforms educational content (PDFs, videos, YouTube, Wikipedia) into interactive knowledge trees, study materials, quizzes, and exams.

---

## Prerequisites

Before deploying, ensure you have:

- [ ] Azure subscription with **Owner** or **Contributor + User Access Administrator** access
- [ ] Required resource providers registered ([see PREREQUISITES.md](docs/PREREQUISITES.md))
- [ ] **ACR pull credentials** (provided by QWiser)
- [ ] Azure OpenAI access approved (or existing deployments)
- [ ] Custom domain ready (e.g., `qwiser.university.edu`)

**Estimated deployment time**: 30-45 minutes for Azure resources, plus configuration.

---

## Deploy to Azure

Click the button below to deploy QWiser infrastructure to your Azure subscription:

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fqwiserai%2Fqwiser-on-prem%2Fmain%2Fbicep%2Fmain.json)

**What gets deployed:**
- Azure Kubernetes Service (AKS) with system and GPU node pools
- Azure Container Registry (ACR) for image storage
- Azure Database for MySQL Flexible Server
- Azure Cache for Redis
- Azure Key Vault for secrets
- Azure App Configuration for centralized config
- Azure Front Door for global load balancing and WAF
- Azure Storage Account for blob storage
- Virtual Network with private endpoints
- Log Analytics workspace for monitoring

---

## Post-Deployment Steps

After the Azure deployment completes, follow these steps in order:

### 1. Import Container Images

Import QWiser container images to your ACR using the credentials provided.

```bash
# Linux/macOS
./scripts/import-images.sh \
    --source-user <provided-by-qwiser> \
    --source-password <provided-by-qwiser> \
    --target-acr <your-acr-name>
```

```powershell
# Windows PowerShell
.\scripts\import-images.ps1 `
    -SourceUser <provided-by-qwiser> `
    -SourcePassword <provided-by-qwiser> `
    -TargetAcr <your-acr-name>
```

See [IMAGE_IMPORT_GUIDE.md](docs/IMAGE_IMPORT_GUIDE.md) for details.

### 2. Seed Configuration

Populate Azure App Configuration with required settings.

```powershell
.\scripts\seed-appconfig.ps1 -AppConfigName <your-appconfig-name>
```

See [APPCONFIG_REFERENCE.md](docs/APPCONFIG_REFERENCE.md) for all configuration keys.

### 3. Seed Key Vault Secrets

Add secrets to Key Vault.

```powershell
.\scripts\seed-keyvault.ps1 -KeyVaultName <your-keyvault-name>
```

### 4. Deploy AI Models

Create Azure OpenAI deployments for the required models.

See [AI_MODELS_SETUP.md](docs/AI_MODELS_SETUP.md) for model requirements and deployment instructions.

### 5. Download ML Models

Download and mount ML models for the embeddings worker.

See [ML_MODELS_SETUP.md](docs/ML_MODELS_SETUP.md) for the model list and download process.

### 6. Apply Kubernetes Manifests

Deploy QWiser services to AKS.

```bash
cd k8s/base
./apply.sh
```

See [DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md) for the full deployment walkthrough.

### 7. Configure LTI Integration

Integrate QWiser with your LMS (Moodle, Canvas, Blackboard).

See [LTI_INTEGRATION.md](docs/LTI_INTEGRATION.md) for step-by-step instructions.

### 8. Verify Deployment

Run post-deployment checks.

See [POST_DEPLOYMENT.md](docs/POST_DEPLOYMENT.md) for verification steps.

---

## Current Version

See [VERSIONS.txt](VERSIONS.txt) for the image tags in this release.

**Current release**: See [CHANGELOG.md](CHANGELOG.md) for version history.

---

## Documentation Index

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

## Architecture Overview

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

**External Dependencies:**
- Azure Database for MySQL (managed)
- Azure Cache for Redis (managed)
- Azure OpenAI (managed)
- Azure Storage (blobs)

---

## Support

- **Documentation issues**: Open an issue in this repository
- **Deployment support**: Contact your QWiser representative
- **Email**: support@qwiser.io

---

## License

This deployment package is provided under license to your institution. See your license agreement for terms.
