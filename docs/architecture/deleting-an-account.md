# Deleting an Account

Account deletion is a lifecycle operation, not a direct `Customer#destroy!`.
The account, its authentication identity, memberships, and owned workspaces can
span Redis/Valkey, the authentication database, and external billing systems.
The operation therefore plans and validates the entire relationship set before
performing irreversible writes.

## Administrative purge contract

Colonel `DELETE /api/colonel/users/:user_id` and
`bin/ots customers purge-one` use the same customer purge lifecycle. They
differ only in discovery depth (see *Discovery depth*): the CLI command sweeps
the global registries, the endpoint does not.

### Preflight policy

Preflight discovers relationships from all available directions, including:

- customer participation references;
- the customer's own `default_org_id` pointer;
- organization member sets and membership records;
- organization ownership and instance indexes;
- the customer email in `Organization.contact_email_index`;
- domain records that refer to an organization.

`contact_email_index` is keyed **verbatim**: `Organization.create!` reserves the
address exactly as the caller supplied it, and the billing-email sync writes
whatever Stripe returned. Every lookup therefore goes through
`Organization.find_contact_email_claims`, which probes the raw and normalized
spellings and falls back to a bounded case-insensitive `HSCAN`. A normalized
`HGET` would report a claimed address as unclaimed and a correct holder as
drifted. Provisioning takes the first exact hit; the preflight passes
`exhaustive: true` so an exact hit cannot hide a second spelling held by a
different organization, which it refuses as `contact_email_index_ambiguous`.

#### Discovery depth

Discovery is **shallow** by default: it reaches organizations through the
customer's own reverse indexes (participations, `organization_instances`,
`default_org_id`) and the contact-email claim, and keeps every
per-organization drift check. Only the CLI single-account path
(`bin/ots customers purge-one`) passes `deep: true`, which additionally sweeps
the global `Organization`, `OrganizationMembership` and `CustomDomain`
registries to catch a reference no reverse index points at — an organization
whose `owner_id` names the customer but which is absent from their
participations. Those sweeps are whole-registry reads, and the lifecycle
re-runs preflight once per planned action plus three times during teardown, so
they are never used on a request path — the colonel endpoint
(`DELETE /api/colonel/users/:id`) is shallow, like self-service closure — or
in the bulk sweep. An operator who needs the global sweep for one account runs
`purge-one` from the CLI. Deep mode runs the sweeps at the initial plan and the
final post-teardown validation; the intermediate revalidations stay shallow.

Shallow discovery derives an organization's membership rows from the
organization's own `members` set (plus the purge target's row, loaded
directly). A live row whose customer is missing from that set is reachable
only through the registry, so on a request path — self-service closure and
the colonel endpoint — it is not seen and a shared workspace could read as
sole-owned. This residual is accepted there: the through-model writes the row
and the set together, so the state is drift, not a normal write, and the deep
CLI path does refuse it.
The bulk sweep does not accept it: it captures the membership registry **once
per run** (`MembershipSnapshot`, a parse of the registry's sorted set with no
per-row load) and every candidate's shallow preflight unions those rows with
the `members` set. Snapshot rows are re-loaded when used, so a row removed by
an earlier candidate of the same run is skipped rather than reported as drift.

A relationship must be complete and unambiguous before purge can execute. The
operation may plan only these automatic actions:

1. remove a consistent, non-owner membership through the canonical membership
   removal operation; or
2. delete a sole-owned personal default workspace through the canonical
   organization deletion operation when its relationships, migration state,
   and billing state pass the checks below.

Preflight refuses before account teardown when an owned workspace has domains,
other members, or ownership/membership/index drift. It also refuses when a scan
fails and the evidence is incomplete. Operators must resolve the reported
condition before retrying; purge does not repair records as a side effect.

Billing checks distinguish history from unresolved state:

- Live subscription statuses (`active`, `trialing`, `past_due`, `unpaid`) block,
  including federated subscriptions without local Stripe identifiers.
- Known non-live statuses (`canceled`, `incomplete`, `incomplete_expired`,
  `paused`) permit historical billing fields. A retained Stripe customer ID,
  billing email, federation timestamp, complimentary marker, or stale plan
  alone does not block.
- Unknown nonblank subscription statuses, a subscription ID without a status,
  and any pending currency-migration intent still block.

These checks use locally stored billing state, not a Stripe API request. They
retain the canonical organization deletion operation's liveness limitations;
for example, an incomplete payment can subsequently become active. Purge does
not cancel subscriptions or delete Stripe records. Billing fields remain intact
until canonical organization destruction removes their local index claims.

Migration checks apply to the customer and each owned workspace. A blank status
or `completed` permits provenance fields such as source identifiers, timestamps,
and comments. Blank status is not proof of completion: it also occurs on native
records and the `create_from_v1_customer!` path. Any other explicit migration
status, including `pending`, `migrating`, `failed`, `skipped`, or an unknown
value, blocks. Completing a migration does not require erasing its provenance.

