// ============================================================================
// Federated Identity Credentials Module
// ============================================================================
// Purpose: Creates federated identity credential for AKS Workload Identity
//
// This module is called AFTER AKS is created (Phase 2) because it requires
// the AKS OIDC issuer URL.
//
// All QWiser workloads share a single ServiceAccount (sa-qwiser) bound to
// the User-Assigned Managed Identity via one federated credential.
//
// K8s Annotations required on ServiceAccount:
//   azure.workload.identity/client-id: <managedIdentityClientId>
//
// K8s Labels required on Pods:
//   azure.workload.identity/use: "true"
// ============================================================================

@description('Existing managed identity name to add federated credentials to')
param managedIdentityName string

@description('AKS OIDC issuer URL (from aks.properties.oidcIssuerProfile.issuerUrl)')
param aksOidcIssuerUrl string

@description('Kubernetes namespace where ServiceAccount is created')
param namespace string = 'default'

// Standard audience for Azure AD token exchange
var audiences = ['api://AzureADTokenExchange']

// ============================================================================
// Existing Managed Identity
// ============================================================================

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: managedIdentityName
}

// ============================================================================
// Federated Identity Credential
// ============================================================================

resource federatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2024-11-30' = {
  parent: managedIdentity
  name: 'fc-sa-qwiser'
  properties: {
    issuer: aksOidcIssuerUrl
    subject: 'system:serviceaccount:${namespace}:sa-qwiser'
    audiences: audiences
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Created federated credential name')
output federatedCredentialName string = federatedCredential.name

@description('Managed identity client ID (needed for K8s ServiceAccount annotation)')
output managedIdentityClientId string = managedIdentity.properties.clientId
