# PR: SSO secure account-linking + opt-in MFA (A1 / A4 / A2)

- **Head:** `claude/fix-sso-secure-linking`
- **Base:** `claude/fix-3499-resolve-omniauth-email` (**stacked on PR-1**)
- **Affects default config:** No (SSO off by default). Default *behaviour* is unchanged for A2.

## Summary

Builds on PR-1's `resolve_omniauth_email` to close the SSO account-takeover vector and add an opt-in MFA
policy.

### A1 — no silent merge into a credentialed account (Critical)
`account_from_omniauth` is the first-time-this-identity path (returning users match earlier by
`(provider, uid)`). If the resolved email matches a **pre-existing account that has its own credential**
(a password), we **refuse to silently adopt it** — otherwise an IdP asserting a victim's email would log
straight into the victim's local account. New `account_has_independent_credentials?` (`!get_password_hash.nil?`,
fail-safe). On a hit: clear `@account`, flash, and redirect to `/signin?auth_error=sso_link_required`
("sign in and connect this provider from settings"). Pure-SSO accounts (no password) still link by
verified email.

### A4 — domain allowlist on the linking path
The SSO domain policy (previously only on account creation) is now also enforced on linking via
`Onetime::SignupValidation.valid_signup_email?(email, display_domain:)`.

### A2 — opt-in local MFA after SSO (default OFF; research-aligned)
Per the WorkOS/Clerk research, SSO-as-fully-authenticated is the industry default, so we **keep that
default** (and the #3114 spec stays green). New **opt-in** `require_local_mfa_after_sso` on
`DetectMfaRequirement` (default false). When enabled, SSO is treated as the first factor and an enrolled
local second factor is still required. **Configurable at two levels** (domain wins over install):
- **Install:** `SSO_REQUIRE_LOCAL_MFA` env (surfaced as `full.sso.require_local_mfa` in `auth.defaults.yaml`).
- **Domain:** `CustomDomain::SsoConfig#require_local_mfa` (tri-state; nil = inherit install default).

## Files

`apps/web/auth/config/hooks/omniauth.rb`, `apps/web/auth/config/hooks/login.rb`,
`apps/web/auth/operations/detect_mfa_requirement.rb`, `lib/onetime/models/custom_domain/sso_config.rb`,
`etc/defaults/auth.defaults.yaml`.

## ⚠️ Behaviour notes

- A1 changes first-time SSO behaviour for **email collisions with password accounts**: instead of silent
  login, the user is told to sign in and link from settings. This is the intended security boundary.
- A2 default is unchanged; only operators who opt in (install or per-domain) get a local 2nd factor
  after SSO.

## Test plan

`../test-plans/SSO-3499-A1-A4-A2.md` (30 cases): the A1 takeover regression, domain-on-linking, and the
A2 default-vs-opt-in matrix. The pure-unit `detect_mfa_requirement_spec.rb` confirms the A2 default is
preserved. **Full SSO integration tests require an SSO-capable env (IdP + auth DB) and must run in CI
before merge.**

## Review status

Implemented with API/idiom verification (`get_password_hash`, `SignupValidation`, `auth_private_methods`
`@account` semantics, `auth_class_eval`); fresh review dispatched (static + the runnable MFA unit spec).
Given SSO can't be runtime-exercised here, treat as a reviewed **draft pending SSO-integration
validation**.
