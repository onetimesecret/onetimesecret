# PR: SSO — resolve email with verified-mailbox fallback (#3499 Phase 1)

- **Head:** `claude/fix-3499-resolve-omniauth-email`
- **Base:** `main` (or `develop`)
- **Stacking:** **base of the SSO stack.** Must merge before / together with PR-2
  (`claude/fix-sso-secure-linking`). Do **not** ship alone with SSO enabled (it broadens email
  resolution before PR-2 adds the account-linking guard).
- **Affects default config:** No (SSO off by default).

## Summary

Implements **#3499 Phase 1**: a single `resolve_omniauth_email` helper that resolves the SSO email from
**tier-1 verified mailbox claims only** — `info.email`, falling back to `extra.raw_info["mail"]` when the
IdP omits the `email` claim (EntraID without a mailbox / email optional claim — #3478). Mutable tier-2
identifiers (`upn`/`preferred_username`) are intentionally NOT used (Microsoft warns they're mutable;
using them for linking is a takeover vector — see #3499). Returns nil when no verified email is
available, falling through to the existing `invalid_email` handling.

Wired into account lookup (`account_from_omniauth`), new-account creation (`omniauth_new_account`), and
the `before_omniauth_create_account` validation (now reads the resolved value).

## Files

`apps/web/auth/config/hooks/omniauth.rb` (1 file).

## Test plan

`../test-plans/SSO-3499-A1-A4-A2.md` (resolution cases SSO-U-01..). Note: full SSO integration specs
need an SSO-capable env (IdP + auth DB); resolution logic was unit-validated in isolation across the
tier cases.

## Review status

Self-validated (resolution logic unit-checked; idiom matches `rodauth_overrides.rb`; accessors confirmed
in the rodauth-omniauth `omniauth_base.rb`). A fresh review was dispatched; the SSO integration specs
could not boot in the analysis env — confirm in an SSO-capable CI before merge.
