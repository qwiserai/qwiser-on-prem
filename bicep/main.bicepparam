// ============================================================================
// QWiser University Infrastructure - Parameter File Template
// ============================================================================
// Purpose: Template for deployment parameters. Copy and customize per environment.
// ============================================================================

using 'main.bicep'

// Required parameters - must be set for deployment
param location = 'israelcentral'  // Change to target region
param environmentName = 'prod'    // Environment identifier

// Optional parameters - defaults provided in main.bicep
param namePrefix = 'qwiser'

param tags = {
  Environment: 'prod'
  Application: 'QWiser'
  ManagedBy: 'Bicep'
  DeployedOn: '' // Will be set at deploy time
}

// Networking - defaults use 10.200.x.x to minimize overlap with common enterprise networks
// Customize only if these conflict with existing campus or peered networks
// param vnetAddressPrefix = '10.200.0.0/16'
// param peSubnetPrefix = '10.200.0.0/24'
// param aksNodesSubnetPrefix = '10.200.4.0/22'
// param aciSubnetPrefix = '10.200.8.0/27'
// param aksPodCidr = '100.64.0.0/16'
