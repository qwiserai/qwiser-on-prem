# QWiser University - LTI 1.3 Integration Guide

## Overview

QWiser requires LTI 1.3 for integration with your Learning Management System (LMS). This guide covers integration with Moodle, but the same principles apply to other LTI 1.3-compliant platforms.

**What LTI enables:**
- Single sign-on from LMS to QWiser
- User identity passed securely (name, email, roles)
- Course context for personalized learning paths
- No separate QWiser accounts required

---

## Prerequisites

Before starting LTI integration:

- [ ] QWiser fully deployed and accessible at your custom domain (e.g., `https://qwiser.myuniversity.edu`)
- [ ] SSL certificate configured and working
- [ ] LMS administrator access
- [ ] Network connectivity between LMS and QWiser (firewall rules configured)

---

## Dynamic Registration (Recommended)

LTI 1.3 Dynamic Registration automates most of the configuration. This is the preferred method.

### Step 1: Initiate Registration in Moodle

1. Log in to Moodle as an administrator
2. Navigate to **Site administration** > **Plugins** > **Activity modules** > **External tool** > **Manage tools**
3. In the **Tool URL** field at the top, enter:
   ```
   https://qwiser.myuniversity.edu/api/lti/register
   ```
   (Replace with your actual QWiser domain)
4. Click **Add LTI Advantage**

### Step 2: Complete Registration

1. Your browser redirects to QWiser's registration page
2. QWiser automatically:
   - Fetches your LMS's OpenID configuration
   - Registers itself with your LMS
   - Displays registration results
3. **Copy the configuration values** shown:
   - `LTI_PLATFORM_ISSUER`
   - `LTI_PLATFORM_CLIENT_ID`
   - `LTI_PLATFORM_DEPLOYMENT_ID`
   - `LTI_PLATFORM_OIDC_AUTH_URL`
   - `LTI_PLATFORM_JWKS_URL`
   - `LTI_PLATFORM_TOKEN_URL`
4. Click **Complete Registration**

### Step 3: Activate in Moodle

1. Back in Moodle, the tool appears as **Pending**
2. Click **Activate** to enable it

### Step 4: Configure QWiser

Add the platform configuration to Azure App Configuration. You can use the Azure CLI:

```bash
# Get App Config name from deployment outputs
APPCONFIG_NAME=$(jq -r '.appConfigName.value' deployment-outputs.json | tr -d '\r')

# Platform configuration (replace with values from registration)
az appconfig kv set -n "$APPCONFIG_NAME" --key "lti:platform:issuer" --value "https://moodle.myuniversity.edu" --label production --yes
az appconfig kv set -n "$APPCONFIG_NAME" --key "lti:platform:client_id" --value "YOUR_CLIENT_ID" --label production --yes
az appconfig kv set -n "$APPCONFIG_NAME" --key "lti:platform:deployment_id" --value "YOUR_DEPLOYMENT_ID" --label production --yes
az appconfig kv set -n "$APPCONFIG_NAME" --key "lti:platform:oidc_auth_url" --value "https://moodle.myuniversity.edu/mod/lti/auth.php" --label production --yes
az appconfig kv set -n "$APPCONFIG_NAME" --key "lti:platform:jwks_url" --value "https://moodle.myuniversity.edu/mod/lti/certs.php" --label production --yes
az appconfig kv set -n "$APPCONFIG_NAME" --key "lti:platform:oauth_token_url" --value "https://moodle.myuniversity.edu/mod/lti/token.php" --label production --yes

# Trigger config refresh (services hot-reload within ~45 seconds)
az appconfig kv set -n "$APPCONFIG_NAME" --key "sentinel" --value "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --label production --yes
```

> **Note:** LTI configuration hot-reloads automatically. No pod restart required.

---

## Integration with Other LMS Platforms

### Canvas

1. Navigate to **Admin** > **Developer Keys** > **+ Developer Key** > **+ LTI Key**
2. Use **Paste JSON** method with:
   ```
   https://qwiser.myuniversity.edu/api/lti/config
   ```
   (Replace with your actual QWiser domain)
3. Copy the Client ID and configure in App Configuration

### Blackboard

1. Navigate to **System Admin** > **LTI Tool Providers** > **Register LTI 1.3/Advantage Tool**
2. Enter JWKS URL: `https://qwiser.myuniversity.edu/api/lti/jwks`
3. Configure launch URL and login URL as above

---

## Create a Test Course Activity

### Step 1: Create or Select a Course

1. In Moodle, go to **Site home**
2. Create a new course or select an existing one

### Step 2: Add QWiser Activity

1. Turn on **Edit mode**
2. Click **Add an activity or resource**
3. Select **External tool**
4. Configure:
   - **Activity name**: `QWiser Study Materials`
   - **Preconfigured tool**: Select `QWiser`
   - **Launch container**: `New window` (recommended)
5. Click **Save and return to course**

### Step 3: Test the Launch

1. Click on the QWiser activity
2. Moodle initiates the LTI 1.3 flow:
   - POST to QWiser's login endpoint
   - Redirect to Moodle's auth endpoint
   - Moodle sends id_token to QWiser's launch endpoint
3. You should land in QWiser, authenticated as the Moodle user
4. 
---

## Verification Checklist

After completing LTI integration:

- [ ] Dynamic registration completed
- [ ] Platform configuration in Azure App Configuration
- [ ] Sentinel key updated to trigger config refresh
- [ ] Test course created with QWiser activity
- [ ] Student launch works (lands in QWiser authenticated)
- [ ] Instructor launch works
- [ ] User name/email displayed correctly in QWiser
- [ ] Multiple concurrent users tested

---

## Related Documentation

- [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) - Full deployment guide
- [APPCONFIG_REFERENCE.md](./APPCONFIG_REFERENCE.md) - All configuration keys
