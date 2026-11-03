# Tenant Connect authorization

Why attaching a tenant-issued SSO identity to an existing account requires
more than a validated tenant callback, and what the Connect pipeline requires
before it binds one.

This document explains the reasoning. The normative specification is
[Requirements for authenticated tenant linking (#3849)](./per-domain-sso.md#requirements-for-authenticated-tenant-linking-3849)
in `per-domain-sso.md`; where the two differ, that section is authoritative.
The platform-surface mechanics (intent nonce, recent re-authentication,
refusal table) are in
[per-install-sso.md](./per-install-sso.md#connected-identities-authenticated-linking-from-account-settings).

## Status

Tenant Connect was refused for a **security boundary**, not because the
Connected Identities UI was unavailable. Issue
[#3849](https://github.com/onetimesecret/onetimesecret/issues/3849) is closed
as completed. The release flip was tracked in
[#4427](https://github.com/onetimesecret/onetimesecret/issues/4427) and
delivered by [PR #4437](https://github.com/onetimesecret/onetimesecret/pull/4437).
The specification records "Implementation status: enabled (#4427)". The
shared callback pipeline in `apps/web/auth/config/hooks/omniauth_connect.rb`
enforces the requirements below.

`OmniAuthConnect.tenant_connect_enabled?` is an internal kill switch with no
operator setting. Closing it refuses tenant Connect and relaxes nothing.

## The boundary

A tenant custom domain is administered by the tenant. Its SSO administrator
controls the IdP configuration and, in practice, the identity assertions
returned by that IdP. OTS therefore cannot treat a tenant SSO callback as
sufficient authority to attach a tenant-issued identity to an arbitrary
existing platform account.

The platform flow is safe because it requires:

1. an already authenticated account session,
2. recent full local re-authentication before the intent is minted
   (`Onetime::RecentReauth.satisfied?`, #4411),
3. an explicit, account-bound, surface-bound, short-lived `connect=1` intent,
   and
4. a callback on the platform surface.

That lets OTS bind the identity to the account identified by the session, not
by the IdP-provided email. See
`src/apps/workspace/account/ConnectedIdentities.vue` and
`apps/web/auth/config/hooks/omniauth.rb`.

The same action requires two further controls on a tenant surface. The
specification states: "Authorizing a tenant Connect requires two independent
controls. Neither control may be inferred from the IdP's email claim."

## Control 1: domain-scoped membership authorization

Before binding a tenant issuer to the session account, the server must
establish that the account is legitimately entitled to use the specific tenant
domain:

- the account has an **active** organization membership in the organization
  that owns the validated custom domain;
- that membership can access **this exact custom domain**, via
  `OrganizationMembership#can_access_domain?`;
- it is not enough merely to belong to the same organization, because
  memberships can be scoped to Domain A while the SSO issuer belongs to
  Domain B.

Without this gate, a tenant-controlled IdP could become a login method on a
platform account that is unrelated to that tenant.

The issuer-backfill work shows why the gate is strict.
`apps/web/auth/operations/backfill_tenant_issuer.rb` requires both
domain-scoped membership and provenance checks before writing a tenant
issuer, specifically to avoid assigning a Domain B issuer to a Domain A-scoped
account or misclassifying a platform identity as a tenant identity.

## Control 2: tenant-surface-scoped session authority

Membership proves the account may use the domain. Callback-domain validation
proves the IdP callback belongs to that domain. Neither proves that the
**session doing the connecting** was established on that domain. The
specification states: "`logged_in?` plus
`session[:validated_omniauth_domain_id]` is insufficient: the first proves
that some account is signed in, while the second validates the SSO callback's
domain. Neither proves that the existing account session belongs to that
tenant surface."

Why this matters for blast radius: once a tenant-issued identity is bound, the
tenant administrator can mint an assertion for that `(provider, issuer, uid)`
and sign in as the account. For an account that was JIT-created on that
tenant, that was already true. For a pre-existing platform account that was
later invited into the organization, a bind would newly hand the tenant
administrator a login to an account that may contain secrets and memberships
from other organizations. Control 2 ensures the authority used to perform that
bind was itself scoped to the tenant and freshly proven with a credential the
tenant administrator does not control.

The control has two parts.

**Host-bound session.** The session cookie carries no `Domain` attribute, so
the browser returns it only to the host that set it. OTS additionally records
the establishing surface at login: the validated custom-domain ID for a tenant
login, `nil` for the canonical host. A request whose resolved display domain
does not match that record is treated as unauthenticated. At the Connect
callback, the request surface must resolve, must equal the surface recorded in
the connect intent, and must equal the surface recorded at login
(`Onetime::SessionSurface.matches_request?`). For a tenant callback that
surface is the validated domain ID. An unvalidated callback on a custom host
is never platform Connect.

**Recent re-authentication.** Before the Connect intent is created, the
account holder must complete a full local re-authentication within
`RecentReauth::CONNECT_MAX_AGE` (300 seconds). The proof is recorded for the
session's account, on the surface the initiation arrives on, by a local
primary (password or WebAuthn) with every MFA factor the account's policy
requires already completed. It is single use: minting the intent consumes it.
A magic-link login, an SSO callback, and a password step that stopped short of
required MFA never record one. The re-authentication is performed with the
account's existing credential, never with the tenant IdP, so a tenant
administrator cannot satisfy it by minting an assertion. The proof is not
re-checked at the callback. The intent carries that admission across the IdP
round trip, which is why the intent is age-bounded and surface-bound.

A WebAuthn credential registered for the platform RP ID cannot ordinarily be
used from an unrelated tenant host. A password, or a credential registered for
the tenant surface, is the fallback. Cross-domain passkey use requires an
explicitly configured related-origins arrangement and is not automatic.

## Why the platform recovery flows are ruled out on tenant callbacks

- **Email-only matching** is unsafe because a tenant IdP can assert a victim's
  email.
- A **password interstitial** would expose a password-guessing path against
  arbitrary platform accounts and could bind the tenant identity after a
  successful guess.
- **Mailbox-proof linking** could cause tenant callbacks to trigger linking
  mail to arbitrary platform addresses.

An unauthenticated tenant callback for an existing email still receives the
H-3 refusal `tenant_sso_link_unavailable`. The way forward it names is to sign
in on the tenant host with an active membership for that domain and link from
Connected Identities.

## Refusal reasons

The `tenant_surface` refusal reason no longer exists in the hook. Commit
`d885e7bd12` was the intermediate step that separated the tenant connect
refusal from `identity_connect_conflict`, so the UI would not point users at a
platform-only recovery path. The connect pipeline now refuses with these
reasons, each logged as `omniauth_identity_connect_refused`:

| Reason | Redirect |
|---|---|
| `surface_mismatch` (tenant callback on a platform session, intent surface differs from callback surface, or unvalidated callback on a custom domain) | `identity_connect_wrong_domain` |
| `tenant_connect_prerequisites_incomplete` (kill switch closed, checked before the membership gate) | `identity_connect_wrong_domain` |
| `tenant_membership_refused` (preceded by `tenant_connect_membership_refused`) | `identity_connect_wrong_domain` |
| `tenant_issuerless` | `identity_connect_wrong_domain` |
| `session_account_missing`, `session_customer_missing`, `identity_owned_elsewhere`, `lookup_error` | `identity_connect_conflict` |

The complete table, including platform-only rows, is in
[per-install-sso.md](./per-install-sso.md#refusals).

## Required flow

The specification fixes this order. The request phase is in
`hooks/omniauth.rb`. The callback wrapper in `hooks/omniauth_connect.rb` runs
before the gem's cached-account and existing-identity shortcuts, so a known
identity cannot bypass the gates.

1. **Request phase.** The user is authenticated and submits `connect=1` for
   the tenant's SSO provider. The request phase first requires
   `RecentReauth.satisfied?` to consume a fresh proof for this account on this
   surface. Only then does it write the short-lived, single-use
   `sso_connect_intent` containing the account ID, the surface, and the mint
   time. Any non-connect initiation deletes a dangling intent. A normal SSO
   sign-in must not enter this path.

2. **Consume the intent first.** On entering `before_omniauth_callback_route`,
   the wrapper consumes the intent once (atomic GETDEL), before tenant
   validation. Every later refusal, including the tenant refusals, has already
   burned the nonce. A rejected tenant connect can never leave an intent live
   for a later callback within its TTL.

3. **Tenant callback validation.** The callback must correspond to the domain
   that initiated it. The tenant SSO policy, including the email-domain
   allowlist, is enforced. The validated custom-domain ID is stamped in
   `session[:validated_omniauth_domain_id]`.

4. **Intent match.** The consumed intent must name the current session
   account. An absent, expired, or mismatched intent is not a connect at all.
   It takes the ordinary non-connect path and is logged as
   `omniauth_connect_intent_absent`.

5. **Session account.** Load the account by session ID through
   `_account_from_session`, never from the SSO email claim. The account must
   be open, its Customer must exist, and the Customer must not be suspended.
   This step owns principal status on both surfaces. The membership gate
   judges the membership, not the principal.

6. **Surface gate.** Apply Control 2: the request surface resolves, equals the
   intent surface, and equals the surface recorded at login. The intent's mint
   time is not in the future and is within `CONNECT_MAX_AGE`. For a tenant
   callback, `tenant_connect_enabled?` is checked next.

7. **Resolve the tenant authorization context.**
   `Auth::Operations::AuthorizeTenantConnect` loads the `CustomDomain` by the
   validated identifier, its `primary_organization`, the session account's
   `Customer`, and the `OrganizationMembership` via `find_by_org_customer`.
   These are the same lookups `hooks/login.rb`, `JoinDomainOrganization`, and
   `BackfillTenantIssuer` already use. No parallel lookup keyed on `org_id` or
   `custid` is introduced. Any nil in the chain is a refusal.

8. **Apply the domain-membership gate, fail closed.**

   ```ruby
   membership&.active? && membership.can_access_domain?(custom_domain)
   ```

   `can_access_domain?` allows either an organization-scoped membership or a
   membership whose `domain_scope_id` is the exact custom domain's `objid`. A
   membership in the same organization but scoped to another custom domain
   fails. The operation is side-effect free. It never creates, activates, or
   re-scopes a membership.

9. **Bind only if every gate passes.** `BindSsoIdentity` resolves ownership by
   the complete `(provider, issuer, uid)` tuple. An unclaimed tuple is bound to
   the session account. A tuple already owned by that account is accepted
   without a duplicate row. A tuple owned by another account is refused
   without switching sessions. The returned email is never used to select the
   account. The successful connection is logged, and the re-authentication
   proof is cleared so a second bind needs a fresh ceremony.

10. **Otherwise, refuse without fallback.** No email auto-link. No
    password-link interstitial. No mailbox-proof link. No automatic
    `JoinDomainOrganization` before the bind. No refusal may re-arm or
    preserve the intent.

The membership must exist before the bind, typically because an organization
owner invited the account or otherwise granted it access. The specification
states: "A successful tenant assertion must not create the membership that is
then used to authorize attaching that same assertion as an account
credential." The login that completes a successful connect still runs
`after_login`, which calls `JoinDomainOrganization`. That call runs after the
bind and short-circuits on the existing membership. It is not part of the
authorization and must not be relied on as such.

## Why the scope check matters

Consider one organization with two custom domains:

```text
Organization Acme
├── secrets.acme.example  → issuer A
└── internal.acme.example → issuer B
```

A user may be an SSO member only for `secrets.acme.example`. A check such as:

```ruby
organization.member?(customer)
```

would incorrectly let that user attach an identity from
`internal.acme.example` as well.

The required check is domain-specific:

```text
active member of Acme
AND
authorized for the exact domain whose SSO issuer returned this identity
AND
session established and recently re-authenticated on that same domain
```

That is the same scope model already used by
`Auth::Operations::BackfillTenantIssuer` and `JoinDomainOrganization`:

- default tenant SSO memberships are scoped to that domain;
- `grant_org_scope` creates an organization-wide membership instead;
- an owner invitation creates an organization-scoped membership, which
  authorizes every domain in the organization;
- `can_access_domain?` evaluates all cases correctly.

## Backfill provenance is not part of the connect gate

`BackfillTenantIssuer` additionally requires:

```text
customer.signup_domain_id == custom_domain.identifier
```

That is needed when rewriting a **legacy issuerless identity row**: without
provenance, the migration cannot tell whether the old row came from the tenant
IdP or the platform IdP.

A fresh tenant Connect binds a newly returned, issuer-specific identity to a
session-authenticated account under Controls 1 and 2. The issue tracker
records that the `signup_domain_id` provenance rule "remains specific to
ambiguous legacy rows and does not apply to new tenant connections."

## The panel

The Connected Identities panel must not infer that a tenant identity is
already linked from a matching route name or a matching issuer. On the
platform surface a provider whose route name matches a linked identity is
suppressed, because one route maps to one issuer there. On the tenant surface
Connect is never suppressed (`src/shared/utils/sso-link-evidence.ts`). The
panel cannot know the callback's `uid`, so the server's full-tuple ownership
check is the authority.
