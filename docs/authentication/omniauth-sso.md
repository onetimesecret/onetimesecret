# SSO Configuration

**Status:** Active
**Version:** 2.0 (2026-03-15)
**Authentication Mode:** Full (Rodauth)

---

## Overview

SSO enables authentication through external identity providers. Users authenticate at the IdP and are redirected back with verified identity claims.

Two integration patterns are available:

| Pattern | When to use | Env var prefix |
|---------|------------|----------------|
| **Generic OIDC** | Customer runs their own IdP (Zitadel, Keycloak, Auth0, Okta) | `OIDC_*` |
| **Provider-specific** | Direct integration with a specific service | `ENTRA_*`, `GOOGLE_*`, `GITHUB_*` |

Generic OIDC uses the `/.well-known/openid-configuration` discovery document. Provider-specific gems handle OAuth quirks (tenant models, non-standard scopes, token formats) so the operator doesn't have to.

Multiple providers can be active simultaneously. Each provider that has its required env vars set will register automatically at boot. The frontend renders one button per configured provider.

**Requirements:**
- `AUTHENTICATION_MODE=full`
- SQL database with migrations applied
- At least one provider's credentials configured

## Quick Start

### 1. Run Migration

```bash
sequel -m apps/web/auth/migrations $AUTH_DATABASE_URL_MIGRATIONS
```

Creates `account_identities` table for storing provider/uid links.

### 2. Set Environment Variables

```bash
# Enable SSO
export AUTH_SSO_ENABLED=true

# Configure one or more providers (see Provider Configuration below)
export OIDC_ISSUER=https://auth.example.com
export OIDC_CLIENT_ID=your-client-id
export OIDC_CLIENT_SECRET=your-client-secret
export OIDC_REDIRECT_URI=https://app.example.com/auth/sso/oidc/callback
```

### 3. Restart Application

Providers load automatically when `AUTH_SSO_ENABLED=true` and their required env vars are present.

## Environment Variables

### Global

| Variable | Required | Description |
|----------|----------|-------------|
| `AUTH_SSO_ENABLED` | Yes | `true` to enable SSO |
| `SSO_DISPLAY_NAME` | No | Default button label for generic OIDC (e.g., "Company SSO") |
| `ALLOWED_SIGNUP_DOMAIN` | No | Comma-separated allowed email domains for SSO signup |

### Generic OIDC

| Variable | Required | Description |
|----------|----------|-------------|
| `OIDC_ISSUER` | Yes | Issuer URL (must serve `/.well-known/openid-configuration`) |
| `OIDC_CLIENT_ID` | Yes | OAuth client ID |
| `OIDC_CLIENT_SECRET` | No | OAuth client secret (empty for PKCE-only flows) |
| `OIDC_REDIRECT_URI` | Yes | Callback: `https://{host}/auth/sso/oidc/callback` |
| `OIDC_ROUTE_NAME` | No | URL segment (default: `oidc`) |

### Microsoft Entra ID

| Variable | Required | Description |
|----------|----------|-------------|
| `ENTRA_TENANT_ID` | Yes | Directory (tenant) ID from Azure portal |
| `ENTRA_CLIENT_ID` | Yes | Application (client) ID |
| `ENTRA_CLIENT_SECRET` | Yes | Client secret value (not the secret ID) |
| `ENTRA_REDIRECT_URI` | Yes | Callback: `https://{host}/auth/sso/entra/callback` |
| `ENTRA_ROUTE_NAME` | No | URL segment (default: `entra`) |
| `ENTRA_DISPLAY_NAME` | No | Button label (default: `Microsoft`) |

### Google

| Variable | Required | Description |
|----------|----------|-------------|
| `GOOGLE_CLIENT_ID` | Yes | OAuth 2.0 client ID |
| `GOOGLE_CLIENT_SECRET` | Yes | OAuth 2.0 client secret |
| `GOOGLE_REDIRECT_URI` | Yes | Callback: `https://{host}/auth/sso/google/callback` |
| `GOOGLE_ROUTE_NAME` | No | URL segment (default: `google`) |
| `GOOGLE_DISPLAY_NAME` | No | Button label (default: `Google`) |

### GitHub

