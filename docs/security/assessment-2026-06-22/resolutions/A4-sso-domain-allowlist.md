# A4 — SSO domain allowlist enforced only on creation, not on linking

- **Severity:** High (gated on SSO + a configured domain allowlist)
- **Status:** Proposed fix
- **Affects default config?** No
- **Related:** A1 (same hook), #3499. Finding 01.
- **Primary files:** `apps/web/auth/config/hooks/omniauth.rb:133-180` (creation guard),
  fork `rodauth-omniauth/lib/rodauth/features/omniauth.rb:79-87`

## Problem (recap)

`allowed_signup_domains` / SSO domain policy is checked in `before_omniauth_create_account` (the
account-**creation** path) but **not** on the account **lookup/linking** path. An SSO identity whose
email domain is outside the allowlist can still resolve-and-link to an existing account, bypassing the
domain restriction the operator configured.

## Root cause

Domain policy lives in the creation hook only. The linking path (`account_from_omniauth` →
`_account_from_login`) never re-applies it, so the allowlist is not a complete authorization boundary.

## Prescribed resolution

Make the domain policy a single function applied at the **one** place that resolves the SSO email, so
both creation and linking honor it:

1. Centralize the check, e.g. `omniauth_email_domain_allowed?(email)`.
2. Call it inside `resolve_omniauth_email` (the helper #3499 introduces) / `account_from_omniauth` so a
   disallowed domain yields "no account" → blocked, **before** any linking decision.
3. Keep the existing creation-time check (defense-in-depth) but it is no longer the sole gate.
4. Default-deny semantics: when an allowlist is configured and the (verified, Tier-1) email's domain is
   not in it, reject — do not fall through to Tier-2 claims or to linking.

```ruby
auth.account_from_omniauth do
  email = resolve_omniauth_email                       # verified Tier-1 only (A1)
  next nil unless email && omniauth_email_domain_allowed?(email)
  # ... A1 secure-linking logic ...
end
```

## Test / verification

- Allowlist = `corp.com`; SSO login `user@evil.com` matching an existing account → **not linked**,
  blocked.
- Allowlist empty/unset → no domain restriction (unchanged).
- Disallowed domain with only Tier-2 claims → blocked (no link, no create).

## Effort & risk

- **Effort:** Small — move/duplicate one check into the resolution helper.
- **Risk:** Low; bundle with A1 (they edit the same hook). Note this also depends on A1 layer-1 so the
  email used for the domain decision is the verified Tier-1 value, not a spoofable Tier-2 claim.
