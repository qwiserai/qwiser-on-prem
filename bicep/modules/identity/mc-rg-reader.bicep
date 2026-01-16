// ============================================================================
// MC Resource Group Reader Role Assignment
// ============================================================================
// Purpose: Grants Reader role on the AKS node resource group (MC_*)
//
// Required for deploymentScript to query:
//   - Internal LoadBalancer resource ID
//   - Frontend IP configuration ID
//
// This module is deployed at resource group scope (the MC_ resource group),
// using `scope: resourceGroup(aks.outputs.nodeResourceGroup)` in main.bicep.
// ============================================================================

@description('Principal ID of the managed identity to grant access')
param principalId string

// ============================================================================
// Variables
// ============================================================================

// Built-in role: Reader (acdd72a7-3385-48ef-bd42-f606fba81ae7)
var readerRoleId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'

// ============================================================================
// Reader Role Assignment
// ============================================================================
// Scoped to the current resource group (the MC_ resource group)
// ============================================================================

resource readerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, principalId, readerRoleId)
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', readerRoleId)
    principalType: 'ServicePrincipal'
    description: 'Allow managed identity to query ILB resources for PLS creation'
  }
}
