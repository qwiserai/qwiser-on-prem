# QWiser University - Prerequisites

> **Last Updated**: 2026-01-14
> **Version**: 1.0.0
> **Audience**: University IT Infrastructure Teams

---

## Prerequisites Checklist

Complete all items before starting deployment.

### Azure Subscription

- [ ] **Active Azure subscription** with billing configured
- [ ] **Subscription-level permissions**: Owner or Contributor + User Access Administrator
- [ ] **Resource provider registrations** (see below)
- [ ] **Sufficient quotas** for required resources (see Quotas section)

### Required Resource Providers

Register these providers in your subscription:

```bash
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.ContainerRegistry
az provider register --namespace Microsoft.KeyVault
az provider register --namespace Microsoft.AppConfiguration
az provider register --namespace Microsoft.DBforMySQL
az provider register --namespace Microsoft.Cache
az provider register --namespace Microsoft.Storage
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.Cdn
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.Insights
az provider register --namespace Microsoft.Security

# Verify registration
az provider show --namespace Microsoft.ContainerService --query "registrationState"
```

### Azure Quotas

| Resource | Minimum Required | How to Check |
|----------|------------------|--------------|
| Standard DSv5 vCPUs | 12 | `az vm list-usage -l eastus -o table \| grep DSv5` |
| Standard NCas T4 v3 vCPUs (GPU) | 4 | `az vm list-usage -l eastus -o table \| grep NC` |
| Public IP Addresses | 5 | `az network list-usages -l eastus -o table` |
| Storage Accounts | 5 | Azure Portal > Subscriptions > Usage + quotas |
| Azure Front Door Premium | 1 | Azure Portal > Subscriptions > Usage + quotas |

**Request quota increase if needed:**
```bash
# Via Azure Portal: Subscriptions > Usage + quotas > Request increase
# Or via Azure CLI:
az support tickets create --ticket-name "Quota Increase" ...
```

---

## Local Tools

### Required Tools

| Tool | Minimum Version | Installation |
|------|-----------------|--------------|
| Azure CLI | 2.67.0+ | [Install Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) |
| kubectl | 1.28+ | `az aks install-cli` |
| Helm | 3.14+ | [Install Helm](https://helm.sh/docs/intro/install/) |
| Git | 2.40+ | [Install Git](https://git-scm.com/downloads) |

**Verify installations:**
```bash
az version
kubectl version --client
helm version
git --version
```

### Optional Tools

| Tool | Purpose | Installation |
|------|---------|--------------|
| jq | JSON parsing | `apt install jq` or `brew install jq` |
| yq | YAML parsing | `snap install yq` or `brew install yq` |
| Bicep CLI | Local Bicep validation | `az bicep install` |

---

## Network Requirements

### Outbound Internet Access

The deployment machine requires outbound access to:

| Endpoint | Purpose |
|----------|---------|
| `*.azure.com` | Azure management APIs |
| `*.azurecr.io` | Container Registry |
| `*.blob.core.windows.net` | Blob Storage |
| `login.microsoftonline.com` | Azure AD authentication |
| `management.azure.com` | Azure Resource Manager |

### Private Endpoint Access

**Decision Table: Network Access Method**

| Situation | Recommendation | Notes |
|-----------|----------------|-------|
| Can use Azure Cloud Shell | Cloud Shell with VNet injection | Easiest setup |
| Corporate VPN to Azure VNet | VPN + private endpoints | Standard enterprise pattern |
| Jumpbox/Bastion in Azure | SSH to jumpbox | Deploy Azure Bastion first |
| Public AKS cluster | Not recommended | Security risk |

**Recommended: Azure Cloud Shell with VNet Integration**

Cloud Shell automatically handles private endpoint connectivity when configured.

---

## Azure AD Configuration

### Service Principal (Optional)

If using service principal instead of managed identity for deployment:

```bash
# Create service principal with Contributor role
az ad sp create-for-rbac \
    --name "qwiser-deployment-sp" \
    --role Contributor \
    --scopes /subscriptions/YOUR_SUBSCRIPTION_ID
```

**Store credentials securely** - never commit to source control.

### User Permissions

The deploying user needs:

| Permission | Scope | Purpose |
|------------|-------|---------|
| Owner OR Contributor + UAA | Subscription | Create resource groups and resources |
| Key Vault Secrets Officer | Key Vault | Seed secrets |
| App Configuration Data Owner | App Configuration | Seed configuration |

---

## External Dependencies

### Custom Domain

- [ ] **Domain ownership** verified
- [ ] **DNS management access** to create CNAME records
- [ ] **TLS certificate** (Azure Front Door provides managed certificate)

**Example domain setup:**
```
Primary: qwiser.myuniversity.edu
DNS Provider: University DNS / Cloudflare / Route53
```

### Container Images

Choose one option:

| Option | Source | Recommended For |
|--------|--------|-----------------|
| QWiser ACR | Contact QWiser for access | Production deployments |
| Self-built | Build from QWiser source code | Custom modifications |
| Export from SaaS | Export from existing QWiser SaaS | Migration from SaaS |

---

## Pre-Deployment Decisions

Make these decisions before starting deployment:

### 1. Environment Naming

```
namePrefix: qwiser (default)
environmentName: prod | staging | dev
```

**Resulting resource group**: `{namePrefix}-{environmentName}-rg` (e.g., `qwiser-prod-rg`)

### 2. Region Selection

| Consideration | Recommended Regions |
|---------------|---------------------|
| Azure AI Foundry availability | eastus, westus2, eastus2, westeurope |
| GPU availability (NC-series) | eastus, westus2, southcentralus |
| Data residency requirements | Region closest to university |
| Disaster recovery pairing | Check Azure region pairs |

### 3. GPU Node Pool

| Question | Yes | No |
|----------|-----|-----|
| Using local embeddings (FastEmbed)? | Deploy GPU pool | Skip GPU pool |
| High embedding throughput needed? | Deploy GPU pool | CPU embeddings OK |
| Budget constraints? | Consider CPU-only | Deploy GPU pool |

**Set in parameters:**
```bicep
param deployGpuNodePool = true  // or false
```

### 4. High Availability

| Component | HA Option | Cost Impact |
|-----------|-----------|-------------|
| MySQL | ZoneRedundant | +50% |
| Redis | Enabled (default) | Included |
| AKS | Multi-zone node pool | Included |

---

## Pre-Deployment Checklist

### Required Information

Gather this information before starting:

| Item | Example | Your Value |
|------|---------|------------|
| Azure Region | eastus | |
| Custom Domain | qwiser.myuniversity.edu | |
| MySQL Admin Username | qwiseradmin | |
| MySQL Admin Password | (secure password) | |
| Environment Name | prod | |
| Deploy GPU Pool | true/false | |

### Pre-Flight Validation

Run these commands to validate prerequisites:

```bash
# 1. Verify Azure CLI authentication
az account show --query "{name:name, id:id, tenantId:tenantId}" -o table

# 2. Verify correct subscription
az account set --subscription "YOUR_SUBSCRIPTION_NAME"

# 3. Verify quota availability
az vm list-usage --location eastus --query "[?contains(name.value, 'DSv5')]" -o table

# 4. Verify kubectl
kubectl version --client

# 5. Verify Helm
helm version

# 6. Verify Bicep
az bicep version
```

---

## Next Steps

Once all prerequisites are met, proceed to [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md).
