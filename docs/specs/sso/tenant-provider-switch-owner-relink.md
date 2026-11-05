# [PROPOSAL] Tenant SSO provider switch: prevention first, then owner-authorized re-link on next sign-in

**Search keywords:** provider switch, switch to SAML, OIDC to SAML, entra_id to saml, NameID format change, tenant_sso_link_unavailable after switch, re-link on next sign-in, relink_pending, owner-authorized rebind, R16, captive account, tenant-minted cohort, own namespace, previous_identity_key, signup_domain_id provenance, rekeys_identities?, 409 acknowledge_migration, credential notice, classifier, cohort A B C, Members tab re-link, H-3, equivalent power, public issuer, Google OIDC, ignore_tid, 2026-10-23

**Date:** 2026-10-23 · **Status:** proposal, not ticketed · **Scope:** tenant (custom-domain) SSO only; platform surface unchanged
**Relation to existing docs:** alternative to [tenant-provider-migration.md](tenant-provider-migration.md) §3 (mailbox-proof offer) for the same cohort; adopts that doc's §1 (generation key) and §2 409 rule; builds on [2026-1023-sso-provider-reset-operator-route.md](2026-1023-sso-provider-reset-operator-route.md) parts 1 and 3 and changes part 2's default from purge to re-link.

---

## Headline

The migration-window design is correct and, by its own Proportionality section, too large for the demand. Its central security choice, mailbox proof over an owner-authorized bind (R16), can be relaxed only where the organization's historical authority over the account's previous identity namespace is established independently of a shared issuer string. A tenant-specific Entra issuer alone does not establish that authority. This proposal has three pieces:

1. **Re-link on next sign-in.** A per-member flag, consumed by one branch in `account_from_omniauth` ahead of the H-3 refusal, binding the asserted tuple to the flagged account when the gates pass. Allowed only when the previous identity key is provably the organization's own namespace. Set by the operator from the CLI first (potentially applicable to the active customer without a switch-time record, subject to independent historical-authority evidence), by the owner from the Members tab once the UI exists. Accounts outside the namespace rule require mailbox/local credential proof or operator investigation; unresolved authority fails closed.
2. **Classifier and dry run** (operator route parts 1 and 2), fixed for multi-domain organizations. The dry-run output is the support reply and the input to the re-link decision.
3. **Prevention.** `rekeys_identities?`, a 409 with cohort counts on any rekeying save, and a Members/SSO-tab notice telling the owner which members have no password or passkey. This is for the next customer, not the current one.

Build order for the active case: the core of piece 1 (flag, callback branch, CLI) first, with the complete classifier checks and historical-authority investigation done for four accounts; then piece 2 and the Members-tab UI; then piece 3. The migration window stays specified and held. The eligible cohort gets continuity of the same account under this proposal too, at roughly a tenth of the machinery.

## The active customer (2026-10-22)

The migration window cannot help them: it needs a record written at the moment of the switch, and §"What this does not cover" says so. The four accounts' identity rows contain the previous key (`entra`, tenant-specific Entra `iss`, `tid+oid`), but not proof of the organization's historical administrative authority over that directory. Re-link is conditional on independently establishing that authority and the complete cohort A checks. Proposed procedure, once the core of piece 1 exists:

1. Colonel checks from the diagnosis: each of the four has `has_password: false`, no WebAuthn, exactly one identity row under `(entra, <iss>)`, `signup_domain_id == D`, active membership (re-added 10/20), not an org owner, not suspended.
2. Review `ots sso relink <domain> <email> --from-key "entra|<iss>"` for each (proposed dry run). Tenant-specific Entra defaults to `undecidable`; without independent historical-authority evidence, refuse and route to mailbox/local credential proof or operator investigation. Only after that evidence and all gates pass, repeat with `--confirm` to set the flag; `flagged_by` records the operator and the ticket. Neither command is shipped.
3. Each user signs in on the custom domain with SAML. The branch binds the SAML tuple to their existing account, deletes nothing (bare Entra issuer is retained per the rule), logs them in. Accounts, secrets, API keys intact.
4. Owner re-sets any roles that were lost when memberships were removed and re-added.

