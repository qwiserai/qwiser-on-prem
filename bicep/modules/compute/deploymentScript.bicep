// ============================================================================
// Deployment Script Module - NGINX Ingress Installation
// ============================================================================
// Purpose: Installs NGINX Ingress Controller via Helm on AKS cluster
//
// Architecture:
//   - Uses `az aks command invoke` to run commands through control plane
//   - Works with both public and private AKS clusters
//   - Creates internal LoadBalancer with static IP for Private Link Service
//
// Sequence:
//   1. Install NGINX Ingress Controller via Helm
//   2. Wait for Internal Load Balancer to be created by Kubernetes
//   3. Output ILB frontend IP configuration ID for PLS creation
//
// Note: VNet-integrated ACI deployment not required when using command invoke.
// The command runs through AKS control plane, bypassing network restrictions.
// ============================================================================

@description('Azure region for resources')
param location string

@description('Naming prefix for resources')
param namingPrefix string

@description('Tags to apply to resources')
param tags object

@description('AKS cluster name')
param aksClusterName string

@description('AKS cluster resource group name')
param aksResourceGroupName string

@description('AKS node resource group name (MC_ resource group)')
param nodeResourceGroupName string

@description('Static IP for NGINX Ingress internal load balancer (must be in AKS subnet range)')
param nginxIngressPrivateIpAddress string

@description('Helm chart version for NGINX Ingress Controller')
param nginxIngressVersion string = '4.12.0'

@description('Kubernetes namespace for NGINX Ingress Controller')
param nginxIngressNamespace string = 'ingress-nginx'

@description('User-assigned managed identity resource ID')
param managedIdentityId string

// --- ConfigMap Parameters ---

@description('Azure App Configuration endpoint URL')
param appConfigEndpoint string

@description('Config label for Azure App Configuration (production or staging)')
@allowed([
  'production'
  'staging'
])
param configLabel string = 'production'

@description('Base URL for QWiser services (e.g., https://qwiser.university.edu)')
param baseUrl string

@description('ACR login server (e.g., myunivacr.azurecr.io)')
param acrLoginServer string

@description('Kubernetes namespace for QWiser workloads')
param workloadNamespace string = 'default'

@description('User-assigned managed identity client ID (for Workload Identity)')
param uamiClientId string

@description('Azure Key Vault name')
param keyVaultName string

@description('Azure AD tenant ID')
param tenantId string

@description('Storage account name for ML models')
param storageAccountName string

// ============================================================================
// Variables
// ============================================================================

var deploymentScriptName = '${namingPrefix}-nginx-install'

// ============================================================================
// Deployment Script - NGINX Ingress Installation
// ============================================================================
// Uses Azure CLI container with az aks command invoke for private cluster access
// API version 2023-08-01 is latest GA as of Jan 2026
// ============================================================================

