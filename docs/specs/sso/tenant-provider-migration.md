# [DECISION] Tenant SSO provider switch: migrate tenant-bound passwordless accounts, owner-initiated, window-bounded

**Search keywords:** provider switch, switch to SAML, OIDC to SAML, entra_id to oidc, NameID format change, identities rekeyed, tenant_sso_link_unavailable after switch, SSO migration window, migrating state, tenant-bound account, passwordless JIT account, H-3, account_identities (provider, issuer, uid), tenant_issuer, sso_identity_migrated, acknowledge_migration, SsoConfig migration record, #4450, #3849, #3840, 2026-10-22

**Date:** 2026-10-22 · **Status:** decided, not yet ticketed · **Scope:** tenant (custom-domain) SSO only; platform surface unchanged

---

## Headline

Changing a custom domain's SSO provider type, IdP EntityID, or SAML NameID format rekeys every identity on that domain. Today the users that domain's previous IdP created (passwordless, JIT) are locked out with `tenant_sso_link_unavailable` and have no self-service way back, by design (H-3). This has happened to several customers. Decision: an org owner switching provider puts the domain's SsoConfig into an acknowledged, time-boxed **migrating** state; during it, a tenant callback may bind the new identity tuple to an existing account **only when the server can prove the account was already bound to this same domain's previous IdP**. Email still only locates; the prior tenant-scoped bind is what authorizes. No colonel involvement, no email trust, no row relabelling.

## Context (why the current behaviour is right, and why this does not weaken it)

- H-3 (`hooks/omniauth.rb:237`): an unlinked IdP identity whose email matches an existing account is never bound on the email alone, because a tenant admin controls their IdP and can assert any email. What it protects is accounts the tenant did **not** create: platform accounts, other tenants' accounts, password accounts sharing an email.
- `lookup_identity` (`features/omniauth.rb:346-357`) refuses lazy issuer grace for SAML and on tenant paths; `backfill-issuer` refuses `saml` domains. Both exist because a NameID is a different namespace from a `sub`, so relabelling rows is unsafe. This decision does not relabel rows.
- The stuck population has a server-verifiable property: every `account_identities` row on the account carries an issuer from **this domain's own SSO history**, and the account has no other credential. The owner already controlled those users completely through the old IdP. Binding them to the same owner's new IdP adds no capability the owner did not have.
- Related diagnoses: `claude/diagnosis/2026-1022-saml-cutover-oidc-accounts-refused-tenant-sso-link-unavailable.md` (this trigger), `claude/diagnosis/2026-1009-tenant-sso-link-unavailable-preexisting-account-custom-domain.md`.

## Decision

### 1. Migration record on `CustomDomain::SsoConfig`

A PUT/PATCH that would rekey identities (provider_type change; `idp_entity_id` change; effective `name_id_format` change, which the code already detects and audits as `domain_sso_name_id_format_changed` with `identities_rekeyed: true`) is refused with 409 unless the request carries `acknowledge_migration: true`. The 409 body includes `affected_accounts` (count of passwordless accounts whose identities are all bound to the domain's current issuer key) so the UI can say "N existing SSO users will be migrated on their next sign-in".

With acknowledgement, the save also writes a migration record on the SsoConfig:

- `from_provider_type`, `from_issuer_key` (the exact issuer string identity rows carry today: `entra` + validated `iss`, OIDC route + issuer, or `"<domain_id>|<EntityID>"`; for a NameID-format-only change the issuer key is unchanged and `from_uid_namespace` records the old format)
- `started_at`, `expires_at` (default 30 days, max 90), `acknowledged_by` (owner custid)
- Audited at WARN: `domain_sso_migration_started` (domain, from/to provider_type, affected count, expires_at; never the issuer values)

While a migration is active, a second rekeying change is refused until the owner ends the migration. The owner can end it early ("Finish migration"); it ends automatically at `expires_at`. Ending is audited (`domain_sso_migration_ended`, reason: `finished|expired|superseded`).

Permission: the same role that may edit the SsoConfig today. Colonel gets read-only visibility of the migration record and may end it; no colonel path bypasses any gate below.

### 2. Migration bind in `account_from_omniauth` (tenant email branch, before the H-3 refusal)

Insert one branch ahead of the `tenant_sso_link_unavailable` redirect. Every gate must pass; any miss falls through to the existing refusal unchanged.

1. Tenant surface: `session[:validated_omniauth_domain_id]` = D (set by `omniauth_tenant.rb`).
2. D's SsoConfig has an active migration record (`now < expires_at`).
3. Exact tuple lookup already missed (we are in the email branch).
4. `existing` located by normalized email; `fold_stable_email?` passed (both already true here).
5. `existing` has no challengeable password (`account_has_challengeable_password?`, including Redis-resident legacy) and no WebAuthn credential. Accounts with a local credential keep the existing route: sign in, Connected identities, Connect.
6. `existing` has at least one identity row, and **every** identity row's `(provider, issuer)` equals the migration record's `from_provider`/`from_issuer_key`. Any row bound elsewhere (platform, another domain, another provider) → refuse. Zero rows → refuse.
7. `existing`'s Customer resolves, is not suspended, and holds an active `OrganizationMembership` that authorizes D (`can_access_domain?`), the same gate tenant Connect uses. Membership removed by the owner → refuse; the owner re-invites first.
8. The new callback resolved a non-sentinel issuer for D (already enforced by `refuse_issuerless_on_tenant?`) and passed `allowed_domains` (already enforced on every tenant callback).
9. The asserted email normalized equals the account email normalized (already true by construction of step 4; restated so the gate list is complete).

On pass: write the new `(provider, issuer, uid)` row for `existing`, delete the old row(s) matching `from_issuer_key`, and return `existing` so the gem logs the user in. Audit at WARN: `tenant_sso_identity_migrated` (domain, account_id, obscured email, from provider/issuer kind, to provider/issuer kind, migration started_at; uids masked). Increment a `migrated_count` on the migration record so the owner's UI can show progress against `affected_accounts`.

MFA: if the account requires a second factor, complete the bind through the existing `DeferredSsoBind` path after the factor, as the mailbox-proof and interstitial flows do, rather than binding before MFA.

### 3. Entra stable-subject bridge (phase 2, optional strengthening)

For `entra_id` → `saml` on the same Entra tenant, the SAML `objectidentifier` claim equals the OIDC `oid`. When present and equal to the old row's `oid` component, the bind may proceed even if gate 9 fails (user's email changed in Entra). Gates 1-8 still apply. Attribute names are IdP-chosen, so this never replaces the gates; it only relaxes the email equality.

