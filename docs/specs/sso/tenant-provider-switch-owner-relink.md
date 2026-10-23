# [PROPOSAL] Tenant SSO provider switch: prevention first, then owner-authorized re-link on next sign-in

**Search keywords:** provider switch, switch to SAML, OIDC to SAML, entra_id to saml, NameID format change, tenant_sso_link_unavailable after switch, re-link on next sign-in, relink_pending, owner-authorized rebind, R16, captive account, tenant-minted cohort, own namespace, previous_identity_key, signup_domain_id provenance, rekeys_identities?, 409 acknowledge_migration, credential notice, classifier, cohort A B C, Members tab re-link, H-3, equivalent power, public issuer, Google OIDC, ignore_tid, 2026-10-23

**Date:** 2026-10-23 · **Status:** proposal, not ticketed · **Scope:** tenant (custom-domain) SSO only; platform surface unchanged
**Relation to existing docs:** alternative to [tenant-provider-migration.md](tenant-provider-migration.md) §3 (mailbox-proof offer) for the same cohort; adopts that doc's §1 (generation key) and §2 409 rule; builds on [2026-1023-sso-provider-reset-operator-route.md](2026-1023-sso-provider-reset-operator-route.md) parts 1 and 3 and changes part 2's default from purge to re-link.

---

## Headline

The migration-window design is correct and, by its own Proportionality section, too large for the demand. Its central security choice, mailbox proof over an owner-authorized bind (R16), protects against a power the org owner already had for the accounts in question: a passwordless JIT account minted by the org's own IdP was already reachable by that org's IdP admin. This proposal has three pieces:

1. **Re-link on next sign-in.** A per-member flag, consumed by one branch in `account_from_omniauth` ahead of the H-3 refusal, binding the asserted tuple to the flagged account when the gates pass. Allowed only when the previous identity key is provably the organization's own namespace. Set by the operator from the CLI first (this resolves the active customer and needs no record from the time of the switch), by the owner from the Members tab once the UI exists. Accounts outside the namespace rule go to the operator or to purge.
2. **Classifier and dry run** (operator route parts 1 and 2), fixed for multi-domain organizations. The dry-run output is the support reply and the input to the re-link decision.
3. **Prevention.** `rekeys_identities?`, a 409 with cohort counts on any rekeying save, and a Members/SSO-tab notice telling the owner which members have no password or passkey. This is for the next customer, not the current one.

Build order for the active case: the core of piece 1 (flag, callback branch, CLI) first, with the classifier's checks done by hand in Colonel for four accounts; then piece 2 and the Members-tab UI; then piece 3. The migration window stays specified and held. The eligible cohort gets continuity of the same account under this proposal too, at roughly a tenth of the machinery.

## The active customer (2026-10-22)

The migration window cannot help them: it needs a record written at the moment of the switch, and §"What this does not cover" says so. Re-link can, because its only historical input is the previous key, and that is sitting in the four accounts' identity rows (`entra`, tenant-specific Entra `iss`, `tid+oid`). Procedure, once the core of piece 1 exists:

1. Colonel checks from the diagnosis: each of the four has `has_password: false`, no WebAuthn, exactly one identity row under `(entra, <iss>)`, `signup_domain_id == D`, active membership (re-added 10/20), not an org owner, not suspended.
2. `ots sso relink <domain> <email> --from-key "entra|<iss>"` for each (operator form of the flag; `flagged_by` records the operator and the ticket). The namespace rule classifies the tenant-specific Entra `iss` as `own`.
3. Each user signs in on the custom domain with SAML. The branch binds the SAML tuple to their existing account, deletes nothing (bare Entra issuer is retained per the rule), logs them in. Accounts, secrets, API keys intact.
4. Owner re-sets any roles that were lost when memberships were removed and re-added.

If the build cannot be done inside the customer's tolerance, the diagnosis's Option A (purge, then plain SAML sign-in) remains available today and loses their data; Option B (reset password, then Connect) works only if the accounts are verified, which is still an unchecked item. The customer should be asked which they prefer with the build estimate in hand.

## Context

