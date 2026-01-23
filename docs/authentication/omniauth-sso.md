# OmniAuth SSO Integration

Single sign-on via external identity providers using OpenID Connect.

## Overview

OmniAuth enables authentication through external identity providers (IdPs) like Zitadel, Keycloak, Auth0, or Okta. Users authenticate at the IdP and are redirected back with verified identity claims.

**Requirements:**
- Full auth mode enabled (`AUTHENTICATION_MODE=full`)
- SQL database with migrations applied
- OIDC-compliant identity provider

## Quick Start

### 1. Run Migration

```bash
# Note sequel requires a password, doesn't use pg_hba trust rules.
sequel -m apps/web/auth/migrations $AUTH_DATABASE_URL_MIGRATIONS
```

Creates `account_identities` table for storing provider/uid links.

### 2. Set Environment Variables

```bash
export ENABLE_OMNIAUTH=true
export OIDC_ISSUER=https://auth.example.com
export OIDC_CLIENT_ID=your-client-id
export OIDC_CLIENT_SECRET=your-client-secret
export OIDC_REDIRECT_URI=https://app.example.com/auth/sso/oidc/callback
```

### 3. Restart Application

The feature loads automatically when `ENABLE_OMNIAUTH=true`.

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `ENABLE_OMNIAUTH` | Yes | Set to `true` to enable |
| `OIDC_ISSUER` | Yes | IdP's issuer URL (used for OIDC discovery) |
| `OIDC_CLIENT_ID` | Yes | OAuth client ID from IdP |
| `OIDC_CLIENT_SECRET` | Yes | OAuth client secret from IdP |
| `OIDC_REDIRECT_URI` | Yes | Callback URL registered with IdP |
| `OIDC_PROVIDER_NAME` | No | Provider name in routes (default: `oidc`). **Must remain `oidc` for frontend compatibility.** |

## Routes

With default configuration:

| Method | Path | Description |
|--------|------|-------------|
| POST | `/auth/sso/oidc` | Initiates SSO flow |
| GET | `/auth/sso/oidc/callback` | Receives IdP response |

## Authentication Flow

```
User clicks "Login with SSO"
    │
    ▼
POST /auth/sso/oidc
    │
    ▼
Redirect to IdP (with PKCE challenge)
    │
    ▼
User authenticates at IdP
    │
    ▼
IdP redirects to /auth/sso/oidc/callback
    │
    ▼
Token exchange (code → tokens)
    │
    ▼
Account lookup by email
    ├─ Found → Link identity, sync session
    └─ Not found → Create account, create Customer, sync session
    │
    ▼
Redirect to dashboard (authenticated)
```

## Behavior

**Account Matching:** Accounts are matched by email address. If an SSO user's email matches an existing password account, the identity is linked to that account.

**Account Creation:** New accounts are created automatically for unrecognized emails. A Customer record and default workspace are created (same as regular signup).

**Email Verification:** SSO accounts are auto-verified. The IdP handles email verification.

**MFA:** Not enforced for SSO logins. The IdP is responsible for multi-factor authentication.

## Provider Configuration

### Zitadel

1. Create a new application in Zitadel console
2. Select "Web" application type
3. Set authentication method to "PKCE"
4. Configure redirect URIs:
   - `https://your-app.com/auth/sso/oidc/callback`
5. Enable scopes: `openid`, `email`, `profile`
6. Copy Client ID and Client Secret

```bash
export OIDC_ISSUER=https://auth.zitadel.example.com
export OIDC_CLIENT_ID=123456789@your-project
export OIDC_CLIENT_SECRET=secret-from-zitadel
export OIDC_REDIRECT_URI=https://your-app.com/auth/sso/oidc/callback
```

### Keycloak

1. Create a new client in your realm
2. Set Access Type to "confidential"
3. Enable "Standard Flow"
4. Add redirect URI
5. Copy Client ID and Secret from Credentials tab

```bash
export OIDC_ISSUER=https://keycloak.example.com/realms/your-realm
export OIDC_CLIENT_ID=your-client
export OIDC_CLIENT_SECRET=secret-from-keycloak
export OIDC_REDIRECT_URI=https://your-app.com/auth/sso/oidc/callback
```

