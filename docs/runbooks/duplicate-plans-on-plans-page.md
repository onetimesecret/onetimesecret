# Duplicate Plans on Plans Page

## Overview

The plans page (`/billing/:extid/plans`) can show two Free plans. This happens when the Free product in Stripe has a recurring price attached, causing it to exist in both the Stripe-synced cache (`free_v1_monthly`) and the config-only cache (`free_v1`).

Key components:
- `Billing::Plan.refresh_from_stripe` — pulls products+prices from Stripe into Redis
- `Billing::Plan.upsert_config_only_plans` — adds plans with `prices: []` from billing.yaml
- `Billing::Plan.prune_stale_plans` — soft-deletes plans no longer in Stripe (sets `active: false` but does NOT remove from Redis)
- `BillingController#list_plans` — returns all plans where `show_on_plans_page == 'true'` (does NOT filter by `active`)

## How Duplicates Happen

Config-only plans (like `free_v1`) have `prices: []` in billing.yaml. They get their plan ID from the bare YAML key: `free_v1`.

If someone adds a recurring price to that product in Stripe (even $0/month), `refresh_from_stripe` creates a second entry with the interval suffix: `free_v1_monthly`.

Then `upsert_config_only_plans` also creates `free_v1` from config. Both have `show_on_plans_page: true`. The plans page shows both.

| Source | Plan ID | Interval | How created |
|--------|---------|----------|-------------|
| Stripe sync | `free_v1_monthly` | `month` | `refresh_from_stripe` found a recurring price |
| Config | `free_v1` | `nil` | `upsert_config_only_plans` from billing.yaml |

## Diagnosis

From `bin/console`:

```ruby
# List all plans with free tier
Billing::Plan.list_plans.select { |p| p.tier == 'free' }.map { |p|
  [p.plan_id, p.show_on_plans_page, p.interval, p.region, p.stripe_price_id]
}
```

If this returns two entries, the one with a `stripe_price_id` and an interval is the Stripe-synced duplicate.

To inspect the offending price:

```ruby
p = Billing::Plan.load('free_v1_monthly')
[p.stripe_price_id, p.stripe_product_id, p.amount]
# e.g. => ["price_xxx", "prod_xxx", "0"]
```

## Resolution

### Step 1: Remove the price in Stripe

In the Stripe Dashboard:
1. Go to **Product Catalog**
2. Find the product by ID (e.g., `prod_xxx`) or search for "Free"
3. Under **Pricing**, find the recurring price (e.g., `price_xxx`)
4. Delete the price if Stripe allows it (prices with no usage can be deleted). Otherwise, archive it.

Either way, the price will be excluded from `active: true` queries during the next sync.

### Step 2: Re-sync with --clear

A plain `catalog pull` is not sufficient. `prune_stale_plans` only soft-deletes (sets `active: false`), but `list_plans` does not filter by `active` — it returns all plans where the Redis key exists. The soft-deleted plan keeps appearing on the plans page.

```bash
bin/ots billing catalog pull --clear
```

`--clear` calls `Billing::Plan.clear_cache` which runs `destroy!` on each plan (removes Redis keys entirely), then rebuilds from Stripe + config.

### Step 3: Verify

From `bin/console`:

```ruby
Billing::Plan.list_plans.select { |p| p.tier == 'free' }.map { |p|
  [p.plan_id, p.show_on_plans_page, p.interval]
}
# Expected: [["free_v1", "true", nil]]
```

## Why --clear Is Required

`prune_stale_plans` soft-deletes: it sets `active = 'false'` but the plan hash remains in Redis. `list_plans` returns all plans where `exists?` is true (ignores `active`), and the controller filters by `show_on_plans_page`, not `active`. A soft-deleted plan with `show_on_plans_page: true` continues to appear until the Redis keys are fully removed via `--clear`.
