# Merging Organizations and Customers

Status: draft — the support-commands audit flagged merge as the one capability
that exists at NO layer (no model method, no Operation, no CLI verb, no colonel
endpoint). This document specifies what a merge must reconcile and proposes a
ruling for every decision that has to be settled before anyone builds it. It is
a sibling to `deleting-an-organization.md`: same house style, same "options and
complications" posture, but unlike that document the rulings here are written
down (see "Rulings") so the build can start once they are ratified. Nothing here
is implemented.

## Scope

Two verbs, one shared shape:

- `org merge <src> <dst>` — fold organization `src` into `dst`, then delete
  `src`. Every member, domain, pending invitation, receipt, entitlement and
  (where reconcilable) billing linkage that hangs off `src` ends up on `dst`.
- `customers merge <src> <dst>` — fold customer account `src` into `dst`. Moves
  `src`'s org memberships, receipts, secrets, feature flags, SSO identities and
  personal/default org onto `dst`; INVALIDATES `src`'s sessions (they are not
  moved, see "Sessions"); then closes `src`'s auth account and purges `src`.

Both are operator-only (CLI + colonel), both are irreversible past the apply
threshold, and both are dry-run-first (see "Safety model").

### The root-cause motivator: duplicate personal orgs

The forcing case is not team consolidation. It is that a single human ends up
with **two accounts** — a native signup plus an SSO-minted one, or two SSO
identities — and therefore two `is_default` personal workspaces
(`organization.rb:71`). `CreateDefaultWorkspace` mints one per account. Its
orphan adoption (`create_default_workspace.rb:213-221`, match by
`contact_email`, only when the existing org has no members) PREVENTS the
duplicate for the same-email case — so by construction the two accounts we are
merging always have DIFFERENT emails (`email_index` is unique), and their two
personal orgs always have different `contact_email`s. Support has no way to say
"these are the same person, make them one." `customers merge` is that verb;
`org merge` is the half of it that reconciles the two personal workspaces, and
is independently useful for teams that stood up two orgs by mistake. Neither can
be built without the other being at least specified, because a customer merge
that leaves two default orgs behind has not merged anything the user can see.

In `AUTHENTICATION_MODE=full` the root case is, at bottom, a **SQL identity**
problem: two `accounts` rows, and the `account_identities` rows (provider,
issuer, uid → account_id; `auth/migrations/008_issuer_scoped_identities.rb`)
that decide which account an SSO login lands on. Re-pointing those rows IS the
SSO half of the merge. The Redis side (orgs, receipts, secrets) is the visible
half; the SQL side is the half that stops the duplicate from coming back.

## Why nothing composes today

The toolbox has SINGLE-record movers, not set movers. The gap is not "write a
merge Operation that calls the existing ones in a loop" — several of the moves
a merge needs have **no primitive at all**, one primitive that exists no-ops on
exactly the collision a merge creates, and the one teardown primitive we would
compose (`Customers::Purge`) leaves the SQL account alive, which resurrects the
duplicate. Enumerated in "Primitives that are insufficient" below.

## Inventory — what a merge reconciles, per subsystem

Every row is a distinct data structure a merge touches. `src`/`dst` are the
losing/surviving side. "Primitive" names the existing Operation or model method
that moves one such record, or `— none —` where none exists.

### Organization merge (`org merge src dst`)

