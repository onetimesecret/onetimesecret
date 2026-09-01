# Merging Organizations and Customers

Status: draft notes — the support-commands audit flagged merge as the one
capability that exists at NO layer (no model method, no Operation, no CLI verb,
no colonel endpoint). This document specifies what a merge must reconcile and
the decisions that must be ratified before anyone builds it. It is a sibling to
`deleting-an-organization.md`: same house style, same "options and complications,
no design decided yet" posture. Nothing here is implemented.

## Scope

Two verbs, one shared shape:

- `org merge <src> <dst>` — fold organization `src` into `dst`, then delete
  `src`. Every member, domain, receipt, entitlement and (where reconcilable)
  billing linkage that hangs off `src` ends up on `dst`.
- `customers merge <src> <dst>` — fold customer account `src` into `dst`. Moves
  `src`'s org memberships, receipts, secrets, sessions and personal/default
  org, then purges `src`.

Both are operator-only (CLI + colonel), both are irreversible past the apply
threshold, and both are dry-run-first (see "Safety model").

### The root-cause motivator: duplicate personal orgs

The forcing case is not team consolidation. It is that a single human ends up
with **two accounts** — a native signup plus an SSO-minted one, or two SSO
identities — and therefore two `is_default` personal workspaces
(`organization.rb:71`). `CreateDefaultWorkspace` mints one per account and
adopts orphans by `contact_email`, so the duplicates accrete silently. Support
has no way to say "these are the same person, make them one." `customers merge`
is that verb; `org merge` is the half of it that reconciles the two personal
workspaces, and is independently useful for teams that stood up two orgs by
mistake. Neither can be built without the other being at least specified,
because a customer merge that leaves two default orgs behind has not merged
anything the user can see.

## Why nothing composes today

The toolbox has SINGLE-record movers, not set movers. The gap is not "write a
merge Operation that calls the existing ones in a loop" — three of the moves a
merge needs have **no primitive at all**, and two of the primitives that exist
refuse or no-op on exactly the collision a merge creates. Enumerated in
"Primitives that are insufficient" below.

## Inventory — what a merge reconciles, per subsystem

Every row is a distinct data structure a merge touches. `src`/`dst` are the
losing/surviving side. "Primitive" names the existing Operation or model method
that moves one such record, or `— none —` where none exists.

### Organization merge (`org merge src dst`)

