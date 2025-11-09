# Plan Definitions Reference

This document describes the plan structure and capabilities for Onetime Secret billing.

**Note:** Plan definitions are now stored in Stripe product metadata and cached in Redis via `Billing::Models::PlanCache`. This document serves as reference for understanding plan structure and configuring Stripe products.

## Plan Structure

Each plan consists of:
- **plan_id**: Unique identifier (e.g., `'identity_v1_monthly'`, `'multi_team_v1_yearly'`)
- **capabilities**: Array of feature strings
- **limits**: Hash of resource limits (`-1` represents unlimited/infinity)
- **tier**: Plan tier (e.g., `'free'`, `'single_team'`, `'multi_team'`)
- **interval**: Billing interval (`'month'` or `'year'`)
- **region**: Geographic region (e.g., `'us-east'`)

## Current Plan Tiers

### Free Tier
Default for all organizations without subscription.

**Capabilities:**
- `create_secrets` - Can create basic secrets
- `basic_sharing` - Can share via link/email
- `view_metadata` - Can view secret metadata

**Limits:**
- `secrets_per_day`: 10
- `secret_lifetime`: 604800 (7 days in seconds)

### Identity Plus (v1)
Single team plan for professionals.

**Capabilities:**
- All Free tier capabilities
- `create_team` - Can create ONE team
- `custom_domains` - Can configure custom domains
- `priority_support` - Priority customer support
- `extended_lifetime` - Longer secret retention

**Limits:**
- `teams`: 1
- `members_per_team`: -1 (unlimited)
- `custom_domains`: -1 (unlimited)
- `secret_lifetime`: 2592000 (30 days)

### Multi-Team (v1)
Unlimited teams for organizations.

**Capabilities:**
- All Identity Plus capabilities
- `create_teams` - Can create MULTIPLE teams (note plural vs. singular)
- `api_access` - API access enabled
- `audit_logs` - Access to audit log features
- `advanced_analytics` - Advanced usage analytics

**Limits:**
- `teams`: -1 (unlimited)
- `members_per_team`: -1 (unlimited)
- `custom_domains`: -1 (unlimited)
- `api_rate_limit`: 10000 (requests per hour)
- `secret_lifetime`: 7776000 (90 days)

## Legacy Plans (Grandfathered)

### Identity Plus (v0)
Lower limits than v1, no custom domains.

**Capabilities:**
- `create_secrets`, `basic_sharing`, `view_metadata`
- `create_team`
- `priority_support`
- **No** `custom_domains`

**Limits:**
- `teams`: 1
- `members_per_team`: 10
- `secret_lifetime`: 1209600 (14 days)

### Multi-Team (v0)
Legacy multi-team plan with lower limits.

**Capabilities:**
- `create_secrets`, `basic_sharing`, `view_metadata`
- `create_teams`
- `api_access`, `priority_support`
- **No** `custom_domains` or `audit_logs`

**Limits:**
- `teams`: -1 (unlimited)
- `members_per_team`: 25
- `api_rate_limit`: 5000
- `secret_lifetime`: 2592000 (30 days)

## Capability Categories

**Core:**
- `create_secrets`, `basic_sharing`, `view_metadata`

**Collaboration:**
- `create_team`, `create_teams`

**Infrastructure:**
- `custom_domains`, `api_access`

**Support:**
- `priority_support`

**Advanced:**
- `audit_logs`, `advanced_analytics`, `extended_lifetime`

## Stripe Product Configuration

Each Stripe product should include metadata:

```json
{
  "app": "onetimesecret",
  "plan_id": "identity_v1_monthly",
  "tier": "single_team",
  "region": "us-east",
  "capabilities": "create_secrets,basic_sharing,view_metadata,create_team,custom_domains,priority_support,extended_lifetime",
  "limit_teams": "1",
  "limit_members_per_team": "-1",
  "limit_custom_domains": "-1",
  "limit_secret_lifetime": "2592000"
}
```

## Upgrade Paths

Recommended upgrade paths for missing capabilities:

- Need `custom_domains`: Free → Identity Plus
- Need `api_access` or `audit_logs`: Identity Plus → Multi-Team
- Need `create_teams` (multiple teams): Free or Identity → Multi-Team

## Plan Naming

Human-readable plan names:
- `free` → "Free"
- `identity_v1` → "Identity Plus"
- `multi_team_v1` → "Multi-Team"
- Legacy plans append version: "Identity Plus (v0)"
