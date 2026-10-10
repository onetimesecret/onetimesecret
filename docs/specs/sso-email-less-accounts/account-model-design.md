# Account model: internal login, optional contact email, verification state

**Status: PROPOSED for G2 approval. No schema, Rodauth, Customer, or index
change is made until this design is approved.** Date: 2026-10-10.

This is the Phase 2 design for [SSO email-less accounts](../../planning/2026-1009-sso-email-less-accounts.md)
(the proposal) and the design record behind [ADR-051](../../adr/adr-051-account-login-is-not-the-contact-email.md).
The proposal's "Proposed identity and data changes", "Lifecycle and tenant
decisions", and "Acceptance evidence" sections are the checklist; every item
is addressed below by number. Phase 2 is an **account-model change**: it adds
no claim fallback, no username substitute, no synthetic email, and no change
to tenant authorization or trusted-linking policy.

Baseline inspected: `main` at `70679c842d`. Gems: rodauth 2.45.0,
rodauth-omniauth 0.6.2, rodauth-tools 0.4.1, sequel 5.106.0, familia 2.12.0
(`Gemfile.lock`).

## 1. Summary of the change

| Concern | Today | Proposed |
|---|---|---|
| External identity key | `(provider, issuer, uid)`, [migration 008](../../../apps/web/auth/migrations/008_issuer_scoped_identities.rb); Entra UID = gem default `tid` + `oid` | **Unchanged.** No row is re-keyed. |
| Rodauth login column | `accounts.email` ([base.rb:67](../../../apps/web/auth/config/base.rb#L67)) | `accounts.login`: opaque, NOT NULL, UNIQUE, never derived from a claim. Value = the Customer `objid` reserved for the account. |
| Contact email | `accounts.email NOT NULL` + `valid_email` CHECK + partial unique index ([001_initial.rb:26–35](../../../apps/web/auth/migrations/001_initial.rb#L26)) | `accounts.email NULL`; CHECK `valid_email` kept (NULL passes); new CHECK `email <> ''`; partial unique index kept for present values. |
| Mailbox verification | Conflated with Rodauth `status_id` (UNVERIFIED/VERIFIED) and mirrored to Customer `verified` / `verified_by` / `verification_hold` | SQL `email_verified_at`, `email_verified_by`, `email_verification_hold` qualify the contact email. `status_id` keeps meaning "account open". Customer fields stay a mirror written only by `SetCustomerVerification`. |
| Customer email | required by `Customer.create!` ([customer.rb:442](../../../lib/onetime/models/customer.rb#L442)); two unique indexes ([customer.rb:187,190](../../../lib/onetime/models/customer.rb#L187)) | optional; `nil` (never `""`) writes **no** entry in either index scope; present values claimed with the existing CAS (`claim_unique_email_index!`). |
| Account–Customer join | `external_id` written **after** the Customer is created, by email lookup ([ensure_customer_for_account.rb:85–127](../../../apps/web/auth/operations/ensure_customer_for_account.rb#L85)); email fallbacks in [sync_session.rb:223–257](../../../apps/web/auth/operations/sync_session.rb#L223), [account.rb:22–35](../../../apps/web/auth/config/hooks/account.rb#L22) | `login` (objid) and `external_id` (= `extid(objid)`) are written **in the account INSERT**. The join is resolved by `external_id` only. Email fallbacks are removed after backfill. |
| Provisioning order | Redis Customer, workspace and org join run inside rodauth-omniauth's SQL transaction ([omniauth.rb:799–960](../../../apps/web/auth/config/hooks/omniauth.rb#L799)) | SQL account + identity commit first (K1); Customer, workspace and session are materialised after commit from the committed row (K2–K4), idempotently, on every login. |

## 2. Identity ownership is preserved (proposal item 1)

Invariants, all current behaviour, none changed by this design:

- Identity rows are keyed `(provider, issuer, uid)` with the `''` issuer sentinel
  for OAuth2-only rows ([008_issuer_scoped_identities.rb](../../../apps/web/auth/migrations/008_issuer_scoped_identities.rb),
  [bind_sso_identity.rb](../../../apps/web/auth/operations/bind_sso_identity.rb) header).
- Tenant callbacks are issuer-exact and refuse issuerless providers
  ([features/omniauth.rb `refuse_issuerless_on_tenant?`, `lookup_identity`](../../../apps/web/auth/config/features/omniauth.rb#L316)).
- Entra keeps the gem's default `tid` + `oid` UID ([lib/onetime/sso_provider/entra.rb](../../../lib/onetime/sso_provider/entra.rb)).
- Returning identities resolve through `account_from_omniauth_identity`
  (account id from the identity row), never through email or login.

The new `login` column is **not** an identity: it is never compared with a
claim, never shown to the user, never accepted from a request, and is not
reachable from any OmniAuth hash value. Changing contact email, UPN,
`preferred_username`, or `sub` can therefore neither move an identity nor
select a different account.

## 3. Data model (proposal items 2–4)

### 3.1 SQL `accounts`

| Column | Type | Constraint | Semantics |
|---|---|---|---|
| `login` | String | NOT NULL, UNIQUE (after backfill, §7) | Opaque internal login. Value = Customer `objid` (UUIDv7 string). Generated server-side before the INSERT. |
| `email` | citext (PG) / String (SQLite) | NULL allowed; CHECK `valid_email` (PG, kept); CHECK `email <> ''` (both); partial unique index on `(email) WHERE status_id IN (1,2)` (kept) | Optional contact email, normalized by `OT::Utils.normalize_email`. |
| `email_verified_at` | DateTime | NULL | When mailbox control was established for the **current** `email` value. Cleared on any email change. |
| `email_verified_by` | String | NULL | Provenance; one of `Auth::Operations::Customers::Doctor::VALID_VERIFIED_BY` ([doctor.rb:95](../../../apps/web/auth/operations/customers/doctor.rb#L95)). |
| `email_verification_hold` | String | NULL | One of `Onetime::Customer::VERIFICATION_HOLDS` ([customer.rb:80](../../../lib/onetime/models/customer.rb#L80)); why an SSO-asserted address was deliberately left unverified. Mutually exclusive with `email_verified_at`. |
| `external_id` | String | existing: NULL, UNIQUE; target: NOT NULL after backfill (§7 M014) | `extid` derived from `login` (Familia 2.12.0 `external_identifier` feature, `derive_external_identifier`: a deterministic HMAC-SHA-256 or SHA-256 of the objid). |
| `status_id` | existing | unchanged | Account open/closed. UNVERIFIED remains the password-signup gate; SSO JIT accounts open at VERIFIED as today. |

Why `login` = Customer objid rather than a separate token:

- The INSERT itself reserves the Customer identity. A crash anywhere after the
  commit is recoverable from the row alone (§4). No second reservation store
  and no email lookup is needed.
- `external_id` is a pure function of `login`, so both are known before the
  INSERT and can never disagree (today they are written in two steps and the
  doctor has to reconcile them).
- `objid` is already the Customer's primary identifier (`identifier_field :objid`,
  [customer.rb:179](../../../lib/onetime/models/customer.rb#L179)) and is internal;
  `extid` stays the only user-facing identifier. `login` is never emitted by
  any API, log, or email.

NULL handling to verify on both engines in the migration spec (proposal item 3):
PostgreSQL and SQLite both treat NULLs as distinct in unique indexes and both
pass a CHECK that evaluates to UNKNOWN, so the partial unique index and
`valid_email` keep working for present values and ignore absent ones. The
`email <> ''` CHECK is what guarantees "absent means NULL". The 005 views
select `a.email` and need no change.

### 3.2 Rodauth configuration

Follows Rodauth's alternative-login guide: `login_column :login`,
`email_to { account[:email] }`. Every `login_column` consumer in the pinned
gems was enumerated (`grep -rn login_column` over rodauth 2.45.0 and
rodauth-omniauth 0.6.2); the ones that change meaning:

| Consumer | Today | Required override |
|---|---|---|
| `_account_from_login(login)` (base.rb:835) | `WHERE email = login` | `account_from_login`: an objid-shaped value matches `login` (needed by `internal_request`, which sets `params[login_param] = account[login_column]`, internal_request.rb:213); anything else is `normalize_email`'d and matched on `email`. Status filter unchanged. |
| `new_account(login)` (create_account.rb:122) and `_omniauth_new_account(login)` (rodauth-omniauth omniauth.rb:174) | `{email: login}` | `{login: new_objid, external_id: extid(new_objid), email: normalized_or_nil, status_id: ...}`. The typed/claimed value goes to `email`, never to `login`. |
| `email_to` (email_base.rb:31) | `account[:email]` via login_column | `account[:email]`; callers must treat `nil` as "no mailbox" (§5). |
| `omniauth_verify_account?` (rodauth-omniauth omniauth.rb:152) | `account[login_column] == omniauth_email` | compare `account[:email]` with the normalized claim, and only when `email_verified_at` is nil. Without this, an unverified password account would no longer be verified by a matching SSO login. |
| `otp_provisioning_name` (otp.rb:321), `webauthn_user_name` (webauthn.rb:333) | login column | `account[:email] || account[:external_id]`. Never the objid. |
| `normalize_login` ([base.rb:77](../../../apps/web/auth/config/base.rb#L77)) | `normalize_email` | unchanged for typed values; objid-shaped values pass through untouched (case folding must never touch an opaque login; proposal item 3). |
| `login_valid_email?`, `require_email_address_logins?` | applied to the typed signup login | unchanged: the typed value is still an email and still validated. |
| `change_login`, `verify_login_change` | not enabled | stay disabled. Contact changes go through `Auth::Operations::Customers::ChangeEmail`, which gains the `email_verified_*` reset (§5). |
| `login_input_type` (base.rb:352) | `email` because `login_column == :email` | irrelevant (JSON-only), noted for completeness. |

App code that reads `account[:email]` as the account's identity rather than
as a contact address must be audited (68 `account[:email]` reads and 11
`find_by_email(account[:email])` lookups in `apps/web/auth`; the identity-bearing
ones): [account.rb:22–35](../../../apps/web/auth/config/hooks/account.rb#L22)
(`resolve_custid` / `resolve_customer`), [login.rb:397](../../../apps/web/auth/config/hooks/login.rb#L397),
[mfa.rb:154,224](../../../apps/web/auth/config/hooks/mfa.rb#L154),
[two_factor.rb:217](../../../apps/web/auth/config/hooks/two_factor.rb#L217),
[teardown_account.rb:150–156](../../../apps/web/auth/operations/teardown_account.rb#L150),
[sync_session.rb:223–257](../../../apps/web/auth/operations/sync_session.rb#L223).
Each `find_by_email(account[:email])` becomes `find_by_extid(account[:external_id])`;
each email-keyed send becomes "send only if `email` present and verified
(§5), else audit event".

### 3.3 Customer (Redis)

- `Customer.create!(objid:, email: nil, ...)`: `objid` is required and comes
  from `accounts.login`; `email` is optional. `nil` is the only representation
  of "absent": `create!` and the `email=` path reject `""`.
  Familia's class and instance unique-index writers skip `nil` but **would
  write a shared `""` key for an empty string** (`return unless field_value`,
  unique_index_generators.rb:565, :369). Prerequisite P1: Familia treats
  `nil`/empty as absent in `add_to_*`, `update_in_*`, `claim_unique_*!` and
  `find_by_*` (returns `nil` for blank input). Until P1 ships, the Customer
  guards above plus a doctor check for a `""` key in `customer:email_index`
  are mandatory.
- Global index `customer:email_index`: absent email → no entry. Present email
  → `claim_unique_email_index!` CAS (already used by ChangeEmail). A claim
  conflict means another Customer holds the address: fail closed with a
  `provisioning_failure_code`, never merge (SQL's partial unique index already
  makes this drift, not a legitimate race).
- Organization-scoped index (`within: Onetime::Organization`): absent email →
  no entry; `update_in_organization_email_index(org, old)` already releases
  the old key and writes nothing for a nil new value. The only current writer
  is [change_email.rb:754](../../../apps/web/auth/operations/customers/change_email.rb#L754);
  this design adds no new writer.
- Lookups: `find_by_email`, `email_exists?`, `load_by_extid_or_email` return
  `nil`/`false` for blank input. `load_by_extid_or_email` and the email
  fallback in `resolve_custid` are removed once backfill is complete (M014).
- Mirror fields: Customer `verified`, `verified_by`, `verification_hold` are
  derived from SQL `email_verified_at`, `email_verified_by`,
  `email_verification_hold` by `SetCustomerVerification`, which is already
  the single writer that updates both stores. Doctor gains the drift check.

### 3.4 Account–Customer association

Rule: **`accounts.external_id` is written in the INSERT and is the only join
key.** Consequences:

- `EnsureCustomerForAccount` changes from "find or create by email, then link"
  to "materialise the Customer for this row": `find_by_extid(external_id)`;
  if absent, `Customer.create!(objid: login, email:, verified mirror…)`. It is
  idempotent and is the single primitive used by SyncSession, password signup,
  SSO, invites and the CLI. The email-based retry loop in
  [sync_session.rb:199–221](../../../apps/web/auth/operations/sync_session.rb#L199) goes away.
- `link_to_rodauth_account` / `verify_link` become a consistency assertion
  (`external_id == customer.extid`), never a write.
- Simple→full `sync_auth_accounts` writes `login = customer.objid`,
  `external_id = customer.extid`, `email = customer.email`.

## 4. Provisioning protocol: checkpoints, crashes, concurrency (proposal item 5)

Today the Redis writes run inside rodauth-omniauth's `transaction do … end`
(omniauth.rb:79–92 in the gem). Two facts make that unrecoverable: Sequel
**commits** when the block exits through a `throw` (the `redirect` calls in
the hook), and **rolls back** on an exception after the Customer was already
written, leaving a Customer that owns the address with no account.

### 4.1 Checkpoints

| Checkpoint | Store | Written by | Idempotency key |
|---|---|---|---|
| K1 account + identity | SQL, one transaction | rodauth-omniauth callback (INSERT accounts with `login`, `external_id`, `email`, verification columns; INSERT account_identities) | `(provider, issuer, uid)` unique; `email` partial unique; `login` unique |
| K2 Customer | Redis | `EnsureCustomerForAccount` from `after_login` (SyncSession) | `objid = login`; email claim CAS |
| K3 workspace / org membership | Redis | `EnsureDefaultWorkspace` (per-customer `Familia::Lock`, existing) or `JoinDomainOrganization` (idempotent, existing) | customer objid |
| K4 session | session store | SyncSession `populate_session` | account id |

K2–K4 run after K1 has committed and run again on **every** login, so any
later checkpoint that is missing is repaired by the next sign-in. The
`after_omniauth_create_account` hook keeps only the audit event and the
verification-column decision (it has the OmniAuth hash); it no longer writes
to Redis.

Preflight before K1 (non-authoritative, early refusal): `Customer.email_exists?(email)`
when an email is present, mirroring the password-signup guard at
[account.rb:139](../../../apps/web/auth/config/hooks/account.rb#L139). It
prevents the common drift case from reaching a committed row; it is not the
correctness guarantee.

### 4.2 Crash boundaries

| Boundary | State left behind | Recovery |
|---|---|---|
| Before K1 commit | nothing | none needed |
| After K1, before K2 | account + identity rows, no Customer | next login: `find_by_extid` misses → create with `objid = login` |
| During K2: email claim conflict | account row, no Customer | fail closed; `:account_provisioning_failed` with `customer_email_conflict`; doctor lists the row; no merge, no retry loop |
| After K2, before K3 | Customer without workspace/membership | next login re-runs K3 (existing lock + idempotence); tenant path still redirects `org_join_failed` when membership is absent |
| After K3, before K4 | everything but the session | user retries sign-in |
| Backfill interrupted | mixed rows with/without `login` | backfill is resumable (`--after-id`) and re-runnable; M013 refuses to add NOT NULL while any row lacks `login` |

### 4.3 Concurrency

- Same identity, two first callbacks: both INSERT an account; the second
  identity INSERT violates `(provider, issuer, uid)` and its transaction rolls
  back, including its account row. Required change: rescue the unique
  violation in the callback and resume as a returning identity instead of
  surfacing a 500.
- Same email, two first callbacks or signup + callback: the second account
  INSERT violates the partial unique email index inside K1 → rollback → the
  existing duplicate-signup handling applies.
- Several email-less first callbacks at once: no shared key exists (`login`
  values are distinct UUIDv7s, no index entry), so they are independent.
- Two logins racing on K2 for one row: same `objid`, `claim_unique_email_index!`
  returns `:owned` to the loser; `create!` on an existing objid is a no-op
  find. K3 is serialised by the existing per-customer lock.

## 5. Contact-dependent features (proposal items 2, 7)

Rule: a mailbox flow addresses an account **only** through `accounts.email`,
and sends **only** when `email_verified_at` is present. An account with no
email is therefore unreachable by every email-keyed entry point by
construction (`account_from_login` on an email finds no row), which gives the
standard enumeration-safe response with no new branch.

| Feature | Absent email | Present, unverified | Present, verified |
|---|---|---|---|
| Password sign-in | not applicable: setting a first password is refused while `email` is nil (an account must keep a usable login handle for the credential it holds) | works (typed email → row) | works |
| Password reset, magic link (`email_auth`), unlock, `webauthn_modify_email`, new-login/MFA alerts | no send; audit event `mailbox_unavailable` | no send; same event | send |
| `verify_account` (password signup) | not applicable | sends (this is the verification); on success sets `email_verified_at`, `email_verified_by = 'email'` and `status_id = VERIFIED` | n/a |
| Contact email add / change (`ChangeEmail`) | add: write `email`, clear verification columns, start verification | change: same; old address released from both index scopes via existing CAS | same |
| MFA enrol/disable, WebAuthn, recovery codes | allowed; recovery-code download is the recovery path; UI copy must say there is no mailbox recovery | allowed | allowed |
| IdP loss | account is unreachable until a verified contact exists or a colonel re-links; documented as a supported refusal | mailbox recovery only after verification | password reset / magic link |
| Last authenticator | removing the only identity while `email` is nil or unverified is refused | same | allowed when a password or magic-link path remains |
| Billing contact / default workspace | `Organization.create!` already accepts a nil contact email ([organization.rb:566,591](../../../lib/onetime/models/organization.rb#L566)); `WorkspaceCollision` must short-circuit on nil; federated claim skipped (already `return false` on blank `billing_email`) | as today | as today |
| Organization invitations | invitations are keyed by `invited_email`; an email-less account cannot be invited by email (unchanged); tenant membership comes from `JoinDomainOrganization` | as today | as today |
| Notifications (`notify_on_reveal`) | skipped with audit event | skipped | sent |
| Secret creation and link sharing | works; sender display falls back to the workspace or "a Onetime Secret user" | works | works |
| Recipient email delivery | **unchanged restriction**; a separate product decision (proposal "Secret sharing") | unchanged | unchanged |
| CLI / colonel targeting (`bin/ots customers …`) | commands accept `--extid`; email arguments stay for accounts that have one | as today | as today |
| API account payloads | `email` may be `null`; `extid` remains the identifier; frontend renders a placeholder (150 `.email` reads in `src/` to audit) | as today | as today |

## 6. Tenant authorization and policy (proposal item 8)

Unchanged by this design:

- A nonempty `SsoConfig.allowed_domains` keeps refusing missing or malformed
  email on new, returning and Connect flows; missing or corrupt configuration
  stays fail-closed ([omniauth_tenant.rb:669](../../../apps/web/auth/config/hooks/omniauth_tenant.rb#L669)).
- Email-less **tenant** JIT provisioning stays refused even with an empty
  allowlist. It interacts with RISK-2026-10-10-01 R1 (tenant JIT only in
  DNS-verified domains, [#4734](https://github.com/onetimesecret/onetimesecret/issues/4734)):
  an account with no email cannot satisfy a domain rule, so admitting it needs
  the separate security/product decision the proposal already requires. This
  design ships the capability behind a flag scoped to the platform / per-install
  route.
- Trusted-email linking, Connect gates and the `email_verified` hold logic are
  untouched. `email_verified_by = 'sso'` is recorded as provenance; whether
  that provenance satisfies the mailbox gate in §5 is RISK-2026-10-10-02
  ([#4735](https://github.com/onetimesecret/onetimesecret/issues/4735)), an
  operator decision. Default in this design: preserve current behaviour (it
  counts), flip tracked under #4735.

## 7. Migration, cutover, mixed versions, rollback (proposal item 9)

Expand / backfill / enforce / enable. No step fabricates an email, deletes an
account, or requires a destructive downgrade.

| Step | Schema | Binary | Data | Notes |
|---|---|---|---|---|
| S0 | current | N | D0: all rows have email | baseline |
| M012 expand | add `login` NULL **with its UNIQUE index**, `email_verified_at`, `email_verified_by`, `email_verification_hold`; leave `email NOT NULL` | N | D0 | old binary ignores new columns; its inserts leave `login` NULL. The unique index is created here rather than at M013 because both engines treat NULLs as distinct, so it costs the old binary nothing and stops two concurrent backfills from putting one objid on two rows. **Shipped** ([012_account_login_and_contact_verification.rb](../../../apps/web/auth/migrations/012_account_login_and_contact_verification.rb)). |
| Backfill op | — | N or N+1 | D0 | `Auth::Operations::BackfillAccountLogins` / `bin/ots customers backfill-logins` (dry-run default, `--limit`, `--after-id`, idempotent, compare-and-set on `login IS NULL`; precedent [normalize_account_emails.rb](../../../apps/web/auth/operations/customers/normalize_account_emails.rb)). Per row: Customer by `external_id` → `login = objid`; else by the stored or normalized email when exactly one Customer matches and no other row links that Customer → `login = objid`, `external_id = extid`; else `skipped_no_customer`, or with `--mint-missing` a fresh UUIDv7 as `login` with `external_id = extid(login)` (the next K2 creates the Customer under it). Minting is opt-in because binary N re-links such a row by email on its next sign-in and overwrites the minted `external_id`; use it only once N+1 is the only binary. An `external_id` naming a missing Customer is reported (`skipped_dangling_external_id`), never rewritten. Verification: `status_id = VERIFIED` **and** Customer `verified` → `email_verified_at = now`, `email_verified_by = verified_by \|\| 'legacy'`; a Customer `verification_hold` is copied; otherwise NULL. The login value is never printed or logged. **Shipped** ([backfill_account_logins.rb](../../../apps/web/auth/operations/backfill_account_logins.rb)). |
| Deploy N+1 | M012 | N+1 | D0 | N+1 writes `login`/`external_id` on every INSERT, reads by `external_id`, keeps email fallbacks read-only for rows still lacking `login`; email-less writes **disabled** (flag default off) |
| M013 enforce | `login NOT NULL` (the UNIQUE index exists since M012) | N+1 only | D0 | refuses to run while any row has NULL `login` (rows inserted by N during the window are swept by re-running the backfill first). **Boot constraint:** `Auth::Migrator.run_if_needed` applies every migration file present at process start, so a refusing M013 is a boot failure. M013 therefore ships in a release deployed only after the operator has confirmed `backfill-logins` reports zero candidates (and `customers doctor` zero `auth_login_missing`), and its refusal message names that command. |
| M014 enable | `email` nullable, CHECK `email <> ''`, `external_id NOT NULL` | N+1 | D0 → D1 once the flag is on | flag `SSO_EMAILLESS_ACCOUNTS` (default off) gates null-email INSERTs on the platform route only |

Compatibility matrix (binary × data):

| | D0 (no null-email rows) | D1 (null-email rows exist) |
|---|---|---|
| N | works at M012 (ignores new columns); **not supported** at M013/M014 (its inserts violate `login NOT NULL`) | broken for those accounts: `normalize_email(nil)` yields `""`, `Customer.create!` raises; **not a supported rollback target** |
| N+1 | works at every schema step | works |

Rollback boundary: **the first null-email row.** Before it, rolling the binary
back to N is safe at M012, and M013/M014 have non-destructive `down`
migrations (drop constraints/columns; `login` data loss is acceptable because
it is re-derivable). After it, rollback means "turn the flag off and stay on
N+1"; the `down` of M014 refuses while null-email rows exist, and no
migration deletes or rewrites those rows.

Operational checks added to `bin/ots customers doctor`: `login` ↔ Customer
objid (`auth_login_missing`, `auth_login_mismatch`; shipped), `""` key in the
global email index (`email_index_blank_key`, repairable; shipped),
`email_verified_at` ↔ Customer `verified` drift (`auth_email_verification_drift`,
report-only until the N+1 binary makes SQL the writer; shipped), the
org-scoped index `""` key, rows with `login` but no Customer (K2 pending), and
accounts without `email` on a tenant domain (must be zero) (the last three
with the N+1 binary).

## 8. Acceptance evidence (maps to the proposal's list)

Each item is a spec or tryout to be written **with** the implementation and
run through `tests/lanes/run`; lane in brackets.

1. Cross-tenant isolation [full-sqlite, full-pg]: same synthetic `oid` under
   two Entra tenants and same `sub` under two issuers → distinct accounts;
   `ignore_tid: true` case; existing identity rows and `external_id` values
   byte-identical before and after M012–M014.
2. Mutable claims [full-sqlite]: changed email / UPN / `preferred_username`
   on a linked identity changes nothing but (optionally) contact email; a
   username equal to a victim's email cannot adopt the victim; contact-email
   collision fails closed; `login` never changes.
3. Null-email persistence [unit, full-sqlite, full-pg]: PG and SQLite INSERT
   with NULL email; `""` rejected by CHECK; several null-email accounts
   coexist; `customer:email_index` and the org-scoped index gain no key;
   Customer save/load round-trip; session round-trip; login/logout; secret
   creation and link sharing.
4. Present-contact lifecycle [full-sqlite]: add / change / remove reconciles
   SQL, both index scopes and verification columns; the old address is
   released; another Customer's entry is never stolen.
5. Tenant returning users [full-sqlite]: allowed domain succeeds; removed
   domain, missing/malformed email with nonempty allowlist, missing/corrupt
   config all refuse a linked identity; empty-allowlist case keeps current
   behaviour; Connect reauth/surface/membership/ownership refusals asserted.
6. Provisioning [full-sqlite, full-pg]: concurrent first logins (same
   identity; same email; N email-less); injected failure after K1, during K2
   (claim conflict), after K2, after K3; each next login converges to one
   account, one Customer, one workspace; backfill interrupted and re-run;
   M013 refuses with a NULL `login`; M014 `down` refuses with a null-email
   row.
7. Lifecycle outcomes [full-sqlite, full-mfa]: every row of §5 has an
   executed example, including the refusals (first password while
   email-less, last-authenticator removal, mailbox flows with unverified
   email).
8. Real Entra route [full-mfa, nightly]: `/auth/sso/entra` and callback through
   the real strategy with representative sanitized claim shapes (with and
   without `email`, with `email_verified` absent); executed and skipped
   counts recorded; operator-approved live smoke test separately.
9. Doctor [unit]: each new check has a positive and a repair example.

## 9. Decisions requested from the approver

1. `login` = Customer `objid` (recommended, §3.1) versus an unrelated token
   plus a separate reservation store.
2. Mailbox verification lives in SQL (`email_verified_*`) with Customer as
   mirror (recommended, §3.1/§3.3) versus Customer-only.
3. Materialise Customer / workspace after K1 commit via SyncSession
   (recommended, §4) versus keeping them inside the Rodauth transaction with
   compensation.
4. Platform-route-only flag for email-less creation; tenant stays refused
   pending the R1 decision (§6).
5. `email_verified_by = 'sso'` keeps satisfying mailbox flows until #4735 is
   decided (§6).
6. Familia P1 (empty string treated as absent in unique indexes) as a
   prerequisite release, versus app-side guards only.

## 10. Out of scope

Graph enrichment, any new claim fallback, `upn` / `preferred_username`
substitutes, trusted-linking changes, tenant allowlist changes, recipient
delivery widening, and the R1/R2/R3/R4 remediations tracked in #4734–#4736.
