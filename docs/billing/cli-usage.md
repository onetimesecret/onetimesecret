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

### `bin/ots billing products show`

Show detailed information about a specific product including metadata and associated prices.

**Arguments:**
- `product_id` - Product ID (required, e.g., prod_ABC123xyz)

**Examples:**
```bash
bin/ots billing products show prod_ABC123xyz

Product Details:
  ID: prod_ABC123xyz
  Name: Identity Plan
  Active: yes
  Description: Professional plan for individuals

Metadata:
  app: onetimesecret
  plan_id: identity_v1
  tier: single_team
  region: us-east
  capabilities: create_secrets,create_team,custom_domains
  limit_teams: 1
  limit_members_per_team: -1

Prices:
  price_123ABC - USD 9.00/month (active)
  price_456DEF - USD 90.00/year (active)
```

**Displayed Information:**
- Product ID, name, and active status
- Product description (if set)
- All metadata fields (app, plan_id, tier, capabilities, limits)
- All associated prices with amounts and intervals

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
4. Caches in Redis via `Billing::Plan`

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
  → Redis (Plan model)
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
- `apps/web/billing/models/plan.rb` - Plan cache implementation
- `lib/onetime/billing_config.rb` - Billing configuration loader

---

## New Commands (Customers, Subscriptions, Invoices, Events)

### `bin/ots billing customers`

List all Stripe customers with optional filtering.

**Options:**
- `--email STRING` - Filter by exact email address
- `--limit INTEGER` - Maximum results to return (default: 100)

**Examples:**
```bash
# List all customers
bin/ots billing customers

# Find customer by email
bin/ots billing customers --email user@example.com

# List first 10 customers
bin/ots billing customers --limit 10
```

**Output:**
```
ID                     EMAIL                          NAME                      CREATED
------------------------------------------------------------------------------------------
cus_ABC123xyz          user@example.com               John Doe                  2024-08-26
cus_DEF456abc          jane@example.com               Jane Smith                2024-08-25

Total: 2 customer(s)
```

---

### `bin/ots billing subscriptions`

List Stripe subscriptions with comprehensive filtering.

**Options:**
- `--status STRING` - Filter by status (active, past_due, canceled, incomplete, trialing, unpaid)
- `--customer STRING` - Filter by customer ID
- `--limit INTEGER` - Maximum results to return (default: 100)

**Examples:**
```bash
# List all subscriptions
bin/ots billing subscriptions

# List only active subscriptions
bin/ots billing subscriptions --status active

# List subscriptions for a specific customer
bin/ots billing subscriptions --customer cus_ABC123xyz

# Find past due subscriptions
bin/ots billing subscriptions --status past_due
```

**Output:**
```
ID                     CUSTOMER               STATUS       PERIOD END
----------------------------------------------------------------------
sub_ABC123xyz          cus_DEF456abc          active       2025-12-19
sub_GHI789def          cus_JKL012ghi          past_due     2025-11-15

Total: 2 subscription(s)

Statuses: active, past_due, canceled, incomplete, trialing, unpaid
```

**Status Meanings:**
- `active` - Subscription is current and active
- `past_due` - Payment failed, awaiting retry
- `canceled` - Subscription has been canceled
- `incomplete` - Initial payment not yet succeeded
- `trialing` - In trial period
- `unpaid` - Payment failed after retry attempts

---

### `bin/ots billing invoices`

List Stripe invoices with multiple filter options.

**Options:**
- `--status STRING` - Filter by status (draft, open, paid, uncollectible, void)
- `--customer STRING` - Filter by customer ID
- `--subscription STRING` - Filter by subscription ID
- `--limit INTEGER` - Maximum results to return (default: 100)

**Examples:**
```bash
# List all invoices
bin/ots billing invoices

# List unpaid invoices
bin/ots billing invoices --status open

# List invoices for a customer
bin/ots billing invoices --customer cus_ABC123xyz

# List invoices for a subscription
bin/ots billing invoices --subscription sub_ABC123xyz

# List paid invoices
bin/ots billing invoices --status paid
```

