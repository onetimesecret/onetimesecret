# Duplicate Plans on Plans Page

## Overview

The plans page (`/billing/:extid/plans`) can show duplicate plans if the same product exists in both the Stripe-synced cache and the config-only cache with different identifiers.

Key components:
- `Billing::Plan.refresh_from_stripe` — pulls products+prices from Stripe into Redis
- `Billing::Plan.upsert_config_only_plans` — adds plans from billing.yaml
- `Billing::Plan.prune_stale_plans` — soft-deletes plans no longer in Stripe (sets `active: false` but does NOT remove from Redis)
- `BillingController#list_plans` — returns all plans where `show_on_plans_page == 'true'` (does NOT filter by `active`)

## How Duplicates Happen

Plans are now keyed by canonical family ID (e.g., `free_v1`, `identity_plus_v1`). Duplicates can occur if:

1. A product exists in both Stripe and config with different `plan_id` metadata
2. The `stripe_product_id` doesn't match between sources
3. Manual entries were created with non-canonical IDs

| Source | Expected ID | Problem |
|--------|-------------|---------|
| Stripe sync | `free_v1` | Product metadata `plan_id` must match config key |
| Config | `free_v1` | Must use canonical family ID |

## Diagnosis

From `bin/console`:

```ruby
# List all plans with free tier
Billing::Plan.list_plans.select { |p| p.tier == 'free' }.map { |p|
  [p.plan_id, p.show_on_plans_page, p.region, p.stripe_product_id]
}
```

If this returns multiple entries for the same tier, check:
1. Product metadata `plan_id` in Stripe matches the config key
2. No non-canonical IDs exist

## Resolution

### Step 1: Verify Stripe product metadata

In the Stripe Dashboard:
1. Go to **Product Catalog**
2. Find the product by ID or name
3. Under **Metadata**, ensure `plan_id` is the canonical family ID (e.g., `free_v1`)

### Step 2: Re-sync with --clear

```bash
bin/ots billing catalog sync --clear
```

This removes stale cache entries and re-syncs from Stripe.

### Step 3: Verify

```ruby
Billing::Plan.list_plans.select { |p| p.tier == 'free' }.size
# Should return 1
```

## Prevention

1. Always use canonical family IDs in Stripe product metadata
2. Run `bin/ots billing catalog validate` before deploying config changes
3. Schema validation rejects non-canonical plan IDs at YAML load time
