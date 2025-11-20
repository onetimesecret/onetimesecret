# Billing CLI Usage Guide

The `bin/ots billing` command suite provides tools for managing Stripe products, prices, and plan cache synchronization.

## Prerequisites

1. **Billing Configuration**
   - File: `etc/billing.yaml` must exist
   - Must have `enabled: true`

2. **Stripe API Key**
   - Set environment variable: `STRIPE_KEY=sk_test_...` or `STRIPE_KEY=sk_live_...`
   - Or configure in `etc/billing.yaml`: `stripe_key: <%= ENV['STRIPE_KEY'] %>`

3. **Redis Running**
   - Required for plan cache operations
   - Default: `valkey://127.0.0.1:2121/0`

## Commands Overview

```bash
bin/ots billing                 # Show help
bin/ots billing plans           # List cached plans
bin/ots billing products        # List Stripe products
bin/ots billing prices          # List Stripe prices
bin/ots billing sync            # Sync from Stripe to cache
bin/ots billing validate        # Validate product metadata
```

## Command Reference

### `bin/ots billing plans`

List plans cached in Redis from previous Stripe sync.

**Options:**
- `--refresh` - Refresh cache from Stripe before listing

**Examples:**
```bash
# List cached plans
bin/ots billing plans

# Refresh and list
bin/ots billing plans --refresh
```

**Output:**
```
PLAN ID              TIER               INTERVAL   AMOUNT     REGION       CAPS
------------------------------------------------------------------------------
identity_v1          single_team        month      USD 9.00   us-east      3
dedicated_v1         multi_team         month      USD 29.00  global       5

Total: 2 plan(s)
```

---

### `bin/ots billing products`

List all products from Stripe API.

**Options:**
- `--active-only` - Show only active products (default: true)
- `--no-active-only` - Show all products including archived

**Examples:**
```bash
# List active products
bin/ots billing products

# List all products
bin/ots billing products --no-active-only
```

**Output:**
```
ID                     NAME                                     PLAN_ID            TIER         REGION   ACTIVE
--------------------------------------------------------------------------------------------------------------
prod_ABC123xyz         Identity Plan                            identity_v1        single_team  us-east  yes
prod_DEF456abc         Dedicated Plan                           dedicated_v1       multi_team   global   yes

Total: 2 product(s)
```

---

### `bin/ots billing products create`

Create a new Stripe product with required metadata.

**Arguments:**
- `name` - Product name (optional, will prompt if not provided)

**Options:**
- `--interactive` - Interactive mode with prompts for all fields
- `--plan-id STRING` - Plan identifier (e.g., identity_v1)
- `--tier STRING` - Tier name (e.g., single_team, multi_team)
- `--region STRING` - Region code (e.g., us-east, global)
- `--capabilities STRING` - Comma-separated capabilities

**Required Metadata Fields:**
- `app` - Always set to "onetimesecret"
- `plan_id` - Unique plan identifier
- `tier` - Tier classification
- `region` - Geographic region
- `capabilities` - Feature list (comma-separated)

**Optional Metadata Fields:**
- `limit_teams` - Maximum teams (-1 for unlimited)
- `limit_members_per_team` - Maximum members per team (-1 for unlimited)

**Examples:**

**Interactive Mode:**
```bash
bin/ots billing products create --interactive
Product name: Identity Plan
Plan ID (e.g., identity_v1): identity_v1
Tier (e.g., single_team, multi_team): single_team
Region (e.g., us-east, global): us-east
Capabilities (comma-separated): create_secrets,create_team,custom_domains
Limit teams (-1 for unlimited): 1
Limit members per team (-1 for unlimited): -1

Creating product 'Identity Plan' with metadata:
  app: onetimesecret
  plan_id: identity_v1
  tier: single_team
  region: us-east
  capabilities: create_secrets,create_team,custom_domains
  limit_teams: 1
  limit_members_per_team: -1

Proceed? (y/n): y

Product created successfully:
  ID: prod_ABC123xyz
  Name: Identity Plan

Next steps:
  bin/ots billing prices create --product prod_ABC123xyz
```

