// ============================================================================
// Azure Kubernetes Service (AKS) Module
// ============================================================================
// Purpose: Creates AKS cluster with Azure CNI Overlay and Cilium for QWiser
//
// Security Configuration (state-actor threat model):
//   - Azure CNI Overlay with Cilium network policies
//   - Workload Identity enabled for Entra ID pod authentication
//   - Key Vault Secrets Provider add-on for CSI secret mounting
//   - API server: Private cluster OR authorized IP ranges (configurable)
//   - Azure Linux OS (minimal attack surface)
//
// Network Configuration:
//   - networkPlugin: 'azure'
//   - networkPluginMode: 'overlay'
//   - networkDataplane: 'cilium'
//   - networkPolicy: 'cilium'
//   - Pod CIDR: 192.168.0.0/16 (configurable - verify no overlap with on-prem)
//
// Node Pool:
//   - System node pool with Azure Linux
//   - x86_64/amd64 architecture ONLY (Nuitka-compiled binaries)
//   - GPU node pool deployed separately via aks-nodepool-gpu.bicep
//
// IMPORTANT: HA requires GeneralPurpose or MemoryOptimized tier.
// Burstable tier does NOT support HA - deployment will fail if combined.
// ============================================================================

@description('Azure region for resources')
param location string

@description('Naming prefix for resources')
param namingPrefix string

@description('Tags to apply to resources')
param tags object

@description('AKS nodes subnet resource ID')
param aksNodesSubnetId string

@description('User-assigned managed identity resource ID for AKS control plane')
param managedIdentityId string

@description('User-assigned managed identity principal ID (for role assignments)')
param managedIdentityPrincipalId string

@description('AKS private DNS zone resource ID (required for private cluster mode)')
param aksDnsZoneId string = ''

@description('Container Registry resource ID for AcrPull role assignment')
param acrId string

// --- Kubernetes Configuration ---

@description('Kubernetes version (leave empty for latest stable)')
param kubernetesVersion string = ''

@description('Enable private cluster mode (API server not publicly accessible)')
param enablePrivateCluster bool = true

@description('Authorized IP ranges for API server access (ignored if privateCluster is true)')
param authorizedIPRanges array = []

@description('Disable public FQDN for private cluster')
param disablePublicFqdn bool = true

// --- System Node Pool Configuration ---

@description('System node pool VM size')
param systemNodeVmSize string = 'Standard_D4s_v5'

@description('System node pool node count')
@minValue(1)
@maxValue(100)
param systemNodeCount int = 3

@description('System node pool min count for autoscaling')
@minValue(1)
param systemNodeMinCount int = 2

@description('System node pool max count for autoscaling')
@minValue(1)
param systemNodeMaxCount int = 10

@description('Enable cluster autoscaler for system node pool')
param enableAutoScaling bool = true

@description('System node pool availability zones. Empty array = no zone pinning (works in all regions).')
param availabilityZones array = []

// --- Network Configuration ---

@description('Pod CIDR for Azure CNI Overlay. WARNING: Verify no overlap with on-prem networks.')
param podCidr string = '192.168.0.0/16'

@description('Service CIDR for Kubernetes services')
param serviceCidr string = '10.100.0.0/16'

@description('DNS service IP (must be within serviceCidr)')
param dnsServiceIP string = '10.100.0.10'

// ============================================================================
// Variables
// ============================================================================

// AKS cluster names: 1-63 chars, alphanumeric, underscores, and hyphens
var aksClusterName = '${namingPrefix}-aks'

// ============================================================================
// Azure Kubernetes Service
// ============================================================================
// API version 2025-09-01 is latest GA as of Jan 2026
// Ref: https://learn.microsoft.com/en-us/azure/templates/microsoft.containerservice/managedclusters
// ============================================================================

