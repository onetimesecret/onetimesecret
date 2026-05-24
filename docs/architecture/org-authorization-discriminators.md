---
labels: authorization, organization, membership
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

## Key Files

| File | Role |
|------|------|
| `lib/onetime/models/organization.rb` | `is_default` field, `can_delete?` |
| `lib/onetime/models/organization_membership.rb` | `domain_scope_id`, `domain_scoped?`, `can_access_domain?` |
| `lib/onetime/application/organization_loader.rb` | Active org selection (priority chain, caching) |
| `lib/onetime/application/auth_strategies/base_session_auth_strategy.rb` | Calls `load_organization_context` |
| `lib/onetime/application/authorization_policies.rb` | Real auth (no discriminators) |
| `apps/web/auth/operations/create_default_workspace.rb` | Sets `is_default! true` |