If the build or historical-authority verification cannot be completed inside the customer's tolerance, the diagnosis's Option A (purge, then plain SAML sign-in) remains available today, subject to purge preflight, and removes account/workspace data and access, not TTL-bound Secret/Receipt records; Option B (reset password, then Connect) works only if the accounts are verified, which is still an unchecked item. The customer should be asked which they prefer with the build estimate in hand.

## Context

- A rekeying change (provider type, OIDC issuer, Entra tenant, SAML EntityID, NameID format) gives every user on the domain a new `(provider, issuer, uid)` tuple. Exact lookup misses; the tenant surface refuses an email match (`hooks/omniauth.rb:539-544`, `tenant_sso_link_unavailable`); the JIT accounts have no password, so Connect is closed. See the 2026-10-22 diagnosis.
- Both existing docs purge whole accounts for this cohort because purging frees `accounts.email`. Purging or editing only the `account_identities` rows does nothing: H-3 refuses on the email match whether the account has zero rows or ten, and the new uid is not known until the new IdP asserts it, so a row cannot be rewritten ahead of time. Any recovery that keeps the account is therefore a lazy bind at the next assertion, authorized by someone. The question is only who authorizes and under what gates.
- The migration doc authorizes with mailbox proof and rejects owner authorization (R16) because "the owner could bind their own identity to an employee's account with one click". Those cohort gates alone do not establish equivalent prior power; historical namespace authority is also required. See the next section.

## Authority argument

**Proposed authority argument (conditional).** For an account that (a) has no local credential, (b) was minted through domain D (`signup_domain_id == D`), (c) has identity rows only under D's previous key, and (d) whose previous identity namespace was demonstrably under the organization's administrative authority before the switch, the organization's administrator could already act as that account's holder before the switch, by signing in as the user through their own IdP. Authorizing a re-link of that account to the organization's new IdP gives the organization nothing it did not have.

**Where the argument fails.** Condition (d) cannot be inferred from a tenant-specific Entra issuer, a configured tenant ID, or `ignore_tid: false`. These identify or constrain the directory, not who administered it historically. If D's previous issuer was one the organization never administered, the owner could not previously act as the user and a re-link would be new power. Concretely:

| Previous key | Org-administered? | Decidable from the key? |
|---|---|---|
| Tenant SAML `<domain_id>\|<EntityID>` | Yes: the owner configured this EntityID for D | Yes (domain-scoped by construction) |
| Entra with tenant-specific `iss` (`.../{tid}/v2.0`) | Unknown without independent historical-authority evidence | **No**: `tid` and `ignore_tid: false` do not prove administration; default `undecidable` |
| Entra `common` / `ignore_tid` | No: any Entra tenant | Yes, refuse |
| Generic `oidc` to Okta, Keycloak, Zitadel, Authentik | Unknown without independent historical-authority evidence | **No**: indistinguishable from the next row by the string |
| Generic `oidc` to Google, GitHub, another public provider | No | **No** |

The proposed rule is: tenant SAML's D-scoped key can classify as `own`; shared Entra and generic OIDC keys default to `undecidable`. They may classify as `own` only with independently established historical administrative authority bound to the organization and previous key, not an issuer-pattern allowlist or an operator merely inspecting the string. Without that evidence, fail closed and route to mailbox/local credential proof or operator investigation; operator flagging is not an override. The evidence format and verification are open items; until implemented, these keys remain ineligible. This classification must be enforced at flagging and consumption, not in a dialog.

