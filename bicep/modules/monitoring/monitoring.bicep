// ============================================================================
// Monitoring Module
// ============================================================================
// Purpose: Creates monitoring infrastructure for QWiser University
//
// Components:
//   - Log Analytics Workspace
//   - Data Collection Endpoint (DCE)
//   - Data Collection Rule (DCR) for Container Insights
//   - Data Collection Rule Association (DCRA) for AKS
//
// Container Insights:
//   Uses DCR-based monitoring (modern approach vs legacy omsagent).
//   Collects ContainerLogV2, performance metrics, and Kubernetes events.
//
// Note: Microsoft Defender for Containers is deployed at subscription scope
// in main.bicep, not in this module.
// ============================================================================

@description('Azure region for resources')
param location string

@description('Naming prefix for resources')
param namingPrefix string

@description('Tags to apply to resources')
param tags object

@description('AKS cluster name for DCR association')
param aksClusterName string

// --- Log Analytics Configuration ---

@description('Log Analytics workspace SKU')
@allowed([
  'Free'
  'PerGB2018'
  'PerNode'
  'Premium'
  'Standalone'
  'Standard'
])
param workspaceSku string = 'PerGB2018'

@description('Log Analytics data retention in days')
@minValue(30)
@maxValue(730)
param retentionInDays int = 90

// --- Container Insights Configuration ---

@description('Enable ContainerLogV2 schema (recommended)')
param enableContainerLogV2 bool = true

@description('Container Insights data collection interval')
@allowed([
  '1m'
  '5m'
  '10m'
  '15m'
  '30m'
])
param collectionInterval string = '5m'

@description('Key Vault name for storing secrets (if provided, App Insights connection string is stored)')
param keyVaultName string = ''

// ============================================================================
// Variables
// ============================================================================

var workspaceName = '${namingPrefix}-law'
var appInsightsName = '${namingPrefix}-appi'
var dceName = '${namingPrefix}-dce'
var dcrName = 'MSCI-${location}-${aksClusterName}'

// ============================================================================
// Log Analytics Workspace
// ============================================================================
// API version 2023-09-01 is latest GA as of Jan 2026
// Ref: https://learn.microsoft.com/en-us/azure/templates/microsoft.operationalinsights/workspaces
// ============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: workspaceSku
    }
    retentionInDays: retentionInDays
    // Enable public ingestion and query (required for Azure Monitor)
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    // Features
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// ============================================================================
// Container Insights Solution
// ============================================================================
// MUST be deployed before DCR - this creates the required tables:
// ContainerLogV2, KubeEvents, KubePodInventory, KubeNodeInventory, etc.
// Ref: https://learn.microsoft.com/en-us/azure/azure-monitor/containers/container-insights-enable-aks
// ============================================================================

resource containerInsightsSolution 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'ContainerInsights(${workspaceName})'
  location: location
  tags: tags
  plan: {
    name: 'ContainerInsights(${workspaceName})'
    publisher: 'Microsoft'
    product: 'OMSGallery/ContainerInsights'
    promotionCode: ''
  }
  properties: {
    workspaceResourceId: logAnalyticsWorkspace.id
  }
}

// ============================================================================
// Application Insights
// ============================================================================
// Workspace-based Application Insights for application telemetry
// API version 2020-02-02 is still current as of Jan 2026
// Ref: https://learn.microsoft.com/en-us/azure/templates/microsoft.insights/components
// ============================================================================

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    RetentionInDays: retentionInDays
  }
}

// ============================================================================
// Data Collection Endpoint
// ============================================================================
// Required for Container Insights DCR-based monitoring
// API version 2023-03-11 is latest GA as of Jan 2026
// ============================================================================

