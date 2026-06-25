# A1 — SSO email-match account takeover (secure account linking)

- **Severity:** Critical (gated on SSO/OmniAuth being enabled; not yet in production)
- **Status:** Proposed fix — **design into issue #3499**, not a standalone patch · **design gap flagged by
  re-verification (2026-06-24) — see callout below; pure-SSO victim path not yet closed as written**
- **Affects default config?** No (SSO is off by default)
- **Related:** #3499 (Support SSO accounts when IdP omits the email claim), #3478, #3482; findings A2, A4
- **Primary files:** `apps/web/auth/config/hooks/omniauth.rb`, `apps/web/auth/config/features/omniauth.rb`,
  fork `rodauth-omniauth/lib/rodauth/features/omniauth.rb`

> **⚠️ Re-verification correction (2026-06-24 blind pass — `RE-VERIFICATION-2026-06-24-independent.md` §4
> "A1 pure-SSO gap", §9 matrix).** The three-layer design below is **sound but incomplete as written** — it
> does not close cross-provider takeover of a **pure-SSO victim**. Severity stays **Critical**.
>
> Two gaps, both source-confirmed:
> 1. **Prerequisite not yet in the tree.** `resolve_omniauth_email` (and `email_claim_verified?`) **do not
>    exist** — `rg resolve_omniauth_email` over `lib/`+`apps/` returns **0 hits** (only docs). Layers 1 and 3
>    presuppose #3499 Phase 1; A1 is genuinely *not* implementable standalone. Land **PR-1 (#3499 Phase 1)
>    first**, then A1 on top (`PR2-sso-secure-linking.md`).
> 2. **Layer-2 guard is too narrow.** It refuses silent linking only when
>    `account_has_other_authenticators?(account)` is **true** (a password hash or a TOTP/WebAuthn factor
>    exists). For a **pure-SSO account** — one with no password and no second factor, linked only to provider
>    A via `(provider, uid)` — that predicate returns **false**, so the guard falls through and the existing
>    account is silently adopted. An attacker who controls a *different* IdP (provider B: a self-service OIDC
>    connection, or any provider that does not prove mailbox ownership) and asserts the victim's verified
>    email therefore takes over the pure-SSO account on the unauthenticated callback. (Both
>    `account_has_other_authenticators?` and `resolve_omniauth_email` are proposed-only: **0 hits** in source.)
>
> **Correction to layer 2.** Do not key the refusal on "has other authenticators." Refuse silent adoption of
> **any** existing account that is **not already linked to the exact `(provider, uid)` currently
> authenticating** — pure-SSO-with-a-different-provider included. The only safe silent path is the returning
> user (same `provider`+`uid`), which `rodauth-omniauth` resolves via `account_identities` *before* this hook
> runs; every other email collision (password account **or** different-provider SSO account) must route to the
> explicit, authenticated, opt-in link flow from Account settings. Concretely, replace the
> `account_has_other_authenticators?` branch with "an account exists for this email **and** it is not the
> identity-keyed returning user → `set_omniauth_error :requires_explicit_link; next nil`." Add a takeover
> regression for the pure-SSO victim (provider A account, provider-B callback asserting the same verified
> email → no login, no link) alongside the existing password-account case in the test plan below.

## Problem (recap)

On the OmniAuth callback, OTS resolves the account by email and links the SSO identity to **any
pre-existing local account** with that email:

```ruby
# apps/web/auth/config/hooks/omniauth.rb:27-30
auth.account_from_omniauth do
  normalized_email = OT::Utils.normalize_email(omniauth_email)
  _account_from_login(normalized_email)        # returns an existing password account
end
auth.omniauth_verify_account? true             # features/omniauth.rb:38-40 — trust the IdP
```

There is **no `email_verified` claim check** anywhere, and the linking is by email alone. An actor who
can make a configured IdP (a tenant SSO connection they influence, a self-service OIDC provider, or any
provider that does not prove mailbox ownership) assert `email = victim@corp.com` is silently linked to
the victim's existing password account and logged in — full account takeover.

## Root cause

Two trust assumptions are baked in:

1. **The email claim is trusted unconditionally** (`omniauth_verify_account? true`, no `email_verified`).
   `rodauth-omniauth` itself states "provider login is required to return the user's email address" and
   uses that email for both creation and lookup — it never asserts the email is *verified by the IdP*.
2. **First-time SSO is allowed to auto-merge into an existing, differently-authenticated account.**
   Returning users are safely keyed by `account_identities (provider, uid)`, but the *first* SSO login
   for an email matching a pre-existing password account silently adopts that account.

#3499 already names this exact vector ("writing an unverified … claim into this column could link an SSO
identity to the wrong account — an account takeover vector") and defines **claim trust tiers**. A1 is the
same root cause seen from the *linking* side: the trust-tier rule must gate **linking**, not only which
claim populates `accounts.email`.

## Prescribed resolution

Fold A1 into #3499's `resolve_omniauth_email` work and add an explicit **secure-linking policy**. Three
layers, defense-in-depth:

