---
id: "012"
status: proposed
title: "ADR-012: Membership-Level Materialized Entitlements"
---

## Status

Proposed

## Date

2026-05-26

## Context

Entitlements and roles are two independent authorization systems in this codebase. They never intersect. `require_entitlement!` checks whether the *organization* has a feature (`auth_org.can?`); it does not check whether the *caller's role* permits exercising it. Every member of an org gets the same answer regardless of role. The role hierarchy (owner > admin > member) exists on `OrganizationMembership` but is enforced only by three discrete guard methods (`verify_organization_owner`, `verify_organization_admin`, `verify_organization_member`) that must be manually paired with entitlement checks at every call site. Nothing forces the pairing. Five domain-branding endpoints already lack it, creating an active privilege gap in self-hosted mode (#3225).

A static `ENTITLEMENT_ROLE_REQUIREMENTS` map (entitlement → minimum role, checked at evaluation time) was the original proposal. That approach adds a second authorization lookup at every check and cannot express per-member operator overrides. The codebase already has a materialized entitlement system for organizations (`WithMaterializedEntitlements`) that stores effective entitlements in Redis sets, supports operator grants/revokes, and reconciles atomically. Extending the same machinery to memberships eliminates the dual-system problem by making the membership the single authorization primitive for authenticated requests.

## Decision

**Materialize entitlements on `OrganizationMembership` using the existing `WithMaterializedEntitlements` feature.** The membership becomes the single source of truth for "what can this caller do in this org."

### Materialization model

`OrganizationMembership` gains `feature :with_materialized_entitlements`, which adds the same Redis structures organizations already use: `entitlements_plan`, `entitlements_grants`, `entitlements_revokes`, `materialized_entitlements` (all sets), and `materialized_entitlements_at` (timestamp+hash).

A static `ROLE_ENTITLEMENTS` map defines which entitlements each role template permits, using Ruby `Set` so the hierarchy composes via set addition:

```ruby
owner_entitlements  = Set['custom_domains', 'custom_branding', 'custom_privacy_defaults',
                           'homepage_secrets', 'incoming_secrets', 'custom_mail_sender',
                           'flexible_from_domain', 'custom_signup_validation',
                           'manage_sso', 'manage_orgs', 'manage_billing']

admin_entitlements  = Set['manage_teams', 'manage_members', 'audit_logs',
                           'workspace_branding', 'ip_access_rules']

member_entitlements = Set['create_secrets', 'view_receipt', 'api_access',
                           'extended_default_expiration', 'notifications']

ROLE_ENTITLEMENTS = {
  'owner'  => (owner_entitlements  | admin_entitlements | member_entitlements).freeze,
  'admin'  => (admin_entitlements  | member_entitlements).freeze,
  'member' => member_entitlements.freeze,
}.freeze
```


At materialization time, the effective set is `org.materialized_entitlements ∩ ROLE_ENTITLEMENTS[role]`, stored in the membership's `entitlements_plan` set, then reconciled via `apply_entitlements` (which adds grants and subtracts revokes). The org intersection ensures a membership never exceeds its org's plan.

### Materialization triggers

Four lifecycle events trigger materialization:

1. **Invite acceptance** (`activate!`): role carried from invitation.
2. **SSO first-auth** (`ensure_membership`): role defaults to `'member'`.
3. **Role change**: re-materialize with new role template.
4. **Org plan change** (subscription webhook): background job re-materializes all active memberships with their current roles against the org's new entitlement set. Eventual consistency is acceptable; the webhook is async already.

### Authorization check

`require_entitlement!` resolves `auth_membership` (via `OrganizationMembership.find_by_org_customer`, O(1) index lookup, memoized per-request) and calls `auth_membership.can?(entitlement)`. No fallback to `auth_org.can?`. Missing membership for an authenticated user is a hard error. The `verify_organization_owner`, `verify_organization_admin`, and `verify_organization_member` methods are retired; the entitlement check subsumes them.

### Role semantics

`role` stays as a field on `OrganizationMembership`. It means "which entitlement template was applied." The `owner?`/`admin?`/`member?` predicates remain as convenience methods for display logic and as input to the materialization trigger. They stop being authorization checks. If an operator grants a member an admin-level entitlement via `entitlements_grants`, that works; the role label stays `'member'` but the effective entitlements include the grant.

### Ownership

`Organization.owner_id` is renamed to `created_by`. It becomes an immutable audit field set once at `Organization.create!`. Current owner authority is determined exclusively by which memberships have the owner entitlement set materialized. An org can have multiple memberships with `role: 'owner'` (multi-owner support is not wired up initially but the data model permits it). `org.owner?(cust)` delegates to `OrganizationMembership.find_by_org_customer(org.objid, cust.objid)&.owner?`.

### Standalone mode

When billing is disabled, `STANDALONE_ENTITLEMENTS` are materialized onto the organization at creation time (replacing the runtime check in `WithEntitlements#entitlements`). Membership materialization works identically in both modes: `org.materialized_entitlements ∩ ROLE_ENTITLEMENTS[role]`. Role differentiation is preserved in self-hosted deployments.

### Module extraction

`WithEntitlements` is split: the plan-based fallback hierarchy (planid lookup, billing_enabled? check, free-tier fallback, `PlanCacheMissError`) moves to a new `WithPlanEntitlements` module included only on Organization. `WithEntitlements` retains `can?`, `check_entitlement`, and the `STANDALONE_ENTITLEMENTS` / `FREE_TIER_ENTITLEMENTS` constants. OrganizationMembership includes `WithMaterializedEntitlements` and defines its own `can?` and `entitlements` methods without the plan fallback chain.

Limits (`limits_plan`, `limit_for`, `at_limit?`) move to a separate `WithMaterializedLimits` module included only on Organization. Limits are org-scoped resources (secret TTL, team count), not per-member. This prevents dead `limits_plan` hashkeys on membership Redis entries.

### What `WithEntitlements` is not included on membership

The `entitlements` method in `WithEntitlements` has a fallback hierarchy tied to `planid`, `billing_enabled?`, and `Billing::Plan.load` — concepts that don't apply to memberships. Including it would require overriding most of the module. The membership's `entitlements` method is simpler: return `materialized_entitlements.to_a` when materialized, compute from `org.entitlements ∩ ROLE_ENTITLEMENTS[role]` as a fallback for unmaterialized memberships.

## Trade-offs

- **We lose**: The simplicity of a single `org.can?` call. Authorization now requires resolving the membership, which is one additional Redis HGET per request (memoized).
- **We gain**: Role-aware entitlement checks without manual pairing. Operator overrides at the membership level (grant a specific member extra access, or restrict one). Elimination of the parallel `verify_organization_*` authorization system. A path to per-member audit logging and capability-based UI rendering.
- **Risk**: Fan-out on plan change. An org with N members requires N re-materializations. At current scale (orgs are low hundreds of members) this is negligible in a background job. If org sizes grow to thousands, the job needs batching or pipelining.
