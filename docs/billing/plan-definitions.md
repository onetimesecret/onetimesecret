# Catalogue Definitions Reference

This document describes the plan structure and capabilities for Onetime Secret billing.

**Note:** Catalogue definitions are now stored in Stripe product metadata and cached in Redis via `Billing::Plan`. This document serves as reference for understanding plan structure and configuring Stripe products.

## Catalogue Structure

Each plan consists of:
- **plan_id**: Unique identifier (e.g., `'identity_plus_v1_monthly'`, `'team_plus_v1_yearly'`)
- **capabilities**: Array of feature strings
- **limits**: Hash of resource limits (`-1` represents unlimited/infinity)
- **tier**: Catalogue tier (e.g., `'free'`, `'single_team'`, `'multi_team'`)
- **interval**: Billing interval (`'month'` or `'year'`)
- **region**: Geographic region (e.g., `'EU'`)

## Current Catalogue Tiers

### Free (free_v1) - free tier
Default without subscription, when billing enabled. When billing disabled, capabilities are not enforced.

**Capabilities:**
- `create_secrets` - Can create basic secrets
- `view_receipt` - Can view secret metadata
- `api_access`

**Limits:**
- `tenancy`: multi
- `secrets_per_day`:
- `secret_lifetime`: 604800 (7 days in seconds)

### Identity Plus (identity_plus_v1) - individuals tier

Individuals

**Capabilities:**
- All Free tier capabilities
- `custom_domains` - Can configure custom domains
- `extended_default_expiration` - 30 days
- `custom_branding`
- `branded_homepage`

**Limits:**
- `teams`: 0
- `secret_lifetime`: 2592000 (30 days)

### Team Plus (team_plus_v1) - single_team tier
Multiple accounts one one team.

**Capabilities:**
- All Identity Plus capabilities
- `manage_teams`
- `manage_members`

*Limits:**
- `tenancy`: multi
- `teams`: 1
- `members_per_team`: 10
- `custom_domains`: -1 (unlimited)
- `secret_lifetime`: 30 days


### Organization Plus (org_plus_v1) - multi_team tier
Unlimited teams for organizations.

**Capabilities:**
- All Team Plus capabilities
- `audit_logs` - Access to audit log features
- `sso`

**Limits:**
- `tenancy`: multi
- `teams`: -1 (unlimited)
- `members_per_team`: 25
- `custom_domains`: -1 (unlimited)
- `secret_lifetime`: 30 days


### Organization Max (org_max_v1) - dedicated tier
Unlimited teams for organizations.

**Capabilities:**
- All Organization Plus capabilities


**Limits:**
- `tenancy`: single
- `teams`: -1 (unlimited)
- `members_per_team`: -1 (unlimited)
- `custom_domains`: -1 (unlimited)
- `secret_lifetime`: custom


## Legacy "Plans"

This plan is grandfathered in for all identity customers <= 2025-12-31.

### Identity Plus (identity) - single_team tier

**Capabilities:**
- `create_secrets`
- `view_receipt`
- `custom_domains`
- `extended_default_expiration`
- `custom_branding`
- `branded_homepage`

**Limits:**
- `teams`: 1
- `members_per_team`: 5
- `secret_lifetime`: 30 days
- `custom_domains`: 25 (more available by request -- sold as "unlimited")


## Capability Categories (work in progress)

**Core:**
- `create_secrets`, `view_receipt`, `extended_default_expiration`, `api_access`

**Collaboration:**
- `create_team`, `create_organization`, `add_team_members`

**Infrastructure:**
- `custom_domains`, `api_access`

**Support:**
- `community_support`
- `slow_email_support`: 14 days.

**Advanced:**
- `audit_logs`

## Stripe Product Configuration

Each Stripe product must include the following metadata fields to be recognized by the billing system:

### Required Metadata Fields

```json
{
  "app": "onetimesecret",
  "tier": "single_team",
  "region": "EU",
  "tenancy": "multi",
  "capabilities": "create_secrets,view_receipt,api_access,custom_domains,extended_default_expiration",
  "created": "2025-11-23"
}
```

### Optional Metadata Fields

```json
{
  "plan_id": "identity_plus_v1",
  "display_order": "10",
  "show_on_plans_page": "true",
  "limit_teams": "1",
  "limit_members_per_team": "10",
  "limit_custom_domains": "-1",
  "limit_secret_lifetime": "2592000"
}
```

**Notes:**
- `app` must be exactly `"onetimesecret"` (case-sensitive)
- `tier` values: `single_team`, `multi_team`
- `region` examples: `EU`, `CA`, `global`
- `tenancy` values: `multi` (shared infrastructure), `dedicated` (single-tenant)
- `capabilities` is comma-separated list (no spaces)
- `created` is ISO date when product was created
- `plan_id` is optional; if not provided, auto-generated as `{tier}_{interval}_{region}`
- `display_order` controls sort order on plans page (lower = earlier, default: 100)
- `show_on_plans_page` controls visibility on public plans page (true/false/yes/no/1/0, default: false)
- `limit_*` fields: use `-1` for unlimited, positive integers otherwise
- Prices must have `type: "recurring"` to be included in plan sync

### Complete Example

```json
{
  "app": "onetimesecret",
  "plan_id": "team_plus_v1",
  "tier": "multi_team",
  "region": "EU",
  "tenancy": "multi",
  "capabilities": "create_secrets,view_receipt,api_access,custom_domains,extended_default_expiration,manage_teams,manage_members",
  "created": "2025-11-23",
  "display_order": "20",
  "show_on_plans_page": "true",
  "limit_teams": "1",
  "limit_members_per_team": "10",
  "limit_custom_domains": "-1",
  "limit_secret_lifetime": "2592000"
}
```

## Validation and Sync

### Validate Product Metadata

Check which products have missing or invalid metadata:

```bash
bin/ots billing validate
```

This will show all products and list any metadata errors.

### Sync Plans from Stripe

After configuring product metadata in Stripe, sync to the local Redis cache:

```bash
bin/ots billing sync
```

This fetches all products with valid metadata and caches them as Plan records. Only products with:
- All required metadata fields
- At least one recurring price
- `app: "onetimesecret"`

will be synced.

### View Cached Plans

```bash
bin/ots billing plans
```

Shows all currently cached plans in Redis.

## Upgrade Paths (wip)

Recommended upgrade paths for missing capabilities:

- Need `custom_domains`: Free → Identity Plus
- Need `api_access` or `audit_logs`: Identity Plus → Team-Plus
- Need `create_teams` (multiple teams) or `sso`: Organization Plus or Max
- Need `tenancy` single: Organization Max
