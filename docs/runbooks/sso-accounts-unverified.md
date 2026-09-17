# SSO-provisioned colonel cannot use their role (customer left unverified)

## Symptom

A user who first signed in through SSO holds `role: colonel` (or `admin` /
`staff`) but is treated as a plain customer. Login works, and
`bin/ots customers diagnose <email>` is clean: it reads the auth database, where
the account is already Verified. Confirm with the doctor, which compares Redis
against the auth database:

```bash
bin/ots customers doctor <email|extid>
# [HIGH] SSO-provisioned customer is unverified while its auth account is
#        Verified (system roles are gated on verified?)
```

`bin/ots customers show <email>` shows the Redis side: `role: colonel` next to
`verified: false`.

## Cause

Before v0.26.5 (#3973), the OmniAuth JIT signup path created the Rodauth
`accounts` row as Verified but wrote the Customer record with `verified: false`,
and nothing later reconciled the two — `after_verify_account` only fires in the
email-verification flow, which an SSO user never enters. System roles are
checked by `has_system_role?` (`lib/onetime/application/authorization_policies.rb`),
which tests `verified?` before it reads the role, so the role was granted but
never effective.

v0.26.5 verifies SSO customers at creation. Customers provisioned via SSO on an
earlier version stay unverified until repaired.

## Repair

Audit first, then apply. The `--all` sweep costs one auth-database read per
customer.

```bash
bin/ots customers doctor --all              # audit only: lists affected customers
bin/ots customers doctor --all --repair     # repairs every repairable finding
bin/ots customers doctor <email> --repair   # one customer
```

The `sso_customer_unverified` check (`Auth::Operations::Customers::Doctor`)
fires only when all three hold: the Customer is unverified, its
`provisioning_origin` is `sso_jit`, and its `accounts` row is Verified. The
repair mirrors that stored fact onto the Customer and writes Redis only; it
never touches the auth database. An existing `verified_by` is preserved; a
record with none is stamped `sso`. One `ColonelAuditEvent` per repaired customer.

## What the doctor will not repair

- **Verification was withheld on purpose.** When the JIT hook deliberately left
  the customer unverified, it recorded why in `verification_hold`, and the
  doctor reports such a record at MEDIUM but never auto-repairs it, even with
  `--repair`. Holds are recorded only when the post-upgrade JIT flow creates a
  Customer; it does not add one to an existing Customer, so older unverified
  `sso_jit` records without a hold remain HIGH, repairable findings even if the
  IdP now asserts `email_verified: false`. The reason tells you what to check:

  | `verification_hold` | Meaning                                                   | Before verifying by hand                                        |
  | :------------------ | :-------------------------------------------------------- | :-------------------------------------------------------------- |
  | `idp_unverified`    | The IdP sent `email_verified: false` at sign-in            | Confirm the address with the IdP (or have the user verify there) |
  | `claim_unreadable`  | The IdP's `email_verified` claim could not be read         | Look for `omniauth_email_verified_claim_unreadable` in the auth log and fix the provider response first |

  Once the address is confirmed, verify via the colonel admin page or
  `bin/ots customers verify <email>`. The hold stays on the record as history.

## What the doctor will not catch

- **Simple auth mode, or auth database unreachable.** The check is skipped
  silently and the customer reports healthy. If a full-mode sweep is quieter
  than expected, confirm the auth DB is up (`diagnose` reports
  `authdb_unavailable` when it is not) and rerun.
- **Role-index drift.** The doctor validates the `role` field, not the
  role index. If `bin/ots customers role list` disagrees with `show`, use the
  sibling fix from the same release (#3974):

  ```bash
  bin/ots customers role reconcile            # dry-run report
  bin/ots customers role reconcile --apply    # confirm, then repair the index
  ```
