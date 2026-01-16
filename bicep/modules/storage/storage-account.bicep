// ============================================================================
// Storage Account Module
// ============================================================================
// Purpose: Creates Storage Account with private endpoints for blob, queue,
//          and Azure Files. Includes file share for ML models.
//
// Security Configuration (state-actor threat model):
//   - publicNetworkAccess: Disabled (all access via Private Endpoints)
//   - networkAcls.defaultAction: Deny
//   - allowBlobPublicAccess: false (no public container access)
//   - minimumTlsVersion: TLS1_2
//   - allowSharedKeyAccess: Parameterized (default true for IT admin uploads)
//
// Resources Created:
//   - Storage Account (Standard_LRS, StorageV2)
//   - Private Endpoints (blob, queue, file)
//   - Azure Files share for ML models
//
// ML Model Storage:
//   - File share 'ml-models' for embedding models (~2-3GB)
//   - Mounted as ReadOnlyMany PVC by embeddings-worker pods
//   - IT uploads models via Azure Cloud Shell or VPN
// ============================================================================

@description('Azure region for resources')
param location string

@description('Naming prefix for resources')
param namingPrefix string

@description('Tags to apply to resources')
param tags object

@description('Private endpoints subnet resource ID')
param peSubnetId string

@description('Blob Storage private DNS zone resource ID')
param blobDnsZoneId string

@description('Queue Storage private DNS zone resource ID')
param queueDnsZoneId string

@description('Azure Files private DNS zone resource ID')
param fileDnsZoneId string

@description('Allow shared key access for IT admin uploads (true = simpler, false = more secure)')
param allowSharedKeyAccess bool = true

@description('Name of the Azure Files share for ML models')
param mlModelsShareName string = 'ml-models'

@description('Quota for ML models file share in GB')
@minValue(1)
@maxValue(5120)
param mlModelsShareQuotaGiB int = 10

@description('Key Vault name for storing secrets (if provided, secrets are created)')
param keyVaultName string = ''

// ============================================================================
// Variables
// ============================================================================

// Storage account names must be globally unique, 3-24 chars, lowercase alphanumeric only
// Remove hyphens from naming prefix for storage account name
var storageAccountName = toLower(replace('${namingPrefix}storage', '-', ''))
var blobPeName = '${namingPrefix}-storage-blob-pe'
var queuePeName = '${namingPrefix}-storage-queue-pe'
var filePeName = '${namingPrefix}-storage-file-pe'

// ============================================================================
// Storage Account
// ============================================================================
// API version 2025-01-01 is latest GA as of Jan 2026
// Ref: https://learn.microsoft.com/en-us/azure/templates/microsoft.storage/storageaccounts
// ============================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    // Security: Disable public network access (Private Endpoint only)
    publicNetworkAccess: 'Disabled'

    // Security: Deny by default (defense in depth with publicNetworkAccess)
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: []
      virtualNetworkRules: []
    }

    // Security: Prevent public blob containers
    allowBlobPublicAccess: false

    // Security: Require TLS 1.2 minimum
    minimumTlsVersion: 'TLS1_2'

    // Security: Require HTTPS
    supportsHttpsTrafficOnly: true

    // Auth: Parameterized - true for simple IT uploads, false for Entra ID only
    // When false, IT admin needs 'Storage File Data Contributor' role
    allowSharedKeyAccess: allowSharedKeyAccess

    // Access tier for blob storage
    accessTier: 'Hot'

    // Disable cross-tenant replication
    allowCrossTenantReplication: false
  }
}

// ============================================================================
// File Services and ML Models Share
// ============================================================================

resource fileServices 'Microsoft.Storage/storageAccounts/fileServices@2025-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {}
}

resource mlModelsShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2025-01-01' = {
  parent: fileServices
  name: mlModelsShareName
  properties: {
    shareQuota: mlModelsShareQuotaGiB
    enabledProtocols: 'SMB'
    accessTier: 'Hot'
  }
}

// ============================================================================
// Private Endpoints
// ============================================================================
// Three private endpoints for blob, queue, and file services
// Each automatically registers in the corresponding private DNS zone
// ============================================================================

// --- Blob Private Endpoint ---
resource blobPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: blobPeName
  location: location
  tags: tags
  properties: {
    subnet: {
      id: peSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${blobPeName}-connection'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

resource blobDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: blobPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-blob-core-windows-net'
        properties: {
          privateDnsZoneId: blobDnsZoneId
        }
      }
    ]
  }
}

// --- Queue Private Endpoint ---
resource queuePrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: queuePeName
  location: location
  tags: tags
  properties: {
    subnet: {
      id: peSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${queuePeName}-connection'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'queue'
          ]
        }
      }
    ]
  }
}

resource queueDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: queuePrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-queue-core-windows-net'
        properties: {
          privateDnsZoneId: queueDnsZoneId
        }
      }
    ]
  }
}

// --- File Private Endpoint ---
resource filePrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: filePeName
  location: location
  tags: tags
  properties: {
    subnet: {
      id: peSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${filePeName}-connection'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'file'
          ]
        }
      }
    ]
  }
}

resource fileDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: filePrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-file-core-windows-net'
        properties: {
          privateDnsZoneId: fileDnsZoneId
        }
      }
    ]
  }
}

// ============================================================================
// Key Vault Secrets for Storage Credentials
// ============================================================================
// Writes STORAGE-ACCOUNT-KEY and STORAGE-CONNECTION-STRING to Key Vault
// Only created if keyVaultName is provided AND allowSharedKeyAccess is true
// Ref: https://learn.microsoft.com/en-us/azure/templates/microsoft.keyvault/vaults/secrets
// ============================================================================

resource existingKeyVault 'Microsoft.KeyVault/vaults@2024-11-01' existing = if (!empty(keyVaultName) && allowSharedKeyAccess) {
  name: keyVaultName
}

resource storageAccountKeySecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = if (!empty(keyVaultName) && allowSharedKeyAccess) {
  parent: existingKeyVault
  name: 'STORAGE-ACCOUNT-KEY'
  properties: {
    value: storageAccount.listKeys().keys[0].value
    contentType: 'text/plain'
  }
}

resource storageConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = if (!empty(keyVaultName) && allowSharedKeyAccess) {
  parent: existingKeyVault
  name: 'STORAGE-CONNECTION-STRING'
  properties: {
    // Standard Azure Storage connection string format
    value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
    contentType: 'text/plain'
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Storage account resource ID')
output storageAccountId string = storageAccount.id

@description('Storage account name')
output storageAccountName string = storageAccount.name

@description('Blob service primary endpoint')
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('Queue service primary endpoint')
output queueEndpoint string = storageAccount.properties.primaryEndpoints.queue

@description('File service primary endpoint')
output fileEndpoint string = storageAccount.properties.primaryEndpoints.file

@description('ML models file share name')
output mlModelsShareName string = mlModelsShare.name

@description('Storage account resource group (for PV configuration)')
output storageAccountResourceGroup string = resourceGroup().name
