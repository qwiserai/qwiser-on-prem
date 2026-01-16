// ============================================================================
// Virtual Network Module
// ============================================================================
// Purpose: Creates VNet with subnets for AKS, private endpoints, and ACI
//
// Subnets:
//   - pe-subnet: Private endpoints and PLS NAT IPs
//   - aks-nodes: AKS node pool VMs (no NSG - AKS manages its own)
//   - aci-scripts: Delegated to ACI for deploymentScript
//
// NSG Strategy:
//   - PE subnet: NSG with Azure default rules (deny by default)
//   - AKS subnet: No NSG created - AKS manages NSG automatically
//   - ACI subnet: No NSG - delegated subnet
// ============================================================================

@description('Azure region for resources')
param location string

@description('Naming prefix for resources')
param namingPrefix string

@description('Tags to apply to resources')
param tags object

@description('VNet address space CIDR')
param vnetAddressPrefix string

@description('Private endpoints subnet CIDR')
param peSubnetPrefix string

@description('AKS nodes subnet CIDR')
param aksNodesSubnetPrefix string

@description('ACI subnet CIDR (delegated)')
param aciSubnetPrefix string

// ============================================================================
// Variables
// ============================================================================

var vnetName = '${namingPrefix}-vnet'
var peNsgName = '${namingPrefix}-pe-nsg'

// ============================================================================
// Network Security Group for Private Endpoints Subnet
// ============================================================================
// Azure automatically applies default rules:
//   - AllowVNetInBound (65000)
//   - AllowAzureLoadBalancerInBound (65001)
//   - DenyAllInBound (65500)
//   - AllowVNetOutBound (65000)
//   - AllowInternetOutBound (65001)
//   - DenyAllOutBound (65500)
//
// We create an explicit NSG to enable logging and future custom rules.
// ============================================================================

resource peNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: peNsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      // Azure default rules provide deny-by-default behavior
      // Add explicit rules here if needed for specific traffic patterns
    ]
  }
}

// ============================================================================
// Virtual Network
// ============================================================================
// Best practice: Define subnets inline within VNet resource
// Ref: https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/scenarios-virtual-networks
// ============================================================================

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      // Private Endpoints subnet
      {
        name: 'pe-subnet'
        properties: {
          addressPrefix: peSubnetPrefix
          networkSecurityGroup: {
            id: peNsg.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
      // AKS nodes subnet - NO NSG (AKS manages its own)
      {
        name: 'aks-nodes'
        properties: {
          addressPrefix: aksNodesSubnetPrefix
          // AKS will create and manage its own NSG
          // Do not assign NSG here per Azure best practices
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      // ACI subnet - delegated to Container Instances
      {
        name: 'aci-scripts'
        properties: {
          addressPrefix: aciSubnetPrefix
          delegations: [
            {
              name: 'Microsoft.ContainerInstance.containerGroups'
              properties: {
                serviceName: 'Microsoft.ContainerInstance/containerGroups'
              }
            }
          ]
        }
      }
    ]
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('VNet resource ID')
output vnetId string = vnet.id

@description('VNet name')
output vnetName string = vnet.name

@description('Private endpoints subnet resource ID')
output peSubnetId string = vnet.properties.subnets[0].id

@description('AKS nodes subnet resource ID')
output aksNodesSubnetId string = vnet.properties.subnets[1].id

@description('ACI scripts subnet resource ID')
output aciSubnetId string = vnet.properties.subnets[2].id

@description('PE NSG resource ID')
output peNsgId string = peNsg.id