**Output:**
```
ID                     CUSTOMER               AMOUNT       STATUS     CREATED
--------------------------------------------------------------------------------
in_ABC123xyz           cus_DEF456abc          USD 9.00     paid       2024-11-19
in_GHI789def           cus_JKL012ghi          USD 29.00    open       2024-11-18

Total: 2 invoice(s)

Statuses: draft, open, paid, uncollectible, void
```

**Status Meanings:**
- `draft` - Invoice created but not finalized
- `open` - Invoice sent to customer, awaiting payment
- `paid` - Invoice has been paid
- `uncollectible` - Invoice marked as uncollectible after failed collection
- `void` - Invoice voided/canceled

---

### `bin/ots billing events`

View recent Stripe events for debugging and monitoring.

**Options:**
- `--type STRING` - Filter by event type (e.g., customer.created, invoice.paid)
- `--limit INTEGER` - Maximum results to return (default: 20)

**Examples:**
```bash
# List recent events
bin/ots billing events

# Show last 50 events
bin/ots billing events --limit 50

# Filter by event type
bin/ots billing events --type customer.created

# Track invoice payments
bin/ots billing events --type invoice.paid

# Monitor subscription changes
bin/ots billing events --type subscription.updated
```

**Output:**
```
ID                     TYPE                                CREATED
----------------------------------------------------------------------
evt_ABC123xyz          customer.created                    2024-11-19 14:22:31
evt_DEF456abc          invoice.paid                        2024-11-19 14:20:15
evt_GHI789def          subscription.created                2024-11-19 14:19:45

Total: 3 event(s)

Common types: customer.created, customer.updated, invoice.paid,
              subscription.created, subscription.updated, payment_intent.succeeded
```

**Common Event Types:**
- `customer.created` - New customer created
- `customer.updated` - Customer details changed
- `customer.deleted` - Customer deleted
- `invoice.created` - New invoice generated
- `invoice.paid` - Invoice payment succeeded
- `invoice.payment_failed` - Invoice payment failed
- `subscription.created` - New subscription started
- `subscription.updated` - Subscription details changed
- `subscription.deleted` - Subscription canceled/ended
- `payment_intent.succeeded` - Payment processed successfully
- `payment_intent.payment_failed` - Payment processing failed

---

### `bin/ots billing customers create`

Create a new Stripe customer.

**Options:**
- `--email STRING` - Customer email (required)
- `--name STRING` - Customer name (optional)
- `--interactive` - Interactive mode with prompts

**Examples:**
```bash
# Command-line mode
bin/ots billing customers create --email user@example.com --name "John Doe"

# Interactive mode
bin/ots billing customers create --interactive
Email: user@example.com
Name (optional): John Doe

Creating customer:
  Email: user@example.com
  Name: John Doe

Proceed? (y/n): y

Customer created successfully:
  ID: cus_ABC123xyz
  Email: user@example.com
  Name: John Doe
```

---

### `bin/ots billing subscriptions cancel`

Cancel a subscription either at period end or immediately.

**Arguments:**
- `subscription_id` - Subscription ID (sub_xyz)

**Options:**
- `--immediately` - Cancel immediately instead of at period end (default: false)
- `--yes` - Skip confirmation prompt (default: false)

**Examples:**
```bash
# Cancel at period end (default - allows customer to use service until paid period ends)
bin/ots billing subscriptions cancel sub_ABC123xyz

Subscription: sub_ABC123xyz
Customer: cus_DEF456abc
Status: active
Current period end: 2025-12-19 00:00:00 UTC

Will cancel at period end: 2025-12-19 00:00:00 UTC

Proceed? (y/n): y

Subscription canceled successfully
Status: active
Will end at: 2025-12-19 00:00:00 UTC

# Cancel immediately (terminates access immediately)
bin/ots billing subscriptions cancel sub_ABC123xyz --immediately

⚠️  Will cancel IMMEDIATELY

Proceed? (y/n): y

Subscription canceled successfully
Status: canceled
Canceled at: 2025-11-19 14:30:00 UTC

# Cancel without confirmation (for automation)
bin/ots billing subscriptions cancel sub_ABC123xyz --immediately --yes
```

**Behavior:**
- **Default**: Subscription continues until end of current billing period, then cancels
- **--immediately**: Subscription terminates immediately, access revoked
- Both methods are non-destructive - subscription data remains in Stripe

---

