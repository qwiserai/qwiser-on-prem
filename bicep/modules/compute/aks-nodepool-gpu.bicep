// ============================================================================
// AKS GPU Node Pool Module
// ============================================================================
// Purpose: Creates optional GPU node pool for embeddings-worker in AKS
//
// GPU Configuration:
//   - Default SKU: Standard_NC4as_T4_v3 (4 vCPUs, 28 GiB RAM, 1x NVIDIA T4 16GB)
//   - Alternative: Standard_NC8as_T4_v3 (8 vCPUs, 56 GiB RAM, 1x NVIDIA T4 16GB)
//   - T4 GPU with 16GB VRAM is sufficient for bge-m3 + jina-colbert-v2 models
//
// IMPORTANT:
//   - NCv3-series (Standard_NC6s_v3) was RETIRED September 2025 - do not use
//   - GPU drivers: AKS managed GPU experience (automatic driver installation)
//   - x86_64/amd64 architecture ONLY (Nuitka-compiled binaries)
//
// Node Labels and Taints:
//   - Label: 'gpu': 'nvidia-t4' for nodeSelector
//   - Taint: 'nvidia.com/gpu=present:NoSchedule' to prevent non-GPU pods
// ============================================================================

@description('Existing AKS cluster name')
param aksClusterName string

@description('GPU node pool name')
param nodePoolName string = 'gpu'

@description('GPU VM size (T4 series recommended)')
@allowed([
  'Standard_NC4as_T4_v3'   // 4 vCPUs, 28 GiB, 1x T4 16GB - Recommended
  'Standard_NC8as_T4_v3'   // 8 vCPUs, 56 GiB, 1x T4 16GB - Higher capacity
  'Standard_NC16as_T4_v3'  // 16 vCPUs, 110 GiB, 1x T4 16GB
  'Standard_NC64as_T4_v3'  // 64 vCPUs, 440 GiB, 4x T4 16GB
])
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
      gpu: 'nvidia-t4'
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
