# A2 — SSO and local MFA (opt-in second factor after SSO)

- **Severity:** Low–Medium — **revised after industry research** (was High). SSO-treated-as-fully-
  authenticated is the *industry-default* posture, not a defect. Gated on SSO + MFA both enabled.
- **Status:** Proposed fix — **additive/opt-in** (does NOT reverse the default)
- **Affects default config?** No (SSO off by default; and the default SSO behaviour is unchanged)
- **Related:** A1, A4; **#3114** (intentionally introduced the SSO-skips-MFA behaviour); #3499. Finding 01.
- **Primary files:** `apps/web/auth/config/hooks/login.rb:128-133`,
  `apps/web/auth/operations/detect_mfa_requirement.rb:151-156`

## Problem (recap) + research correction

The original finding framed "SSO skips local MFA" (`via_omniauth: true` short-circuits the MFA
requirement in `detect_mfa_requirement.rb:151-156`) as a High-severity bypass. **Industry research
changes that assessment.** The dominant pattern across managed auth providers and frameworks is that
**SSO is treated as fully authenticated by default, and local MFA is not layered on top** — the IdP is
trusted to enforce its own MFA:

- **WorkOS** *explicitly* exempts SSO users from MFA even when "Require MFA" is enabled, and disables
  non-SSO methods for SSO orgs (the IdP handles MFA). [WorkOS AuthKit MFA docs]
- **Clerk** treats SSO as fully authenticated; "Require MFA" is off by default, and for enterprise SSO
  it defers to the IdP's MFA (Azure/Google/Okta). [Clerk enterprise-connections docs]
- The same holds for the other surveyed frameworks: SSO = sufficient auth by default; any post-SSO MFA
  is explicitly configured.

So OTS's current behaviour (added deliberately in **#3114**) is **aligned with industry norms**, and an
existing spec (`apps/web/auth/spec/unit/detect_mfa_requirement_spec.rb`) asserts it. Reversing it *by
default* would (a) diverge from every comparable product, (b) reverse an intentional product decision,
and (c) break that spec. We therefore do **not** make local-MFA-after-SSO the default.

The residual, legitimate concern is narrow: a **high-assurance** operator may want defense-in-depth —
require a local second factor after SSO regardless of the IdP. Today there is no way to opt into that.

## Prescribed resolution (opt-in, default-off)

Add an **optional** policy, defaulting to today's (industry-standard) behaviour:

1. **Default (unchanged):** SSO is fully authenticated; an enrolled local second factor is NOT
   challenged after SSO. Keeps #3114, keeps the existing spec green, matches WorkOS/Clerk.
2. **New opt-in config `omniauth_require_local_mfa?` (default `false`).** When an operator enables it,
   a successful SSO callback for an account with an active second factor (TOTP/WebAuthn) sets the
   existing `awaiting_mfa` partial-auth state and routes through the normal MFA challenge.
3. **Optional IdP step-up credit (refinement):** even with the opt-in on, treat the second factor as
   satisfied when the OIDC token proves the IdP performed MFA — `amr` includes `mfa`/`otp`/`hwk`, or
   `acr` matches a configured high-assurance value — behind explicit per-provider config
   (`trust_idp_mfa` + allowed `acr`). Never infer MFA from the mere presence of SSO.

```ruby
# sketch — default returns today's behaviour unless the operator opts in
def detect_mfa_requirement(account, via_omniauth:)
  if via_omniauth
    return mfa_not_required unless omniauth_require_local_mfa?      # default: industry-standard
    return mfa_satisfied if idp_asserted_mfa?(omniauth_extra)       # optional step-up credit
  end
  require_mfa_if_enrolled(account)
end
```

Keep the decision in `detect_mfa_requirement` so password and SSO share one path; SSO only changes
*which* first factor was used.

## Alternatives considered

- **Reverse the default (require local MFA after SSO):** rejected — contrary to WorkOS/Clerk and the
  surveyed frameworks, reverses intentional #3114 behaviour, and breaks the existing spec. Not
  warranted given the IdP already authenticates (and usually MFAs) the user.
- **Do nothing:** acceptable for most deployments, but leaves no lever for high-assurance operators who
  explicitly distrust IdP-side MFA. The opt-in is cheap and self-contained.

## Test / verification

- **Default (opt-in off):** account with TOTP enrolled logs in via SSO → logged in, NOT challenged
  (existing #3114 spec stays green).
- **Opt-in on:** same account → lands in `awaiting_mfa`, second factor required.
- **Opt-in on + `trust_idp_mfa` + token `amr=["mfa"]`:** second factor satisfied; `amr=["pwd"]` → still
  challenged.
- Account with no second factor → SSO logs in directly (unchanged) in all modes.

## Effort & risk

- **Effort:** Small — a config predicate consulted in `detect_mfa_requirement`, reusing the existing
  `awaiting_mfa` machinery. No default behaviour change, so no migration.
- **Risk:** Very low (default path untouched; the existing spec stays green). The opt-in is new,
  isolated behaviour exercised only when explicitly enabled.
