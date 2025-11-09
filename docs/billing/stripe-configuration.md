# Stripe Configuration

## Prerequisites

- Stripe account ([create one](https://dashboard.stripe.com/register))
- Stripe API keys ([find them here](https://dashboard.stripe.com/apikeys))

## Environment Variables

```bash
BILLING_ENABLED=true
STRIPE_KEY=sk_test_...              # Secret key from Stripe dashboard
STRIPE_WEBHOOK_SECRET=whsec_...     # From webhook endpoint setup
```

## Product Setup

Create products in [Stripe Dashboard → Products](https://dashboard.stripe.com/products).

**Required Metadata** (on each product):
```json
{
  "app": "onetimesecret",
  "plan_id": "identity_v1",
  "capabilities": ["create_secrets", "create_team", "custom_domains"],
  "limit_teams": 1,
  "limit_members_per_team": -1
}
```

**Available plan_id values:** See `lib/onetime/billing/plan_definitions.rb`

**Capabilities list:** See `CAPABILITIES` constant in same file

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
FAMILIA_DEBUG=0 bundle exec try --agent try/billing/
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

## Regional Setup

For multi-region deployments, create separate products per region with `region` metadata:

```json
{
  "app": "onetimesecret",
  "plan_id": "identity_v1",
  "region": "us-east",
  ...
}
```

PlanCache will automatically organize by tier/interval/region.