### `bin/ots billing test create-customer`

Create a test customer with attached payment method for development/testing. **Test mode only.**

**Options:**
- `--with-card` - Attach test card (default: true)

**Examples:**
```bash
# Create test customer with card
bin/ots billing test create-customer

Creating test customer:
  Email: test-a3f9@example.com

Customer created:
  ID: cus_TEST123xyz
  Email: test-a3f9@example.com

Test card attached:
  Payment method: pm_TEST456abc
  Card: Visa ****4242
  Expiry: 12/2027

Test customer ready for use!

Next steps:
  bin/ots billing subscriptions create --customer cus_TEST123xyz

# Create without payment method
bin/ots billing test create-customer --no-with-card
```

**Test Card Details:**
- Card number: 4242 4242 4242 4242
- Brand: Visa
- Always succeeds for test charges
- See [Stripe test cards](https://stripe.com/docs/testing) for other scenarios

**Notes:**
- Only works with test API keys (sk_test_*)
- Generates random email address to avoid conflicts
- Customer includes description with creation timestamp
- Useful for testing subscription flows, payments, webhooks

---

### `bin/ots billing subscriptions pause`

Pause a subscription to stop billing while maintaining customer access.

**Arguments:**
- `subscription_id` - Subscription ID (sub_xyz)

**Options:**
- `--yes` - Skip confirmation prompt (default: false)

**Examples:**
```bash
# Pause subscription with confirmation
bin/ots billing subscriptions pause sub_ABC123xyz

Subscription: sub_ABC123xyz
Customer: cus_DEF456abc
Status: active

Pause subscription? (y/n): y

Subscription paused successfully
Status: active
Paused: Billing paused, access continues

# Pause without confirmation
bin/ots billing subscriptions pause sub_ABC123xyz --yes
```

**Behavior:**
- Customer retains access to service
- Billing is paused - no invoices generated
- Subscription remains in "active" status
- Use for temporary holds, payment issues, or seasonal pauses
- Resume with `billing subscriptions resume`

---

### `bin/ots billing subscriptions resume`

Resume a paused subscription to restart billing.

**Arguments:**
- `subscription_id` - Subscription ID (sub_xyz)

**Options:**
- `--yes` - Skip confirmation prompt (default: false)

**Examples:**
```bash
# Resume subscription with confirmation
bin/ots billing subscriptions resume sub_ABC123xyz

Subscription: sub_ABC123xyz
Customer: cus_DEF456abc
Status: active
Currently paused: Yes

Resume subscription? (y/n): y

Subscription resumed successfully
Status: active
Billing will resume on next period

# Resume without confirmation
bin/ots billing subscriptions resume sub_ABC123xyz --yes
```

**Behavior:**
- Clears pause status from subscription
- Billing resumes at next billing cycle
- No prorated charges for paused period
- Customer access continues uninterrupted

---

### `bin/ots billing customers show`

Show comprehensive customer details including payment methods and subscriptions.

**Arguments:**
- `customer_id` - Customer ID (cus_xxx)

**Examples:**
```bash
bin/ots billing customers show cus_ABC123xyz

Customer Details:
  ID: cus_ABC123xyz
  Email: user@example.com
  Name: John Doe
  Created: 2024-11-19 14:00:00 UTC
  Currency: usd
  Balance: USD 0.00

Payment Methods:
  pm_1ABC123xyz - card (default)
    Card: Visa ****4242 (12/2027)
  pm_2DEF456abc - card
    Card: Mastercard ****5555 (6/2026)

Subscriptions:
  sub_GHI789def - active
    Period: 2024-11-19 00:00:00 UTC to 2024-12-19 00:00:00 UTC
  sub_JKL012ghi - active (paused)
    Period: 2024-11-15 00:00:00 UTC to 2024-12-15 00:00:00 UTC
```

**Information Displayed:**
- Customer metadata (ID, email, name, creation date)
- Account balance and currency
- All payment methods with default indicator
- Card/bank details (brand, last 4 digits, expiry)
- Active subscriptions with pause status
- Subscription billing periods

**Use Cases:**
- Customer support inquiries
- Verify payment method before subscription changes
- Troubleshoot billing issues
- Audit customer account status

---

### `bin/ots billing customers delete`

Delete a Stripe customer with safety checks to prevent accidental data loss.

**Arguments:**
- `customer_id` - Customer ID (cus_xxx)

**Options:**
- `--yes` - Skip confirmation and override active subscription check (default: false)

**Examples:**
```bash
# Safe delete (blocks if active subscriptions exist)
bin/ots billing customers delete cus_ABC123xyz

Customer: cus_ABC123xyz
Email: user@example.com

⚠️  Delete customer permanently? (y/n): y

Customer deleted successfully

# Force delete (even with active subscriptions)
bin/ots billing customers delete cus_ABC123xyz --yes

⚠️  Customer has active subscriptions!
Cancel subscriptions first or use --yes

Customer deleted successfully
```

**Safety Features:**
- Checks for active subscriptions before deletion
- Requires explicit confirmation unless --yes flag used
- Cannot be undone - customer data permanently removed
- Blocks deletion if active subscriptions found (unless --yes)

**Important Notes:**
- Deletion is permanent and cannot be reversed
- Customer data is removed from Stripe
- Subscription history is lost
- Use caution with production customers
- Consider canceling subscriptions first instead of forcing deletion

**Use Cases:**
- Remove test customers after development
- Clean up duplicate customer records
- Handle GDPR deletion requests
- Remove customers after full account closure

---

### `bin/ots billing subscriptions update`

Update an existing subscription's price or quantity with optional proration.

**Arguments:**
- `subscription_id` - Subscription ID (sub_xyz)

**Options:**
- `--price STRING` - New price ID to switch to (price_xxx)
- `--quantity INTEGER` - New quantity for subscription items
- `--prorate` / `--no-prorate` - Enable/disable prorated charges (default: enabled)

**Examples:**
```bash
# Update quantity with proration
bin/ots billing subscriptions update sub_ABC123xyz --quantity 3

Current subscription:
  Subscription: sub_ABC123xyz
  Current price: price_DEF456
  Current quantity: 1
  Amount: USD 9.00

New configuration:
  New price: price_DEF456
  New quantity: 3
  Prorate: true

Proceed? (y/n): y

Subscription updated successfully
Status: active

# Change to different price tier
bin/ots billing subscriptions update sub_ABC123xyz --price price_GHI789

Current subscription:
  Subscription: sub_ABC123xyz
  Current price: price_DEF456
  Current quantity: 1
  Amount: USD 9.00

New configuration:
  New price: price_GHI789
  New quantity: 1
  Prorate: true

Proceed? (y/n): y

Subscription updated successfully
Status: active

# Update without proration
bin/ots billing subscriptions update sub_ABC123xyz --quantity 5 --no-prorate

New configuration:
  New price: price_DEF456
  New quantity: 5
  Prorate: false

Proceed? (y/n): y

Subscription updated successfully
```

**Behavior:**
- **Proration (default)**: Customer charged/credited proportionally for usage changes
- **No proration**: Changes take effect at next billing cycle without adjustments
- Must specify either `--price` or `--quantity` (or both)
- Shows current vs new configuration before proceeding
- Requires confirmation before making changes

**Common Use Cases:**
- Upgrade/downgrade customer to different plan tier
- Adjust quantity for seat-based pricing
- Add/remove licenses mid-billing cycle
- Change billing interval (via price change)

**Proration Explained:**
- Enabled: Customer billed immediately for upgrade, credited for downgrade
- Disabled: Changes apply at next renewal without immediate charges
- Use proration for immediate plan changes
- Disable for changes effective at renewal

---

### `bin/ots billing payment-methods set-default`

Set the default payment method for a customer's recurring invoices.

**Arguments:**
- `payment_method_id` - Payment method ID (pm_xxx)

**Options:**
- `--customer STRING` - Customer ID (cus_xxx) - **required**

**Examples:**
```bash
# Set default payment method
bin/ots billing payment-methods set-default pm_ABC123xyz --customer cus_DEF456

Payment method: pm_ABC123xyz
Customer: cus_DEF456

Set as default? (y/n): y

Default payment method updated successfully
Default: pm_ABC123xyz
```

**Behavior:**
- Validates that payment method belongs to customer
- Updates customer's invoice settings with new default
- All future invoices will use this payment method
- Requires confirmation before making changes

**Validation:**
- Ensures payment method is attached to customer
- Returns error if payment method belongs to different customer
- Payment method must be active and valid

**Use Cases:**
- Customer adds new card and wants to use it by default
- Switch between multiple saved payment methods
- Update default after card expiration
- Customer support: change payment method for failed payments

**Important Notes:**
- Only affects future invoices, not past charges
- Previous payment methods remain attached to customer
- Customer can still have multiple payment methods on file
- Default is used automatically for subscription renewals

---

### `bin/ots billing refunds`

List all refunds with optional filtering by charge.

**Options:**
- `--charge STRING` - Filter by charge ID (ch_xxx)
- `--limit INTEGER` - Maximum results to return (default: 100)

**Examples:**
```bash
# List all refunds
bin/ots billing refunds

Fetching refunds from Stripe...
ID                     CHARGE                 AMOUNT       STATUS     CREATED
------------------------------------------------------------------------------------------
re_ABC123xyz           ch_DEF456abc           USD 9.00     succeeded  2024-11-19 14:00:00
re_GHI789def           ch_JKL012ghi           USD 29.00    succeeded  2024-11-19 13:30:00

Total: 2 refund(s)

# List refunds for specific charge
bin/ots billing refunds --charge ch_ABC123xyz

# List recent refunds only
bin/ots billing refunds --limit 10
```

**Displayed Information:**
- Refund ID
- Charge ID (original payment)
- Refund amount and currency
- Status (succeeded, pending, failed, canceled)
- Creation timestamp

---

### `bin/ots billing refunds create`

Create a refund for a charge (full or partial).

**Options:**
- `--charge STRING` - Charge ID (ch_xxx) **required**
- `--amount INTEGER` - Amount in cents (leave empty for full refund)
- `--reason STRING` - Refund reason: duplicate, fraudulent, requested_by_customer
- `--yes` - Skip confirmation prompt

**Examples:**
```bash
# Full refund with confirmation
bin/ots billing refunds create --charge ch_ABC123xyz --reason requested_by_customer

Charge: ch_ABC123xyz
Amount: USD 29.00
Customer: cus_DEF456ghi

Refund amount: USD 29.00
Reason: requested_by_customer

Create refund? (y/n): y

Refund created successfully:
  ID: re_GHI789jkl
  Amount: USD 29.00
  Status: succeeded

# Partial refund (50%)
bin/ots billing refunds create --charge ch_ABC123xyz --amount 1450 --reason duplicate

# Full refund without confirmation
bin/ots billing refunds create --charge ch_ABC123xyz --reason fraudulent --yes
```

**Refund Reasons:**
- `duplicate` - Duplicate charge
- `fraudulent` - Fraudulent transaction
- `requested_by_customer` - Customer requested refund

**Behavior:**
- Default: Full refund of charge amount
- Partial: Specify --amount in cents
- Customer receives refund to original payment method
- Refund processes asynchronously (usually instant for test mode)
- Stripe fee is not refunded

---

### `bin/ots billing test trigger-webhook`

Trigger test webhook events for development/testing. **Requires Stripe CLI.**

**Arguments:**
- `event_type` - Stripe event type (e.g., customer.subscription.updated)

**Options:**
- `--subscription STRING` - Subscription ID for subscription events
- `--customer STRING` - Customer ID for customer events

**Examples:**
```bash
# Trigger customer creation event
bin/ots billing test trigger-webhook customer.created

Triggering test webhook: customer.created
Command: stripe trigger customer.created

[Stripe CLI output...]

# Trigger subscription update with context
bin/ots billing test trigger-webhook customer.subscription.updated --subscription sub_ABC123xyz

# Trigger invoice payment with customer
bin/ots billing test trigger-webhook invoice.payment_succeeded --customer cus_DEF456abc
```

**Common Event Types:**
- `customer.created` - New customer
- `customer.subscription.created` - New subscription
- `customer.subscription.updated` - Subscription changed
- `customer.subscription.deleted` - Subscription canceled
- `invoice.payment_succeeded` - Payment succeeded
- `invoice.payment_failed` - Payment failed
- `charge.succeeded` - Charge succeeded
- `charge.refunded` - Charge refunded

**Prerequisites:**
- Stripe CLI installed: https://stripe.com/docs/stripe-cli
- Test API key (sk_test_*)
- Webhook endpoint configured locally or with `stripe listen --forward-to`

**Use Cases:**
- Test webhook handlers during development
- Verify subscription lifecycle events
- Debug payment flow edge cases
- Integration testing for automated workflows

---

### `bin/ots billing sigma queries`

List available Stripe Sigma queries for data analysis and reporting.

**Options:**
- `--limit INTEGER` - Maximum results to return (default: 100)

**Examples:**
```bash
# List all saved queries
bin/ots billing sigma queries

Fetching Sigma queries from Stripe...
ID                     NAME                                     CREATED
--------------------------------------------------------------------------------
sqa_ABC123xyz          Monthly Revenue by Plan                  2024-11-19
sqa_DEF456abc          Active Subscriptions Report              2024-11-18
sqa_GHI789def          Churn Analysis                           2024-11-15

Total: 3 query/queries
```

**Note:** Sigma is only available on Stripe paid plans. See [Stripe Sigma docs](https://stripe.com/docs/sigma) for details.

---

### `bin/ots billing sigma run`

Execute a Sigma query and display results.

**Arguments:**
- `query_id` - Sigma query ID (sqa_xxx)

**Options:**
- `--format STRING` - Output format: table, csv, json (default: table)
- `--output FILE` - Save results to file instead of stdout

**Examples:**
```bash
# Run query and display as table
bin/ots billing sigma run sqa_ABC123xyz

Executing Sigma query: Monthly Revenue by Plan
Query: SELECT date_trunc('month', created) as month, ...

MONTH        PLAN_ID          REVENUE
------------------------------------------
2024-11-01   identity_v1      USD 450.00
2024-11-01   multi_team_v1    USD 870.00
2024-10-01   identity_v1      USD 360.00

Total: 3 row(s)

# Export to CSV
bin/ots billing sigma run sqa_ABC123xyz --format csv --output revenue.csv

Query executed successfully
Results saved to: revenue.csv

# Get JSON output
bin/ots billing sigma run sqa_ABC123xyz --format json
```

**Output Formats:**
- `table` - Human-readable ASCII table (default)
- `csv` - Comma-separated values for spreadsheets
- `json` - JSON array for programmatic processing

**Common Queries to Create in Stripe Dashboard:**
- Monthly Recurring Revenue (MRR) by plan
- Subscription churn rate
- Customer lifetime value (LTV)
- Failed payment analysis
- Revenue by region/tier

---

### `bin/ots billing payment-links`

List all Stripe payment links.

**Options:**
- `--active-only` - Show only active links (default: true)
- `--no-active-only` - Show all links including archived
- `--limit INTEGER` - Maximum results to return (default: 100)

**Examples:**
```bash
# List active payment links
bin/ots billing payment-links

Fetching payment links from Stripe...
ID                             PRODUCT/PRICE                  AMOUNT       INTERVAL   ACTIVE
----------------------------------------------------------------------------------------------------
plink_1Q1cjPHA8OZxV3CL         Identity Plan                  USD 9.00     month      yes
plink_1Pq2CEHA8OZxV3CL         Team Plus                      USD 29.00    month      yes

Total: 2 payment link(s)

# List all including archived
bin/ots billing payment-links --no-active-only
```

**Output Information:**
- Payment link ID (full)
- Product name
- Price amount and currency
- Billing interval
- Active status

---

### `bin/ots billing payment-links create`

Create a new payment link for a product price.

**Options:**
- `--price STRING` - Price ID (price_xxx) **required**
- `--quantity INTEGER` - Fixed quantity (default: 1)
- `--allow-quantity` - Allow customer to adjust quantity (default: false)
- `--after-completion STRING` - Redirect URL after successful payment

**Examples:**
```bash
# Create basic payment link
bin/ots billing payment-links create --price price_ABC123xyz

Price: price_ABC123xyz
Product: Identity Plan
Amount: USD 9.00/month

Creating payment link...

Payment link created successfully:
  ID: plink_DEF456ghi
  URL: https://pay.stripe.com/live/def456ghi

Share this link with customers!

# Create with quantity adjustment allowed
bin/ots billing payment-links create --price price_ABC123xyz --allow-quantity

# Create with custom redirect
bin/ots billing payment-links create \
  --price price_ABC123xyz \
  --after-completion https://onetimesecret.com/welcome

# Create for quantity-based pricing
bin/ots billing payment-links create \
  --price price_GHI789jkl \
  --quantity 5 \
  --allow-quantity
```

**Behavior:**
- Creates shareable URL for direct checkout
- No login required for customers
- Automatically creates customer in Stripe
- Starts subscription immediately upon payment
- Link remains active until archived

**Use Cases:**
- Email campaigns with direct upgrade links
- Marketing pages with "Buy Now" buttons
- Sales team sharing with prospects
- Self-service upgrade paths
- Social media promotions

---

### `bin/ots billing payment-links update`

Update an existing payment link's configuration.

**Arguments:**
- `link_id` - Payment link ID (plink_xxx)

**Options:**
- `--active BOOLEAN` - Activate or deactivate link
- `--allow-quantity BOOLEAN` - Enable/disable quantity adjustment
- `--after-completion STRING` - Update redirect URL

**Examples:**
```bash
# Deactivate a payment link
bin/ots billing payment-links update plink_ABC123xyz --active false

Payment link: plink_ABC123xyz
Current status: active

Update status to inactive? (y/n): y

Payment link updated successfully
Status: inactive

# Update redirect URL
bin/ots billing payment-links update plink_ABC123xyz \
  --after-completion https://onetimesecret.com/thank-you

# Enable quantity adjustment
bin/ots billing payment-links update plink_ABC123xyz --allow-quantity true
```

**Note:** Cannot change the associated price on existing link. Create a new link for different price.

---

### `bin/ots billing payment-links show`

Display detailed information about a payment link.

**Arguments:**
- `link_id` - Payment link ID (plink_xxx)

**Examples:**
```bash
bin/ots billing payment-links show plink_ABC123xyz

Payment Link Details:
  ID: plink_ABC123xyz
  URL: https://pay.stripe.com/live/abc123xyz
  Active: yes

Product:
  ID: prod_DEF456ghi
  Name: Identity Plan

Price:
  ID: price_GHI789jkl
  Amount: USD 9.00
  Interval: month

Configuration:
  Quantity: 1 (fixed)
  After completion: https://onetimesecret.com/welcome
```

**Displayed Information:**
- Link ID and shareable URL
- Active status
- Associated product and price details
- Quantity configuration (fixed or adjustable)
- Redirect settings (if configured)

---

### `bin/ots billing payment-links archive`

Archive a payment link (prevents future use while preserving data).

**Arguments:**
- `link_id` - Payment link ID (plink_xxx)

**Options:**
- `--yes` - Skip confirmation prompt

**Examples:**
```bash
# Archive with confirmation
bin/ots billing payment-links archive plink_ABC123xyz

Payment link: plink_ABC123xyz
URL: https://pay.stripe.com/live/abc123xyz
Status: active

Archive this payment link? (y/n): y

Payment link archived successfully
Status: inactive
URL no longer accepts payments

# Archive without confirmation
bin/ots billing payment-links archive plink_ABC123xyz --yes
```

**Behavior:**
- Link becomes inactive immediately
- URL no longer accepts new payments
- Existing subscriptions from link remain active
- Link data preserved for reporting
- Can be reactivated if needed

**Use Cases:**
- End of promotional campaign
- Deprecate old pricing
- Replace with updated link
- Seasonal offer expiration

---

## Advanced Workflows

### Monitor Payment Issues

```bash
# Find past due subscriptions
bin/ots billing subscriptions --status past_due

# Check unpaid invoices
bin/ots billing invoices --status open

# Review recent payment failures
bin/ots billing events --type invoice.payment_failed --limit 10
```

### Customer Support

```bash
# Look up customer
bin/ots billing customers --email user@example.com

# Check their subscription status
bin/ots billing subscriptions --customer cus_ABC123xyz

# Review their invoices
bin/ots billing invoices --customer cus_ABC123xyz

# Check recent activity
bin/ots billing events --limit 20 | grep cus_ABC123xyz
```

### Reconciliation

```bash
# List all paid invoices
bin/ots billing invoices --status paid --limit 500

# Check active subscriptions count
bin/ots billing subscriptions --status active

# Review recent billing events
bin/ots billing events --limit 100
```

### Debugging

```bash
# Monitor webhook events
bin/ots billing events --limit 50

# Check subscription lifecycle events
bin/ots billing events --type subscription.updated --limit 20

# Track failed payments
bin/ots billing events --type payment_intent.payment_failed
```

### Analytics with Sigma

```bash
# List available reports
bin/ots billing sigma queries

# Run revenue analysis
bin/ots billing sigma run sqa_ABC123xyz --format table

# Export monthly data to CSV
bin/ots billing sigma run sqa_DEF456abc --format csv --output mrr-report.csv

# Get churn data as JSON for dashboards
bin/ots billing sigma run sqa_GHI789def --format json
```

### Payment Link Management

```bash
# Create payment link for a plan
bin/ots billing payment-links create --price price_ABC123xyz \
  --after-completion https://onetimesecret.com/welcome

# List all active links
bin/ots billing payment-links

# Check performance of a specific link
bin/ots billing payment-links show plink_DEF456ghi

# Archive expired campaign link
bin/ots billing payment-links archive plink_OLD123xyz --yes

# Create quantity-based link for team seats
bin/ots billing payment-links create \
  --price price_TEAM789 \
  --allow-quantity \
  --after-completion https://onetimesecret.com/team-setup
```

---

## Quick Reference

| Command | Description | Key Options |
|---------|-------------|-------------|
| `billing plans` | List cached plans | `--refresh` |
| `billing products` | List Stripe products | `--active-only` |
| `billing products create` | Create product | `--interactive`, `--plan-id`, `--tier` |
| `billing products show` | Show product details | - |
| `billing products events` | Show product-related events | `--limit`, `--type` |
| `billing products update` | Update product metadata | `--interactive`, metadata fields |
| `billing prices` | List Stripe prices | `--product`, `--active-only` |
| `billing prices create` | Create price | `--amount`, `--interval`, `--currency` |
| `billing customers` | List customers | `--email`, `--limit` |
| `billing customers create` | Create new customer | `--email`, `--name`, `--interactive` |
| `billing customers show` | Show customer details | - |
| `billing customers delete` | Delete customer | `--yes` |
| `billing subscriptions` | List subscriptions | `--status`, `--customer`, `--limit` |
| `billing subscriptions cancel` | Cancel subscription | `--immediately`, `--yes` |
| `billing subscriptions pause` | Pause subscription billing | `--yes` |
| `billing subscriptions resume` | Resume paused subscription | `--yes` |
| `billing subscriptions update` | Update subscription price/quantity | `--price`, `--quantity`, `--prorate` |
| `billing invoices` | List invoices | `--status`, `--customer`, `--subscription` |
| `billing refunds` | List refunds | `--charge`, `--limit` |
| `billing refunds create` | Create refund | `--charge`, `--amount`, `--reason`, `--yes` |
| `billing payment-methods set-default` | Set default payment method | `--customer` |
| `billing events` | View recent events | `--type`, `--limit` |
| `billing test create-customer` | Create test customer with card | `--with-card` |
| `billing test trigger-webhook` | Trigger test webhook event | `--subscription`, `--customer` |
| `billing sigma queries` | List Sigma queries | `--limit` |
| `billing sigma run` | Execute Sigma query | `--format`, `--output` |
| `billing payment-links` | List payment links | `--active-only`, `--limit` |
| `billing payment-links create` | Create payment link | `--price`, `--quantity`, `--allow-quantity`, `--after-completion` |
| `billing payment-links update` | Update payment link | `--active`, `--allow-quantity`, `--after-completion` |
| `billing payment-links show` | Show payment link details | - |
| `billing payment-links archive` | Archive payment link | `--yes` |
| `billing sync` | Sync Stripe to cache | - |
| `billing validate` | Validate metadata | - |

---

## API Rate Limits

Stripe has API rate limits. The CLI uses reasonable defaults:
- Most list commands: 100 results (can adjust with `--limit`)
- Events: 20 results by default (less noisy)
- All commands paginate properly

If you hit rate limits, add delays between commands or reduce `--limit`.