- A rekeying change (provider type, OIDC issuer, Entra tenant, SAML EntityID, NameID format) gives every user on the domain a new `(provider, issuer, uid)` tuple. Exact lookup misses; the tenant surface refuses an email match (`hooks/omniauth.rb:539-544`, `tenant_sso_link_unavailable`); the JIT accounts have no password, so Connect is closed. See the 2026-10-22 diagnosis.
- Both existing docs purge whole accounts for this cohort because purging frees `accounts.email`. Purging or editing only the `account_identities` rows does nothing: H-3 refuses on the email match whether the account has zero rows or ten, and the new uid is not known until the new IdP asserts it, so a row cannot be rewritten ahead of time. Any recovery that keeps the account is therefore a lazy bind at the next assertion, authorized by someone. The question is only who authorizes and under what gates.
- The migration doc authorizes with mailbox proof and rejects owner authorization (R16) because "the owner could bind their own identity to an employee's account with one click". For the cohort its own gates 6, 7 and 9 define, that is not new power. See the next section.

## Authority argument

**Claim.** For an account that (a) has no local credential, (b) was minted through domain D (`signup_domain_id == D`), (c) has identity rows only under D's previous key, and (d) whose previous key names a directory the organization administers, the organization's administrator could already act as that account's holder before the switch, by signing in as the user through their own IdP. Authorizing a re-link of that account to the organization's new IdP gives the organization nothing it did not have.

**Where the claim fails.** Condition (d). If D's previous issuer was one the organization never administered, the owner could not previously act as the user and a re-link would be new power. Concretely:

| Previous key | Org-administered? | Decidable from the key? |
|---|---|---|
| Tenant SAML `<domain_id>\|<EntityID>` | Yes: the owner configured this EntityID for D | Yes (domain-scoped by construction) |
| Entra with tenant-specific `iss` (`.../{tid}/v2.0`) | Yes: the org's Entra tenant | Yes (`tid` present, `ignore_tid` false) |
| Entra `common` / `ignore_tid` | No: any Entra tenant | Yes, refuse |
| Generic `oidc` to Okta, Keycloak, Zitadel, Authentik | Yes in practice | **No**: indistinguishable from the next row by the string |
| Generic `oidc` to Google, GitHub, another public provider | No | **No** |

So the rule has to be: self-serve re-link is permitted when the previous key is tenant SAML or tenant-specific Entra; refused otherwise. For generic `oidc`, the operator decides (they can look at the issuer), or the account goes to purge. This classification is the one thing between R16 and a safe owner-side version, and it is enforced in code, not in a dialog.

**What mailbox proof adds for the permitted cases.** For the 2026-10-22 customer the on-file mailbox is M365 in the same Entra tenant, so the proof link is readable by the same administrator; the proof moves the evidence from the OTS audit log to the M365 audit log. The departed-employee case (mailbox reassigned to a new hire) is caught by the membership gate, not by mailbox proof, in both designs. R12 in the migration doc already concedes the owner usually administers the mailbox. This proposal takes that concession to its conclusion for the permitted namespaces and keeps mailbox proof available as the window design for the others, should the demand appear.

## Decision

The phases below are numbered by dependency for a cold reader (prevention, classifier, re-link). For the active customer the order of construction is 3-core, 2, 3-UI, 1, as stated in the Headline.

### Phase 1: prevention (no change to keys or binding)

1. `rekeys_identities?(old, new)` as specified in tenant-provider-migration.md §1: provider_type, OIDC `issuer`, Entra `tenant_id` or `ignore_tid`, SAML `idp_entity_id`, effective `name_id_format`. Shared by the save path, the 409 and tests.
2. PUT/PATCH where `rekeys_identities?` is true returns 409 unless `acknowledge_migration: true`. Body: the Phase 2 classifier counts (A/B/C, see below) and the passwordless count. On acknowledge, the save records `previous_identity_key = (provider, issuer)` and `switched_at` on the SsoConfig (single level; a second switch overwrites and is subject to the second-switch rule in Phase 3). Audit `domain_sso_switched` at WARN (domain, from/to provider_type, counts; never issuer values).
3. SSO tab and Members tab notice, always on, independent of any switch: "N members sign in only through SSO and have no password or passkey. If you ever change your identity provider, they will lose access until recovered. Ask them to add one." Every member who does is cohort B and needs nobody.
4. Acknowledgement text: "Switch sign-in to [provider]. N members have no password or passkey and will be unable to sign in until you re-link them from the Members tab or they recover individually. No accounts or secrets will be deleted."

