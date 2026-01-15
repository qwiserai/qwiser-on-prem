// ============================================================================
// QWiser University Infrastructure - Main Deployment
// ============================================================================
// Purpose: Orchestrates deployment of all Azure resources for QWiser University
// This file grows incrementally across implementation phases.
// ============================================================================

targetScope = 'subscription'

// ============================================================================
// Parameters
// ============================================================================

@description('Environment name used for resource naming (e.g., prod, staging)')
@minLength(1)
@maxLength(10)
param environmentName string

@description('Base name prefix for all resources')
@minLength(1)
@maxLength(10)
param namePrefix string = 'qwiser'

@description('Tags to apply to all resources. Example: { Environment: "prod", CostCenter: "IT-12345", Owner: "admin@university.edu" }')
param tags object = {}

// ============================================================================
// Networking Parameters
// ============================================================================

@description('Virtual network address space. Uses 10.200.x.x range to minimize overlap with common enterprise networks. Change if this conflicts with existing campus or Azure networks.')
param vnetAddressPrefix string = '10.200.0.0/16'

@description('Subnet for private endpoints (Azure PaaS services connect here via Private Link). Currently uses ~11 IPs for private endpoints and Private Link Service NAT.')
param peSubnetPrefix string = '10.200.0.0/24'

@description('Subnet for AKS worker nodes. Size /22 provides 1024 IPs to support cluster autoscaling.')
param aksNodesSubnetPrefix string = '10.200.4.0/22'

@description('Subnet for deployment scripts (temporary containers used during infrastructure setup). Requires Azure Container Instances delegation.')
param aciSubnetPrefix string = '10.200.8.0/27'

// ============================================================================
// Storage Parameters
// ============================================================================

@description('Allow shared key access on storage account (true = simpler IT uploads, false = Entra ID only)')
param storageAllowSharedKeyAccess bool = true

// ============================================================================
// MySQL Parameters
// ============================================================================

@description('MySQL administrator login name')
@minLength(1)
param mysqlAdminLogin string

@description('MySQL administrator password')
@secure()
param mysqlAdminPassword string

@description('MySQL SKU tier')
@allowed([
  'Burstable'
  'GeneralPurpose'
  'MemoryOptimized'
])
param mysqlSkuTier string = 'GeneralPurpose'

@description('MySQL SKU name')
param mysqlSkuName string = 'Standard_D2ds_v4'

@description('MySQL storage size in GB')
param mysqlStorageSizeGB int = 64

@description('MySQL high availability mode (Burstable tier does not support HA)')
@allowed([
  'Disabled'
  'SameZone'
  'ZoneRedundant'
])
param mysqlHighAvailabilityMode string = 'Disabled'

// ============================================================================
// Redis Parameters
// ============================================================================

@description('Redis SKU name. Balanced tier recommended for QWiser workloads.')
@allowed([
  'Balanced_B0'    // 0.5 GB - Dev/test only
  'Balanced_B1'    // 1 GB   - Dev/test
  'Balanced_B3'    // 3 GB   - Small production
  'Balanced_B5'    // 5 GB   - Small production (default)
  'Balanced_B10'   // 10 GB  - Medium production
  'Balanced_B20'   // 20 GB  - Large production
  'Balanced_B50'   // 50 GB  - Large production
  'Balanced_B100'  // 100 GB - Enterprise
])
param redisSkuName string = 'Balanced_B5'

@description('Enable Redis high availability')
@allowed([
  'Enabled'
  'Disabled'
])
param redisHighAvailability string = 'Enabled'

@description('Redis availability zones for zone redundancy')
param redisZones array = []

// ============================================================================
// AKS Parameters
// ============================================================================

@description('Kubernetes version (leave empty for latest stable)')
param kubernetesVersion string = ''

@description('Enable private cluster mode (API server not publicly accessible)')
param aksEnablePrivateCluster bool = true

@description('Authorized IP ranges for API server access (ignored if private cluster)')
param aksAuthorizedIPRanges array = []

@description('AKS system node pool VM size')
param aksSystemNodeVmSize string = 'Standard_D4s_v5'

@description('AKS system node pool initial node count')
param aksSystemNodeCount int = 3

@description('AKS system node pool min count for autoscaling')
param aksSystemNodeMinCount int = 2

@description('AKS system node pool max count for autoscaling')
param aksSystemNodeMaxCount int = 10

@description('Pod CIDR for Azure CNI Overlay. Uses CGNAT range (100.64.x.x) which is unlikely to conflict with campus networks. Only change if your network already uses this range.')
param aksPodCidr string = '100.64.0.0/16'

