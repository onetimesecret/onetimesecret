# SSO: Tenant identities outside the proven email domains

Use this runbook after upgrading to a release that includes #4734
(RISK-2026-10-10-01), or whenever the auth log carries
`omniauth_tenant_email_domain_unverified` with `outcome: signed_in`.

Since #4734, tenant SSO creates an account only for an address inside a
custom domain the tenant organization has proven by its TXT ownership check
([per-domain SSO: verified email domains](../authentication/per-domain-sso.md#verified-email-domains)).
The gate runs when an account is about to be created. An identity bound to an
account before the gate existed keeps signing in; the sign-in hook records it
with `outcome: signed_in` so the operator can review it. That event lists only
the accounts that sign in again. `bin/ots sso audit-email-domains` walks the
identity rows themselves, so dormant bindings are found too.

## Symptoms

- `omniauth_tenant_email_domain_unverified` with `outcome: signed_in` in the
  auth log, naming a `domain_id`, `org_id`, an obscured address and an
  `asserted_domain` the organization has not verified.
- A tenant reports that a colleague can still sign in through SSO with an
  address at a domain the organization never added, while a new colleague
  with the same kind of address is refused with `domain_not_allowed`.
- After the upgrade, the operator wants an inventory of accounts a tenant IdP
  minted for addresses the tenant has not proven (the audit's scenarios S1,
  S2 and S8).

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
   itself plus every other custom domain of the organization whose ownership
   is accepted, matched on a label boundary by A-label);
4. prints one line per row and a tally. Nothing is written.

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
  TXT check. The row then reports `inside` on the next run. The domain never
  has to be pointed at this service;
- an account the tenant IdP minted for an address its organization does not
  control. This is the squatting the risk register describes: when the
  address owner later uses a canonical-host password reset or magic link,
  both parties sign into the same account.

Ask the tenant which it is before unlinking. When in doubt, verify first;
unlinking is reversible only by the user linking the identity again.

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

1. The organization verifies the user's email domain under Domains (TXT
   check).
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