**What mailbox proof adds.** Mailbox proof demonstrates access to the on-file mailbox; it does not require inferring historical directory administration from an issuer. Even if the 2026-10-22 customer's mailbox is M365 in that Entra tenant, neither that fact nor the identity row establishes the OTS organization's historical authority. Equivalent administrator access is a conditional argument, not evidence of eligibility. A removed membership blocks the departed-employee case; a retained membership requires separate review and does not prove who now controls the mailbox. The proposal keeps the mailbox-proof window as an alternative for namespaces whose historical authority is not established.

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

- **Cohort A is organization-scoped, not domain-scoped.** An organization-scoped membership grants `can_access_domain?` on every domain of the organization. Cohort A requires: no password, no WebAuthn; `signup_domain_id == D`; identity rows per Phase 3 gate 7; memberships in D's organization only; **and no other domain of that organization still accepts the account's rows** (another domain on the same bare generation-0 issuer, or any domain whose current config resolves to the account's previous key). If that last test fails the account is C with reason `identity_still_live_elsewhere`; purging or re-linking it would break the user's other domain.
- Add `namespace` to the classifier output: `own` (D-scoped tenant SAML, or independently established historical authority under the rule above), `undecidable` (tenant-specific Entra and generic `oidc` by default), `public` (Entra `common`/`ignore_tid`, or an operator-maintained denylist of public issuers). Phase 3 consumes it; the issuer string alone cannot promote `undecidable` to `own`.
- Default route for A becomes re-link (Phase 3) only where `namespace == own`; otherwise require mailbox/local credential proof or operator investigation. Purge is a separate destructive recovery option after operator review, not authority proof.
- Dry-run output states the actual purge plan per account: account/auth data and API keys removed, memberships removed, and eligible personal workspace and its receipt index deleted. Purge does **not** burn or destroy Secret/Receipt records: they remain TTL-bound and expire on their own schedule (`apps/web/auth/operations/customers/purge_preflight.rb`, `owned_workspace_notes`). Distinguish loss of account/workspace access and indexes from destruction of secret content; do not promise deletion of everything keyed by customer id.

### Phase 3: owner-authorized re-link on next sign-in

**Data.** `OrganizationMembership` gains `relink_pending` (nullable struct or sidecar record): `domain_id`, `from_key = (provider, issuer)` copied from the SsoConfig's `previous_identity_key` at the moment of flagging, `source_identity_ids` snapshotted at flagging, `flagged_by`, `flagged_at`, `expires_at` (default 30 days, open). Cleared on bind, on owner unset, on expiry, on membership removal.

**Operator action (proposed, first to ship, retroactive; not available today).** `ots sso relink <domain> <email> [--from-key "<provider>|<issuer>"] [--reason ...] [--confirm]`. Without `--from-key` it uses the SsoConfig's `previous_identity_key`; with it, the operator supplies the key for switches made before that field existed (the active customer). The command runs the complete classifier and authority checks, refuses on any failure with the gate named, and defaults to dry run (also explicit via `--dry-run`). Only `--confirm` sets the flag with `flagged_by = operator:<id>` and audits `tenant_sso_relink_flagged`; `--confirm` and `--dry-run` are mutually exclusive. The namespace rule is enforced here too; `--force` does not exist.

**Owner action (UI, second).** Members tab, on a member the classifier reports as A with `namespace == own`: "Re-link on next sign-in". Confirmation: "[name] will be connected to this account the next time they sign in through [current provider] with the address [email]. Until then nothing changes." Permission: the role that may edit the SsoConfig. Audit `tenant_sso_relink_flagged`. The button is absent, with the reason, for B (has a credential: Connect), C (reason category) and for `namespace != own` ("contact support").

**Callback branch** in `account_from_omniauth`, tenant email branch, ahead of the `tenant_sso_link_unavailable` refusal. Issue the bind only when every gate passes; any miss falls through to the existing refusal unchanged, same error code, so the branch is not probeable.

1. Tenant surface: `session[:validated_omniauth_domain_id]` = D.
2. Exact tuple lookup missed; the resolved tuple is under D's current key with a non-sentinel issuer; the assertion passed D's current config policy (`allowed_domains`, `restrict_to`, enabled), already enforced.
3. `existing` located by normalized email; `fold_stable_email?` passed.
4. `existing` has an active `OrganizationMembership` with `can_access_domain?(D)` and `relink_pending` set for D, not expired. Revalidate **complete organization-scoped cohort A** from current state: memberships in D's organization only, and no other domain of that organization currently accepts any source row, in addition to the credential, provenance and source-row gates below. A single shared identity row does not imply a single organization membership. Classifier results from flagging are not sufficient.
5. `existing` has no challengeable password and no WebAuthn credential.
6. `customer.signup_domain_id == D.identifier`.
7. **Source rows, v1 rule:** `existing` has exactly one identity row, its `(provider, issuer)` equals `relink_pending.from_key`, and its id equals `source_identity_ids`. JIT initially creates exactly one row; current eligibility still requires the complete cohort A checks. Accounts with more rows (an earlier retained bare-issuer row, a platform-era Connect) go to the operator in v1; adopting the migration doc's retained-row bookkeeping (§2, R13) is the v2 relaxation if it is ever needed.
8. `relink_pending.from_key` classifies as `namespace == own` **at bind time**, revalidating any independent historical-authority evidence for this organization and key. Classification is not pure on a shared Entra/OIDC key: missing, stale or unverifiable evidence means `undecidable` and refusal, including for operator-set flags.
9. Customer resolves, not suspended.
10. Destination tuple is not owned by another account (`:conflict` → audit, no bind, flag unchanged).

On pass: at flag consumption, revalidate complete cohort A and the destination's active SSO config/key and assertion policy (gate 2), including after MFA. In one transaction with the membership row locked, re-read the source row and re-check the gates before mutation; fail closed if eligibility or policy changed or cannot be established. The implementation must guard against concurrent membership/config changes as well as source-row changes; the membership-row lock alone is not sufficient for cross-store checks. Then insert the destination row, delete the source row when `from_key` is domain-scoped to D (tenant SAML) or retain it when it is a bare generation-0 OIDC/Entra issuer (it may serve another domain; same rule as the migration doc §3), clear `relink_pending`, audit `tenant_sso_identity_relinked` (domain, account_id, obscured email, from/to provider kind, row deleted or retained, flagged_by; uids masked). Then continue login as a normal exact-tuple hit.

**MFA.** If the account requires a second factor, do not bind before it passes. Extend `DeferredSsoBind` with a relink payload carrying the account/destination tuple plus `membership_id`, `domain_id`, `from_key`, `source_identity_ids`, flag identity, validated assertion email and policy-relevant context, and the destination config/key version or fingerprint used to validate the assertion. These are proposed additions, not current payload guarantees. At `.complete`, revalidate the account/flag binding, complete organization-scoped cohort A and gates 1 to 10 against current state, including destination SSO availability (`enabled`, activation, `restrict_to`), current key, `allowed_domains`, and assertion policy. A disabled, changed or unreadable config/key, newly disallowed email, or policy that cannot be revalidated refuses the bind and requires a fresh sign-in; passing callback-time checks is insufficient. Apply the same pre-mutation checks and concurrency protection as the non-MFA path. Stash or revalidation failure → no bind, flag unchanged, audited.

**Second switch.** A rekeying save while any membership of D's organization has `relink_pending` for D is refused until the owner acknowledges "N members flagged for re-link have not signed in yet and will need individual recovery". On acknowledge, those flags are cleared (their `from_key` no longer matches the new `previous_identity_key`) and the accounts become C for the operator. Rollback to the previous provider is a rekeying save under the same rule.

**Expiry.** Default 30 days from flagging, owner can re-flag. Rationale: a standing bind authorization is standing exposure; the cost of re-flagging is one click. Whether to have an expiry at all is an open item.

## Threat review

| Case | Outcome |
|---|---|
| Owner asserts an employee's email from the new IdP to capture their account, previous key `own` | Succeeds only for a flagged account passing complete cohort A and historical-authority checks. Equivalent prior authority is conditional on that evidence, not a tenant-specific Entra issuer. Audited in OTS with `flagged_by`. |
| Same, previous key `public` or `undecidable` | Button absent; gate 8 refuses at bind time even if the flag were set by another path. |
| Owner asserts the email of a platform-minted account that happens to be a member | Gate 6 (`signup_domain_id` blank or other) refuses. |
| Account with a password or passkey | Button absent; gate 5 refuses. Connect is the route. |
| Departed employee, mailbox reassigned to a new hire | Membership removed → gate 4 refuses. Membership kept → the organization still regards the account as that member's; same as leaving the user enabled in the IdP. |
| Account with a second membership elsewhere, or another domain of this org still accepting its rows | Classifier C; button absent; gate 4 revalidates complete cohort A at consumption, including after MFA. Either condition can exist with the same single shared identity row, so gate 7 alone is insufficient. Changes after flagging also refuse. |
| Attacker with a stolen owner session | Can flag; still needs the IdP to assert the email. Same blast radius as editing the SsoConfig, which the same session already permits. |
| NameID-format-only change, new NameID equals an old one | Exact lookup hits before this branch. Closed by the §1 generation key, not by this proposal. |
| Compromised new IdP after the flag is set | Can take eligible flagged accounts while current policy permits. Compromise of the new IdP does not establish access to the previous IdP; the historical-authority argument is about the organization's administrator, not this attacker. |

## Not chosen

| Alternative | Why not |
|---|---|
| Owner purges or edits `account_identities` rows directly | Rows alone unlock nothing (H-3 refuses on the email match); the new uid is unknown until asserted. The re-link flag is the only form "modify the rows" can take. |
| Owner purges whole captive accounts | Buys nothing over re-link for recovery and grants deletion of a person's account and workspace/index data, not burning of TTL-bound Secret/Receipt records. Purge stays operator-side. |
| Mailbox-proof window (migration doc §2 to §4) | Correct, and held. For independently established `own` namespaces the prior-authority argument may justify an alternative; an Entra issuer alone does not. Remains the design for `public`/`undecidable` namespaces if demand appears. |
| Operator-only re-link | Same mechanism with a support ticket per switch. Self-serve is conditional on established namespace authority; operator investigation cannot bypass an undecidable result. |
| Always-on re-link without a flag | Removes the explicit per-account authorization the code comment at `features/omniauth.rb:346-357` requires and turns every config change into silent rebinding. |
| Full retained-row bookkeeping in v1 | Not needed for the JIT cohort (one row). Deferred to v2 by reference to the migration doc. |

## Effect on the existing documents

- tenant-provider-migration.md: R16 disposition should record that the rejection rests on condition (d) above, not on owner impersonation in general; status stays "held" with this proposal as the active path. §1 and the 409 rule are adopted here unchanged.
- 2026-1023-sso-provider-reset-operator-route.md: cohort A becomes organization-scoped with the `identity_still_live_elsewhere` reason; question 3's "no membership → no access" reasoning is withdrawn; default A route becomes re-link where `namespace == own`; the sweep purges only `public`/`undecidable` A accounts after operator review; the ordering refusal and the lockout window between the owner's save and recovery go in the runbook as expected behaviour.

## Open items

- [ ] Confirm on baseline whether tenant JIT marks accounts verified (Colonel check from the 2026-10-22 diagnosis); it decides whether cohort C's self-service reset route exists without `ots customers verify`.
- [ ] Confirm the R2 [VULN] candidate; if real, the §1 generation key ships in Phase 1.
- [ ] Decide: `relink_pending` expiry (30 days proposed, or none).
- [ ] Define independent historical-authority evidence, organization/key binding, storage and bind-time revalidation for tenant-specific Entra and generic `oidc`. Both default to `undecidable`; issuer patterns, tenant IDs and `ignore_tid: false` are insufficient. Until this exists, fail closed to mailbox/local credential proof or operator investigation, including for the active customer.
- [ ] Decide: where `relink_pending` lives (membership column vs. sidecar keyed by membership and domain).
- [ ] Ticket Phase 1: predicate, 409 with counts, `previous_identity_key`/`switched_at`, notices, audit.
- [ ] Ticket Phase 2: classifier (`TenantSsoCohort`, org-scoped A, `namespace`), `ots customers sso-cohort <domain>` dry run, operator route sweep narrowed to `public`/`undecidable`.
- [ ] Ticket Phase 3 core (first): `relink_pending`, proposed `ots sso relink` with `--from-key`, dry run by default and explicit `--confirm` mutation, callback branch gates 1 to 10, locked transaction and deletion/retention rule, `DeferredSsoBind` relink payload, audit events. Target: the four accounts of the 2026-10-22 customer.
- [ ] Ticket Phase 3 UI (after Phase 2): Members-tab button and confirmation, `previous_identity_key` recorded on save, second-switch refusal, expiry.
- [ ] Customer: build estimate for Phase 3 core against their tolerance; offer purge (Option A) as the immediate alternative with its data loss stated.
- [ ] Test matrix: each gate failing alone → refusal unchanged, same code; all pass → bound, logged in, source row deleted (SAML) or retained (bare OIDC), flag cleared, audit present; `namespace == public` with flag forced → refused at gate 8; two rows → refused (v1); conflict on destination tuple → no bind, flag kept; MFA account → bind only after second factor and current-policy revalidation; destination disabled, key/config changed, `allowed_domains` narrowed or assertion policy changed during MFA → no bind, flag kept; tenant-specific Entra without independent historical-authority evidence → gate 8 refuses; password added between flag and sign-in → refused; membership removed → refused; expired flag → refused; second rekeying save with flags pending → 409 until acknowledged, flags cleared; two domains on one Entra tenant, one switches, member of both → classifier C, button absent; second organization membership added or another domain starts accepting the single source row after flagging (including during MFA) → gate 4 refuses at consumption; proposed CLI without `--confirm` → dry run only, with `--confirm` → flag only if all checks pass; stolen-session flag plus foreign email → gate 6 refuses.
- [ ] Docs: `per-domain-sso.md` §"Switching an existing Entra configuration" (re-link procedure, namespace rule), `saml-policy.md` NameID paragraph, `hooks/omniauth.rb:346-353` comment (platform-only rationale now conditional on the namespace rule), runbook `docs/runbooks/sso-provider-switch.md`.

## Related

- [tenant-provider-migration.md](tenant-provider-migration.md) (migration window; held)
- [2026-1023-sso-provider-reset-operator-route.md](2026-1023-sso-provider-reset-operator-route.md) (classifier and sweep)
- `claude/diagnosis/2026-1022-saml-cutover-oidc-accounts-refused-tenant-sso-link-unavailable.md` (trigger)
- `claude/diagnosis/2026-1009-tenant-sso-link-unavailable-preexisting-account-custom-domain.md`
- Repo: `apps/web/auth/config/hooks/omniauth.rb` (`:237`, `:326-353`, `:539-544`), `apps/web/auth/config/features/omniauth.rb` (`resolve_issuer`, `lookup_identity`, `:346-357`), `apps/web/auth/operations/deferred_sso_bind.rb`, `apps/web/auth/operations/backfill_tenant_issuer.rb` (gates 0-2), `apps/web/auth/operations/customers/{purge,purge_preflight}.rb`, `lib/onetime/models/organization_membership.rb` (`can_access_domain?`, `provisioning_source`, `domain_scope_id`), `lib/onetime/models/customer.rb:272` (`signup_domain_id`), `lib/onetime/sso_provider/saml.rb:205` (`tenant_issuer`)
