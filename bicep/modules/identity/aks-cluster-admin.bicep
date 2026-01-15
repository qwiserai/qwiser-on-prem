// ============================================================================
// AKS Cluster Admin Role Assignment
// ============================================================================
// Purpose: Grants Azure Kubernetes Service Cluster Admin Role to managed identity
//
// Required for: Deployment scripts that use `az aks command invoke` to run
// commands on the AKS cluster (e.g., Helm install, kubectl apply).
//
// This role allows:
//   - Microsoft.ContainerService/managedClusters/runCommand/action
//   - Microsoft.ContainerService/managedClusters/commandResults/read
// ============================================================================

@description('AKS cluster name')
param aksClusterName string

@description('Principal ID (object ID) of the managed identity')
param principalId string

// Built-in role: Azure Kubernetes Service Cluster Admin Role
// Ref: https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#azure-kubernetes-service-cluster-admin-role
var aksClusterAdminRoleId = '0ab0b1a8-8aac-4efd-b8c2-3ee1fb270be8'

// Reference existing AKS cluster
resource aksCluster 'Microsoft.ContainerService/managedClusters@2025-09-01' existing = {
  name: aksClusterName
}

// Role assignment scoped to the AKS cluster
resource clusterAdminRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aksCluster.id, principalId, aksClusterAdminRoleId)
  scope: aksCluster
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', aksClusterAdminRoleId)
    principalType: 'ServicePrincipal'
    description: 'Allow managed identity to run commands on AKS cluster via az aks command invoke'
  }
}
