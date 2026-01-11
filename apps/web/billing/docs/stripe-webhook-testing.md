Here's how to test the webhook endpoint locally from the Stripe test API:

## Option 1: Stripe CLI (Recommended - Real-time)

### 1. Install Stripe CLI:
```bash
# macOS
brew install stripe/stripe-cli/stripe

# Or download from https://stripe.com/docs/stripe-cli
```

### 2. Login to Stripe:
```bash
stripe login
```

### 3. Forward webhooks to your local server:
```bash
# Start your local server first
bin/ots server

# In another terminal, forward Stripe webhooks
stripe listen --forward-to https://dev.onetime.dev/billing/webhook
```

This will:
- Give you a webhook signing secret (starts with `whsec_`)
- Forward all Stripe test events to your local endpoint
- Show you the webhook payloads and responses in real-time

### 4. Update your config with the webhook secret:
```yaml
# etc/billing.yaml
webhook_signing_secret: whsec_xxxxxxxxxxxxxxxxxxxxx  # From stripe listen
```

### 5. Trigger test events:
```bash
# Trigger specific events
stripe trigger customer.subscription.updated
stripe trigger checkout.session.completed
stripe trigger customer.subscription.deleted
stripe trigger product.updated

# Or create real test objects in Stripe Dashboard
```

## Option 2: Stripe Dashboard (Manual)

### 1. Start your local server with ngrok:
```bash
# Start ngrok tunnel
ngrok http 7143

# Copy the HTTPS URL (e.g., https://abc123.ngrok.io)
```

### 2. Configure webhook in Stripe Dashboard:
- Go to https://dashboard.stripe.com/test/webhooks
- Click "Add endpoint"
- URL: `https://abc123.ngrok.io/billing/webhook`
- Select events to listen for
- Copy the webhook signing secret

### 3. Update your config:
```yaml
# etc/billing.yaml
webhook_signing_secret: whsec_xxxxxxxxxxxxxxxxxxxxx  # From dashboard
```

### 4. Test by creating objects in Stripe Dashboard

## Option 3: Send Raw Webhook (For Testing Only)

### 1. Get a sample payload:
```bash
stripe listen --print-json > /tmp/sample_webhook.json
# Or use Stripe's webhook event samples
```

### 2. Send directly to your endpoint:
```bash
# This will fail signature verification unless you disable it for testing
curl -X POST http://localhost:7143/billing/webhook \
  -H "Content-Type: application/json" \
  -d @/tmp/sample_webhook.json
```

## Recommended Testing Flow

### 1. Start local server:
```bash
bin/ots server
# Should be running on http://localhost:7143
```

### 2. Start Stripe webhook forwarding:
```bash
stripe listen --forward-to http://localhost:7143/billing/webhook
```

You'll see output like:
```
> Ready! Your webhook signing secret is whsec_abc123... (^C to quit)
```

### 3. Update billing config temporarily:
```yaml
# etc/billing.yaml
webhook_signing_secret: whsec_abc123...  # Use the secret from stripe listen
```

### 4. Trigger test events:
```bash
# In another terminal
stripe trigger customer.subscription.updated
stripe trigger checkout.session.completed

# Watch the output in your server terminal
# Check event tracking:
bin/ots billing webhooks --stats
```

### 5. Inspect tracked events:
```bash
# Get the event ID from the stripe trigger output
bin/ots billing webhooks evt_test_xxx

# See the event details with full metadata
```

## Verify Enhanced Tracking

After sending a webhook, check that it was tracked:

```bash
# View statistics
bin/ots billing webhooks --stats

# Should show:
# Total Events: 1
# By Status:
#   success      1
# By Event Type:
#   customer.subscription.updated    1

# Inspect the event
bin/ots billing webhooks evt_test_xxx

# Should show:
# Status: success
# Retry Count: 1
# API Version: 2023-10-16
# Event payload stored: Yes
```

## Test Retry Logic

To test the retry behavior:

### 1. Temporarily break your webhook handler:
```ruby
# In apps/web/billing/controllers/webhooks.rb
def handle_subscription_updated(subscription)
  raise "Simulated error for testing"  # Add this line temporarily
end
```

### 2. Send webhook:
```bash
stripe trigger customer.subscription.updated
```

### 3. Check the event:
```bash
bin/ots billing webhooks evt_test_xxx

# Should show:
# Status: retrying (colored yellow)
# Retry Count: 1
# Error Message: Simulated error for testing
```

### 4. Send again (Stripe will retry):
```bash
stripe trigger customer.subscription.updated
# Same event ID will increment retry count
```

### 5. Fix the code and send once more:
```bash
# Remove the raise line

stripe trigger customer.subscription.updated
# Should now show Status: success
```

This tests the complete retry flow: pending → retrying → success.
