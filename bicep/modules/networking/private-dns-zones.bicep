// ============================================================================
// Private DNS Zones Module
// ============================================================================
// Purpose: Creates all private DNS zones required for Private Link connectivity
//
// Zones created (9 total):
//   1. privatelink.mysql.database.azure.com     - MySQL Flexible Server
//   2. privatelink.redis.azure.net              - Azure Managed Redis
//   3. privatelink.vaultcore.azure.net          - Key Vault
//   4. privatelink.azconfig.io                  - App Configuration
//   5. privatelink.blob.core.windows.net        - Blob Storage
//   6. privatelink.queue.core.windows.net       - Queue Storage
//   7. privatelink.file.core.windows.net        - Azure Files
//   8. privatelink.{region}.azmk8s.io           - AKS Private Cluster API
//   9. privatelink.azurecr.io                   - Azure Container Registry
//
// Each zone is linked to the VNet for name resolution.
// ============================================================================

@description('Azure region (used for AKS private DNS zone name)')
param location string

@description('VNet resource ID to link DNS zones to')
param vnetId string

@description('Tags to apply to resources')
param tags object

// ============================================================================
// Private DNS Zones
// ============================================================================
// API version 2024-06-01 is latest GA as of Jan 2026
// Ref: https://learn.microsoft.com/en-us/azure/templates/microsoft.network/privatednszones
// ============================================================================

// 1. MySQL Flexible Server
resource mysqlDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.mysql.database.azure.com'
  location: 'global'
  tags: tags
}

// 2. Azure Managed Redis
// Endpoint format: <cachename>.<region>.redis.azure.net:10000
resource redisDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.redis.azure.net'
  location: 'global'
  tags: tags
}

// 3. Key Vault
resource keyVaultDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
  tags: tags
}

// 4. App Configuration
resource appConfigDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.azconfig.io'
  location: 'global'
  tags: tags
}

// 5. Blob Storage
resource blobDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.blob.core.windows.net'
  location: 'global'
  tags: tags
}

// 6. Queue Storage
resource queueDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.queue.core.windows.net'
  location: 'global'
  tags: tags
}

// 7. Azure Files
resource fileDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.file.core.windows.net'
  location: 'global'
  tags: tags
}

// 8. AKS Private Cluster API Server
// Zone name is region-specific: privatelink.{region}.azmk8s.io
resource aksDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.${location}.azmk8s.io'
  location: 'global'
  tags: tags
}

// 9. Azure Container Registry
resource acrDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.azurecr.io'
  location: 'global'
  tags: tags
}

// ============================================================================
// VNet Links
// ============================================================================
// Each private DNS zone must be linked to the VNet for name resolution.
// Auto-registration is disabled (not needed for private endpoint scenarios).
// ============================================================================

resource mysqlVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: mysqlDnsZone
  name: 'mysql-vnet-link'
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}

resource redisVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: redisDnsZone
  name: 'redis-vnet-link'
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}

resource keyVaultVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: keyVaultDnsZone
  name: 'keyvault-vnet-link'
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}

resource appConfigVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: appConfigDnsZone
  name: 'appconfig-vnet-link'
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}

resource blobVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: blobDnsZone
  name: 'blob-vnet-link'
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}

resource queueVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: queueDnsZone
  name: 'queue-vnet-link'
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}

resource fileVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: fileDnsZone
  name: 'file-vnet-link'
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}

resource aksVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: aksDnsZone
  name: 'aks-vnet-link'
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}

resource acrVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: acrDnsZone
  name: 'acr-vnet-link'
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('MySQL private DNS zone resource ID')
output mysqlDnsZoneId string = mysqlDnsZone.id

@description('Azure Managed Redis private DNS zone resource ID')
output redisDnsZoneId string = redisDnsZone.id

@description('Key Vault private DNS zone resource ID')
output keyVaultDnsZoneId string = keyVaultDnsZone.id

@description('App Configuration private DNS zone resource ID')
output appConfigDnsZoneId string = appConfigDnsZone.id

@description('Blob Storage private DNS zone resource ID')
output blobDnsZoneId string = blobDnsZone.id

@description('Queue Storage private DNS zone resource ID')
output queueDnsZoneId string = queueDnsZone.id

@description('Azure Files private DNS zone resource ID')
output fileDnsZoneId string = fileDnsZone.id

@description('AKS private DNS zone resource ID')
output aksDnsZoneId string = aksDnsZone.id

@description('ACR private DNS zone resource ID')
output acrDnsZoneId string = acrDnsZone.id
