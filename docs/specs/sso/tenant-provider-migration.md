# [DECISION] Tenant SSO provider switch: migrate tenant-bound passwordless accounts, owner-initiated, window-bounded

**Search keywords:** provider switch, switch to SAML, OIDC to SAML, entra_id to oidc, NameID format change, identities rekeyed, identity generation, tenant_sso_link_unavailable after switch, SSO migration window, migrating state, tenant-bound account, passwordless JIT account, H-3, mailbox proof tenant, email-confirmed migration, signup_domain_id provenance, account_identities (provider, issuer, uid), tenant_issuer, sso_identity_migrated, acknowledge_migration, SsoConfig migration record, #4450, #3849, #3840, #3877, 2026-10-22, 2026-10-23

**Date:** 2026-10-22, revised 2026-10-23 (v2 after independent review, v2.1 after second pass) · **Status:** revised; not yet ticketed · **Scope:** tenant (custom-domain) SSO only; platform surface unchanged

**Revision note:** v1 authorized the bind from "every identity row matches the domain's previous issuer key". That is not provenance (OIDC/Entra issuers are not domain-scoped, `features/omniauth.rb:280-289`) and NameID collisions bypassed the branch entirely. v2 moved authorization to mailbox proof. v2.1 tightens key encoding, completion checks, offer/retry semantics, and wording. Ledger at the end.

---

## Headline

Changing a custom domain's SSO identity namespace (provider type, OIDC issuer, Entra tenant, SAML EntityID, NameID format) rekeys every identity on that domain. The passwordless JIT users that domain's previous IdP created are locked out with `tenant_sso_link_unavailable` and have no self-service way back, by design (H-3). Decision: an org owner making such a change opens an acknowledged, time-boxed **migration window** on the SsoConfig and bumps the domain's **identity generation**. During the window, a tenant callback that misses the exact tuple and locates a passwordless account **that this domain provably minted** is offered the existing **mailbox-proof** linking flow (#3840 Phase 4), today platform-only. Email locates, mailbox control binds, the window plus provenance gates decide when a tenant surface may offer it. The IdP assertion alone never binds anything.

## Context

- H-3 (`hooks/omniauth.rb:237`, restated at `:346-353`): a tenant admin controls their IdP and can assert any email, so an unlinked tenant identity whose email matches an existing account is refused, and the tenant surface is excluded from mailbox-proof linking because the owner "could otherwise trigger link emails to arbitrary platform addresses".
- The population stuck after a switch is narrower than "arbitrary addresses": accounts whose `customer.signup_domain_id` is this domain, whose every identity row is under this domain's previous issuer key, with no local credential, and an active membership authorizing this domain. `backfill_tenant_issuer.rb` already uses these gates (DOMAIN-SCOPE, PROVENANCE, MULTIPLE-CANDIDATES) to tell a tenant-minted row from a platform-minted one under a shared route name. This decision reuses them.
- Why mailbox proof and not the assertion: the new IdP is owner-controlled, so any attribute in the assertion (email, `objectidentifier`, anything) can be fabricated by the owner. A tenant-scoped prior bind proves the account was created through this domain's config, not that the owner controlled the old IdP's directory. Mailbox proof is independent of the **IdP assertion**; it is not necessarily independent of the owner, who may also administer the mailbox. What it does is reuse the account's existing recovery trust boundary, the one magic-link and the platform Phase 4 flow already accept for passwordless accounts. The migration gates narrow **to whom** a tenant surface may send that proof; they do not replace it.
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
- Two domains on the same OIDC issuer share identity rows at generation 0 (intended, `saml.rb` comment: provably the same IdP). From generation 1 the migrated domain's rows are domain-scoped and no longer shared. See §3 completion for why a shared generation-0 source row is left in place rather than deleted.
- Exact lookup cannot resolve a new-generation subject to an old-generation row: Bob's new NameID `123` at `D|g1|E` is a different tuple from Alice's `D|E`.
- A NameID-format-only change is a full rekey with the full record. No lighter variant.

### 2. Migration record on `CustomDomain::SsoConfig`

A PUT/PATCH where `rekeys_identities?` is true is refused with 409 unless the request carries `acknowledge_migration: true`. The 409 body carries the preview counts from §4. With acknowledgement, the save increments `identity_generation` and writes the migration record:

- `migration_id`, `from_generation`, `to_generation`, `from_provider_type`, `from_issuer_key` (exact string old rows carry)
- `started_at`, `expires_at` (default 30 days, max 90), `acknowledged_by`
- `eligible_count` at start; per-account `migration_outcomes` rows: `(migration_id, account_id, status ∈ pending|completed|ineligible, source_identity_ids, proofs_issued, last_proof_at, completed_at)`. Written at start for every account the preview classified. This is the one-time eligibility record; `completed` is terminal.
- Audit at WARN: `domain_sso_migration_started` (domain, from/to provider_type, generations, counts, expires_at; never issuer values)

