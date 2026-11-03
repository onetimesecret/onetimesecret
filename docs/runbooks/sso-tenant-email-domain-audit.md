# SSO: Tenant identities outside the proven email domains

Use this runbook after upgrading to a release that includes #4734
(RISK-2026-10-10-01), or whenever the auth log carries
`omniauth_tenant_email_domain_unverified` with `outcome: signed_in`.

Since #4734, tenant SSO creates an account only for an address inside a
custom domain the tenant organization has proven
([per-domain SSO: verified email domains](../authentication/per-domain-sso.md#verified-email-domains)).
A domain is proven by a Colonel override of its verification, or, under a
validation strategy that checks the TXT record (`approximated`,
`caddy_on_demand`), by its verified flag together with a passing TXT check
on record (`verified_confirmed_at`, written since v0.26.14 for a pass from
such a strategy). The flag alone does not count: a domain verified under
`passthrough`, or before v0.26.14, and not checked since has it with no
recorded pass; ADR-016 treats such a domain as never confirmed after a move
to `caddy_on_demand`, and ADR-049 says a switch to either TXT strategy must
not let the flag qualify by itself. Such a domain
counts once `bin/ots domains verify --all` or the scheduled refresh records
a pass. Under `passthrough` (the default) the verify call sets the flag
without a DNS lookup and records no pass, so there only a Colonel override
counts.
The gate runs when an account is about to be created. An identity bound to an
account before the gate existed keeps signing in; the sign-in hook records it
with `outcome: signed_in` so the operator can review it. That event lists only
the accounts that sign in again. `bin/ots sso audit-email-domains` walks the
identity rows themselves, so dormant bindings are found too.

## Symptoms

- `omniauth_tenant_email_domain_unverified` with `outcome: signed_in` in the
  auth log, naming a `domain_id`, `org_id`, an obscured address and an
  `asserted_domain` the organization has not proven.
- A tenant reports that a colleague can still sign in through SSO with an
  address at a domain the organization never added, while a new colleague
  with the same kind of address is refused with `domain_not_allowed`.
- After the upgrade, the operator wants an inventory of accounts a tenant IdP
  minted for addresses the tenant has not proven (the audit's scenarios S1,
  S2 and S8).
- On a `passthrough` install after the upgrade: new tenant SSO users are
  refused with `domain_not_allowed`, even at the tenant's own custom domain,
  and every returning tenant user logs `outcome: signed_in`, because no
  domain has a Colonel override yet. See
  [Passthrough installs](#passthrough-installs).
- On an `approximated` or `caddy_on_demand` install after the upgrade, the
  same symptoms for a domain that was verified before v0.26.14, or under
  `passthrough` before the strategy changed, and has not been checked since:
  it has no recorded TXT pass. See
  [Verified domains without a recorded TXT pass](#verified-domains-without-a-recorded-txt-pass).

## What the command does

```console
$ bin/ots sso audit-email-domains secrets.example.com
```

For the tenant domain given (display domain or CustomDomain extid) it

1. resolves the organization, the SSO configuration, the provider route and
   the identity issuer the live callback writes: the configured issuer for
   OIDC, `https://login.microsoftonline.com/<tenant_id>/v2.0` for Entra ID,
   `<domain_id>|<IdP EntityID>` for SAML;
2. reads every `account_identities` row under that provider and issuer;
3. compares each account's address with the proven set exactly as the login
   gate does (`Organization#owns_email_domain_through?`: the tenant domain
   itself plus every other custom domain of the organization, each counted
   only while `CustomDomain#ownership_proven?`, matched on a label boundary
   by A-label);
4. prints one line per row and a tally. Nothing is written.

The header line `Proven by:` (JSON `proof_basis`) names the basis this
install accepts: `TXT ownership check or Colonel override`
(`txt_or_override`) under a strategy that checks TXT, or `Colonel override
only` (`override_only`) under one that does not. When the configured
strategy cannot be built (an unknown `validation_strategy` with
`strict_strategy: true`), only overrides count and the basis reads
`override_only_strategy_error`; fix the setting before reading the rows.
Read the `outside` rows against it.

Under a TXT strategy the header also lists, as `No TXT pass:` (JSON
`verified_without_txt_pass`), the organization's domains that are verified
without an override and have no passing TXT check on record. Those domains
do not count, so addresses at them report `outside` until a verify run
records a pass.

Statuses:

| Status | Meaning |
|---|---|
| `inside` | The address lies inside a proven domain. Nothing to do. |
| `outside` | The address lies outside every proven domain. Bound before #4734, or the proof lapsed since. |
| `would_unlink` / `unlinked` | `--unlink` preview / result for an `outside` row that passes the provenance gate. |
| `skipped_ambiguous_origin` | Outside, but the account's `signup_domain_id` does not name this domain. Never unlinked. |
| `skipped_no_account` | The identity row has no accounts row with an address (orphan). |
| `error` | A per-row failure; the command exits 1. |

The default run is a dry run even with `--unlink`; `--confirm` executes.
`--json` prints the same report for scripting.

## Deciding what to do with an `outside` row

An `outside` row is one of two things, and the command cannot tell them
apart:

- a legitimate member whose organization has not (yet) proven that email
  domain. The organization adds the domain under Domains and completes the
  TXT check; on a `passthrough` install a Colonel overrides the domain's
  verification instead, after confirming the organization owns it. The row
  then reports `inside` on the next run. The domain never has to be pointed
  at this service;
- a legitimate member at a domain the header lists under `No TXT pass:`.
  The domain is verified, but no passing TXT check is on record. Run
  `bin/ots domains verify --all` (or wait for the scheduled refresh); when
  the check passes, the row reports `inside` on the next run. Do not unlink
  on this basis;
- an account the tenant IdP minted for an address its organization does not
  control. This is the squatting the risk register describes: when the
  address owner later uses a canonical-host password reset or magic link,
  both parties sign into the same account.

Ask the tenant which it is before unlinking. When in doubt, prove the domain
first; unlinking is reversible only by the user linking the identity again.

## Passthrough installs

Under `passthrough`, every domain an organization registers and verifies
reads as verified, but none is proven until a Colonel overrides its
verification. Right after the upgrade, therefore, the audit reports every
identity under a tenant domain as `outside`, including addresses at the
tenant's own custom domain. Do not unlink on that basis.

1. For each tenant domain with SSO enabled, confirm outside this service that
   the organization owns the names its people's addresses use.
2. Override each such domain's verification to true as a Colonel (on the
   domain's page in the admin area, Override Status, then "Accept ownership
   by override"; or `POST /api/colonel/domains/:extid/override` with
   `verified: true`). A later passthrough verify call keeps the override.
3. Run the audit again. Rows at an overridden domain now report `inside`;
   decide the remaining `outside` rows as above.

## Verified domains without a recorded TXT pass

Under `approximated` or `caddy_on_demand`, a domain counts only when a TXT
check has passed since it was verified. `verified_confirmed_at` records that
pass and first shipped in v0.26.14, so a domain verified before that release
and not checked since has none; neither does a domain verified under
`passthrough` before the install moved to a TXT strategy and not checked
since. ADR-016 treats such a domain as never confirmed after a move to
`caddy_on_demand`, and ADR-049 says a switch to either TXT strategy must not
let the flag qualify by itself. The header's `No TXT pass:` line names these
domains.

1. Run `bin/ots domains verify --all` after upgrading, or enable the
   scheduled refresh (`DomainRefreshJob`). A domain whose record is in place
   passes and counts from then on; one whose record is missing is demoted,
   which is the state ADR-016 describes for it.
2. Run the audit again. Rows at a domain that passed now report `inside`.
3. A domain that cannot pass (a private network, a record the organization
   will not add) can be accepted by Colonel override instead, after the
   operator confirms the organization owns it.

Until the pass is recorded, new people at that domain are refused with
`domain_not_allowed`; people whose identity is already bound to an account
keep signing in and log `outcome: signed_in`.

## Unlinking

```console
$ bin/ots sso audit-email-domains secrets.example.com --unlink           # preview
$ bin/ots sso audit-email-domains secrets.example.com --unlink --confirm # execute
```

What changes: the `account_identities` row is deleted and the auth log
records `omniauth_tenant_identity_unlinked` (warn) with the domain,
organization, account id, provider, obscured address, asserted domain and
`actor: cli`.

What does not change:

- the SQL account, its address, its password or passkeys, and the Customer
  record, including its verification fields (those are the subject of
  #4735);
- the organization membership;
- any other identity on the account.

After the unlink, the tenant identity can no longer sign in to that account.
A later tenant sign-in asserting the same address is refused: the account
exists, and an unauthenticated tenant callback never links by email. The
address owner can still claim the account through a canonical-host password
reset.

### Provenance gate

For OIDC and Entra ID the identity key (provider, issuer, uid) is shared by
every tenant and platform configuration that names the same IdP. A row under
this tenant's issuer may therefore have been bound on the platform surface or
by another tenant. The command unlinks a row only when the account's
`signup_domain_id` names this domain. That field is set once when tenant SSO
creates the account and is never rewritten. Any other `outside` row is
reported as `skipped_ambiguous_origin`; review it by hand. SAML keys carry the
domain id, so the gate is a formality there, but it is applied uniformly.

### Re-admitting a legitimate user after an unlink

1. The organization proves the user's email domain: it adds the domain
   under Domains and passes the TXT check (a domain already verified with no
   recorded pass needs a verify run), or, on a `passthrough` install, a
   Colonel overrides the domain's verification.
2. The user signs in on the canonical host. An account minted by SSO has no
   password: they use the password reset first.
3. The user links the tenant identity again from Connected Identities (the
   authenticated linking path, which is not gated by the email domain).

The next audit run reports the row as `inside`.

## JSON example

```console
$ bin/ots sso audit-email-domains secrets.example.com --unlink --json
{
  "domain": "secrets.example.com",
  "organization": "on8q30gih2uxu2cw77jzh7caq07",
  "provider": "oidc",
  "issuer": "https://idp.example.com/",
  "sso_enabled": true,
  "proof_basis": "txt_or_override",
  "verified_without_txt_pass": [],
  "dry_run": true,
  "unlink": true,
  "statistics": {
    "scanned": 3,
    "inside": 1,
    "outside": 0,
    "unlink": 1,
    "skipped_ambiguous_origin": 1,
    "skipped_no_account": 0,
    "errors": 0
  },
  "results": [
    {
      "status": "inside",
      "account_id": 4821,
      "uid": "a1b2c3",
      "customer": "cu2k...",
      "email": "me*****@secrets.example.com",
      "asserted_domain": "secrets.example.com",
      "provider": "oidc",
      "issuer": "https://idp.example.com/",
      "organization": "on8q30gih2uxu2cw77jzh7caq07",
      "message": "Address lies inside a domain the organization has proven"
    },
    {
      "status": "would_unlink",
      "account_id": 4830,
      "uid": "d4e5f6",
      "customer": "cu9x...",
      "email": "vi*****@unrelated.example.org",
      "asserted_domain": "unrelated.example.org",
      "...": "..."
    },
    {
      "status": "skipped_ambiguous_origin",
      "account_id": 4835,
      "...": "..."
    }
  ]
}
```

## Related

- [per-domain SSO: verified email domains](../authentication/per-domain-sso.md#verified-email-domains)
- [Active risk register](../security/active-risk-register.md), RISK-2026-10-10-01
- `bin/ots sso backfill-issuer`, the sibling operation for pre-migration-008
  identity rows
- [sso-accounts-unverified.md](./sso-accounts-unverified.md) for the
  Customer verification fields this command leaves alone
