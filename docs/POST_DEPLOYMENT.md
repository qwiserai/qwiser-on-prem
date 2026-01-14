# QWiser University - Post-Deployment Guide

> **Last Updated**: 2026-01-14
> **Version**: 1.0.0
> **Audience**: University IT Infrastructure Teams

---

## Overview

This guide covers post-deployment configuration tasks after the main infrastructure and application deployment is complete.

---

## LTI 1.3 Integration (Moodle/Canvas)

### Prerequisites

- [ ] QWiser deployment complete and accessible
- [ ] LMS administrator access (Moodle, Canvas, Blackboard)
- [ ] Public HTTPS URL for QWiser (e.g., `https://qwiser.myuniversity.edu`)

### Step 1: Generate RSA Key Pair

```bash
# Generate RSA private key
openssl genrsa -out lti-private-key.pem 2048

# Extract public key
openssl rsa -in lti-private-key.pem -pubout -out lti-public-key.pem

# Display private key for Key Vault upload
cat lti-private-key.pem
```

### Step 2: Store Private Key in Key Vault

```bash
KEYVAULT_NAME="qwiser-prod-kv"

# Upload private key (replace newlines with \n for single-line storage)
az keyvault secret set \
    --vault-name "$KEYVAULT_NAME" \
    --name "LTI-PRIVATE-KEY" \
    --file lti-private-key.pem
```

### Step 3: Register QWiser in LMS

#### Moodle Configuration

1. Navigate to: Site Administration > Plugins > Activity modules > External tool > Manage tools
2. Click "Configure a tool manually"
3. Configure:

| Setting | Value |
|---------|-------|
| Tool name | QWiser |
| Tool URL | `https://qwiser.myuniversity.edu/lti/launch` |
| LTI version | LTI 1.3 |
| Public key type | RSA key |
| Public key | (paste contents of lti-public-key.pem) |
| Initiate login URL | `https://qwiser.myuniversity.edu/lti/login` |
| Redirection URI(s) | `https://qwiser.myuniversity.edu/lti/callback` |
| Services | Enable appropriate services |

4. Save and note the following values:
   - Platform ID (Issuer)
   - Client ID
   - Deployment ID
   - Public keyset URL (JWKS)
   - Access token URL
   - Authentication request URL

#### Canvas Configuration

1. Navigate to: Admin > Developer Keys > + Developer Key > LTI Key
2. Configure:

| Setting | Value |
|---------|-------|
| Key Name | QWiser |
| Redirect URIs | `https://qwiser.myuniversity.edu/lti/callback` |
| Target Link URI | `https://qwiser.myuniversity.edu/lti/launch` |
| OpenID Connect Initiation URL | `https://qwiser.myuniversity.edu/lti/login` |
| JWK Method | Public JWK URL |
| Public JWK URL | `https://qwiser.myuniversity.edu/.well-known/jwks.json` |

3. Save and note the Client ID

### Step 4: Update App Configuration

```bash
APPCONFIG_NAME="qwiser-prod-appconfig"

# Moodle example values
az appconfig kv set -n "$APPCONFIG_NAME" --key "lti:platform:issuer" --value "https://moodle.myuniversity.edu" --label production --yes
az appconfig kv set -n "$APPCONFIG_NAME" --key "lti:platform:client_id" --value "YOUR_CLIENT_ID" --label production --yes
az appconfig kv set -n "$APPCONFIG_NAME" --key "lti:platform:deployment_id" --value "YOUR_DEPLOYMENT_ID" --label production --yes
az appconfig kv set -n "$APPCONFIG_NAME" --key "lti:platform:oidc_auth_url" --value "https://moodle.myuniversity.edu/mod/lti/auth.php" --label production --yes
az appconfig kv set -n "$APPCONFIG_NAME" --key "lti:platform:oauth_token_url" --value "https://moodle.myuniversity.edu/mod/lti/token.php" --label production --yes
az appconfig kv set -n "$APPCONFIG_NAME" --key "lti:platform:jwks_url" --value "https://moodle.myuniversity.edu/mod/lti/certs.php" --label production --yes

# Trigger config refresh
az appconfig kv set -n "$APPCONFIG_NAME" --key "sentinel" --value "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --label production --yes
```

### Step 5: Test LTI Launch

1. In LMS, add QWiser as an external tool to a course
2. Click to launch QWiser
3. Verify successful authentication and course context

---

## DNS Configuration

### Create CNAME Record

Get Front Door hostname:
```bash
FRONTDOOR_HOSTNAME=$(az afd endpoint show \
    --resource-group "qwiser-prod-rg" \
    --profile-name "qwiser-prod-fd" \
    --endpoint-name "qwiser-prod-fd-endpoint" \
    --query "hostName" -o tsv)

echo "CNAME target: $FRONTDOOR_HOSTNAME"
```

Create DNS record:
```
Type: CNAME
Name: qwiser (or your subdomain)
Value: qwiser-prod-fd-xxxxx.z01.azurefd.net
TTL: 3600
```

### Add Custom Domain to Front Door

```bash
az afd custom-domain create \
    --resource-group "qwiser-prod-rg" \
    --profile-name "qwiser-prod-fd" \
    --custom-domain-name "qwiser-university" \
    --host-name "qwiser.myuniversity.edu" \
    --certificate-type ManagedCertificate \
    --minimum-tls-version TLS12
```

### Domain Validation

Azure Front Door requires domain ownership verification:

```bash
# Check validation status
az afd custom-domain show \
    --resource-group "qwiser-prod-rg" \
    --profile-name "qwiser-prod-fd" \
    --custom-domain-name "qwiser-university" \
    --query "validationProperties"
```