@description('Deploy GPU node pool for embeddings-worker. Required - embeddings fail without GPU acceleration.')
param deployGpuNodePool bool = true

@description('GPU node pool VM size')
param gpuNodeVmSize string = 'Standard_NC4as_T4_v3'

// ============================================================================
// Ingress Parameters
// ============================================================================

@description('Static private IP for NGINX Ingress internal LoadBalancer (must be in AKS nodes subnet range)')
param nginxIngressPrivateIp string = '10.200.4.250'

@description('Enable Web Application Firewall on Front Door')
param enableWaf bool = true

@description('WAF mode (Detection for testing, Prevention for production)')
@allowed([
  'Detection'
  'Prevention'
])
param wafMode string = 'Prevention'

// ============================================================================
// Workload Identity Parameters
// ============================================================================

@description('Kubernetes namespace for QWiser workloads (federated credentials bound to this namespace)')
param workloadNamespace string = 'default'

// ============================================================================
// URL Configuration Parameters
// ============================================================================

@description('Custom domain that university will point to Front Door (e.g., qwiser.university.edu). Used for ConfigMap URL env vars.')
param customDomain string

// ============================================================================
// Variables
// ============================================================================

// Derive location from deployment region (user selects in Portal's region dropdown)
var location = deployment().location

var resourceGroupName = '${namePrefix}-${environmentName}-rg'
var namingPrefix = '${namePrefix}-${environmentName}'
var aksClusterName = '${namingPrefix}-aks'

// Unique suffix for globally unique Key Vault names
var uniqueSuffix = substring(uniqueString(subscription().subscriptionId, resourceGroupName), 0, 6)

// Pre-compute node resource group name (deterministic: MC_<rg>_<cluster>_<location>)
// This allows cross-RG role assignments without waiting for AKS outputs
var nodeResourceGroupName = 'MC_${resourceGroupName}_${aksClusterName}_${location}'

// ============================================================================
// Resource Group
// ============================================================================

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// ============================================================================
// Phase 1: Core Infrastructure
// ============================================================================

// --- Networking ---
module vnet 'modules/networking/vnet.bicep' = {
  scope: rg
  name: 'deploy-vnet'
  params: {
    location: location
    namingPrefix: namingPrefix
    tags: tags
    vnetAddressPrefix: vnetAddressPrefix
    peSubnetPrefix: peSubnetPrefix
    aksNodesSubnetPrefix: aksNodesSubnetPrefix
    aciSubnetPrefix: aciSubnetPrefix
  }
}

module privateDnsZones 'modules/networking/private-dns-zones.bicep' = {
  scope: rg
  name: 'deploy-private-dns-zones'
  params: {
    location: location
    vnetId: vnet.outputs.vnetId
    tags: tags
  }
}

// --- Identity ---
module managedIdentity 'modules/identity/managed-identity.bicep' = {
  scope: rg
  name: 'deploy-managed-identity'
  params: {
    location: location
    namingPrefix: namingPrefix
    tags: tags
    aksNodesSubnetId: vnet.outputs.aksNodesSubnetId
    peSubnetId: vnet.outputs.peSubnetId
    aksDnsZoneId: privateDnsZones.outputs.aksDnsZoneId
  }
}

// --- Security ---
module keyVault 'modules/security/keyvault.bicep' = {
  scope: rg
  name: 'deploy-keyvault'
  params: {
    location: location
    namingPrefix: namingPrefix
    uniqueSuffix: uniqueSuffix
    tags: tags
    peSubnetId: vnet.outputs.peSubnetId
    privateDnsZoneId: privateDnsZones.outputs.keyVaultDnsZoneId
    workloadIdentityPrincipalId: managedIdentity.outputs.principalId
  }
}

// --- Configuration ---
module appConfig 'modules/config/appconfig.bicep' = {
  scope: rg
  name: 'deploy-appconfig'
  params: {
    location: location
    namingPrefix: namingPrefix
    tags: tags
    peSubnetId: vnet.outputs.peSubnetId
    privateDnsZoneId: privateDnsZones.outputs.appConfigDnsZoneId
    workloadIdentityPrincipalId: managedIdentity.outputs.principalId
  }
}

// ============================================================================
// Phase 2: Data & Compute Infrastructure
// ============================================================================

