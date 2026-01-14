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

// Networking - defaults are usually fine, customize if needed
// param vnetAddressPrefix = '10.0.0.0/16'
// param peSubnetPrefix = '10.0.0.0/24'
// param aksNodesSubnetPrefix = '10.0.1.0/22'
// param aciSubnetPrefix = '10.0.5.0/27'
