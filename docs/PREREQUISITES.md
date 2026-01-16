# QWiser University - Prerequisites

---

## QWiser ACR Credentials

You need pull credentials for the QWiser container registry. Contact jonathan@qwiser.io to obtain these.

---

## Azure Subscription

- **Active Azure subscription** with billing configured
- **Subscription-level permissions**: Owner or Contributor + User Access Administrator

### Required Resource Providers

Register these providers **before** starting deployment. Some providers (especially `Microsoft.ContainerInstance`) can take several minutes to register and will cause deployment timeouts if not pre-registered.

```bash
# Register all required providers
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.ContainerRegistry
az provider register --namespace Microsoft.ContainerInstance  # Required for deployment scripts
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
az provider register --namespace Microsoft.ManagedIdentity
```

**Verify all providers are registered** (run this before deploying):

```bash
# Check all required providers at once
for ns in Microsoft.ContainerService Microsoft.ContainerRegistry Microsoft.ContainerInstance \
           Microsoft.KeyVault Microsoft.AppConfiguration Microsoft.DBforMySQL Microsoft.Cache \
           Microsoft.Storage Microsoft.Network Microsoft.Cdn Microsoft.OperationalInsights \
           Microsoft.Insights Microsoft.Security Microsoft.ManagedIdentity; do
    state=$(az provider show --namespace $ns --query "registrationState" -o tsv 2>/dev/null)
    printf "%-40s %s\n" "$ns" "$state"
done
```

All providers should show `Registered`. If any show `NotRegistered` or `Registering`, wait and re-check before proceeding.

---

## Required Tools

| Tool | Minimum Version | Installation |
|------|-----------------|--------------|
| Azure CLI | 2.67.0+ | [Install Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) |
| kubectl | 1.28+ | `az aks install-cli` |
| Helm | 3.14+ | [Install Helm](https://helm.sh/docs/intro/install/) |
| Git | 2.40+ | [Install Git](https://git-scm.com/downloads) |
| jq | 1.6+ | [Install jq](https://jqlang.github.io/jq/download/) |

**Verify installations:**
```bash
az version
kubectl version --client
helm version
git --version
jq --version
```

---

## Required Permissions

The deploying user needs:

| Permission | Scope | Purpose |
|------------|-------|---------|
| Owner OR Contributor + UAA | Subscription | Create resource groups and resources |
| Key Vault Secrets Officer | Key Vault | Seed secrets |
| App Configuration Data Owner | App Configuration | Seed configuration |

---

## Next Steps

Once all prerequisites are met, proceed to [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md).