**Start migration** without a config change: same record, same acknowledgement, for IdP-side subject changes OTS cannot observe.

**Ending.** Owner action "End migration window" (confirmation states how many accounts remain `pending`), or automatic at `expires_at`. Audit `domain_sso_migration_ended` (reason `ended|expired`, completed/pending counts). Ending invalidates every outstanding proof token for the migration.

**Second switch.** A rekeying save or Start migration while a record is active is refused. After a window ends with `pending` accounts remaining, the next rekeying save is refused until the owner acknowledges a second count: "N users from the previous switch never migrated and will need individual recovery." Those accounts are not chained to the new source; they go to the operator route (§5). Rollback to the previous config is itself a rekeying save under this rule. This is a product tradeoff, accepted: acknowledgement permits stranding, and stranded users are support load.

Permission: the role that may edit the SsoConfig today. Colonel: read-only view of the record and outcomes, may end a window; no colonel path mints a bind.

### 3. Tenant mailbox-proof offer in `account_from_omniauth`

In the tenant email branch, ahead of the `tenant_sso_link_unavailable` refusal, issue a proof only when every gate passes. Any miss falls through to the existing refusal unchanged.

1. Tenant surface: `session[:validated_omniauth_domain_id]` = D.
2. D has an active migration record (`now < expires_at`).
3. Exact tuple lookup missed; the resolved tuple is at D's current `identity_generation` with a non-sentinel issuer (`refuse_issuerless_on_tenant?` already enforced); the assertion passed D's **current** SsoConfig policy (`allowed_domains`, `restrict_to`, config enabled), already enforced on every tenant callback.
4. `existing` located by normalized email; `fold_stable_email?` passed.
5. `existing` has no challengeable password and no WebAuthn credential.
6. **Provenance:** `customer.signup_domain_id == D.identifier` (set once at signup, never rewritten; blank or other → refuse). Same gate as `backfill_tenant_issuer.rb` GATE 2.
7. **Source rows:** `existing` has ≥ 1 identity row, every row's `(provider, issuer)` equals `(from_provider, from_issuer_key)`, and those row ids equal `migration_outcomes.source_identity_ids` for this account. Any row elsewhere, zero rows, or a mismatch with the snapshot → refuse.
8. `migration_outcomes` status for `(migration_id, account_id)` is `pending`.
9. Customer resolves, not suspended, active `OrganizationMembership` with `can_access_domain?(D)`.
10. **Issuance throttle:** `proofs_issued` below a per-migration cap (3 proposed) and `last_proof_at` older than a cooldown (10 minutes proposed, under the 15-minute token TTL so at most one live token at a time). Over the cap or inside the cooldown → fall through to the refusal with the existing `tenant_sso_link_unavailable` code (no distinct code, so a callback cannot probe the throttle state). Issuing a new token invalidates the previous one for the same `(migration_id, account_id)`.

On pass: mint the existing `SsoLinkVerification` token (`sso_link_confirm.rb`, 15-minute TTL) to the **on-file** address, payload extended by `migration_id`, `to_generation`, `source_identity_ids`; increment `proofs_issued`, set `last_proof_at`. Redirect to the token-less notice as the platform flow does. Audit `tenant_sso_migration_proof_sent`. No login from the callback.

**Semantics:** one **successful** migration per account per migration; proofs may be issued up to the cap. A `pending` account that never confirms stays `pending` until the window ends.

**Completion** (`ConfirmSsoLink`, extended). Per-client throttle on the confirm POST already applies. After the existing watermark and email-ownership re-checks, re-run the **full applicable policy**: gates 2, 3 (current config policy, against the assertion data snapshotted in the token), 5, 6, 7, 8, 9, and `D.identity_generation == to_generation`. Any failure → `:stale`, audited `tenant_sso_migration_stale` with the failing gate, nothing written. On pass, in one transaction with the outcome row locked (`SELECT ... FOR UPDATE` or equivalent compare-and-set on `status = 'pending'`): re-read the source rows under the lock and compare to `source_identity_ids`; insert the destination row; delete source rows per the rule below; set the outcome `completed`. A concurrent completion that loses the lock sees `completed` and returns `:stale`. Never select rows for deletion by issuer match.

