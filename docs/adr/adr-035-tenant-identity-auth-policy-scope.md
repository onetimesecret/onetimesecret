---
id: 035
status: accepted
decided: 2026-08-11
title: "ADR-035: Tenant Identity and Authentication-Policy Scope"
---

## Context

Split out of [ADR-024](adr-024-custom-domain-auth-override-resolution.md).
[ADR-034](adr-034-restrict-to-enforcement.md) governs *which
methods* work on a request host; this ADR governs *which accounts* may
authenticate on it — a separate axis.

## Decision

An account's authenticatable surface is governed by its owning domain/org
policy, not by the request host it happens to arrive on:

- Canonical-pool accounts are not valid logins on branded custom domains.
- Custom-domain signup, where the owner enables it, produces org-scoped
  accounts — never canonical-pool accounts.
- Account-management operations (`SsoOnlyGating` and similar) are governed
  by the owning org's auth policy, never re-keyed to the current request
  host.

Second-factor completion ceremonies (e.g. `webauthn-auth`, `otp_auth`) are
account-scoped under this same rule: which second factor an account holds is
a property of the account, not a choice offered by the host, so
[ADR-034](adr-034-restrict-to-enforcement.md)'s host-restriction enforcement
does not gate them.

[ADR-034](adr-034-restrict-to-enforcement.md)'s request-host method
enforcement is an interim mitigation on the *method* axis; it does not
restrict which accounts can use those methods. Full account-scoping is the
robust fix and lives in this ADR going forward.

## Consequences

The current shared-pool behavior (any account authenticates on any host with
sign-in enabled) does not yet match this decision and is a known,
long-standing gap — tracked as follow-up implementation work, not an open
architectural question.

## References

- `apps/web/core/controllers/authentication.rb`, `registration.rb`
- `apps/web/auth/config/hooks/omniauth_tenant.rb`
