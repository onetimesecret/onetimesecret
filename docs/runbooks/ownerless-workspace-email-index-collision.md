# Ownerless Workspace / Email-Index Collision

Use this runbook when an account can authenticate but cannot establish an
organization context, default-workspace creation raises
`Onetime::OrganizationExists`, or diagnostics report a workspace contact-email
collision.

## Safety rules

- Do not adopt or transfer a workspace solely because its `contact_email`
  matches the current account email.
- Do not remove stale member IDs just to make the legacy adoption guard pass.
  That does not repair `owner_id`, indexes, entitlements, or retained data.
- Do not delete organization hashes or index fields directly in Redis/Valkey.
- Do not force organization deletion while domains or unresolved billing remain.
- Treat a partial purge as an incident state. Inspect completed stages before
  retrying any mutation.

Email reuse proves control of an address at a point in time; it does not prove
ownership of data retained from a previously purged account.

## Symptoms

One or more of these conditions may appear:

- signup and verification succeed, and login succeeds;
- the customer has no organizations;
- an entitlement-gated request fails while trying to create or load a default
  workspace;
- logs contain `Onetime::OrganizationExists: Organization exists for that email
  address`;
- account diagnostics report an ownerless workspace, stale members, a phantom or
  occupied contact-email index, or blocked/incomplete organization context;
- a purge result is `refused` or `partial` with organization blockers.

## Diagnose without changing data

1. Run customer diagnostics:

   ```console
   bin/ots customers diagnose user@example.com --json --full
   ```

   The equivalent no-SSH path is Colonel → Customers → customer detail →
   **Account Diagnostics**.

2. Scan organizations globally:

   ```console
   bin/ots org doctor --all --json
   ```

   A relationship-only customer lookup is insufficient: a recreated customer
   may have no participation link to the old workspace. The normalized-email
   contact index is the only connection.

3. Correlate the evidence. Record:

   - indexed organization id and whether the organization exists;
   - `contact_email` and whether its index points back to the same organization;
   - `owner_id` and whether that customer exists;
   - live and stale member entries and membership records;
   - default-workspace flags and customer `default_org_id` pointers;
   - domains, including domain records missing from the organization list;
   - billing/subscription identifiers and status;
   - invitations, receipts, and other retained organization data;
   - purge `status`, `stage`, `completed_stages`, `actions`, and `blockers`.

4. If any source is unavailable or diagnostics report incomplete evidence, stop.
   Restore the diagnostic source before deciding that deletion or transfer is
   safe.

## Choose an explicit resolution

### A. The workspace belongs to another live account or team

Preserve the workspace. Repair ownership/index drift through the relevant
canonical operation, then allow the new account to create its own default
workspace. If the purged customer still appears as a non-owner member, remove
that relationship through semantic membership cleanup rather than raw set
edits.

Useful operator paths:

```console
bin/ots org transfer-ownership ORG NEW_OWNER
bin/ots memberships remove --help
```

Transfer ownership only to an existing active member after verifying the
workspace and the intended owner.

### B. The workspace contains domains, billing, members, or retained data

Do not adopt it and do not force-delete it as collision cleanup.

1. transfer each domain or remove it through the domain operation;
2. cancel or otherwise resolve billing in Stripe and local billing state;
3. transfer ownership when another member should retain the workspace;
4. resolve invitations, receipts, and retained data according to the applicable
   retention or erasure policy;
5. rerun both diagnostics.

Customer purge should remain refused until preflight can prove the resulting
relationship set is safe.

### C. The workspace is an ownerless, empty personal default workspace

Deletion may be appropriate only after confirming all of the following:

- no live or stale members or membership records remain;
- no domains or domain-reference drift exists;
- no billing identifiers or subscription state remains;
- no invitations, receipts, or other retained organization data remains;
- the contact-email index consistently points to this organization;
- no live customer has a valid ownership claim.

Preview the canonical organization deletion:

```console
bin/ots org delete ORG --dry-run --json
```

Review the plan and guardrail result. If policy authorizes deletion, apply
through the same command's confirmed path; do not replace it with direct model
or datastore deletion. Rerun organization and customer diagnostics afterward.

