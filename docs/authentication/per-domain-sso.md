# Per-Domain SSO Configuration

This document describes the per-domain SSO configuration system and the conditions required for the SSO configuration tab to appear in organization settings.

## Overview

SSO configuration is bound to individual custom domains, not organizations. This enables multi-IdP configurations where different domains owned by the same organization can use different identity providers.

## Prerequisites

The SSO tab is controlled by the `manage_sso` entitlement and organization SSO
feature flag. Enable organizations and per-domain SSO, then restart the auth
application so its provider routes are registered:

```bash
export ENABLE_ORGS=true
export ORGS_SSO_ENABLED=true
```

The organization must also have the `manage_sso` entitlement. The following
configuration keeps that entitlement current.

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

### 2. Publish and Materialize the Catalog

After updating `billing.yaml`, use the combined catalog sync. It pushes the
catalog to Stripe, refreshes the Redis plan cache, and materializes the updated
entitlements on organizations:

```bash
# Preview the complete sync
bin/ots billing catalog sync --dry-run

# Push, pull, and materialize
bin/ots billing catalog sync
```

The Stripe Product metadata should contain:

```
entitlements: "create_secrets,view_receipt,api_access,custom_domains,manage_sso,custom_branding"
```

For an existing organization, verify the effective entitlement with the
supported diagnostic rather than inspecting a cache key directly:

```bash
bin/ots billing diagnose --org <organization-extid> --entitlement manage_sso
```

### 3. Organization Assignment

The organization must be subscribed to a plan that includes `manage_sso`.
Catalog sync materializes the plan's effective entitlements on the organization:

```ruby
# Backend: lib/onetime/models/features/with_entitlements.rb
org.entitlements  # Returns effective entitlements
org.can?('manage_sso')  # Returns true/false
```

## Data Flow

### Entitlement Resolution (Tab Visibility)

