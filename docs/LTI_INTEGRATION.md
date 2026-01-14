# QWiser University - LTI 1.3 Integration Guide

> **Last Updated**: 2026-01-14
> **Version**: 1.0.0
> **Audience**: University IT / LMS Administrators

---

## Overview

QWiser supports LTI 1.3 for seamless integration with your Learning Management System (LMS). This guide covers integration with Moodle, but the same principles apply to Canvas, Blackboard, and other LTI 1.3-compliant platforms.

**What LTI enables:**
- Single sign-on from LMS to QWiser
- User identity passed securely (name, email, roles)
- Course context for personalized learning paths
- No separate QWiser accounts required

---

## Prerequisites

Before starting LTI integration:

- [ ] QWiser fully deployed and accessible at your custom domain (e.g., `https://qwiser.university.edu`)
- [ ] SSL certificate configured and working
- [ ] LMS administrator access
- [ ] Network connectivity between LMS and QWiser (firewall rules configured)

---

## LTI Endpoints

QWiser exposes the following LTI endpoints. Replace `QWISER_DOMAIN` with your deployment domain.

| Endpoint | URL | Purpose |
|----------|-----|---------|
| Dynamic Registration | `https://QWISER_DOMAIN/api/lti/register` | Auto-configure the tool |
| Configuration | `https://QWISER_DOMAIN/api/lti/config` | Manual config JSON |
| OIDC Login | `https://QWISER_DOMAIN/api/lti/login` | OIDC initiation |
| Launch | `https://QWISER_DOMAIN/api/lti/launch` | Tool launch endpoint |
| JWKS | `https://QWISER_DOMAIN/api/lti/jwks` | Public keys for signature verification |

---

## Method A: Dynamic Registration (Recommended)

LTI 1.3 Dynamic Registration automates most of the configuration. This is the preferred method.

### Step 1: Initiate Registration in Moodle

1. Log in to Moodle as an administrator
2. Navigate to **Site administration** > **Plugins** > **Activity modules** > **External tool** > **Manage tools**
3. In the **Tool URL** field at the top, enter:
   ```
   https://QWISER_DOMAIN/api/lti/register
   ```
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

### Step 4: Configure Privacy Settings

1. Click on the QWiser tool to edit
2. Update privacy settings:

| Field | Recommended Value |
|-------|-------------------|
| Share launcher's name with tool | `Always` |
| Share launcher's email with tool | `Always` |
| Accept grades from the tool | `Never` (unless using grade passback) |

3. Click **Save changes**

### Step 5: Configure QWiser

Add the platform configuration to Azure App Configuration:

```
lti:platform:issuer         = https://moodle.university.edu
lti:platform:client-id      = <from registration>
lti:platform:deployment-id  = <from registration>
lti:platform:oidc-auth-url  = https://moodle.university.edu/mod/lti/auth.php
lti:platform:jwks-url       = https://moodle.university.edu/mod/lti/certs.php
lti:platform:token-url      = https://moodle.university.edu/mod/lti/token.php
```

**Important:** After updating App Configuration, restart the `public-api` pods:

```bash
kubectl rollout restart deployment/public-api -n qwiser
```

---

## Method B: Manual Configuration

If Dynamic Registration isn't supported or fails, configure manually.

### Step 1: Add Tool Manually in Moodle

1. In **Manage tools**, click **Configure a tool manually**
2. Fill in:

| Field | Value |
|-------|-------|
| Tool name | `QWiser` |
| Tool URL | `https://QWISER_DOMAIN/api/lti/launch` |
| Tool description | `AI-powered learning platform` |
| LTI version | `LTI 1.3` |
| Public key type | `Keyset URL` |
| Public keyset | `https://QWISER_DOMAIN/api/lti/jwks` |
| Initiate login URL | `https://QWISER_DOMAIN/api/lti/login` |
| Redirection URI(s) | `https://QWISER_DOMAIN/api/lti/launch` |
| Default launch container | `New window` |

3. Click **Save changes**

### Step 2: Retrieve Moodle Platform Details

After saving, Moodle displays platform details. Note:

| Field | App Config Key |
|-------|----------------|
| Platform ID | `lti:platform:issuer` |
| Client ID | `lti:platform:client-id` |
| Deployment ID | `lti:platform:deployment-id` |
| Public keyset URL | `lti:platform:jwks-url` |
| Access token URL | `lti:platform:token-url` |
| Authentication request URL | `lti:platform:oidc-auth-url` |

### Step 3: Configure QWiser