**Source-row deletion rule.** Delete captured source rows only when `from_issuer_key` is domain-scoped to D (tenant SAML at any generation; any provider at generation ≥ 1). When `from_issuer_key` is a bare generation-0 OIDC/Entra issuer, leave the rows: a bare-issuer row may legitimately serve another domain configured on the same IdP, and this migration must not break that user's other domain. The row still only works where that IdP is configured, which is the status quo. Record `source_rows_retained: true` on the outcome and in the audit event.

Audit `tenant_sso_identity_migrated` (domain, account_id, obscured email, from/to provider kind and generation, rows deleted or retained; uids masked).

**MFA:** the existing deferred bind after mailbox proof (#3877, `DeferredSsoBind`) is reused with a migration-specific payload (`migration_id`, `to_generation`, `source_identity_ids`); `.complete` runs the same full revalidation and the same locked transaction before binding. Stash write failure → no bind, outcome stays `pending`, user may obtain another proof within the throttle (same best-effort contract as today, audited `sso_deferred_bind_stash_failed`). `:conflict` (destination tuple owned by another account) → audit, no bind, outcome unchanged.

### 4. Owner-facing surface

Preview and status use the same classifier as gates 5-9 (gates 3, 4, 10 are callback-time only), so counts are truthful:

- **Eligible for email-confirmed migration** (passwordless, provenance D, all rows under source key, active membership)
- **Needs individual recovery** with a reason category per account (has local credential: use Connect; identity elsewhere; membership missing; provenance unknown), without exposing other identities or credentials
- During the window: **Completed** / **Still pending**

Acknowledgement text: "Switch sign-in to [provider]. Eligible existing users keep their account if they sign in **and confirm the email we send them** before [date, time zone]. Other users will need individual recovery. No accounts or secrets will be deleted."

The deadline applies to confirmation, not to the request. A proof issued shortly before `expires_at` is `:stale` if opened after it; the notice page states the deadline, and the banner warns the owner in the final 24 hours.

Before activation the dialog links the existing SSO test sign-in (if present for the provider; open item) and states the recovery route for the owner's own account: a password or passkey on the owner account, set before switching. The dialog refuses to proceed if the owner account is itself passwordless with no passkey.

No purge in this feature. Account deletion stays with the account holder (self-service close) and the operator (`Customers::Purge`, Colonel/CLI); the owner's per-org tool remains Members removal.

### 5. Recovery outside the window

- Pending accounts after expiry get today's refusal. Verified accounts: reset password → sign in → Connected identities → Connect (self-service). Unverified JIT accounts get no reset email (`login_request_enumeration.rb:276`), so for them the route is operator-only: Colonel/CLI purge with consent, or a future operator-run migration using the same classifier. The UI says "individual recovery"; the support doc names both routes. "No self-service way back" means no automatic tenant-callback recovery.
- Phase 2 (optional): for `entra_id` → `saml` on the same Entra tenant, an old-subject lookup on the `oid` component of the source rows against the asserted `objectidentifier`, requiring `tenantid` equal to the source `tid`, refusing ambiguous matches. This relaxes gate 4 (email changed in Entra) only; mailbox proof still binds, to the on-file address.

## Rejected alternatives

| Alternative | Why not |
|---|---|
| Bind from the assertion alone when prior rows match the previous issuer key (v1) | Issuer match is not provenance (shared route names, non-domain-scoped OIDC issuers); the new IdP is owner-controlled so no asserted attribute is proof. R1. |
| Enable `*_TRUST_EMAIL_FOR_LINKING` on tenant surfaces | Binds by email alone against any account. H-3. |
| Lazy issuer grace / `backfill-issuer` for SAML | Relabels `sub` rows with a SAML issuer (#4450). |
| Lighter miss-only variant for NameID-format changes | Exact lookup hits cross-generation collisions before any gate runs. R2. Generation in the key is required. |
| `<issuer>|<n>` without domain for OIDC generations | Two domains on one issuer at the same generation would share tuples. R8. |
| Delete every source row on completion | A bare generation-0 OIDC row can serve another domain on the same IdP. R8 follow-on. |
| Keep two providers active in parallel | Connect needs recent local re-auth (#4411); SSO login cannot Connect. |
| Owner-triggered purge, default or secondary | `Customers::Purge` is global account deletion, not removal of one org's SSO association. R5. |
| Colonel-only remap tool | Every switch becomes a ticket; the gates are server-enforced regardless of who flips the switch. A CLI stays for stranded cohorts. |
| Better warnings only | Does not help the locked-out users; owners switch anyway. |

## What this does not cover

- Accounts with a password or passkey: Connect from Connected identities, unchanged.
- Accounts whose provenance is blank or another domain, or with any identity elsewhere: individual recovery.
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
| R10 | "One offer" conflicts with retry; repeated mail possible | Accepted. One successful migration per account; issuance cap and cooldown under the token TTL; new token invalidates the previous; ending the window invalidates all (§2, §3 gate 10). No existing per-account issuance limiter to reuse; the confirm POST throttle (`sso_link_confirm.rb:142-147`) is per client IP only. |
| R11 | "Automatic migration" understates the user action; deadline semantics | Accepted. "Eligible for email-confirmed migration"; deadline is on confirmation; stale-after-expiry stated (§4). |
| R12 | Mailbox proof is independent of the assertion, not of the owner | Accepted; rationale reworded to "the account's existing recovery trust boundary" (Context). |

## Open items

- [ ] Ticket: `rekeys_identities?` predicate; `identity_generation` on SsoConfig; `<domain_id>|g<n>|<base_issuer>` key in `resolve_issuer` for all tenant providers at generation ≥ 1; `|` refused in EntityID/issuer at save; generation 0 byte-identical; backfill untouched
- [ ] Ticket: migration record, `migration_outcomes`, 409/acknowledge, Start migration, End window (invalidates tokens), second-switch rule (`put_sso_config.rb` / `patch_sso_config.rb`, serializers, change_logger)
- [ ] Ticket: tenant mailbox-proof offer with gates 1-10; issuance cap/cooldown; `SsoLinkVerification` payload extension and supersede-on-reissue; `ConfirmSsoLink` full revalidation and locked transaction; deletion rule; `DeferredSsoBind` migration payload; audit events
- [ ] Ticket: owner UI (preview counts with reasons, acknowledgement, migrating banner with final-24h warning, End migration window, pending list) and Colonel read-only view
- [ ] [VULN] candidate, separate from this decision: NameID-format change on an existing SAML domain can resolve a new NameID to an old row today (`saml-policy.md:19` says identities are rekeyed; the key does not include format). Confirm on current baseline before filing.
- [ ] Decide: default and maximum window (30/90 proposed); issuance cap and cooldown (3 / 10 min proposed)
- [ ] Decide: whether the SSO tab already has a test sign-in per provider; if not, whether to require one before activation
- [ ] Phase 2: Entra `oid`/`tenantid` old-subject lookup
- [ ] Test matrix: each gate failing alone → refusal unchanged; pass → proof to on-file address, no login from callback; confirm → destination row present, source rows deleted or retained per rule, outcome completed, audit present; shared-issuer platform account with blank or other `signup_domain_id` → refused; two domains on one OIDC issuer, one migrates → other domain still signs in; cross-generation NameID collision → distinct tuples; same-issuer (NameID-only) migration → new row survives; second proof for a completed account → refused; fourth proof within a window → refused with the generic code; reissue invalidates prior token; concurrent confirms for one account → one completion, one `:stale`; password added, allowed_domains changed, window ended, membership removed, or config changed between proof and confirm, and between confirm and MFA → `:stale`; proof issued before expiry and opened after → `:stale`; A→B→C with pending A users → second switch refused until acknowledged; unverified account → no reset email, operator route documented
- [ ] Docs: `per-domain-sso.md` §"Switching an existing Entra configuration" and §"Identity linking and surface isolation"; `saml-policy.md` NameID paragraph; `saml.rb` tenant_issuer comment (generation encoding); `hooks/omniauth.rb:346-353` comment (platform-only rationale now conditional)
- [x] Repo copy `docs/specs/sso/tenant-provider-migration.md`: synced to v2.1 (2026-10-23)
- [ ] `AGENTS.md` repo-conventions: the issuerless-refusal and surface-isolation invariants are in scope for the PR that adds the tenant offer

## Related

- `claude/diagnosis/2026-1022-saml-cutover-oidc-accounts-refused-tenant-sso-link-unavailable.md`
- `claude/diagnosis/2026-1009-tenant-sso-link-unavailable-preexisting-account-custom-domain.md`
- Repo: `apps/web/auth/config/hooks/omniauth.rb` (`:237`, `:326-353`, `:428-438` issuance), `apps/web/auth/config/features/omniauth.rb` (`resolve_issuer` `:266-290`, `lookup_identity` `:330`), `apps/web/auth/routes/sso_link_confirm.rb`, `apps/web/auth/operations/confirm_sso_link.rb`, `apps/web/auth/operations/deferred_sso_bind.rb`, `apps/web/auth/operations/backfill_tenant_issuer.rb` (gates 0-2), `apps/web/auth/operations/customers/purge.rb`, `lib/onetime/models/sso_link_verification.rb:73` (TTL), `lib/onetime/sso_provider/saml.rb:205`, `lib/onetime/models/customer.rb:272` (`signup_domain_id`), `docs/authentication/per-domain-sso.md`, `docs/authentication/saml-policy.md`
