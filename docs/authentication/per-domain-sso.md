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
2. recent full re-authentication with a local credential, including every
   MFA factor the account requires, consumed single-use at initiation
   (`Onetime::RecentReauth.satisfied?`, #4411);
3. an explicit `connect=1` initiation that creates a short-lived, single-use,
   server-side `sso_connect_intent` containing the session account ID and the
   surface the re-authentication was verified on; and
4. a callback classified as platform-originated, on the surface the intent
   records.

OAuth `state` binds the callback to the browser's SSO initiation. The connect
intent separately proves that the initiation was a **connect** operation for
that specific account. The callback consumes the intent atomically (`GETDEL`,
or GET+DEL in one transaction on older clients), compares it with the current
session account ID, and loads the target account from the session rather than
from the IdP-provided email.

Tenant callbacks are refused instead:

| Situation | Result |
|-----------|--------|
| Authenticated session with a valid connect intent, tenant callback | Refused: `identity_connect_conflict` for principal failures; `identity_connect_wrong_domain` for surface, membership, or release-gate failures |
| Unlinked tenant identity whose asserted email matches an existing account | `tenant_sso_link_unavailable` |

The first row is defence-in-depth behind the host-bound session (below): the
auth router refuses a platform session on a tenant host before any Rodauth
route runs, so a tenant initiation from that browser records no intent and
its callback arrives anonymous, landing on the second row.

The refused connect attempt has already consumed its `sso_connect_intent`. A
logged-in tenant callback without a valid intent is logged
`omniauth_connect_intent_absent` and takes the ordinary non-connect path:
existing-identity sign-in, or, for an unlinked identity, the email branches
(JIT creation subject to `before_omniauth_create_account`, or the second row).

The second message does not direct the user to Connected Identities because
that path also refuses tenant callbacks. Today no membership state changes
either refusal; the user-facing copy points to an organization-owner invite or
support. An accepted, active membership is the precondition the future tenant
Connect SSO flow will require (below); it does not by itself link the identity.

#### Requirements for authenticated tenant linking (#3849)

**Implementation status:** `config/hooks/omniauth_connect.rb` implements the
shared callback pipeline, including session-account and Customer status,
surface binding, exact-domain membership, and full-tuple ownership checks.
`OmniAuthConnect.tenant_connect_enabled?` remains hard-coded `false`; there is
no operator override. An otherwise authorized tenant Connect is refused with
reason `tenant_connect_prerequisites_incomplete`, without binding an identity.
The Connected Identities panel keeps the interim tenant route-name suppression
(#4412) until the gate opens: exposing a Connect action the callback refuses
unconditionally would burn the user's single-use re-authentication proof for
nothing. The swap to identity evidence ships with the gate flip (#4427).
Release still requires the complete success/refusal regression matrix below. Tests exercise the gated pipeline with
that method stubbed; this does not enable tenant Connect in production.

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
   itself be established on the same tenant surface, and the account holder
   must have re-authenticated there recently. `logged_in?` plus
   `session[:validated_omniauth_domain_id]` is insufficient: the first proves
   that some account is signed in, while the second validates the SSO
   callback's domain. Neither proves that the existing account session belongs
   to that tenant surface.

   **Decision (2026-09-12).** The standards establish requirements for
   authenticated linking and re-authentication, but they do not prescribe this
   host-local session design:

   - [NIST SP 800-63C-4 section 3.8.1, Account Linking](https://pages.nist.gov/800-63-4/sp800-63c/Federation/#account-linking)
     requires an authenticated session with the subscriber account for every
     linking function. It recommends authentication with an existing
     federated identifier before linking a new one.
   - [OWASP ASVS 5.0.0 requirement 7.5.1](https://github.com/OWASP/ASVS/blob/v5.0.0/5.0/en/0x16-V7-Session-Management.md#v75-defenses-against-session-abuse)
     requires full re-authentication before changing sensitive account
     attributes that affect authentication. OTS treats adding a tenant-issued
     login identity as such a change.
   - RFC 6265 section 4.1.2.3 specifies the delivery scope of a cookie without
     a `Domain` attribute. It does not require an application to record a
     tenant marker or authenticate on a particular host.

   OTS chooses the following additional controls to prevent a platform session
   from acquiring a tenant-controlled login method:

   - *Host-bound session.* The session cookie carries no `Domain` attribute
     (`lib/onetime/application/middleware_stack.rb`), so the browser returns it
     only to the host that set it. OTS must additionally record the
     establishing surface at login (the validated custom-domain ID for a
     tenant login, `nil` for the canonical host), treat a request whose
     resolved display domain does not match that record as unauthenticated,
     and require the recorded surface to equal the callback's validated domain
     ID. This marker and its enforcement are OTS controls, not RFC 6265
     requirements.
   - *Recent re-authentication.* Before creating the tenant Connect SSO intent,
     require full re-authentication with an existing local account credential
     within a short window. It must complete every MFA factor required by the
     account's normal local sign-in policy. A password can satisfy this only
     where that policy does not require another factor. A WebAuthn assertion
     can satisfy it only when its credential is usable from the tenant host and
     meets that policy's user-verification and MFA requirements. Rodauth's
     `password_grace_period` and `confirm_password` features are conventional
     primitives; neither is enabled today. A session restored by the `remember`
     feature does not satisfy the check. The platform Connect path enforces
     this requirement as of #4411 (`RecentReauth::CONNECT_MAX_AGE`, 300s; see
     [per-install-sso.md](per-install-sso.md#recent-full-re-authentication-gates-the-intent-4411)).

   Email authentication is not an equivalent option for this requirement.
   [NIST SP 800-63B-4 section 3.1.3.1](https://pages.nist.gov/800-63-4/sp800-63b/authenticators/#out-of-band-authenticators)
   prohibits email for out-of-band authentication. OTS must not use an email
   link to satisfy this re-authentication gate; any future email-based
   exception would be an explicit OTS policy exception, not NIST AAL
   conformance.

   WebAuthn credentials are scoped to an RP ID. [WebAuthn Level 3 section
   5.5](https://www.w3.org/TR/webauthn-3/#dictdef-publickeycredentialrequestoptions)
   requires the requested RP ID to exactly equal the credential's RP ID. A
   passkey registered for the platform RP ID therefore cannot ordinarily be
   used from an unrelated tenant host, and a request for the tenant RP ID does
   not match that platform credential.
   Offer a password or a credential registered for the tenant surface as the
   fallback. Cross-domain passkey use requires an explicitly designed and
   supported [WebAuthn related-origins arrangement](https://www.w3.org/TR/webauthn-3/#sctn-related-origins), including a shared RP ID and its
   `.well-known/webauthn` configuration; it is not automatic.

   The re-authentication is performed with the account's existing credential,
   never with the tenant IdP, so a tenant administrator cannot satisfy it by
   minting an assertion.

The second control prevents a platform session that happens to receive a valid
tenant callback from gaining a tenant-issued credential. Callback-domain
validation remains required, but it cannot substitute for session scoping.

The tenant Connect SSO flow must fail closed in the following authorization
order. The request phase remains in `hooks/omniauth.rb`. The shared wrapper in
`hooks/omniauth_connect.rb` consumes intent on entering
`before_omniauth_callback_route`, then calls the tenant validation hook in
`hooks/omniauth_tenant.rb`, then runs the account and binding gates. Consuming
before tenant validation also burns intent when that validation refuses.
This wrapper runs before the gem's cached-account and existing-identity
shortcuts; limiting these gates to `account_from_omniauth` would miss known
identities.

1. **Request phase.** Require an explicit tenant Connect SSO initiation.
   `connect=1` on an authenticated session writes the existing short-lived,
   account-bound `sso_connect_intent`; any non-connect initiation deletes a
   dangling one. An ordinary SSO sign-in must not enter the connect path.
2. **Callback route hook** (`before_omniauth_callback_route`). Validate that
   the callback corresponds to the custom domain that initiated it, enforce
   the tenant SSO policy, and stamp `session[:validated_omniauth_domain_id]`.
   This runs before account resolution.
3. **Consume the intent first.** The callback wrapper consumes the intent
   once (atomic `GETDEL`, before step 2), then compares it with the current
   session account ID after tenant validation, **before every gate below**. Only a present, matching intent
   enters steps 4 to 9; an absent, expired, or mismatched intent is not a
   connect at all and takes the existing non-connect path (logged
   `omniauth_connect_intent_absent`), exactly as on the platform surface.
   This is the order the platform path already uses: every refusal,
   including the tenant refusal, burns the nonce, so a rejected tenant
   connect can never leave an intent live for a later callback within its
   TTL.
4. Require an authenticated, open account loaded from the session
   (`_account_from_session`), never from the SSO email claim. This step owns
   account status on both surfaces: the Rodauth `open` status filter that
   `_account_from_session` applies, and `Customer#suspended?`. The `/auth`
   Roda router does not run `BaseSessionAuthStrategy`, whose per-request
   suspension refusal protects every Otto-routed app, and `SetSuspension`'s
   session sweep cannot see inside encrypted payloads, so a suspended
   customer holding a live session reaches the callback with no refusal
   between them and the bind unless this step refuses it. Steps 6 and 7 do
   not re-check it (**decision 2026-09-15**): `AuthorizeTenantConnect`
   judges the membership, not the principal, and the platform Connect path
   has the same exposure with no membership gate at all, so the check has to
   live in the shared step.
5. Verify that the authenticated session is scoped to that same tenant
   surface: the surface recorded at login equals the validated domain ID, and
   a recent re-authentication on that host is on record.
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
   `membership.can_access_domain?(custom_domain)`. Steps 6 and 7 are
   implemented by `Auth::Operations::AuthorizeTenantConnect` (#4413,
   `apps/web/auth/operations/authorize_tenant_connect.rb`): it takes the
   session account row and the validated domain ID, performs exactly the
   lookup chain above, and returns a frozen result whose `authorized?` is the
   only field the caller branches on. Every nil in the chain, an inactive
   row, a sibling-domain scope and a raised lookup are distinct refusal
   reasons, all logged as `tenant_connect_membership_refused`. The operation
   is side-effect free: it never creates, activates or re-scopes a membership
   and never touches `account_identities`. Its regression suite is
   `apps/web/auth/spec/integration/full/authorize_tenant_connect_spec.rb`.
8. Bind the new `(provider, issuer, uid)` identity only to the session account
   and log the successful connection. Do not use the returned email to select
   the account.
9. On any failed check in steps 4 to 7, refuse without falling back to
   email matching, a password interstitial, mailbox proof, or automatic
   `JoinDomainOrganization` membership creation.

Every refusal after step 3 occurs after the intent has already been consumed;
none of them may re-arm or preserve it.

The server-side gates are necessary but not the only change. The Connected
Identities panel (`src/apps/workspace/account/ConnectedIdentities.vue`) must not
infer that a tenant identity is already linked from either a matching route
name or a matching issuer. It keeps tenant provider actions available and lets
the callback resolve the complete tuple. A platform and tenant can use the same
issuer with different OIDC clients; with
[OpenID Connect pairwise subject identifiers](https://openid.net/specs/openid-connect-core-1_0.html#SubjectIDTypes), the issuer provides a different `sub` value to each client.

**Decision (2026-09-12):** identities are keyed on `(provider, issuer, uid)`.
OpenID Connect Core 1.0 section 5.7 states that "the only guaranteed unique
identifier for a given End-User is the combination of the iss Claim and the
sub Claim." The panel cannot know the callback's `uid`, so it must keep
Connect available whenever equivalence is not already established. At the
callback, after the tenant, session, membership, and intent gates, resolve the
returned full `(provider, issuer, uid)` tuple: accept an existing tuple for the
session account as already connected, bind an unclaimed tuple to that account,
and refuse a tuple owned by another account. The `GET /auth/identities` payload
may display `issuer`, but it cannot safely drive this pre-callback
suppression.

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

#### Acceptance gate for enabling tenant Connect

The hard-coded tenant refusal may be removed only when each row below has an
end-to-end callback assertion, where applicable, and the listed validation
lanes pass without skips or timeouts. Unit tests of individual policy objects
support this evidence but do not replace callback coverage.

| Area | Required acceptance evidence |
|------|------------------------------|
| Initiation and re-authentication | A custom-host flow through `POST /auth/reauth`, Connect initiation, and callback; password-only success where policy permits; password alone refused when MFA is required; password plus required MFA succeeds; remembered and email-authenticated sessions cannot mint an intent. |
| Session surface | Tenant A session succeeds only on tenant A; tenant A → tenant B and tenant → platform callbacks refuse; the initiating cookie is host-only; every refusal consumes the intent. |
| Callback validation | A live intent is consumed before domain mismatch, tenant policy, principal, membership, release, and identity-ownership refusals. A replay cannot bind. |
| Principal and authorization | Open account and unsuspended Customer required; exact-domain, organization-scoped, and owner memberships succeed; missing, inactive, wrong-organization, and sibling-domain memberships refuse. |
| Identity ownership | Unclaimed full tuple binds to the session account; same-account tuple is idempotent; another account's tuple refuses without changing the session. IdP email is irrelevant. |
| No fallback | With trusted-email linking enabled and a victim email asserted, every failed tenant gate still creates no identity, account, membership, password challenge, or mailbox-proof challenge. |
| Post-login behavior | Successful Connect reaches `JoinDomainOrganization` as an existing member, creates no membership, and preserves its scope; any documented default-workspace adoption is asserted separately. |
| Client behavior | Platform routes remain suppressed when linked. Tenant routes remain visible despite matching route, issuer, or masked UID, and submit `connect=1`. |
| Concurrency | Two simultaneous intent consumers yield one payload. Two PostgreSQL writers for one unclaimed tuple leave one row and produce only the documented idempotent/conflict outcomes. |
| Browser journey | A custom-host Connected Identities journey covers panel → local re-authentication → Connect initiation → callback success, plus at least one cross-surface or ownership refusal. The success harness may open the gate only in the test process; no production override is added. |

The focused acceptance files are:

- `apps/web/auth/spec/integration/full/omniauth_connect_link_spec.rb`
- `apps/web/auth/spec/integration/full/authorize_tenant_connect_spec.rb`
- `apps/web/auth/spec/integration/full/callback_validation_spec.rb`
- `spec/integration/full/session_surface_login_stamp_spec.rb`
- `apps/web/auth/spec/operations/bind_sso_identity_spec.rb`
- the session/re-authentication unit and route specs
- `src/tests/shared/utils/sso-link-evidence.spec.ts`
- `src/tests/apps/workspace/account/ConnectedIdentities.spec.ts`

After the missing scenarios are implemented, run the focused files first, then
`pnpm type-check:tests`, the complete Vitest suite, and the `unit`,
`full-sqlite`, and PostgreSQL full-auth lanes. The final run must include the
browser/system suite. A passing focused subset is not sufficient evidence to
change `tenant_connect_enabled?`.

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
`OrganizationLoader`). On the identity side,
`Auth::Operations::BackfillTenantIssuer` uses it as an authorization gate
before changing a legacy identity row, and
`Auth::Operations::AuthorizeTenantConnect` (#4413) uses it as the pre-bind gate
for a new tenant connection; the SSO join path does not.

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
same legacy-row ambiguity. **Decision (2026-09-12):** `signup_domain_id` is
not a requirement for new tenant connections. [NIST SP 800-63C-4 section
3.8.1](https://pages.nist.gov/800-63-4/sp800-63c/Federation/#account-linking)
requires an authenticated session with the subscriber account for linking and
recommends authentication using an existing federated identifier. The identity
being bound is unique per OpenID Connect Core section 5.7 by issuer and
subject; neither standard conditions the bind on where the account was
created. Authority here therefore comes from the account holder's
authenticated, recently re-authenticated session plus the domain-scoped
membership; where the account originally signed up is irrelevant to either,
and requiring it would refuse legitimate cases such as an employee whose
platform account predates the tenant, with no security gain. The provenance
check stays specific to the backfill operation and cannot replace either of
the two required controls above.

The callback pipeline now calls the membership gate, but the hard-coded release
gate continues to refuse tenant Connect until the acceptance matrix above is
complete. Removing that gate before its controls are demonstrated together
could allow a tenant-controlled IdP to become a login method for an account
outside the tenant authorization boundary.

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
