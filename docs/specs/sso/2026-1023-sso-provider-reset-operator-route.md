# Tenant SSO provider switch: operator reset route (classifier + guarded sweep)

**Date:** 2026-10-23 · **Status:** draft ticket, not filed · **Parent:** [tenant-provider-migration.md](../specs/sso/tenant-provider-migration.md) §5 (Recovery outside the window) and Proportionality · **Trigger:** `claude/diagnosis/2026-1022-saml-cutover-oidc-accounts-refused-tenant-sso-link-unavailable.md`

## Problem statement

When a custom domain's SSO identity namespace changes (provider type, issuer, Entra tenant, SAML EntityID, NameID format), every passwordless JIT account that domain minted is locked out with `tenant_sso_link_unavailable` and cannot self-recover (H-3, by design). The decision doc's migration window is the continuity-preserving fix and is not yet built; its Proportionality section says the operator route is needed regardless, both for stranded cohorts and as the interim path.

Today the operator route is "purge the accounts so the new identity can JIT fresh ones" (purging frees `accounts.email`, which is the actual blocker). Executed one account at a time through Colonel or `ots customers purge`, it has two failure modes:

1. **Wrong-cohort purge.** The only safe candidates are accounts that exist in no context outside the requesting organization. Nothing enforces that. `Customers::Purge` preflight refuses org owners and non-empty workspaces, but a membership in another organization is *removed* (purge.rb:21 "consistent non-owner memberships are removed"), not refused. An operator working a university roster has N chances to strip someone's standing in an unrelated org on a third party's say-so.
2. **Ordering.** Purging before the SsoConfig is switched lets users re-mint accounts under the old key between the two steps; the operator has to remember the order.

Support burden: per-account classification by hand, plus writing the owner a list of who needs what.

## Current state