| Variable | Required | Description |
|----------|----------|-------------|
| `GITHUB_CLIENT_ID` | Yes | OAuth App client ID |
| `GITHUB_CLIENT_SECRET` | Yes | OAuth App client secret |
| `GITHUB_REDIRECT_URI` | Yes | Callback: `https://{host}/auth/sso/github/callback` |
| `GITHUB_ROUTE_NAME` | No | URL segment (default: `github`) |
| `GITHUB_DISPLAY_NAME` | No | Button label (default: `GitHub`) |

## Routes

Each configured provider registers two routes:

| Method | Path | Description |
|--------|------|-------------|
| POST | `/auth/sso/{provider}` | Initiates SSO flow |
| GET | `/auth/sso/{provider}/callback` | Receives IdP response |

Where `{provider}` is the route name (`oidc`, `entra`, `google`, `github`, or custom).

## Authentication Flow

```
User clicks "Login with {Provider}"
    │
    ▼
POST /auth/sso/{provider}
    │
    ▼
Redirect to IdP (with PKCE challenge + state)
    │
    ▼
User authenticates at IdP
    │
    ▼
IdP redirects to /auth/sso/{provider}/callback
    │
    ▼
Token exchange (code → tokens)
    │
    ▼
Account lookup by email
    ├─ Found → Link identity, sync session
    └─ Not found → Create account + Customer + workspace, sync session
    │
    ▼
Redirect to dashboard (authenticated)
```

All hooks (`account_from_omniauth`, `before_omniauth_create_account`, etc.) are provider-agnostic. Adding a new provider does not require hook changes.

## Behavior

**Account Matching:** By email (case-insensitive). An SSO user whose email matches an existing password account gets their identity linked to that account.

**Account Creation:** Automatic for unrecognized emails. Creates Customer record and default workspace.

**Multi-Provider:** One account can have multiple linked identities (e.g., OIDC + Entra). The `account_identities` table stores `(provider, uid)` pairs per account.

**Email Verification:** SSO accounts are auto-verified. The IdP handles verification.

**MFA:** Not enforced for SSO logins. The IdP is responsible for MFA.

## Provider Configuration

### Generic OIDC (Zitadel, Keycloak, Auth0, Okta)

Use this for any IdP that exposes `/.well-known/openid-configuration`.

#### Zitadel

1. Console → Applications → New → Web
2. Authentication method: PKCE
3. Redirect URI: `https://{host}/auth/sso/oidc/callback`
4. Scopes: `openid`, `email`, `profile`
5. Copy **Client ID** and **Client Secret**

```bash
OIDC_ISSUER=https://auth.zitadel.example.com
OIDC_CLIENT_ID=123456789@your-project
OIDC_CLIENT_SECRET=secret-from-zitadel
OIDC_REDIRECT_URI=https://your-app.com/auth/sso/oidc/callback
```

#### Keycloak

1. Admin Console → Realm → Clients → Create
2. Access Type: confidential, Standard Flow: enabled
3. Redirect URI: `https://{host}/auth/sso/oidc/callback`
4. Copy **Client ID** and **Secret** from Credentials tab

```bash
OIDC_ISSUER=https://keycloak.example.com/realms/your-realm
OIDC_CLIENT_ID=your-client
OIDC_CLIENT_SECRET=secret-from-keycloak
OIDC_REDIRECT_URI=https://your-app.com/auth/sso/oidc/callback
```

#### Auth0

1. Dashboard → Applications → Create → Regular Web Application
2. Settings → Allowed Callback URLs: `https://{host}/auth/sso/oidc/callback`
3. Copy **Domain**, **Client ID**, **Client Secret**

```bash
OIDC_ISSUER=https://your-tenant.auth0.com
OIDC_CLIENT_ID=your-client-id
OIDC_CLIENT_SECRET=your-client-secret
OIDC_REDIRECT_URI=https://your-app.com/auth/sso/oidc/callback
```

### Microsoft Entra ID

Uses the `omniauth-entra-id` gem. Handles Microsoft's tenant model and token format.

#### Azure Portal Setup

1. **Azure Portal** → Microsoft Entra ID → App registrations → New registration
2. **Name**: e.g., "Onetime Secret SSO"
3. **Supported account types**: Single tenant (or multi-tenant if needed)
4. **Redirect URI**: Web → `https://{host}/auth/sso/entra/callback`
5. Click **Register**

Get the values:
- **Application (client) ID** → `ENTRA_CLIENT_ID`
- **Directory (tenant) ID** → `ENTRA_TENANT_ID`
- Certificates & secrets → New client secret → copy **Value** (not Secret ID) → `ENTRA_CLIENT_SECRET`