```
billing.yaml
    │
    ▼ bin/ots billing catalog sync
Stripe Product Metadata → Redis Plan Cache
    │
    ▼ materialize entitlements
Organization Entitlements
    │
    ▼ org.entitlements
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

### Tenant callback validation

During the request phase, `omniauth_setup` stores the initiating custom-domain ID
and public host in the session. At the start of the callback, the tenant hook:

1. consumes the pending tenant context;
2. resolves the custom domain from the callback's public host;
3. requires its identifier to equal the initiating domain ID;
4. enforces the tenant SSO email-domain policy; and
5. stores the validated domain ID in
   `session[:validated_omniauth_domain_id]` for downstream hooks.

A mismatch returns `403 tenant_mismatch`. Missing or unreadable tenant
configuration and malformed or disallowed asserted email addresses also fail
closed. An empty SSO email-domain allowlist is the configured allow-all case.

This validation proves that the SSO transaction was initiated and completed for
the same custom domain. It does **not** prove that an existing authenticated
account session was established for, or is authorized to act on, that tenant
surface.

### Identity linking and surface isolation

Identity linking is currently platform-only. The three platform linking paths
are not offered on tenant callbacks:

- the authenticated [Connected Identities panel](per-install-sso.md#connected-identities-authenticated-linking-from-account-settings);
- the [password interstitial](per-install-sso.md#sign-in-interstitial-password-challenge-linking); and
- [mailbox-proof linking](per-install-sso.md#mailbox-proof-linking-passwordless-accounts).

The trusted-IdP email-linking flag also has no effect on tenant callbacks. These
paths require `session[:validated_omniauth_domain_id]` to be `nil`; a validated
tenant callback sets it to the custom-domain ID.

A tenant administrator controls the tenant's IdP configuration and, in
practice, the identity assertions returned by that IdP. OTS therefore cannot
use a tenant assertion, including its email claim, as sufficient authority to
attach a tenant-issued identity to an arbitrary existing platform account.
Once attached, that identity becomes a credential for the account.

The platform connect path has a different trust boundary. The platform
operator controls the provider configuration, and a bind requires all of the
following:

1. an authenticated account session;
2. an explicit `connect=1` initiation that creates a short-lived, single-use,
   server-side `sso_connect_intent` containing the session account ID; and
3. a callback classified as platform-originated.

OAuth `state` binds the callback to the browser's SSO initiation. The connect
intent separately proves that the initiation was a **connect** operation for
that specific account. The callback consumes the intent atomically (`GETDEL`,
or GET+DEL in one transaction on older clients), compares it with the current
session account ID, and loads the target account from the session rather than
from the IdP-provided email.

Tenant callbacks are refused instead:

| Situation | Result |
|-----------|--------|
| Authenticated session with a valid connect intent, tenant callback | `identity_connect_wrong_domain` |
| Unlinked tenant identity whose asserted email matches an existing account | `tenant_sso_link_unavailable` |

The refused connect attempt has already consumed its `sso_connect_intent`. A
logged-in tenant callback without a valid intent is logged
`omniauth_connect_intent_absent` and takes the unauthenticated email branches
instead, so it ends in JIT creation (still subject to
`before_omniauth_create_account`) or the second row.

The second message does not direct the user to Connected Identities because
that path also refuses tenant callbacks. Today no membership state changes
either refusal; the user-facing copy points to an organization-owner invite or
support. An accepted, active membership is the precondition the future tenant
Connect SSO flow will require (below); it does not by itself link the identity.

#### Requirements for authenticated tenant linking (#3849)

Removing the tenant refusal requires two independent controls. Neither control
may be inferred from the IdP's email claim.

1. **Domain-scoped membership authorization.** The session account's
   `Customer` must have an active `OrganizationMembership` in the organization
   that owns the validated custom domain, and that membership must authorize
   the exact domain:

   ```ruby
   membership&.active? && membership.can_access_domain?(custom_domain)
   ```

   `can_access_domain?` permits either an organization-scoped membership or a
   membership whose `domain_scope_id` equals the custom domain's `objid`. A
   membership scoped to another domain in the same organization must fail.

2. **Tenant-surface-scoped session authority.** The authenticated session must
   itself be established or explicitly authorized for the same tenant surface.
   The current application has no tenant-scoped session concept. In particular,
   `logged_in?` plus `session[:validated_omniauth_domain_id]` is insufficient:
   the first proves that some account is signed in, while the second validates
   the SSO callback's domain. Neither proves that the existing account session
   belongs to that tenant surface.

The second control prevents a platform session that happens to receive a valid
tenant callback from gaining a tenant-issued credential. Callback-domain
validation remains required, but it cannot substitute for session scoping.

A future tenant Connect SSO flow must therefore fail closed in this order. The
phases match the platform connect path: the request phase
(`omniauth_request_validation_phase` in `hooks/omniauth.rb`), then the
callback route hook (`before_omniauth_callback_route`, owned by
`hooks/omniauth_tenant.rb`), then `account_from_omniauth` in
`hooks/omniauth.rb`.

1. **Request phase.** Require an explicit tenant Connect SSO initiation.
   `connect=1` on an authenticated session writes the existing short-lived,
   account-bound `sso_connect_intent`; any non-connect initiation deletes a
   dangling one. An ordinary SSO sign-in must not enter the connect path.
2. **Callback route hook** (`before_omniauth_callback_route`). Validate that
   the callback corresponds to the custom domain that initiated it, enforce
   the tenant SSO policy, and stamp `session[:validated_omniauth_domain_id]`.
   This runs before account resolution.
3. **Consume the intent first.** In `account_from_omniauth`, consume the
   intent once (atomic `GETDEL`) and compare it with the current session
   account ID, **before every gate below**. Only a present, matching intent
   enters steps 4 to 9; an absent, expired, or mismatched intent is not a
   connect at all and takes the existing non-connect path (logged
   `omniauth_connect_intent_absent`), exactly as on the platform surface.
   This is the order the platform path already uses: every refusal,
   including the tenant refusal, burns the nonce, so a rejected tenant
   connect can never leave an intent live for a later callback within its
   TTL.
4. Require an authenticated, open account loaded from the session
   (`_account_from_session`), never from the SSO email claim.
5. Verify that the authenticated session is scoped to that same tenant surface.
6. Load the validated `CustomDomain`
   (`CustomDomain.find_by_identifier(domain_id)`), its owning organization
   (`custom_domain.primary_organization`), the session account's `Customer`
   (`Customer.find_by_extid(account[:external_id])`), and the membership
   (`OrganizationMembership.find_by_org_customer(organization.objid,
   customer.objid)`). These are the lookups `hooks/login.rb`,
   `Auth::Operations::JoinDomainOrganization` and
   `Auth::Operations::BackfillTenantIssuer` already perform between them; do
   not introduce a parallel lookup keyed on `org_id` or `custid`. Any nil in
   that chain is a refusal; `can_access_domain?` already returns false for a
   nil domain.
7. Require both an active membership and
   `membership.can_access_domain?(custom_domain)`.
8. Bind the new `(provider, issuer, uid)` identity only to the session account
   and log the successful connection. Do not use the returned email to select
   the account.
9. On any failed check in steps 4 to 7, refuse without falling back to
   email matching, a password interstitial, mailbox proof, or automatic
   `JoinDomainOrganization` membership creation.

Every refusal after step 3 occurs after the intent has already been consumed;
none of them may re-arm or preserve it.

The server-side gates are necessary but not the only change. The Connected
Identities panel (`src/apps/workspace/account/ConnectedIdentities.vue`) hides
a provider whenever any existing identity's `provider` equals the provider's
OmniAuth `route_name`, on the assumption that one route maps to one issuer.
That holds on the platform surface but not on a tenant surface, where the
tenant `oidc` provider resolves to a different issuer than a platform `oidc`
identity. #3849 must make that dedup issuer-aware (the `GET /auth/identities`
payload already returns `issuer` per row) or the tenant connect button will be
absent for exactly the accounts this flow targets.

The membership must exist before the bind. A successful tenant assertion must
not create the membership that is then used to authorize attaching that same
assertion as an account credential.

The login completing a successful tenant connect still runs the `after_login`
hook, which consumes `session[:validated_omniauth_domain_id]` and calls
`Auth::Operations::JoinDomainOrganization` for any tenant login
(`hooks/login.rb`). That operation checks only `organization.member?(customer)`,
not `can_access_domain?`, so on this path it returns `already_member` without
creating anything. It is not a substitute for the gate and must not be cited
as a reason to remove it: the gate runs before the bind, the join runs after
the login, and only the former authorizes the credential. Note that the
`already_member` path still runs `adopt_domain_default_org`, which repoints
`default_org_id` to the domain organization and archives a personal workspace,
so a tenant connect on a pre-existing platform account may carry that side
effect when the account still owns an unarchived personal default workspace
and its `default_org_id` is either empty or points at that workspace.

#### Why the domain scope matters

One organization can own multiple custom domains with different SSO issuers:

```text
Organization Acme
├── secrets.acme.example  → issuer A
└── internal.acme.example → issuer B
```

A user can be authorized only for `secrets.acme.example`. A check such as
`organization.member?(customer)` would incorrectly admit that user on
`internal.acme.example`. The required authorization is:

```text
active member of Acme
AND
allowed to access the exact domain whose SSO issuer returned the identity
```

`Auth::Operations::JoinDomainOrganization` produces this scope model for SSO
joins but does not enforce it. A first tenant SSO login creates a membership
scoped to that domain, unless the domain's `grant_org_scope` setting is on, in
which case the membership is organization-scoped. Its existing-member
short-circuit is `organization.member?(customer)`, the check the Acme example
calls incorrect, so a member scoped to a sibling domain is neither re-scoped
nor checked on a later SSO login through another domain of the same
organization.

Memberships created by an organization owner's invitation carry no
`domain_scope_id` and are therefore organization-scoped: an invited account
passes `can_access_domain?` for every custom domain the organization owns. An
SSO join that finds a pending invitation for the same email activates that
invitation and inherits its organization scope rather than the domain scope.
The domain-scoped case in the Acme example arises from SSO joins, not from
invitations.

`OrganizationMembership#can_access_domain?` evaluates both forms and is
already the enforcement primitive for domain resource access (the domains API,
`OrganizationLoader`). On the identity side, only
`Auth::Operations::BackfillTenantIssuer` currently uses it as an authorization
gate before changing an identity row; the SSO join path does not.