### 4. Owner-facing surface

- Switch dialog: shows affected count, requires acknowledgement, explains the window, offers "Start fresh" as an explicit secondary action (purge of the affected accounts via the existing audited `Customers::Purge`, each one listed, confirmation per batch). Default is migrate.
- SSO tab while migrating: "Migrating from <old> until <date>: <migrated>/<affected> users signed in" with a Finish button.
- After expiry: remaining users get today's refusal and the self-service password-reset + Connect route; the SSO tab lists them so the owner can act.

## Rejected alternatives

| Alternative | Why not |
|---|---|
| Enable `*_TRUST_EMAIL_FOR_LINKING` on tenant surfaces during the window | Binds by email alone; would let the owner attach a tenant identity to any platform or password account sharing an email. Exactly what H-3 forbids. |
| Lazy issuer grace / `backfill-issuer` for SAML | Relabels `sub` rows with a SAML issuer; a NameID that collides with an old `sub` would sign in as that account (#4450). This decision keys on the account's prior bind plus a fresh assertion, and never rewrites a uid. |
| Keep two providers active in parallel | Connect requires recent local re-authentication (#4411); an SSO login via the old provider cannot Connect the new one. Multi-config adds surface for no gain over the migration record. |
| Owner-triggered purge as the default | Destroys users' secrets and makes account deletion an owner power. Kept only as an explicit, listed, secondary choice. |
| Colonel-only remap tool | Every switch becomes a ticket; adds no security property, since the gates above are server-enforced regardless of who flips the switch. Keep a CLI for odd cases, not as the product path. |
| Better warnings only | Already tried; does not help the users already locked out, and owners switch anyway. |

## What this does not cover

- Accounts with a password or passkey: unchanged (Connect from Connected identities).
- Platform accounts and accounts bound to another domain or provider: refused by gate 6.
- Accounts whose membership was removed: refused by gate 7 until re-invited.
- Users whose email changed in the IdP: refused unless phase 2 applies.
- Not retroactive: domains already switched before this ships have no migration record. The 2026-10-22 customer proceeds with the purge route in its diagnosis doc.

## Open items

- [ ] Ticket: migration record + 409/acknowledge on rekeying saves (API, `put_sso_config.rb` / `patch_sso_config.rb`, serializers, change_logger)
- [ ] Ticket: migration bind branch in `hooks/omniauth.rb` with the nine gates; audit events; `DeferredSsoBind` for MFA accounts
- [ ] Ticket: owner UI (switch dialog with count and acknowledgement; migrating banner; Finish)
- [ ] Ticket: Colonel read-only view + end-migration action
- [ ] Decide: default and maximum window (30/90 proposed)
- [ ] Decide: whether a NameID-format-only change needs the full record or a lighter "uid namespace" variant of the same gates
- [ ] Phase 2: Entra `objectidentifier` bridge
- [ ] Test matrix: each gate failing alone → refusal unchanged; pass → bind, login, old row gone, audit present; expired window → refusal; platform surface untouched; second switch during window refused; MFA account defers bind
- [ ] Docs: `per-domain-sso.md` §"Switching an existing Entra configuration" to describe the migration state; `saml-policy.md` NameID paragraph likewise
- [ ] Update `AGENTS.md` repo-conventions note if the migration branch changes what reviewers may treat as invariant

## Related

- `claude/diagnosis/2026-1022-saml-cutover-oidc-accounts-refused-tenant-sso-link-unavailable.md`
- `claude/diagnosis/2026-1009-tenant-sso-link-unavailable-preexisting-account-custom-domain.md`
- Chat "SSO identity linking errors on tenant surface" (2026-09-08), #3849 history
- Repo: `apps/web/auth/config/hooks/omniauth.rb`, `apps/web/auth/config/features/omniauth.rb`, `apps/web/auth/config/hooks/omniauth_connect.rb`, `apps/web/auth/operations/backfill_tenant_issuer.rb`, `docs/authentication/per-domain-sso.md`, `docs/authentication/saml-policy.md`
