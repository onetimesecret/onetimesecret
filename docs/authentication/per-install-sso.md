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
| **Provider-specific** | Direct integration with a specific service | `ENTRA_*`, `GOOGLE_*`, `GITHUB_*`, `APPLE_*`, `AUTH0_*` |
| **SAML 2.0** | The IdP has no OIDC login flow | `SAML_*` |

Generic OIDC uses the `/.well-known/openid-configuration` discovery document. Provider-specific gems handle OAuth quirks (tenant models, non-standard scopes, token formats) so the operator doesn't have to. SAML has no client credential: trust is the IdP's signing certificate, pinned in configuration.

Multiple providers can be active simultaneously. Each provider that has its required env vars set will register automatically at boot. The frontend renders one button per configured provider.

**Requirements:**
- `AUTHENTICATION_MODE=full`
- A runtime SQL database connection (`AUTH_DATABASE_URL`) with migrations applied
- At least one provider's credentials configured

## Quick Start

### 1. Configure Database URLs and Run Migration

```bash
# Required: database used by the running application
export AUTH_DATABASE_URL=postgres://onetime_app:password@db.example.com/onetime_auth

# Optional: separate, privileged connection used only for migrations
export AUTH_DATABASE_URL_MIGRATIONS=postgres://onetime_migrator:password@db.example.com/onetime_auth

sequel -m apps/web/auth/migrations "$AUTH_DATABASE_URL"
```

`AUTH_DATABASE_URL` is the runtime connection. `AUTH_DATABASE_URL_MIGRATIONS` is optional, but when it is used it must target the same database; substitute it for `AUTH_DATABASE_URL` in the migration command. The migration creates `account_identities` for provider/issuer/uid identity links.

### 2. Set Environment Variables

```bash
# Enable SSO
export AUTH_SSO_ENABLED=true

# Configure one or more providers (see Provider Configuration below)
export OIDC_ISSUER=https://auth.example.com
export OIDC_CLIENT_ID=your-client-id
export OIDC_CLIENT_SECRET=your-client-secret
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
| `SSO_ALLOW_PLATFORM_FALLBACK` | No | Explicit opt-in (`true`) to expose platform providers for sign-in on a custom domain without active tenant SSO. Platform OIDC/OAuth providers appear on any registered custom domain; platform SAML appears only when the domain is verified, and additionally requires the exact custom-domain ACS URL to be registered at the IdP. Fallback providers are not available for Connect on that custom-domain surface. |
| `SSO_FORM_ACTION_ORIGINS` | No | Space-separated extra origins added to the CSP `form-action` directive. IdP origins are auto-derived — platform providers at boot, tenant (per-domain) SSO issuers per-request. Use this process-wide override only for split-endpoint OIDC or a tenant discovery-availability fallback (see [Troubleshooting](#sso-login-blocked-on-chromium-family-browsers-csp-form-action)). |

### Generic OIDC

| Variable | Required | Description |
|----------|----------|-------------|
| `OIDC_ISSUER` | Yes | Issuer URL (must serve `/.well-known/openid-configuration`) |
| `OIDC_CLIENT_ID` | Yes | OAuth client ID |
| `OIDC_CLIENT_SECRET` | No | OAuth client secret (empty for PKCE-only flows) |
| `OIDC_ROUTE_NAME` | No | URL segment (default: `oidc`) |

### Microsoft Entra ID

| Variable | Required | Description |
|----------|----------|-------------|
| `ENTRA_TENANT_ID` | Yes | Directory (tenant) ID from Azure portal |
| `ENTRA_CLIENT_ID` | Yes | Application (client) ID |
| `ENTRA_CLIENT_SECRET` | Yes | Client secret value (not the secret ID) |
| `ENTRA_ROUTE_NAME` | No | URL segment (default: `entra`) |
| `ENTRA_DISPLAY_NAME` | No | Button label (default: `Microsoft`) |

### Google

| Variable | Required | Description |
|----------|----------|-------------|
| `GOOGLE_CLIENT_ID` | Yes | OAuth 2.0 client ID |
| `GOOGLE_CLIENT_SECRET` | Yes | OAuth 2.0 client secret |
| `GOOGLE_ROUTE_NAME` | No | URL segment (default: `google`) |
| `GOOGLE_DISPLAY_NAME` | No | Button label (default: `Google`) |

### GitHub

| Variable | Required | Description |
|----------|----------|-------------|
| `GITHUB_CLIENT_ID` | Yes | OAuth App client ID |
| `GITHUB_CLIENT_SECRET` | Yes | OAuth App client secret |
| `GITHUB_ROUTE_NAME` | No | URL segment (default: `github`) |
| `GITHUB_DISPLAY_NAME` | No | Button label (default: `GitHub`) |

### Apple

| Variable | Required | Description |
|----------|----------|-------------|
| `APPLE_CLIENT_ID` | Yes | Services ID (e.g. `com.example.web`), not the App ID |
| `APPLE_TEAM_ID` | Yes | Apple Developer Team ID |
| `APPLE_KEY_ID` | Yes | Key ID of the Sign in with Apple private key |
| `APPLE_PRIVATE_KEY` | Yes | Contents of the `.p8` EC key (not a path); the `\n`-escaped single-line form is accepted |
| `APPLE_ROUTE_NAME` | No | URL segment (default: `apple`) |
| `APPLE_DISPLAY_NAME` | No | Button label (default: `Apple`) |

### SAML 2.0

| Variable | Required | Description |
|----------|----------|-------------|
| `SAML_IDP_SSO_SERVICE_URL` | Yes | The IdP's SSO endpoint (HTTP-Redirect binding). `https://` only; no credentials in the URL |
| `SAML_IDP_ENTITY_ID` | Yes | The IdP's EntityID exactly as it sends it in `<Issuer>`; compared byte for byte and stored as the issuer of every SAML identity |
| `SAML_IDP_CERT` | Yes | The IdP's X.509 signing certificate in PEM form: exactly one certificate, inside its validity window (not expired, not yet valid); the `\n`-escaped single-line form is accepted. Fingerprints are not accepted |
| `SAML_SP_ENTITY_ID` | No | Our SP EntityID (the Audience the IdP must send). Default: `https://{site.host}/auth/sso/{route}/metadata` |
| `SAML_UID_ATTRIBUTE` | No | SAML attribute to use as the stable user id instead of the NameID. Required when the IdP can only send a transient NameID |
| `SAML_ROUTE_NAME` | No | URL segment (default: `saml`) |
| `SAML_DISPLAY_NAME` | No | Button label (default: `SAML SSO`) |

A missing **or unusable** value (non-https URL, a URL with a fragment or a host the CSP layer cannot carry, blank EntityID, a certificate that does not parse, has more than one block, has expired, or is not yet valid) skips the provider with an error in the boot log and hides the button; boot never fails. See [SAML 2.0](#saml-20-1) under Provider Configuration.

## Routes

Each configured provider registers two routes:

| Method | Path | Description |
|--------|------|-------------|
| POST | `/auth/sso/{provider}` | Initiates SSO flow |
| GET | `/auth/sso/{provider}/callback` | Receives IdP response |
| GET | `/auth/sso/{provider}/metadata` | SAML only: SP metadata XML (404 while the route has no trust anchors) |

Where `{provider}` is the route name (`oidc`, `entra`, `google`, `github`, `apple`, `saml`, or custom).

Apple and SAML are the exceptions to the GET callback: Apple uses
`response_mode=form_post`, and SAML's HTTP-POST binding delivers the
`SAMLResponse` the same way, so their callbacks arrive as a cross-site **POST**
to the same path. OmniAuth's middleware handles either method, but the session
cookie does not — see the Apple and SAML sections below for the `same_site`
prerequisite. SAML's `/slo` and `/spslo` sub-paths answer 501 (single logout
is disabled).

The callback URL (`https://{host}/auth/sso/{provider}/callback`) is constructed from the request host. Register the exact URL with the IdP. For platform SAML, the SP EntityID remains the fixed platform value while an opted-in verified custom-domain fallback uses that request host for its ACS URL; the IdP must register each such ACS URL explicitly. The strategy fixes the ACS to the public host plus the callback path, so a sign-in link's query string cannot change it.

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
Account lookup by (provider, issuer, uid), then by email
    ├─ (provider, issuer, uid) already linked → sync session
    ├─ Email matches an account, but this identity is not linked
    │     ├─ Trusted-IdP flag ON  → auto-link identity, sync session
    │     └─ Trusted-IdP flag OFF →
    │            ├─ account HAS a password → sign-in interstitial
    │            │      (prove existing password → link identity → sync session)
    │            └─ account has NO password (passwordless) → mailbox-proof link
    │                   (email single-use token to on-file address → user clicks →
    │                    confirm → link identity → sign in), tenant surface → refuse
    └─ Email unknown → Create account + Customer + workspace, sync session
    │
    ▼
