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
bin/ots billing catalog           # List cached plans
bin/ots billing products        # List Stripe products
bin/ots billing prices          # List Stripe prices
bin/ots billing sync            # Sync from Stripe to cache
bin/ots billing validate        # Validate product metadata
```

## Command Reference

### `bin/ots billing catalog`

List plans cached in Redis from previous Stripe sync.

**Options:**
- `--refresh` - Refresh cache from Stripe before listing

**Examples:**
```bash
# List cached plans
bin/ots billing catalog

# Refresh and list
bin/ots billing catalog --refresh
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
  bin/ots billing catalog
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
bin/ots billing catalog
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
bin/ots billing catalog

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
- `subscription_id` - Subscription ID (sub_xxx)

**Options:**
- `--immediately` - Cancel immediately instead of at period end (default: false)
- `--force` - Skip confirmation prompt (default: false)

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
bin/ots billing subscriptions cancel sub_ABC123xyz --immediately --force
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
- `subscription_id` - Subscription ID (sub_xxx)

**Options:**
- `--force` - Skip confirmation prompt (default: false)

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
bin/ots billing subscriptions pause sub_ABC123xyz --force
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
- `subscription_id` - Subscription ID (sub_xxx)

**Options:**
- `--force` - Skip confirmation prompt (default: false)

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
bin/ots billing subscriptions resume sub_ABC123xyz --force
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
- `--force` - Skip confirmation and override active subscription check (default: false)

**Examples:**
```bash
# Safe delete (blocks if active subscriptions exist)
bin/ots billing customers delete cus_ABC123xyz

Customer: cus_ABC123xyz
Email: user@example.com

⚠️  Delete customer permanently? (y/n): y

Customer deleted successfully

# Force delete (even with active subscriptions)
bin/ots billing customers delete cus_ABC123xyz --force

⚠️  Customer has active subscriptions!
Cancel subscriptions first or use --force

Customer deleted successfully
```

**Safety Features:**
- Checks for active subscriptions before deletion
- Requires explicit confirmation unless --force flag used
- Cannot be undone - customer data permanently removed
- Blocks deletion if active subscriptions found (unless --force)

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
- `subscription_id` - Subscription ID (sub_xxx)

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

---

## Quick Reference

| Command | Description | Key Options |
|---------|-------------|-------------|
| `billing catalog` | List cached plans | `--refresh` |
| `billing products` | List Stripe products | `--active-only` |
| `billing products create` | Create product | `--interactive`, `--plan-id`, `--tier` |
| `billing products update` | Update product metadata | `--interactive`, metadata fields |
| `billing prices` | List Stripe prices | `--product`, `--active-only` |
| `billing prices create` | Create price | `--amount`, `--interval`, `--currency` |
| `billing customers` | List customers | `--email`, `--limit` |
| `billing customers create` | Create new customer | `--email`, `--name`, `--interactive` |
| `billing customers show` | Show customer details | - |
| `billing customers delete` | Delete customer | `--force` |
| `billing subscriptions` | List subscriptions | `--status`, `--customer`, `--limit` |
| `billing subscriptions cancel` | Cancel subscription | `--immediately`, `--force` |
| `billing subscriptions pause` | Pause subscription billing | `--force` |
| `billing subscriptions resume` | Resume paused subscription | `--force` |
| `billing subscriptions update` | Update subscription price/quantity | `--price`, `--quantity`, `--prorate` |
| `billing invoices` | List invoices | `--status`, `--customer`, `--subscription` |
| `billing payment-methods set-default` | Set default payment method | `--customer` |
| `billing events` | View recent events | `--type`, `--limit` |
| `billing test create-customer` | Create test customer with card | `--with-card` |
| `billing sync` | Sync Stripe to cache | - |
| `billing validate` | Validate metadata | - |

---

## API Rate Limits

Stripe has API rate limits. The CLI uses reasonable defaults:
- Most list commands: 100 results (can adjust with `--limit`)
- Events: 20 results by default (less noisy)
- All commands paginate properly

If you hit rate limits, add delays between commands or reduce `--limit`.