| Subsystem | Structure(s) | Primitive | Collision case |
|---|---|---|---|
| Memberships | `org.members` zset + `customer.participations` reverse index + the `OrganizationMembership` through-hash (`organization_membership.rb:516-517`) | `Memberships::Add` / `Remove` / `SetRole` | Customer is a member of BOTH orgs → duplicate membership; roles differ → convergence decision |
| Entitlements | per-membership `materialized_entitlements` + `entitlements_plan/grants/revokes` sub-keys, materialized only via `change_role!` (`organization_membership.rb:258-269`) — the role LABEL alone grants nothing | re-materialize through `Memberships::Add`/`SetRole`, or `Org::Reconcile` | src and dst on different plans → which entitlement set survives |
| Domains | `org.domains` zset + `CustomDomain#org_id` + `CustomDomain.owners` class-hashkey (`custom_domain.rb:87,92`) | `Domains::Transfer` (moves ONE) | same-`display_domain` records on both sides → unique-index collapse (below) |
| Domain uniqueness | `CustomDomain.display_domain_index` — `unique_index :display_domain`, "domain can only exist once" (`custom_domain.rb:140`) | `update_display_domain` (`custom_domain.rb:194`) | two `CustomDomain` records, same `display_domain`, one per org → index can hold only one |
| Receipts | `Receipt#org_id` + the `organization:<objid>:receipts` zset (`receipt.rb:52,74`) | `— none —` | receipts silently keep keying off the dead `src` objid (the `Org::Delete` dangling-ref, delete.rb note 3) |
| Billing / Stripe | org fields `stripe_customer_id`, `stripe_subscription_id`, `billing_email`, `email_hash` + their four unique/multi indexes (`with_organization_billing.rb:63-106`) | `Org::Reconcile` (re-pulls ONE org's sub) | both orgs `billing_live?` → two live Stripe customers, unmergeable via API |
| Ownership | `owner_id` (deprecated) + `created_by` (immutable, ADR-012, `organization.rb:68-69`) + the `role:'owner'` membership | `Org::TransferOwnership` | src and dst owned by different customers |
| Default-workspace | `org.is_default` label + `customer.default_org_id` pointer (`organization.rb:71`, `customer.rb:201`) | `— none —` (delete clears, never promotes) | merging one personal workspace into another orphans a `default_org_id` |
| Identity index | `contact_email_index` unique index (`organization.rb:63`) | `delete!` override releases it (`organization.rb:427-431`) | src and dst share a `contact_email` — index holds one |
| Registry | `Organization.instances` class zset | `instances.remove` (`org/delete.rb` step 2) | — |
| Audit | `ColonelAuditEvent`, COUNT-capped, no TTL | `ColonelAuditEvent.record` | eviction pressure (see "Audit") |

### Customer merge (`customers merge src dst`)

| Subsystem | Structure(s) | Primitive | Collision case |
|---|---|---|---|
| Org memberships | `customer.participations` + each `org.members` entry + through-hash | `Memberships::Add`/`Remove` per org | src and dst both members of org X → duplicate; role convergence |
| Personal/default org | src's `is_default` org + `default_org_id` pointer | delegate to `org merge` | two personal workspaces → this is the root case; needs `org merge` |
| Receipts | `customer.receipts` zset + `Receipt#owner_id` (`receipt.rb:34`, `customer.rb:102`) | `— none —` | — |
| Secrets | `customer.secrets` zset + `secrets_active` counter (`customer.rb:112-122`) | `— none —` | counter must move with the zset or drift |
| Sessions | `customer.active_sessions` zset (`customer.rb:129`) | `— none —` | — |
| Feature flags | `customer.feature_flags` hashkey (`customer.rb:130`) | `— none —` | conflicting per-flag values |
| Identity index | `unique_index :email → email_index` (`customer.rb:172`, case-sensitive, un-normalized `customer.rb:343,353`) | freed on `destroy!` | src email collides with, or must be freed for, dst |
| Role index | `multi_index :role → role_index` (`customer/features/role_index.rb:27`) | `Customers::ReconcileRoleIndex` | src is `colonel`, dst is not → privilege escalation risk |
| Account fields | `planid`, `signup_domain_id`, `provisioning_origin`, `locale`, `notify_on_reveal`, `last_login` (`customer.rb:187-212`) | `— none —` | last-writer / which value wins |
| Full-auth SQL row | Postgres `accounts` row, `external_id = customer.extid` (memory: authdb-customer linkage) | `— none —` (no cross-store merge primitive) | two `accounts` rows, `citext` partial-unique email `where status_id in (1,2)` |
| Deprecated billing | `customer.stripe_customer_id` (`customer/features/deprecated_fields.rb:31`) | `migrate_billing_to_org` (`migration_fields.rb`) | legacy accounts still carry it |
| Audit | `customer.purge` verb precedent (`customers/purge.rb`) | `ColonelAuditEvent.record` | — |

## The four collision cases that need a ruling

### 1. Same-`display_domain` collapse

`display_domain_index` is globally unique — a `display_domain` maps to exactly
one `CustomDomain` record. A merge creates a collision when `src` and `dst` each
own a record for the SAME display domain (e.g. `dst` is the real org and `src` is
a stale/orphaned duplicate that also holds `example.com`). Naively moving `src`'s
domain via `Domains::Transfer` sets its `org_id` to `dst` but the unique index
still points at ONE of the two records. `Domains::Transfer` has no
display-domain-collision guard — its only refusal is `:mismatch`
(`domains/transfer.rb`). The merge must, BEFORE transferring, detect display
collisions between the two domain sets and COLLAPSE each pair: pick a survivor,
re-point the loser's receipts (`Receipt#domain_id` + the domain's receipts
zset), then `Domains::Remove` the loser. **Open: which record survives** — dst's,
or the `verified`/`resolving` one regardless of side?

### 2. Duplicate membership + role convergence

