# A2 — SSO bypasses MFA unconditionally

- **Severity:** High (gated on SSO + MFA both enabled)
- **Status:** Proposed fix
- **Affects default config?** No (SSO off by default)
- **Related:** A1, A4; #3499 (same SSO callback work). Finding 01.
- **Primary files:** `apps/web/auth/config/hooks/login.rb:128-133`,
  `apps/web/auth/operations/detect_mfa_requirement.rb:151-156`

## Problem (recap)

The MFA requirement is short-circuited whenever the login arrives via SSO:

```ruby
# detect_mfa_requirement.rb (≈151-156): via_omniauth: true returns "MFA not required"
# before any per-account policy is consulted.
```

A user who has enrolled TOTP/WebAuthn can therefore authenticate with **only** the federated factor —
SSO silently downgrades a 2-factor account to 1-factor. If A1 is also exploitable, MFA provides no
backstop.

## Root cause

SSO is being treated as "authentication complete" rather than "first factor satisfied." The IdP's own
assurance level (whether *it* performed MFA) is never inspected, and the local MFA enrollment is ignored
for the `via_omniauth` path.

## Prescribed resolution

Treat federation as the **first factor**. After a successful SSO callback, consult the account's local
MFA enrollment and the IdP's asserted authentication strength:

1. **Default:** if the account has any active second factor (TOTP/WebAuthn/recovery), set the
   `awaiting_mfa` partial-auth state after SSO and route through the existing MFA challenge — exactly as
   password login does. Do **not** return early for `via_omniauth`.
2. **IdP step-up credit (optional, explicit):** if the OIDC token asserts MFA was performed — `amr`
   contains `mfa`/`otp`/`hwk`, or `acr` matches a configured high-assurance value — you *may* treat the
   second factor as satisfied. Gate this behind explicit per-provider config
   (`trust_idp_mfa: true` + allowed `acr` values); never infer it from the mere presence of SSO.
3. Make the decision in `detect_mfa_requirement` so password and SSO share one code path: SSO changes
   *which* first factor was used, not *whether* a second factor is required.

```ruby
# sketch
def detect_mfa_requirement(account, via_omniauth:)
  return mfa_satisfied if via_omniauth && idp_asserted_mfa?(omniauth_extra)   # opt-in only
  require_mfa_if_enrolled(account)            # same logic for password and SSO
end
```

## Alternatives considered

- **Keep skipping MFA for SSO** (status quo): rejected — defeats the user's explicit second-factor choice
  and pairs catastrophically with A1.
- **Always force local MFA even when IdP did step-up:** acceptable and safest default; the `amr`/`acr`
  credit is an optional convenience, off by default.

## Test / verification

- Account with TOTP enrolled logs in via SSO → lands in `awaiting_mfa`, second factor required.
- With `trust_idp_mfa` on and token `amr=["mfa"]` → second factor satisfied; with `amr=["pwd"]` →
  still challenged.
- Account with no second factor → SSO logs in directly (unchanged).

## Effort & risk

- **Effort:** Small/Medium — localized to `detect_mfa_requirement` + the login hook. Reuses the existing
  `awaiting_mfa` machinery (already correctly gated, per finding 01 positives).
- **Risk:** Low. Land with A1/A4 as part of the SSO hardening PR before SSO ships.
