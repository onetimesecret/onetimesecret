# Deleting an Organization

Status: implemented lifecycle policy for organization deletion and customer
purge integration.

## Purpose

Organization deletion must preserve ownership, membership, domain, billing,
contact-email index, and default-workspace invariants. It must use the canonical
organization operation; deleting a model hash directly is not equivalent.

Customer purge is a coordinated caller of that operation. It does not receive a
general force-delete capability.

## Standalone organization deletion

`Onetime::Operations::Org::Delete` is the canonical deletion path used by the
CLI, Colonel, and customer-facing adapters. It plans before applying and owns
cleanup of organization indexes, memberships, invitations, affected
`default_org_id` pointers, notifications, and audit records.

The operation retains independent guardrails for:

- attached or drifted domains;
- default personal workspaces;
- active subscriptions;
- deleting an owner's last organization.

Operator force options unlock only the guard they name. In particular, forcing
a default workspace does not bypass domains or billing, and forcing a billing
organization does not cancel Stripe.

## Customer purge policy

Administrative account purge performs a global, read-only organization
preflight before account teardown. Each discovered relationship is classified
as one of the following:

| Relationship | Policy |
| --- | --- |
| Consistent non-owner membership | Remove through semantic membership cleanup. |
| Sole-owned, empty, non-billing personal default workspace | Delete through canonical organization teardown. |
| Owned workspace with domains | Refuse until domains are removed or transferred. |
| Owned workspace with billing state | Refuse until billing is resolved. |
| Owned workspace with other members | Refuse until ownership is transferred or membership is otherwise resolved. |
| Sole-owned workspace with the owner's own invitations, receipts, or description | Delete; reported on the planned action as `notes`. Receipts are TTL-bound records and are not destroyed by the purge. |
| Workspace with an unfinished v1 to v2 migration | Refuse: the migration owns rows outside the workspace. |
| Drifted ownership, membership, domain, instance, or contact-email index evidence | Refuse until repaired and re-diagnosed. |
| Incomplete scan or lookup | Refuse because absence of evidence is not proof that cleanup is safe. |

The account-purge integration may bypass only the default-workspace and
last-organization guardrails for the exact personal workspace authorized by a
fresh, matching purge plan. Domain and billing guardrails remain active. The
capability is revalidated immediately before organization mutation and is not
available to public adapters.

## Ordering and concurrency

The customer lifecycle uses this sequence:

1. discover all customer, membership, organization, contact-email index, and
   domain references;
2. refuse if any relationship is unsafe or incomplete;
3. before each planned cleanup, rerun preflight and require the same remaining
   plan;
4. execute one canonical organization or membership operation;
5. after cleanup, require a clean plan with no remaining actions;
6. revalidate immediately before account teardown mutations;
7. revoke sessions, close/strip the authentication identity, and delete the
   customer;
8. scan organization references again;
9. record successful completion only after final validation and audit.

There is no cross-store transaction. If the plan changes or a later operation
fails after an earlier cleanup completed, the result is `partial`, not
`success`.

## Refusal and partial outcomes

A `refused` result means no planned cleanup action completed. It returns the
blocking organization evidence and the current stage so an operator can repair
state while the customer remains intact.

A `partial` result means at least one cleanup or teardown stage completed before
the lifecycle stopped. Operators must inspect `actions`, `stage`,
`completed_stages`, and `blockers`; they must not assume that either the old
account or all old organization references still exist. Re-running without that
inspection can compound drift.

Only a `success` result means final organization-reference validation passed.

## Same-email recreation

After a successful purge, no old organization contact-email reservation or
ownership/member reference remains that can block a newly created account with
the same normalized email. The recreated account can provision a new default
workspace and use organization-context-dependent endpoints.

This guarantee does not authorize restoration. A matching contact email alone
never proves that a new account owns an old workspace. Automatic same-email-only
adoption is prohibited, especially when the workspace contains domains,
billing, live or stale members, receipts, invitations, or other retained data.
Any supported restoration must be explicit, complete, and audited, and must
repair ownership metadata, memberships, indexes, and entitlements together.

## Operational interfaces

- Preview or delete one organization with `bin/ots org delete ORG`.
- Transfer ownership with `bin/ots org transfer-ownership ORG NEW_OWNER`.
- Remove a non-owner membership with `bin/ots memberships remove`.
- Diagnose global organization drift with `bin/ots org doctor --all --json`.
- Purge one account through the coordinated lifecycle with
  `bin/ots customers purge-one IDENTIFIER` or Colonel customer details.

Do not use direct model destruction or raw index deletion as the primary repair
path. See
[`ownerless-workspace-email-index-collision.md`](../../runbooks/ownerless-workspace-email-index-collision.md)
for incident handling.