If validation requires TXT record, create:
```
Type: TXT
Name: _dnsauth.qwiser
Value: (provided validation token)
TTL: 3600
```

---

## Testing Checklist

### Infrastructure Tests

| Test | Command | Expected Result |
|------|---------|-----------------|
| Front Door health | `curl -I https://qwiser.myuniversity.edu/ready` | HTTP 200 |
| TLS certificate | `openssl s_client -connect qwiser.myuniversity.edu:443` | Valid certificate |
| API health | `curl https://qwiser.myuniversity.edu/api/healthz` | `{"status":"healthy"}` |

### Application Tests

| Test | How to Verify |
|------|---------------|
| User registration | Create new account via web UI |
| Login/logout | Sign in and sign out |
| Content upload | Upload a PDF document |
| Tree generation | Create knowledge tree from uploaded content |
| Question generation | Generate questions from tree |
| Chat functionality | Start a chat session with content |

### Integration Tests

| Test | How to Verify |
|------|---------------|
| LTI launch | Launch from LMS, verify SSO |
| Database connectivity | Check internal-db logs for successful queries |
| Redis connectivity | Check public-api logs for cache operations |
| AI endpoints | Generate content, verify AI model responses |

---

## Monitoring Setup

### Azure Monitor Alerts

Create alerts for critical metrics:

```bash
RESOURCE_GROUP="qwiser-prod-rg"
ACTION_GROUP_ID="/subscriptions/.../resourceGroups/.../providers/microsoft.insights/actionGroups/qwiser-alerts"

# High CPU Alert
az monitor metrics alert create \
    --name "AKS-High-CPU" \
    --resource-group "$RESOURCE_GROUP" \
    --scopes "/subscriptions/.../resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ContainerService/managedClusters/qwiser-prod-aks" \
    --condition "avg node_cpu_usage_percentage > 80" \
    --window-size 5m \
    --evaluation-frequency 1m \
    --action "$ACTION_GROUP_ID"

# Pod restart alert
az monitor metrics alert create \
    --name "Pod-Restarts" \
    --resource-group "$RESOURCE_GROUP" \
    --scopes "/subscriptions/.../resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ContainerService/managedClusters/qwiser-prod-aks" \
    --condition "sum kube_pod_container_status_restarts_total > 5" \
    --window-size 15m \
    --action "$ACTION_GROUP_ID"
```

### Log Analytics Queries

Save these queries in Log Analytics:

**Failed requests:**
```kusto
ContainerLog
| where LogEntry contains "ERROR"
| summarize count() by bin(TimeGenerated, 1h), ContainerID
| order by TimeGenerated desc
```

**AI API latency:**
```kusto
ContainerLog
| where LogEntry contains "ai_request_duration"
| extend duration = extract("duration=([0-9.]+)", 1, LogEntry)
| summarize avg(todouble(duration)) by bin(TimeGenerated, 5m)
```

---

## Backup Configuration

### Export App Configuration

```bash
# Full export
az appconfig kv export \
    -n "$APPCONFIG_NAME" \
    --label production \
    --destination file \
    --path ./backup/appconfig-$(date +%Y%m%d).json \
    --format json

# Export to Azure Storage
az storage blob upload \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name backups \
    --file ./backup/appconfig-$(date +%Y%m%d).json \
    --name "appconfig/appconfig-$(date +%Y%m%d).json"
```

### Export Key Vault Secrets (Metadata Only)

```bash
# List secrets (not values - security!)
az keyvault secret list --vault-name "$KEYVAULT_NAME" -o table > ./backup/keyvault-secrets-list.txt
```

### Database Backup

MySQL Flexible Server has automated backups. To create on-demand backup:

```bash
az mysql flexible-server backup create \
    --resource-group "$RESOURCE_GROUP" \
    --name "qwiser-prod-mysql" \
    --backup-name "manual-$(date +%Y%m%d)"
```

---

## Security Hardening

### Post-Deployment Security Checklist

- [ ] Disable Azure CLI access from public network (if not needed)
- [ ] Enable Azure Defender recommendations
- [ ] Review Network Security Groups
- [ ] Enable audit logging for Key Vault
- [ ] Configure Azure AD Conditional Access for admin users
- [ ] Review RBAC assignments (principle of least privilege)

### WAF Tuning

After 1-2 weeks of production traffic, review WAF logs and adjust:

```bash
# View blocked requests
az monitor log-analytics query \
    --workspace "$WORKSPACE_ID" \
    --analytics-query "AzureDiagnostics | where Category == 'FrontDoorWebApplicationFirewallLog' | where action_s == 'Block'"
```

---

## Maintenance Windows

### Recommended Schedule

| Task | Frequency | Duration | Impact |
|------|-----------|----------|--------|
| K8s upgrades | Monthly | 30-60 min | Rolling restarts |
| Certificate renewal | Automatic | None | None |
| Database maintenance | Weekly (Azure managed) | None | None |
| Secret rotation | Quarterly | 15 min | Rolling restarts |

### Pre-Maintenance Communication

Template for IT announcement:
```
Subject: QWiser Scheduled Maintenance - [DATE]

QWiser will undergo scheduled maintenance on [DATE] from [TIME] to [TIME].

Expected impact:
- Brief service interruptions (< 5 minutes)
- Users may need to refresh their browser

Actions required:
- Save any in-progress work before maintenance window
- No action needed after maintenance

Contact: it-support@university.edu
```

---

## Related Documentation

- [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) - Full deployment guide
- [SECRET_ROTATION.md](./SECRET_ROTATION.md) - Secret rotation procedures
- [APPCONFIG_REFERENCE.md](./APPCONFIG_REFERENCE.md) - Configuration reference
