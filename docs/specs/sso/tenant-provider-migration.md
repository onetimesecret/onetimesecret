# [DECISION] Tenant SSO provider switch: migrate tenant-bound passwordless accounts, owner-initiated, window-bounded

**Search keywords:** provider switch, switch to SAML, OIDC to SAML, entra_id to oidc, NameID format change, identities rekeyed, identity generation, tenant_sso_link_unavailable after switch, SSO migration window, migrating state, tenant-bound account, passwordless JIT account, H-3, mailbox proof tenant, email-confirmed migration, signup_domain_id provenance, retained identity rows, account_identities (provider, issuer, uid), tenant_issuer, sso_identity_migrated, acknowledge_migration, SsoConfig migration record, account model, org-managed vs person-owned, repair authority, membership replacement, replace member access, tenant-minted cohort, verified domain is not email namespace, accounts.email uniqueness, state-ownership inventory, #4450, #3849, #3840, #3877, #4734, 2026-10-22, 2026-10-23

**Date:** 2026-10-22, revised 2026-10-23 (v2 after independent review, v2.1 second pass, v2.2 third pass, v2.3 account-model review) · **Status:** revised; not yet ticketed · **Scope:** tenant (custom-domain) SSO only; platform surface unchanged

**Revision note:** v1 authorized the bind from "every identity row matches the domain's previous issuer key". That is not provenance (OIDC/Entra issuers are not domain-scoped, `features/omniauth.rb:280-289`) and NameID collisions bypassed the branch entirely. v2 moved authorization to mailbox proof. v2.1 tightened key encoding, completion checks, offer/retry semantics, and wording. v2.2 makes retained source rows an explicit, id-recorded exception in every gate that reads identity rows, and replaces the fixed proof cap with a replenishing limit. v2.3 states the account model and authority rule this decision rests on, and records why three alternatives raised in the account-model review (verified-domain authority, owner-authorized rebind of tenant-minted accounts, membership replacement) are not the path, with membership replacement kept as a deferred route for the cohort this decision cannot reach. Ledger at the end.

---

## Headline

Changing a custom domain's SSO identity namespace (provider type, OIDC issuer, Entra tenant, SAML EntityID, NameID format) rekeys every identity on that domain. The passwordless JIT users that domain's previous IdP created are locked out with `tenant_sso_link_unavailable` and have no self-service way back, by design (H-3). Decision: an org owner making such a change opens an acknowledged, time-boxed **migration window** on the SsoConfig and bumps the domain's **identity generation**. During the window, a tenant callback that misses the exact tuple and locates a passwordless account **that this domain provably minted** is offered the existing **mailbox-proof** linking flow (#3840 Phase 4), today platform-only. Email locates, mailbox control binds, the window plus provenance gates decide when a tenant surface may offer it. The IdP assertion alone never binds anything.

## Context