A customer who belongs to both orgs (org merge) — or two customers who both
belong to org X (customer merge) — must not end with two through-models for the
same (org, customer) pair. `Memberships::Add` is idempotent but returns
`:no_change` WITHOUT touching the role (`memberships/add.rb`, "add is strictly
additive"). So a merge cannot lean on Add for convergence; it must, after Add,
explicitly `SetRole` to the converged role. **Open: convergence rule** — highest
privilege wins (owner > admin > member), or dst's existing role always wins?
Highest-privilege is the safe-for-the-user default but can silently escalate.

### 3. Conflicting entitlements / plans

`src` and `dst` may sit on different `planid`s with different materialized
entitlements and different per-membership overrides
(`memberships/entitlement_override.rb`). Because entitlements are materialized
from the ORG's plan at `change_role!` time, a member moved from `src` to `dst`
must be re-materialized against `dst`'s plan — the role label carries no
capability. The merge should finish with an `Org::Reconcile` pass over `dst` so
every membership converges on dst's entitlement set. **Open: does dst's plan
always win**, or does a higher `src` plan get promoted onto dst first (a billing
decision, not a merge decision)?

### 4. Billing customer conflict

If BOTH orgs are `billing_live?` (`organization.rb`, the wider-than-active check
`Org::Delete` uses), there are two live Stripe customers with two subscriptions.
Stripe has no customer-merge API, and this app NEVER calls Stripe from a merge
(same rule as `Org::Delete`'s `:active_subscription` guard and `Org::Reconcile`
being pull-only). The merge must REFUSE (`:billing_conflict`) and tell the
operator to cancel or move the subscription in Stripe first, exactly as delete
refuses `:active_subscription`. A one-sided live subscription is fine: it stays
on `dst`, or moves with the org if `dst` had none. **Open: may `src`'s Stripe
linkage move to `dst` when `dst` has none** — is repointing `stripe_customer_id`
+ the unique index safe without a Stripe-side write? Likely yes (the index is
local), but it is a billing-team ratification, not a merge-author call.

## Ordering and transactionality

There is NO transaction that spans this. Redis has no FKs (delete.rb note 3);
full-auth mode adds a Postgres row with no primitive that spans both stores. The
ratified doctrine already exists — `Customers::ChangeEmail`
(`change_email.rb:26-55`): **SQL first inside `db.transaction`, then Redis, then
compensation + a `:partial` terminal status, then DETECTION via a doctor
check.** A merge inherits all four parts and adds a fifth: idempotent re-run.

Forced ordering (each step assumes the prior one committed):

1. **Preview / snapshot** — resolve both sides, compute the full plan, detect all
   four collision classes. Mutates nothing. This is the dry-run output.
2. **Refuse-or-proceed guards** — `:billing_conflict` (both live),
   `:same_org`/`:same_customer`, `:src_is_dst_default` and the like. First trip
   wins, nothing mutated, mirroring `Org::Delete`'s guard ladder.
3. **Move set-valued state onto dst** — memberships (Add + SetRole convergence),
   domains (collapse duplicates, then Transfer), receipts (re-point + move zset),
   for customer merge also secrets/sessions/flags. Each move is individually
   ordered and individually isolated: a failure here leaves a HALF-MERGED state
   that a re-run must be able to finish (idempotency), NOT roll back.
4. **Re-point identity + pointers** — `default_org_id` promotion, `contact_email`
   / `email_index` resolution, `role_index`, and in full-auth the `accounts`
   row (SQL FIRST, per doctrine).
5. **Reconcile** — `Org::Reconcile` over dst so entitlements converge.
6. **Destroy the loser** — `Org::Delete` (org merge) / `Customers::Purge`
   (customer merge) on `src`, now emptied. This is the irreversible threshold;
   everything before it was additive-to-dst and therefore re-runnable.

The critical property: **steps 3–5 are additive to `dst`, not destructive to
`src`.** `src` is not torn down until step 6, so a crash anywhere in 3–5 leaves
`src` intact and a re-run re-computes the plan and finishes. This is the same
"recover by re-running the op, not the doctor" stance as
`Org::TransferOwnership`'s promote-then-demote window.

What is NON-ATOMIC and therefore needs a repair/idempotency story:

- **Receipt re-pointing** — no primitive; a partial move leaves some receipts on
  the dead `src` objid. `Org::Delete` today just abandons them (note 3). A merge
  must instead move them, and a doctor check must find any left behind.
- **The `accounts` row (full-auth)** — SQL commit then Redis is the ChangeEmail
  hazard verbatim; a `:partial` merge needs an `:auth_email_drift`-style check.
- **The members/participations pair** — memory: these drift; repair is
  remove+add. A merge that moves memberships must leave both structures aligned
  or the `ensure_member_through_models` chore will see drift.

## Audit requirements (ADR-023)

- **Real actor, never fabricated** (ADR-023): the operator's public identity
  (colonel extid or CLI sentinel), never an objid, never a guessed value.
- **Both sides recorded**: each merge event's `detail` must name BOTH `src` and
  `dst` extids, so the trail answers "where did this org/account go" and "what
  was folded into this one" from either end.
- **Traceable through the composed ops**: like `Org::TransferOwnership` (three
  events per transfer, by design D26), a merge will emit the top-level
  `organization.merge` / `customer.merge` event PLUS the sub-events from each
  composed `Memberships::*`, `Domains::Transfer`, `Org::Delete` call. That is a
  feature — the sub-events make the merge replayable. Adapters MUST NOT
  double-audit.
- **Eviction discipline**: the audit set is COUNT-capped with no TTL
  (`ColonelAuditEvent`). A merge fans out many sub-events, so a merge storm is a
  real eviction primitive. Because merge is operator-only (unlike customer-facing
  `Org::Delete`), refusal-auditing is acceptable here — follow
  `TransferOwnership` (audit refusals), not `Org::Delete` (suppress them). **Open:
  cap the sub-event fan-out** for a merge that moves hundreds of members?

## Safety model — dry-run first

Consistent with `Domains::Remove`, `Domains::Transfer`, `Org::Delete` and
`Org::TransferOwnership`: `dry_run:` defaults to **true**. A dry run computes the
complete plan — every membership move, every domain collapse, every receipt
count, the billing verdict, the default-org promotion — and returns it as a
`Result` while mutating and auditing NOTHING. `dry_run` rides in the audit
`detail` so a blown-up preview is distinguishable from a blown-up apply (the
`Org::Delete` / `Domains::Transfer` precedent). The apply path is entered only
with `dry_run: false` and echoes the same plan, so the operator's confirmation
prompt and the receipt read identically.

## Compose vs. new — the operation surface

**Compose (exists, reuse verbatim):**

- `Onetime::Operations::Memberships::Add` / `Remove` / `SetRole` — membership
  moves + entitlement materialization.
- `Onetime::Operations::Memberships::Support#sole_owner?` — the last-owner
  invariant, so a merge never orphans `dst`.
- `Onetime::Operations::Domains::Transfer` — per-domain reassignment (AFTER the
  merge resolves display collisions Transfer does not handle).
- `Onetime::Operations::Domains::Remove` — dropping a collapsed duplicate domain.
- `Onetime::Operations::Org::Reconcile` — final entitlement/billing convergence
  on `dst`.
- `Onetime::Operations::Org::Delete` — tearing down the emptied `src` org.
- `Onetime::Operations::Org::TransferOwnership` — when `src` and `dst` are owned
  by different customers and ownership must move first.
- `Auth::Operations::Customers::Purge` — tearing down the emptied `src` customer.
- `Auth::Operations::Customers::ReconcileRoleIndex` — repairing `role_index` on
  `dst` after a role move.

**New operations required (name them; DO NOT implement):**

- `Onetime::Operations::Org::Merge` — the org-merge orchestrator. Owns the
  guard ladder, the display-domain collapse, receipt re-pointing, default-org
  promotion, and the ordered fan-out over the composed ops. Lives in
  `lib/onetime/operations/org/` beside `delete.rb` (model-owned verbs, D10).
- `Auth::Operations::Customers::Merge` — the customer-merge orchestrator.
  Composes `Org::Merge` for the two personal workspaces, moves
  receipts/secrets/sessions/flags, resolves the `email_index`, handles the
  full-auth `accounts` row (SQL-first per ChangeEmail doctrine), then `Purge`s
  `src`. Lives in `apps/web/auth/operations/customers/`.

## Primitives that are insufficient (real gaps, not wiring)

1. **No receipt re-pointing primitive.** `Receipt#org_id` / `#owner_id` and the
   `organization:<objid>:receipts` / `customer:<objid>:receipts` zsets are moved
   by NOTHING today — `Org::Delete` explicitly abandons them (delete.rb note 3,
   the #4205-family dangling ref). A merge that dropped receipts on the floor
   would lose the very history it is consolidating. Needs a new bulk re-point
   helper + a doctor check for stragglers.
2. **No secrets/sessions mover.** `customer.secrets` (+ the `secrets_active`
   counter that can only drift together, `customer.rb:112-122`),
   `customer.active_sessions`, and `customer.feature_flags` have no
   cross-customer move path.
3. **`Domains::Transfer` is not collision-aware.** It updates `org_id` + owners +
   collections but has no `display_domain_index` guard, so it cannot resolve two
   records claiming the same display domain — the merge must collapse them first.
4. **`Memberships::Add` does not converge roles.** `:no_change` on an existing
   member leaves the role untouched by design, so role convergence is the
   merge's own responsibility (Add then SetRole).
5. **No cross-store customer merge.** The full-auth `accounts` row has no
   merge/move primitive; the ChangeEmail doctrine (SQL-first + `:partial` +
   doctor detection) is the pattern to extend, not a primitive to call.
6. **No default-org promotion primitive.** `Org::Delete` clears `default_org_id`
   but never promotes a survivor (delete.rb note 4) — a merge of personal
   workspaces MUST promote, and that verb does not exist.

## Open questions to ratify before build

1. **Domain survivor rule** (collision case 1): dst's record always, or the
   `verified`/`resolving` one regardless of side?
2. **Role convergence rule** (case 2): highest-privilege-wins (safe-for-user,
   risks silent escalation) vs. dst's-role-wins (predictable, can demote)?
3. **Plan/entitlement precedence** (case 3): does dst's plan always win, or is a
   higher src plan promoted onto dst first (billing decision)?
4. **Stripe linkage move** (case 4): may `src`'s `stripe_customer_id` + unique
   index repoint to `dst` when `dst` has none, with no Stripe-side write?
   Billing-team call.
5. **`created_by` on merge**: immutable per ADR-012 (delete.rb / transfer.rb
   D32), so a merged org's `created_by` keeps pointing at a customer who may
   themselves be the merged-away `src`. Is a permanent `standardize_owner_id`
   Branch-3b warning on merged orgs acceptable, as it is for transfers?
6. **Customer field precedence** (locale, notify_on_reveal, planid,
   signup_domain_id, provisioning_origin): last-writer, dst-wins, or
   field-by-field? provisioning_origin and signup_domain_id are provenance —
   arguably must NOT change.
7. **`colonel` role merge**: if `src` is a colonel and `dst` is not (or vice
   versa), does the merged account become a colonel? A merge must not be a
   privilege-escalation path; probably refuse when roles differ at the colonel
   tier.
8. **Audit fan-out cap** (Audit section): does a merge moving hundreds of members
   flood the capped audit set, and if so does the top-level event summarize
   instead of emitting one sub-event per move?
9. **Reversibility window**: is there ANY undo, or is step 6 (destroy `src`) the
   hard, documented, irreversible threshold — matching delete's "no cascade, no
   transaction, no undo" (delete.rb note 3)? Default assumption: irreversible,
   dry-run is the only safety net.
10. **`src` with a live one-sided subscription**: does it move with the org, or
    does the merge refuse until billing is settled even when only ONE side is
    live?

## Common thread

Mirrors `deleting-an-organization.md`'s closing shape: (a) a merge moves
set-valued state onto `dst` additively and only tears `src` down at the very
end, so a crash is recoverable by re-running the op, never by hand-repair; (b)
the merge NEVER calls Stripe and refuses when both sides bill; (c) entitlements
follow from re-materialization against dst's plan, never from copying role
labels; (d) receipts and the full-auth `accounts` row are the two places with no
primitive and no atomicity, so they carry the idempotency + doctor-detection
burden; (e) merge is operator-only and audited on both success and refusal, with
both `src` and `dst` named in every event.
