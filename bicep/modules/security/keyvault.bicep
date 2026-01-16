// ============================================================================
// Key Vault Module
// ============================================================================
// Purpose: Creates Key Vault with private endpoint for secret management
//
// Security Configuration (state-actor threat model):
//   - publicNetworkAccess: Disabled (all access via Private Endpoint)
//   - enableRbacAuthorization: true (RBAC instead of access policies)
//   - Soft delete: enabled (Azure default, 90 days)
//   - Purge protection: enabled (prevents permanent deletion)
//
// Secrets stored (seeded by post-deploy scripts):
//   - DB-PASSWORD, DB-USER
//   - JWT-SECRET, INTERNAL-SECRET-KEY
//   - AI-FOUNDRY-API-KEY
//   - LTI-PRIVATE-KEY
//   - QDRANT-API-KEY
//   - STORAGE-ACCOUNT-KEY, STORAGE-CONNECTION-STRING
//   - APPLICATIONINSIGHTS-CONNECTION-STRING
//
// Role Assignments:
//   - Key Vault Secrets User to workload identity (for runtime secret access)
// ============================================================================

@description('Azure region for resources')
param location string

@description('Naming prefix for resources')
param namingPrefix string

@description('Unique suffix for globally unique Key Vault name')
param uniqueSuffix string

@description('Tags to apply to resources')
param tags object

@description('Private endpoints subnet resource ID')
param peSubnetId string

@description('Key Vault private DNS zone resource ID')
param privateDnsZoneId string

@description('Workload identity principal ID (for Secrets User role)')
param workloadIdentityPrincipalId string

@description('Soft delete retention in days (7-90)')
@minValue(7)
@maxValue(90)
param softDeleteRetentionInDays int = 90

// ============================================================================
// Variables
// ============================================================================

// Key Vault names must be globally unique, 3-24 chars, alphanumeric + hyphens
var keyVaultName = '${namingPrefix}-kv-${uniqueSuffix}'
var privateEndpointName = '${namingPrefix}-kv-pe'

// Built-in role definition IDs
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

// ============================================================================
// Key Vault
// ============================================================================
// API version 2024-11-01 is latest GA as of Jan 2026
// Ref: https://learn.microsoft.com/en-us/azure/templates/microsoft.keyvault/vaults
// ============================================================================

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }

    // Security: Use RBAC instead of access policies
    enableRbacAuthorization: true

    // Security: Disable public network access (Private Endpoint only)
    publicNetworkAccess: 'Disabled'

    // Security: Enable soft delete (prevents accidental deletion)
    enableSoftDelete: true
    softDeleteRetentionInDays: softDeleteRetentionInDays

    // Security: Enable purge protection (prevents malicious permanent deletion)
    // Note: Cannot be disabled once enabled; KV uses random suffix so name conflicts aren't an issue
    enablePurgeProtection: true

    // Network configuration (deny all public access)
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

// ============================================================================
// Private Endpoint
// ============================================================================
// API version 2024-05-01 is latest GA as of Jan 2026
// Ref: https://learn.microsoft.com/en-us/azure/templates/microsoft.network/privateendpoints
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
          privateLinkServiceId: keyVault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
}

// ============================================================================
// Private DNS Zone Group
// ============================================================================
// Automatically creates A record in the private DNS zone for the PE
// ============================================================================

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-vaultcore-azure-net'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

// ============================================================================
// Role Assignment - Key Vault Secrets User
// ============================================================================
// Allows workload identity to read secrets at runtime
// This is a data-plane role (not management plane)
// ============================================================================

resource secretsUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, workloadIdentityPrincipalId, keyVaultSecretsUserRoleId)
  scope: keyVault
  properties: {
    principalId: workloadIdentityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalType: 'ServicePrincipal'
    description: 'Allow workload identity to read secrets from Key Vault'
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Key Vault resource ID')
output keyVaultId string = keyVault.id

@description('Key Vault name')
output keyVaultName string = keyVault.name

@description('Key Vault URI (for App Config references)')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Private endpoint resource ID')
output privateEndpointId string = privateEndpoint.id
