# Per-Domain SSO Configuration

This document describes the per-domain SSO configuration system and the conditions required for the SSO configuration tab to appear in organization settings.

## Overview

SSO configuration is bound to individual custom domains, not organizations. This enables multi-IdP configurations where different domains owned by the same organization can use different identity providers.

## Prerequisites

The SSO tab visibility is controlled by the `manage_sso` entitlement. The following conditions must be met for the tab to appear.

## Configuration Layers

### 1. billing.yaml

The `manage_sso` entitlement must be defined in two places:

**Root-level entitlements section** (defines valid entitlement keys):

```yaml
entitlements:
  manage_sso:
    category: advanced
    description: Single sign-on configuration and management
```

**Plan entitlements array** (assigns entitlement to plan):

```yaml
plans:
  identity_plus_v1:
    entitlements:
      - create_secrets
      - view_receipt
      - api_access
      - custom_domains
      - manage_sso      # Must match root-level key exactly
      - custom_branding
```

### 2. Stripe Product Metadata

After updating `billing.yaml`, push to Stripe:

```bash
bin/ots billing catalog push
```

The Stripe Product metadata should contain:

```
entitlements: "create_secrets,view_receipt,api_access,custom_domains,manage_sso,custom_branding"
```

### 3. Redis Plan Cache

Sync from Stripe to Redis:

```bash
bin/ots billing catalog pull
```

Verify the entitlement is cached:

```bash
redis-cli SISMEMBER 'billing_plan:identity_plus_v1:entitlements' 'manage_sso'
# Returns 1 if present, 0 if missing
```

### 4. Organization Assignment

The organization must be subscribed to a plan that includes `manage_sso`. The entitlements are computed dynamically at runtime:

```ruby
# Backend: lib/onetime/models/features/with_entitlements.rb
org.entitlements  # Returns plan entitlements from Redis cache
org.can?('manage_sso')  # Returns true/false
```

## Data Flow

### Entitlement Resolution (Tab Visibility)

```
billing.yaml
    │
    ▼ bin/ots billing catalog push
Stripe Product Metadata
    │
    ▼ bin/ots billing catalog pull
Redis Plan Cache (billing_plan:<plan_id>:entitlements)
    │
    ▼ org.entitlements (via Billing::Plan.load)
Organization API Response
    │
    ▼ can(ENTITLEMENTS.MANAGE_SSO)
SSO Tab Visibility
```

### Login Flow (Runtime)

**Prerequisite:** Organization must have a custom domain with SSO configured.

```
User visits https://{custom-domain}/signin
    │
    ▼
POST /auth/sso/{provider}
    │
    ▼
Public host headers → DetectHost → display domain → CustomDomain::SsoConfig
    │
    ▼
Inject domain credentials into OmniAuth strategy
    │
    ▼
Redirect to domain's IdP
    │
    ▼
IdP callback → tenant validation → session created
```

Resolution chain (`apps/web/auth/config/hooks/omniauth_tenant.rb`):

| Step | Lookup | Result |
|------|--------|--------|
| 1 | Public host headers, resolved by `DetectHost` | `env['onetime.display_domain'] = secrets.acme.com` |
| 2 | `CustomDomain.load_by_display_domain(display_domain)` | CustomDomain record |
| 3 | `custom_domain.identifier` | Domain identifier |
| 4 | `CustomDomain::SsoConfig.find_by_domain_id(domain_id)` | SSO credentials |
| 5 | `domain_config.to_omniauth_options` | OmniAuth strategy injection |

**Security:** Tenant context (domain_id) stored in session during request phase, validated on callback to prevent cross-tenant redirect attacks.

