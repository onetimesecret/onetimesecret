# Tenant SSO provider switch: existing users refused with `tenant_sso_link_unavailable`

## Symptom

A custom-domain org changed its SSO provider (OIDC → SAML, Entra → OIDC, new
Entra tenant, new SAML EntityID, or NameID format). Every user who signed in
under the old provider now gets "This identity isn't connected to an account on
this domain". Domain SSO status shows the last failure as
`tenant_sso_link_unavailable` at the `account` step. Users new to the domain
sign in fine. The owner has usually already tried removing and re-inviting
members, deleting and recreating the SSO config, or both; none of it changed
anything.

## Cause

Identity rows are keyed `(provider, issuer, uid)`; the switch gave every user a
new key. Exact lookup misses, the callback finds an existing account by email,
and on a tenant surface an email match is refused (H-3). The accounts were
JIT-created, so they have no password and cannot use Connect. No tool relinks
identity rows; `bin/ots sso backfill-issuer` refuses SAML.

The blocker is the **accounts**, not the config. Recreating the SsoConfig,
removing memberships, or deleting identity rows leaves the email collision in
place. Only two things clear it: delete the account (fresh JIT), or bind the new
identity to the account by an explicit per-account action.

## Triage (10 minutes)

For each affected email:

```bash
bin/ots customers diagnose <email>     # has_password, external_identities, verified, sessions
bin/ots customers show <email>         # role, verified, memberships
```

Record per account: `has_password`, WebAuthn present, identity rows
(provider/issuer), `verified`, `signup_domain_id`, org owner yes/no, any
membership in another org, and whether an old identity is still accepted on any
other accessible domain (including a sibling domain in this org).

In Colonel, on the domain: current `provider_type`, `allowed_domains`,
`restrict_to`, last completed sign-in (who, and whether it was a new JIT).

Classify:

| Cohort | Test | Route |
|---|---|---|
| **B** credentialed | has password or WebAuthn | self-service Connect, no operator action |
| **A** captive | no credential, `signup_domain_id` = this domain, identity rows only under the old key, none still accepted on another accessible domain, memberships in this org only, not owner | purge (today) or re-link (when built) |
| **C** anything else | foreign membership, platform-minted, provenance blank, identity elsewhere, `identity_still_live_elsewhere` | individual: see below |

An org-scoped membership can authorize sibling domains without a second
membership. If a sibling still accepts the old shared Entra/OIDC row, classify
the account as C (`identity_still_live_elsewhere`), not A. Check each accessible
domain's current SSO config; matching provenance and no foreign membership are
not sufficient.

Never purge the org owner. If the owner is passwordless, stop and get them a
password first (reset flow) before anything else.

## Decide with the customer

Ask one question: **can the affected accounts be discarded?** Purge removes
the account, API keys, eligible personal workspace, memberships and role
assignments, and account/index access to secret history. It does **not** delete
`Secret` or `Receipt` records or revoke already-shared links: those records
remain TTL-bound. If links must be revoked, arrange explicit burning separately
before losing account access. State this in writing before they answer.

Source: `apps/web/auth/operations/customers/purge_preflight.rb`,
`owned_workspace_notes`: "the organization's receipt index is dropped with it,
while the Receipt and Secret records are TTL-bound and expire on their own
schedule."

- Disposable → Route 1.
- Must keep → Route 2 (today) or Route 3 (once shipped).

## Route 1: purge, then plain sign-in (cohort A, accounts disposable)

Preconditions: SsoConfig already points at the new provider (otherwise users
re-mint under the old key between steps); `allowed_domains` covers every email
domain in play or is empty; owner not in the list; `restrict_to` not blocking.

```bash
bin/ots customers purge <email> --reason "SSO provider switch, ticket #NNN"   # one per account, confirm each
```

Preflight refuses org owners and non-empty workspaces. It **removes** (does not
refuse) memberships in other orgs, which is why cohort C must never reach this
step.

Then each user signs in on the custom domain with the new provider. JIT creates
a fresh account and auto-joins the org. Owner re-sets roles in the Members tab.
Tell the owner the new accounts are passwordless again and the same trap applies
to any future switch.

## Route 2: password, then Connect (cohort B, or A when accounts must be kept)

1. User: "Forgot your password?" on the custom domain → set a password.
   Unverified accounts receive no reset email. Check `verified` in triage; if
   false, `bin/ots customers verify <email>` after confirming mailbox
   ownership out of band (reply from that address on the ticket thread).
2. User: sign in with email + password on the custom domain.
3. User: Security settings → Connected identities → Connect the domain's
   provider → re-authenticate. The tenant Connect callback binds the new tuple.
4. SSO sign-in works.

Requires `restrict_to` not pinned to SSO-only and an active membership for the
domain.

## Route 3: operator re-link (cohort A, accounts must be kept; not yet built)

Spec: `docs/specs/sso/tenant-provider-switch-owner-relink.md`. When shipped:

```bash
bin/ots sso relink <domain> <email> --from-key "<provider>|<old issuer>"     # dry run
bin/ots sso relink <domain> <email> --from-key "<provider>|<old issuer>" --confirm
```

Refused unless the old key is the org's own namespace (tenant SAML, or
tenant-specific Entra issuer). User then signs in once with the new provider;
the callback binds and logs them in. Nothing deleted.

## Cohort C

Individual handling. Foreign membership or platform-minted: Route 2 only, never
purge. Provenance blank or identity elsewhere: Route 2 if they have or can set a
password; otherwise escalate. `identity_still_live_elsewhere`: never purge;
use Route 2 or escalate without deleting the account.

## What does not work (tell the owner once)

Members-tab remove and re-invite (membership only; invite runs the same
callback). Deleting and recreating the SsoConfig. Rolling back
to the old provider (works, but is itself a switch; the new-provider JIT
accounts created meanwhile are now the stranded ones).

Successful authenticated self-service account closure already calls `Purge`
and deletes the auth account (`apps/web/auth/config/hooks/account.rb`,
`after_close_account` and `delete_account`). **Never follow successful closure
with another email-based purge**: a fresh JIT account may already have reused
that email. Operator recovery is only for confirmed incomplete cleanup, after
revalidating the exact original Customer identity and auth-account linkage
against the closure evidence, not resolving a target by email alone.

## Prevention (say it in the closing reply)

Before any future provider change, every member should add a password or
passkey. A member with one is cohort B and recovers alone. The product-side
warning on rekeying saves is the prevention phase of the spec above.

## Related

- `docs/specs/sso/tenant-provider-switch-owner-relink.md`
- `docs/specs/sso/tenant-provider-migration.md` (migration window, held)
- `docs/specs/sso/2026-1023-sso-provider-reset-operator-route.md` (classifier and guarded sweep)
- `docs/runbooks/sso-accounts-unverified.md`, `docs/runbooks/cannot-log-in-or-create-account.md`
- `docs/authentication/per-domain-sso.md` §"Switching an existing Entra configuration"
