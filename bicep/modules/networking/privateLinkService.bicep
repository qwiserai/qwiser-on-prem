// ============================================================================
// Private Link Service Module
// ============================================================================
// Purpose: Creates Private Link Service for Front Door → AKS internal LB
//
// Architecture:
//   Internet → Front Door → Private Endpoint → PLS → ILB → NGINX Ingress
//
// The PLS enables Front Door Premium to privately connect to the AKS internal
// load balancer without exposing any public IP on the cluster.
//
// Key Configuration:
//   - Load balancer frontend IP from MC_ resource group
//   - NAT IP configurations in the PE subnet (same subnet as other PEs)
//   - Auto-approval disabled (approved via post-deploy script)
//
// Post-Deploy Requirement:
//   The Private Endpoint connection from Front Door must be manually approved
//   after deployment. See post-deploy.sh/ps1 for the approval command.
// ============================================================================

@description('Azure region for resources')
param location string

@description('Naming prefix for resources')
param namingPrefix string

@description('Tags to apply to resources')
param tags object

@description('Private endpoints subnet resource ID (for NAT IPs)')
param peSubnetId string

@description('Frontend IP configuration resource ID from the internal LoadBalancer')
param frontendIpConfigId string

// ============================================================================
// Variables
// ============================================================================

var plsName = '${namingPrefix}-pls-nginx'

// ============================================================================
// Private Link Service
// ============================================================================
// API version 2024-05-01 is latest GA as of Jan 2026
// Ref: https://learn.microsoft.com/en-us/azure/templates/microsoft.network/privatelinkservices
// ============================================================================

resource privateLinkService 'Microsoft.Network/privateLinkServices@2024-05-01' = {
  name: plsName
  location: location
  tags: tags
  properties: {
    // Load balancer frontend IP to expose via Private Link
    loadBalancerFrontendIpConfigurations: [
      {
        id: frontendIpConfigId
      }
    ]

    // NAT IP configurations for translating Private Endpoint traffic
    // These IPs are in the PE subnet and are used by the PLS for SNAT
    ipConfigurations: [
      {
        name: 'pls-nat-ip-1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          privateIPAddressVersion: 'IPv4'
          subnet: {
            id: peSubnetId
          }
          primary: true
        }
      }
      {
        name: 'pls-nat-ip-2'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          privateIPAddressVersion: 'IPv4'
          subnet: {
            id: peSubnetId
          }
          primary: false
        }
      }
    ]

    // Visibility: Allow connections from Front Door in the same subscription
    // NOTE: Front Door creates its PE in Azure-managed infrastructure, not our VNet
    visibility: {
      subscriptions: [
        subscription().subscriptionId
      ]
    }

    // Auto-approval disabled - must be approved via post-deploy script
    // This ensures explicit human approval of the Front Door connection
    autoApproval: {
      subscriptions: []
    }

    // Enable TCP Proxy Protocol v2 (optional, for passing client IP)
    enableProxyProtocol: false

    // Fqdns are not needed for Front Door integration
    fqdns: []
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Private Link Service resource ID')
output plsId string = privateLinkService.id

@description('Private Link Service name')
output plsName string = privateLinkService.name

@description('Private Link Service alias (for PE connection)')
output plsAlias string = privateLinkService.properties.alias
