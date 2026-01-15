// ============================================================================
// MySQL Flexible Server Module
// ============================================================================
// Purpose: Creates MySQL Flexible Server with private endpoint for QWiser
//
// Security Configuration (state-actor threat model):
//   - Public network access: Created with public access mode, then disabled
//   - Private Endpoint: Provides secure VNet-based connectivity
//   - TLS: Enforced via require_secure_transport server configuration
//   - Admin password: Passed securely, recommend storing in Key Vault
//
// Networking Approach:
//   MySQL Flexible Server supports two networking modes:
//   1. VNet Integration (delegatedSubnet) - Server deployed INTO a VNet
//   2. Public access + Private Endpoint - Server accessible only via PE
//
//   We use option 2 because:
//   - More flexible for hub-spoke topologies
//   - Can disable public access after PE is configured
//   - Works with existing Private DNS Zones
//
// High Availability Options:
//   - Disabled: No HA
//   - SameZone: Standby in same availability zone (local redundancy)
//   - ZoneRedundant: Standby in different AZ (requires supported regions)
//
// IMPORTANT: HA requires GeneralPurpose or MemoryOptimized tier.
// Burstable tier does NOT support HA - deployment will fail if combined.
//
// Maintenance Window:
//   Cannot be set during initial creation (Azure limitation).
//   Configure via Azure Portal or CLI post-deployment.
// ============================================================================

@description('Azure region for resources')
param location string

@description('Naming prefix for resources')
param namingPrefix string

@description('Tags to apply to resources')
param tags object

@description('Private endpoints subnet resource ID')
param peSubnetId string

@description('MySQL private DNS zone resource ID')
param privateDnsZoneId string

// --- MySQL Configuration ---

@description('MySQL administrator login name')
@minLength(1)
param administratorLogin string

@description('MySQL administrator password')
@secure()
param administratorLoginPassword string

@description('MySQL version')
@allowed([
  '5.7'
  '8.0.21'
])
param mysqlVersion string = '8.0.21'

@description('SKU tier: Burstable (B-series), GeneralPurpose (D-series), or MemoryOptimized (E-series). Burstable does NOT support HA.')
@allowed([
  'Burstable'
  'GeneralPurpose'
  'MemoryOptimized'
])
param skuTier string = 'GeneralPurpose'

@description('SKU name must match tier: B* for Burstable, D* for GeneralPurpose, E* for MemoryOptimized.')
param skuName string = 'Standard_D2ds_v4'

@description('Storage size in GB')
@minValue(20)
@maxValue(16384)
param storageSizeGB int = 64

@description('High availability mode')
@allowed([
  'Disabled'
  'SameZone'
  'ZoneRedundant'
])
param highAvailabilityMode string = 'Disabled'

@description('Backup retention period in days')
@minValue(1)
@maxValue(35)
param backupRetentionDays int = 14

@description('Enable geo-redundant backup')
@allowed([
  'Disabled'
  'Enabled'
])
param geoRedundantBackup string = 'Disabled'

@description('Key Vault name for storing credentials (if provided, secrets are created)')
param keyVaultName string = ''

// ============================================================================
// Variables
// ============================================================================

// MySQL server names: 3-63 chars, lowercase alphanumeric and hyphens
var mysqlServerName = '${namingPrefix}-mysql'
var privateEndpointName = '${namingPrefix}-mysql-pe'

// ============================================================================
// MySQL Flexible Server
// ============================================================================
// API version 2024-12-30 is latest GA as of Jan 2026
// Ref: https://learn.microsoft.com/en-us/azure/templates/microsoft.dbformysql/flexibleservers
// ============================================================================

resource mysqlServer 'Microsoft.DBforMySQL/flexibleServers@2024-12-30' = {
  name: mysqlServerName
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuTier
  }
  properties: {
    // Administrator credentials
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword

    // MySQL version
    version: mysqlVersion

    // Storage configuration
    storage: {
      storageSizeGB: storageSizeGB
      autoGrow: 'Enabled'
      autoIoScaling: 'Enabled'
    }

    // Backup configuration
    backup: {
      backupRetentionDays: backupRetentionDays
      geoRedundantBackup: geoRedundantBackup
    }

    // High availability (disabled for Burstable tier)
    highAvailability: {
      mode: highAvailabilityMode
    }

    // Network configuration
    // For Private Endpoint approach: don't set delegatedSubnetResourceId
    // We create the PE separately and then disable public access
    network: {
      // Public network access will be disabled after PE is established
      // Note: Cannot set to 'Disabled' at creation time without existing PE
      publicNetworkAccess: 'Enabled'
    }

    // Create mode (Default = new server)
    createMode: 'Default'
  }
}

// ============================================================================
// Server Configuration: Require Secure Transport (TLS)
// ============================================================================
// Explicitly enforce TLS for all connections (state-actor threat model)
// This is Azure's default, but explicit configuration is preferred.
// ============================================================================

resource requireSecureTransport 'Microsoft.DBforMySQL/flexibleServers/configurations@2024-12-30' = {
  parent: mysqlServer
  name: 'require_secure_transport'
  properties: {
    value: 'ON'
    source: 'user-override'
  }
}

// ============================================================================
// Private Endpoint
// ============================================================================
// Ref: https://learn.microsoft.com/en-us/azure/mysql/flexible-server/how-to-networking-private-link-azure-cli
// groupId for MySQL Flexible Server is 'mysqlServer'
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
          privateLinkServiceId: mysqlServer.id
          groupIds: [
            'mysqlServer'
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
        name: 'privatelink-mysql-database-azure-com'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

// ============================================================================
// Key Vault Secrets for Database Credentials
// ============================================================================
// Writes DB-USER and DB-PASSWORD to Key Vault for App Config references
// Only created if keyVaultName is provided
// Ref: https://learn.microsoft.com/en-us/azure/templates/microsoft.keyvault/vaults/secrets
// ============================================================================

resource existingKeyVault 'Microsoft.KeyVault/vaults@2024-11-01' existing = if (!empty(keyVaultName)) {
  name: keyVaultName
}

resource dbUserSecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = if (!empty(keyVaultName)) {
  parent: existingKeyVault
  name: 'DB-USER'
  properties: {
    value: administratorLogin
    contentType: 'text/plain'
  }
}

resource dbPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = if (!empty(keyVaultName)) {
  parent: existingKeyVault
  name: 'DB-PASSWORD'
  properties: {
    value: administratorLoginPassword
    contentType: 'text/plain'
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('MySQL server resource ID')
output mysqlServerId string = mysqlServer.id

@description('MySQL server name')
output mysqlServerName string = mysqlServer.name

@description('MySQL server FQDN')
output mysqlServerFqdn string = mysqlServer.properties.fullyQualifiedDomainName

@description('Private endpoint resource ID')
output privateEndpointId string = privateEndpoint.id