**Identity linking is platform-only.** The three linking paths documented for platform SSO — the authenticated [Connected Identities panel](per-install-sso.md#connected-identities-authenticated-linking-from-account-settings), the [sign-in interstitial](per-install-sso.md#sign-in-interstitial-password-challenge-linking), and [mailbox-proof linking](per-install-sso.md#mailbox-proof-linking-passwordless-accounts) — are **not** offered on a tenant callback, and the trusted-IdP email-linking flag has no effect here. Each of those paths is gated on `session[:validated_omniauth_domain_id]` being `nil`, which a tenant callback always sets. A tenant admin controls their own IdP's assertions, so a tenant-issuer identity must not be bound to an account located by email (or to whatever account happens to hold the current platform session). Tenant SSO keeps the refusal: an unlinked identity whose email matches an existing account is refused with `account_exists_link_required`. Authenticated tenant-surface linking requires org-membership verification first and is tracked in #3849.

## OIDC for sovereign Microsoft Entra tenants

Per-domain `entra_id` uses the commercial Microsoft authority and cannot be
pointed at a sovereign cloud. Configure a sovereign tenant as generic OIDC:

| Field | Value |
|-------|-------|
| `provider_type` | `oidc` |
| `issuer` (US Government) | `https://login.microsoftonline.us/{tenant_id}/v2.0` |
| `issuer` (Microsoft Cloud China / 21Vianet) | `https://login.partner.microsoftonline.cn/{tenant_id}/v2.0` |

Replace `{tenant_id}` with the directory's tenant ID. The issuer must be the
**v2.0** issuer. Do not use the v1 issuer,
`https://sts.windows.net/{tenant_id}/`: its issuer origin differs from the
origin of the authorization endpoint. Per-domain CSP derives an origin from
the issuer, while Chromium checks the authorization endpoint destination, so
that split blocks the sign-in redirect. `SSO_FORM_ACTION_ORIGINS` is the
process-wide fallback for such split-endpoint OIDC configurations, but the v2.0
issuer avoids the split for Entra sovereign tenants.

The issuer is entered manually; there is no sovereign-cloud preset. It must be
an HTTPS URL with a public host, and it must serve valid OIDC discovery. Check
the exact value against the IdP's published metadata and test the connection
before enabling SSO. A syntactically valid typo can pass URL validation but
fail discovery; on Chromium-family browsers, a wrong derived origin can also
appear as an apparent no-op with a `form-action` CSP violation.

### Access control

Generic OIDC is not assumed to enforce Entra application assignments. Set
`allowed_domains` to the email domains that may use the custom domain. The
allowlist is enforced on every tenant SSO callback; an empty list allows every
email domain that the IdP authenticates. This differs from `entra_id`, where
app assignment is treated as the access-control boundary.

### Switching an existing Entra configuration

Changing a tenant from `entra_id` to `oidc` changes its identity key. Under
`entra_id`, identities use provider `entra` and uid `tid+oid`; under `oidc`,
they use the OIDC route name (normally `oidc`) and uid `sub`. Existing users
are therefore treated as unlinked after the switch unless the stored identity
records are migrated deliberately.

`bin/ots sso backfill-issuer` does not migrate this change: it only stamps an
issuer onto legacy identity rows whose issuer is `''`. Sovereign tenants could
not have worked through `entra_id`, so this is migration debt only for a
previously configured tenant that was pointed at the wrong cloud.

## Troubleshooting

### SSO Tab Not Appearing

1. **Check billing mode**:
   ```bash
   # If billing disabled, SSO should appear automatically
   echo $BILLING_ENABLED
   ```

2. **Verify Redis cache**:
   ```bash
   redis-cli SMEMBERS 'billing_plan:<plan_id>:entitlements'
   ```

3. **Check Stripe metadata**:
   ```bash
   bin/ots billing catalog pull --dry-run
   ```

4. **Verify organization's plan**:
   ```ruby
   # In console
   org = Organization.load(extid)
   org.planid
   org.entitlements
   org.can?('manage_sso')
   ```

5. **Check frontend debug logs** (if enabled):
   ```
   [OrganizationSettings] SSO visibility: ...
   [useEntitlements] can(): { entitlement: "manage_sso", ... }
   ```

### Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| SSO tab missing | `manage_sso` not in plan entitlements | Add to billing.yaml, push, pull |
| Entitlement in YAML but not Redis | Push/pull not run | Run `bin/ots billing catalog push && pull` |
| Mismatch between YAML key and plan | Root uses `sso`, plan uses `manage_sso` | Use consistent naming (`manage_sso`) |
| SSO configured but login fails | No custom domain with SSO config | Add custom domain and configure SSO |
| Platform SSO used instead of domain SSO | Accessing via canonical domain | Use domain's custom URL |

### SSO Login Blocked on Chromium-Family Browsers (CSP `form-action`)

**Symptom:** Clicking the domain SSO button appears to do nothing, and the browser console reports a Content-Security-Policy error for `form-action`. This affects Chrome, Edge, and other Chromium-family browsers; Firefox does not enforce `form-action` across this redirect chain.

**Cause:** The sign-in page posts to `/auth/sso/{provider}`, which redirects to the domain's IdP authorization endpoint. CSP must permit that IdP destination as well as the initial same-origin form target.

**Normal behavior:** The application resolves the domain's enabled SSO configuration per request and adds its IdP origin to `form-action` only for that domain's response. Standard tenant OIDC configurations whose issuer and authorization endpoint share an origin, and commercial-cloud tenant Entra configurations, require no environment configuration.

**Exceptions:**

- **OIDC issuer differs from the authorization endpoint:** The per-request policy derives the issuer origin, but CSP checks the authorization endpoint's origin. Add that endpoint origin to `SSO_FORM_ACTION_ORIGINS`.
- **Sovereign-cloud Entra:** Per-domain Entra uses the commercial Microsoft endpoint, `https://login.microsoftonline.com`; it cannot be redirected to a sovereign cloud through `SSO_FORM_ACTION_ORIGINS`. Configure the domain as `oidc` with the sovereign issuer instead, so its origin is added per request.
- **Tenant SSO configuration cannot be read while rendering the sign-in page:** No IdP origin is added for that response. The browser reports the CSP error until the lookup succeeds; `SSO_FORM_ACTION_ORIGINS` is a manual fallback where this availability risk cannot block sign-in.

`SSO_FORM_ACTION_ORIGINS` is process-wide: it widens CSP for every page, tenant, and canonical host. Use it only for a known exception, with the exact additional origin:

```bash
SSO_FORM_ACTION_ORIGINS="https://auth.example.gov"
```

Operational triage — the `TenantCspExtras` log signals, how to read the emitted header, and resolution by cause: [docs/runbooks/tenant-sso-csp-form-action.md](../runbooks/tenant-sso-csp-form-action.md).

### Custom-Domain POST Returns 403 (`HttpOrigin`)

This is separate from CSP. `HttpOrigin` validates the **source** of `POST /auth/sso/{provider}`; CSP `form-action` validates the IdP **destination** after the redirect.

With proxies that rewrite `Host` to the canonical host while forwarding the public custom domain in a trusted header, older installations can reject custom-domain SSO requests with `403` and `attack prevented by Rack::Protection::HttpOrigin`. Upgrade to the release containing #4170. The fix compares `Origin` with the request's resolved `env['onetime.display_domain']`; do not work around this by maintaining a custom-domain origin allowlist in environment configuration.

## Related Configuration

### Organization Switcher

The organization switcher (separate from SSO tab) requires:

```bash
ENABLE_ORGS=true
```

This controls `features.organizations.enabled` in the bootstrap response.

### AUTH_SSO_ENABLED vs ORGS_SSO_ENABLED

Independent flags is the cleaner design.

Distinction:
- AUTH_SSO_ENABLED: Install-level SSO on canonical domain (env-configured providers)
- ORGS_SSO_ENABLED: Org-level SSO for custom domains (DB-configured per-domain)

The two features serve fundamentally different use cases:

┌──────────────────┬──────────────────┬──────────────────────────────────┬─────────────────────────────────────────┐
│       Flag       │      Scope       │          Configuration           │                Use Case                 │
├──────────────────┼──────────────────┼──────────────────────────────────┼─────────────────────────────────────────┤
│ AUTH_SSO_ENABLED │ Canonical domain │ Env vars (OIDC_*, ENTRA_*, etc.) │ Self-hosted enterprise with single IdP  │
├──────────────────┼──────────────────┼──────────────────────────────────┼─────────────────────────────────────────┤
│ ORGS_SSO_ENABLED │ Custom domains   │ DB per-domain (CustomDomain::SsoConfig)  │ SaaS offering enterprise SSO to tenants │
└──────────────────┴──────────────────┴──────────────────────────────────┴─────────────────────────────────────────┘

The key scenario that breaks hierarchical design:

A SaaS operator may want AUTH_SSO_ENABLED=false (users sign up with passwords on onetimesecret.com) while
ORGS_SSO_ENABLED=true (enterprise customers configure SSO for secrets.acme.com). A master switch would force enabling
install-level SSO (with dummy or unused providers) just to unlock the org-level feature.

Why independent is more maintainable:

1. Single responsibility: Each flag controls exactly one subsystem. AUTH_SSO flows through AuthConfig.sso_enabled? →
Rodauth OmniAuth. ORGS_SSO flows through features.organizations.sso_enabled → CustomDomain::SsoConfig resolution.
2. No coupling bugs: Changes to install-level SSO can't accidentally break org-level SSO or vice versa.
3. Clearer config intent: AUTH_SSO_ENABLED=false, ORGS_SSO_ENABLED=true explicitly communicates "no platform SSO, yes
tenant SSO" without needing to understand implicit relationships.
4. Entitlements already provide the per-org gate: The manage_sso entitlement controls which organizations can use domain
  SSO. The feature flag gates the entire capability at the install level—orthogonal concerns.

The one exception: If the underlying OAuth session machinery required AUTH_SSO_ENABLED to be true for any OAuth to work,
  coupling would be necessary. But from the recon, domain SSO has independent provider resolution that doesn't depend on
install-level providers.

## Billing

### Billing Disabled (Standalone Mode)

When billing is disabled (`BILLING_ENABLED=false`), all entitlements are granted automatically via `STANDALONE_ENTITLEMENTS`. The SSO tab appears for all organizations without additional configuration.

### Billing Enabled

When billing is enabled, the organization must have the `manage_sso` entitlement. This requires proper configuration across multiple layers.

## See Also

- [SSO Configuration Guide](per-install-sso.md) - platform-level SSO setup and provider configuration
- [OmniAuth Tenant Resolution](../../apps/web/auth/config/hooks/omniauth_tenant.rb) - runtime credential injection
- [CustomDomain::SsoConfig Model](../../lib/onetime/models/custom_domain/sso_config.rb) - per-domain SSO storage
- [Billing Catalog Management](../../apps/web/billing/docs/catalog-api-design.md)
- [Entitlements System](../authorizations/membership-entitlements.md)
- [STANDALONE_ENTITLEMENTS](../../lib/onetime/models/features/with_entitlements.rb)
