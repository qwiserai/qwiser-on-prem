// ============================================================================
// Azure Front Door Premium Module
// ============================================================================
// Purpose: Creates Azure Front Door Premium with WAF and PLS origin
//
// Architecture:
//   Internet → Front Door (WAF) → Private Endpoint → PLS → ILB → NGINX
//
// Security Configuration (state-actor threat model):
//   - Front Door Premium SKU (required for Private Link origins)
//   - Web Application Firewall with managed rule sets
//   - OWASP Top 10 protection
//   - Bot protection
//   - Rate limiting
//
// Post-Deploy Requirement:
//   1. Private Endpoint connection must be approved (see post-deploy script)
//   2. University configures CNAME: subdomain.university.edu → FD endpoint
// ============================================================================

@description('Azure region for resources (global for Front Door)')
param location string = 'global'

@description('Naming prefix for resources')
param namingPrefix string

@description('Tags to apply to resources')
param tags object

@description('Private Link Service resource ID')
param privateLinkServiceId string

@description('Private Link Service location (must match PLS location for PE creation)')
param privateLinkServiceLocation string

@description('Private IP address of the internal load balancer')
param originPrivateIpAddress string

@description('Log Analytics workspace resource ID for diagnostics')
param logAnalyticsWorkspaceId string

@description('Enable Web Application Firewall')
param enableWaf bool = true

@description('WAF mode')
@allowed([
  'Detection'
  'Prevention'
])
param wafMode string = 'Prevention'

// ============================================================================
// Variables
// ============================================================================

var frontDoorName = '${namingPrefix}-fd'
var endpointName = '${namingPrefix}-endpoint'
var originGroupName = 'default-origin-group'
var originName = 'aks-pls-origin'
var routeName = 'default-route'
var wafPolicyName = '${replace(namingPrefix, '-', '')}waf'

// ============================================================================
// Front Door Profile (Premium SKU for Private Link)
// ============================================================================
// API version 2024-02-01 is latest GA as of Jan 2026
// Ref: https://learn.microsoft.com/en-us/azure/templates/microsoft.cdn/profiles
// ============================================================================

resource frontDoorProfile 'Microsoft.Cdn/profiles@2024-02-01' = {
  name: frontDoorName
  location: location
  tags: tags
  sku: {
    // Premium required for Private Link origin support
    name: 'Premium_AzureFrontDoor'
  }
  properties: {
    originResponseTimeoutSeconds: 60
  }
}

// ============================================================================
// Front Door Endpoint
// ============================================================================

resource frontDoorEndpoint 'Microsoft.Cdn/profiles/afdEndpoints@2024-02-01' = {
  parent: frontDoorProfile
  name: endpointName
  location: location
  tags: tags
  properties: {
    enabledState: 'Enabled'
    // Auto-generated hostname: <endpointName>.z01.azurefd.net
  }
}

// ============================================================================
// Origin Group with Health Probe
// ============================================================================

resource originGroup 'Microsoft.Cdn/profiles/originGroups@2024-02-01' = {
  parent: frontDoorProfile
  name: originGroupName
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 0
    }
    healthProbeSettings: {
      probePath: '/healthz'
      probeRequestType: 'GET'
      probeProtocol: 'Http'
      probeIntervalInSeconds: 30
    }
    sessionAffinityState: 'Disabled'
  }
}

// ============================================================================
// Origin with Private Link
// ============================================================================
// Uses shared Private Link to connect to the PLS
// ============================================================================

resource origin 'Microsoft.Cdn/profiles/originGroups/origins@2024-02-01' = {
  parent: originGroup
  name: originName
  properties: {
    hostName: originPrivateIpAddress
    httpPort: 80
    httpsPort: 443
    originHostHeader: originPrivateIpAddress
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
    enforceCertificateNameCheck: true

    // Private Link configuration
    sharedPrivateLinkResource: {
      privateLink: {
        id: privateLinkServiceId
      }
      // Location must match the PLS location for PE creation to succeed
      privateLinkLocation: privateLinkServiceLocation
      requestMessage: 'Front Door origin connection to NGINX Ingress'
      groupId: '' // Empty for Private Link Service (not a specific sub-resource)
    }
  }
}

// ============================================================================
// Route
// ============================================================================

resource route 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-02-01' = {
  parent: frontDoorEndpoint
  name: routeName
  properties: {
    originGroup: {
      id: originGroup.id
    }
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    forwardingProtocol: 'HttpOnly' // NGINX handles TLS termination internally
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
    enabledState: 'Enabled'
  }
  dependsOn: [
    origin
  ]
}

// ============================================================================
// WAF Policy
// ============================================================================

resource wafPolicy 'Microsoft.Network/FrontDoorWebApplicationFirewallPolicies@2024-02-01' = if (enableWaf) {
  name: wafPolicyName
  location: location
  tags: tags
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
  properties: {
    policySettings: {
      enabledState: 'Enabled'
      mode: wafMode
      requestBodyCheck: 'Enabled'
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'Microsoft_DefaultRuleSet'
          ruleSetVersion: '2.1'
          ruleSetAction: 'Block'
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '1.0'
          ruleSetAction: 'Block'
        }
      ]
    }
    customRules: {
      rules: [
        // Rate limiting rule
        {
          name: 'RateLimitRule'
          priority: 100
          enabledState: 'Enabled'
          ruleType: 'RateLimitRule'
          rateLimitDurationInMinutes: 1
          rateLimitThreshold: 1000
          matchConditions: [
            {
              matchVariable: 'RequestUri'
              operator: 'Contains'
              negateCondition: false
              matchValue: [
                '/'
              ]
            }
          ]
          action: 'Block'
        }
      ]
    }
  }
}

// ============================================================================
// Security Policy (WAF → Endpoint binding)
// ============================================================================

resource securityPolicy 'Microsoft.Cdn/profiles/securityPolicies@2024-02-01' = if (enableWaf) {
  parent: frontDoorProfile
  name: 'waf-security-policy'
  properties: {
    parameters: {
      type: 'WebApplicationFirewall'
      wafPolicy: {
        id: wafPolicy.id
      }
      associations: [
        {
          domains: [
            {
              id: frontDoorEndpoint.id
            }
          ]
          patternsToMatch: [
            '/*'
          ]
        }
      ]
    }
  }
}

// ============================================================================
// Diagnostic Settings
// ============================================================================

resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'front-door-diagnostics'
  scope: frontDoorProfile
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'FrontDoorAccessLog'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'FrontDoorHealthProbeLog'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'FrontDoorWebApplicationFirewallLog'
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
// Outputs
// ============================================================================

@description('Front Door profile resource ID')
output frontDoorId string = frontDoorProfile.id

@description('Front Door profile name')
output frontDoorName string = frontDoorProfile.name

@description('Front Door endpoint hostname (use for CNAME)')
output frontDoorEndpointHostname string = frontDoorEndpoint.properties.hostName

@description('Front Door endpoint ID')
output frontDoorEndpointId string = frontDoorEndpoint.id

@description('WAF policy resource ID')
output wafPolicyId string = enableWaf ? wafPolicy.id : ''
