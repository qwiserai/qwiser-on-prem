// ============================================================================
// Managed Identity Module
// ============================================================================
// Purpose: Creates User-Assigned Managed Identity for AKS and workloads
//
// This identity is used for:
//   - AKS cluster identity (control plane operations)
//   - Workload Identity (pod-level Azure authentication)
//   - Creating/managing Internal Load Balancer
//   - Creating/managing Private Link Service
//
// Role Assignments (created in this module):
//   - Network Contributor on AKS nodes subnet (for ILB operations)
//   - Network Contributor on PE subnet (for PLS NAT IP allocation)
//
// Additional roles assigned by other modules:
//   - Key Vault Secrets User (keyvault.bicep)
//   - App Configuration Data Reader (appconfig.bicep)
//   - Private DNS Zone Contributor (Phase 2, for AKS private cluster)
//   - Redis Data Owner (Phase 2, redis.bicep)
//   - AcrPull (Phase 2, aks.bicep - assigned to kubelet identity after cluster creation)
// ============================================================================

@description('Azure region for resources')
param location string

@description('Naming prefix for resources')
param namingPrefix string

@description('Tags to apply to resources')
param tags object

@description('AKS nodes subnet resource ID (for Network Contributor role)')
param aksNodesSubnetId string

@description('Private endpoints subnet resource ID (for Network Contributor role)')
param peSubnetId string

@description('AKS private DNS zone resource ID (for Private DNS Zone Contributor role)')
param aksDnsZoneId string

// ============================================================================
// Variables
// ============================================================================

var identityName = '${namingPrefix}-identity'

// Built-in role definition IDs
// Ref: https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles
var networkContributorRoleId = '4d97b98b-1d4f-4787-a291-c67834d212e7'
var privateDnsZoneContributorRoleId = 'b12aa53e-6015-4669-85d0-8515ebb3ae7f'

// ============================================================================
// User-Assigned Managed Identity
// ============================================================================
// API version 2024-11-30 is latest GA as of Jan 2026
// Ref: https://learn.microsoft.com/en-us/azure/templates/microsoft.managedidentity/userassignedidentities
// ============================================================================

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: identityName
  location: location
  tags: tags
}

// ============================================================================
// Role Assignments - Network Contributor
// ============================================================================
// Required for AKS to:
//   - Create Internal Load Balancer in AKS nodes subnet
//   - Allocate NAT IPs for Private Link Service in PE subnet
//
// Note: Role assignment names must be GUIDs and be deterministic for idempotency
// ============================================================================

// Network Contributor on AKS nodes subnet
resource aksSubnetNetworkContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(managedIdentity.id, aksNodesSubnetId, networkContributorRoleId)
  scope: aksNodesSubnet
  properties: {
    principalId: managedIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', networkContributorRoleId)
    principalType: 'ServicePrincipal'
    description: 'Allow managed identity to manage ILB in AKS nodes subnet'
  }
}

// Network Contributor on PE subnet (for PLS NAT IP allocation)
resource peSubnetNetworkContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(managedIdentity.id, peSubnetId, networkContributorRoleId)
  scope: peSubnet
  properties: {
    principalId: managedIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', networkContributorRoleId)
    principalType: 'ServicePrincipal'
    description: 'Allow managed identity to allocate PLS NAT IPs in PE subnet'
  }
}

// ============================================================================
// Role Assignment - Private DNS Zone Contributor
// ============================================================================
// Required for AKS private cluster to auto-register API server DNS record
// in the private DNS zone during cluster creation.
// Without this role, AKS private cluster deployment will fail.
// ============================================================================

resource aksDnsZoneContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(managedIdentity.id, aksDnsZoneId, privateDnsZoneContributorRoleId)
  scope: aksDnsZone
  properties: {
    principalId: managedIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', privateDnsZoneContributorRoleId)
    principalType: 'ServicePrincipal'
    description: 'Allow managed identity to manage DNS records in AKS private DNS zone'
  }
}

// ============================================================================
// Existing Resources (for scoping role assignments)
// ============================================================================

resource aksNodesSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  name: last(split(aksNodesSubnetId, '/'))!
  parent: aksVnet
}

resource peSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  name: last(split(peSubnetId, '/'))!
  parent: peVnet
}

// Extract VNet name from subnet ID
// Subnet ID format: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Network/virtualNetworks/{vnet}/subnets/{subnet}
var aksVnetName = split(aksNodesSubnetId, '/')[8]
var peVnetName = split(peSubnetId, '/')[8]

resource aksVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: aksVnetName
}

resource peVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: peVnetName
}

// Extract DNS zone name from zone ID
// Zone ID format: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Network/privateDnsZones/{zoneName}
var aksDnsZoneName = last(split(aksDnsZoneId, '/'))!

resource aksDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: aksDnsZoneName
}

// ============================================================================
// Outputs
// ============================================================================

@description('Managed identity resource ID')
output identityId string = managedIdentity.id

@description('Managed identity principal ID (object ID)')
output principalId string = managedIdentity.properties.principalId

@description('Managed identity client ID (application ID)')
output clientId string = managedIdentity.properties.clientId

@description('Managed identity name')
output identityName string = managedIdentity.name