| Subsystem | Structure(s) | Primitive | Collision case |
|---|---|---|---|
| Memberships | `org.members` zset + `customer.participations` reverse index + the `OrganizationMembership` through-hash (`organization_membership.rb:516-517`) | `Memberships::Add` / `Remove` / `SetRole` | Customer is a member of BOTH orgs → duplicate membership; roles differ → convergence rule (R2) |
| Org-scoped email index | per-org `unique_index :email, :email_index, within: Onetime::Organization` (`customer.rb:175`) — the index the customer Doctor polices as `:org_email_index_stale` | maintained by `Memberships::Add`/`Remove` | must be written on dst and released on src for every moved member |
| Pending invitations | `org.pending_invitations` staged set + `OrganizationMembership` rows with `customer_objid` nil and `invited_email` set (`organization_membership.rb:140,153`); invite tokens encode the org | `— none —` (`Org::Delete` step 3 destroys them) | same `invited_email` pending on both sides → keep dst's, drop src's |
| Entitlements | per-membership `materialized_entitlements` + `entitlements_plan/grants/revokes` sub-keys, materialized only via `change_role!` (`organization_membership.rb:258-269`) — the role LABEL alone grants nothing | re-materialize through `Memberships::Add`/`SetRole`, or `Org::Reconcile` | src and dst on different plans → dst's plan wins (R3) |
| Domains | `org.domains` zset + `CustomDomain#org_id` + `CustomDomain.owners` class-hashkey (`custom_domain.rb:87,92`) | `Domains::Transfer` (moves ONE) | none in normal operation — see next row |
| Domain uniqueness | `CustomDomain.display_domain_index` — `unique_index :display_domain`; `create!` gates on `display_domain_index.hsetnx` (`custom_domain.rb:140,808-809`) so a second record for the same display domain CANNOT be created | `update_display_domain` (`custom_domain.rb:194`) | reachable only via index drift → refuse `:domain_collision` (R1), not a merge branch |
| Receipts | `Receipt#org_id` + the `organization:<objid>:receipts` zset (`receipt.rb:52,74`) | `— none —` | receipts silently keep keying off the dead `src` objid (the `Org::Delete` dangling-ref, delete.rb note 3) |
| Billing / Stripe | org fields `stripe_customer_id`, `stripe_subscription_id`, `billing_email`, `email_hash` + their four unique/multi indexes (`with_organization_billing.rb:63-106`) | `Org::Reconcile` (re-pulls ONE org's sub) | src `billing_live?` → refuse `:billing_conflict` (R4) |
| Ownership | `owner_id` (deprecated) + `created_by` (immutable, ADR-012, `organization.rb:68-69`) + the `role:'owner'` membership | `Org::TransferOwnership` | src and dst owned by different customers; `created_by` and `invited_by` dangle after a customer merge (R5) |
| Default-workspace | `org.is_default` label + `customer.default_org_id` pointer (`organization.rb:71`, `customer.rb:201`) | `— none —` (delete clears, never promotes) | merging one personal workspace into another orphans a `default_org_id` |
| Contact email | `contact_email` + `contact_email_index` unique index (`organization.rb:63`) | `delete!` override releases it (`organization.rb:427-431`) | COMMON: src and dst differ → dst keeps its own, src's is released at delete. RARE: equal → index already holds one; nothing to do |
| Registry | `Organization.instances` class zset | `instances.remove` (`org/delete.rb` step 2) | — |
| Audit | `ColonelAuditEvent`, COUNT-capped at `MAX_EVENTS = 10_000`, no TTL (`colonel_audit_event.rb:116`) | `ColonelAuditEvent.record` | eviction pressure (see "Audit") |

### Customer merge (`customers merge src dst`)

| Subsystem | Structure(s) | Primitive | Collision case |
|---|---|---|---|
| Org memberships | `customer.participations` + each `org.members` entry + through-hash + each org's scoped `email_index` (`customer.rb:175`) | `Memberships::Add`/`Remove` per org | src and dst both members of org X → duplicate; role convergence (R2) |
| Personal/default org | src's `is_default` org + `default_org_id` pointer | delegate to `org merge` | two personal workspaces → this is the root case; needs `org merge` |
| Pending invitations | `OrganizationMembership` rows with `invited_email == src.email` in any org | `— none —` | src's email closes → invites addressed to it orphan; re-address to dst's email or drop if dst is already a member |
| Receipts | `customer.receipts` zset + `Receipt#owner_id` back-pointer (`receipt.rb:34`, `customer.rb:102`); `Receipt#owner?` compares `fobj.objid == owner_id` (`receipt.rb:210`) | `— none —` | moving the zset without rewriting every record's `owner_id` gives dst a list of receipts it does not own |
| Secrets | `customer.secrets` zset + `secrets_active` counter (`customer.rb:112-122`) + `Secret#owner_id` back-pointer (`secret.rb:42`); `Secret#owner?` compares by objid (`secret.rb:97`); `Secret#destroy!` decrements the counter of `owner_id` (`secret.rb:64-66`) | `— none —` | zset moved but `owner_id` not rewritten → dst cannot burn them AND every later destroy decrements the DEAD owner, so dst's counter drifts up forever. Safe to rewrite: `Secret` declares no `aad_fields` (`receipt.rb:255-258`), so `owner_id` is not bound into the ciphertext |
| Sessions | `customer.active_sessions` zset (`customer.rb:129`) + the session blobs keyed on src's `external_id` (`session.rb:725`) + SQL `account_active_session_keys` / `account_session_keys` / `account_remember_keys` | `— none —` (and none wanted) | NOT moved: destroyed. A src session that became a dst session would never have satisfied dst's MFA |
| Feature flags | `customer.feature_flags` hashkey (`customer.rb:130`) | `— none —` | conflicting per-flag values → dst wins (R6) |
| Identity index | `unique_index :email → email_index` (`customer.rb:172`). `create!` normalizes (`customer.rb:346`); only `email_exists?` reads raw (`customer.rb:394`) | freed on `destroy!` | src and dst emails always differ (unique); src's is freed at purge |
| Role index | `multi_index :role → role_index` (`customer/features/role_index.rb:27`) | `Customers::ReconcileRoleIndex` | either side `colonel` → refuse `:colonel` (R7) |
| Account fields | `planid`, `signup_domain_id`, `provisioning_origin`, `locale`, `notify_on_reveal`, `last_login` (`customer.rb:187-212`) | `— none —` | dst wins; provenance untouched (R6) |
| Full-auth `accounts` row | Postgres `accounts` row, `external_id = customer.extid`; `citext` email with partial unique `where status_id in (1,2)` (`auth/migrations/001_initial.rb:26,32`) | `— none —`; `Customers::Purge` → `DeleteCustomer` is Redis-only (`delete_customer.rb:85`, `cli/customers/purge_command.rb:212`) | src row left open → next login autocreates a fresh Customer + default workspace (`auth/config/base.rb:54`, `hooks/account.rb:198`) and the duplicate is BACK. Must be closed (`status_id` 3) |
| Full-auth SSO identities | `account_identities` (provider, issuer, uid → account_id) | `— none —` (`BindSsoIdentity` binds one; nothing re-points) | THE root-case move: every src identity row → dst's `account_id`. An identity left on src resurrects the duplicate on its next SSO login |
| Full-auth credentials | `account_password_hashes`, `account_previous_password_hashes` | `— none —` | src's password is DROPPED (dst keeps its own); the user logs in with dst's password or via a re-pointed identity |
| Full-auth MFA | `account_webauthn_keys`, `account_webauthn_user_ids` (1:1 per account, `001_initial.rb:164-167`), `account_otp_keys`, `account_recovery_codes`, `account_sms_codes` | `— none —` | `webauthn_user_ids` cannot move (one per account); src's MFA is DROPPED, dst's stands |
| Full-auth lockout/audit | `account_lockouts`, `account_login_failures`, `account_authentication_audit_logs`, `account_activity_times` | `— none —` | src's rows deleted with the close; the Rodauth audit log stays on the closed row (history, never moved) |
| Deprecated billing | `customer.stripe_customer_id` (`customer/features/deprecated_fields.rb:31`) | `migrate_billing_to_org` (`migration_fields.rb`) | legacy accounts still carry it |
| Audit | `customer.purge` verb precedent (`customers/purge.rb`) | `ColonelAuditEvent.record` | — |

## The four collision cases

### 1. Same-`display_domain` (drift only)

`display_domain_index` is globally unique and `CustomDomain.create!` claims the
entry with `HSETNX` before writing the record (`custom_domain.rb:808-809`), so two
live records for one display domain cannot be created. The case is reachable
only through index drift (a record whose index entry was lost or repointed).
That makes it a doctor check, not a merge branch: the preview compares the two
domain sets by `display_domain`, and any overlap refuses `:domain_collision`
before anything moves. `Domains::Transfer` has no such guard — its only refusal
is `:mismatch` (`domains/transfer.rb:59`) — so the merge owns the check. The
operator repairs the drift (`domains` doctor / remove) and re-runs.
**Ruling R1.**

### 2. Duplicate membership + role convergence

A customer who belongs to both orgs (org merge) — or two customers who both
belong to org X (customer merge) — must not end with two through-models for the
same (org, customer) pair. `Memberships::Add` is idempotent but returns
`:no_change` WITHOUT touching the role (`memberships/add.rb:100`, "add is
strictly additive"). So a merge cannot lean on Add for convergence; it must,
after Add, explicitly `SetRole` to the converged role. **Ruling R2: dst's role
wins, never escalate.** A merge must not be a privilege path. When src's role
was higher the plan carries a warning naming the (org, customer, src_role,
dst_role) so the operator can `SetRole` deliberately afterwards. The last-owner
invariant (`Memberships::Support#sole_owner?`) is checked on dst after every
move; a merge never leaves dst ownerless.

### 3. Conflicting entitlements / plans

`src` and `dst` may sit on different `planid`s with different materialized
entitlements and different per-membership overrides
(`memberships/entitlement_override.rb`). Because entitlements are materialized
from the ORG's plan at `change_role!` time, a member moved from `src` to `dst`
must be re-materialized against `dst`'s plan — the role label carries no
capability. The merge finishes with an `Org::Reconcile` pass over `dst` so every
membership converges on dst's entitlement set. **Ruling R3: dst's plan always
wins.** Promoting dst to src's higher plan is `Org::SetPlan`, run by the
operator BEFORE the merge; it is a billing decision and the merge does not make
it.

### 4. Billing customer conflict

Stripe has no customer-merge API, and this app NEVER calls Stripe from a merge
(same rule as `Org::Delete`'s `:active_subscription` guard and `Org::Reconcile`
being pull-only). Repointing `stripe_customer_id` + its unique index locally
without a Stripe-side write would leave the Stripe customer's metadata naming
an org that no longer exists, so its webhooks would land on nothing. **Ruling
R4: refuse `:billing_conflict` whenever `src` is `billing_live?`** (the
wider-than-active check `Org::Delete` uses), regardless of dst's state. The
operator cancels or moves the subscription in Stripe first, exactly as delete
demands. dst's own subscription, live or not, is untouched. This collapses the
old "one-sided live subscription" question: src live → refuse; only dst live →
fine; neither → fine.

## Sessions

`customers merge` does not move sessions. Session blobs carry src's
`external_id` (`session.rb:725`), `active_sessions` members are sids into those
blobs, and in full mode the SQL session/remember tables mirror them. "Moving"
would mean rewriting encrypted session blobs to claim dst's identity — and a
session minted for src has never passed dst's MFA. The merge destroys every src
session (`Sessions::RevokeAllForCustomer` for the Redis blobs, the
`active_sessions` sidecar and SQL `account_active_session_keys`;
`MergeAuthAccount` for `account_session_keys` / `account_remember_keys`) and the
user signs in again as dst. This is the one place where the merge is
deliberately destructive before step 6; it is safe because src's sessions have
no value to preserve.

## Ordering and transactionality

There is NO transaction that spans this. Redis has no FKs (delete.rb note 3);
full-auth mode adds a Postgres side with no primitive that spans both stores.
The ratified doctrine already exists — `Customers::ChangeEmail`
(`change_email.rb:26-55`): **SQL first inside `db.transaction`, then Redis, then
compensation + a `:partial` terminal status, then DETECTION via a doctor
check.** A merge inherits all four parts and adds a fifth: idempotent re-run.

Forced ordering (each step assumes the prior one committed):

1. **Preview / snapshot** — resolve both sides, compute the full plan, detect
   every refusal condition. Mutates nothing. This is the dry-run output.
2. **Refuse-or-proceed guards** — `:same_org` / `:same_customer`,
   `:src_is_dst_default`, `:billing_conflict` (src live, R4),
   `:domain_collision` (R1), `:colonel` (R7), `:sole_owner` (dst would be left
   ownerless). First trip wins, nothing mutated, mirroring `Org::Delete`'s guard
   ladder.
3. **Move set-valued state onto dst** — memberships (Add + SetRole convergence
   + org-scoped `email_index`), pending invitations, domains (`Transfer` per
   domain; no collapse step, R1 already refused overlaps), receipts (rewrite
   `org_id` / `owner_id` on each record + move the zset), for customer merge
   also secrets (rewrite `Secret#owner_id`, move the zset, move the
   `secrets_active` count) and feature flags. Each move is individually ordered
   and individually isolated: a failure here leaves a HALF-MERGED state that a
   re-run must be able to finish (idempotency), NOT roll back.
4. **Re-point identity + pointers** — `default_org_id` promotion, `role_index`,
   and in full-auth the SQL side, SQL FIRST inside ONE `db.transaction`:
   re-point src's `account_identities` rows to dst's `account_id`; delete src's
   password, MFA, session, remember, lockout rows; set src's `accounts.status_id`
   to closed. Closing src's row here — before Redis teardown — is the fail-safe
   direction: a crash after this commit leaves a src Customer that can no longer
   log in and cannot be autocreated over, and a re-run finishes. A re-run must
   therefore tolerate "src account already closed" and "identity already on
   dst" as no-ops.
5. **Invalidate src sessions** (customer merge; see "Sessions").
6. **Reconcile** — `Org::Reconcile` over dst so entitlements converge.
7. **Destroy the loser** — `Org::Delete` (org merge) / `Customers::Purge`
   (customer merge) on `src`, now emptied. This is the irreversible threshold;
   everything before it was additive-to-dst (or, for sessions and the SQL
   close, destructive only of state with no value) and therefore re-runnable.

The critical property: **steps 3–6 are additive to `dst`, not destructive to
`src`'s data.** `src` is not torn down until step 7, so a crash anywhere in 3–6
leaves `src`'s records intact and a re-run re-computes the plan and finishes.
This is the same "recover by re-running the op, not the doctor" stance as
`Org::TransferOwnership`'s promote-then-demote window.

What is NON-ATOMIC and therefore needs a repair/idempotency story:

- **Receipt / secret re-pointing** — no primitive; a partial move leaves some
  records with `owner_id` / `org_id` on the dead `src` objid. `Org::Delete`
  today just abandons receipts (note 3). A merge must instead move them, and a
  doctor check must find any left behind (a record whose owner does not load,
  or whose owner's zset does not contain it).
- **The SQL side (full-auth)** — SQL commit then Redis is the ChangeEmail hazard
  verbatim; a `:partial` merge needs an `:auth_email_drift`-style check, plus a
  new one: an `account_identities` row whose `account_id` is a closed account
  (an identity the merge never re-pointed).
- **The `secrets_active` counter** — moved as a number, not re-derived; a
  partial move leaves it split across two customers. The existing up-drift
  tolerance applies (readers already treat the index as candidates).
- **The members/participations pair** — memory: these drift; repair is
  remove+add. A merge that moves memberships must leave both structures aligned
  or the `ensure_member_through_models` chore will see drift.

## Audit requirements (ADR-023)

- **Real actor, never fabricated** (ADR-023): the operator's public identity
  (colonel extid or CLI sentinel), never an objid, never a guessed value.
- **Both sides recorded**: each merge event's `detail` must name BOTH `src` and
  `dst` extids, so the trail answers "where did this org/account go" and "what
  was folded into this one" from either end. For a customer merge the top-level
  `detail` also carries src's obscured email and the src field values that dst's
  won over (R6), since that is the only place they survive.
- **Traceable through the composed ops**: like `Org::TransferOwnership` (three
  events per transfer, by design D26), a merge will emit the top-level
  `organization.merge` / `customer.merge` event PLUS the sub-events from each
  composed `Memberships::*`, `Domains::Transfer`, `Org::Delete` call. That is a
  feature — the sub-events make the merge replayable. Adapters MUST NOT
  double-audit.
- **Eviction discipline**: the audit set is COUNT-capped at 10,000 with no TTL
  (`colonel_audit_event.rb:116`). A merge fans out roughly two sub-events per
  moved member (Add + SetRole), so a 200-member merge is ~4% of the entire
  trail. **Ruling R8: keep the per-move sub-events** — they are the replay log
  — and put counts (members, domains, receipts, secrets, identities) in the
  top-level event so it stands alone if the sub-events are evicted. Because
  merge is operator-only (unlike customer-facing `Org::Delete`),
  refusal-auditing is acceptable here — follow `TransferOwnership` (audit
  refusals), not `Org::Delete` (suppress them).

## Safety model — dry-run first

Consistent with `Domains::Remove`, `Domains::Transfer`, `Org::Delete` and
`Org::TransferOwnership`: `dry_run:` defaults to **true**. A dry run computes the
complete plan — every membership move with its convergence warning, every
domain transfer, every receipt and secret count, the identity rows to re-point,
the billing verdict, the default-org promotion — and returns it as a `Result`
while mutating and auditing NOTHING. `dry_run` rides in the audit `detail` so a
blown-up preview is distinguishable from a blown-up apply (the `Org::Delete` /
`Domains::Transfer` precedent). The apply path is entered only with
`dry_run: false` and echoes the same plan, so the operator's confirmation prompt
and the receipt read identically.

## Compose vs. new — the operation surface

**Compose (exists, reuse verbatim):**

- `Onetime::Operations::Memberships::Add` / `Remove` / `SetRole` — membership
  moves + entitlement materialization + org-scoped `email_index`.
- `Onetime::Operations::Memberships::Support#sole_owner?` — the last-owner
  invariant, so a merge never orphans `dst`.
- `Onetime::Operations::Domains::Transfer` — per-domain reassignment (AFTER the
  merge's `:domain_collision` guard, which Transfer does not have).
- `Onetime::Operations::Org::Reconcile` — final entitlement/billing convergence
  on `dst`.
- `Onetime::Operations::Org::Delete` — tearing down the emptied `src` org.
- `Onetime::Operations::Org::TransferOwnership` — when `src` and `dst` are owned
  by different customers and ownership must move first.
- `Onetime::Operations::Sessions::RevokeAllForCustomer` — destroys every
  session in src's `active_sessions` sidecar AND the SQL
  `account_active_session_keys` rows (`revoke_all_for_customer.rb:228-237`);
  the merge calls it on src in step 5. `account_session_keys` and
  `account_remember_keys` are not its business; they go with
  `MergeAuthAccount`.
- `Auth::Operations::Customers::Purge` — tearing down the emptied `src` customer
  (Redis only — see the SQL primitive below).
- `Auth::Operations::Customers::ReconcileRoleIndex` — repairing `role_index` on
  `dst` after a role move.

**New operations required (name them; DO NOT implement):**

- `Onetime::Operations::Org::Merge` — the org-merge orchestrator. Owns the
  guard ladder, pending-invitation moves, receipt re-pointing, default-org
  promotion, and the ordered fan-out over the composed ops. Lives in
  `lib/onetime/operations/org/` beside `delete.rb` (model-owned verbs, D10).
- `Auth::Operations::Customers::Merge` — the customer-merge orchestrator.
  Composes `Org::Merge` for the two personal workspaces, moves
  receipts/secrets/flags (rewriting `owner_id`), invalidates src's sessions,
  calls the SQL primitive below, then `Purge`s `src`. Lives in
  `apps/web/auth/operations/customers/`.
- `Auth::Operations::MergeAuthAccount` — the SQL-only, single-transaction
  primitive for step 4: re-point `account_identities`, drop src's credential /
  MFA / session / lockout rows, close src's `accounts` row. Idempotent (already
  closed / already re-pointed are no-ops). Returns what it changed so the
  orchestrator's audit `detail` can count identities moved. Lives beside
  `bind_sso_identity.rb`, whose (provider, issuer, uid) discipline it must keep.

## Primitives that are insufficient (real gaps, not wiring)

1. **No receipt / secret re-pointing primitive.** `Receipt#org_id` /
   `#owner_id`, `Secret#owner_id`, and the `organization:<objid>:receipts` /
   `customer:<objid>:receipts` / `customer:<objid>:secrets` zsets are moved by
   NOTHING today — `Org::Delete` explicitly abandons receipts (delete.rb note 3,
   the #4205-family dangling ref). A merge that dropped them on the floor would
   lose the very history it is consolidating, and a zset-only move is worse
   than none (dst lists what it cannot own; counters drift). Needs a bulk
   re-point helper that rewrites the back-pointer AND moves the zset member,
   plus a doctor check for stragglers.
2. **`Customers::Purge` is Redis-only.** `DeleteCustomer` calls
   `customer.destroy!` and nothing else (`delete_customer.rb:85`); the CLI
   prints "clean up orphaned SQL accounts separately"
   (`purge_command.rb:212`). Composed as-is at the end of a merge, it leaves
   src's `accounts` row open, and `external_identity_check_columns :autocreate`
   plus the `create_customer` hook recreate the Customer — with a new default
   workspace — on the next login. The merge cannot use Purge without the SQL
   close in front of it.
3. **No SQL identity move.** `account_identities` rows are bound by
   `BindSsoIdentity` and never re-pointed; the MFA, session and credential
   tables have no cross-account move and, for `webauthn_user_ids`, cannot have
   one. `MergeAuthAccount` is new.
4. **`Memberships::Add` does not converge roles.** `:no_change` on an existing
   member leaves the role untouched by design, so role convergence is the
   merge's own responsibility (Add then SetRole).
5. **No pending-invitation mover.** Invites are org-keyed through-hashes with
   tokens that encode the org; `Org::Delete` destroys them, nothing moves them.
6. **No default-org promotion primitive.** `Org::Delete` clears `default_org_id`
   but never promotes a survivor (delete.rb note 4) — a merge of personal
   workspaces MUST promote, and that verb does not exist.
7. **`Domains::Transfer` has no drift guard.** It updates `org_id` + owners +
   collections but never checks `display_domain_index`; the merge's
   `:domain_collision` refusal covers it, and a doctor check should exist
   independently of merge.

## Rulings (proposed — ratify before build)

Every question the first draft left open has a proposed answer. Each is the
simpler, non-escalating choice; the alternative is noted where it was seriously
considered.

- **R1 — Domain collision: refuse.** Two records for one display domain are
  index drift, not a merge branch; refuse `:domain_collision` and let the
  operator repair. (Rejected: a state-based survivor rule — clever, and the
  kind of rule that surprises.)
- **R2 — Role convergence: dst's role wins, never escalate.** Warn in the plan
  when src's role was higher. (Rejected: highest-privilege-wins — a silent
  escalation path through an operator verb.)
- **R3 — Plan precedence: dst's plan wins.** Promotion is `Org::SetPlan`, run
  first.
- **R4 — Billing: refuse if src is live.** No local repoint of Stripe ids
  without a Stripe-side write, ever. Only-dst-live is fine. Supersedes both the
  "may src's linkage move" and "one-sided live subscription" questions.
- **R5 — `created_by` / `invited_by` dangle.** Both are immutable-or-provenance
  objids (ADR-012; transfer.rb D32). After a customer merge they may name the
  purged src. Accept the permanent `standardize_owner_id` Branch-3b warning,
  exactly as transfers do; the audit event's src→dst mapping is the resolution.
- **R6 — Customer field precedence: dst wins everything.** `signup_domain_id`
  and `provisioning_origin` are provenance and are not touched on dst; src's
  values are recorded in the audit `detail`. `last_login` takes the max.
  Feature flags: dst's value wins per key; keys only src had are copied.
- **R7 — Colonel: refuse if either side is a colonel.** Colonel accounts are
  few and are merged by hand if ever. Removes the escalation question entirely
  rather than adjudicating it.
- **R8 — Audit fan-out: keep sub-events, summarize in the top-level event.**
  Accept the eviction pressure at the 10k cap; merge is rare and operator-only.
- **R9 — Reversibility: none.** Step 7 is the hard threshold, matching delete's
  "no cascade, no transaction, no undo" (delete.rb note 3). Dry-run is the only
  safety net.
- **R10 — Sessions: invalidate, never move** (see "Sessions").
- **R11 — src's password and MFA are dropped**, not merged. The user keeps
  dst's credentials and dst's MFA; src's SSO identities become dst's. The plan
  says so in the confirmation prompt, because it is the one thing the human
  behind the accounts will notice.

## Common thread

Mirrors `deleting-an-organization.md`'s closing shape: (a) a merge moves
set-valued state onto `dst` additively and only tears `src` down at the very
end, so a crash is recoverable by re-running the op, never by hand-repair; (b)
the merge NEVER calls Stripe and refuses when `src` bills; (c) entitlements and
roles follow from re-materialization against dst's plan and dst's role, never
from copying labels or taking the higher one; (d) receipts, secrets and the
full-auth SQL side are the places with no primitive and no atomicity, so they
carry the idempotency + doctor-detection burden — and the SQL side must be
closed BEFORE the Redis purge or the duplicate resurrects itself; (e) merge is
operator-only and audited on both success and refusal, with both `src` and
`dst` named in every event.