What does **not** refuse: content of the sole-owner default workspace that goes
with it — the workspace description, outstanding invitations the departing
owner sent, a contact address that diverged from the account's (the
billing-email sync writes that field), and the workspace's receipts. None of it
belongs to another party, so none of it is a reason to refuse an erasure
request; it is reported on the planned action as `notes` so an operator can
still see what a purge removed. Receipts are a note, not a deletion: no purge
path destroys `Receipt` or `Secret` records. Deleting the organization drops its
receipt index and deleting the customer drops theirs; the records themselves
are TTL-bound (a receipt lives twice its secret's TTL) and expire on that
schedule. Refusing over receipts would make erasure unavailable to any account
that used the product in the last two weeks.
`owner_id` must match the customer's current objid or custid, with active owner
membership and the other relationship checks still required. Creator attribution
also accepts the customer's preserved `v1_custid`; it does not use the current
email address alone as an identity alias. If the migration generator omitted
`created_by`, preflight requires a completed organization migration whose
`v1_identifier` equals the target customer's object key and whose
`v1_source_custid` matches that customer's current or preserved identifier.
Missing or contradictory evidence still refuses. Purge never rewrites creator
attribution to make these checks pass.

A customer email matching an organization contact email is discovery evidence,
not authorization to attach that organization to another account.

## Lifecycle ordering

The ordering is deliberate:

1. **Complete read-only preflight.** Discover every relevant relationship and
   produce blockers plus a cleanup plan.
2. **Revalidate before each cleanup mutation.** If the plan changed, stop.
3. **Organization cleanup.** Delete an approved personal workspace and/or
   remove approved non-owner memberships through canonical operations.
4. **Post-cleanup revalidation.** Require an executable plan with no remaining
   actions or blockers.
5. **Account teardown.** Revalidate immediately before each account mutation,
   revoke sessions, close and strip the SQL authentication identity in full auth
   mode, and delete the Redis/Valkey customer last.
6. **Post-teardown reference validation.** Scan again so a concurrent workspace
   write cannot be reported as a clean purge.
7. **Audit completion.** Record the final administrative purge event.

Redis/Valkey and the authentication database do not provide one transaction
across this sequence. Revalidation narrows the race window; structured partial
results make any operation that crossed a mutation boundary visible.

## Result semantics

The lifecycle result includes `status`, `blockers`, completed `actions`,
`planned_actions`, current `stage`, and `completed_stages`.

- `success`: all policy-approved cleanup and account teardown completed, final
  reference validation passed, and the audit event was recorded.
- `refused`: preflight or revalidation stopped the operation before any cleanup
  action completed. The customer remains available for remediation and retry.
- `partial`: one or more cleanup or teardown stages completed before a later
  guard, revalidation, or write failed. Do not report deletion as successful and
  do not retry blindly; inspect `stage`, `completed_stages`, `actions`, and
  `blockers` first.
- `not_found`: the target disappeared or could not be deleted as the resolved
  target. This is not proof of a successful purge.

Only `success` permits the admin UI to show a success notification and leave the
customer page. A 2xx transport response is not itself proof of lifecycle
success.

## What successful purge guarantees

A successful purge removes or resolves the organization references that would
reserve the purged customer's normalized email or leave ownership/member
references to that customer. Local customer, contact-email, and billing index
claims can then be reused for a new customer and workspace.

In full-auth mode, the duplicate-signup hook normalizes the submitted email and
excludes closed SQL account rows from its conflict check. A retained closed row
alone does not prevent signup with the same address. A non-closed SQL account or
an existing Redis customer still blocks reuse, and normal signup validation
continues to apply.

Local index release is not data restoration. A new account does not inherit the
old account's organizations or retained workspace data. No recovery path may
adopt a workspace based only on email equality.

In full authentication mode, account teardown retains a closed,
credential-stripped SQL account row and its authentication audit history. The
SQL uniqueness constraint permits a new live row with the same address. Signup
creates a new identity rather than reopening the closed account. Purge
confirmation must not claim that every datum in every store is deleted.

## Self-service deletion

Self-service account closure — `/auth/close-account` in full mode and the
simple-mode delete endpoint — runs the **same** preflight and cleanup policy as
the administrative purge. It is not an authorization to dispose of ambiguous
retained organization data, and it must never become a same-email adoption path.

Two things differ, both because the account itself is the actor:

- **Attribution.** The purge is constructed with `self_service: true`, which
  defaults the actor to the customer. Without it these events would be recorded
  as `actor: 'unknown'`.
- **Audit trail.** Self-service events are written to the **security** trail,
  not the operator trail. The operator trail is capped and trimmed oldest-first,
  so a caller who can retry a deletion at will must not be able to write to it.
  Refusals are the unbounded case — a blocked account produces one per click —
  and are logged only, never recorded. A refusal that has already crossed a
  mutation boundary is still recorded, on the security trail.

## Bulk inactivity purge

Bulk deletion must use the same preflighted lifecycle for each selected
customer. Candidate selection by inactivity changes how targets are chosen; it
does not weaken organization ownership policy or turn a partial result into
success.

The run's audit trail is one receipt pair, not one event per candidate. The CLI
opens a `customer.purge.bulk` start receipt on the operator trail that registers
every candidate (`BulkAuditContext`), and each purge authorizes its candidate
against that receipt **immediately after the initial preflight, before the
first refusal**. A covered purge, and the organization, membership, and session
operations nested under it, suppress their own operator events; the completion
receipt records the destroyed, refused, partial, and not-found counts. The
ordering is the invariant: a refused candidate never consumes an operator-trail
slot, because the operator trail is capped and trimmed oldest-first and refusal
is the common outcome of an inactivity sweep. Because the receipt carries only
counts, the CLI writes each refused or partial candidate's identifier and
blocker codes (never the email) to the application log; that log line is the
only place they persist. A candidate the receipt does not cover — unregistered,
already consumed, or under a completed context — audits normally.

Two per-account costs are paid once per run instead. The membership registry is
captured once (see *Discovery depth*) and shared by every candidate's preflight.
And the session revocation inside teardown is constructed with
`sweep_untracked_sessions: false`: the administrative revoke normally follows
its guaranteed tracked kill with a bounded `SCAN` of the whole session keyspace
for pre-sidecar blobs, decrypting each key, and a sweep would repeat that walk
once per candidate. Candidates have been idle past the cutoff, so every blob
they could own has expired; the tracked revocation and the Rodauth row purge
still run, and the revocation's audit detail records `untracked_sweep:
skipped` so a zero count cannot read as a completed sweep.