```bash
ENTRA_TENANT_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
ENTRA_CLIENT_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
ENTRA_CLIENT_SECRET=client-secret-value
ENTRA_REDIRECT_URI=https://your-app.com/auth/sso/entra/callback
```

Note: Entra client secrets expire. Set a calendar reminder for rotation.

### Google

Uses the `omniauth-google-oauth2` gem.

#### Google Cloud Console Setup

1. **Google Cloud Console** → APIs & Services → Credentials → Create credentials → OAuth client ID
2. **Application type**: Web application
3. **Authorized redirect URIs**: `https://{host}/auth/sso/google/callback`
4. Copy **Client ID** and **Client secret**

```bash
GOOGLE_CLIENT_ID=xxxxxxxxxxxx.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=GOCSPX-xxxxxxxxxxxxx
GOOGLE_REDIRECT_URI=https://your-app.com/auth/sso/google/callback
```

Requires: OAuth consent screen configured, `email` and `profile` scopes approved.

### GitHub

Uses the `omniauth-github` gem.

#### GitHub Setup

1. **GitHub** → Settings → Developer settings → OAuth Apps → New OAuth App
2. **Authorization callback URL**: `https://{host}/auth/sso/github/callback`
3. Copy **Client ID** and generate a **Client secret**

```bash
GITHUB_CLIENT_ID=Iv1.xxxxxxxxxxxx
GITHUB_CLIENT_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
GITHUB_REDIRECT_URI=https://your-app.com/auth/sso/github/callback
```

Note: For GitHub Organizations, use GitHub Apps instead of OAuth Apps for finer-grained permissions.

## Domain Restrictions

Restrict which email domains can create accounts via SSO.

```bash
# Single domain
ALLOWED_SIGNUP_DOMAIN=company.com

# Multiple domains
ALLOWED_SIGNUP_DOMAIN=company.com,subsidiary.com,partner.org
```

| Configuration | Behavior |
|--------------|----------|
| Not set or empty | All domains allowed (default) |
| Set | Only listed domains can create new accounts |

- Case-insensitive matching
- Subdomains are NOT matched (`sub.company.com` does not match `company.com`)
- Restrictions apply to **new account creation only** — existing linked accounts can still log in
- Rejected attempts logged as `omniauth_domain_rejected` with obscured email
- Error message is generic (allowed domains are never revealed to the user)

### Existing user can't log in after domain restriction added

Domain restrictions only affect **new account creation**. Existing accounts with linked SSO identities can still log in regardless of domain restrictions. To block existing users, remove their account or unlink their SSO identity from the `account_identities` table.

## Self-Serve Configuration (Future)

The current implementation is install-time only — env vars set at deploy, read at boot.

A self-serve path is architecturally possible for credential management. OmniAuth's `setup` phase allows a per-request lambda to override strategy options (client_id, client_secret, tenant_id) with values loaded from the database.

**What can be self-serve:**
- Credentials for an already-registered strategy type
- Per-organization IdP settings

**What cannot be self-serve:**
- Adding new strategy gems (requires rebuild/redeploy)
- Registering new strategy types (Rack middleware is assembled at boot)

