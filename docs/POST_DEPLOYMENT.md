# QWiser University - Post-Deployment Guide

> **Last Updated**: 2026-01-15
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
KEYVAULT_NAME=$(jq -r '.keyVaultName.value' deployment-outputs.json)

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
APPCONFIG_NAME=$(jq -r '.appConfigName.value' deployment-outputs.json)

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

## Related Documentation

- [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) - Full deployment guide
- [SECRET_ROTATION.md](./SECRET_ROTATION.md) - Secret rotation procedures
- [APPCONFIG_REFERENCE.md](./APPCONFIG_REFERENCE.md) - Configuration reference
