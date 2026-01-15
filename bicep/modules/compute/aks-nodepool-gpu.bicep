// ============================================================================
// AKS GPU Node Pool Module
// ============================================================================
// Purpose: Creates optional GPU node pool for embeddings-worker in AKS
//
// GPU Options (see createUiDefinition.json for full list):
//   - T4 series: Standard_NC4as_T4_v3 (recommended for production)
//   - Legacy: Standard_NC6 (K80, cheap for testing)
//   - High-end: A100, H100, V100 for enterprise workloads
//
// IMPORTANT:
//   - GPU drivers: AKS managed GPU experience (automatic driver installation)
//   - x86_64/amd64 architecture ONLY (Nuitka-compiled binaries)
//
// Node Labels and Taints:
//   - Label: 'hardware-type': 'gpu' for nodeSelector
//   - Taint: 'nvidia.com/gpu=present:NoSchedule' to prevent non-GPU pods
// ============================================================================

@description('Existing AKS cluster name')
param aksClusterName string

@description('GPU node pool name')
param nodePoolName string = 'gpu'

@description('GPU VM size - validated by createUiDefinition.json')
param gpuVmSize string = 'Standard_NC4as_T4_v3'

@description('Initial node count')
@minValue(0)
@maxValue(10)
param nodeCount int = 1

@description('Minimum node count for autoscaling (0 = scale to zero)')
@minValue(0)
param minCount int = 0

@description('Maximum node count for autoscaling')
@minValue(1)
param maxCount int = 3

@description('Enable cluster autoscaler')
param enableAutoScaling bool = true

@description('AKS nodes subnet resource ID')
param aksNodesSubnetId string

@description('Availability zones (GPU SKUs may have limited zone availability)')
param availabilityZones array = []

// ============================================================================
// Reference existing AKS cluster
// ============================================================================

resource aksCluster 'Microsoft.ContainerService/managedClusters@2025-09-01' existing = {
  name: aksClusterName
}

// ============================================================================
// GPU Node Pool
// ============================================================================
// GPU drivers are automatically installed by AKS managed GPU experience
// ============================================================================

resource gpuNodePool 'Microsoft.ContainerService/managedClusters/agentPools@2025-09-01' = {
  parent: aksCluster
  name: nodePoolName
  properties: {
    mode: 'User'
    vmSize: gpuVmSize
    count: nodeCount
    minCount: enableAutoScaling ? minCount : null
    maxCount: enableAutoScaling ? maxCount : null
    enableAutoScaling: enableAutoScaling
    availabilityZones: !empty(availabilityZones) ? availabilityZones : null
    vnetSubnetID: aksNodesSubnetId
    // Azure Linux for GPU nodes
    osSKU: 'AzureLinux'
    osType: 'Linux'
    // GPU-specific labels for nodeSelector
    nodeLabels: {
      'nodepool-type': 'gpu'
      'hardware-type': 'gpu'
    }
    // Taint to prevent non-GPU workloads from scheduling
    nodeTaints: [
      'nvidia.com/gpu=present:NoSchedule'
    ]
    // Scale-down settings for cost optimization
    scaleDownMode: enableAutoScaling ? 'Delete' : null
    // Upgrade settings
    upgradeSettings: {
      maxSurge: '33%'
    }
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('GPU node pool name')
output nodePoolName string = gpuNodePool.name

@description('GPU node pool provisioning state')
output provisioningState string = gpuNodePool.properties.provisioningState