Add keys to Azure App Configuration as shown in Method A, Step 5.

---

## Integration with Other LMS Platforms

### Canvas

1. Navigate to **Admin** > **Developer Keys** > **+ Developer Key** > **+ LTI Key**
2. Use **Paste JSON** method with:
   ```
   https://QWISER_DOMAIN/api/lti/config
   ```
3. Copy the Client ID and configure in App Configuration

### Blackboard

1. Navigate to **System Admin** > **LTI Tool Providers** > **Register LTI 1.3/Advantage Tool**
2. Enter JWKS URL: `https://QWISER_DOMAIN/api/lti/jwks`
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

---

## Security Considerations

### Network Security

Ensure your firewall allows:
- **Outbound from QWiser to LMS**: For JWKS fetching and token verification
- **Inbound from LMS to QWiser**: For LTI launch requests

### HTTPS Requirements

- **QWiser must use HTTPS** with a valid SSL certificate
- **LMS should use HTTPS** for secure token transmission
- Self-signed certificates are NOT supported

### Token Security

LTI tokens are signed JWTs. QWiser:
- Validates signatures using the LMS's JWKS endpoint
- Checks token expiration
- Verifies issuer and audience claims

### User Data

QWiser receives from the LMS:
- User identifier (sub claim)
- Name (if privacy settings allow)
- Email (if privacy settings allow)
- Course context
- Roles (student, instructor, admin)

QWiser does NOT receive:
- LMS passwords
- Other user accounts
- Full course rosters

---

## Troubleshooting

### "Tool configuration not found"

**Cause**: Mismatch in endpoint URLs

**Solution**:
1. Verify Login URL and Redirect URI match exactly (including trailing slash)
2. Check QWiser is reachable from Moodle server:
   ```bash
   curl -v https://QWISER_DOMAIN/api/lti/jwks
   ```

### "Invalid signature"

**Cause**: JWKS mismatch or clock skew

**Solution**:
1. Verify JWKS URLs return valid JSON:
   ```bash
   curl https://moodle.university.edu/mod/lti/certs.php
   curl https://QWISER_DOMAIN/api/lti/jwks
   ```
2. Check server time synchronization (NTP)
3. Ensure App Configuration has correct platform URLs

### "Invalid issuer"

**Cause**: `lti:platform:issuer` doesn't match the LMS

**Solution**:
1. Check the issuer in the JWT token (decode at jwt.io)
2. Update `lti:platform:issuer` to match exactly

### "Network error" during registration

**Cause**: Firewall blocking QWiser from reaching LMS

**Solution**:
1. Verify DNS resolution from QWiser pods:
   ```bash
   kubectl exec -it deployment/public-api -n qwiser -- nslookup moodle.university.edu
   ```
2. Check outbound firewall rules

### Launch redirects to login page

**Cause**: Session not established properly

**Solution**:
1. Ensure cookies are allowed (SameSite=None for cross-origin)
2. Check frontend-env-config.yaml has correct domain
3. Verify CORS settings if needed

---

## App Configuration Reference

Complete list of LTI-related configuration keys:

| Key | Description | Example |
|-----|-------------|---------|
| `lti:platform:issuer` | LMS platform identifier | `https://moodle.university.edu` |
| `lti:platform:client-id` | OAuth client ID from LMS | `abc123xyz` |
| `lti:platform:deployment-id` | Deployment ID from LMS | `1` |
| `lti:platform:oidc-auth-url` | OIDC authorization endpoint | `https://moodle.university.edu/mod/lti/auth.php` |
| `lti:platform:jwks-url` | LMS public keys endpoint | `https://moodle.university.edu/mod/lti/certs.php` |
| `lti:platform:token-url` | Token endpoint (for services) | `https://moodle.university.edu/mod/lti/token.php` |

---

## Verification Checklist

After completing LTI integration:

- [ ] Dynamic registration completed (or manual config saved)
- [ ] Platform configuration in Azure App Configuration
- [ ] `public-api` pods restarted
- [ ] Test course created with QWiser activity
- [ ] Student launch works (lands in QWiser authenticated)
- [ ] Instructor launch works
- [ ] User name/email displayed correctly in QWiser
- [ ] Multiple concurrent users tested

---

## Related Documentation

- [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) - Full deployment guide
- [APPCONFIG_REFERENCE.md](./APPCONFIG_REFERENCE.md) - All configuration keys
- [POST_DEPLOYMENT.md](./POST_DEPLOYMENT.md) - Post-deployment verification