#### Why issuer backfill has an additional provenance gate

`Auth::Operations::BackfillTenantIssuer` also requires:

```ruby
customer.signup_domain_id.to_s == custom_domain.identifier.to_s
```

That operation rewrites a legacy identity whose issuer is the empty-string
sentinel. Membership alone cannot establish whether such an ambiguous row came
from the tenant IdP, the platform IdP, or another tenant using the same provider
route. The signup-domain check supplies additional provenance before the
operation changes the row.

A fresh tenant connect receives an issuer-specific identity from the validated
callback and binds it to a session-selected account, so it does not have the
same legacy-row ambiguity. The current #3849 acceptance criteria require
verified domain membership and a tenant-surface-scoped session; they do not yet
make `signup_domain_id` a requirement for new connections. That must remain an
explicit product-policy decision rather than being inherited automatically
from the backfill operation. It also cannot replace either of the two required
controls above.

Until #3849 implements both controls and their failure cases,
`apps/web/auth/config/hooks/omniauth.rb` deliberately refuses tenant connects.
Removing only the current surface guard would allow a tenant-controlled IdP to
become a login method for an account outside the tenant authorization boundary.

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

1. **Check the organization feature flags**:
   ```bash
   echo "$ENABLE_ORGS"
   echo "$ORGS_SSO_ENABLED"
   ```
   Both values must be `true`.