resource aksCluster 'Microsoft.ContainerService/managedClusters@2025-09-01' = {
  name: aksClusterName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    // Kubernetes version (null = latest stable)
    kubernetesVersion: !empty(kubernetesVersion) ? kubernetesVersion : null

    // DNS prefix for the cluster
    dnsPrefix: aksClusterName

    // Enable OIDC Issuer for Workload Identity
    oidcIssuerProfile: {
      enabled: true
    }

    // Workload Identity for Entra ID pod authentication
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }

    // API Server Access Configuration
    apiServerAccessProfile: {
      enablePrivateCluster: enablePrivateCluster
      // For private cluster: use pre-created DNS zone, not 'System'
      privateDNSZone: enablePrivateCluster ? aksDnsZoneId : null
      // For public cluster with authorized IPs
      authorizedIPRanges: !enablePrivateCluster && !empty(authorizedIPRanges) ? authorizedIPRanges : null
      // Disable public FQDN for private clusters
      enablePrivateClusterPublicFQDN: enablePrivateCluster ? !disablePublicFqdn : null
    }

    // Network Profile: Azure CNI Overlay with Cilium
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkDataplane: 'cilium'
      networkPolicy: 'cilium'
      podCidr: podCidr
      serviceCidr: serviceCidr
      dnsServiceIP: dnsServiceIP
      loadBalancerSku: 'standard'
    }

    // Add-on Profiles
    addonProfiles: {
      // Key Vault Secrets Provider (CSI Driver for secret mounting)
      azureKeyvaultSecretsProvider: {
        enabled: true
        config: {
          enableSecretRotation: 'true'
          rotationPollInterval: '2m'
        }
      }
    }

    // System Node Pool
    agentPoolProfiles: [
      {
        name: 'system'
        mode: 'System'
        vmSize: systemNodeVmSize
        count: systemNodeCount
        minCount: enableAutoScaling ? systemNodeMinCount : null
        maxCount: enableAutoScaling ? systemNodeMaxCount : null
        enableAutoScaling: enableAutoScaling
        availabilityZones: !empty(availabilityZones) ? availabilityZones : null
        vnetSubnetID: aksNodesSubnetId
        // Azure Linux 3 (AzureLinux on AKS 1.32+ defaults to v3)
        osSKU: 'AzureLinux'
        osType: 'Linux'
        // Taints for system node pool
        nodeTaints: [
          'CriticalAddonsOnly=true:NoSchedule'
        ]
        // Node labels
        nodeLabels: {
          'nodepool-type': 'system'
        }
        // Upgrade settings
        upgradeSettings: {
          maxSurge: '33%'
        }
      }
    ]

    // Auto-upgrade channel
    autoUpgradeProfile: {
      upgradeChannel: 'stable'
      nodeOSUpgradeChannel: 'NodeImage'
    }
  }
}

// ============================================================================
// User Node Pool (for application workloads)
// ============================================================================
// Separate from system pool to avoid CriticalAddonsOnly taint
// ============================================================================

resource userNodePool 'Microsoft.ContainerService/managedClusters/agentPools@2025-09-01' = {
  parent: aksCluster
  name: 'user'
  properties: {
    mode: 'User'
    vmSize: systemNodeVmSize
    count: systemNodeCount
    minCount: enableAutoScaling ? systemNodeMinCount : null
    maxCount: enableAutoScaling ? systemNodeMaxCount : null
    enableAutoScaling: enableAutoScaling
    availabilityZones: !empty(availabilityZones) ? availabilityZones : null
    vnetSubnetID: aksNodesSubnetId
    osSKU: 'AzureLinux'
    osType: 'Linux'
    nodeLabels: {
      'nodepool-type': 'user'
    }
    upgradeSettings: {
      maxSurge: '33%'
    }
  }
}

// ============================================================================
// AcrPull Role Assignment for Kubelet Identity
// ============================================================================
// The kubelet identity (not cluster identity) needs AcrPull role to pull images
// ============================================================================

// Built-in role: AcrPull (7f951dda-4ed3-4680-a7ca-43fe172d538d)
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aksCluster.id, acrId, acrPullRoleId)
  scope: resourceGroup()
  properties: {
    principalId: aksCluster.properties.identityProfile.kubeletidentity.objectId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// Contributor Role Assignment for AKS Command Invoke
// ============================================================================
// Required for deploymentScript to run `az aks command invoke`
//
// IMPORTANT: The built-in "Azure Kubernetes Service Cluster Admin Role" does NOT
// include the `Microsoft.ContainerService/managedClusters/commandResults/read`
// permission required to retrieve command results. This is a known Azure issue:
// https://github.com/Azure/AKS/issues/3462
//
// `az aks command invoke` requires BOTH:
//   - Microsoft.ContainerService/managedClusters/runCommand/action
//   - Microsoft.ContainerService/managedClusters/commandResults/read
//
// Solution: Use Contributor role scoped ONLY to the AKS cluster resource.
// This is minimal privilege for the specific resource while providing all
// required permissions.
// ============================================================================

// Built-in role: Contributor (b24988ac-6180-42a0-ab88-20f7382dd24c)
var contributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'

resource aksContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aksCluster.id, managedIdentityPrincipalId, contributorRoleId)
  scope: aksCluster
  properties: {
    principalId: managedIdentityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleId)
    principalType: 'ServicePrincipal'
    description: 'Allow managed identity to run az aks command invoke (requires runCommand + commandResults/read)'
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('AKS cluster resource ID')
output aksClusterId string = aksCluster.id

@description('AKS cluster name')
output aksClusterName string = aksCluster.name

@description('AKS cluster FQDN (for public clusters) or private FQDN')
output aksClusterFqdn string = enablePrivateCluster ? aksCluster.properties.privateFQDN : aksCluster.properties.fqdn

@description('AKS OIDC Issuer URL (for federated credentials)')
output oidcIssuerUrl string = aksCluster.properties.oidcIssuerProfile.issuerURL

@description('AKS kubelet identity object ID')
output kubeletIdentityObjectId string = aksCluster.properties.identityProfile.kubeletidentity.objectId

@description('AKS kubelet identity client ID')
output kubeletIdentityClientId string = aksCluster.properties.identityProfile.kubeletidentity.clientId

@description('Managed cluster resource group (MC_ resource group)')
output nodeResourceGroup string = aksCluster.properties.nodeResourceGroup