Redirect to dashboard (authenticated)
```

All hooks (`account_from_omniauth`, `before_omniauth_create_account`, etc.) are provider-agnostic. Adding a new provider does not require hook changes.

SAML differs in the middle of that diagram: the redirect to the IdP carries an
AuthnRequest (HTTP-Redirect binding), the IdP returns a signed Response to the
callback by HTTP-POST, and there is no token exchange — the signed assertion
is the identity. The callback is accepted only if it answers the AuthnRequest
this session started; everything from that point on (account lookup, linking,
creation) is the same.

## Behavior

**Account Matching:** By linked identity first — the `(provider, issuer, uid)` key in `account_identities`. The `issuer` is `''` for OAuth2-only identities; legacy rows start with that sentinel and a platform OAuth2/OIDC callback lazily upgrades them to its resolved issuer (a SAML callback never does: no SAML identity was ever stored under the sentinel, so a sentinel row under the SAML route belongs to whatever protocol that route name served before, and a NameID is not a `sub`). If that identity is already linked, the user is signed into its account. If the identity is *not* linked but the IdP email matches an existing account, the default is to **refuse email-only auto-linking** (email may locate an account, but only a demonstrated credential may bind an identity to it). On the platform surface, a password-holding account is offered a **sign-in interstitial** to prove its existing password (on by default — see [Sign-in interstitial](#sign-in-interstitial-password-challenge-linking)), and a **passwordless** account is offered **mailbox-proof linking** — a single-use link emailed to its on-file address (on by default — see [Mailbox-proof linking](#mailbox-proof-linking-passwordless-accounts)). An operator can also opt a trusted IdP into email auto-linking (see [Identity Linking and the Trusted-IdP Flag](#identity-linking-and-the-trusted-idp-flag)). A signed-in user can link an identity deliberately, without any email involvement, from [Connected Identities](#connected-identities-authenticated-linking-from-account-settings) in account settings.

**Account Creation:** Automatic for unrecognized emails. Creates Customer record and default workspace.

**Multi-Provider:** One account can have multiple linked identities (e.g., OIDC + Entra). The `account_identities` table stores `(provider, issuer, uid)` keys per account.

**Email Verification:** SSO accounts are auto-verified. The IdP handles verification. SAML carries no `email_verified` claim, so a SAML account is verified on IdP trust alone; an attribute the IdP names `email_verified` with the value `false` is still honoured as a hold.

**MFA:** Not enforced for SSO logins. The IdP is responsible for MFA.

## Identity Linking and the Trusted-IdP Flag

### The invariant

An email claim may **locate** an account; only a **demonstrated credential** may **bind** an identity to it. Email is metadata, not an identity join key.

Concretely: an SSO login is identified by the `(provider, issuer, uid)` key recorded in `account_identities`; `issuer` is `''` for OAuth2-only rows, while legacy rows begin with that sentinel until a platform callback lazily upgrades them. When that key is already linked, the user is signed into the linked account. When it is *not* linked but the IdP-supplied email happens to match an existing account, the default behavior is to **refuse email-only auto-linking** — because anyone who controls the IdP can mint a token bearing any victim's email address. Auto-linking on email alone would let such a token take over the matching account. On the platform surface, the user can instead prove an existing password or control of the account's on-file mailbox. Tenant callbacks, and platform cases where those proof paths cannot proceed, receive the H-3 refusal: `omniauth_link_refused_existing_account` (level `warn`, carrying `surface: platform|tenant`) and a redirect. The platform redirect is `/signin?auth_error=account_exists_link_required`, telling the user to sign in with their existing method and then link. The tenant redirect is `/signin?auth_error=tenant_sso_link_unavailable`: the unauthenticated proof paths are platform-only, so the copy names an org-owner invite or support instead. An account holder with an active membership for that domain can sign in on the tenant host and link from Connected Identities (#3849).

This is the correct default for a multi-tenant platform. It is *not* what a self-hosted single-tenant operator wants when they control both the app and the IdP — for them, email is a trustworthy join key, and the refusal locks legitimate users out. The trusted-IdP flag is the sanctioned, opt-in exception.

### Connected Identities: authenticated linking from account settings

The invariant says a *demonstrated credential* is what binds an identity. The cleanest such credential is one the user has **already** demonstrated: an active, authenticated session. So the primary way to attach an SSO identity to an existing account is not a callback heuristic at all — it is a deliberate action the signed-in user takes from **Security settings → Connected identities** (`/account/settings/security/connections`, `src/apps/workspace/account/ConnectedIdentities.vue`).

This is the surface the other paths point at: the H-3 refusal flash names it, and the interstitial and mailbox-proof flows send `link_expired` / `link_conflict` here rather than re-minting a token.

**The panel** lists the account's linked identities — canonical provider label, the `issuer` (hidden for the `''` sentinel on legacy / OAuth2-only rows), and a **masked** `uid` — with a Remove action behind a confirmation dialog, plus eligible Connect providers. On the platform surface, "already linked" is decided by route name (`provider.route_name` vs the row's `provider`), which is correct there because one route maps to one issuer. On a custom-domain surface with active tenant SSO, the panel does not suppress the tenant provider by route-name evidence: the client cannot establish tuple equivalence before the callback (the `uid` is masked, and pairwise subject identifiers differ per client), so the server's full-tuple ownership check decides (`src/shared/utils/sso-link-evidence.ts`).

A custom domain without active tenant `SsoConfig` is different. `SSO_ALLOW_PLATFORM_FALLBACK=true` may expose platform providers there for **sign-in** (platform SAML only once the domain is verified), but the panel omits them from Connected Identities. Their callbacks have no validated tenant context, and a custom-surface callback cannot be authorized as platform Connect. Initiate platform Connect from a canonical/operator surface instead. Suppression is a display heuristic; callback validation remains the control.

```
Signed-in user clicks "Connect {provider}"
    │
    ▼
Form POST /auth/sso/{provider} with connect=1  (submitSsoLogin, src/shared/utils/sso.ts)
    │
    ▼
