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
| `ALLOWED_SIGNUP_DOMAIN` | No | Comma-separated list of allowed email domains for SSO signup (see Domain Restrictions) |

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

The SSO button is integrated into the signin page when OmniAuth is enabled. The feature flag `isOmniAuthEnabled()` controls visibility.

### Vue Component

The `SsoButton.vue` component handles SSO initiation:

```vue
<!-- src/apps/session/components/SsoButton.vue -->
<script setup>
const handleSsoLogin = () => {
  const form = document.createElement('form');
  form.method = 'POST';
  form.action = '/auth/sso/oidc';

  // CSRF token (required)
  const csrfInput = document.createElement('input');
  csrfInput.type = 'hidden';
  csrfInput.name = 'shrimp';  // Project uses 'shrimp' as CSRF param name
  csrfInput.value = csrfStore.shrimp;
  form.appendChild(csrfInput);

  document.body.appendChild(form);
  form.submit();
};
</script>
```

### CSRF Protection

OmniAuth routes (`/auth/sso/*`) use OAuth's built-in state parameter for CSRF protection instead of form tokens.

**How it works:**
1. **Request phase:** OmniAuth generates a random `state` value, stores it in session, and includes it in the authorization URL
2. **Callback phase:** The IdP returns the `state`; OmniAuth validates it matches before processing

**Implementation note:** Rack::Protection is configured to skip `/auth/sso/*` routes (see `lib/onetime/middleware/security.rb`). The frontend still includes the `shrimp` token for consistency, but it is not validated for SSO routes. This avoids conflicts between form-based CSRF and OAuth's built-in protection.

### Feature Flag

The SSO button only appears when:
1. `ENABLE_OMNIAUTH=true` is set
2. The bootstrap payload includes `features.omniauth: true`

Check in Vue: `isOmniAuthEnabled()` from `src/utils/features.ts`

### Static HTML (Custom Integrations)

For non-Vue integrations:

```html
<form method="POST" action="/auth/sso/oidc">
  <button type="submit">Login with SSO</button>
</form>
```

Note: No CSRF token is required for SSO routes. OAuth's state parameter handles CSRF protection.

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

## Domain Restrictions

Optionally restrict which email domains can create accounts via SSO. Uses the same configuration as regular signup.

### Configuration

```bash
# Single domain
export ALLOWED_SIGNUP_DOMAIN=company.com

# Multiple domains
export ALLOWED_SIGNUP_DOMAIN=company.com,subsidiary.com,partner.org
```

### Behavior

| Configuration | Behavior |
|--------------|----------|
| Not set or empty | All domains allowed (default) |
| Single domain | Only that domain can create accounts |
| Multiple domains | Any listed domain can create accounts |

### Security Considerations

- **Generic error messages:** Users from unauthorized domains see "Your email domain is not authorized for SSO signup" - the allowed domains are never revealed.
- **Audit logging:** Rejected attempts are logged with event `omniauth_domain_rejected` including the obscured email and domain for security review.
- **Case-insensitive:** Domain matching is case-insensitive (`COMPANY.COM` matches `company.com`).
- **Subdomains not matched:** `sub.company.com` does NOT match `company.com` - add each subdomain explicitly if needed.
- **Existing accounts:** Domain restrictions only apply to new account creation. Existing accounts with linked SSO identities can still log in regardless of domain restrictions.

### Example: Enterprise Deployment

```bash
# Only employees from company.com can use SSO
export ALLOWED_SIGNUP_DOMAIN=company.com

# Include subsidiary and contractor domains
export ALLOWED_SIGNUP_DOMAIN=company.com,subsidiary.com,contractors.company.com
```

### Troubleshooting Domain Restrictions

**"Your email domain is not authorized for SSO signup"**

1. Verify the user's email domain is in `ALLOWED_SIGNUP_DOMAIN`
2. Check for typos (e.g., `comapny.com` vs `company.com`)
3. Remember subdomains must be listed explicitly
4. Check logs for `omniauth_domain_rejected` events

**Existing user can't log in after domain restriction added**

Domain restrictions only affect NEW account creation. If the user already has an account with a linked SSO identity, they can still log in. To block existing users, remove their account or unlink their SSO identity.

## Security Notes

- PKCE is enabled by default for enhanced security
- Discovery document is fetched from issuer URL
- Email from IdP is trusted (no additional verification)
- Sessions use same security settings as password auth
- Domain restrictions validated before account creation

## Error Handling

### Error Display Flow

