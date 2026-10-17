---
id: "051"
status: proposed
title: "ADR-051: The Account Login Is Not the Contact Email"
---

## Status

Proposed. The decision below describes the target model, not current
runtime behavior. The [expand migration](../../apps/web/auth/migrations/012_account_login_and_contact_verification.rb)
adds nullable login and verification columns, but email remains required and
is still Rodauth's login column. Email-less account creation remains disabled.

## Date

2026-10-10

## Context

This ADR proposes separating the stable internal account login from the
optional contact email. Here, *login* means the value Rodauth uses internally,
not the email a user types to sign in. Existing email-based sign-in remains
available for accounts with an address.

Rodauth currently uses `accounts.email` as its login column
([configuration](../../apps/web/auth/config/base.rb)). The column is `NOT NULL`
and has a unique index for active accounts where partial indexes are supported
([schema](../../apps/web/auth/migrations/001_initial.rb)). The table also has a
unique `external_id` column. After account creation,
[`EnsureCustomerForAccount`](../../apps/web/auth/operations/ensure_customer_for_account.rb)
finds or creates the Redis `Customer` by normalized email, then writes the
Customer's `extid` to SQL `external_id` to link the records.
[`Customer.create!`](../../lib/onetime/models/customer.rb) refuses an empty
email, and Customer has both global and organization-scoped unique email indexes.

This coupling has three consequences:

- An identity provider (IdP) that authenticates a user but supplies no usable
  `email` claim cannot provision a new account
  ([#3478](https://github.com/onetimesecret/onetimesecret/issues/3478),
  [#3499](https://github.com/onetimesecret/onetimesecret/issues/3499)). The
  [Phase 2 proposal](../planning/2026-1009-sso-email-less-accounts.md) excludes
  `upn`, `preferred_username`, fabricated addresses, and relaxed tenant
  allowlists as substitutes.
- Mailbox control, account status, and identity ownership are different
  facts. The current model does not separate them consistently. The
  [2026-10-10 G3 security review](../security/audits/security-audit-2026-10-10.md)
  examined email-claim authorization, verification, and domain-name comparison.
  The [active risk register](../security/active-risk-register.md) records three
  Medium ratings by operator decision; the audit's own ratings differ.
- SQL and Redis do not share a transaction. Redis provisioning runs inside
  Rodauth's SQL transaction, which can commit on a redirect or roll back on
  an exception without undoing Redis writes. As described in the
  [provisioning design](../specs/sso-email-less-accounts/account-model-design.md),
  this can leave an account without a Customer, or a Customer holding an
  email-index entry without an account. The current protocol has no durable,
  email-independent checkpoint for recovery.

The [account-model design](../specs/sso-email-less-accounts/account-model-design.md)
contains the implementation details, migration sequence, and acceptance
requirements. This ADR records the proposed architectural decision.

## Decision

1. **Separate internal login, contact email, and verification state.**
   `accounts.login` becomes Rodauth's `login_column`: an opaque,
   server-generated, `NOT NULL UNIQUE` value. It is never derived from or
   compared with an IdP claim, and is never shown to the user.
   `accounts.email` becomes a nullable contact address. Structural validation
   and active-account uniqueness remain for present values; empty strings
   are forbidden. `email_verified_at`, `email_verified_by`, and
   `email_verification_hold` record verification state, its source, and any
   reason verification was withheld for the current address. Email changes
   clear that state. Account status continues to gate account access, including
   the existing password-signup verification gate; it is not mailbox evidence.
2. **Reserve the Customer identity in the account INSERT.**
   The login value is the Customer's `objid` (internal object identifier).
   SQL `external_id` stores the Customer's `extid` (external identifier),
   derived deterministically from `objid` and written in the same INSERT.
   The committed SQL row therefore reserves the Redis identity before the
   Customer exists. After backfill and cutover, the account–Customer join uses
   `external_id` only; email is never used to find, link, or merge a Customer
   during login or provisioning recovery.
3. **Preserve external identity ownership.**
   `account_identities` stays keyed by `(provider, issuer, uid)`: the provider,
   validated issuer, and provider user identifier. The empty-string issuer
   sentinel and existing issuerless-provider refusal rules remain. Entra keeps
   the strategy gem's `tid` + `oid` UID. No row is re-keyed and no synthetic
   `{provider}:{uid}` login is created.
4. **Change Redis and SQL together.**
   An absent contact email writes no entry in either Customer email index.
   Present addresses use the existing compare-and-set path, which claims an
   address only when it is unowned or already belongs to the same Customer.
   Conflicts refuse provisioning; they never merge Customers.
5. **Provision in recoverable checkpoints.**
   The SQL account and identity commit first. Customer creation, workspace or
   tenant membership, and session setup follow from the committed row. These
   steps run idempotently on every login, so a retry resumes incomplete
   provisioning without an email lookup. Email-index conflicts are reported
   for reconciliation, not retried as merges.
6. **Use contact email for mailbox-dependent flows.**
   Password reset, magic links, and other recovery or notification flows
   resolve an account through its contact email and send only when that
   address meets the verification policy. Verification messages are the
   necessary exception: they establish control of a new or changed address.
   An account without a contact email cannot use email-keyed entry points
   and must retain a usable non-email authenticator. Adding verification
   columns does not itself establish that an IdP assertion proves mailbox
   control; that policy is tracked separately under
   [#4735](https://github.com/onetimesecret/onetimesecret/issues/4735).
7. **Do not widen access policy.**
   This change does not relax tenant allowlists, trusted-email linking,
   authenticated identity-linking (Connect) gates, or the recipient-email
   delivery restriction. Email-less creation is planned behind a default-off
   flag on the platform/per-install route only. Tenant email-less creation
   remains refused pending the separate security/product decision tied to
   `RISK-2026-10-10-01`. This ADR does not replace or approve the separate G3
   remediations recorded in the [active risk register](../security/active-risk-register.md).

## Rationale

The internal login must be stable even when the contact address changes or is
absent. [OpenID Connect Core 1.0 §5.7](https://openid.net/specs/openid-connect-core-1_0.html#ClaimStability)
states that "the only guaranteed unique identifier for a given End-User is the
combination of the `iss` Claim and the `sub` Claim." Email has no equivalent
stability guarantee. This supports separating contact data from identity; it
does not require changing existing identity keys.

The proposed model preserves `objid`, `extid`, and the external identity tuple.
Email remains the user-facing lookup value for local sign-in and mailbox flows,
subject to each flow's verification requirements. Reserving the Customer
identity in the account INSERT gives later provisioning steps a stable key to
resume after a crash, rather than using an email address to infer ownership.

## Trade-offs

- **Cost:** email can no longer serve as a shortcut for account identity.
  Authentication hooks, CLI commands, and frontend readers must distinguish
  contact data from identifiers. Customer lookups that currently use
  `account[:email]` must move to `external_id`. Every mailbox-dependent feature
  needs an explicit outcome for absent or unverified email. The design records
  the source inventory and feature-by-feature requirements.
- **Benefit:** accounts can exist without a contact email, verification state
  is separate from account status, and interrupted provisioning can resume
  from the committed SQL row. The schema supports separating IdP assertions
  from mailbox evidence; it does not resolve the G3 risks by itself.
- **Migration risk:** expand, backfill, deploy compatible readers/writers,
  enforce constraints, then enable email-less creation. Older binaries are
  compatible only during the expand step. Once a null-email account exists,
  rollback means turning the flag off while retaining a compatible binary,
  not reverting to an email-required binary or schema. The design contains
  the compatibility matrix and rollback limits.
- **Index risk:** a Familia fix is needed to prevent empty strings from
  becoming shared email-index keys. Until it is available, application-level
  blank-email guards and index checks are required for correctness.

## Related

- [Account-model design](../specs/sso-email-less-accounts/account-model-design.md): implementation details, migration sequence, and acceptance requirements.
- [Phase 2 proposal](../planning/2026-1009-sso-email-less-accounts.md): scope and review/release gates.
- [G3 security review](../security/audits/security-audit-2026-10-10.md) and [active risk register](../security/active-risk-register.md): evidence and current risk disposition; tracking issues [#4734](https://github.com/onetimesecret/onetimesecret/issues/4734), [#4735](https://github.com/onetimesecret/onetimesecret/issues/4735), and [#4736](https://github.com/onetimesecret/onetimesecret/issues/4736).
- [ADR-016: Domain Validation State Model](adr-016-domain-validation-state-model.md): domain ownership axis.
- [ADR-048: Evidence Basis for Security Decisions](adr-048-evidence-basis-for-security-decisions.md): evidence requirements.
- [Rodauth alternative-login guide](https://rodauth.jeremyevans.net/rdoc/files/doc/guides/alternative_login_rdoc.html).
- [OpenID Connect Core 1.0 §5.7: Claim Stability and Uniqueness](https://openid.net/specs/openid-connect-core-1_0.html#ClaimStability).