2. **Publish and materialize the catalog** after any entitlement change:
   ```bash
   bin/ots billing catalog sync
   ```

3. **Verify the organization's effective entitlement**:
   ```bash
   bin/ots billing diagnose --org <organization-extid> --entitlement manage_sso
   ```

4. **Check frontend debug logs** (if enabled):
   ```
   [OrganizationSettings] SSO visibility: ...
   [useEntitlements] can(): { entitlement: "manage_sso", ... }
   ```

### Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| SSO tab missing | `ORGS_SSO_ENABLED` is not `true` | Enable `ORGS_SSO_ENABLED=true` and restart the auth application |
| SSO tab missing | `manage_sso` is not materialized for the organization | Add it to `billing.yaml`, then run `bin/ots billing catalog sync` |
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

When billing is disabled (`BILLING_ENABLED=false`), `STANDALONE_ENTITLEMENTS` grants `manage_sso` to every organization. `ENABLE_ORGS=true` and `ORGS_SSO_ENABLED=true` are still required for the organization UI and SSO configuration tab.

### Billing Enabled

When billing is enabled, the organization must have the `manage_sso` entitlement. This requires proper configuration across multiple layers.

## See Also

- [SSO Configuration Guide](per-install-sso.md) - platform-level SSO setup and provider configuration
- [Issue #3849](https://github.com/onetimesecret/onetimesecret/issues/3849) - authenticated tenant-surface identity linking requirements and status
- [OmniAuth Tenant Resolution](../../apps/web/auth/config/hooks/omniauth_tenant.rb) - runtime credential injection
- [CustomDomain::SsoConfig Model](../../lib/onetime/models/custom_domain/sso_config.rb) - per-domain SSO storage
- [Billing Catalog Management](../../apps/web/billing/docs/catalog-api-design.md)
- [Entitlements System](../authorizations/membership-entitlements.md)
- [STANDALONE_ENTITLEMENTS](../../lib/onetime/models/features/with_entitlements.rb)
