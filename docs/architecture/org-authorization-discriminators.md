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

For organization invitations, authorization checks both the member's capability
and the scope of their membership in the target organization.

### Decision on listing pending invitations

An active organization-scoped member with `manage_members` can list the
organization's pending invitations. A domain-scoped member receives HTTP 403
with no invitation records or count, including when an administrator explicitly
grants that member `manage_members`. The existing site-operator path continues
to allow an operator without a membership to administer the organization.

Creating, resending, and revoking invitations already require organization
scope from members. Listing reveals invitees' email addresses, proposed roles,
and invitation tokens across the organization. An administrator responsible
for one domain has no need for that information. The invitation names the
organization as its destination, so the invitee's email domain cannot
determine which invitations a domain administrator may see.

NIST SP 800-53 Rev. 5, control AC-6, limits authorized access to what is
“necessary to accomplish assigned organizational tasks.” OneTime Secret
applies that principle by checking the scope before reading the list.
[NIST SP 800-53 Rev. 5, AC-6, Least Privilege](https://csrc.nist.gov/CSRC/media/Projects/risk-management/800-53%20Downloads/800-53r5/SP_800-53_v5_1-derived-OSCAL.pdf#page=39)

The same boundary applies to `manage_org`. Updating or deleting an organization
requires organization-wide scope because the change affects every domain and
member. A member configuring incoming secrets for a domain must have access
to that particular domain.

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

The result is cached in the Rack session and flows into controller context via `env['otto.strategy_result'].metadata[:organization_context]`.

## Active Domain Selection

See Onetime::Middleware::DomainStrategy.

## Signup Domain Association

| Field | Entity | Meaning | Set When |
|-------|--------|---------|----------|
| `signup_domain_id` | `Customer` | CustomDomain identifier at signup | Account creation |

### Current behavior

`signup_domain_id` captures the custom-domain identifier during new account
creation, including password sign-up and SSO JIT provisioning. It is provenance
metadata, not current domain state:

- **Written at account creation only** — Existing accounts are not updated when
  they later interact with a tenant domain.
- **Nil is valid** — An account created without a resolved custom domain has no
  `signup_domain_id`.
- **No current policy fallback** — The current signup-policy resolver uses the
  request's `display_domain`; it does not read `signup_domain_id`. Do not rely on
  this field for re-verification or background-job policy selection unless that
  reader is implemented.

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

A single provenance field cannot represent all of a multi-organization user's
custom-domain associations. Any future out-of-band policy reader must define how
it selects the relevant domain instead of treating `signup_domain_id` as a current
membership or primary-domain record.

### When Request Context Is Available

Current signup-policy resolution uses `display_domain` from the request. It does
not fall back to `signup_domain_id` when request context is unavailable.

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
| `apps/web/auth/operations/ensure_default_workspace.rb` | Sets `is_default! true` |
| `apps/api/account/logic/account/create_account.rb` | Sets `signup_domain_id` on new accounts |
