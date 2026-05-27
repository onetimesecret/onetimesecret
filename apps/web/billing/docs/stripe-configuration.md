# Stripe Configuration

## Prerequisites

- Stripe account ([create one](https://dashboard.stripe.com/register))
- Stripe API keys ([find them here](https://dashboard.stripe.com/apikeys))

## Setup

Billing is optional and disabled by default. To enable:

1. **Copy the example config:**
   ```bash
   cp etc/examples/billing.example.yaml etc/billing.yaml
   ```

2. **Configure environment variables** (or edit `etc/billing.yaml` directly):
   ```bash
   STRIPE_API_KEY=sk_test_...           # Secret key from Stripe dashboard
   STRIPE_WEBHOOK_SECRET=whsec_...     # From webhook endpoint setup
   ```

3. **Enable billing** in `etc/billing.yaml`:
   ```yaml
   billing:
     enabled: true
   ```

The billing app only loads when `etc/billing.yaml` exists with `enabled: true`. See `lib/onetime/billing_config.rb` for implementation details.

## Product Setup

Create products in [Stripe Dashboard → Products](https://dashboard.stripe.com/products).

**Required Metadata** (on each product):
```json
{
  "app": "onetimesecret",
  "plan_id": "identity_plus_v1",
  "entitlements": "create_secrets,create_team,custom_domains",
  "limit_teams": "1",
  "limit_members_per_team": "-1",
  "limit_owners_per_team": "1",
  "limit_admins_per_team": "-1",
  "limit_regular_members_per_team": "-1"
}
```

**Member limit semantics:** `limit_members_per_team` is the aggregate ceiling
across all roles. The three role-specific keys (`limit_owners_per_team`,
`limit_admins_per_team`, `limit_regular_members_per_team`) apply sub-caps per
role. Both the role-specific bucket and the aggregate are enforced on
invitation; the stricter of the two wins.

**Available plan_id values:** See `apps/web/billing/plan_helpers.rb` and plan cache

**Entitlements list:** See `WithEntitlements::STANDALONE_ENTITLEMENTS` constant in `lib/onetime/models/features/with_entitlements.rb`

**Limits:** Use `-1` for unlimited, `0` for none, positive integers for specific limits

## Webhook Configuration

1. Create endpoint: [Stripe Dashboard → Webhooks](https://dashboard.stripe.com/webhooks)
2. URL: `https://yoursite.com/billing/webhook`
3. Events to listen for:
   - `checkout.session.completed`
   - `customer.subscription.created`
   - `customer.subscription.updated`
   - `customer.subscription.deleted`
   - `product.updated`
   - `price.updated`
4. Copy signing secret to `STRIPE_WEBHOOK_SECRET`

## Verification

**Backend:**
```bash
pnpm run test:tryouts:agent try/billing/
# Should show: 55 testcases passed
```

**Test Checkout Flow:**
1. Start server with billing enabled
2. Visit `/account/billing/plans`
3. Click upgrade button
4. Use [Stripe test cards](https://stripe.com/docs/testing)
5. Verify organization planid updates after successful checkout

**Webhook Testing:**
```bash
# Install Stripe CLI: https://stripe.com/docs/stripe-cli
stripe listen --forward-to localhost:3000/billing/webhook
stripe trigger checkout.session.completed
```

## Promotion Codes

Stripe Checkout Sessions created by this application enable
`allow_promotion_codes: true`, which renders an "Add promotion code" field
on the Stripe-hosted checkout page during both initial signup
(`GET /billing/plans/:product/:interval`) and existing-org upgrades
(`POST /billing/org/:extid/checkout`).

For the field to be useful, promotion codes must first be created in the
Stripe Dashboard:

1. **Create a coupon:** [Stripe Dashboard → Products → Coupons](https://dashboard.stripe.com/coupons)
   - Set the discount (percent off or amount off)
   - Set duration (once, repeating, or forever)
   - Optionally restrict to specific products
2. **Create a promotion code** for the coupon
   - Promotion codes are customer-facing strings (e.g., `WELCOME20`) that
     customers enter at checkout
   - One coupon can have many promotion codes
3. Customers enter the promotion code on the Stripe-hosted checkout page —
   no extra UI work is required on our side.

**Note on currency:** Amount-off coupons are denominated in a single currency
and only apply to checkouts in that currency. Percent-off coupons work across
currencies. See `apps/web/billing/lib/currency_migration_service.rb` for how
incompatible coupons are surfaced during currency migrations.

## Regional Setup

For multi-region deployments, create separate products per region with `region` metadata:

```json
{
  "app": "onetimesecret",
  "plan_id": "identity_plus_v1",
  "region": "us-east",
  ...
}
```

The Plan model will automatically organize by tier/interval/region.