SSO errors (authentication failures, domain rejections, etc.) are displayed via the following flow:

```
OmniAuth failure callback
    │
    ▼
omniauth_on_failure hook logs error to stderr and Auth::Logging
    │
    ▼
Redirect to /signin?auth_error=sso_failed
    │
    ▼
Frontend Login.vue reads query param, displays localized error
    │
    ▼
Query param cleared from URL (prevents error on refresh)
```

The `auth_error` query param approach was chosen over flash messages because:
- Vue frontend doesn't read server-side flash messages directly
- Query params work reliably across the OAuth redirect chain
- Error codes map to i18n keys for localized messages

### Error Codes

The `auth_error` query parameter maps to i18n keys in `locales/content/en/session-auth.json`:

| Code | i18n Key | Meaning |
|------|----------|---------|
| `sso_failed` | `web.login.errors.sso_failed` | General SSO authentication failure |
| `token_missing` | `web.login.errors.token_missing` | Magic link token not in URL |
| `token_expired` | `web.login.errors.token_expired` | Magic link expired |
| `token_invalid` | `web.login.errors.token_invalid` | Magic link token invalid |

### Customizing Error Messages

The `omniauth_failure_error_flash` configuration sets a default message (used for logging):

```ruby
# apps/web/auth/config/hooks/omniauth.rb
auth.omniauth_failure_error_flash 'SSO authentication failed. Please try again or use password login.'
```

The actual user-facing message comes from the frontend i18n system based on the `auth_error` query param.

## Files

### Backend

| File | Purpose |
|------|---------|
| `apps/web/auth/config/features/omniauth.rb` | Rodauth feature configuration (routes, OIDC settings) |
| `apps/web/auth/config/hooks/omniauth.rb` | Callback hooks (domain validation, account creation) |
| `apps/web/auth/migrations/006_omniauth_identities.rb` | Database migration for identity linking |
| `lib/onetime/auth_config.rb` | Feature flag method (`omniauth_enabled?`) |
| `etc/defaults/auth.defaults.yaml` | Default configuration |
| `apps/web/core/views/serializers/config_serializer.rb` | Exposes `omniauth` flag to frontend |

### Frontend

| File | Purpose |
|------|---------|
| `src/apps/session/components/SsoButton.vue` | SSO login button component |
| `src/apps/session/components/AuthMethodSelector.vue` | Integrates SSO with other auth methods |
| `src/utils/features.ts` | `isOmniAuthEnabled()` feature detection |
| `src/types/declarations/bootstrap.d.ts` | TypeScript types for `features.omniauth` |

### Tests

| File | Coverage |
|------|----------|
| `apps/web/auth/spec/integration/omniauth_csrf_spec.rb` | CSRF token validation |
| `apps/web/auth/spec/unit/omniauth_domain_validation_spec.rb` | Domain restriction logic |
| `src/tests/apps/session/components/SsoButton.spec.ts` | Frontend component tests |
| `src/tests/apps/session/components/AuthMethodSelector.spec.ts` | Integration with auth selector |

## Testing

### Manual Testing Checklist

1. **Feature flag disabled:**
   - [ ] SSO button should NOT appear on signin page
   - [ ] POST to `/auth/sso/oidc` returns 404

2. **Feature flag enabled (no IdP configured):**
   - [ ] SSO button appears on signin page
   - [ ] Clicking button shows configuration error

3. **Fully configured:**
   - [ ] SSO button redirects to IdP
   - [ ] Successful auth creates account and redirects to dashboard
   - [ ] Session is properly authenticated

4. **Domain restrictions:**
   - [ ] Allowed domain: account created successfully
   - [ ] Disallowed domain: 403 error, generic message
   - [ ] Check logs for `omniauth_domain_rejected` event

### Running Tests

```bash
# Backend unit tests (no Valkey required)
bundle exec rspec apps/web/auth/spec/unit/omniauth_domain_validation_spec.rb

# Backend integration tests (requires Valkey)
bundle exec rspec apps/web/auth/spec/integration/omniauth_csrf_spec.rb

# Frontend tests
pnpm test src/tests/apps/session/components/SsoButton.spec.ts
pnpm test src/tests/apps/session/components/AuthMethodSelector.spec.ts
```

## See Also

- [Switching to Full Auth Mode](switching-to-full-mode.md)
- [Rodauth OmniAuth](https://github.com/janko/rodauth-omniauth)
- [OmniAuth OpenID Connect](https://github.com/omniauth/omniauth_openid_connect)