resource dataCollectionEndpoint 'Microsoft.Insights/dataCollectionEndpoints@2023-03-11' = {
  name: dceName
  location: location
  tags: tags
  kind: 'Linux'
  properties: {
    description: 'Data collection endpoint for Container Insights'
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

// ============================================================================
// Data Collection Rule for Container Insights
// ============================================================================
// DCR defines what data the Azure Monitor Agent collects from AKS
// Ref: https://learn.microsoft.com/en-us/azure/azure-monitor/containers/container-insights-data-collection-dcr
// ============================================================================

resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: dcrName
  location: location
  tags: tags
  kind: 'Linux'
  dependsOn: [
    containerInsightsSolution // Wait for solution to create required tables
  ]
  properties: {
    description: 'Data collection rule for Container Insights'
    dataCollectionEndpointId: dataCollectionEndpoint.id
    dataSources: {
      extensions: [
        {
          name: 'ContainerInsightsExtension'
          extensionName: 'ContainerInsights'
          streams: enableContainerLogV2 ? [
            'Microsoft-ContainerLogV2'
            'Microsoft-KubeEvents'
            'Microsoft-KubePodInventory'
            'Microsoft-KubeNodeInventory'
            'Microsoft-KubeServices'
            'Microsoft-KubeMonAgentEvents'
            'Microsoft-InsightsMetrics'
            'Microsoft-Perf'
          ] : [
            'Microsoft-ContainerLog'
            'Microsoft-KubeEvents'
            'Microsoft-KubePodInventory'
            'Microsoft-KubeNodeInventory'
            'Microsoft-KubeServices'
            'Microsoft-KubeMonAgentEvents'
            'Microsoft-InsightsMetrics'
            'Microsoft-Perf'
          ]
          extensionSettings: {
            dataCollectionSettings: {
              interval: collectionInterval
              namespaceFilteringMode: 'Off'
              enableContainerLogV2: enableContainerLogV2
            }
          }
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: logAnalyticsWorkspace.id
          name: 'ciworkspace'
        }
      ]
    }
    dataFlows: [
      {
        streams: enableContainerLogV2 ? [
          'Microsoft-ContainerLogV2'
          'Microsoft-KubeEvents'
          'Microsoft-KubePodInventory'
          'Microsoft-KubeNodeInventory'
          'Microsoft-KubeServices'
          'Microsoft-KubeMonAgentEvents'
          'Microsoft-InsightsMetrics'
          'Microsoft-Perf'
        ] : [
          'Microsoft-ContainerLog'
          'Microsoft-KubeEvents'
          'Microsoft-KubePodInventory'
          'Microsoft-KubeNodeInventory'
          'Microsoft-KubeServices'
          'Microsoft-KubeMonAgentEvents'
          'Microsoft-InsightsMetrics'
          'Microsoft-Perf'
        ]
        destinations: [
          'ciworkspace'
        ]
      }
    ]
  }
}

// ============================================================================
// Data Collection Rule Association
// ============================================================================
// Associates the DCR with the AKS cluster
// ============================================================================

resource dcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = {
  name: 'ContainerInsightsExtension'
  scope: aksCluster
  properties: {
    dataCollectionRuleId: dataCollectionRule.id
    description: 'Association of data collection rule for Container Insights'
  }
}

// Reference to existing AKS cluster for scoping the DCR association
resource aksCluster 'Microsoft.ContainerService/managedClusters@2025-09-01' existing = {
  name: aksClusterName
}

// ============================================================================
// AKS Diagnostic Settings (Kubernetes Audit Logs)
// ============================================================================
// Required for state-actor threat model: Kubernetes audit log analysis
// Enables Defender for Containers to analyze API server audit events
// Ref: https://learn.microsoft.com/en-us/azure/aks/monitor-aks#resource-logs
// ============================================================================

resource aksDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'aks-audit-logs'
  scope: aksCluster
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'kube-audit'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'kube-audit-admin'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'kube-controller-manager'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'kube-scheduler'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'cluster-autoscaler'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'guard'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// ============================================================================
// Key Vault Secret for App Insights Connection String
// ============================================================================
// Writes APPLICATIONINSIGHTS-CONNECTION-STRING to Key Vault for App Config
// Only created if keyVaultName is provided
// ============================================================================

resource existingKeyVault 'Microsoft.KeyVault/vaults@2024-11-01' existing = if (!empty(keyVaultName)) {
  name: keyVaultName
}

resource appInsightsConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = if (!empty(keyVaultName)) {
  parent: existingKeyVault
  name: 'APPLICATIONINSIGHTS-CONNECTION-STRING'
  properties: {
    value: appInsights.properties.ConnectionString
    contentType: 'text/plain'
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Log Analytics workspace resource ID')
output workspaceId string = logAnalyticsWorkspace.id

@description('Log Analytics workspace name')
output workspaceName string = logAnalyticsWorkspace.name

@description('Log Analytics workspace customer ID (for agent configuration)')
output workspaceCustomerId string = logAnalyticsWorkspace.properties.customerId

@description('Data collection endpoint resource ID')
output dceId string = dataCollectionEndpoint.id

@description('Data collection rule resource ID')
output dcrId string = dataCollectionRule.id

@description('Application Insights resource ID')
output appInsightsId string = appInsights.id

@description('Application Insights name')
output appInsightsName string = appInsights.name

@description('Application Insights connection string')
output appInsightsConnectionString string = appInsights.properties.ConnectionString

@description('Application Insights instrumentation key')
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