- `Auth::Operations::Customers::Purge` (purge.rb): single-account admin purge with `PurgePreflight` plan/blockers, `BulkAuditContext` support, operator audit trail. Bulk callers exist: `PurgeInactive` (`ots customers purge-inactive`), `PruneClosedAccounts`.
- `PurgePreflight` (purge_preflight.rb): blocker taxonomy (`migration_in_flight`, owner, non-empty workspace, stale participation, ...). No blocker for "has memberships outside organization X".
- Provenance signals already in the data: `Customer#signup_domain_id` (set once at signup), identity rows `(provider, issuer, uid)` with the tenant SAML key `<domain_id>|<EntityID>` and bare issuer for OIDC/Entra at generation 0, `OrganizationMembership#provisioning_source` and `#domain_scope_id`, `#can_access_domain?`.
- `backfill_tenant_issuer.rb` gates 0-2 (DOMAIN-SCOPE, PROVENANCE, MULTIPLE-CANDIDATES) already distinguish tenant-minted from platform-minted rows under a shared route name.
- The decision doc defines the same cohort as its eligibility test (gates 5-9: no local credential, `signup_domain_id == D`, every identity row under D's source key, active membership authorizing D).
- Operator ops for the non-purgeable cohort exist: `ots customers verify` (`SetVerification`) unblocks password reset for unverified JIT accounts; Connect from Connected identities is the user-side bind.
- No owner-facing view of any of this.

## Proposed shape (for discussion, not prescription)

Three parts, each independently useful:

1. **Classifier** `Auth::Operations::Customers::TenantSsoCohort` (name open): given a domain D and an account, returns one of
   - **A captive**: no password, no WebAuthn; `signup_domain_id == D`; every identity row's `(provider, issuer)` equals D's previous key; memberships: D only
   - **B credentialed**: has a password or WebAuthn (self-service Connect; no operator action)
   - **C global**: anything else, with a reason code (`foreign_membership`, `identity_elsewhere`, `provenance_other`, `provenance_blank`, `platform_minted`)
   plus `email_verified` so the C route (self-service reset vs. operator `verify` first) is visible. Extracted from `backfill_tenant_issuer.rb` gates and the decision doc's gates 5-9 so both consumers share one definition.
2. **Guarded sweep** `Auth::Operations::Customers::SsoProviderReset` modelled on `PurgeInactive`: classifies every member of D, purges **A only** through the existing `Purge` under one `BulkAuditContext`, prints B and C with routes. Refuses to run (not warn) when:
   - any candidate would be purged with a membership outside D: new `PurgePreflight` blocker `foreign_membership`, enabled by the sweep (and available to `ots customers purge --refuse-foreign-membership` for single runs);
   - D's current `SsoConfig` would still mint identities under the key the A rows carry (config not switched yet);
   - the organization's owner account(s) have no local credential (the owner would be locked out of fixing their own config);
   - no `--confirm <A count>` matching the dry run (same pattern as `dlq purge`).
   `--dry-run` is the default and its output is the owner's communication list.
3. **Owner-side prevention** (smallest useful slice of decision doc §4): the SSO tab shows the classifier counts for the current config and a "members should add a password or passkey before you switch" notice. Every account that does so moves to B and needs nobody. Full preview/acknowledgement UI stays with the decision doc.

## Investigation questions

1. **What does `Purge` destroy for a cohort-A customer?** Secrets they created (do active secrets die?), receipts, API keys, anything keyed by `custid` (CustomDomain is; could a member own one?). The owner must be told this in the dry-run output, not discover it.
2. **Previous key for the ordering check.** Derive from the A rows (they all share one `(provider, issuer)`) or require `--from-issuer-key` explicitly? Deriving is friendlier; explicit is harder to misuse when a domain has had two switches.
3. **Shared generation-0 OIDC rows.** A captive account's bare-issuer row would also work on another domain configured on the same Entra tenant, but only if the account had a membership there, which `foreign_membership` already refuses. Confirm there is no other path by which a bare-issuer row serves a second domain without a membership.
4. **Should `foreign_membership` become a default `Purge` blocker** (operator must pass `--remove-foreign-memberships` to get today's behaviour) rather than opt-in? Today's semantics are documented and audited; changing the default is a separate decision.
5. **Owner accounts in cohort A or C.** Refuse the whole sweep, or exclude and report? Refuse: an owner without a credential is the one person who must not be stranded.
6. **Pending invites** (`customer_objid` nil, `invited_email` set) on D: untouched, or re-sent after the switch?
7. **Does the sweep need to run from Colonel as well as the CLI?** The CLI is enough for the operator; Colonel read-only view of the classified roster may be the useful half.
8. **Classifier reuse.** Confirm the decision doc's gates 5-9 and this cohort A are the same predicate except for "memberships: D only", and decide whether the decision doc should adopt that stricter test too (an eligible account with a second membership migrates fine; it just must not be purged).
9. **Interaction with the account-model Phase 2** (nullable email): once email-less accounts exist, "purge frees the email" stops being the mechanism and the C route becomes membership replacement (decision doc §5). Does the classifier need an `email_less` outcome now, or is that Phase 2's problem?

## Out of scope

- The migration window itself (identity generation, migration record, mailbox-proof offer): decision doc.
- Membership replacement / "Replace member's SSO access": deferred behind account-model Phase 2 (decision doc §5).
- Any bind performed on owner or operator authority without mailbox proof: rejected (decision doc R16).
- Changing `Purge` semantics for existing callers (question 4 is a separate decision).
- Platform-surface accounts.

## Acceptance criteria

- One classifier, unit-tested against fixtures for each A/B/C reason, shared by the sweep and (later) the decision doc preview; the `backfill_tenant_issuer.rb` gates either call it or are documented as equivalent.
- `ots customers sso-reset <domain>` (name open) dry run lists every member with cohort, reason code, verification state, and route; live run requires `--confirm <count>` equal to the dry-run A count.
- Live run purges only A; any A candidate with a foreign membership makes the whole run refuse before the first write (`PurgePreflight` blocker `foreign_membership`, covered by a test where one account in a roster of three is a member elsewhere).
- Ordering refusal tested: config unchanged → refused with a message naming the step.
- Owner-credential refusal tested.
- Every purge appears on the operator trail under one bulk receipt with the refused count.
- Dry-run output states what purge destroys per customer (answer to question 1).
- Runbook: `docs/runbooks/sso-provider-switch.md` with the owner-side sequence (members add credentials → owner switches → operator dry run → owner notifies B/C → operator live run) and the C routes (`verify` then reset; Connect).
- Decision doc §5 and Proportionality link here; the "individual recovery" wording in §4/§5 points at the runbook.

## Related

- [tenant-provider-migration.md](../specs/sso/tenant-provider-migration.md)
- [email-less-accounts-account-model.md](../specs/sso/email-less-accounts-account-model.md) (Phase 2 dependency of the replacement route)
- `apps/web/auth/operations/customers/{purge,purge_preflight,purge_inactive,prune_closed_accounts,set_verification}.rb`
- `apps/web/auth/operations/backfill_tenant_issuer.rb`
- `lib/onetime/cli/customers/{purge_command,purge_inactive_command,verify_command}.rb`
- `lib/onetime/models/organization_membership.rb` (`provisioning_source`, `domain_scope_id`, `can_access_domain?`), `lib/onetime/models/customer.rb:272` (`signup_domain_id`)