### D. The contact-email index is phantom or drifted

A phantom index points to no organization; a drifted index disagrees with the
organization's own contact email or identity. Use the organization diagnostic
repair path supported for the reported check. Do not clear an index merely
because it blocks signup: first prove that no organization should hold it and
retain the before/after diagnostic output with the incident record.

## Provisioning latch (409) versus temporary unavailability (503)

Default-workspace provisioning (`Auth::Operations::EnsureDefaultWorkspace`)
runs lazily on the first entitlement-gated request and from the signup / SSO
hooks. Two distinct failure states come out of it; do not treat them alike.

**Latched: `AccountProvisioningFailed` (HTTP 409).** Provisioning hit a
classified contact-email collision (`empty_orphan`, `stale_members`,
`live_members`, `retained_data`, or an unrepairable `phantom_index` /
`index_mismatch`). The customer record carries
`provisioning_failure_code=default_workspace_collision` plus the
classification, `customers diagnose` reports `account_provisioning_failed`,
and every org-less request answers 409 with the same code. The request path
never re-runs provisioning while the latch is set; it is released only by the
doctor (below) or by canonical provisioning succeeding through another
surface.

**Not latched: `AccountProvisioningUnavailable` (HTTP 503, `retry_after`).**
Nothing was persisted. Two causes, named in the body's `reason`:

- `collision_unreadable` — the classifier could not read its evidence (a
  datastore error mid-scan). This is "could not determine", not an account
  state, so it is never latched; the next request classifies again.
- `provisioning_in_progress` — another request holds this customer's creation
  lock and its workspace did not appear within the bounded wait.

A 503 that keeps recurring for one customer is a datastore problem (look at
the classifier's logged `error`/`reason`), not a collision to resolve.

**Creation lock.** Creation is serialized per customer with a `Familia::Lock`
on `customer:<customer objid>:org_creation_lock` (15s TTL here; the same key
the organizations API takes, with a 30s TTL, for a user-initiated create, so
the two creators never interleave). A contender polls for the holder's
workspace for up to ~2s and returns it without classifying anything, because
a collision seen during that window would be the customer's own half-built
organization. Never delete the lock key by hand; the TTL bounds a holder that
died mid-create.

**Releasing a latch with the doctor.** `bin/ots customers doctor <email>`
reports `workspace_provisioning_failed` with the *current* classification and
whether the customer already has a workspace. Under `--repair` the latch is
released only on evidence, never blindly:

- the customer already has a workspace (a stale latch from a race that the
  workspace outlived), or
- the live classification is `clear` or `current_valid_workspace`.

The repair re-runs canonical provisioning, which converges and clears the
flag itself, then verifies the persisted result; the audit trail records
`workspace_provisioning_latch_released`. `phantom_index` / `index_mismatch`
latches go through the workspace-collision repair instead (compare-and-delete
the stale claim, then provision). Any other classification keeps the latch
and the report names it; resolve it with sections A–D above. An `unreadable`
classification is reported as transient with a retry action and is never a
release.

## Handling purge results

- `refused`: the customer should still exist. Resolve every blocker, rerun
  diagnostics, and submit a new purge request.
- `partial`: some cleanup or account teardown completed. Do not promise that the
  account is deleted, do not navigate away from the evidence, and do not repeat
  the command until the completed actions and remaining references are known.
- `success`: final reference validation passed. Same-email account recreation
  should create a new default workspace; it must not restore the old workspace.

## Verify recovery

After repair or a successful purge:

1. customer diagnostics contain no collision or incomplete organization-context
   finding;
2. `bin/ots org doctor --all --json` no longer reports the affected owner/index
   failures;
3. a recreated account with the same email receives a newly provisioned default
   workspace;
4. the new customer has an active owner membership and a matching
   `default_org_id`;
5. entitlement-gated requests, including recent receipts, complete without
   workspace provisioning errors;
6. audit records identify the purge, transfer, membership removal, or
   organization deletion that resolved the incident.

Do not verify recovery by authentication alone. The original failure permits
login while organization context remains unusable.
