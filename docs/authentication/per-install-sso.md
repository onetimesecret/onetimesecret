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
| `SSO_FORM_ACTION_ORIGINS` | No | Space-separated extra origins added to the CSP `form-action` directive. IdP origins are auto-derived — platform providers at boot, tenant (per-domain) SSO issuers per-request — so this override is only for sovereign clouds or split-endpoint OIDC (see [Troubleshooting](#sso-login-blocked-on-chromium-family-browsers-csp-form-action)) |

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

## Routes

Each configured provider registers two routes:

| Method | Path | Description |
|--------|------|-------------|
| POST | `/auth/sso/{provider}` | Initiates SSO flow |
| GET | `/auth/sso/{provider}/callback` | Receives IdP response |

Where `{provider}` is the route name (`oidc`, `entra`, `google`, `github`, or custom).

The callback URL (`https://{host}/auth/sso/{provider}/callback`) is auto-constructed from the request host at runtime. Register this URL with your IdP — no env var needed. For multi-tenant deployments with custom domains, each domain gets its own callback URL automatically.

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
Account lookup by (provider, uid), then by email
    ├─ (provider, uid) already linked → sync session
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

## Behavior

**Account Matching:** By linked identity first — the `(provider, uid)` pair in `account_identities`. If that identity is already linked, the user is signed into its account. If the identity is *not* linked but the IdP email matches an existing account, the default is to **refuse** auto-linking (email may locate an account, but only a demonstrated credential may bind an identity to it). Three paths relax that refusal without weakening the invariant: a password-holding account is offered a **sign-in interstitial** to prove its existing password (on by default — see [Sign-in interstitial](#sign-in-interstitial-password-challenge-linking)); a **passwordless** account is offered **mailbox-proof linking** — a single-use link emailed to its on-file address (on by default, platform surface — see [Mailbox-proof linking](#mailbox-proof-linking-passwordless-accounts)); and an operator can opt a trusted IdP into email auto-linking (see [Identity Linking and the Trusted-IdP Flag](#identity-linking-and-the-trusted-idp-flag)). A signed-in user can also link an identity deliberately, without any email involvement, from [Connected Identities](#connected-identities-authenticated-linking-from-account-settings) in account settings.

**Account Creation:** Automatic for unrecognized emails. Creates Customer record and default workspace.

**Multi-Provider:** One account can have multiple linked identities (e.g., OIDC + Entra). The `account_identities` table stores `(provider, uid)` pairs per account.

**Email Verification:** SSO accounts are auto-verified. The IdP handles verification.

**MFA:** Not enforced for SSO logins. The IdP is responsible for MFA.

## Identity Linking and the Trusted-IdP Flag

### The invariant

An email claim may **locate** an account; only a **demonstrated credential** may **bind** an identity to it. Email is metadata, not an identity join key.

Concretely: an SSO login is identified by the `(provider, uid)` pair recorded in `account_identities`. When that pair is already linked, the user is signed into the linked account. When it is *not* linked, but the IdP-supplied email happens to match an existing account, the default behavior is to **refuse** — because anyone who controls the IdP can mint a token bearing any victim's email address. Auto-linking on email alone would let such a token take over the matching account. The refusal is logged as `omniauth_link_refused_existing_account` (level `warn`) and the user is redirected to `/signin?auth_error=account_exists_link_required` with a flash telling them to sign in with their existing method.

This is the correct default for a multi-tenant platform. It is *not* what a self-hosted single-tenant operator wants when they control both the app and the IdP — for them, email is a trustworthy join key, and the refusal locks legitimate users out. The trusted-IdP flag is the sanctioned, opt-in exception.

### Connected Identities: authenticated linking from account settings

The invariant says a *demonstrated credential* is what binds an identity. The cleanest such credential is one the user has **already** demonstrated: an active, authenticated session. So the primary way to attach an SSO identity to an existing account is not a callback heuristic at all — it is a deliberate action the signed-in user takes from **Security settings → Connected identities** (`/account/settings/security/connections`, `src/apps/workspace/account/ConnectedIdentities.vue`).

This is the surface the other paths point at: the H-3 refusal flash names it, and the interstitial and mailbox-proof flows send `link_expired` / `link_conflict` here rather than re-minting a token.

**The panel** lists the account's linked identities — canonical provider label, the `issuer` (hidden for the `''` sentinel on legacy / OAuth2-only rows), and a **masked** `uid` — with a Remove action behind a confirmation dialog, plus a Connect button for each configured provider **not** already linked. "Already linked" is decided by route name (`provider.route_name` vs the row's `provider`), which is correct on the platform surface where one route maps to one issuer.

```
Signed-in user clicks "Connect {provider}"
    │
    ▼
Form POST /auth/sso/{provider} with connect=1  (submitSsoLogin, src/shared/utils/sso.ts)
    │
    ▼
omniauth_request_validation_phase → write sidecar:<sid>:sso_connect_intent = <account id>
    │
    ▼
IdP round-trip → callback → account_from_omniauth
    │
    ▼
Consume the intent (atomic GETDEL)
    ├─ matches the current session account → bind (provider, issuer, uid) to it, re-affirm session
    ├─ tenant callback on a platform session → refuse (identity_connect_conflict)
    ├─ session account no longer open       → refuse (identity_connect_conflict)
    └─ absent / expired / other account     → fall through to the email branches (never bind)
    │
    ▼
Back to /account/settings/security/connections
```

#### Two signals are required to bind, not one

`logged_in?` alone is **not** connect intent. Tabs share cookies, so an ordinary second-tab or shared-browser SSO *sign-in* arriving on an already-authenticated session would otherwise be routed through the bind path and permanently attach the arriving IdP identity to whoever happens to be signed in. Binding therefore requires **both**:

1. an authenticated session (`session_value`), and
2. an **account-bound connect intent** established at initiation.

The division of labour: OAuth `state`/CSRF proves *"this browser initiated a request"*; the intent nonce proves *"this browser initiated a **connect** for **this account**"*.

#### The connect-intent nonce (#3859)

| Property | Behavior |
|----------|----------|
| Written | `omniauth_request_validation_phase` (`config/hooks/omniauth.rb`), during `POST /auth/sso/:provider`, only when a logged-in caller submits `connect=1` |
| Stored as | `sidecar:<sid>:sso_connect_intent` = the **session account id** (not a bare boolean), short TTL (~5 min — one IdP round-trip) |
| Consumed | Atomic GETDEL in `account_from_omniauth`, before any email-based branch |
| Binds when | The consumed value equals the *current* session account id |
| Abandoned connect | Needs no cleanup — the key expires. Additionally, any **non**-connect SSO initiation deletes a dangling intent, so a later plain `connect=0` callback can never consume one that is still in TTL |
| Failure mode | Fail-closed — a failed write or a miss means no intent, and no intent means no bind |

It is a sidecar key rather than a field in the session blob on purpose. A blob-resident nonce was only ever cleared at the callback, so an abandoned connect (user cancels at the IdP, the IdP errors, the tab closes) left it live for the *next* callback on that session — even a plain sign-in — to consume and bind on, which is exactly the shared-browser bind the nonce exists to prevent. Blob copies written by pre-#3859 code are discarded unconsumed.

#### Email plays no part in the decision

The connect branch is evaluated **first** — ahead of the trusted-provider auto-link and the H-3 refusal — because a proven session credential outranks the email-only heuristics those branches rely on. Within it, the account is loaded **by session id** (`_account_from_session`, which also applies the open-status filter), never by email. The IdP-supplied email appears only in the audit event, obscured.

That ordering is the point: matching a connect to an email-*located* account would be the pre-account-hijacking anti-pattern — an attacker who controls an IdP that emits a victim's email would be routed to the victim's account. Routing by session leaves the victim untouched no matter what the IdP claims.

"Already linked elsewhere" cannot arise on this path: an existing `(provider, issuer, uid)` row routes the gem to `account_from_omniauth_identity` instead, so this hook is only ever reached for a **new** identity.

#### Refusals

| Condition | Outcome | Audit event |
|-----------|---------|-------------|
| Tenant callback (`validated_omniauth_domain_id` set) on a platform session | Redirect `/signin?auth_error=identity_connect_conflict` | `omniauth_identity_connect_refused`, reason `tenant_surface` |
| Session account gone or no longer open (e.g. closed mid-session) | Redirect `/signin?auth_error=identity_connect_conflict` | `omniauth_identity_connect_refused`, reason `session_account_missing` |
| Logged in, but no valid intent (second tab, shared browser, intent for a different account) | **No bind** — falls through to the email branches exactly as an unauthenticated caller would | `omniauth_connect_intent_absent` (level `info`) |
| Bind succeeds | `(provider, issuer, uid)` row written for the session account; session re-affirmed | `omniauth_identity_connected` (level `warn`) |

Refusing rather than falling back matters in the first row: a tenant admin controls their own IdP's assertions, so binding a tenant-issuer identity onto a platform-session account would hand them a login into that account.

#### Managing linked identities (`GET` / `DELETE /auth/identities`)

`apps/web/auth/routes/identities.rb`, mirroring `routes/active_sessions.rb`:

| Endpoint | Purpose | Response |
|----------|---------|----------|
| `GET /auth/identities` | List the current account's identities | `{ identities: [{ id, provider, issuer, uid }] }` — `uid` is masked (`abcd…wxyz`, or `***` when ≤ 8 chars); the row `id` is the delete handle, so the full `sub` is never sent to the client. No `created_at`: migrations 006/008 do not add one. |
| `DELETE /auth/identities/:id` | Remove one identity | `200 { success }`; `404` unknown/not-yours; `409 { error_code: "last_credential" }`; `401` unauthenticated |

**No IDOR by construction.** Every query derives from one dataset pinned to `account_id = rodauth.session_value`, and the dataset is never widened. A cross-account id filters to zero rows and yields `404` — never a delete of someone else's identity. The `:id` segment is an integer matcher, so a non-numeric segment falls through to the router's 404.

**Last-credential guard.** An SSO-only account (no usable password) may not remove its **final** identity — that would lock it out. Accounts that have a password may remove identities freely. The existence check, the guard, and the delete run in **one transaction** with an account-scoped row lock (`for_update.all`), closing a TOCTOU where two concurrent DELETEs for *different* ids of the same SSO-only account could each observe two rows, both pass the guard, and strip every sign-in method. Note the shape: materialize the locked rows and count in Ruby — `identities_ds.for_update.count` emits `SELECT count(*) … FOR UPDATE`, which PostgreSQL rejects. Removals are logged (`SSO identity disconnected`, level `warn`).

**Issuer column.** Binds on this path go through the same `(provider, issuer, uid)` shape as the callback, with `issuer` coerced to the `''` sentinel rather than `NULL` so it matches the issuer-scoped unique index (see migration `008_issuer_scoped_identities.rb`).

#### Platform-only

The panel connects identities on the **platform** surface only. Authenticated linking on a tenant (custom-domain) surface needs org-membership verification before a tenant-issuer identity may be bound to an account, and is a deliberate follow-up (#3849).

### Sign-in interstitial (password-challenge linking)

The refusal is the *right* default, but for one common case it is unnecessarily blunt: a user who already has a **password** account and now signs in through SSO for the first time. That user *can* demonstrate a credential — their existing password — so instead of dead-ending them, the callback offers a **sign-in interstitial** that collects and verifies that password before binding the identity. This keeps the invariant intact: email still only *locates* the account; the existing password is the credential that *binds*.

This path needs no operator configuration. It is on by default and is the platform-surface recovery for a password user's first SSO sign-in (the counterpart to the authenticated [Connected Identities panel](#connected-identities-authenticated-linking-from-account-settings), which serves users who signed in with their password first).

**What happens (unauthenticated callback, existing account, identity not linked, trust flag off):**

1. `account_from_omniauth` looks up the located account's password hash directly (it cannot use `has_password?`, which reads the *session* account and there is no session yet on this path).
2. **Account has a password →** it mints a single-use `Onetime::SsoLinkChallenge` in Redis — a short-lived (5 min) token snapshotting `(provider, resolved_issuer, uid, normalized email, account id)` — logs `omniauth_link_challenge_issued` (level `warn`), and redirects the browser to the SPA interstitial at `/link-sso/{token}`.
3. **Account has no password (SSO-only) →** unchanged H-3 refusal (`omniauth_link_refused_existing_account`, redirect to `/signin?auth_error=account_exists_link_required`). There is no credential to challenge.

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
| 409 | `link_conflict` | the email now resolves to a different account than the one snapshotted at mint |

**Why the token is single-use (security-load-bearing).** `POST /auth/link-sso` **deletes** the challenge up front — before it even checks the password — so a token is worth exactly **one** attempt. This is deliberate: password verification runs through `Auth::Config.valid_login_and_password?`, a Rodauth *internal request* that does **not** go through the login route and therefore does **not** increment lockout counters. Without one-shot consumption, a token minted by an attacker who completed an SSO round-trip asserting a victim's email would be an unbounded (TTL-window) password-guessing oracle with no lockout. One-shot consumption bounds it to a single guess per full IdP round-trip. The 5-minute TTL bounds abandoned challenges. On a wrong password the user must restart the SSO sign-in — a deliberate trade of a small amount of retry convenience for closing the oracle.

**Session establishment reuses Rodauth's own machinery.** On a correct password the handler binds the `(provider, issuer, uid)` row (same shape as `omniauth_identity_insert_hash`) and then calls `rodauth.login('password')` rather than hand-rolling the session. That runs the normal `after_login` path — the Redis session blob via `SyncSession` (the real app auth gate), `active_sessions` registration, and MFA detection — so a password account that has OTP configured still gets the MFA gate, exactly as a direct `/auth/login` would.

**Platform-only.** The interstitial is only ever offered on the platform callback path. The email branches in `account_from_omniauth` are reached solely when `session[:validated_omniauth_domain_id]` is `nil` (tenant callbacks bind by session or refuse earlier), so a tenant callback can never mint a challenge. Authenticated tenant-surface linking is a separate follow-up.

### Mailbox-proof linking (passwordless accounts)

The sign-in interstitial above proves ownership with the account's **existing password**. That leaves one case: a **passwordless** account (SSO-only, or migrated without a local password) whose owner now signs in through a *new* SSO identity. There is no password to challenge — but that account can still prove ownership the same way magic-link (email_auth) does: **control of its on-file mailbox.** So instead of dead-ending at the H-3 refusal, the callback **emails a single-use link to the account's on-file address**, and binding the `(provider, issuer, uid)` identity happens only when the user clicks it and confirms. Mailbox control is the demonstrated credential; the invariant holds.

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

```bash
OIDC_ISSUER=https://your-tenant.auth0.com
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

- **Tenant (per-domain) SSO (per-request):** on a custom domain whose per-domain SSO config is enabled and permitted, the domain's IdP origin (the SSO config's issuer origin for OIDC, `https://login.microsoftonline.com` for Entra ID) is added to `form-action` for that request only — on that domain and nowhere else. No env var is involved; the origin follows the domain's stored SSO config automatically.

No configuration is required for the common case. The boot-time set is exposed as `Onetime.auth_config.sso_form_action_origins`; the per-request widening is `Onetime::Middleware::TenantCspExtras`.

**When to use the override:** Set `SSO_FORM_ACTION_ORIGINS` (space-separated origins) when the auto-derived origin is wrong or incomplete:

- **Sovereign / national clouds (platform Entra)** — e.g. env-configured Entra on `https://login.microsoftonline.us` (US Government) or another regional Microsoft endpoint instead of the global `https://login.microsoftonline.com`.

  This applies to the **platform** (env-configured) provider only. Tenant (per-domain) Entra is commercial-cloud only: the tenant strategy passes no authority option and the per-domain SSO config has no authority field, so a tenant Entra config always redirects to `login.microsoftonline.com` — no override changes that. Do **not** set `SSO_FORM_ACTION_ORIGINS` to a sovereign endpoint for a tenant Entra config: it would widen `form-action` on every page, for every tenant and the canonical host, while the redirect still goes to the commercial cloud — a security regression that fixes nothing. For a sovereign-cloud tenant, configure the domain with provider type `oidc` and the sovereign issuer URL instead; the per-request derivation then admits the right origin automatically.
- **OIDC issuer ≠ authorization endpoint** — when the discovery document's `authorization_endpoint` lives on a different origin than the issuer (`OIDC_ISSUER`, or a tenant SSO config's issuer). The form POSTs to the authorization endpoint's origin, which is what CSP checks.
- **Per-request derivation gaps** — the tenant widening depends on resolving the display domain's stored SSO config at response time. If the domain record is unreachable (datastore blip), the widening is skipped silently — the only symptom is the browser-console CSP error — and the issuers are effectively unknown per-request. `SSO_FORM_ACTION_ORIGINS` remains the manual fallback when such gaps must not block SSO.

```bash
SSO_FORM_ACTION_ORIGINS="https://login.microsoftonline.us https://auth.example.gov"
```

**Interim workaround (un-upgraded installs):** If you cannot yet deploy the fix, set `CSP_ENABLED=false` to drop the CSP header entirely. This unblocks SSO at the cost of losing CSP protection, so treat it as temporary and re-enable CSP after upgrading.

## Security Notes

- PKCE enabled by default (generic OIDC)
- OAuth state parameter provides CSRF protection for the redirect flow
- The IdP email verifies the account for JIT signup, but by default is **not** treated as an identity join key: an SSO identity is not auto-linked to a pre-existing account found only by email (see [Identity Linking and the Trusted-IdP Flag](#identity-linking-and-the-trusted-idp-flag))
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
