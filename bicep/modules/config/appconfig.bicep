// ============================================================================
// App Configuration Module
// ============================================================================
// Purpose: Creates App Configuration store with private endpoint
//
// Security Configuration (state-actor threat model):
//   - publicNetworkAccess: Disabled (all access via Private Endpoint)
//   - disableLocalAuth: true (Entra ID only, no access keys)
//
// Configuration stored (seeded by post-deploy scripts):
//   - environment, logging:level
//   - db:*, redis:*, qdrant:*
//   - azure:storage:*, azure:applicationinsights_connection_string
//   - ai:* (model endpoints, API keys as KV refs)
//   - params:* (feature configuration)
//   - lti:* (LTI platform config)
//   - sentinel (config refresh trigger)
//
// Key Vault References:
//   - Secrets are stored as KV references in App Config
//   - Format: {"uri": "https://{kv}.vault.azure.net/secrets/{name}"}
//   - App Config SDK automatically resolves KV references
//
// Role Assignments:
//   - App Configuration Data Reader to workload identity
// ============================================================================

@description('Azure region for resources')
param location string

@description('Naming prefix for resources')
param namingPrefix string

@description('Tags to apply to resources')
param tags object

@description('Private endpoints subnet resource ID')
param peSubnetId string

@description('App Configuration private DNS zone resource ID')
param privateDnsZoneId string

@description('Workload identity principal ID (for Data Reader role)')
param workloadIdentityPrincipalId string

@description('Enable purge protection. Disable for test/dev to allow easy cleanup.')
param enablePurgeProtection bool = true

// ============================================================================
// Variables
// ============================================================================

// App Config names must be globally unique, 5-50 chars
var appConfigName = '${namingPrefix}-appconfig'
var privateEndpointName = '${namingPrefix}-appconfig-pe'

// Built-in role definition IDs
var appConfigDataReaderRoleId = '516239f1-63e1-4d78-a4de-a74fb236a071'

// ============================================================================
// App Configuration Store
// ============================================================================
// API version 2024-05-01 is latest GA as of Jan 2026
// Ref: https://learn.microsoft.com/en-us/azure/templates/microsoft.appconfiguration/configurationstores
// ============================================================================

resource appConfig 'Microsoft.AppConfiguration/configurationStores@2024-05-01' = {
  name: appConfigName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    // Security: Disable public network access (Private Endpoint only)
    publicNetworkAccess: 'Disabled'

    // Security: Disable local auth (Entra ID only, no access keys)
    // All access must use Managed Identity or Azure AD authentication
    disableLocalAuth: true

    // Purge protection (prevents permanent deletion) - disable for test/dev
    enablePurgeProtection: enablePurgeProtection

    // Soft delete retention (default 7 days for Standard SKU)
    softDeleteRetentionInDays: 7
  }
}

// ============================================================================
// Private Endpoint
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
          privateLinkServiceId: appConfig.id
          groupIds: [
            'configurationStores'
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
        name: 'privatelink-azconfig-io'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

// ============================================================================
// Role Assignment - App Configuration Data Reader
// ============================================================================
// Allows workload identity to read configuration at runtime
// This is a data-plane role (not management plane)
// ============================================================================

resource dataReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(appConfig.id, workloadIdentityPrincipalId, appConfigDataReaderRoleId)
  scope: appConfig
  properties: {
    principalId: workloadIdentityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', appConfigDataReaderRoleId)
    principalType: 'ServicePrincipal'
    description: 'Allow workload identity to read configuration from App Configuration'
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('App Configuration resource ID')
output appConfigId string = appConfig.id

@description('App Configuration name')
output appConfigName string = appConfig.name

@description('App Configuration endpoint (for AZURE_APP_CONFIG_ENDPOINT env var)')
output appConfigEndpoint string = appConfig.properties.endpoint

@description('Private endpoint resource ID')
output privateEndpointId string = privateEndpoint.id
