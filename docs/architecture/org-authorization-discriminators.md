---
labels: authorization, organization, membership, signup, custom-domain
---
# Organization Authorization Discriminators

## The Two Fields

| Field | Entity | Meaning | Set When |
|-------|--------|---------|----------|
| `is_default` | `Organization` | Auto-created personal workspace | Signup, once |
| `domain_scope_id` | `OrganizationMembership` | Member restricted to one domain | SSO join |

These are orthogonal. `is_default` is org provenance; `domain_scope_id` is membership scope.

## Current Usage

**`is_default`** — workspace selection heuristic + deletion guard:
- `OrganizationLoader#determine_organization`: one step in "which org is active context?"
- `Organization#can_delete?`: returns false — data-integrity guard

**`domain_scoped?`** — SSO membership access check:
- `OrganizationMembership#domain_scoped?`: `!domain_scope_id.empty?`
- `OrganizationMembership#can_access_domain?`: the actual runtime gate
- `OrganizationLoader`: gates domain-based workspace selection

**Neither is used in authorization policy.** Real auth is `owner?`, `member?`, role, entitlements.

## Design Rationale

`is_default` answers "is this the personal workspace created at signup?" — immutable provenance.

`domain_scoped?` answers "is this member's access restricted to a specific domain?" — mutable configuration.

They correlate today (personal orgs lack custom domains, tenant orgs have them) but this is entitlement layout, not structural truth. An Identity Plus user attaching a custom domain to their personal org breaks the correlation.

**Use each for its intended purpose:**
- `is_default` → org kind discrimination, deletion guards
- `domain_scoped?` → membership-level access scope
- `owner?`/`member?`/entitlements → authorization

## Edge Case: Default Org Conversion

Undecided: can `is_default` be cleared to convert a personal org to tenant org?

**Option 1** (current behavior): Default orgs stay default forever. User creates new tenant org and migrates. Cleaner model.

**Option 2**: `is_default` can be cleared on conversion. Messier model, smoother UX. Requires creating a new empty default org for that user.

No code currently calls `is_default! false` post-creation. The immutability is de facto, not enforced.

## Active Organization Selection

The active org for a request is determined by `OrganizationLoader`, a module included in all auth strategies. See the module's header comment for the priority chain and caching behavior.

The result is cached in the session and flows into controller context via `env['otto.auth_result'].metadata[:organization_context]`.

## Active Domain Selection

See Onetime::Middleware::DomainStrategy.

## Signup Domain Association

| Field | Entity | Meaning | Set When |
|-------|--------|---------|----------|
| `signup_domain_id` | `Customer` | CustomDomain identifier at signup | Account creation |

### Purpose

`signup_domain_id` captures the custom domain context when a user signs up. Used for:

1. **Re-verification** — When re-verification is triggered without request context (background job, admin action), this field determines which domain's validation strategy applies.

2. **Background jobs** — Jobs processing signup-related work can load the associated `SignupConfig` without request context.

### Semantic: "First Meaningful Association"

The field captures provenance, not current state:

- **Set if missing, don't overwrite** — If a user signed up on canonical (no custom domain) then later interacts on a tenant domain, the field is set on that interaction. Once set, it's not overwritten.
- **Nil is valid** — Users who only interact on canonical domain have no `signup_domain_id`. Global config applies.

### Comparison to Other SaaS

Slack, Linear, and Notion sidestep this problem by modeling tenant association differently:

| Aspect | Slack/Linear/Notion | OTS |
|--------|---------------------|-----|
| User identity | Tenant-agnostic | Tenant-agnostic |
| Tenant association | Explicit join event | Implicit via `signup_domain_id` + org membership |
| Multiple tenants | User belongs to N workspaces | User belongs to N orgs, single `signup_domain_id` |
| Validation rules | Apply per-tenant at join time | Apply per-domain at signup time |

These products don't need a "signup domain" because workspace membership is the explicit, auditable record of association. A user can be in Acme workspace AND Beta workspace — each has its own rules.

### Limitations

**Single-field approach breaks down with multi-tenant users.** If a user is a member of multiple organizations with different custom domains, `signup_domain_id` captures only one. For out-of-band operations, we'd need to either:

- Look up org memberships and find the relevant domain
- Accept that a "primary" or "most recent" association is used

This is acceptable for MVP. Multi-tenant edge cases are rare and can be addressed by using request context when available (which covers most cases).

### When Request Context Is Available

When `display_domain` is in the request (web flows), it takes precedence over `signup_domain_id`. The stored field is only consulted when request context is unavailable.

## Key Files

| File | Role |
|------|------|
| `lib/onetime/models/organization.rb` | `is_default` field, `can_delete?` |
| `lib/onetime/models/organization_membership.rb` | `domain_scope_id`, `domain_scoped?`, `can_access_domain?` |
| `lib/onetime/models/customer.rb` | `signup_domain_id` field |
| `lib/onetime/models/custom_domain/signup_config.rb` | Per-domain signup validation config |
| `lib/onetime/signup_validation.rb` | Shared validation module (per-domain + global fallback) |
| `lib/onetime/application/organization_loader.rb` | Active org selection (priority chain, caching) |
| `lib/onetime/application/auth_strategies/base_session_auth_strategy.rb` | Calls `load_organization_context` |
| `lib/onetime/application/authorization_policies.rb` | Real auth (no discriminators) |
| `apps/web/auth/operations/create_default_workspace.rb` | Sets `is_default! true` |
| `apps/api/account/logic/account/create_account.rb` | Sets `signup_domain_id` on new accounts |
