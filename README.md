# QWiser On-Premises Deployment

Deploy QWiser to your own Azure infrastructure.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fqwiserai%2Fqwiser-on-prem%2Fv1.0.0%2Fbicep%2Fmain.json/createUIDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Fqwiserai%2Fqwiser-on-prem%2Fv1.0.0%2Fbicep%2FcreateUiDefinition.json)

---

## What is QWiser?

QWiser is an AI-powered learning platform that transforms educational content (PDFs, videos, YouTube, Wikipedia) into interactive knowledge trees, study materials, quizzes, and exams.

---

## Prerequisites

Before deploying, see [PREREQUISITES.md](docs/PREREQUISITES.md) for:
- Required Azure permissions
- Resource provider registration
- Required tools (Azure CLI, kubectl, Helm, jq)

---

## Quick Start

### Option A: One-Click Deploy (Recommended)

Click the button at the top of this page, fill in the parameters, and deploy. Recommended for built-in validations and guided configuration.

After deployment completes:

1. Clone this repo for post-deployment scripts:
   ```bash
   git clone https://github.com/qwiserai/qwiser-on-prem.git
   cd qwiser-on-prem
   ```

2. Continue to **[DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md)**.

### Option B: Deploy via CLI

If you prefer CLI over the portal, see `bicep/main.bicep` and `bicep/main.bicepparam` If you know what you are doing.

---

## What Gets Deployed

The Bicep deployment creates:

- **Compute**: Azure Kubernetes Service (AKS)
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

After infrastructure deployment, follow [DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md) to complete:

1. **Capture deployment outputs** - Save Azure deployment outputs for later use
2. **Run post-deployment scripts** - Seed Key Vault secrets and App Configuration
3. **Deploy AI models** - Create Azure OpenAI deployments
4. **Import container images** - Pull QWiser images to your ACR
5. **Install Kubernetes components** - KEDA, Qdrant, QWiser services
6. **Configure custom domain** - DNS CNAME + Front Door custom domain
7. **Verify deployment** - Health checks and connectivity tests

**Estimated time**: 1-2 hours after infrastructure deployment completes.

---

## Documentation

| Document | Description |
|----------|-------------|
| [PREREQUISITES.md](docs/PREREQUISITES.md) | Prerequisites and resource provider registration |
| [DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md) | Full deployment walkthrough |
| [IMAGE_IMPORT_GUIDE.md](docs/IMAGE_IMPORT_GUIDE.md) | Container image import process |
| [ML_MODELS_SETUP.md](docs/ML_MODELS_SETUP.md) | ML model download and mounting |
| [APPCONFIG_REFERENCE.md](docs/APPCONFIG_REFERENCE.md) | Configuration key reference |
| [LTI_INTEGRATION.md](docs/LTI_INTEGRATION.md) | LMS integration guide |
| [SECRET_ROTATION.md](docs/SECRET_ROTATION.md) | Secret rotation procedures |

---

## Versioning

See [VERSIONS.txt](VERSIONS.txt) for current image tags.
