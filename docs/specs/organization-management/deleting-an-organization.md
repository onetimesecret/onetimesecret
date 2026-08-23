# Deleting an Organization

Status: draft notes — options and complications, no design decided yet.

## Options

A. Outright delete. Solve the technical complexity and make it a non-issue.
B. Archive/hide. A user-facing option in the Org Settings. Removes it from
   the org context dropdown and orgs list page. There's a chance it could
   cause strange behaviour.
   - In Django, soft deletes are clean and easy by creating a base
     Manager/QuerySet class that automatically appends `.active()` to the
     model's queries. They just don't exist as far as the application is
     concerned.
C. Explain in the UI why default orgs are important/necessary? Might just
   sound like lazy bullshit (which I think it would be).

## Complications with removing a default org

1. A default org is the user's identity container, not a team. Plan,
   entitlements, limits, Stripe customer/subscription
   (`with_organization_billing.rb:63-79`), receipts (`receipt.rb:74`), and
   domains all hang off the org. A customer with no active org is a
   degraded read-only session (`organization_loader.rb:197-207`). In
   Clerk/GitHub terms the default org is the personal account, not an
   organization — and nobody lets you delete a personal account separately
   from the user.
2. Deleting it doesn't delete it — it resets it. CreateDefaultWorkspace runs
   from the account/omniauth hooks and lazily from `auth_org`
   (`create_default_workspace.rb:78,151`). If the customer has zero other
   orgs, the next entitlement-gated action mints a fresh `is_default` org
   (or adopts an orphan via `find_by_contact_email`, line 194). So "delete
   my only/default org" is semantically account purge
   (`bin/ots customers purge-one`), which is exactly why `:last_org` is
   non-overridable.
3. No cascade, no transaction, no undo. Redis has no FKs; teardown is
   ordered writes with per-step rescue. After `destroy!`, these still point
   at the dead objid:
   - `Receipt#org_id` + the `organization:<objid>:receipts` zset key
     (never touched by `destroy!`)
   - `SessionMetadata#org_id`, `ColonelAuditEvent` payloads (fine as
     tombstone refs, but readers must be nil-tolerant)
   - `OrganizationMembership` through-model hashes —
     `remove_members_instance` removes participation; the
     `ensure_member_through_models` chore exists because this drifts
   - Stripe: `stripe_customer_id` goes with the org, the Stripe Customer
     lives on with no back-pointer (the #4205 drift). The op refuses while
     `billing_live?`, but a canceled-sub org still orphans the Stripe
     customer.
   - Materialized entitlement/limit/secret_activity keys — verify whether
     Familia's `destroy!` clears those DataTypes; unconfirmed.
4. `is_default` is a label on the org, `default_org_id` is a pointer on the
   customer, and they can disagree. The op clears the pointer but never
   promotes a surviving org to `is_default`, so the "personal workspace"
   badge, colonel `v-if="org.is_default"` branches, and the `:is_default`
   guard stop protecting anything for that user. If the customer has
   another org, the correct verb is demote-and-promote, not delete-and-hope.
5. Audit eviction — refusals are deliberately unaudited because the audit
   set is COUNT-capped (documented in the op header). Any new reversible
   path must keep that property.

Common thread: (a) cascade memberships/invitations, never users; (b) hard
delete is explicit and irreversible, or there is a soft/delayed path —
never a hidden half-cascade; (c) the personal container is only deleted by
deleting the user; (d) "must have ≥1 org" is enforced at login by routing
to create, not by refusing deletion.

## Complications with soft deleting

`archive!` already hides the org everywhere that matters and blocks
re-creation:

- `ListOrganizations` rejects archived
  (`apps/api/organizations/logic/organizations/list_organizations.rb:30,36`);
  `OrganizationLoader` skips archived at steps 3 and 5; `CreateOrganization`
  counts only non-archived toward the limit.
- `CreateDefaultWorkspace#workspace_already_exists?` counts
  `organization_instances` — membership survives archiving, so it returns
  "exists" and mints nothing (`create_default_workspace.rb:156-170`).

Three things break it, in order of severity:

1. Archived-only customer silently keeps using the "deleted" org. Loader
   returns nil → `auth_org` calls CreateDefaultWorkspace → nil → fallback
   `org ||= cust.organization_instances.first`
   (`lib/onetime/logic/organization_context.rb:91`) has no archived filter
   and hands back the archived org. So secrets, receipts, limits all keep
   keying off it; it's invisible, not gone. This is the same trap as
   #4211's "nil-on-archived". Either keep `:last_org` non-overridable for
   soft delete too, or fix that fallback to `.reject(&:archived?)` and
   decide what an org-less session does.
2. `archived` already means something else. `archive!`/`archived_comment`
   are the SSO bulk-migration "superseded by domain org" state;
   `JoinDomainOrganization` re-archives on every domain SSO login and
   domains doctor check 9 reads it that way
   (`organization.rb:323-357`). Reusing it for customer-requested deletion
   conflates states. Use a separate marker (`deleted_at` + reason, or a
   status field) — or at minimum a reserved `archived_comment` value the
   SSO paths never write.
3. `archive!` skips the guards `Org::Delete` has. It warns on domains and
   never checks `billing_live?`, so a soft-deleted org can keep billing in
   Stripe and keep owning live domains. And nothing promotes a surviving
   org to `is_default`/`default_org_id`.