// --- Storage ---
module storageAccount 'modules/storage/storage-account.bicep' = {
  scope: rg
  name: 'deploy-storage-account'
  params: {
    location: location
    namingPrefix: namingPrefix
    tags: tags
    peSubnetId: vnet.outputs.peSubnetId
    blobDnsZoneId: privateDnsZones.outputs.blobDnsZoneId
    queueDnsZoneId: privateDnsZones.outputs.queueDnsZoneId
    fileDnsZoneId: privateDnsZones.outputs.fileDnsZoneId
    allowSharedKeyAccess: storageAllowSharedKeyAccess
    keyVaultName: keyVault.outputs.keyVaultName
  }
}

// --- Container Registry ---
module acr 'modules/registry/acr.bicep' = {
  scope: rg
  name: 'deploy-acr'
  params: {
    location: location
    namingPrefix: namingPrefix
    tags: tags
    peSubnetId: vnet.outputs.peSubnetId
    privateDnsZoneId: privateDnsZones.outputs.acrDnsZoneId
  }
}

// --- Database ---
module mysql 'modules/data/mysql.bicep' = {
  scope: rg
  name: 'deploy-mysql'
  params: {
    location: location
    namingPrefix: namingPrefix
    tags: tags
    peSubnetId: vnet.outputs.peSubnetId
    privateDnsZoneId: privateDnsZones.outputs.mysqlDnsZoneId
    administratorLogin: mysqlAdminLogin
    administratorLoginPassword: mysqlAdminPassword
    skuTier: mysqlSkuTier
    skuName: mysqlSkuName
    storageSizeGB: mysqlStorageSizeGB
    highAvailabilityMode: mysqlHighAvailabilityMode
    keyVaultName: keyVault.outputs.keyVaultName
  }
}

// --- Redis ---
module redis 'modules/data/redis.bicep' = {
  scope: rg
  name: 'deploy-redis'
  params: {
    location: location
    namingPrefix: namingPrefix
    tags: tags
    peSubnetId: vnet.outputs.peSubnetId
    privateDnsZoneId: privateDnsZones.outputs.redisDnsZoneId
    skuName: redisSkuName
    highAvailability: redisHighAvailability
    zones: redisZones
  }
}

// --- AKS ---
module aks 'modules/compute/aks.bicep' = {
  scope: rg
  name: 'deploy-aks'
  params: {
    location: location
    namingPrefix: namingPrefix
    tags: tags
    aksNodesSubnetId: vnet.outputs.aksNodesSubnetId
    managedIdentityId: managedIdentity.outputs.identityId
    managedIdentityPrincipalId: managedIdentity.outputs.principalId
    aksDnsZoneId: privateDnsZones.outputs.aksDnsZoneId
    acrId: acr.outputs.acrId
    kubernetesVersion: kubernetesVersion
    enablePrivateCluster: aksEnablePrivateCluster
    authorizedIPRanges: aksAuthorizedIPRanges
    systemNodeVmSize: aksSystemNodeVmSize
    systemNodeCount: aksSystemNodeCount
    systemNodeMinCount: aksSystemNodeMinCount
    systemNodeMaxCount: aksSystemNodeMaxCount
    podCidr: aksPodCidr
  }
}

// --- AKS GPU Node Pool (Optional) ---
module aksGpuNodePool 'modules/compute/aks-nodepool-gpu.bicep' = if (deployGpuNodePool) {
  scope: rg
  name: 'deploy-aks-gpu-nodepool'
  params: {
    aksClusterName: aks.outputs.aksClusterName
    gpuVmSize: gpuNodeVmSize
    aksNodesSubnetId: vnet.outputs.aksNodesSubnetId
  }
}

// --- Monitoring ---
module monitoring 'modules/monitoring/monitoring.bicep' = {
  scope: rg
  name: 'deploy-monitoring'
  params: {
    location: location
    namingPrefix: namingPrefix
    tags: tags
    aksClusterName: aks.outputs.aksClusterName
    keyVaultName: keyVault.outputs.keyVaultName
  }
}

// --- Federated Identity Credentials (Workload Identity) ---
// Creates federated credentials for all QWiser ServiceAccounts
// Required for pods to authenticate to Azure services (Redis, Key Vault, App Config)
// Note: All services must deploy to the same namespace specified by workloadNamespace parameter
module federatedCredentials 'modules/identity/federated-credentials.bicep' = {
  scope: rg
  name: 'deploy-federated-credentials'
  params: {
    managedIdentityName: managedIdentity.outputs.identityName
    aksOidcIssuerUrl: aks.outputs.oidcIssuerUrl
    namespace: workloadNamespace
  }
}

