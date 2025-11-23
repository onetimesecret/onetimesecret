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
- **region**: Geographic region (e.g., `'us-east'`)

## Current Catalogue Tiers

### Free (free_v1) - free tier
Default without subscription, when billing enabled. When billing disabled, capabilities are not enforced.

**Capabilities:**
- `create_secrets` - Can create basic secrets
- `view_metadata` - Can view secret metadata
- `api_access`

**Limits:**
- `tenancy`: multi
- `secrets_per_day`:
- `secret_lifetime`: 604800 (7 days in seconds)

### Identity Plus (identity_plus_v2) - individuals tier

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
- `view_metadata`
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
- `create_secrets`, `view_metadata`, `extended_default_expiration`, `api_access`

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

Each Stripe product should include metadata:

```json
{
  "app": "onetimesecret",
  "plan_id": "identity_v1_monthly",
  "tier": "single_team",
  "region": "us-east",
  "capabilities": "create_secrets,basic_sharing,view_metadata,create_team,custom_domains,extended_default_expiration",
  "limit_teams": "1",
  "limit_members_per_team": "-1",
  "limit_custom_domains": "-1",
  "limit_secret_lifetime": "2592000"
}
```

## Upgrade Paths (wip)

Recommended upgrade paths for missing capabilities:

- Need `custom_domains`: Free → Identity Plus
- Need `api_access` or `audit_logs`: Identity Plus → Team-Plus
- Need `create_teams` (multiple teams) or `sso`: Organization Plus or Max
- Need `tenancy` single: Organization Max
