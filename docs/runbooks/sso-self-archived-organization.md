# SSO Self-Archived Organization

Use this runbook when a tenant (custom-domain SSO) organization has been
soft-archived with a comment that names the organization's own public id, and
its owner and members have lost organization-gated features.

## Symptoms

One or more of these conditions may appear:

- the owner and the members of a tenant organization lose organization-gated
  features (team secrets, custom-domain management, billing pages) while they
  can still sign in;
- `OrganizationLoader` returns no organization for them, because the loader
  skips archived organizations;
- the owner's `default_org_id` names an organization whose `archived_at` is
  set;
- `bin/ots domains doctor --all` reports `archived_org_reference` for the
  tenant's domain;
- the organization's `archived_comment` reads
  `Superseded by domain org <extid> via SSO self-heal` where `<extid>` is the
  organization's **own** public id.

The self-referential comment is the distinguishing signal. A comment that
names a *different* organization describes a personal workspace archived by
earlier versions of the sign-in and is not covered here.

## Cause

`Auth::Operations::JoinDomainOrganization` runs on every tenant SSO login.
Before #4717, after joining the customer to the domain organization it
repointed their default to that organization and archived the personal
default workspace it replaced. When the signed-in customer owned the domain
organization and that organization carried the `is_default` flag (an
auto-created workspace later promoted to the tenant organization), the
workspace it resolved as "the personal default" was the domain organization
itself, and nothing compared the two. The organization was archived on the
owner's tenant SSO login, and again on the first login after any restore.

#4717 changes the login path so it never archives: it joins the customer and
repoints their default, and leaves every workspace as it was. Records archived
before that change are not restored by it; that is what the rest of this
runbook does. A restored organization stays live regardless of when the login
change is deployed.

## Safety rules

- A restore is durable: the login path never archives, so no sign-in undoes
  it. If the running version predates #4717, deploy it first; until then an
  owner SSO login can archive the organization again.
- Do not clear `archived_at` or `archived_comment` directly in Redis/Valkey or
  from `bin/console`. `bin/ots org unarchive` is the only path that resets both
  fields together and records the change in the operator audit trail.
- Do not repoint `default_org_id` as part of this repair unless the owner's
  pointer is actually wrong. For the self-archive case it already names the
  archived organization and needs no change. The command reports where the
  pointer goes; it never changes it.
- Treat any archived organization whose comment names a different organization
  as out of scope. Deciding whether to restore it is a separate judgement.

## Discover the affected organizations

1. Scan every domain. Check 9 (`archived_org_reference`) is report-only and
   fires when a domain's `org_id` points at an organization whose
   `archived_at` is set:

   ```console
   bin/ots domains doctor --all
   ```

   Each affected domain is printed as `<fqdn> (<domain extid>)` followed by

   ```text
   [HIGH]     org_id '<org objid>' points to an archived organization [manual fix required]
              Manual decision required: unarchive the organization, or move the domain (bin/ots domains transfer <fqdn> --to-org <ORG>)
   ```

   Note that the message carries the organization's internal id (`org_id`),
   which `bin/ots org unarchive` accepts directly. With `--json` the same
   finding is the issue whose `check` is `archived_org_reference`.

2. For each reported organization, run the dry run. It writes nothing and
   prints the archived comment:

   ```console
   bin/ots org unarchive <ORG>
   ```

   ```text
   DRY RUN — nothing has been written yet
   Organization:     <org extid> (<display name>)
   Owner:            <owner extid>
   Archived comment: Superseded by domain org <org extid> via SSO self-heal

   Dry run only — re-run with --run to apply.
   ```

   When the owner's `default_org_id` names a different live organization the
   dry run adds one line before the blank one:
   `Owner default workspace: <other extid>; this organization will not become their default`.

3. Keep only the organizations whose comment names their **own** extid (the
   one printed on the `Organization:` line). Those are the #4717 records. The
   same fields are visible in the Colonel organization detail
   (`GET /api/colonel/organizations/:org_id`: `archived`, `archived_at`,
   `archived_comment`).

## Repair

For each organization kept in the previous step:

1. Confirm the running version includes #4717 (login never archives).

2. Verify the surrounding state before writing anything:

   - the owner still holds an active `owner` membership
     (`bin/ots org doctor <ORG>` checks 1, 2 and 4);
   - the owner's `default_org_id` names this organization: read the
     `default_org_id:` line of `bin/ots customers show <owner>` and compare it
     with the org's `org_id` from the domain scan. A missing
     `Owner default workspace:` line in the dry run is not proof of this; the
     line is also absent when the pointer is empty or names an archived or
     missing organization;
   - `planid`, `stripe_customer_id` and `stripe_subscription_id` are the values
     you expect for the tenant. The archive never touched them, so a mismatch
     here is a different problem; stop and investigate it first.

3. Apply:

   ```console
   bin/ots org unarchive <ORG> --run
   ```

   Expected output is `Unarchived <org extid> (<display name>)` with the
   cleared comment on the next line. One `organization.unarchive` event with
   `result: success` is recorded in the operator audit trail; the cleared
   comment is kept in the event detail.

4. Verify the repair holds. Ask the owner to sign in through the tenant SSO
   (or sign in as them with an authorized test account on a staging copy),
   then confirm the organization is still live:

   ```console
   bin/ots org unarchive <ORG>
   ```

   Expected: `<org extid> (<display name>) is not archived; nothing to do.`
   A domain scan should no longer report `archived_org_reference` for the
   tenant's domain.

## The `Owner default workspace` advisory

Both passes print `Owner default workspace: <other extid>; this organization
will not become their default` when the owner's `default_org_id` names a
*different* organization that is live. The same value is `pointer_org_id` in
the `--json` payload and in the audit event detail. It is information, not a
refusal: the unarchive proceeds exactly as it would without it.

Why it matters: the restored organization stays live either way, but the
owner keeps landing in the other organization until someone repoints the
default. Members can choose their own default workspace, so a pointer
elsewhere may be deliberate.

The advisory does not appear for the self-archive case covered by this
runbook, where the pointer already names the archived organization. If it
does appear, find out where the pointer came from before deciding whether to
change it (`bin/ots customers doctor <owner>`); do not repoint it as part of
the unarchive.

## What this runbook does not cover

- Personal workspaces archived by earlier versions of the sign-in (comment
  names a different organization). Restoring one of those is a product
  decision about which workspace the customer should have.
- Personal workspaces whose comment reads `Bulk SSO migration to <domain>`.
  These are legacy data from a removed operator tool; the same product
  decision applies.