omniauth_request_validation_phase → RecentReauth.satisfied? consumes the recent-reauth proof (#4411)
    ├─ no proof / stale / other account / other surface / non-local primary
    │     → no intent; redirect /reauth?redirect=/account/settings/security/connections
    └─ fresh proof → write sidecar:<sid>:sso_connect_intent = { account_id, surface, at }
    │
    ▼
IdP round-trip → callback wrapper (omniauth_connect.rb)
    │
    ▼
Consume the intent (atomic GETDEL), run tenant validation, then Connect gates
    ├─ matching intent + valid principal + same surface (+ exact-domain membership on a tenant) + unclaimed/own tuple → bind or accept existing identity, re-affirm session
    ├─ tenant callback on a platform session → refuse (identity_connect_wrong_domain)
    ├─ intent surface ≠ callback surface     → refuse (identity_connect_wrong_domain)
    ├─ custom-surface callback without validated tenant context → refuse (identity_connect_wrong_domain)
    ├─ tenant callback: enablement constant closed, no active membership for the exact domain, or no resolvable issuer → refuse (identity_connect_wrong_domain)
    ├─ session account no longer open, Customer missing/suspended, or tuple owned elsewhere → refuse (identity_connect_conflict)
    └─ absent / expired / malformed / other account → ordinary non-connect path
    │
    ▼
Back to /account/settings/security/connections
```

A completed Connect returns to the panel path the panel supplied in the form's `redirect` field, validated as an internal path at initiation (the same check signup applies; anything else is dropped and Rodauth's default login redirect applies); refusals keep their sign-in error redirect.

#### Two signals are required to bind, not one

`logged_in?` alone is **not** connect intent. Tabs share cookies, so an ordinary second-tab or shared-browser SSO *sign-in* arriving on an already-authenticated session would otherwise be routed through the bind path and permanently attach the arriving IdP identity to whoever happens to be signed in. Binding therefore requires **both**:

1. an authenticated session (`session_value`), and
2. an **account-bound connect intent** established at initiation.

The division of labour: OAuth `state`/CSRF proves *"this browser initiated a request"*; the intent nonce proves *"this browser initiated a **connect** for **this account**"*.

#### Recent full re-authentication gates the intent (#4411)

An authenticated session plus `connect=1` is intent, not proof. Attaching a login identity changes the account's authenticators ([OWASP ASVS 5.0.0 requirement 7.5.1](https://github.com/OWASP/ASVS/blob/v5.0.0/5.0/en/0x16-V7-Session-Management.md#v75-defenses-against-session-abuse)), so the request phase mints the intent **only** after `Onetime::RecentReauth.satisfied?` (`lib/onetime/session/recent_reauth.rb`, #4410) consumes a proof that is:

| Binding | Requirement |
|---------|-------------|
| Account | recorded for the session's account (`session_value`) |
| Surface | recorded on the surface the initiation arrives on (`Onetime::SessionSurface.for_env`) |
| Age | no older than `RecentReauth::CONNECT_MAX_AGE` (300s) |
| Ceremony | first completed method is a local primary (`password` or `webauthn`), with every MFA factor the account requires already completed |
| Use | single-use — the gate consumes it, so one ceremony admits exactly one initiation; a second initiation (or a concurrent one) is refused |

A proof is recorded only by a completed local ceremony: a password (or WebAuthn-primary) login that satisfied MFA policy, or a completed `POST /auth/reauth` (`apps/web/auth/routes/reauth.rb`, the surface-aware re-authentication endpoint from #4414). A magic-link login, an SSO callback, a remembered session, and a password step that stopped short of required MFA never record one, so none of them can reach the intent write. A user who signed in with a password moments ago passes the gate on that login; otherwise the refusal redirects to `/reauth?redirect=/account/settings/security/connections`, the re-authentication view returns them to the panel, and they click Connect again.

Refusal is fail-closed on every path: nothing is minted, any dangling intent from an earlier initiation is deleted, and `omniauth_connect_reauth_required` (level `warn`) is logged. Platform mailbox-proof linking is a separate recovery policy and does not satisfy this gate.

A proof is also cleared before its window elapses by the events that invalidate it (#4420): logout (`before_logout`), password change (`after_change_password`), WebAuthn credential removal (`after_webauthn_remove`), and a successful Connect bind (`bind_omniauth_connect_identity`, which the gate already consumed for — the clear there is the cheap guarantee that a second bind within the window needs a fresh ceremony).

#### The connect-intent nonce (#3859)

| Property | Behavior |
|----------|----------|
| Written | `omniauth_request_validation_phase` (`config/hooks/omniauth.rb`), during `POST /auth/sso/:provider`, only when a logged-in caller submits `connect=1` **and** the recent-reauth gate consumed a fresh proof (#4411) |
| Stored as | `sidecar:<sid>:sso_connect_intent` = `{ account_id, surface, at }` — the **session account id**, the surface descriptor the gate verified, and the mint time (a pre-#4411 bare account id is refused as malformed), short TTL (~5 min — one IdP round-trip) |
| Consumed | Atomic GETDEL in the `before_omniauth_callback_route` wrapper, before tenant validation and the gem's cached-account/known-identity shortcuts |
| Binds when | The intent matches the current session account and surface, the account is open with an existing unsuspended Customer, the recorded session surface matches, and the full tuple is unclaimed or already owned by that account. On a tenant surface, additionally: the enablement constant is open, the session account holds an active membership authorizing the exact custom domain, and the tenant issuer resolves. |
| Abandoned connect | Needs no cleanup — the key expires. Additionally, any **non**-connect SSO initiation deletes a dangling intent, so a later plain `connect=0` callback can never consume one that is still in TTL |
| Failure mode | Fail-closed — a failed write or a miss means no intent, and no intent means no bind |

It is a sidecar key rather than a field in the session blob on purpose. A blob-resident nonce was only ever cleared at the callback, so an abandoned connect (user cancels at the IdP, the IdP errors, the tab closes) left it live for the *next* callback on that session — even a plain sign-in — to consume and bind on, which is exactly the shared-browser bind the nonce exists to prevent. Blob copies written by pre-#3859 code are discarded unconsumed.

#### Email plays no part in the decision

The Connect gates run **before account resolution** — ahead of the gem's known-identity shortcut, trusted-provider auto-link, and H-3 refusal. The account is loaded **by session id** (`_account_from_session`, which also applies the open-status filter), never by email. A missing or suspended Customer is refused on both surfaces. The successful Connect audit event records the provider, issuer, and session account ID, not the IdP-supplied email.

That ordering is the point: matching a connect to an email-*located* account would be the pre-account-hijacking anti-pattern — an attacker who controls an IdP that emits a victim's email would be routed to the victim's account. Routing by session leaves the victim untouched no matter what the IdP claims.

`BindSsoIdentity` resolves ownership by the complete `(provider, issuer, uid)` tuple after authorization. An unclaimed tuple is bound to the session account; a tuple already owned by that account is accepted without a duplicate row. A tuple owned by another account is refused without switching sessions. Connect does not use the ordinary lookup's legacy issuer backfill.

#### Refusals

| Condition | Outcome | Audit event |
|-----------|---------|-------------|
| Initiation without recent full re-authentication (no proof, stale, consumed, other account, other surface, non-local primary) | Redirect `/reauth?redirect=/account/settings/security/connections`; **no intent minted** | `omniauth_connect_reauth_required` (level `warn`) |
| Tenant callback (`validated_omniauth_domain_id` set) on a platform session | Redirect `/signin?auth_error=identity_connect_wrong_domain` | `omniauth_identity_connect_refused`, reason `surface_mismatch` |
| Intent surface differs from the callback surface (or the callback surface is unresolved) | Redirect `/signin?auth_error=identity_connect_wrong_domain` | `omniauth_identity_connect_refused`, reason `surface_mismatch` |
| Platform-fallback Connect callback on a custom domain without validated tenant context | Redirect `/signin?auth_error=identity_connect_wrong_domain` | `omniauth_identity_connect_refused`, reason `surface_mismatch` |
| Session account gone or no longer open (e.g. closed mid-session) | Redirect `/signin?auth_error=identity_connect_conflict` | `omniauth_identity_connect_refused`, reason `session_account_missing` |
| Customer missing | Redirect `/signin?auth_error=identity_connect_conflict` | `omniauth_identity_connect_refused`, reason `session_customer_missing` |
| Customer suspended | The auth router destroys the session before the Connect hook runs; the intent is purged with it and nothing is bound. See [Sessions ended before the callback](#sessions-ended-before-the-callback). The hook keeps its own `session_customer_suspended` refusal as a backstop | `customer_session_rejected` (level `warn`), reason `account_suspended` |
| Exact tuple owned by another account | Redirect `/signin?auth_error=identity_connect_conflict`; no account switch | `omniauth_identity_connect_refused`, reason `identity_owned_elsewhere` |
| Tenant Connect while the enablement constant is closed (`OmniAuthConnect.tenant_connect_enabled?`, an internal kill switch with no operator setting; checked before the membership gate, so no `tenant_connect_membership_authorized` record is written) | Redirect `/signin?auth_error=identity_connect_wrong_domain` | `omniauth_identity_connect_refused`, reason `tenant_connect_prerequisites_incomplete` |
| Tenant Connect without an active membership that authorizes the exact custom domain (`Auth::Operations::AuthorizeTenantConnect`) | Redirect `/signin?auth_error=identity_connect_wrong_domain` | `tenant_connect_membership_refused`, then `omniauth_identity_connect_refused`, reason `tenant_membership_refused` |
| Tenant Connect whose issuer cannot be resolved | Redirect `/signin?auth_error=identity_connect_wrong_domain` | `omniauth_identity_connect_refused`, reason `tenant_issuerless` |
| A gate raises before the bind (nothing written) | Redirect `/signin?auth_error=identity_connect_conflict` | `omniauth_connect_lookup_error` (level `error`), then `omniauth_identity_connect_refused`, reason `lookup_error` |
| The bind insert or a step after it raises (ownership re-read, audit log) | Unhandled: generic 500 from the auth router. If the row was written the identity **is** bound; either way a retry is idempotent. Never reported as a refusal | `Auth router unhandled exception` |
| Logged in, but no valid intent (second tab, shared browser, intent for a different account, malformed or pre-#4411 intent) | **No authenticated Connect** — takes the ordinary existing-identity or email-based sign-in path | `omniauth_connect_intent_absent` (level `info`) |
| Bind succeeds | `(provider, issuer, uid)` row written for the session account; session re-affirmed | `omniauth_identity_connected` (level `warn`) |

Refusing rather than falling back matters in the `surface_mismatch` rows: a tenant admin controls their own IdP's assertions, so binding a tenant-issuer identity onto a platform-session account would hand them a login into that account.

#### Sessions ended before the callback

The auth router (`apps/web/auth/router.rb`) evaluates the customer session ahead of every `/auth/*` route, Rodauth's and OmniAuth's included. Three verdicts destroy the Rack session on the spot: a revoked active-session row, a surface mismatch, and a definitive customer rejection (suspended, stale credentials, customer not found). When the request is an SSO callback, the router then lets it continue as the anonymous request it now is, and logs the event with `outcome: continued_anonymous` and the in-flight state it found (`omniauth_keys`, `sidecar_fields`).

| Verdict | Audit event |
|---------|-------------|
| Active-session row revoked | `active_session_revoked`, plus `active_session_revoked_mid_flow` (level `warn`) when a flow was in flight |
| Surface mismatch | `session_surface_mismatch` (level `warn`) |
| Suspended, stale credentials, customer not found | `customer_session_rejected` (level `warn`), with `reason` |

Two requirements decide this ordering:

- **The session ends first.** [OWASP ASVS 5.0.0 requirement 7.4.2](https://github.com/OWASP/ASVS/blob/v5.0.0/5.0/en/0x16-V7-Session-Management.md#v74-session-termination) requires that all active sessions are terminated when an account is disabled, and 7.4.1 that a terminated session cannot be used further. A suspended account's session is therefore not kept alive so that a later hook can refuse it more specifically.
- **The callback cannot outlive the session that started it.** [RFC 9700 section 2.1](https://www.rfc-editor.org/rfc/rfc9700.html#section-2.1) requires one-time `state` values "securely bound to the user agent", and [section 4.7.1](https://www.rfc-editor.org/rfc/rfc9700.html#section-4.7.1) describes `state` as linking the redirection request to the user agent session ([RFC 6749 section 10.12](https://www.rfc-editor.org/rfc/rfc6749#section-10.12) is the original requirement). OmniAuth keeps `omniauth.state`, the OIDC nonce and the PKCE verifier in the Rack session, so destroying the session removes them and the callback fails state verification. The Connect intent lives in the session sidecar and is purged by the same destroy, so nothing can be bound to the ended account.

The user sees an SSO failure and signs in again; the provider's one-time authorization code is spent. That is the cost of ending the session first, and the `warn` lines above are what tie the SSO failure to its cause.

**Test-mode caveat.** OmniAuth's mock mode (`OmniAuth.config.test_mode`) short-circuits the strategy's callback phase, so the state check does not run in specs. After a destroy, a mocked callback proceeds as an ordinary anonymous sign-in with the mocked assertion. Specs for these cases assert the router outcome (session destroyed, intent purged, nothing bound to the ended account, event logged) and do not assert what the mocked anonymous callback does next.

#### Managing linked identities (`GET` / `DELETE /auth/identities`)

`apps/web/auth/routes/identities.rb`, mirroring `routes/active_sessions.rb`:

| Endpoint | Purpose | Response |
|----------|---------|----------|
| `GET /auth/identities` | List the current account's identities | `{ identities: [{ id, provider, issuer, uid }] }` — `uid` is masked (`abcd…wxyz`, or `***` when ≤ 8 chars); the row `id` is the delete handle, so the full `sub` is never sent to the client. No `created_at`: migrations 006/008 do not add one. |
| `DELETE /auth/identities/:id` | Remove one identity | `200 { success }`; `404` unknown/not-yours; `409 { error_code: "last_credential" }`; `401` unauthenticated |

**No IDOR by construction.** Every query derives from one dataset pinned to `account_id = rodauth.session_value`, and the dataset is never widened. A cross-account id filters to zero rows and yields `404` — never a delete of someone else's identity. The `:id` segment is an integer matcher, so a non-numeric segment falls through to the router's 404.

**Last-credential guard.** An SSO-only account (no usable password) may not remove its **final** identity — that would lock it out. Accounts that have a password may remove identities freely. The existence check, the guard, and the delete run in **one transaction** with an account-scoped row lock (`for_update.all`), closing a TOCTOU where two concurrent DELETEs for *different* ids of the same SSO-only account could each observe two rows, both pass the guard, and strip every sign-in method. Note the shape: materialize the locked rows and count in Ruby — `identities_ds.for_update.count` emits `SELECT count(*) … FOR UPDATE`, which PostgreSQL rejects. Removals are logged (`SSO identity disconnected`, level `warn`).

**Issuer column.** Binds on this path go through the same `(provider, issuer, uid)` shape as the callback, with `issuer` coerced to the `''` sentinel rather than `NULL` so it matches the issuer-scoped unique index (see migration `008_issuer_scoped_identities.rb`).

#### Tenant surfaces

The panel also connects identities on a custom-domain surface when that domain has active tenant SSO (#3849). Tenant Connect is independent of `SSO_ALLOW_PLATFORM_FALLBACK`: fallback neither enables nor authorizes it. [NIST SP 800-63C-4 section 3.8.1](https://pages.nist.gov/800-63-4/sp800-63c/Federation/#account-linking) requires an authenticated subscriber session for linking, and [OWASP ASVS 5.0.0 requirement 7.5.1](https://github.com/OWASP/ASVS/blob/v5.0.0/5.0/en/0x16-V7-Session-Management.md#v75-defenses-against-session-abuse) requires full re-authentication before changing sensitive authentication attributes — both surfaces enforce the latter through the recent-reauth gate above (#4411). For tenant linking OTS additionally requires validated tenant callback context, an active organization membership that authorizes the exact custom domain (`OrganizationMembership#can_access_domain?`: organization-scoped, or scoped to that domain), a session scoped to the tenant surface, and recent full local re-authentication that completes the account's required MFA factors. Tenant Connect is also release-gated by `OmniAuthConnect.tenant_connect_enabled?`, an internal kill switch for incident response with no operator setting; closing it refuses tenant Connect and relaxes nothing. These tenant-session controls are OTS choices, not an architecture prescribed by those standards. Callback-domain validation (`session[:validated_omniauth_domain_id]`) is necessary but not a substitute for the membership or re-authentication gates. See [Requirements for authenticated tenant linking](per-domain-sso.md#requirements-for-authenticated-tenant-linking-3849).

### Sign-in interstitial (password-challenge linking)

The refusal is the *right* default, but for one common case it is unnecessarily blunt: a user who already has a **password** account and now signs in through SSO for the first time. That user *can* demonstrate a credential — their existing password — so instead of dead-ending them, the callback offers a **sign-in interstitial** that collects and verifies that password before binding the identity. This keeps the invariant intact: email still only *locates* the account; the existing password is the credential that *binds*.

This path needs no operator configuration. It is on by default and is the platform-surface recovery for a password user's first SSO sign-in (the counterpart to the authenticated [Connected Identities panel](#connected-identities-authenticated-linking-from-account-settings), which serves users who signed in with their password first).

**What happens (unauthenticated callback, existing account, identity not linked, trust flag off):**

1. `account_from_omniauth` looks up the located account's password hash directly (it cannot use `has_password?`, which reads the *session* account and there is no session yet on this path).
2. **Account has a password →** it mints a single-use `Onetime::SsoLinkChallenge` in Redis — a short-lived (5 min) token snapshotting `(provider, resolved_issuer, uid, normalized email, account id)` — logs `omniauth_link_challenge_issued` (level `warn`), and redirects the browser to the SPA interstitial at `/link-sso/{token}`.
3. **Account has no password (SSO-only) →** on the platform surface, it continues to [Mailbox-proof linking](#mailbox-proof-linking-passwordless-accounts); tenant callbacks retain the H-3 refusal (`omniauth_link_refused_existing_account`, redirect to `/signin?auth_error=tenant_sso_link_unavailable`) because there is no local credential to challenge.

**The interstitial endpoints** (`apps/web/auth/routes/link_sso.rb`):

| Endpoint | Purpose | Response |
|----------|---------|----------|
| `GET /auth/link-sso/{token}` | Display context for the page | `{ provider, email }` — display only; never the account id, uid, or issuer. Missing/consumed/expired token → `404 { error, error_code: "link_expired" }`. |
| `POST /auth/link-sso` | Verify password, bind identity, log in | Body `{ token, password }`. Success establishes the session and returns Rodauth's standard login JSON response (`200 { success, … }`, plus `mfa_required`/`billing_redirect` when applicable). Failures return `{ error, error_code }` (see below). |

**POST error codes** (the SPA maps these to copy and, for `link_expired`/`link_conflict`, the account-settings connections pointer `/account/settings/security/connections`):

| Status | `error_code` | Meaning |
|--------|--------------|---------|
| 400 | `invalid_request` | token or password missing |
| 401 | `link_expired` | token missing / already consumed / expired, or the located account vanished |
| 401 | `invalid_password` | the existing password did not verify |
| 409 | `link_conflict` | the email resolves to a different account than the one snapshotted at mint, or the identity is already bound to another account |
| 429 | `link_rate_limited` | too many password-verification attempts; retry later (the token is not consumed) |

**Why the token is single-use (security-load-bearing).** `POST /auth/link-sso` **deletes** the challenge up front — before it even checks the password — so a token is worth exactly **one** attempt. This is deliberate: password verification runs through `Auth::Config.valid_login_and_password?`, a Rodauth *internal request* that does **not** go through the login route and therefore does **not** increment lockout counters. Without one-shot consumption, a token minted by an attacker who completed an SSO round-trip asserting a victim's email would be an unbounded (TTL-window) password-guessing oracle with no lockout. One-shot consumption bounds it to a single guess per full IdP round-trip. The 5-minute TTL bounds abandoned challenges. On a wrong password the user must restart the SSO sign-in — a deliberate trade of a small amount of retry convenience for closing the oracle.

**Session establishment reuses Rodauth's own machinery.** On a correct password the handler binds the `(provider, issuer, uid)` row (same shape as `omniauth_identity_insert_hash`) and then calls `rodauth.login('password')` rather than hand-rolling the session. That runs the normal `after_login` path — the Redis session blob via `SyncSession` (the real app auth gate), `active_sessions` registration, and MFA detection — so a password account that has OTP configured still gets the MFA gate, exactly as a direct `/auth/login` would.

**Platform-only.** The interstitial is only ever offered on the platform callback path. The email branches in `account_from_omniauth` are reached solely when `session[:validated_omniauth_domain_id]` is `nil` (tenant callbacks bind by session or refuse earlier), so a tenant callback can never mint a challenge. Authenticated linking on a tenant surface goes through [Connected Identities](#connected-identities-authenticated-linking-from-account-settings).

### Mailbox-proof linking (passwordless accounts)

The sign-in interstitial above proves ownership with the account's **existing password**. That leaves one case: a **passwordless** account (SSO-only, or migrated without a local password) whose owner now signs in through a *new* SSO identity. There is no password to challenge — but that account can still prove ownership the same way magic-link (email_auth) does: **control of its on-file mailbox.** So instead of dead-ending at the H-3 refusal, the callback **emails a single-use link to the account's on-file address**, and binding the `(provider, issuer, uid)` identity happens only when the user clicks it and confirms. Mailbox control is the demonstrated credential; the invariant holds.

This is an OTS platform-linking and account-recovery policy, not a NIST
out-of-band authentication method or a substitute for the full
re-authentication required for tenant Connect. NIST SP 800-63B-4 prohibits
email for out-of-band authentication; any use of this flow is an explicit OTS
policy exception rather than NIST AAL conformance.

**The token travels only through the email — never the callback redirect.** The proof is mailbox control, so the callback redirects the browser to a **token-less** notice (`/signin?auth_notice=link_verification_sent`) and delivers the token *solely* to the on-file inbox. A caller who merely completed an SSO round-trip asserting the victim's email therefore never learns the token and cannot self-consume it.

**What happens (unauthenticated callback, existing passwordless account, identity not linked, trust flag off, platform surface):**

1. `account_from_omniauth` finds no challengeable password for the located account (Phase 3's SQL + Redis-migration probe both come up empty).
2. It mints a single-use `Onetime::SsoLinkVerification` in Redis — a short-lived (15 min) token snapshotting `(provider, resolved_issuer, uid, normalized email, account id, initiating session id, password watermark)`.
3. It emails the token to the account's **on-file address** (`fallback: :sync`, auth-critical), logs `sso_link_verification_issued` (level `warn`), and redirects to the token-less notice. If mail delivery *raises*, the token is consumed and the flow falls through to the H-3 refusal — the user is never told to check an inbox that got no mail (fail closed).

**Consent screen + confirm endpoints** (`apps/web/auth/routes/sso_link_confirm.rb`):

| Endpoint | Purpose | Response |
|----------|---------|----------|
| `GET /auth/sso-link-confirm/{token}` | Consent display context | `{ provider, email }` — names the requesting provider and echoes the claimed email; never the account id, uid, issuer, sid, or watermark. **Never consumes the token.** Missing/consumed/expired token → `404 { error, error_code: "link_expired" }`. |
| `POST /auth/sso-link-confirm` | Consume token, bind identity, log in | Body `{ token }`. Success establishes the session and returns Rodauth's standard login JSON response (`200 { success, … }`, or `mfa_required` when a second factor is pending). Failures return `{ error, error_code }` (see below). |

**Why GET is display-only and POST does the mutation.** The emailed link opens the SPA consent screen, which `GET`s the display context (the consent copy names the provider *and* the claimed email) and only mutates on an explicit user action — the `POST`. A GET must stay side-effect-free: mail clients and link-preview bots prefetch GET URLs, and a mutating GET would let such a prefetch silently consume the single-use token before the user ever consents.

**POST error codes:**

| Status | `error_code` | Meaning |
|--------|--------------|---------|
| 400 | `invalid_request` | token missing from the POST body |
| 401 | `link_expired` | token missing / already consumed / expired, or the snapshotted account vanished or is no longer loginable |
| 409 | `link_conflict` | the account was re-emailed since issuance, or the `(provider, issuer, uid)` is already bound to a different account |
| 409 | `link_invalidated` | a credential change advanced the account's password watermark since the token was issued |
| 409 | `link_error` | the credential watermark could not be read; the consumed token cannot be retried |
| 429 | `confirm_rate_limited` | too many confirmation attempts; retry later (the token is not consumed) |

**Single-use, atomically consumed.** `POST /auth/sso-link-confirm` deletes the token up front (`#delete!` — the atomic single-use gate) before binding, so it is worth exactly one confirmation. Two concurrent confirmations race on the delete count; only the winner proceeds. The 15-minute TTL bounds abandoned tokens.

**Invalidated on any credential change (watermark, not a sweep).** The token snapshots the account's `Customer#last_password_update` at issuance. Every password set/reset/change stamps that watermark (via `Auth::Operations::UpdatePasswordMetadata` in the `after_*_password` hooks). At confirm time the op re-reads the current watermark and rejects (`link_invalidated`) if it advanced. This is a comparison, not a token-enumeration sweep — no need to find and delete outstanding tokens on every credential change. (This is why the credential-change hooks needed no modification.)

**Soft, cross-device session binding.** The token records the id of the session that *initiated* the SSO round-trip, but the check is **compare-and-warn, not a hard gate**: mailbox proof is inherently cross-device (the user may open the link on their phone). A sid mismatch is logged (`sso_link_verification_cross_device`, level `info`) and tolerated.

**Confirm logs the user in.** The account is passwordless and clicking the emailed link proves mailbox control — the *same* proof magic-link uses to authenticate — so on success the confirm route establishes the session through Rodauth's own `login` machinery (`rodauth.login('sso_link_confirm')`), not a hand-rolled session. That runs the normal `after_login` path (Redis session blob via `SyncSession` — the real app auth gate — plus `active_sessions` registration and MFA detection). The user lands signed in and their newly linked SSO works next time.

**MFA-safe bind, completed after the second factor.** SSO logins are MFA-exempt, so if the passwordless account has a pending second factor the identity bind is **deferred** rather than performed at confirm time — a pre-2FA bind would be an MFA-bypassing login path. The authorized bind is stashed by `Auth::Operations::DeferredSsoBind` in a short-TTL `SessionSidecar` key bound to the partial-MFA session's sid (#3858), the login proceeds to the OTP step (emitting `mfa_required`, logged as `sso_link_verification_deferred_mfa`), and `after_two_factor_authentication` (`config/hooks/two_factor.rb`) completes the bind once the second factor succeeds — OTP *or* recovery code. Completion is single-use (atomic GETDEL at the store), account-bound, and audit-and-skip on conflict/mismatch (`sso_deferred_bind_completed`): MFA has already succeeded, so nothing on that path may fail the login. For a login that never went through a deferred branch the check is one Redis GETDEL and no DB access. Moot for default installs (MFA off), load-bearing for `AUTH_MFA_ENABLED` deployments. The password interstitial uses the same machinery (#3877/#3879).

**Platform-only.** Like the password interstitial, mailbox-proof linking is only offered on the platform callback path. A tenant admin controls their own IdP and could otherwise trigger link emails to arbitrary platform addresses, so tenant callbacks keep the unchanged H-3 refusal.

**Audit events.** `sso_link_verification_issued` (issuance), `sso_link_verification_confirmed` (successful bind), plus `sso_link_verification_deferred_mfa`, `sso_link_verification_invalidated`, `sso_link_verification_conflict`, `sso_link_verification_cross_device`, and `sso_link_verification_send_FAILED` for the branch outcomes.

### The flag

Per-provider environment variables, plus a global fallback. Default is **false** (refuse) in every case.

| Variable | Applies to |
|----------|-----------|
| `OIDC_TRUST_EMAIL_FOR_LINKING` | Generic OIDC provider |
| `ENTRA_TRUST_EMAIL_FOR_LINKING` | Microsoft Entra ID |
| `GOOGLE_TRUST_EMAIL_FOR_LINKING` | Google |
| `GITHUB_TRUST_EMAIL_FOR_LINKING` | GitHub |
| `SSO_TRUST_EMAIL_FOR_LINKING` | Global fallback (deprecated single-OIDC default) |

Set the value to the string `true` to enable; anything else (or unset) is disabled. Precedence: a per-provider variable, **when present**, wins for that provider (`true` enables, any other value disables); otherwise the global `SSO_TRUST_EMAIL_FOR_LINKING=true` enables linking for every platform provider that has no per-provider override; otherwise the default of `false` applies.

**Opting a single provider out of a global `true` requires an explicit `=false`, not omission.** With `SSO_TRUST_EMAIL_FOR_LINKING=true`, a provider whose `*_TRUST_EMAIL_FOR_LINKING` is simply left unset *inherits* the global `true` — it is not opted out. To disable linking for one provider while keeping the global default for the others, set that provider's variable explicitly, e.g. `GITHUB_TRUST_EMAIL_FOR_LINKING=false`. Setting **every** provider to `false` disables the feature entirely even with the global `true` still present.

**What it does when true:** for the matched provider, `account_from_omniauth` returns the account located by the (normalized, case-insensitive) email instead of refusing. `rodauth-omniauth` then persists the `(provider, uid)` row and signs the user in — the intended auto-link. The lookup surface is unchanged: it is the *same* normalized email H-3 already used, just no longer refused. Each such link emits an `omniauth_email_linked_trusted_provider` audit event at level `warn`, so linking-by-trust is always visible in the audit log.

### Threat-model caveat

> You are declaring this IdP wholly inside your trust boundary. Enable only for single-tenant installs where the same operator controls both OTS and the IdP.

Why: whoever controls the IdP can mint a token bearing **any** victim's email. Trusting the email for linking is therefore identical to trusting the IdP to never do that. That assumption holds when you run the IdP yourself and it serves only your own users; it does not hold for a shared or third-party IdP, or for any deployment where users bring their own IdP. Turning the flag on there converts "controls an IdP" into "can take over any account by email."

### The flag is platform-only; multi-tenant is refused by construction

The flag affects **only** the platform (environment-configured) SSO provider path. It has no effect on per-domain tenant SSO (`CustomDomain::SsoConfig`). This is enforced structurally, not by a second check: the tenant callback path sets `session[:validated_omniauth_domain_id]`, and the linking branch only runs when that value is `nil`. Tenant callbacks therefore never reach the trusted-linking branch, regardless of how the flag is set.

Because the flag looks like it might apply to tenants but cannot, the boot initializer `CheckTenantSsoTrust` emits a **WARN** (via the auth logger) when the flag is enabled *and* at least one `CustomDomain::SsoConfig` record exists — a signal that an operator may believe they enabled cross-IdP email linking for tenants when they have not. The guard is **non-fatal by design**: production runs live tenant SSO configs alongside a large account base, and a fatal guard would brick those deploys. A clean install with the flag off boots silently.

### Documented bypass: domain validation is skipped on the auto-link path

The `before_omniauth_create_account` hook — which enforces `ALLOWED_SIGNUP_DOMAIN` and per-domain `SignupConfig` restrictions — runs only on the account-**create** path. The trusted auto-link path returns the existing account before any create happens, so it does **not** pass through that domain check. This is acceptable because no new account is minted and no new email is admitted: the account already exists and was located by its own stored email. It is called out here so the behavior is documented rather than discovered — if you rely on `ALLOWED_SIGNUP_DOMAIN` as a security boundary, note that it gates signups, not links.

### Gotcha: renaming a provider route orphans existing links

The `provider` string stored in `account_identities` is derived from the provider's route name (`OIDC_ROUTE_NAME`, `ENTRA_ROUTE_NAME`, etc., defaulting to `oidc`/`entra`/`google`/`github`). Changing that route name — or moving a tenant from one strategy to another — changes the stored `provider` value for all **new** logins, which no longer matches the `provider` recorded on **existing** `account_identities` rows. The effect is that every previously linked user is treated as unlinked at once: each is refused (default) or forced through a fresh auto-link (trust flag on) on their next SSO sign-in. Treat any change to a route name as a mass re-link event and communicate it to your users, or migrate the stored `provider` values deliberately. Do not rename provider routes casually on a deployment with existing SSO users.

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
```

#### Auth0

1. Dashboard → Applications → Create → Regular Web Application
2. Settings → Allowed Callback URLs: `https://{host}/auth/sso/oidc/callback`
3. Copy **Domain**, **Client ID**, **Client Secret**

Auth0 asserts `iss` with a **trailing slash** (`https://<tenant>/`).
`OIDC_ISSUER` must match it byte for byte: both the discovery document's
`issuer` and the id_token's `iss` are compared exactly, so without the slash
sign-in fails with an issuer mismatch. Custom domains follow the same rule.

```bash
OIDC_ISSUER=https://your-tenant.auth0.com/
OIDC_CLIENT_ID=your-client-id
OIDC_CLIENT_SECRET=your-client-secret
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
- Ensure the application issues a usable `email` claim. SSO account lookup and just-in-time creation read the OmniAuth `info.email` value; configure Entra optional claims or user-attribute mapping when the token does not include `email`.

```bash
ENTRA_TENANT_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
ENTRA_CLIENT_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
ENTRA_CLIENT_SECRET=client-secret-value
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
```

Note: For GitHub Organizations, use GitHub Apps instead of OAuth Apps for finer-grained permissions.

### Apple

Uses the `omniauth-apple` gem. The gem mints a fresh ES256 client-secret JWT per
request from your `.p8` key, so there is no client secret to configure.

#### Apple Developer Setup

1. **Apple Developer** → Certificates, Identifiers & Profiles → Identifiers → new **Services ID**
2. Enable **Sign in with Apple** on it and configure the web domain
3. **Return URL**: `https://{host}/auth/sso/apple/callback`
4. Keys → new key with **Sign in with Apple** enabled → download the `.p8` (once only)

Get the values:
- **Services ID** (e.g. `com.example.web`) → `APPLE_CLIENT_ID`
- **Team ID** (top right of the developer portal) → `APPLE_TEAM_ID`
- **Key ID** of the key you created → `APPLE_KEY_ID`
- The **contents** of the `.p8` file → `APPLE_PRIVATE_KEY`

```bash
APPLE_CLIENT_ID=com.example.web
APPLE_TEAM_ID=XXXXXXXXXX
APPLE_KEY_ID=XXXXXXXXXX
APPLE_PRIVATE_KEY="<whole .p8 file, newlines written as literal \n>"
```

`APPLE_PRIVATE_KEY` takes the entire `.p8` file including its PEM header and
footer lines, with each newline written as a literal `\n`; the provider
definition un-escapes it before `OpenSSL::PKey::EC` parses it. A real sample
is not printed here because it trips the `detect-private-key` pre-commit hook.

Prerequisite: Apple's callback is a cross-site POST (`response_mode=form_post`),
and a `SameSite=Lax` cookie is withheld on it — set `site.session.same_site: none`
with `secure: true` or the flow fails CSRF validation at the callback.

Note: the user's **name** arrives only on the **first** authorization for a
given Services ID. The **email** comes from the id_token on every
authorization, so repeat sign-ins and account creation are unaffected — but it
may be a private-relay address (`@privaterelay.appleid.com`). Leave
`APPLE_TRUST_EMAIL_FOR_LINKING` false.

### SAML 2.0

Uses the `omniauth-saml` gem (ruby-saml underneath) through this application's
own subclass, `OmniAuth::Strategies::RequestBoundSAML`, which binds every
response to the sign-in request this session started and refuses everything
else. There is no client ID or secret: trust is the IdP's signing certificate,
pinned in `SAML_IDP_CERT`. What the subclass enforces, and why, is in
[Adding an SSO Provider](adding-sso-providers.md#known-provider-quirks).

#### Identity Provider Setup

Register Onetime Secret as a service provider (SP) at your IdP. With `{host}`
the value of `site.host` and `saml` the route name:

| IdP setting | Value |
|-------------|-------|
| SP EntityID / Audience | `https://{host}/auth/sso/saml/metadata` (or `SAML_SP_ENTITY_ID`, if you set it) |
| Assertion Consumer Service (ACS) URL | `https://{host}/auth/sso/saml/callback`, HTTP-POST binding |
| SP metadata | `https://{host}/auth/sso/saml/metadata` (served once the provider is configured) |
| NameID format | persistent (requested in every AuthnRequest; a transient NameID is refused unless `SAML_UID_ATTRIBUTE` is set) |
| Assertion signing | required (`want_assertions_signed`), RSA-SHA256 or stronger. A response signed or digested with SHA-1 (or any algorithm outside RSA/ECDSA-SHA256/384/512 and SHA-256/384/512) is refused as `saml_weak_signature_algorithm`: ruby-saml 1.18.1 itself verifies whichever algorithm the response declares, so the strategy enforces the allowlist |
| Assertion encryption | off (not supported) |
| AuthnRequest signing | off (requests are not signed; no SP key is configured) |
| Attributes | the user's email as an attribute named `email` or `mail` (the NameID is the user id, not the email); optionally `name`, `first_name`, `last_name`, and the attribute named in `SAML_UID_ATTRIBUTE` |

Then take from the IdP:

- its **SSO service URL** (HTTP-Redirect binding) → `SAML_IDP_SSO_SERVICE_URL`
- its **EntityID** (the value it sends in `<Issuer>`) → `SAML_IDP_ENTITY_ID`
- its **signing certificate** (PEM) → `SAML_IDP_CERT`

```bash
SAML_IDP_SSO_SERVICE_URL=https://idp.example.com/sso/saml
SAML_IDP_ENTITY_ID=https://idp.example.com/metadata
SAML_IDP_CERT="-----BEGIN CERTIFICATE-----\nMIID...\n-----END CERTIFICATE-----"
```

`SAML_IDP_CERT` takes the whole PEM file, header and footer lines included,
with each newline written as a literal `\n` (the same convention as
`APPLE_PRIVATE_KEY`); a value that already contains newlines is accepted as
is. Exactly one certificate: a bundle is refused rather than trusting only its
first block. Certificate fingerprints are not supported — fingerprint-only
trust accepts whatever certificate the response embeds.

`SAML_IDP_ENTITY_ID` is compared byte for byte with the response's Issuer
(scheme case, trailing slash and all), and it is the issuer half of every SAML
identity key `(saml, EntityID, NameID)`. Changing it later orphans existing
SAML sign-ins.

The default `SAML_SP_ENTITY_ID` is derived at boot from `site.host` and
`site.ssl`; if both `SAML_SP_ENTITY_ID` and `site.host` are blank the provider
is skipped. It is a boot-time constant: the IdP registers one audience for the
platform, whichever host a request arrives on.

Prerequisite: the HTTP-POST binding delivers the response as a cross-site POST
and a `SameSite=Lax` cookie is withheld on it, taking the pending sign-in
request with it — set `site.session.same_site: none` with `secure: true`, as
for Apple. Without it every callback is refused as `saml_no_pending_request`.
The app checks this for you. With the platform `SAML_*` variables set under an
incompatible cookie, the provider is skipped outright — no route, no login
button — and boot logs `[OmniAuth] Skipping SAML provider 'saml':
site.session.same_site is 'lax' and secure is …; SAML needs same_site: none
with secure: true, …` (the same skip contract as missing vars, below). With
`ORGS_SSO_ENABLED=true` and no platform vars, the route still registers as the
tenant placeholder, and boot instead logs `[OmniAuth] SAML is enabled (tenant
SSO (ORGS_SSO_ENABLED=true)) but site.session.same_site is 'lax' and secure is
…; SAML needs same_site: none with secure: true, …`, continuing (boot never
aborts for an SSO provider). On the tenant side the same
rule is enforced at save time: the domain SSO API refuses to create a
`provider_type: saml` configuration (422 on `provider_type`, "SAML sign-in
cannot complete on this install: …") while the cookie is incompatible, since an
organization admin cannot change the install's cookie. An existing SAML record
stays editable — it can be disabled, rotated or switched to another provider —
so nothing gets stuck.

Missing or unusable configuration skips the provider (`[OmniAuth] Skipping
SAML provider 'saml': …` in the boot log, naming the variable) and hides the
button; it does not fail boot. Issue #4450 asked for a boot failure; the
provider registration path is designed never to take password, MFA and
magic-link sign-in down with it, so SAML follows the same skip contract as
every other provider. The usability check runs again per request when the button is
rendered: a certificate that expires while the process is running hides the
button and ruby-saml refuses every login with it (`check_idp_cert_expiration`),
but nothing alerts on it — watch the certificate's expiry.

Certificate rotation: only one IdP certificate is trusted at a time
(`idp_cert_multi` is not supported), so there is no overlap window. Update
`SAML_IDP_CERT` and restart when the IdP switches to its new certificate.

Not supported, by design: IdP-initiated sign-in (users must start from this
site's sign-in page; a response that answers no pending request is refused),
Single Logout (`/slo` and `/spslo` answer 501), encrypted assertions, signed
AuthnRequests, multiple IdP certificates, fingerprint configuration. One
sign-in attempt is pending per session: a second tab's request supersedes the
first, whose response is then refused.

Platform SAML uses one fixed SP EntityID: `SAML_SP_ENTITY_ID`, or its default
based on `site.host`. Its ACS normally uses `site.host`. With
`SSO_ALLOW_PLATFORM_FALLBACK=true`, a verified custom domain without active
tenant SSO may use the same platform SAML configuration for **sign-in only**.
That flow keeps the fixed platform EntityID but sets the ACS to the exact
request host:

`https://{verified-custom-domain}/auth/sso/{route}/callback`

Register that exact ACS URL at the IdP before enabling the fallback for users.
The sign-in must start and return on the same custom host. The session cookie
must therefore be host-only (no `Domain` attribute) and configured
`SameSite=None; Secure`; otherwise the POST callback cannot recover the pending
request safely.

This is a platform identity path, not tenant SSO. It uses the platform IdP
certificate, platform EntityID, and platform identity namespace; it does not
load the domain's `SsoConfig`, create validated tenant context, authorize
Connected Identities, or confer tenant membership. A domain with active tenant
SSO uses its tenant configuration instead.

Treat each registered fallback ACS as lifecycle-managed configuration. Remove
its IdP registration when the custom domain is deleted, becomes unverified,
stops resolving to this installation, gains active tenant SSO, or platform
fallback is disabled. Per-domain SAML with its own trust configuration is
documented in [Per-Domain SSO](per-domain-sso.md#saml-20-for-a-custom-domain).

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
  provider VARCHAR NOT NULL,             -- configured route name
  issuer VARCHAR NOT NULL DEFAULT '',    -- '' sentinel when no issuer is available
  uid VARCHAR NOT NULL,                  -- IdP-specific subject identifier
  UNIQUE (provider, issuer, uid)
);
CREATE INDEX ON account_identities (account_id);
```

The identity key is `(provider, issuer, uid)`. `issuer` scopes providers that can authenticate against multiple issuers; OAuth2-only rows use the empty-string (`''`) sentinel rather than `NULL`, and legacy rows start with that value until a platform callback lazily upgrades them. The `provider` value is derived from the configured route name.

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
| `sso_cancelled` | `web.login.errors.sso_cancelled` | The user declined at the IdP |
| `sso_not_configured` | `web.login.errors.sso_not_configured` | Custom domain with no tenant SSO configuration at all |
| `sso_config_unusable` | `web.login.errors.sso_config_unusable` | Tenant SSO exists but cannot produce usable options: expired or not-yet-valid certificate, or a field that no longer decrypts |

SAML refusals made by `RequestBoundSAML` land on `sso_failed` with the reason
in a `[saml_response_refused]` log event; ruby-saml document-validation
failures land there as `invalid_ticket`. See [SAML sign-in refused](#saml-sign-in-refused).

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

### SSO user's colonel/admin role has no effect

Customers provisioned via SSO before v0.26.5 were left unverified in Redis, and system roles require `verified?`. See [runbooks/sso-accounts-unverified.md](../runbooks/sso-accounts-unverified.md) for the `bin/ots customers doctor --all --repair` procedure. (#3973)

A customer provisioned on a current version can also be unverified on purpose: if the IdP asserted `email_verified: false`, or that claim could not be read, the hook records the reason in `verification_hold` and the doctor will not auto-repair it. The same runbook covers what to check before verifying by hand.

### SAML sign-in refused

Every refusal lands on `/signin?auth_error=sso_failed`. The reason is in the
auth log as `[saml_response_refused] reason=<code>` — a gate in
`RequestBoundSAML`, or `reason=invalid_ticket` for ruby-saml document
validation, where `detail` carries the gem's check name (bounded to 200
characters, one line). The `[OmniAuth FAILURE]` line and the
`omniauth_failure` audit event carry a fixed message for SAML: ruby-saml's
messages embed response text (Issuer, Audience, the unsigned StatusMessage),
so they never reach a log line unbounded.

| `reason` | Meaning | Check |
|----------|---------|-------|
| `saml_no_pending_request` | The callback arrived in a session with no pending sign-in | `site.session.same_site` must be `none` with `secure: true` (boot logs `[OmniAuth] SAML is enabled … but site.session.same_site is …` for the tenant placeholder only — with platform `SAML_*` vars set the provider is skipped instead and never reaches this row); an IdP-initiated sign-in (started from the IdP's portal) is refused by design; a second sign-in tab supersedes the first |
| `saml_acs_host_mismatch` | The callback host does not match the ACS host fixed for this request, or the custom host is not eligible for platform fallback | Start and complete the flow on the same host. For custom-domain platform fallback, verify the domain, enable `SSO_ALLOW_PLATFORM_FALLBACK`, confirm no active tenant SSO configuration supersedes it, and register the exact request-host ACS URL at the IdP |
| `saml_response_missing` | The callback was not a POST carrying a `SAMLResponse` (the event names the `method`); the pending sign-in is left intact | A cross-site GET (an `<img>` or prefetch) hitting the callback path, or a browser retrying a redirect as GET; harmless unless frequent |
| `saml_in_response_to_unbound` | The signed assertion's `SubjectConfirmationData/@InResponseTo` is missing, or does not equal the pending AuthnRequest id on every bearer confirmation | The IdP response does not satisfy the required request binding, or the assertion may have been rewrapped; investigate |
| `saml_misconfigured` | `idp_entity_id` or `sp_entity_id` is blank on the route | The platform variables are unusable, or the custom-domain tenant record was not injected |
| `saml_issuer_unreadable` | The Issuer elements could not be read after validation (defense in depth: a missing or repeated Issuer is refused by ruby-saml first, as `invalid_ticket`) | IdP configuration |
| `saml_weak_signature_algorithm` | A signature in the response uses a `SignatureMethod` or `DigestMethod` outside the allowlist (RSA/ECDSA-SHA256/384/512, SHA-256/384/512) — typically RSA-SHA1 / SHA1 | Configure SHA-256 signing at the IdP; the log event names the offending `kind` and `algorithm` URI |
| `saml_issuer_mismatch` | The response's Issuer is not byte-equal to `SAML_IDP_ENTITY_ID` (or the tenant's `idp_entity_id`) | Copy the EntityID exactly as the IdP publishes it — scheme case, port, trailing slash |
| `saml_transient_name_id` | The IdP sent a transient NameID | Configure a persistent NameID at the IdP, or set `SAML_UID_ATTRIBUTE` (platform only) |
| `saml_missing_uid` | The NameID (or the uid attribute) is empty | IdP attribute mapping |
| `saml_assertion_unbounded` | The assertion has no `ID` or no `Conditions/@NotOnOrAfter` | IdP configuration; both are required |
| `saml_assertion_lifetime_exceeded` | `Conditions/@NotOnOrAfter` is more than one hour (plus 60 s clock drift) in the future; the event carries `lifetime_seconds` | Shorten the assertion lifetime at the IdP; check the IdP clock |
| `saml_assertion_replayed` | The same assertion was presented a second time | Browser back/refresh on the callback page; otherwise investigate |
| `saml_replay_guard_unavailable` | Valkey/Redis was unavailable during the callback | Datastore health; the callback fails closed |
| `invalid_ticket` | ruby-saml rejected the document: signature, unsigned assertion, audience, destination or recipient, validity window (60 s clock drift allowed), expired IdP certificate, InResponseTo mismatch, non-Success status | The event's `detail` names the check; compare the IdP's SP registration with the values in the SAML setup table |

### SAML callback returns 403

`Rack::Protection::HttpOrigin` denies a cross-site POST unless its `Origin`
is an admitted IdP origin. For platform SAML that origin is derived from
`SAML_IDP_SSO_SERVICE_URL` (the browser posts back from the IdP's SSO
endpoint), never from the EntityID; the same platform origin applies to an
eligible custom-domain fallback. `SSO_FORM_ACTION_ORIGINS` widens this set too,
so it can cover an IdP whose login page lives on a different origin than its
SSO service URL. Tenant SAML instead admits that domain record's
`idp_sso_service_url` origin for the domain only, with no override.

### CSRF error on callback

If you see `encoded token is not a string`: the CSRF bypass for SSO routes is misconfigured. Check that `lib/onetime/middleware/security.rb` skips `/auth/sso/*` and that the `omniauth_request_validation_phase` hook is empty in `hooks/omniauth.rb`.

### SSO login blocked on Chromium-family browsers (CSP `form-action`)

**Symptom:** Clicking a "Login with {Provider}" button appears to do nothing, and the browser console shows a Content-Security-Policy error naming the `form-action` directive. Chrome, Edge, and other Chromium-family browsers are affected; Firefox is not.

**Cause:** As of otto 2.5 (shipped in v0.26.0-rc1), the emitted CSP contained `form-action 'self'`. The SSO flow POSTs a form to `/auth/sso/{provider}`, which responds with a redirect to the IdP's authorization endpoint. Chromium enforces `form-action` across the entire redirect chain, so the cross-origin hop to the IdP is blocked. Firefox only checks the initial (same-origin) form target and never trips the policy — which is why the bug reproduces in one browser family and not the other. (#3848)

**Fix (automatic):** IdP origins are derived on two levels (#3848, #4173):

- **Platform providers (boot):** the origin of each active env-configured SSO provider is added to the `form-action` directive when the router is built:

  | Provider | Origin added |
  |----------|--------------|
  | Microsoft Entra ID | `https://login.microsoftonline.com` |
  | Google | `https://accounts.google.com` |
  | GitHub | `https://github.com` |
  | Generic OIDC | Origin of `OIDC_ISSUER` |
  | Apple | `https://appleid.apple.com` |
  | Auth0 | Origin of `AUTH0_DOMAIN` |
  | SAML 2.0 | Origin of `SAML_IDP_SSO_SERVICE_URL` (not the EntityID) |

- **Tenant (per-domain) SSO (per-request):** on a custom domain whose per-domain SSO config is enabled and permitted, the domain's IdP origin (the SSO config's issuer origin for OIDC, its `idp_sso_service_url` origin for SAML, `https://login.microsoftonline.com` for Entra ID) is added to `form-action` for that request only — on that domain and nowhere else. No env var is involved; the origin follows the domain's stored SSO config automatically.

No configuration is required for the common case. The boot-time set is exposed as `Onetime.auth_config.sso_form_action_origins`; the per-request widening is `Onetime::Middleware::TenantCspExtras`.

**Sovereign Microsoft Entra:** The Entra provider is pinned to the commercial cloud on both platform and tenant SSO. Configure a sovereign cloud as generic OIDC with its sovereign v2.0 issuer; its origin is derived automatically. Do not add a sovereign origin through `SSO_FORM_ACTION_ORIGINS`: it widens CSP but does not change the Entra redirect. See [OIDC for sovereign Microsoft Entra tenants](per-domain-sso.md#oidc-for-sovereign-microsoft-entra-tenants) for tenant issuer values, access-control posture, and identity-migration caveats.

**When to use the override:** Set `SSO_FORM_ACTION_ORIGINS` (space-separated origins) when the auto-derived origin is wrong or incomplete:

- **OIDC issuer ≠ authorization endpoint** — when the discovery document's `authorization_endpoint` lives on a different origin than the issuer (`OIDC_ISSUER`, or a tenant SSO config's issuer). The form POSTs to the authorization endpoint's origin, which is what CSP checks.
- **Per-request derivation gaps** — the tenant widening depends on resolving the display domain's stored SSO config at response time. If the domain record is unreachable (datastore blip), the widening is skipped silently — the only symptom is the browser-console CSP error — and the issuers are effectively unknown per-request. `SSO_FORM_ACTION_ORIGINS` remains the manual fallback when such gaps must not block SSO.

```bash
SSO_FORM_ACTION_ORIGINS="https://authorize.example.gov"
```

**Interim workaround (un-upgraded installs):** If you cannot yet deploy the fix, set `CSP_ENABLED=false` to drop the CSP header entirely. This unblocks SSO at the cost of losing CSP protection, so treat it as temporary and re-enable CSP after upgrading.

## Security Notes

- PKCE enabled by default (generic OIDC)
- OAuth state parameter provides CSRF protection for the redirect flow
- The IdP email verifies the account for JIT signup, but by default is **not** treated as an identity join key: an SSO identity is not auto-linked to a pre-existing account found only by email (see [Identity Linking and the Trusted-IdP Flag](#identity-linking-and-the-trusted-idp-flag))
- Sessions use same security settings as password auth
- Domain restrictions validated before account creation
- Client secrets should be rotated per provider's recommendations
- SAML: every response must answer the AuthnRequest this session issued (`InResponseTo` on the signed assertion's `SubjectConfirmationData`, one-shot; only a POST carrying a `SAMLResponse` consumes the pending id) — IdP-initiated sign-in is refused; the response Issuer must equal the configured EntityID byte for byte; assertions must be signed with SHA-256 or stronger (ruby-saml verifies whichever algorithm the response declares, so the strategy refuses SHA-1 and unknown algorithms itself; a certificate embedded in the response is matched against the pinned one by SHA-256 fingerprint) and are single-use (a Valkey replay cache keyed on the assertion ID, TTL bounded by `NotOnOrAfter`; assertions valid for more than one hour are refused); trust is one pinned PEM certificate with expiry checked, never a fingerprint; the auth hash never carries the raw response
- `ruby-saml` is pinned exactly in the `Gemfile` with its advisory history; `bundler-audit` runs on every PR

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
| `lib/onetime/sso_provider/registry.rb` | Provider definitions (one file per provider under `lib/onetime/sso_provider/`) |
| `lib/onetime/sso_provider/saml.rb` | SAML definition, validators and the single hardened-options builder shared with tenant SAML |
| `lib/onetime/sso_provider/request_bound_saml.rb` | `OmniAuth::Strategies::RequestBoundSAML` — the SAML gates |
| `lib/onetime/security/saml_assertion_replay_guard.rb` | Single-use assertion cache |
| `lib/onetime/middleware/http_origin_options.rb` | Cross-site POST callback allowance (Apple, SAML) |

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
| `apps/web/auth/spec/config/hooks/omniauth_spec.rb` | Email normalization, SAML issuer resolution through the wired hooks |
| `spec/unit/onetime/sso_provider/request_bound_saml_spec.rb` | SAML gates against real signed responses (`spec/support/saml/test_idp.rb`) |
| `apps/web/auth/spec/integration/full/tenant_saml_sso_spec.rb` | Tenant SAML sign-in end to end through Rodauth |
| `apps/web/auth/spec/integration/full_saml_platform/platform_saml_sso_spec.rb` | Platform SAML sign-in end to end, including eligible custom-domain fallback (env-configured IdP); own lane `full-saml-platform` |

## Testing

See [OmniAuth Testing Guide](omniauth-testing.md) for local IdP setup and test procedures.

```bash
# Backend
tests/lanes/run unit --only apps/web/auth/spec/unit/omniauth_domain_validation_spec.rb
tests/lanes/run full-sqlite --only apps/web/auth/spec/integration/full/omniauth_csrf_spec.rb

# Frontend
pnpm test src/tests/apps/session/components/SsoButton.spec.ts
```

## See Also

- [OmniAuth Testing Guide](omniauth-testing.md)
- [Switching to Full Auth Mode](switching-to-full-mode.md)
- [rodauth-omniauth](https://github.com/janko/rodauth-omniauth)
- [omniauth-entra-id](https://github.com/pond/omniauth-entra-id)
- [omniauth_openid_connect](https://github.com/omniauth/omniauth_openid_connect)
- [omniauth-saml](https://github.com/omniauth/omniauth-saml) and [ruby-saml](https://github.com/SAML-Toolkits/ruby-saml)