resource nginxInstallScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: deploymentScriptName
  location: location
  tags: tags
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    azCliVersion: '2.67.0'
    timeout: 'PT15M'
    retentionInterval: 'P1D'
    cleanupPreference: 'OnSuccess'
    environmentVariables: [
      {
        name: 'AKS_CLUSTER_NAME'
        value: aksClusterName
      }
      {
        name: 'AKS_RESOURCE_GROUP'
        value: aksResourceGroupName
      }
      {
        name: 'NODE_RESOURCE_GROUP'
        value: nodeResourceGroupName
      }
      {
        name: 'NGINX_INGRESS_VERSION'
        value: nginxIngressVersion
      }
      {
        name: 'NGINX_INGRESS_NAMESPACE'
        value: nginxIngressNamespace
      }
      {
        name: 'NGINX_PRIVATE_IP'
        value: nginxIngressPrivateIpAddress
      }
      // ConfigMap environment variables
      {
        name: 'QWISER_NAMESPACE'
        value: workloadNamespace
      }
      {
        name: 'APP_CONFIG_ENDPOINT'
        value: appConfigEndpoint
      }
      {
        name: 'CONFIG_LABEL'
        value: configLabel
      }
      {
        name: 'BASE_URL'
        value: baseUrl
      }
      {
        name: 'ACR_LOGIN_SERVER'
        value: acrLoginServer
      }
      {
        name: 'UAMI_CLIENT_ID'
        value: uamiClientId
      }
      {
        name: 'KEY_VAULT_NAME'
        value: keyVaultName
      }
      {
        name: 'TENANT_ID'
        value: tenantId
      }
      {
        name: 'STORAGE_ACCOUNT_NAME'
        value: storageAccountName
      }
    ]
    scriptContent: '''
      #!/bin/bash
      set -e

      echo "Installing NGINX Ingress Controller on AKS cluster..."

      # Login with user-assigned managed identity
      az login --identity --username "$UAMI_CLIENT_ID" --allow-no-subscriptions -o none

      # Wait for RBAC propagation (retry every 5s, up to 45s)
      echo "Waiting for RBAC permissions..."
      for i in {1..9}; do
        if az aks command invoke --resource-group "$AKS_RESOURCE_GROUP" --name "$AKS_CLUSTER_NAME" --command "echo OK" -o none 2>/dev/null; then
          echo "RBAC ready."
          break
        fi
        if [ $i -eq 9 ]; then
          echo "ERROR: RBAC not ready after 45 seconds"
          exit 1
        fi
        sleep 5
      done

      # Create the Helm install command with values for internal LoadBalancer
      HELM_COMMAND="helm upgrade --install nginx-ingress ingress-nginx/ingress-nginx \
        --namespace $NGINX_INGRESS_NAMESPACE \
        --create-namespace \
        --version $NGINX_INGRESS_VERSION \
        --set controller.replicaCount=2 \
        --set controller.service.annotations.'service\\.beta\\.kubernetes\\.io/azure-load-balancer-internal'='true' \
        --set controller.service.annotations.'service\\.beta\\.kubernetes\\.io/azure-load-balancer-internal-subnet'='aks-nodes' \
        --set controller.service.annotations.'service\\.beta\\.kubernetes\\.io/azure-load-balancer-health-probe-request-path'='/healthz' \
        --set controller.service.loadBalancerIP=$NGINX_PRIVATE_IP \
        --set controller.service.externalTrafficPolicy=Local \
        --set controller.nodeSelector.'kubernetes\\.io/os'=linux \
        --set defaultBackend.nodeSelector.'kubernetes\\.io/os'=linux \
        --set controller.resources.requests.cpu=100m \
        --set controller.resources.requests.memory=256Mi \
        --set controller.resources.limits.cpu=1000m \
        --set controller.resources.limits.memory=1Gi \
        --set controller.containerSecurityContext.runAsUser=101 \
        --set controller.containerSecurityContext.runAsNonRoot=true \
        --set controller.containerSecurityContext.allowPrivilegeEscalation=false \
        --wait \
        --timeout 10m"

      # Install NGINX Ingress via Helm
      echo "Installing NGINX Ingress via Helm..."
      az aks command invoke \
        --resource-group "$AKS_RESOURCE_GROUP" \
        --name "$AKS_CLUSTER_NAME" \
        --command "helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx && helm repo update && $HELM_COMMAND"

      # Wait for LoadBalancer IP (usually immediate with --wait flag)
      echo "Waiting for LoadBalancer IP..."
      for i in {1..10}; do
        LB_IP=$(az aks command invoke \
          --resource-group "$AKS_RESOURCE_GROUP" \
          --name "$AKS_CLUSTER_NAME" \
          --command "kubectl get svc nginx-ingress-ingress-nginx-controller -n $NGINX_INGRESS_NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}'" \
          --query "logs" -o tsv 2>/dev/null | tr -d '\n')

        if [ -n "$LB_IP" ] && [ "$LB_IP" != "null" ]; then
          echo "LoadBalancer IP: $LB_IP"
          break
        fi
        sleep 10
      done

      if [ -z "$LB_IP" ] || [ "$LB_IP" == "null" ]; then
        echo "ERROR: LoadBalancer IP not assigned"
        exit 1
      fi

      # Get internal LoadBalancer resource ID
      ILB_ID=$(az network lb show \
        --resource-group "$NODE_RESOURCE_GROUP" \
        --name "kubernetes-internal" \
        --query "id" -o tsv 2>/dev/null || echo "")

      if [ -z "$ILB_ID" ]; then
        echo "ERROR: kubernetes-internal LoadBalancer not found"
        exit 1
      fi

      # Get frontend IP configuration ID
      FRONTEND_IP_CONFIG_ID=$(az network lb frontend-ip list \
        --resource-group "$NODE_RESOURCE_GROUP" \
        --lb-name "kubernetes-internal" \
        --query "[?privateIPAddress=='$NGINX_PRIVATE_IP'].id | [0]" -o tsv 2>/dev/null || echo "")

      if [ -z "$FRONTEND_IP_CONFIG_ID" ]; then
        FRONTEND_IP_CONFIG_ID=$(az network lb frontend-ip list \
          --resource-group "$NODE_RESOURCE_GROUP" \
          --lb-name "kubernetes-internal" \
          --query "[0].id" -o tsv 2>/dev/null || echo "")
      fi

      if [ -z "$FRONTEND_IP_CONFIG_ID" ]; then
        echo "ERROR: Frontend IP configuration not found"
        exit 1
      fi

      # Create QWiser ConfigMap
      echo "Creating QWiser ConfigMap..."
      CUSTOM_DOMAIN=$(echo "$BASE_URL" | sed 's|^https://||' | sed 's|^http://||' | sed 's|/$||')

      CONFIGMAP_YAML="apiVersion: v1
kind: ConfigMap
metadata:
  name: qwiser-config
  namespace: $QWISER_NAMESPACE
data:
  AZURE_APP_CONFIG_ENDPOINT: \"$APP_CONFIG_ENDPOINT\"
  CONFIG_LABEL: \"$CONFIG_LABEL\"
  PUBLIC_URL: \"$BASE_URL\"
  FRONTEND_URL: \"$BASE_URL\"
  REACT_APP_SERVER_API_URL: \"$BASE_URL\"
  CUSTOM_DOMAIN: \"$CUSTOM_DOMAIN\"
  ACR_LOGIN_SERVER: \"$ACR_LOGIN_SERVER\"
  UAMI_CLIENT_ID: \"$UAMI_CLIENT_ID\"
  KEY_VAULT_NAME: \"$KEY_VAULT_NAME\"
  TENANT_ID: \"$TENANT_ID\"
  STORAGE_ACCOUNT_NAME: \"$STORAGE_ACCOUNT_NAME\""

      # Create namespace if it doesn't exist, then apply ConfigMap
      az aks command invoke \
        --resource-group "$AKS_RESOURCE_GROUP" \
        --name "$AKS_CLUSTER_NAME" \
        --command "kubectl create namespace $QWISER_NAMESPACE --dry-run=client -o yaml | kubectl apply -f - && echo '$CONFIGMAP_YAML' | kubectl apply -f -"

      echo "QWiser ConfigMap created successfully."

      # Output values for use by other Bicep resources
      echo "{ \"ilbId\": \"$ILB_ID\", \"frontendIpConfigId\": \"$FRONTEND_IP_CONFIG_ID\", \"loadBalancerIp\": \"$LB_IP\" }" > $AZ_SCRIPTS_OUTPUT_PATH

      echo "NGINX Ingress installation complete!"
    '''
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Deployment script resource ID')
output scriptId string = nginxInstallScript.id

@description('Internal LoadBalancer resource ID')
output ilbId string = nginxInstallScript.properties.outputs.ilbId

@description('Frontend IP configuration resource ID for PLS')
output frontendIpConfigId string = nginxInstallScript.properties.outputs.frontendIpConfigId

@description('LoadBalancer IP address')
output loadBalancerIp string = nginxInstallScript.properties.outputs.loadBalancerIp