### 1. Only a *verified* Tier-1 email may be used for lookup/linking

Extend #3499's `resolve_omniauth_email` so it returns an email **only when it is verified**:

```ruby
# Single source of the linkable email. Encodes trust tier AND verification.
def resolve_omniauth_email
  info = omniauth_params_info            # omniauth.info / omniauth.extra.raw_info
  return nil unless email_claim_verified?(info)   # see below
  e = info['email'] || info.dig('raw_info', 'mail')   # Tier 1 only (per #3499)
  e && OT::Utils.normalize_email(e)
end

# Verification policy, per provider. OIDC exposes email_verified; some providers
# guarantee verification implicitly (document each in a trust policy table).
def email_claim_verified?(info)
  case omniauth_provider.to_s
  when 'oidc', 'google_oauth2', 'entra_id'
    v = info['email_verified']
    v.nil? ? provider_guarantees_verified_email?(omniauth_provider) : !!v
  when 'github'
    # GitHub only returns verified primary emails via the API scope we request
    true
  else
    false
  end
end
```

Tier-2 claims (`upn`, `preferred_username`) are **never** used for the email column or linking — exactly
as #3499 specifies. This closes the "unverified claim → wrong account" path #3499 calls out.

### 2. Do not auto-merge SSO into a pre-existing, differently-authenticated account

This is the core A1 change and the most important for long-term safety. `account_from_omniauth` must
return an existing account **only** when it is safe to adopt it:

```ruby
auth.account_from_omniauth do
  email = resolve_omniauth_email
  next nil unless email                       # no verified email -> new-account path (#3499 Phase 2)

  account = _account_from_login(email)
  next nil unless account

  # Safe ONLY if this account is already linked to THIS (provider, uid),
  # which rodauth-omniauth checks before calling this hook for returning users,
  # OR the account has no password set (pure-SSO account, nothing to take over).
  if account_has_other_authenticators?(account[account_id_column])
    # An existing PASSWORD account. Refuse silent linking; route to explicit,
    # authenticated linking instead of adopting the account.
    set_redirect_error_flash login_required_error_flash
    set_omniauth_error :requires_explicit_link   # -> "An account with this email exists.
                                                 #    Sign in and link SSO from Account settings."
    next nil
  end
  account
end
```

`account_has_other_authenticators?` = "a password hash exists, or any non-SSO authenticator (TOTP,
WebAuthn) is registered." For these accounts, linking must be an **explicit, authenticated, opt-in action
from Account settings** (user is already logged in to the local account, then connects the IdP) — not a
side effect of an unauthenticated callback. Returning pure-SSO users are unaffected (keyed by
`(provider, uid)`).

### 3. Enforce the SSO domain allowlist on the linking path too (closes A4)

The domain policy currently runs only in `before_omniauth_create_account`. Move the check into
`resolve_omniauth_email`/`account_from_omniauth` so **lookup/linking** also respects
`allowed_signup_domains`. See `A4-sso-domain-allowlist.md`.

## Alternatives considered

- **Trust `info.email` but require `email_verified`** (layer 1 only): necessary but **insufficient** — a
  malicious/compromised tenant IdP can set `email_verified: true`. Layer 2 (no silent merge into
  password accounts) is what actually stops takeover, so both are required.
- **Block any email collision entirely:** rejected — hurts the legitimate "I have a password account and
  want to add SSO" case. The explicit authenticated-link flow serves that safely.

## Test / verification

Add to `apps/web/auth/spec/integration/full/`:
1. **Takeover regression:** seed a password account `victim@corp.com`; simulate an OmniAuth callback
   (`provider=oidc`, new `uid`) asserting `email=victim@corp.com` with `email_verified` absent/false →
   assert **no login**, identity **not** linked, redirect to the explicit-link message.
2. **Unverified-but-true tenant claim:** `email_verified: true` from an untrusted tenant + existing
   password account → still no silent merge (layer 2).
3. **Tier-2 only** (`preferred_username` matches an account, no verified email) → no link (keep the
   `invalid_email` expectation noted in `omniauth_missing_email_spec.rb:291-319`).
4. **Happy paths:** returning pure-SSO user by `(provider, uid)` logs in; first-time SSO with verified
   email and *no* pre-existing account creates an account under domain policy.

## Effort & risk

- **Effort:** Medium — concentrated in `hooks/omniauth.rb` + the `resolve_omniauth_email` helper that
  #3499 is already adding. No schema change for layer 1/2 (layer 3 reuses existing domain config).
- **Sequencing:** land **before** SSO ships. Recommend a stacked PR on top of #3499: PR-1 = #3499 Phase 1
  (`resolve_omniauth_email`, Tier-1/verified), PR-2 = A1 layer-2 secure-linking + A4 + A2 (MFA).
- **Risk:** low regression for returning SSO users (identity-keyed path unchanged); the behavior change is
  for first-time email collisions, which is the intended security boundary.