// --- Microsoft Defender for Containers (Subscription Scope) ---
// State-actor threat model: Runtime threat detection, vulnerability scanning
// Ref: https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-for-containers-introduction
resource defenderForContainers 'Microsoft.Security/pricings@2024-01-01' = {
  name: 'Containers'
  properties: {
    pricingTier: 'Standard'
    extensions: [
      {
        name: 'ContainerSensor'
        isEnabled: 'True'
      }
      {
        name: 'ContainerRegistriesVulnerabilityAssessments'
        isEnabled: 'True'
      }
      {
        name: 'AgentlessDiscoveryForKubernetes'
        isEnabled: 'True'
      }
    ]
  }
}

// --- MC_ Resource Group Reader Role (for deploymentScript LB queries) ---
// Note: Uses pre-computed nodeResourceGroupName to avoid Bicep scope limitation
module mcRgReader 'modules/identity/mc-rg-reader.bicep' = {
  scope: resourceGroup(nodeResourceGroupName)
  name: 'deploy-mc-rg-reader-role'
  params: {
    principalId: managedIdentity.outputs.principalId
  }
  dependsOn: [
    aks // MC_ resource group exists only after AKS is created
  ]
}

// ============================================================================
// Phase 2 (continued): Ingress Path - Task 2.7
// ============================================================================
// Architecture: Internet → Front Door (WAF) → PE → PLS → ILB → NGINX Ingress
//
// Deployment sequence:
//   1. deploymentScript: Installs NGINX Ingress via Helm, outputs ILB info
//   2. privateLinkService: Creates PLS pointing to ILB frontend IP
//   3. frontDoor: Creates Front Door Premium with WAF, connects to PLS
//
// Post-deploy requirement:
//   Private Endpoint connection from Front Door must be approved manually
// ============================================================================

// --- NGINX Ingress Controller Installation + ConfigMap ---
module nginxIngress 'modules/compute/deploymentScript.bicep' = {
  scope: rg
  name: 'deploy-nginx-ingress'
  params: {
    location: location
    namingPrefix: namingPrefix
    tags: tags
    aksClusterName: aksClusterName
    aksResourceGroupName: resourceGroupName
    nodeResourceGroupName: nodeResourceGroupName
    nginxIngressPrivateIpAddress: nginxIngressPrivateIp
    managedIdentityId: managedIdentity.outputs.identityId
    // ConfigMap parameters
    appConfigEndpoint: appConfig.outputs.appConfigEndpoint
    configLabel: environmentName == 'staging' ? 'staging' : 'production'
    baseUrl: 'https://${customDomain}'
    acrLoginServer: acr.outputs.acrLoginServer
    workloadNamespace: workloadNamespace
    // K8s manifest substitution parameters (Phase 5)
    uamiClientId: managedIdentity.outputs.clientId
    keyVaultName: keyVault.outputs.keyVaultName
    tenantId: tenant().tenantId
    storageAccountName: storageAccount.outputs.storageAccountName
  }
  dependsOn: [
    mcRgReader // Ensure Reader role on MC_ RG is assigned before script runs
  ]
}

// --- Private Link Service for ILB ---
module privateLinkService 'modules/networking/privateLinkService.bicep' = {
  scope: rg
  name: 'deploy-private-link-service'
  params: {
    location: location
    namingPrefix: namingPrefix
    tags: tags
    peSubnetId: vnet.outputs.peSubnetId
    frontendIpConfigId: nginxIngress.outputs.frontendIpConfigId
  }
}

