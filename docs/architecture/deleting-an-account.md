# Deleting an Account

Account deletion is a lifecycle operation, not a direct `Customer#destroy!`.
The account, its authentication identity, memberships, and owned workspaces can
span Redis/Valkey, the authentication database, and external billing systems.
The operation therefore plans and validates the entire relationship set before
performing irreversible writes.

## Administrative purge contract

Colonel `DELETE /api/colonel/users/:user_id` and
`bin/ots customers purge-one` use the same customer purge lifecycle.

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
customer's own reverse indexes and keeps every per-organization drift check.
Single-account operator entry points (the colonel endpoint and
`bin/ots customers purge-one`) pass `deep: true`, which additionally sweeps the
global `Organization`, `OrganizationMembership` and `CustomDomain` registries to
catch a reference no reverse index points at — an organization whose `owner_id`
names the customer but which is absent from their participations. Those sweeps
are whole-registry reads, and the lifecycle re-runs preflight once per planned
action plus three times during teardown, so they are never used on a request
path or in the bulk sweep. Deep mode runs them at the initial plan and the
final post-teardown validation; the intermediate revalidations stay shallow.

Shallow discovery derives an organization's membership rows from the
organization's own `members` set (plus the purge target's row, loaded
directly). A live row whose customer is missing from that set is reachable
only through the registry, so on a request path — self-service closure — it is
not seen and a shared workspace could read as sole-owned. This residual is
accepted there: the through-model writes the row and the set together, so the
state is drift, not a normal write, and the deep operator paths do refuse it.
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
   organization deletion operation when it is empty and non-billing.

Preflight refuses before account teardown when an owned workspace has domains,
billing state, other members, an unfinished v1 to v2 migration, or
ownership/membership/index drift. It also refuses when a scan fails and the
evidence is incomplete. Operators must transfer ownership, remove retained
resources, or repair drift and then run preflight again.

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
`owner_id` and `created_by` are compared tolerantly against both the customer's
objid and custid, because rows predating the objid standardization chore still
carry the custid and a legacy encoding is not drift.

A customer email matching an organization contact email is discovery evidence,
not authorization to attach that organization to another account.

## Lifecycle ordering

The ordering is deliberate:

1. **Complete read-only preflight.** Discover every relevant relationship and
   produce blockers plus a cleanup plan.
2. **Revalidate before each cleanup mutation.** If the plan changed, stop.
3. **Organization cleanup.** Delete an approved empty personal workspace and/or
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
references to that customer. Recreating and verifying an account with the same
email can therefore provision a new default workspace and establish a usable
organization context for entitlement-gated requests.

This is a recreation guarantee, not data restoration. The new account does not
inherit the old account's organizations or retained workspace data. No recovery
path may adopt a workspace based only on email equality.

In full authentication mode, account teardown retains a closed,
credential-stripped SQL account row and its authentication audit history. That
retained tombstone is intentional and does not reserve the email against a new
live account. Consequently, purge confirmation must not claim that every datum
in every store is deleted.

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
