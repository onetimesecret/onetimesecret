# OmniAuth Testing Guide

## Local IdP Setup

### Zitadel (recommended)

```bash
docker run -d --name zitadel \
  -p 8080:8080 \
  ghcr.io/zitadel/zitadel:latest start-dev
```

Access console at `http://localhost:8080`. Default admin: `zitadel-admin@zitadel.localhost` / `Password1!`

Create a Web Application project:
- Redirect URI: `http://localhost:3000/auth/sso/oidc/callback`
- Grant type: Authorization Code + PKCE
- Note the Client ID and Client Secret

### Keycloak (alternative)

```bash
docker run -d --name keycloak \
  -p 8080:8080 \
  -e KEYCLOAK_ADMIN=admin \
  -e KEYCLOAK_ADMIN_PASSWORD=admin \
  quay.io/keycloak/keycloak:latest start-dev
```

Create realm, client, and user via admin console at `http://localhost:8080/admin`.

## Environment Configuration

```bash
export ENABLE_OMNIAUTH=true
export OIDC_ISSUER=http://localhost:8080           # Zitadel/Keycloak base URL
export OIDC_CLIENT_ID=<from-idp>
export OIDC_CLIENT_SECRET=<from-idp>
export OIDC_REDIRECT_URI=http://localhost:3000/auth/sso/oidc/callback
```

For Zitadel, issuer is typically `http://localhost:8080`.
For Keycloak, issuer is `http://localhost:8080/realms/<realm-name>`.

## Verification

```bash
# Feature flag exposed
curl -s http://localhost:3000/bootstrap/me | jq '.features.omniauth'
# Should return: true

# OIDC discovery endpoint reachable
curl -s $OIDC_ISSUER/.well-known/openid-configuration | jq '.authorization_endpoint'
```

## Test Scenarios

| Scenario | Expected |
|----------|----------|
| SSO button visibility | Appears on `/signin` when `ENABLE_OMNIAUTH=true` |
| New user login | Account created, redirected to dashboard |
| Existing user login | Logged in via linked identity |
| Domain restriction | Redirected to `/signin?auth_error=sso_failed` |
| CSRF missing | 403 Forbidden (Rack::Protection rejects) |
| IdP denies access | Redirected to `/signin?auth_error=sso_failed` |

## Automated Tests

```bash
# Frontend component tests
pnpm test src/tests/apps/session/components/SsoButton.spec.ts
pnpm test src/tests/apps/session/components/AuthMethodSelector.spec.ts

# Backend (mocks OmniAuth callback)
bundle exec rspec apps/web/auth/spec/
```

## Debugging

```bash
# Watch auth logs (failures print to stderr)
# Look for: [OmniAuth FAILURE] type=... class=... msg=...

# Common issues:
# - "CSRF detected" → shrimp token missing or invalid (Rack::Protection)
# - "InvalidToken" → route_csrf mismatch (should be bypassed for OmniAuth)
# - "Discovery failed" → OIDC_ISSUER URL incorrect or unreachable
# - "Callback mismatch" → OIDC_REDIRECT_URI doesn't match IdP config
# - "Errors.App.NotFound" → Client ID doesn't match IdP configuration
```
