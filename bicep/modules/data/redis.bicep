// ============================================================================
// Azure Managed Redis Module
// ============================================================================
// Purpose: Creates Azure Managed Redis (Redis Enterprise) with private endpoint
//
// Security Configuration (state-actor threat model):
//   - publicNetworkAccess: Disabled (Private Endpoint only)
//   - minimumTlsVersion: 1.2
//   - clientProtocol: Encrypted
//   - accessKeysAuthentication: Disabled (Entra ID auth only)
//
// Architecture:
//   - Redis Enterprise cluster (Microsoft.Cache/redisEnterprise)
//   - Default database (Microsoft.Cache/redisEnterprise/databases)
//   - Private Endpoint with groupId 'redisEnterprise'
//
// Authentication:
//   Per university deployment requirements, uses Entra ID authentication
//   via redis-entraid package. Access keys are disabled.
//
// Connection:
//   - Endpoint: <cachename>.<region>.redis.azure.net:10000
//   - DNS Zone: privatelink.redis.azure.net
// ============================================================================

@description('Azure region for resources')
param location string

@description('Naming prefix for resources')
param namingPrefix string

@description('Tags to apply to resources')
param tags object

@description('Private endpoints subnet resource ID')
param peSubnetId string

@description('Redis private DNS zone resource ID')
param privateDnsZoneId string

// --- Redis Configuration ---

@description('Redis SKU name. Balanced tier recommended for standard workloads. Size suffix indicates approximate memory (B1=1GB, B5=5GB, B10=10GB, B20=20GB).')
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
param skuName string = 'Balanced_B5'

@description('Enable high availability (data replication)')
@allowed([
  'Enabled'
  'Disabled'
])
param highAvailability string = 'Enabled'

@description('Availability zones for zone redundancy')
param zones array = []

@description('Redis database eviction policy')
@allowed([
  'NoEviction'
  'AllKeysLRU'
  'AllKeysLFU'
  'AllKeysRandom'
  'VolatileLRU'
  'VolatileLFU'
  'VolatileRandom'
  'VolatileTTL'
])
param evictionPolicy string = 'VolatileLRU'
param clusteringPolicy string = 'EnterpriseCluster'

@description('Workload Identity principal ID for data-plane access')
param workloadIdentityPrincipalId string

// ============================================================================
// Variables
// ============================================================================

// Redis Enterprise names: 1-60 chars, alphanumeric and hyphens
var redisName = '${namingPrefix}-redis'
var privateEndpointName = '${namingPrefix}-redis-pe'

// Built-in role: Redis Cache Data Contributor
// Ref: https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/databases#redis-cache-data-contributor
var redisCacheDataContributorRoleId = 'e0b5f6ed-0a0c-48d4-a5c1-db94bb34d5ed'

// ============================================================================
// Azure Managed Redis (Redis Enterprise)
// ============================================================================
// API version 2025-07-01 is latest GA as of Jan 2026
// Ref: https://learn.microsoft.com/en-us/azure/templates/microsoft.cache/redisenterprise
// ============================================================================

resource redisEnterprise 'Microsoft.Cache/redisEnterprise@2025-07-01' = {
  name: redisName
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  zones: !empty(zones) ? zones : null
  properties: {
    // Security: Minimum TLS 1.2
    minimumTlsVersion: '1.2'

    // Security: Disable public network access (Private Endpoint only)
    publicNetworkAccess: 'Disabled'

    // High availability for data replication
    highAvailability: highAvailability
  }
}

// ============================================================================
// Redis Database
// ============================================================================
// The database is a child resource of the Redis Enterprise cluster
// ============================================================================

resource redisDatabase 'Microsoft.Cache/redisEnterprise/databases@2025-07-01' = {
  parent: redisEnterprise
  name: 'default'
  properties: {
    // Security: Require TLS for client connections
    clientProtocol: 'Encrypted'

    // Security: Disable access key authentication (use Entra ID)
    accessKeysAuthentication: 'Disabled'

    // Port for Redis connections (Azure Managed Redis standard)
    port: 10000

    // Clustering policy
    clusteringPolicy: clusteringPolicy

    // Eviction policy when memory is full
    evictionPolicy: evictionPolicy

    // Persistence disabled by default (can be enabled if needed)
    persistence: {
      aofEnabled: false
      rdbEnabled: false
    }
  }
}

// ============================================================================
// Private Endpoint
// ============================================================================
// groupId for Azure Managed Redis is 'redisEnterprise'
// Ref: https://learn.microsoft.com/en-us/azure/redis/private-link
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
          privateLinkServiceId: redisEnterprise.id
          groupIds: [
            'redisEnterprise'
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
        name: 'privatelink-redis-azure-net'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

// ============================================================================
// Data-Plane Role Assignment for Workload Identity
// ============================================================================
// Pods using Workload Identity need Redis Cache Data Contributor role
// to authenticate via Entra ID (access keys are disabled)
// ============================================================================

resource dataContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(redisEnterprise.id, workloadIdentityPrincipalId, redisCacheDataContributorRoleId)
  scope: redisEnterprise
  properties: {
    principalId: workloadIdentityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', redisCacheDataContributorRoleId)
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Redis Enterprise cluster resource ID')
output redisId string = redisEnterprise.id

@description('Redis Enterprise cluster name')
output redisName string = redisEnterprise.name

@description('Redis host name (use with port 10000)')
output redisHostName string = redisEnterprise.properties.hostName

@description('Redis database resource ID')
output redisDatabaseId string = redisDatabase.id

@description('Private endpoint resource ID')
output privateEndpointId string = privateEndpoint.id
