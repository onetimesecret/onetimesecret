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
- organization member sets and membership records;
- organization ownership and instance indexes;
- the normalized customer email in `Organization.contact_email_index`;
- domain records that refer to an organization.

A relationship must be complete and unambiguous before purge can execute. The
operation may plan only these automatic actions:

1. remove a consistent, non-owner membership through the canonical membership
   removal operation; or
2. delete a sole-owned personal default workspace through the canonical
   organization deletion operation when it is empty and non-billing.

Preflight refuses before account teardown when an owned workspace has domains,
billing state, other members, pending invitations, receipts, retained
organization data, or ownership/membership/index drift. It also refuses when a
scan fails and the evidence is incomplete. Operators must transfer ownership,
remove retained resources, or repair drift and then run preflight again.

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

Self-service account closure shares the ordered session/authentication/customer
teardown, but the organization preflight policy above describes the
administrative purge surface. Self-service closure is not an authorization to
dispose of ambiguous retained organization data, and it must never become a
same-email adoption path.

## Bulk inactivity purge

Bulk deletion must use the same preflighted lifecycle for each selected
customer. Candidate selection by inactivity changes how targets are chosen; it
does not weaken organization ownership policy or turn a partial result into
success.