Adopt §1's `identity_generation` and `<domain_id>|g<n>|<base_issuer>` key encoding in the same ticket if the R2 [VULN] candidate (NameID-format change resolving a new NameID to an old row) is confirmed on baseline. It is independent of everything else here. Phase 3 does not depend on it for cross-provider switches; it does for same-issuer NameID-format changes, which would otherwise collide at exact lookup before the re-link branch runs.

### Phase 2: classifier and dry run

As in the operator route, parts 1 and 2, with these changes:

- **Cohort A is organization-scoped, not domain-scoped.** A membership grants `can_access_domain?` on every domain of the organization. Cohort A requires: no password, no WebAuthn; `signup_domain_id == D`; identity rows per Phase 3 gate 7; memberships in D's organization only; **and no other domain of that organization still accepts the account's rows** (another domain on the same bare generation-0 issuer, or any domain whose current config resolves to the account's previous key). If that last test fails the account is C with reason `identity_still_live_elsewhere`; purging or re-linking it would break the user's other domain.
- Add `namespace` to the classifier output: `own` (tenant SAML, tenant-specific Entra), `undecidable` (generic `oidc`), `public` (Entra `common`/`ignore_tid`, or an operator-maintained denylist of public issuers). Phase 3 consumes it.
- Default route for A becomes re-link (Phase 3) where `namespace == own`; purge remains for `undecidable` after operator review and for `public`.
- Dry-run output still states, per account, what purge would destroy (operator route question 1): unviewed secrets they created, API keys, personal workspace, anything keyed by their customer id.

### Phase 3: owner-authorized re-link on next sign-in

**Data.** `OrganizationMembership` gains `relink_pending` (nullable struct or sidecar record): `domain_id`, `from_key = (provider, issuer)` copied from the SsoConfig's `previous_identity_key` at the moment of flagging, `source_identity_ids` snapshotted at flagging, `flagged_by`, `flagged_at`, `expires_at` (default 30 days, open). Cleared on bind, on owner unset, on expiry, on membership removal.

**Operator action (first to ship, retroactive).** `ots sso relink <domain> <email> [--from-key "<provider>|<issuer>"] [--reason ...]`. Without `--from-key` it uses the SsoConfig's `previous_identity_key`; with it, the operator supplies the key for switches made before that field existed (the active customer). The command runs the classifier checks that exist at the time, refuses on any failure with the gate named, sets the flag with `flagged_by = operator:<id>`, and audits `tenant_sso_relink_flagged`. `--dry-run` default, same as the other customer commands. The namespace rule is enforced here too; `--force` does not exist.

**Owner action (UI, second).** Members tab, on a member the classifier reports as A with `namespace == own`: "Re-link on next sign-in". Confirmation: "[name] will be connected to this account the next time they sign in through [current provider] with the address [email]. Until then nothing changes." Permission: the role that may edit the SsoConfig. Audit `tenant_sso_relink_flagged`. The button is absent, with the reason, for B (has a credential: Connect), C (reason category) and for `namespace != own` ("contact support").

**Callback branch** in `account_from_omniauth`, tenant email branch, ahead of the `tenant_sso_link_unavailable` refusal. Issue the bind only when every gate passes; any miss falls through to the existing refusal unchanged, same error code, so the branch is not probeable.

1. Tenant surface: `session[:validated_omniauth_domain_id]` = D.
2. Exact tuple lookup missed; the resolved tuple is under D's current key with a non-sentinel issuer; the assertion passed D's current config policy (`allowed_domains`, `restrict_to`, enabled), already enforced.
3. `existing` located by normalized email; `fold_stable_email?` passed.
4. `existing` has an active `OrganizationMembership` with `can_access_domain?(D)` and `relink_pending` set for D, not expired.
5. `existing` has no challengeable password and no WebAuthn credential.
6. `customer.signup_domain_id == D.identifier`.
7. **Source rows, v1 rule:** `existing` has exactly one identity row, its `(provider, issuer)` equals `relink_pending.from_key`, and its id equals `source_identity_ids`. JIT creates exactly one row, so this covers the whole JIT cohort. Accounts with more rows (an earlier retained bare-issuer row, a platform-era Connect) go to the operator in v1; adopting the migration doc's retained-row bookkeeping (§2, R13) is the v2 relaxation if it is ever needed.
8. `relink_pending.from_key` classifies as `namespace == own` **at bind time** (re-checked; the classification function is pure on the key).
9. Customer resolves, not suspended.
10. Destination tuple is not owned by another account (`:conflict` → audit, no bind, flag unchanged).

On pass: in one transaction with the membership row locked, re-read the source row under the lock, insert the destination row, delete the source row when `from_key` is domain-scoped to D (tenant SAML) or retain it when it is a bare generation-0 OIDC/Entra issuer (it may serve another domain; same rule as the migration doc §3), clear `relink_pending`, audit `tenant_sso_identity_relinked` (domain, account_id, obscured email, from/to provider kind, row deleted or retained, flagged_by; uids masked). Then continue login as a normal exact-tuple hit.

**MFA.** If the account requires a second factor, do not bind before it passes. Reuse `DeferredSsoBind` with a relink payload (`membership_id`, `from_key`, `source_identity_ids`); `.complete` re-runs gates 4 to 10 and the locked transaction. Stash failure → no bind, flag unchanged, audited.

**Second switch.** A rekeying save while any membership of D's organization has `relink_pending` for D is refused until the owner acknowledges "N members flagged for re-link have not signed in yet and will need individual recovery". On acknowledge, those flags are cleared (their `from_key` no longer matches the new `previous_identity_key`) and the accounts become C for the operator. Rollback to the previous provider is a rekeying save under the same rule.

**Expiry.** Default 30 days from flagging, owner can re-flag. Rationale: a standing bind authorization is standing exposure; the cost of re-flagging is one click. Whether to have an expiry at all is an open item.

## Threat review

| Case | Outcome |
|---|---|
| Owner asserts an employee's email from the new IdP to capture their account, previous key `own` | Succeeds only for a flagged, captive account. Owner could already sign in as that user through the previous IdP. No new power; now audited in OTS with `flagged_by`. |
| Same, previous key `public` or `undecidable` | Button absent; gate 8 refuses at bind time even if the flag were set by another path. |
| Owner asserts the email of a platform-minted account that happens to be a member | Gate 6 (`signup_domain_id` blank or other) refuses. |
| Account with a password or passkey | Button absent; gate 5 refuses. Connect is the route. |
| Departed employee, mailbox reassigned to a new hire | Membership removed → gate 4 refuses. Membership kept → the organization still regards the account as that member's; same as leaving the user enabled in the IdP. |
| Account with a second membership elsewhere, or another domain of this org still accepting its rows | Classifier C; button absent; v1 gate 7 refuses accounts with more than one row. |
| Attacker with a stolen owner session | Can flag; still needs the IdP to assert the email. Same blast radius as editing the SsoConfig, which the same session already permits. |
| NameID-format-only change, new NameID equals an old one | Exact lookup hits before this branch. Closed by the §1 generation key, not by this proposal. |
| Compromised new IdP after the flag is set | Can take flagged captive accounts. Could also JIT new ones and, through the previous IdP, already could take these. |

## Not chosen

| Alternative | Why not |
|---|---|
| Owner purges or edits `account_identities` rows directly | Rows alone unlock nothing (H-3 refuses on the email match); the new uid is unknown until asserted. The re-link flag is the only form "modify the rows" can take. |
| Owner purges whole captive accounts | Buys nothing over re-link for recovery and grants deletion of a person's secrets and account (migration doc R5). Purge stays operator-side. |
| Mailbox-proof window (migration doc §2 to §4) | Correct, and held. For `own` namespaces it adds an M365 audit trail at the cost of most of §3. Remains the design for `public`/`undecidable` namespaces if demand appears. |
| Operator-only re-link | Same mechanism with a support ticket per switch. The namespace rule makes the common case safe to self-serve; the operator keeps the undecidable one. |
| Always-on re-link without a flag | Removes the explicit per-account authorization the code comment at `features/omniauth.rb:346-357` requires and turns every config change into silent rebinding. |
| Full retained-row bookkeeping in v1 | Not needed for the JIT cohort (one row). Deferred to v2 by reference to the migration doc. |

## Effect on the existing documents

- tenant-provider-migration.md: R16 disposition should record that the rejection rests on condition (d) above, not on owner impersonation in general; status stays "held" with this proposal as the active path. §1 and the 409 rule are adopted here unchanged.
- 2026-1023-sso-provider-reset-operator-route.md: cohort A becomes organization-scoped with the `identity_still_live_elsewhere` reason; question 3's "no membership → no access" reasoning is withdrawn; default A route becomes re-link where `namespace == own`; the sweep purges only `public`/`undecidable` A accounts after operator review; the ordering refusal and the lockout window between the owner's save and recovery go in the runbook as expected behaviour.

## Open items

- [ ] Confirm on baseline whether tenant JIT marks accounts verified (Colonel check from the 2026-10-22 diagnosis); it decides whether cohort C's self-service reset route exists without `ots customers verify`.
- [ ] Confirm the R2 [VULN] candidate; if real, the §1 generation key ships in Phase 1.
- [ ] Decide: `relink_pending` expiry (30 days proposed, or none).
- [ ] Decide: namespace classification for generic `oidc`: operator-maintained denylist of public issuers plus `undecidable` default, or allowlist of known tenant-specific patterns.
- [ ] Decide: where `relink_pending` lives (membership column vs. sidecar keyed by membership and domain).
- [ ] Ticket Phase 1: predicate, 409 with counts, `previous_identity_key`/`switched_at`, notices, audit.
- [ ] Ticket Phase 2: classifier (`TenantSsoCohort`, org-scoped A, `namespace`), `ots customers sso-cohort <domain>` dry run, operator route sweep narrowed to `public`/`undecidable`.
- [ ] Ticket Phase 3 core (first): `relink_pending`, `ots sso relink` with `--from-key`, callback branch gates 1 to 10, locked transaction and deletion/retention rule, `DeferredSsoBind` relink payload, audit events. Target: the four accounts of the 2026-10-22 customer.
- [ ] Ticket Phase 3 UI (after Phase 2): Members-tab button and confirmation, `previous_identity_key` recorded on save, second-switch refusal, expiry.
- [ ] Customer: build estimate for Phase 3 core against their tolerance; offer purge (Option A) as the immediate alternative with its data loss stated.
- [ ] Test matrix: each gate failing alone → refusal unchanged, same code; all pass → bound, logged in, source row deleted (SAML) or retained (bare OIDC), flag cleared, audit present; `namespace == public` with flag forced → refused at gate 8; two rows → refused (v1); conflict on destination tuple → no bind, flag kept; MFA account → bind only after second factor; password added between flag and sign-in → refused; membership removed → refused; expired flag → refused; second rekeying save with flags pending → 409 until acknowledged, flags cleared; two domains on one Entra tenant, one switches, member of both → classifier C, button absent; stolen-session flag plus foreign email → gate 6 refuses.
- [ ] Docs: `per-domain-sso.md` §"Switching an existing Entra configuration" (re-link procedure, namespace rule), `saml-policy.md` NameID paragraph, `hooks/omniauth.rb:346-353` comment (platform-only rationale now conditional on the namespace rule), runbook `docs/runbooks/sso-provider-switch.md`.

## Related

- [tenant-provider-migration.md](tenant-provider-migration.md) (migration window; held)
- [2026-1023-sso-provider-reset-operator-route.md](2026-1023-sso-provider-reset-operator-route.md) (classifier and sweep)
- `claude/diagnosis/2026-1022-saml-cutover-oidc-accounts-refused-tenant-sso-link-unavailable.md` (trigger)
- `claude/diagnosis/2026-1009-tenant-sso-link-unavailable-preexisting-account-custom-domain.md`
- Repo: `apps/web/auth/config/hooks/omniauth.rb` (`:237`, `:326-353`, `:539-544`), `apps/web/auth/config/features/omniauth.rb` (`resolve_issuer`, `lookup_identity`, `:346-357`), `apps/web/auth/operations/deferred_sso_bind.rb`, `apps/web/auth/operations/backfill_tenant_issuer.rb` (gates 0-2), `apps/web/auth/operations/customers/{purge,purge_preflight}.rb`, `lib/onetime/models/organization_membership.rb` (`can_access_domain?`, `provisioning_source`, `domain_scope_id`), `lib/onetime/models/customer.rb:272` (`signup_domain_id`), `lib/onetime/sso_provider/saml.rb:205` (`tenant_issuer`)