// --- Azure Front Door Premium with WAF ---
module frontDoor 'modules/networking/frontdoor.bicep' = {
  scope: rg
  name: 'deploy-front-door'
  params: {
    namingPrefix: namingPrefix
    tags: tags
    privateLinkServiceId: privateLinkService.outputs.plsId
    privateLinkServiceLocation: location // PLS is in same region as main deployment
    originPrivateIpAddress: nginxIngressPrivateIp
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    enableWaf: enableWaf
    wafMode: wafMode
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Resource group name')
output resourceGroupName string = rg.name

@description('VNet resource ID')
output vnetId string = vnet.outputs.vnetId

@description('AKS nodes subnet resource ID')
output aksNodesSubnetId string = vnet.outputs.aksNodesSubnetId

@description('Private endpoints subnet resource ID')
output peSubnetId string = vnet.outputs.peSubnetId

@description('Managed identity resource ID')
output managedIdentityId string = managedIdentity.outputs.identityId

@description('Managed identity principal ID')
output managedIdentityPrincipalId string = managedIdentity.outputs.principalId

@description('Managed identity client ID')
output managedIdentityClientId string = managedIdentity.outputs.clientId

@description('Key Vault resource ID')
output keyVaultId string = keyVault.outputs.keyVaultId

@description('Key Vault URI')
output keyVaultUri string = keyVault.outputs.keyVaultUri

@description('Key Vault name')
output keyVaultName string = keyVault.outputs.keyVaultName

@description('App Configuration resource ID')
output appConfigId string = appConfig.outputs.appConfigId

@description('App Configuration name')
output appConfigName string = appConfig.outputs.appConfigName

@description('App Configuration endpoint')
output appConfigEndpoint string = appConfig.outputs.appConfigEndpoint

// --- Phase 2 Outputs ---

@description('Storage account resource ID')
output storageAccountId string = storageAccount.outputs.storageAccountId

@description('Storage account name')
output storageAccountName string = storageAccount.outputs.storageAccountName

@description('ML models file share name')
output mlModelsShareName string = storageAccount.outputs.mlModelsShareName

@description('ACR resource ID')
output acrId string = acr.outputs.acrId

@description('ACR login server')
output acrLoginServer string = acr.outputs.acrLoginServer

@description('MySQL server resource ID')
output mysqlServerId string = mysql.outputs.mysqlServerId

@description('MySQL server FQDN')
output mysqlServerFqdn string = mysql.outputs.mysqlServerFqdn

@description('Redis cluster resource ID')
output redisId string = redis.outputs.redisId

@description('Redis cluster name')
output redisName string = redis.outputs.redisName

@description('Redis host name (use with port 10000)')
output redisHostName string = redis.outputs.redisHostName

@description('AKS cluster resource ID')
output aksClusterId string = aks.outputs.aksClusterId

@description('AKS cluster name')
output aksClusterName string = aks.outputs.aksClusterName

@description('AKS cluster FQDN')
output aksClusterFqdn string = aks.outputs.aksClusterFqdn

@description('AKS OIDC Issuer URL (for federated credentials)')
output oidcIssuerUrl string = aks.outputs.oidcIssuerUrl

@description('AKS kubelet identity object ID')
output kubeletIdentityObjectId string = aks.outputs.kubeletIdentityObjectId

@description('AKS kubelet identity client ID')
output kubeletIdentityClientId string = aks.outputs.kubeletIdentityClientId

@description('AKS node resource group (MC_ resource group)')
output nodeResourceGroup string = aks.outputs.nodeResourceGroup

@description('Log Analytics workspace resource ID')
output logAnalyticsWorkspaceId string = monitoring.outputs.workspaceId

@description('Log Analytics workspace name')
output logAnalyticsWorkspaceName string = monitoring.outputs.workspaceName

@description('Container Insights DCR resource ID')
output containerInsightsDcrId string = monitoring.outputs.dcrId

@description('Application Insights resource ID')
output appInsightsId string = monitoring.outputs.appInsightsId

@description('Application Insights name')
output appInsightsName string = monitoring.outputs.appInsightsName

@description('Application Insights connection string')
output appInsightsConnectionString string = monitoring.outputs.appInsightsConnectionString

// --- Phase 2.7: Ingress Outputs ---

@description('NGINX Ingress internal LoadBalancer IP')
output nginxIngressIp string = nginxIngress.outputs.loadBalancerIp

@description('Private Link Service resource ID')
output privateLinkServiceId string = privateLinkService.outputs.plsId

@description('Private Link Service name')
output privateLinkServiceName string = privateLinkService.outputs.plsName

@description('Front Door profile resource ID')
output frontDoorId string = frontDoor.outputs.frontDoorId

@description('Front Door endpoint hostname (configure CNAME: subdomain.university.edu → this)')
output frontDoorHostname string = frontDoor.outputs.frontDoorEndpointHostname

@description('WAF policy resource ID')
output wafPolicyId string = frontDoor.outputs.wafPolicyId

// --- URL Configuration Outputs ---

@description('DNS CNAME record IT must create (custom domain → Front Door hostname)')
output dnsConfig string = '${customDomain} CNAME ${frontDoor.outputs.frontDoorEndpointHostname}'

@description('Base URL for ConfigMap env vars (PUBLIC_URL, FRONTEND_URL, REACT_APP_SERVER_API_URL)')
output baseUrl string = 'https://${customDomain}'