**Command-Line Mode:**
```bash
bin/ots billing products create \
  "Enterprise Plan" \
  --plan-id enterprise_v1 \
  --tier multi_team \
  --region global \
  --capabilities "create_secrets,create_team,custom_domains,api_access"
```

---

### `bin/ots billing products update`

Update metadata for an existing Stripe product.

**Arguments:**
- `product_id` - Product ID (required, e.g., prod_ABC123xyz)

**Options:**
- `--interactive` - Interactive mode
- `--plan-id STRING` - Update plan ID
- `--tier STRING` - Update tier
- `--region STRING` - Update region
- `--capabilities STRING` - Update capabilities

**Examples:**
```bash
# Update single field
bin/ots billing products update prod_ABC123xyz --tier multi_team

# Interactive update
bin/ots billing products update prod_ABC123xyz --interactive

# Update multiple fields
bin/ots billing products update prod_ABC123xyz \
  --tier enterprise \
  --capabilities "create_secrets,create_team,custom_domains,api_access,priority_support"
```

---

### `bin/ots billing prices`

List all prices from Stripe API.

**Options:**
- `--product STRING` - Filter by product ID
- `--active-only` - Show only active prices (default: true)
- `--no-active-only` - Show all prices

**Examples:**
```bash
# List all prices
bin/ots billing prices

# List prices for specific product
bin/ots billing prices --product prod_ABC123xyz

# List all prices including archived
bin/ots billing prices --no-active-only
```

**Output:**
```
ID                     PRODUCT                AMOUNT       INTERVAL   ACTIVE
------------------------------------------------------------------------------
price_123ABC           prod_ABC123xyz         USD 9.00     month      yes
price_456DEF           prod_ABC123xyz         USD 90.00    year       yes
price_789GHI           prod_DEF456abc         USD 29.00    month      yes

Total: 3 price(s)
```

---

### `bin/ots billing prices create`

Create a new recurring price for a product.

**Arguments:**
- `product_id` - Product ID (optional, will prompt if not provided)

**Options:**
- `--amount INTEGER` - Amount in cents (e.g., 900 for $9.00)
- `--currency STRING` - Currency code (default: usd)
- `--interval STRING` - Billing interval: month, year, week, day (default: month)
- `--interval-count INTEGER` - Number of intervals (default: 1)

**Examples:**

**Interactive Mode:**
```bash
bin/ots billing prices create
Product ID: prod_ABC123xyz
Amount in cents (e.g., 900 for $9.00): 900

Creating price:
  Product: prod_ABC123xyz
  Amount: USD 9.00
  Interval: 1 month(s)

Proceed? (y/n): y

Price created successfully:
  ID: price_123ABC
  Amount: USD 9.00
  Interval: 1 month(s)
```

**Command-Line Mode:**
```bash
# Monthly price
bin/ots billing prices create prod_ABC123xyz --amount 900 --interval month

# Annual price with discount
bin/ots billing prices create prod_ABC123xyz --amount 9000 --interval year

# Quarterly price
bin/ots billing prices create prod_ABC123xyz --amount 2700 --interval month --interval-count 3
```

---

### `bin/ots billing sync`

Synchronize products and prices from Stripe to Redis cache.

**Examples:**
```bash
bin/ots billing sync
```

**Output:**
```
Syncing from Stripe to Redis cache...

Successfully synced 5 plan(s) to cache

To view cached plans:
  bin/ots billing plans
```

**What it does:**
1. Fetches all active products from Stripe
2. For each product, fetches associated prices
3. Combines product metadata + price data
4. Caches in Redis via `Billing::Models::PlanCache`

---

### `bin/ots billing validate`

Validate that all Stripe products have required metadata.

**Examples:**
```bash
bin/ots billing validate
```

**Output (all valid):**
```
Fetching products from Stripe...
✓ All 3 product(s) have valid metadata
```

**Output (with errors):**
```
Fetching products from Stripe...

Identity Plan (prod_ABC123xyz):
  ✗ Missing required metadata field: capabilities
  ✗ Missing required metadata field: region

Enterprise Plan (prod_DEF456abc):
  ✗ Invalid app metadata (should be 'onetimesecret')

2 product(s) have metadata errors

Required metadata fields:
  - app
  - plan_id
  - tier
  - region
  - capabilities
```

