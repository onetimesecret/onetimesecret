# Stripe Webhook Events - Implementation Status

**Last Updated:** 2025-11-23

## Currently Implemented

### Subscription Lifecycle
- ✅ `checkout.session.completed` - Creates/updates organization subscription
- ✅ `customer.subscription.updated` - Updates subscription status
- ✅ `customer.subscription.deleted` - Marks subscription as canceled

### Product/Price Management
- ✅ `product.created` - Refreshes plan cache
- ✅ `product.updated` - Refreshes plan cache
- ✅ `price.created` - Refreshes plan cache
- ✅ `price.updated` - Refreshes plan cache

**Note:** We use "Plan" terminology internally but consume Stripe's Product+Price API (not legacy Plan objects).

---

## Not Yet Implemented

### Critical Priority - Payment Failures

**Impact:** Without these handlers, failed payments may go unnoticed, causing service disruptions.

- ⚠️ `invoice.payment_failed` - Payment failed, may need to suspend access
  - **Action Needed:** Update organization status to `past_due`, notify admin
  - **Business Logic:** Define grace period before suspension

- ⚠️ `invoice.payment_action_required` - Payment requires customer action (3D Secure, etc.)
  - **Action Needed:** Send email to organization admin with payment link
  - **Business Logic:** How long to wait before marking as failed?

- ⚠️ `customer.subscription.trial_will_end` - Trial expiring soon (7 days default)
  - **Action Needed:** Send notification email to organization admin
  - **Business Logic:** Upsell opportunity, conversion reminder

### High Priority - Payment Success

**Impact:** Confirms successful payment, good for audit trail and customer notifications.

- 📋 `invoice.payment_succeeded` / `invoice.paid` - Payment processed successfully
  - **Action Needed:** Log successful payment, send receipt email
  - **Business Logic:** Update last payment date on organization
  - **Note:** `invoice.paid` is alias for `invoice.payment_succeeded`

### Medium Priority - Subscription Management

**Impact:** Handles paused subscriptions and creation tracking.

- 📋 `customer.subscription.created` - New subscription created
  - **Action Needed:** Log subscription creation (may be redundant with checkout.session.completed)
  - **Business Logic:** Determine if this adds value over existing checkout handler

- 📋 `customer.subscription.paused` - Subscription paused by customer
  - **Action Needed:** Update organization status to `paused`, restrict access
  - **Business Logic:** Define what features remain available when paused

- 📋 `customer.subscription.resumed` - Subscription resumed after pause
  - **Action Needed:** Restore organization to `active` status
  - **Business Logic:** Restore full feature access

### Medium Priority - Customer Management

**Impact:** Keeps customer data in sync, useful for support and analytics.

- 📋 `customer.created` - Customer created in Stripe
  - **Action Needed:** Log customer creation event
  - **Business Logic:** May be redundant if customer is created via our API

- 📋 `customer.updated` - Customer details changed (email, payment method, etc.)
  - **Action Needed:** Sync customer metadata if needed
  - **Business Logic:** Determine which fields we care about

- 📋 `customer.deleted` - Customer deleted from Stripe
  - **Action Needed:** Log deletion, handle orphaned organizations
  - **Business Logic:** Cleanup strategy for related data

### Medium Priority - Refunds & Disputes

**Impact:** Financial reconciliation and fraud prevention.

- 📋 `charge.refunded` - Payment was refunded
  - **Action Needed:** Log refund, potentially revoke access
  - **Business Logic:** Full vs partial refund handling

- 📋 `charge.dispute.created` - Customer initiated chargeback/dispute
  - **Action Needed:** Flag account, notify admin, suspend access
  - **Business Logic:** Dispute resolution workflow

- 📋 `charge.dispute.closed` - Dispute resolved (won or lost)
  - **Action Needed:** Update account status based on outcome
  - **Business Logic:** Reinstate access if won, confirm suspension if lost

### Lower Priority - Informational

**Impact:** Useful for debugging and audit trail, but not business-critical.

- 📝 `invoice.created` - Invoice generated (before payment attempt)
  - **Action Needed:** Log invoice creation
  - **Business Logic:** Notification or just audit trail?

- 📝 `invoice.finalized` - Invoice finalized (ready for payment)
  - **Action Needed:** Log finalization
  - **Business Logic:** Pre-payment notification opportunity?

- 📝 `invoice.updated` - Invoice modified
  - **Action Needed:** Log changes
  - **Business Logic:** Track what changed (amount, due date, etc.)

- 📝 `payment_method.attached` - Payment method added to customer
  - **Action Needed:** Log payment method addition
  - **Business Logic:** Security notification to customer?

- 📝 `payment_method.detached` - Payment method removed
  - **Action Needed:** Log removal, warn if no backup payment method
  - **Business Logic:** Prevent service disruption

---

## Implementation Notes

### Event Tracking
All webhook events (handled or not) are tracked via `StripeWebhookEvent` model with:
- Processing state machine (pending → success/failed/retrying)
- Full event payload storage for debugging
- Retry logic (max 3 attempts)
- 30-day retention for compliance

### Handler Pattern
```ruby
when 'event.type'
  handle_event_type(event.data.object)
```

### Testing
Use Stripe CLI to test events:
```bash
stripe trigger customer.subscription.updated
stripe trigger invoice.payment_failed
stripe trigger checkout.session.completed
```

### Error Handling
All handlers should:
1. Mark event as processing: `event_record.mark_processing!`
2. Execute business logic with error handling
3. Mark success: `event_record.mark_success!`
4. Mark failure on error: `event_record.mark_failed!(error)`

---

## Future Considerations

### Webhook Endpoint Security
- ✅ Signature verification implemented
- ✅ Timestamp validation (5-minute window)
- ✅ Idempotency via event_id deduplication
- ✅ Replay attack prevention

### Scalability
- Consider async job queue for heavy processing
- Monitor webhook processing latency
- Set up alerting for max retries reached

### Business Logic Decisions Needed

1. **Grace Period:** How long after `invoice.payment_failed` before suspending access?
2. **Pause vs Cancel:** What features are available when subscription is paused?
3. **Refund Policy:** Full refund = immediate access revocation, or grace period?
4. **Dispute Handling:** Automatic suspension on dispute, or manual review?
5. **Trial Notifications:** What cadence? (7 days, 3 days, 1 day before expiry)

---

## Related Files

- **Webhook Controller:** `apps/web/billing/controllers/webhooks.rb`
- **Event Model:** `apps/web/billing/models/stripe_webhook_event.rb`
- **Webhook Validator:** `apps/web/billing/lib/webhook_validator.rb`
- **Plan Model:** `apps/web/billing/models/plan.rb`
- **Organization Model:** `lib/onetime/models/organization.rb` (with billing features)

---

## Changelog

### 2025-11-23 - Issue #2020
- ✅ Enhanced webhook event tracking with MVP fields
- ✅ Added processing state machine (pending/success/failed/retrying)
- ✅ Added full event payload storage
- ✅ Extended TTL to 30 days for compliance
- ✅ Added product.created and price.created handlers
- ✅ Documented remaining unimplemented events
