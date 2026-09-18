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

Keycloak and Zitadel both act as SAML 2.0 IdPs as well: create a SAML client
(Keycloak) or SAML application (Zitadel) with the SP EntityID and ACS URL from
the [SAML section](per-install-sso.md#saml-20-1) of the SSO guide, download
the realm/instance signing certificate, and fill `SAML_IDP_*` instead of
`OIDC_*`.

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
export AUTHENTICATION_MODE=full
export AUTH_SSO_ENABLED=true
export OIDC_ISSUER=http://localhost:8080           # Zitadel/Keycloak base URL
export OIDC_CLIENT_ID=<from-idp>
export OIDC_CLIENT_SECRET=<from-idp>
```
The callback URL is auto-constructed from the request host at runtime (e.g., `https://{host}/auth/sso/oidc/callback`). Register this URL with the IdP. The correct value is displayed on the domain SSO config screen.

For Zitadel, issuer is typically `http://localhost:8080`.
For Keycloak, issuer is `http://localhost:8080/realms/<realm-name>`.

## Verification

```bash
# SSO configuration exposed to the sign-in page
curl -s http://localhost:3000/bootstrap/me | jq '.features.sso'
# Should show enabled: true and a non-empty providers array

# OIDC discovery endpoint reachable
curl -s $OIDC_ISSUER/.well-known/openid-configuration | jq '.authorization_endpoint'
```

## Test Scenarios

| Scenario | Expected |
|----------|----------|
| SSO button visibility | Appears on `/signin` when SSO is enabled and bootstrap returns at least one configured provider |
| No configured provider | No platform SSO button is rendered; the provider strategy is not registered unless per-domain SSO is enabled |
| New user login | Account created, redirected to dashboard |
| Existing user login | Logged in via linked identity |
| Domain restriction | Redirected to `/signin?auth_error=domain_not_allowed`; the UI does not disclose allowed domains |
| OAuth state mismatch | OmniAuth rejects callback (CSRF protection) |
| IdP denies access | Redirected to `/signin?auth_error=sso_cancelled` |
| Other IdP failure | Redirected to `/signin?auth_error=sso_failed` |
| SAML response with no pending sign-in (IdP-initiated, or the session cookie was withheld) | Redirected to `/signin?auth_error=sso_failed`; log shows `[saml_response_refused] reason=saml_no_pending_request` |
| SAML response presented twice | Second presentation refused, `reason=saml_assertion_replayed` |

## Automated Tests

```bash
# Frontend component tests
pnpm test src/tests/apps/session/components/SsoButton.spec.ts
pnpm test src/tests/apps/session/components/AuthMethodSelector.spec.ts

# Backend (mocks OmniAuth callback)
tests/lanes/run full-sqlite

# SAML: real signed responses from a throwaway IdP (spec/support/saml/test_idp.rb),
# no mocks of ruby-saml
tests/lanes/run unit --only spec/unit/onetime/sso_provider/request_bound_saml_spec.rb
tests/lanes/run full-pg --only apps/web/auth/spec/integration/full/tenant_saml_sso_spec.rb
try --agent try/unit/security/saml_assertion_replay_guard_try.rb
```

`SamlSpec::TestIdp` generates its own keypair per process and signs
assertions with ruby-saml's own `XMLSecurity::Document`, so the specs run the
gem's full validate path (signature, audience, destination, conditions,
InResponseTo). No key material is checked in. It is not auto-loaded; require
it explicitly, because the application only loads ruby-saml when a SAML
provider is configured.

## Debugging

```bash
# Watch auth logs (failures print to stderr)
# Look for: [OmniAuth FAILURE] type=... class=... msg=...

# Common issues:
# - "csrf_detected" → OAuth state parameter mismatch (session expired or manipulated)
# - "Discovery failed" → OIDC_ISSUER URL incorrect or unreachable
# - "Callback mismatch" → callback URL doesn't match IdP's allowed redirect URIs
# - "Errors.App.NotFound" → Client ID doesn't match IdP configuration
# - "[saml_response_refused] reason=..." → a RequestBoundSAML gate; the reason
#   table is in per-install-sso.md under "SAML sign-in refused"
# - "type=invalid_ticket" on a SAML route → ruby-saml rejected the document
#   (signature, audience, destination, validity window, cert expiry)
```

## Manual Testing Checklist

### Feature flag disabled (`AUTH_SSO_ENABLED=false` or unset)

- [ ] SSO button does NOT appear on the signin page
- [ ] POST to `/auth/sso/{provider}` returns 404

### Feature flag enabled, no platform IdP configured

- [ ] SSO button does NOT appear on the signin page
- [ ] The bootstrap response has an empty `features.sso.providers` array
- [ ] The platform provider route is not registered

Per-domain SSO is the exception: with `ORGS_SSO_ENABLED=true`, the routes are
registered with placeholder credentials and receive each domain's credentials at request time.

### Fully configured (feature flag + IdP credentials)

- [ ] SSO button on signin page redirects to the IdP login screen
- [ ] Successful authentication at the IdP creates a new account
- [ ] After authentication, user is redirected to the dashboard
- [ ] Session is properly authenticated (user can access protected pages)
- [ ] Cancelling or denying access at the IdP returns to `/signin?auth_error=sso_cancelled`

### Domain restrictions (`ALLOWED_SIGNUP_DOMAIN`)

- [ ] User with an allowed email domain can create an account via SSO
- [ ] User with a disallowed email domain returns to `/signin?auth_error=domain_not_allowed` without listing allowed domains
- [ ] Logs contain an `omniauth_domain_rejected` event for the rejected attempt

### Multi-provider

- [ ] Each configured provider shows its own button on the signin page
- [ ] Buttons use the correct route names (e.g., `/auth/sso/oidc`, `/auth/sso/entra`)
- [ ] Buttons display the correct provider display names