### Auth0

1. Create a new "Regular Web Application"
2. Configure Allowed Callback URLs
3. Copy Domain, Client ID, and Client Secret

```bash
export OIDC_ISSUER=https://your-tenant.auth0.com
export OIDC_CLIENT_ID=your-client-id
export OIDC_CLIENT_SECRET=your-client-secret
export OIDC_REDIRECT_URI=https://your-app.com/auth/sso/oidc/callback
```

## Frontend Integration

Add an SSO button to your login form:

```html
<form method="POST" action="/auth/sso/oidc">
  <button type="submit">Login with SSO</button>
</form>
```

Or use a link with JavaScript:

```html
<a href="#" onclick="document.getElementById('sso-form').submit()">
  Login with SSO
</a>
<form id="sso-form" method="POST" action="/auth/sso/oidc" style="display:none"></form>
```

## Database Schema

The migration creates:

```sql
CREATE TABLE account_identities (
  id BIGINT PRIMARY KEY,
  account_id BIGINT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  provider VARCHAR NOT NULL,
  uid VARCHAR NOT NULL,
  UNIQUE (provider, uid)
);
CREATE INDEX ON account_identities (account_id);
```

## Troubleshooting

### "Missing OIDC configuration"

Check that all required environment variables are set:
```bash
echo $OIDC_ISSUER $OIDC_CLIENT_ID $OIDC_CLIENT_SECRET
```

### Callback returns error

1. Verify redirect URI matches exactly (including trailing slash)
2. Check IdP logs for detailed error
3. Ensure client secret is correct

### Discovery fails

Test OIDC discovery endpoint:
```bash
curl https://your-issuer/.well-known/openid-configuration
```

### Account not created

Check application logs for errors during `after_omniauth_create_account` hook. Ensure Redis is accessible for Customer creation.

## Deployment Modes

### Standalone/Self-hosted

The current implementation supports a single OIDC provider configured via environment variables. This is ideal for:
- Single-organization deployments
- Self-hosted instances with one IdP
- Development and testing

**Constraint:** The frontend hardcodes `/auth/sso/oidc` as the SSO endpoint. Do not change `OIDC_PROVIDER_NAME` from its default value `oidc`.

### Multi-tenant (Future)

Per-organization SSO (BYOIDC) is not yet implemented. When needed, this would require:
- Organization SSO config stored in maindb (PostgreSQL)
- Dynamic OmniAuth setup based on organization context
- URL pattern like `/auth/sso/org/:org_extid/oidc`
- Self-service admin UI for IdP configuration

See industry patterns: WorkOS Organizations, Auth0 Organizations, Stripe Organizations.

#### Recommended architecture for Multi-tenant

```
Customer A (Okta) ──┐
                    ├──► Zitadel ──► OIDC ──► Onetime Secret
Customer B (Azure) ─┘
```

Rather than:

```
Customer A (Okta)  ──► SAML ──► Onetime Secret
Customer B (Azure) ──► OIDC ──► Onetime Secret
```

The Zitadel-as-broker approach is one protocol in your app, federation complexity handled by the IdP.

## Security Notes

- PKCE is enabled by default for enhanced security
- Discovery document is fetched from issuer URL
- Email from IdP is trusted (no additional verification)
- Sessions use same security settings as password auth

## Files

- `apps/web/auth/config/features/omniauth.rb` - Feature configuration
- `apps/web/auth/config/hooks/omniauth.rb` - Callback hooks
- `apps/web/auth/migrations/006_omniauth_identities.rb` - Database migration
- `lib/onetime/auth_config.rb` - Feature flag (`omniauth_enabled?`)
- `etc/defaults/auth.defaults.yaml` - Default configuration

## See Also

- [Switching to Full Auth Mode](switching-to-full-mode.md)
- [Rodauth OmniAuth](https://github.com/janko/rodauth-omniauth)
- [OmniAuth OpenID Connect](https://github.com/omniauth/omniauth_openid_connect)