---

## Common Workflows

### Creating a Complete New Plan

```bash
# 1. Create the product
bin/ots billing products create --interactive
# Follow prompts...
# Product ID returned: prod_ABC123xyz

# 2. Create monthly price
bin/ots billing prices create prod_ABC123xyz --amount 900 --interval month

# 3. Create annual price (with discount)
bin/ots billing prices create prod_ABC123xyz --amount 9000 --interval year

# 4. Sync to cache
bin/ots billing sync

# 5. Verify
bin/ots billing validate
bin/ots billing plans
```

### Updating Existing Product

```bash
# 1. List products to find ID
bin/ots billing products

# 2. Update metadata
bin/ots billing products update prod_ABC123xyz --capabilities "create_secrets,create_team,api_access"

# 3. Re-sync cache
bin/ots billing sync

# 4. Validate
bin/ots billing validate
```

### Auditing Current Setup

```bash
# Check what's in Stripe
bin/ots billing products
bin/ots billing prices

# Check what's cached
bin/ots billing plans

# Validate metadata
bin/ots billing validate

# Refresh cache if needed
bin/ots billing sync
```

---

## Metadata Requirements

All products **must** include these metadata fields:

| Field | Description | Example Values |
|-------|-------------|----------------|
| `app` | Application identifier | `onetimesecret` |
| `plan_id` | Unique plan identifier | `identity_v1`, `dedicated_v2` |
| `tier` | Plan tier classification | `single_team`, `multi_team`, `enterprise` |
| `region` | Geographic region | `us-east`, `eu-west`, `global` |
| `capabilities` | Comma-separated features | `create_secrets,create_team,custom_domains` |

**Optional metadata:**
- `limit_teams` - Maximum number of teams (-1 = unlimited)
- `limit_members_per_team` - Maximum members per team (-1 = unlimited)
- `limit_secrets_per_month` - Monthly secret creation limit
- `limit_api_calls_per_day` - Daily API call limit

**Common capabilities:**
- `create_secrets` - Create secrets
- `create_team` - Create teams
- `custom_domains` - Use custom domains
- `api_access` - API access
- `priority_support` - Priority customer support
- `advanced_analytics` - Advanced usage analytics
- `sso` - Single sign-on

---

## Troubleshooting

### "Error: Billing not enabled"
- Ensure `etc/billing.yaml` exists
- Check that `billing.enabled: true`

### "Error: STRIPE_KEY not set"
- Set environment variable: `export STRIPE_KEY=sk_test_...`
- Or configure in `etc/billing.yaml`

### "Error: Product not found"
- Verify product ID is correct
- Check you're using the right Stripe account (test vs live keys)

### Metadata validation failures
- Run `bin/ots billing validate` to see which fields are missing
- Update product: `bin/ots billing products update <id> --<field> <value>`
- Re-sync: `bin/ots billing sync`

---

## Development vs Production

**Test Mode (recommended for development):**
```bash
export STRIPE_KEY=sk_test_...
bin/ots billing products
```

**Live Mode (production only):**
```bash
export STRIPE_KEY=sk_live_...
bin/ots billing products
```

**Note:** Test and live modes have completely separate data. Products created in test mode won't appear in live mode.

---

## Integration with Application

The billing CLI manages Stripe data that the application consumes:

1. **Products** → Define what plans are available
2. **Prices** → Define how much plans cost and billing intervals
3. **Plan Cache** → Application reads from this for fast access

**Sync workflow:**
```
Stripe (products + prices)
  → bin/ots billing sync
  → Redis (PlanCache)
  → Application reads from cache
```

**When to sync:**
- After creating/updating products in Stripe Dashboard
- After using CLI to create/update products
- On deployment to refresh cache
- Periodically (automated job recommended)

---

## See Also

- Stripe Products API: https://docs.stripe.com/api/products
- Stripe Prices API: https://docs.stripe.com/api/prices
- `apps/web/billing/models/plan_cache.rb` - Cache implementation
- `lib/onetime/billing_config.rb` - Billing configuration loader
