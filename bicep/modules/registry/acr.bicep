// ============================================================================
// Azure Container Registry Module
// ============================================================================
// Purpose: Creates Premium ACR with private endpoint for container image storage
//
// Security Configuration (state-actor threat model):
//   - publicNetworkAccess: Disabled (all access via Private Endpoint)
//   - networkRuleSet.defaultAction: Deny
//   - Premium SKU required for private endpoint support
//   - Anonymous pull disabled
//
// Image Import Strategy:
//   - IT imports images from source ACR (qwiser.azurecr.io) using az acr import
//   - No imagePullSecrets needed - AKS uses AcrPull role assignment
//
// AcrPull Role Assignment:
//   - NOT created in this module (kubelet identity doesn't exist yet)
//   - Created in AKS module after cluster deployment
//   - Role target: AKS kubelet identity (identityProfile.kubeletidentity.objectId)
// ============================================================================

@description('Azure region for resources')
param location string

@description('Naming prefix for resources')
param namingPrefix string

@description('Tags to apply to resources')
param tags object

@description('Private endpoints subnet resource ID')
param peSubnetId string

@description('ACR private DNS zone resource ID')
param privateDnsZoneId string

// ============================================================================
// Variables
// ============================================================================

// ACR names must be globally unique, 5-50 chars, alphanumeric only
// Remove hyphens from naming prefix for ACR name
var acrName = toLower(replace('${namingPrefix}acr', '-', ''))
var privateEndpointName = '${namingPrefix}-acr-pe'

// ============================================================================
// Azure Container Registry
// ============================================================================
// API version 2025-04-01 is latest GA as of Jan 2026
// Ref: https://learn.microsoft.com/en-us/azure/templates/microsoft.containerregistry/registries
// ============================================================================

resource acr 'Microsoft.ContainerRegistry/registries@2025-04-01' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: 'Premium'  // Required for private endpoint support
  }
  properties: {
    // Security: Disable public network access (Private Endpoint only)
    publicNetworkAccess: 'Disabled'

    // Security: Deny all public network access by default
    networkRuleSet: {
      defaultAction: 'Deny'
      ipRules: []
    }

    // Security: Disable anonymous pull (require authentication)
    anonymousPullEnabled: false

    // Security: Disable admin user (use managed identity instead)
    adminUserEnabled: false

    // Enable zone redundancy for high availability (Premium feature)
    zoneRedundancy: 'Disabled'  // Can be enabled if region supports it

    // Data endpoint for improved pull performance (Premium feature)
    dataEndpointEnabled: false
  }
}

// ============================================================================
// Private Endpoint
// ============================================================================
// Ref: https://learn.microsoft.com/en-us/azure/container-registry/container-registry-private-link
// groupId for ACR is 'registry'
// ============================================================================

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: privateEndpointName
  location: location
  tags: tags
  properties: {
    subnet: {
      id: peSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${privateEndpointName}-connection'
        properties: {
          privateLinkServiceId: acr.id
          groupIds: [
            'registry'
          ]
        }
      }
    ]
  }
}

// ============================================================================
// Private DNS Zone Group
// ============================================================================

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-azurecr-io'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('ACR resource ID')
output acrId string = acr.id

@description('ACR name')
output acrName string = acr.name

@description('ACR login server (e.g., myacr.azurecr.io)')
output acrLoginServer string = acr.properties.loginServer

@description('Private endpoint resource ID')
output privateEndpointId string = privateEndpoint.id