- H-3 (`hooks/omniauth.rb:237`, restated at `:346-353`): a tenant admin controls their IdP and can assert any email, so an unlinked tenant identity whose email matches an existing account is refused, and the tenant surface is excluded from mailbox-proof linking because the owner "could otherwise trigger link emails to arbitrary platform addresses".
- The population stuck after a switch is narrower than "arbitrary addresses": accounts whose `customer.signup_domain_id` is this domain, whose every identity row is under this domain's previous issuer key, with no local credential, and an active membership authorizing this domain. `backfill_tenant_issuer.rb` already uses these gates (DOMAIN-SCOPE, PROVENANCE, MULTIPLE-CANDIDATES) to tell a tenant-minted row from a platform-minted one under a shared route name. This decision reuses them.
- Why mailbox proof and not the assertion: the new IdP is owner-controlled, so any attribute in the assertion (email, `objectidentifier`, anything) can be fabricated by the owner. A tenant-scoped prior bind proves the account was created through this domain's config, not that the owner controlled the old IdP's directory. Mailbox proof is independent of the **IdP assertion**; it is not necessarily independent of the owner, who may also administer the mailbox. What it does is reuse the account's existing recovery trust boundary, the one magic-link and the platform Phase 4 flow already accept for passwordless accounts. The migration gates narrow **to whom** a tenant surface may send that proof; they do not replace it.
- **Account model.** OTS accounts are person-owned and global (one account, memberships in many organizations); organizations control their tenant's sign-in configuration, JIT creation, and memberships. That hybrid is the common SaaS shape, not the defect. The defect is that until this decision nothing said what repair authority an organization has when its own configuration change kills the only identity its passwordless users have. The rule this decision adopts: **the organization's authority is over who may be offered recovery, never over the bind.** Owner action opens the window; provenance gates (6, 7, 9) narrow the offer to accounts this domain provably minted and still authorizes; mailbox proof, the account's existing recovery boundary, performs the bind. The organization never gains the ability to act as the person.
- **Why not a stronger owner authority.** Three candidates were examined (ledger R15-R17). A DNS-verified custom domain proves control of a hostname (`CustomDomain#ownership_verified`), not of the `example.com` mailbox namespace and not of any account cohort, so it cannot stand in for account authority (#4734 R1 gates where JIT may run, nothing more). An owner-authorized rebind of a "captive" account (minted by this domain, sole membership here, no local credential) without mailbox proof would let the owner bind their own identity to an employee's account with one click and read that employee's secret metadata; provenance proves the account was minted here, not that the owner may act as its holder. Mailbox proof does not make that impossible (R12: the IdP owner usually administers the mailbox too), but it raises the act from a button to interception of a user's mailbox, leaves evidence in the owner's own tenant, and is the boundary magic-link and password reset already accept, so it adds no exposure the account did not already have. Replacing the member with a fresh account and transferring org-scoped access is blocked today by `accounts.email` uniqueness (the collision refusal at `hooks/omniauth.rb:533` and the tenant variant are the visible layer) and by account-owned state (`CustomDomain` and `Receipt` carry a customer id); it is deferred, not rejected (§5).
- Related: `claude/diagnosis/2026-1022-saml-cutover-oidc-accounts-refused-tenant-sso-link-unavailable.md` (trigger), `claude/diagnosis/2026-1009-tenant-sso-link-unavailable-preexisting-account-custom-domain.md`.

## Decision

### 1. Identity-namespace change predicate and identity generation

Define `rekeys_identities?(old_config, new_config)` on the resolved identity key, not on `provider_type` alone. True when any of these change: provider_type; OIDC `issuer`; Entra `tenant_id` (or the `ignore_tid` flag); SAML `idp_entity_id`; effective SAML `name_id_format`. One predicate, used by the API save path, the 409 preview, and tests.

`SsoConfig` gains `identity_generation` (integer, 0 for every existing record). Every rekeying save, and every explicit Start migration (§2), increments it.

**Key encoding.** One encoding for every tenant identity at generation ≥ 1, all provider types:

```
<domain_id> | g<n> | <base_issuer>
```

`domain_id` is the CustomDomain objid (fixed alphabet, never contains `|`), `g<n>` is the generation, `base_issuer` is the remainder: the IdP EntityID for SAML, the resolved issuer (`iss`) for OIDC/Entra. Two fixed-width fields then the remainder: never parsed at runtime (keys are compared byte-wise), and unambiguous by construction because the first two fields have a fixed alphabet. To remove the one edge case, an EntityID or issuer containing `|` is refused at config save (`|` is not a valid URI character; today's code already compares EntityIDs byte-wise without normalizing).

Generation 0 keeps today's keys byte-identical: `<domain_id>|<EntityID>` for tenant SAML, bare issuer for OIDC/Entra. No backfill, no change to `backfill_tenant_issuer.rb`.

Consequences, stated:
- Two domains on the same OIDC issuer share identity rows at generation 0 (intended, `saml.rb` comment: provably the same IdP). From generation 1 the migrated domain's rows are domain-scoped and no longer shared. See §3 for why a shared generation-0 source row is retained rather than deleted, and how later migrations treat it.
- Exact lookup cannot resolve a new-generation subject to an old-generation row: Bob's new NameID `123` at `D|g1|E` is a different tuple from Alice's `D|E`.
- A NameID-format-only change is a full rekey with the full record. No lighter variant.

### 2. Migration record on `CustomDomain::SsoConfig`

A PUT/PATCH where `rekeys_identities?` is true is refused with 409 unless the request carries `acknowledge_migration: true`. The 409 body carries the preview counts from §4. With acknowledgement, the save increments `identity_generation` and writes the migration record:

- `migration_id`, `from_generation`, `to_generation`, `from_provider_type`, `from_issuer_key` (exact string old rows carry)
- `started_at`, `expires_at` (default 30 days, max 90), `acknowledged_by`
- `eligible_count` at start; per-account `migration_outcomes` rows: `(migration_id, account_id, status ∈ pending|completed|ineligible, source_identity_ids, retained_identity_ids, proofs_issued_24h, last_proof_at, completed_at)`. Written at start for every account the preview classified. This is the one-time eligibility record; `completed` is terminal.
- Audit at WARN: `domain_sso_migration_started` (domain, from/to provider_type, generations, counts, expires_at; never issuer values)

**Retained rows across migrations.** `retained_identity_ids` on a `completed` outcome records, by id, the source rows §3 left in place. The set of **retained rows for (D, account)** is the union of `retained_identity_ids` over D's completed outcomes for that account. Every gate below that inspects identity rows (eligibility, preview, gate 7, confirmation, MFA completion) treats a retained row as neither a source row nor a foreign row: it is ignored for the "every row matches the source" test and is never deleted by a later migration. Matching is by row id, never by key shape, so a bare-issuer row that was **not** retained by one of D's migrations (a platform-minted row, for instance) still fails gate 7.

**Start migration** without a config change: same record, same acknowledgement, for IdP-side subject changes OTS cannot observe.

**Ending.** Owner action "End migration window" (confirmation states how many accounts remain `pending`), or automatic at `expires_at`. Audit `domain_sso_migration_ended` (reason `ended|expired`, completed/pending counts). Ending invalidates every outstanding proof token for the migration.

**Second switch.** A rekeying save or Start migration while a record is active is refused. After a window ends with `pending` accounts remaining, the next rekeying save is refused until the owner acknowledges a second count: "N users from the previous switch never migrated and will need individual recovery." Those accounts are not chained to the new source; they go to the operator route (§5). Rollback to the previous config is itself a rekeying save under this rule. This is a product tradeoff, accepted: acknowledgement permits stranding, and stranded users are support load. Accounts that **completed** the previous migration are ordinary candidates for the next one: their current-generation row is the new source, and any retained rows are ignored per the rule above.

Permission: the role that may edit the SsoConfig today. Colonel: read-only view of the record and outcomes, may end a window; no colonel path mints a bind.

### 3. Tenant mailbox-proof offer in `account_from_omniauth`

In the tenant email branch, ahead of the `tenant_sso_link_unavailable` refusal, issue a proof only when every gate passes. Any miss falls through to the existing refusal unchanged.

1. Tenant surface: `session[:validated_omniauth_domain_id]` = D.
2. D has an active migration record (`now < expires_at`).
3. Exact tuple lookup missed; the resolved tuple is at D's current `identity_generation` with a non-sentinel issuer (`refuse_issuerless_on_tenant?` already enforced); the assertion passed D's **current** SsoConfig policy (`allowed_domains`, `restrict_to`, config enabled), already enforced on every tenant callback.
4. `existing` located by normalized email; `fold_stable_email?` passed.
5. `existing` has no challengeable password and no WebAuthn credential.
6. **Provenance:** `customer.signup_domain_id == D.identifier` (set once at signup, never rewritten; blank or other → refuse). Same gate as `backfill_tenant_issuer.rb` GATE 2.
7. **Source rows:** after excluding the retained rows for (D, account) (§2), `existing` has ≥ 1 identity row, every remaining row's `(provider, issuer)` equals `(from_provider, from_issuer_key)`, and those row ids equal `migration_outcomes.source_identity_ids` for this account. Any remaining row elsewhere, zero remaining rows, or a mismatch with the snapshot → refuse.
8. `migration_outcomes` status for `(migration_id, account_id)` is `pending`.
9. Customer resolves, not suspended, active `OrganizationMembership` with `can_access_domain?(D)`.
10. **Issuance limit, replenishing:** `last_proof_at` older than a cooldown (10 minutes proposed, under the 15-minute token TTL so at most one live token at a time) and `proofs_issued_24h` below a rolling 24-hour cap (3 proposed). No total cap for the window: a user who lets three links expire can try again the next day, every day until the window ends. Over the cap or inside the cooldown → fall through to the refusal with the existing `tenant_sso_link_unavailable` code (no distinct code, so a callback cannot probe the limit). Issuing a new token invalidates the previous one for the same `(migration_id, account_id)`. Mail volume from this feature is therefore bounded at the daily cap per account, including when an owner-controlled IdP drives the requests.

On pass: mint the existing `SsoLinkVerification` token (`sso_link_confirm.rb`, 15-minute TTL) to the **on-file** address, payload extended by `migration_id`, `to_generation`, `source_identity_ids`; update `proofs_issued_24h`, set `last_proof_at`. Redirect to the token-less notice as the platform flow does. Audit `tenant_sso_migration_proof_sent`. No login from the callback.

**Semantics:** one **successful** migration per account per migration; proofs may be issued within the replenishing limit for as long as the window is open. A `pending` account that never confirms stays `pending` until the window ends; it is never locked out of further proofs while the window is open. There is no permanent issuance exhaustion from a window-wide cap; retries remain subject to the rolling limit and migration deadline.

**Completion** (`ConfirmSsoLink`, extended). Per-client throttle on the confirm POST already applies. After the existing watermark and email-ownership re-checks, re-run the **full applicable policy**: gates 2, 3 (current config policy, against the assertion data snapshotted in the token), 5, 6, 7 (with the same retained-row exclusion), 8, 9, and `D.identity_generation == to_generation`. Any failure → `:stale`, audited `tenant_sso_migration_stale` with the failing gate, nothing written. On pass, in one transaction with the outcome row locked (`SELECT ... FOR UPDATE` or equivalent compare-and-set on `status = 'pending'`): re-read the source rows under the lock and compare to `source_identity_ids`; insert the destination row; delete or retain source rows per the rule below; write `retained_identity_ids`; set the outcome `completed`. A concurrent completion that loses the lock sees `completed` and returns `:stale`. Never select rows for deletion by issuer match.

**Source-row deletion rule.** Delete captured source rows only when `from_issuer_key` is domain-scoped to D (tenant SAML at any generation; any provider at generation ≥ 1). When `from_issuer_key` is a bare generation-0 OIDC/Entra issuer, leave the rows and record their ids in `retained_identity_ids`: a bare-issuer row may legitimately serve another domain configured on the same IdP, and this migration must not break that user's other domain. The row still works wherever that IdP is configured, which is the status quo; the owner-facing list says so (§4). Retained rows stay retained through every later migration of D (§2).

Audit `tenant_sso_identity_migrated` (domain, account_id, obscured email, from/to provider kind and generation, rows deleted or retained; uids masked).

**MFA:** the existing deferred bind after mailbox proof (#3877, `DeferredSsoBind`) is reused with a migration-specific payload (`migration_id`, `to_generation`, `source_identity_ids`); `.complete` runs the same full revalidation (retained-row exclusion included) and the same locked transaction before binding. Stash write failure → no bind, outcome stays `pending`, user may obtain another proof within the limit (same best-effort contract as today, audited `sso_deferred_bind_stash_failed`). `:conflict` (destination tuple owned by another account) → audit, no bind, outcome unchanged.

### 4. Owner-facing surface

Preview and status use the same classifier as gates 5-9, retained-row exclusion included (gates 3, 4, 10 are callback-time only), so counts are truthful:

- **Eligible for email-confirmed migration** (passwordless, provenance D, all non-retained rows under source key, active membership)
- **Needs individual recovery** with a reason category per account (has local credential: use Connect; identity elsewhere; membership missing; provenance unknown), without exposing other identities or credentials
- During the window: **Completed** / **Still pending**
- A completed account whose previous sign-in was a shared generation-0 OIDC/Entra identity is marked "previous sign-in still valid on other domains using that provider", so the owner does not read completion as revocation.

Acknowledgement text: "Switch sign-in to [provider]. Eligible existing users keep their account if they sign in **and confirm the email we send them** before [date, time zone]. Other users will need individual recovery. No accounts or secrets will be deleted."

The deadline applies to confirmation, not to the request. A proof issued shortly before `expires_at` is `:stale` if opened after it; the notice page states the deadline, and the banner warns the owner in the final 24 hours.

Before activation the dialog links the existing SSO test sign-in (if present for the provider; open item) and states the recovery route for the owner's own account: a password or passkey on the owner account, set before switching. The dialog refuses to proceed if the owner account is itself passwordless with no passkey.

No purge in this feature. Account deletion stays with the account holder (self-service close) and the operator (`Customers::Purge`, Colonel/CLI); the owner's per-org tool remains Members removal.

### 5. Recovery outside the window

- Pending accounts after expiry get today's refusal. Verified accounts: reset password → sign in → Connected identities → Connect (self-service). Unverified JIT accounts get no reset email (`login_request_enumeration.rb:276`), so for them the route is operator-only: Colonel/CLI purge with consent, or a future operator-run migration using the same classifier. The UI says "individual recovery"; the support doc names both routes. "No self-service way back" means no automatic tenant-callback recovery.
- Phase 2 (optional): for `entra_id` → `saml` on the same Entra tenant, an old-subject lookup on the `oid` component of the source rows against the asserted `objectidentifier`, requiring `tenantid` equal to the source `tid`, refusing ambiguous matches. This relaxes gate 4 (email changed in Entra) only; mailbox proof still binds, to the on-file address. The `oid` correspondence is a mapping, not an authorization: the new IdP is owner-controlled, so a matching `objectidentifier` can be fabricated. It may locate; it never binds.
- **Deferred: membership replacement ("Replace member's SSO access").** For the "needs individual recovery" cohort, the alternative to recovering the old account is an owner-authorized, single-use replacement: the replacement user signs in through the current tenant SSO into a **fresh** account, an explicit authorization (not an inferred email match) connects that account to the selected membership, org-scoped access and state transfer, the old account's access to this organization is revoked, and the old account, its other memberships and personal data are untouched. Sessions and API keys do not move; historical audit keeps the original actor. This is the correct shape for accounts the organization has no authority over, and it is not buildable yet: a fresh account with the same contact email cannot exist under today's `accounts.email` uniqueness (the collision refusal is only the visible layer, and the invite path refuses cross-account acceptance), so it depends on the account-model Phase 2 (`login` column, nullable `email`; [email-less-accounts-account-model.md](email-less-accounts-account-model.md), ADR-051). The same Phase 2 also makes this route necessary rather than optional: an email-less account has no mailbox to prove, so for that population membership replacement is the only recovery short of the operator. Tenant email-less JIT is refused today (account-model §6), so no such accounts exist yet on tenant surfaces. It also depends on the state-ownership inventory (open item): `CustomDomain` and `Receipt` are keyed by customer id, so "transfer org-scoped state" is a migration, not a flag flip. Revisit when Phase 2 ships.

## Proportionality

This decision is substantial: an identity generation in the key, a migration record with per-account outcomes, retained-row bookkeeping, ten gates at offer time re-run at confirmation, and an owner UI. The size is driven by the security constraints (R2 alone, the cross-generation NameID collision, requires the generation key regardless of anything else here), not by the size of the demand. The demand so far is one customer, on 2026-10-22, and that customer is not covered: the design is not retroactive and the diagnosis doc routes them to the purge path.

So the design is proportionate to the constraints and unproven against demand. That is a product decision, not a design one, and it is left open here. The cheaper options if the decision is to wait:

- the operator route in §5 (Colonel/CLI purge with consent, or an operator-run migration using the same classifier), which handles stranded cohorts one ticket at a time and is required anyway for accounts the window cannot reach;
- the deferred membership-replacement route in §5, once account-model Phase 2 lands, which also becomes necessary for email-less accounts.

Neither gives an eligible user continuity of the same account; only this decision does. The trigger to build it is a second customer switching providers, or the first customer asking for a switch that the purge route would make expensive for them.

## Rejected alternatives

| Alternative | Why not |
|---|---|
| Bind from the assertion alone when prior rows match the previous issuer key (v1) | Issuer match is not provenance (shared route names, non-domain-scoped OIDC issuers); the new IdP is owner-controlled so no asserted attribute is proof. R1. |
| Enable `*_TRUST_EMAIL_FOR_LINKING` on tenant surfaces | Binds by email alone against any account. H-3. |
| Lazy issuer grace / `backfill-issuer` for SAML | Relabels `sub` rows with a SAML issuer (#4450). |
| Lighter miss-only variant for NameID-format changes | Exact lookup hits cross-generation collisions before any gate runs. R2. Generation in the key is required. |
| `<issuer>|<n>` without domain for OIDC generations | Two domains on one issuer at the same generation would share tuples. R8. |
| Delete every source row on completion | A bare generation-0 OIDC row can serve another domain on the same IdP. R8 follow-on. |
| Recognize retained rows by key shape (bare issuer) in gate 7 | A platform-minted bare-issuer row has the same shape; only an id recorded by one of D's completed migrations proves D retained it. R13. |
| Fixed proof cap per migration | Three expired links exhaust recovery for the rest of a 30-day window; a support-only lockout inside the feature meant to remove one. R14. |
| Keep two providers active in parallel | Connect needs recent local re-auth (#4411); SSO login cannot Connect. |
| Owner-triggered purge, default or secondary | `Customers::Purge` is global account deletion, not removal of one org's SSO association. R5. |
| Colonel-only remap tool | Every switch becomes a ticket; the gates are server-enforced regardless of who flips the switch. A CLI stays for stranded cohorts. |
| Better warnings only | Does not help the locked-out users; owners switch anyway. |
| Treat a DNS-verified custom domain as authority over its users' accounts (Atlassian "managed accounts" analogy) | `ownership_verified` proves control of a hostname, not of the email namespace or of any account cohort; the vendors that do this verify the email domain itself. #4734 R1 uses verification to gate where JIT runs, not who owns accounts. R15. |
| Owner-authorized rebind of a tenant-minted "captive" account (sole membership here, no local credential) without mailbox proof | Provenance proves the account was minted through this domain, not that the owner may act as its holder; the owner could bind their own identity and read the employee's secret metadata with one click. Mailbox proof is not owner-independent (R12) but it costs interception, leaves evidence outside OTS, and is the account's existing recovery boundary. The cohort definition survives as gates 6, 7, 9 narrowing the **offer**; the bind stays with mailbox proof. R16. |
| Membership replacement now (fresh account plus transfer) instead of this decision | Blocked by `accounts.email` uniqueness and account-owned state; needs account-model Phase 2 and the inventory. Deferred for the "needs individual recovery" cohort (§5), not rejected. R17. |

## What this does not cover

- Accounts with a password or passkey: Connect from Connected identities, unchanged.
- Accounts whose provenance is blank or another domain, or with any non-retained identity elsewhere: individual recovery.
- Membership removed: refused until re-invited.
- Email changed in the IdP: refused unless phase 2 applies.
- Not retroactive. Existing domains start at generation 0 with no record; the 2026-10-22 customer proceeds with the purge route in its diagnosis doc.

## Review ledger (independent review, 2026-10-23)

| ID | Finding | Disposition |
|---|---|---|
| R1 | Gate 6 issuer match is not tenant provenance | Accepted. `signup_domain_id` gate (6), source-row snapshot (7); authorization moved to mailbox proof (§3). v1 sentence "adds no capability the owner did not have" withdrawn. |
| R2 | NameID collisions resolve at exact lookup before any migration branch | Accepted. `identity_generation` in the key (§1). Reviewer agreed on the split: not new attacker capability where the owner already controls the IdP; a real cross-namespace confusion during a legitimate change. Baseline exposure filed separately below. |
| R3 | Same-issuer migration can delete the new row and re-migrate | Accepted. One-time `migration_outcomes`, captured `source_identity_ids`, locked atomic completion, deletion never by issuer match (§2, §3). |
| R4 | `DeferredSsoBind` has no migration context | Accepted (payload is account_id/provider/issuer/uid only, `deferred_sso_bind.rb:136`). Migration payload plus full revalidation at completion (§3). |
| R5 | "Start fresh" grants global deletion to owners | Accepted. Removed (§4). |
| R6 | Trigger list incomplete | Accepted. `rekeys_identities?` and explicit Start migration (§1, §2). |
| R7 | Second switch strands the unmigrated cohort | Accepted as an explicit tradeoff: next switch refused until the owner acknowledges the stranded count; stranded users are support load (§2). |
| R8 | `issuer|n` not domain-scoped for OIDC; ambiguous concatenation; gen-0 compatibility | Accepted. Single encoding `<domain_id>|g<n>|<base_issuer>`, `|` refused in EntityID/issuer at save, gen 0 byte-identical (§1). Follow-on: shared gen-0 OIDC source rows retained, not deleted (§3). |
| R9 | Completion omits gate 5 and current config policy; concurrency unspecified | Accepted. Full policy re-run at confirm and after MFA; outcome row locked, source rows re-read under the lock (§3). |
| R10 | "One offer" conflicts with retry; repeated mail possible | Accepted. One successful migration per account; cooldown under the token TTL; new token invalidates the previous; ending the window invalidates all (§2, §3 gate 10). No existing per-account issuance limiter to reuse; the confirm POST throttle (`sso_link_confirm.rb:142-147`) is per client IP only. |
| R11 | "Automatic migration" understates the user action; deadline semantics | Accepted. "Eligible for email-confirmed migration"; deadline is on confirmation; stale-after-expiry stated (§4). |
| R12 | Mailbox proof is independent of the assertion, not of the owner | Accepted; rationale reworded to "the account's existing recovery trust boundary" (Context). |
| R13 | Retained gen-0 row makes a completed account fail gate 7 on the next migration (A→B then B→C) | Accepted. `retained_identity_ids` recorded by id at completion; retained rows excluded from the every-row test in eligibility, preview, gate 7, confirmation, and MFA completion; never deleted by later migrations; matching by id, not key shape (§2, §3, §4). Owner-facing note that a retained previous sign-in still works on other domains (§4). Test added. |
| R14 | Fixed cap of three proofs per migration exhausts recovery for the remaining window | Accepted. Replaced with a replenishing limit: cooldown plus rolling 24-hour cap, no window total (§3 gate 10). |

Account-model review (second thread, 2026-10-23):

| ID | Finding | Disposition |
|---|---|---|
| R15 | The account model "sits between two established models" and the ambiguity is the cost; a verified domain could supply the missing authority | Partly accepted. The hybrid is the industry norm; the missing piece was an explicit authority rule, now stated in Context. Verified-domain authority rejected: hostname control is not email-namespace control and not account authority (Rejected alternatives). |
| R16 | A tenant-minted captive cohort (provenance here, sole membership here, passwordless) could be rebound on owner authority alone, avoiding mailbox proof and the email-uniqueness problem | Rejected: turns owner impersonation of an employee into a one-click action. Mailbox proof does not prevent an owner who also administers the mailbox (R12); it makes the act costly, evidenced, and no worse than the recovery boundary the account already has. The cohort test is already gates 6, 7, 9; it decides the offer, not the bind. Decision unchanged. |
| R17 | Repairing the account is the wrong target; replace the membership with a fresh account and transfer org-scoped state | Accepted as the right shape for the cohort this decision cannot reach; deferred behind account-model Phase 2 (`accounts.email` uniqueness) and the state-ownership inventory (§5, open item). Not a substitute for this decision: the eligible cohort gets continuity of the same account, which replacement cannot give. |
| R18 | Entra `tid`+`oid` present in both OIDC claims and SAML attributes gives a deterministic cross-protocol match | Accepted as a locator for Phase 2 (§5), explicitly not as authorization: the asserting IdP is owner-controlled. |

## Open items

- [ ] Ticket: `rekeys_identities?` predicate; `identity_generation` on SsoConfig; `<domain_id>|g<n>|<base_issuer>` key in `resolve_issuer` for all tenant providers at generation ≥ 1; `|` refused in EntityID/issuer at save; generation 0 byte-identical; backfill untouched
- [ ] Ticket: migration record, `migration_outcomes` (incl. `retained_identity_ids`, `proofs_issued_24h`), 409/acknowledge, Start migration, End window (invalidates tokens), second-switch rule (`put_sso_config.rb` / `patch_sso_config.rb`, serializers, change_logger)
- [ ] Ticket: tenant mailbox-proof offer with gates 1-10 and the retained-row exclusion; replenishing issuance limit; `SsoLinkVerification` payload extension and supersede-on-reissue; `ConfirmSsoLink` full revalidation and locked transaction; deletion/retention rule; `DeferredSsoBind` migration payload; audit events
- [ ] Ticket: owner UI (preview counts with reasons, retained-row note, acknowledgement, migrating banner with final-24h warning, End migration window, pending list) and Colonel read-only view
- [ ] [VULN] candidate, separate from this decision: NameID-format change on an existing SAML domain can resolve a new NameID to an old row today (`saml-policy.md:19` says identities are rekeyed; the key does not include format). Confirm on current baseline before filing.
- [ ] Decide: default and maximum window (30/90 proposed); proof cooldown and rolling daily cap (10 min / 3 per 24 h proposed)
- [ ] Decide: whether the SSO tab already has a test sign-in per provider; if not, whether to require one before activation
- [ ] Phase 2: Entra `oid`/`tenantid` old-subject lookup (locator only; mailbox proof still binds)
- [ ] State-ownership inventory: every model keyed by customer id that an organization would consider its own (first pass: `CustomDomain`, `Receipt`; check API keys, secret metadata, billing, `Organization.created_by` stays immutable audit), classified as account-owned, membership-owned, or org-owned. Input to the deferred membership-replacement route (§5); also tells support what an unrecoverable account strands.
- [ ] Decide, after account-model Phase 2 ships: build membership replacement for the "needs individual recovery" cohort, or keep the operator route
- [ ] Decide (product): build this decision now, or hold it until a second provider-switch request and rely on the operator route meanwhile (Proportionality)
- [ ] Test matrix: each gate failing alone → refusal unchanged; pass → proof to on-file address, no login from callback; confirm → destination row present, source rows deleted or retained per rule with `retained_identity_ids` written, outcome completed, audit present; shared-issuer platform account with blank or other `signup_domain_id` → refused; platform-minted bare-issuer row on a D-provenance account, never retained by D → refused (id match, not shape); two domains on one OIDC issuer, one migrates → other domain still signs in; **A→B completed with a retained gen-0 row, then B→C → eligible, migrates, retained row still present, B row deleted**; cross-generation NameID collision → distinct tuples; same-issuer (NameID-only) migration → new row survives; second proof for a completed account → refused; fourth proof within 24 h → refused with the generic code, allowed after the rolling window; reissue invalidates prior token; concurrent confirms for one account → one completion, one `:stale`; password added, allowed_domains changed, window ended, membership removed, or config changed between proof and confirm, and between confirm and MFA → `:stale`; proof issued before expiry and opened after → `:stale`; A→B→C with pending A users → second switch refused until acknowledged; unverified account → no reset email, operator route documented
- [ ] Docs: `per-domain-sso.md` §"Switching an existing Entra configuration" and §"Identity linking and surface isolation"; `saml-policy.md` NameID paragraph; `saml.rb` tenant_issuer comment (generation encoding); `hooks/omniauth.rb:346-353` comment (platform-only rationale now conditional)
- [x] Repo copy `docs/specs/sso/tenant-provider-migration.md`: synced to v2.3 (2026-10-23)
- [ ] `AGENTS.md` repo-conventions: the issuerless-refusal and surface-isolation invariants are in scope for the PR that adds the tenant offer

## Related

- `claude/diagnosis/2026-1022-saml-cutover-oidc-accounts-refused-tenant-sso-link-unavailable.md`
- `claude/diagnosis/2026-1009-tenant-sso-link-unavailable-preexisting-account-custom-domain.md`
- Repo: `apps/web/auth/config/hooks/omniauth.rb` (`:237`, `:326-353`, `:428-438` issuance), `apps/web/auth/config/features/omniauth.rb` (`resolve_issuer` `:266-290`, `lookup_identity` `:330`), `apps/web/auth/routes/sso_link_confirm.rb`, `apps/web/auth/operations/confirm_sso_link.rb`, `apps/web/auth/operations/deferred_sso_bind.rb`, `apps/web/auth/operations/backfill_tenant_issuer.rb` (gates 0-2), `apps/web/auth/operations/customers/purge.rb`, `lib/onetime/models/sso_link_verification.rb:73` (TTL), `lib/onetime/sso_provider/saml.rb:205`, `lib/onetime/models/customer.rb:272` (`signup_domain_id`), `docs/authentication/per-domain-sso.md`, `docs/authentication/saml-policy.md`, `docs/specs/sso/email-less-accounts-account-model.md` (Phase 2 dependency of the deferred membership-replacement route), `lib/onetime/models/organization_membership.rb` (`provisioning_source`, `domain_scope_id`), `lib/onetime/models/custom_domain.rb:122` (`ownership_verified`)