The available provider types are fixed at deploy time (what's in the Gemfile). The credentials for each type can be made dynamic.

This would require: a provider config model, encrypted secret storage, admin UI, and a connection validation flow. Not yet implemented.

## Frontend Integration

SSO buttons appear on the signin page when `AUTH_SSO_ENABLED=true`. The bootstrap payload includes a `providers` array, and `AuthMethodSelector.vue` renders one `SsoButton` per configured provider.

Feature check: `isOmniAuthEnabled()` from `src/utils/features.ts`.

CSRF protection for `/auth/sso/*` routes uses OAuth's state parameter, not form tokens. `Rack::Protection` is configured to skip these routes (see `lib/onetime/middleware/security.rb`).

### Static HTML (Custom Integrations)

For non-Vue integrations, a plain form POST works:

```html
<form method="POST" action="/auth/sso/{provider}">
  <button type="submit">Login with SSO</button>
</form>
```

No CSRF token required -- OAuth's state parameter handles CSRF protection for SSO routes.

## Database Schema

```sql
CREATE TABLE account_identities (
  id BIGINT PRIMARY KEY,
  account_id BIGINT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  provider VARCHAR NOT NULL,  -- e.g. 'oidc', 'entra_id', 'google_oauth2', 'github'
  uid VARCHAR NOT NULL,       -- IdP-specific subject identifier
  UNIQUE (provider, uid)
);
CREATE INDEX ON account_identities (account_id);
```

The `provider` column stores the OmniAuth strategy name, which may differ from the route name (e.g., strategy `entra_id` at route `/auth/sso/entra`).

## Error Handling

```
OmniAuth failure → omniauth_on_failure hook (logs to stderr + Auth::Logging)
    → redirect to /signin?auth_error=sso_failed
    → Frontend reads query param, displays localized error
    → Query param cleared from URL
```

| `auth_error` Code | i18n Key | Meaning |
|-------------------|----------|---------|
| `sso_failed` | `web.login.errors.sso_failed` | General SSO failure |

## Troubleshooting

### "Missing OIDC configuration" / "Missing Entra ID configuration"

Check required env vars are set and non-empty:
```bash
echo $OIDC_ISSUER $OIDC_CLIENT_ID    # for generic OIDC
echo $ENTRA_TENANT_ID $ENTRA_CLIENT_ID $ENTRA_CLIENT_SECRET  # for Entra
```

### Callback returns error

1. Verify redirect URI matches exactly what's registered with the IdP (including trailing slash)
2. Check IdP logs for detailed error
3. Ensure client secret is correct and not expired (Entra secrets expire)

### OIDC discovery fails

```bash
curl https://your-issuer/.well-known/openid-configuration
```

### Account not created

Check logs for errors in `after_omniauth_create_account`. Ensure Redis/Valkey is accessible for Customer creation.

### CSRF error on callback

If you see `encoded token is not a string`: the CSRF bypass for SSO routes is misconfigured. Check that `lib/onetime/middleware/security.rb` skips `/auth/sso/*` and that the `omniauth_request_validation_phase` hook is empty in `hooks/omniauth.rb`.

## Security Notes

- PKCE enabled by default (generic OIDC)
- OAuth state parameter provides CSRF protection for the redirect flow
- Email from IdP is trusted (no additional verification performed)
- Sessions use same security settings as password auth
- Domain restrictions validated before account creation
- Client secrets should be rotated per provider's recommendations

## Codebase Reference

### Backend

| File | Role |
|------|------|
| `apps/web/auth/config/features/omniauth.rb` | Provider registration (one method per provider type) |
| `apps/web/auth/config/hooks/omniauth.rb` | Callback hooks — provider-agnostic |
| `apps/web/auth/config.rb` | Feature gating (`if omniauth_enabled?`) |
| `apps/web/auth/migrations/006_omniauth_identities.rb` | Identity table migration |
| `lib/onetime/auth_config.rb` | `omniauth_enabled?`, `sso_providers` |
| `etc/defaults/auth.defaults.yaml` | Feature flag defaults |
| `apps/web/core/views/serializers/config_serializer.rb` | `build_omniauth_config` → frontend bootstrap |
| `lib/onetime/middleware/security.rb` | CSRF bypass for `/auth/sso/*` |

### Frontend

| File | Role |
|------|------|
| `src/apps/session/components/SsoButton.vue` | SSO login button (accepts provider props) |
| `src/apps/session/components/AuthMethodSelector.vue` | Renders SSO buttons per provider |
| `src/utils/features.ts` | `isOmniAuthEnabled()` |

### Tests

| File | Coverage |
|------|----------|
| `apps/web/auth/spec/integration/omniauth_csrf_spec.rb` | CSRF configuration |
| `apps/web/auth/spec/unit/omniauth_domain_validation_spec.rb` | Domain restriction logic |
| `apps/web/auth/spec/config/hooks/omniauth_spec.rb` | Email normalization |

## Testing

See [OmniAuth Testing Guide](omniauth-testing.md) for local IdP setup and test procedures.

```bash
# Backend
bundle exec rspec apps/web/auth/spec/unit/omniauth_domain_validation_spec.rb
bundle exec rspec apps/web/auth/spec/integration/omniauth_csrf_spec.rb

# Frontend
pnpm test src/tests/apps/session/components/SsoButton.spec.ts
```

## See Also

- [OmniAuth Testing Guide](omniauth-testing.md)
- [Switching to Full Auth Mode](switching-to-full-mode.md)
- [rodauth-omniauth](https://github.com/janko/rodauth-omniauth)
- [omniauth-entra-id](https://github.com/pond/omniauth-entra-id)
- [omniauth_openid_connect](https://github.com/omniauth/omniauth_openid_connect)
