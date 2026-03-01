# Duplicate Product Handling

## Overview

The `bin/ots billing products create` command automatically detects and handles duplicate products to prevent accidental creation of multiple products with the same `plan_id`.

This follows Stripe's best practice: "To make your script idempotent and resilient to errors, you can safely try to create the product first, then update it if the product already exists."

## How It Works

### Uniqueness Check

Products are considered duplicates if they have the same:
- `metadata['app']` = `'onetimesecret'`
- `metadata['plan_id']` (e.g., `'identity_v1_monthly'`)

The `plan_id` is the primary identifier since it uniquely combines tier, interval, and region.

### Detection Process

1. **Before creating**: Command searches existing Stripe products
2. **If duplicate found**: User is prompted with options
3. **If no duplicate**: Product is created normally

## User Experience

### First Run (No Duplicate)

```bash
$ bin/ots billing products create "Identity Plus" \
  --plan-id=identity_v1_monthly \
  --tier=single_team \
  --capabilities="create_secrets,custom_domains"

Creating product 'Identity Plus' with metadata:
  app: onetimesecret
  plan_id: identity_v1_monthly
  tier: single_team
  capabilities: create_secrets,custom_domains
  ...

Proceed? (y/n): y

Product created successfully:
  ID: prod_xxx
  Name: Identity Plus

Next steps:
  bin/ots billing prices create prod_xxx --amount=2900 --currency=cad --interval=month
```

### Second Run (Duplicate Detected)

```bash
$ bin/ots billing products create "Identity Plus Updated" \
  --plan-id=identity_v1_monthly \
  --tier=single_team \
  --capabilities="create_secrets,custom_domains,audit_logs"

⚠️  Product already exists with plan_id: identity_v1_monthly
  Product ID: prod_xxx
  Name: Identity Plus
  Tier: single_team
  Region: us-east
  Capabilities: create_secrets, custom_domains

What would you like to do?
  1) Update existing product with new values
  2) Create duplicate anyway (not recommended)
  3) Cancel

Choice (1-3): 1

Updating product prod_xxx...

✓ Product updated successfully:
  ID: prod_xxx
  Name: Identity Plus Updated

Next steps:
  bin/ots billing sync  # Update Redis cache
  bin/ots billing products show prod_xxx  # View details
```

## Options

### Interactive Choice (Default)

When a duplicate is detected, you'll be prompted to:

1. **Update existing product** - Replaces metadata and name with new values
2. **Create duplicate anyway** - Creates a second product (not recommended)
3. **Cancel** - Abort operation

### Force Mode

Skip duplicate detection entirely:

```bash
bin/ots billing products create "Identity Plus" \
  --plan-id=identity_v1_monthly \
  --force
```

**When to use `--force`:**
- Testing multiple product configurations
- Intentionally creating products with same metadata
- Automated scripts that handle duplicates differently

**Not recommended for:**
- Production use
- Standard plan setup

## Use Cases

### 1. Setup Script (Idempotent)

Run this script multiple times safely:

```bash
#!/bin/bash
# scripts/setup_stripe_plans.sh

source .env

# First run: Creates product
# Subsequent runs: Prompts to update
bin/ots billing products create "Identity Plus" \
  --plan-id=identity_v1_monthly \
  --tier=single_team \
  --capabilities="create_secrets,custom_domains" \
  --limit_teams=0 \
  --limit_secret_lifetime=2592000

# Auto-answer with update (option 1)
echo "1" | bin/ots billing products create "Team Plus" \
  --plan-id=team_plus_v1_monthly \
  --tier=multi_team \
  --capabilities="create_secrets,manage_teams"
```

### 2. Updating Plan Metadata

Change capabilities or limits without recreating:

```bash
# Initial creation
bin/ots billing products create "Identity Plus" \
  --plan-id=identity_v1_monthly \
  --capabilities="create_secrets,custom_domains"

# Later: Add audit_logs capability
bin/ots billing products create "Identity Plus" \
  --plan-id=identity_v1_monthly \
  --capabilities="create_secrets,custom_domains,audit_logs"

# Choose option 1 to update
```

### 3. Testing Product Variations

Use `--force` to test different configurations:

```bash
# Create test variant 1
bin/ots billing products create "Test A" \
  --plan-id=test_v1 \
  --capabilities="cap_a" \
  --force

# Create test variant 2 (same plan_id)
bin/ots billing products create "Test B" \
  --plan-id=test_v1 \
  --capabilities="cap_b" \
  --force

# Clean up later in Stripe Dashboard
```

## Technical Details

### Implementation

```ruby
# Check for existing product by plan_id
def find_existing_product(plan_id)
  Stripe::Product.list(active: true, limit: 100).data.find do |product|
    product.metadata['app'] == 'onetimesecret' &&
    product.metadata['plan_id'] == plan_id
  end
end
```

### Update vs Create

**Update operation (`Stripe::Product.update`):**
- Replaces product name
- Replaces all metadata fields
- Adds/updates marketing features
- **Preserves existing prices**

**Create operation (`Stripe::Product.create`):**
- Creates new product ID
- New metadata
- No prices (must create separately)

### Error Handling

- **Stripe API unavailable**: Warning shown, creation continues
- **Network timeout during check**: Defaults to allowing creation
- **Invalid choice (1-3)**: Cancels operation

## Best Practices

✅ **DO:**
- Use consistent `plan_id` format: `{tier}_{version}_{interval}`
- Let command detect and update existing products
- Run `bin/ots billing sync` after updates
- Review changes with `bin/ots billing products show`

❌ **DON'T:**
- Use `--force` for production setups
- Create multiple products with same `plan_id`
- Skip the sync step after updating metadata
- Change `plan_id` of existing products (create new instead)

## Related Commands

```bash
# View existing products
bin/ots billing products

# Update product metadata directly
bin/ots billing products update prod_xxx --capabilities="new,caps"

# Sync to Redis cache
bin/ots billing sync

# Validate all product metadata
bin/ots billing validate
```

## Troubleshooting

### "Warning: Could not search for existing products"

**Cause**: Stripe API error during duplicate check

**Solution**: Check `.env` has valid `STRIPE_API_KEY`, or use `--force` to skip check

### Product created but not in Redis cache

**Cause**: Haven't synced after creation

**Solution**: Run `bin/ots billing sync`

### Multiple products with same plan_id

**Cause**: Created with `--force` or before duplicate detection was added

**Solution**: Archive duplicates in Stripe Dashboard, keep one active

## Integration with Familia v2

After updating products, sync updates Redis cache with native types:

```bash
bin/ots billing sync
# Populates:
# - set :capabilities
# - set :features
# - hashkey :limits (flattened "teams.max" => "1")
# - stringkey :stripe_data_snapshot (JSON backup)
```

The duplicate detection ensures your Redis cache stays consistent with a single authoritative product per `plan_id`.
