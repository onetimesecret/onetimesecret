---
id: "051"
status: proposed
title: "ADR-051: The Account Login Is Not the Contact Email"
---

## Status

Proposed

## Date

2026-10-10

## Context

Rodauth authenticates against `accounts.email` (`login_column :email`,
`apps/web/auth/config/base.rb`). The column is `NOT NULL`, carries the only
unique index on the table, and is also the key by which the SQL account is
joined to its Redis `Customer` after creation (`EnsureCustomerForAccount`
looks the Customer up by normalized email, then writes `external_id`).
`Customer.create!` refuses an empty email, and the Customer keeps a global and
an organization-scoped unique email index.

Consequences in the field:

- An identity provider that validates a user but supplies no usable `email`
  claim cannot provision an account (#3478, #3499). The documented position is
  that `upn`, `preferred_username`, a fabricated address, or a relaxed tenant
  allowlist are not acceptable substitutes.
- Mailbox verification, account status, and "is this the same person" are
  three different facts that the current model represents with one column
  and one status value. The 2026-10-10 G3 review
  (`docs/security/audits/security-audit-2026-10-10.md`) registered three
  Medium findings that come from reading the email claim as more than a
  contact address.
- Provisioning writes to SQL and Redis inside one Rodauth transaction whose
  exit semantics (commit on redirect, rollback on exception) leave either an
  account without a Customer or a Customer that owns an address without an
  account. Both states are only repairable by hand.

The design that resolves this is written up in
`docs/specs/sso-email-less-accounts/account-model-design.md`. This record
captures the decision it depends on.

## Decision

1. **Login, contact email and verification are separate columns.**
   `accounts.login` becomes Rodauth's `login_column`: an opaque, server-generated,
   `NOT NULL UNIQUE` value that is never derived from, compared with, or
   displayed as a claim. `accounts.email` becomes a nullable contact address
   (structural CHECK and active-row uniqueness kept for present values; empty
   string forbidden). `email_verified_at`, `email_verified_by` and
   `email_verification_hold` state whether and how control of the current
   address was established. Account status keeps meaning "open or not".
2. **The login value is the Customer's `objid`, reserved in the account
   INSERT.** `external_id` (the Customer `extid`) is a deterministic function
   of it and is written in the same statement. The SQL row therefore reserves
   the Redis identity before anything else exists, and the account–Customer
   join is resolved by `external_id` only. Email is never used to find, link
   or merge a Customer.
3. **External identity ownership is unchanged.** `account_identities` stays
   keyed by `(provider, issuer, uid)` with the existing issuer sentinel and
   refusal rules; Entra keeps the gem's `tid` + `oid` UID. No row is re-keyed
   and no synthetic `{provider}:{uid}` login is created.
4. **Redis and SQL change together.** An absent contact email writes no entry
   in either Customer email index; present addresses are claimed through the
   existing compare-and-set path; conflicts fail closed and are never merged.
5. **Provisioning is checkpointed.** The SQL account and identity commit
   first; the Customer, workspace or tenant membership, and session are
   materialised afterwards from the committed row, idempotently, on every
   login. Every crash boundary has a defined recovery that needs no email.
6. **Mailbox flows address an account only through its contact email** and
   send only to a verified one. An account without a contact email is
   unreachable by password reset, magic link and the other email-keyed
   entry points by construction, and must keep a non-email authenticator.
7. **Policy is not widened by this change.** Tenant allowlists, trusted
   linking, Connect gates and the recipient-delivery restriction stay as they
   are. Email-less creation ships behind a default-off flag on the platform
   route; the tenant case waits for the separate decision tied to
   RISK-2026-10-10-01.

Why this approach: it removes the dependency on a mutable, unverifiable claim
from the one place that must be stable (the login), while keeping every
existing identifier (`objid`, `extid`, identity tuple) and every existing
email-based user flow working for accounts that have an address. Making the
reservation part of the INSERT is what turns cross-store provisioning from
"compensate by hand" into "retry converges".

## Trade-offs

- **We lose**: the simplicity of "one email, one account, one column". Code
  that treated `account[:email]` as the account identity (68 `account[:email]` reads in `apps/web/auth`, eleven of them
  Customer lookups by that address, plus CLI and frontend readers) must be
  audited and moved to `external_id`, and every mailbox-dependent feature needs an
  explicit "no mailbox" outcome.
- **We gain**: accounts that can exist without a mailbox, verification state
  that can be reasoned about separately from account status, a provisioning
  path that is recoverable from the SQL row alone, and a schema in which the
  G3 findings can be remediated without further structural change.
- **Risk**: a three-step expand/backfill/enforce migration with a mixed-version
  window; the rollback boundary moves once the first null-email account
  exists (binary rollback is replaced by flag-off). A Familia fix is needed so
  an empty string can never become a shared index key; until it ships the
  application guards are load-bearing.

## Related

- `docs/specs/sso-email-less-accounts/account-model-design.md` (design, checklist, acceptance evidence)
- `docs/planning/2026-1009-sso-email-less-accounts.md` (Phase 2 proposal)
- `docs/security/audits/security-audit-2026-10-10.md`; tracking issues #4734, #4735, #4736
- ADR-016 (domain ownership axis), ADR-048 (evidence basis for security decisions)
- Rodauth alternative-login guide: https://rodauth.jeremyevans.net/rdoc/files/doc/guides/alternative_login_rdoc.html
- OIDC Core 1.0 §5.7 claim stability: https://openid.net/specs/openid-connect-core-1_0.html#ClaimStability
