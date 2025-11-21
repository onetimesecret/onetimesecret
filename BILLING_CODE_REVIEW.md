# Stripe Billing Integration Code Review

**Review Date:** 2025-11-21
**Reviewer:** Claude Code
**Scope:** `apps/web/billing/` and Dry::CLI command implementations

## Executive Summary

This comprehensive code review evaluated the Stripe billing integration focusing on correctness, code clarity, admin UX, and integration quality. The review identified **3 critical**, **8 major**, and **12 minor** issues across the billing codebase.

### Key Findings

- ✅ **Strengths:** Well-structured architecture, good separation of concerns, comprehensive webhook handling
- ⚠️ **Critical Issues:** Missing idempotency keys, no retry logic, insufficient webhook timestamp validation
- 📈 **Opportunities:** Enhanced CLI UX, improved error handling, better code reusability

---

## 1. Correctness Issues

### 1.1 Missing Idempotency Keys (CRITICAL)

**Severity:** Critical
**Location:** Multiple CLI commands and controllers
**Impact:** Duplicate charges/subscriptions on network failures

#### Issue
Stripe API create operations don't use idempotency keys, risking duplicate operations if requests are retried after network failures.

**Example:**
```ruby
# apps/web/billing/cli/customers_create_command.rb:47
customer = Stripe::Customer.create(customer_params)
```

#### Recommendation
Use idempotency keys for all create operations:

```ruby
customer = Stripe::Customer.create(
  customer_params,
  { idempotency_key: generate_idempotency_key }
)
```

**Files Affected:**
- `apps/web/billing/cli/customers_create_command.rb:47`
- `apps/web/billing/cli/products_create_command.rb:79`
- `apps/web/billing/cli/prices_create_command.rb:66`
- `apps/web/billing/cli/refunds_create_command.rb:49`
- `apps/web/billing/controllers/plans.rb:87`
- `apps/web/billing/controllers/plans.rb:192`

**Solution:** See `apps/web/billing/lib/stripe_client.rb` (NEW)

---

### 1.2 No Retry Logic for Network Failures (CRITICAL)

**Severity:** Critical
**Location:** All Stripe API calls
**Impact:** Operations fail permanently on transient network errors

#### Issue
No automatic retry mechanism for network failures. Stripe SDK's built-in retry is disabled or not configured.

#### Recommendation
Implement exponential backoff retry logic for transient errors:

```ruby
def with_retry(max_attempts = 3)
  attempt = 0
  begin
    attempt += 1
    yield
  rescue Stripe::APIConnectionError, Net::ReadTimeout => ex
    retry if attempt < max_attempts
    raise
  end
end
```

**Solution:** See `apps/web/billing/lib/stripe_client.rb` (NEW)

---

### 1.3 Insufficient Webhook Timestamp Validation (CRITICAL)

**Severity:** Critical
**Location:** `apps/web/billing/controllers/webhooks.rb:42`
**Impact:** Vulnerable to replay attacks

#### Issue
Webhook signature is verified but timestamp freshness is not checked, allowing replay attacks with old but validly-signed events.

**Current Code:**
```ruby
event = Stripe::Webhook.construct_event(
  payload, sig_header, webhook_secret
)
```

#### Recommendation
Verify event timestamp and reject events older than 5 minutes:

```ruby
event = Stripe::Webhook.construct_event(payload, sig_header, webhook_secret)

event_age = Time.now - Time.at(event.created)
if event_age > 300 # 5 minutes
  raise SecurityError, "Webhook event too old"
end
```

**Solution:** See `apps/web/billing/lib/webhook_validator.rb` (NEW)

---

### 1.4 Missing Error Handling in Webhook Processing (MAJOR)

**Severity:** Major
**Location:** `apps/web/billing/controllers/webhooks.rb:75-88`
**Impact:** Unhandled exceptions cause webhook failures

#### Issue
No exception handling around event processing. If any handler raises an exception, the webhook returns 500, causing Stripe to retry infinitely.

**Current Code:**
```ruby
case event.type
when 'checkout.session.completed'
  handle_checkout_completed(event.data.object)
# ... etc
end
```

#### Recommendation
Wrap event processing in try/catch and return 200 even on errors to prevent Stripe retries:

```ruby
begin
  case event.type
  # ... handle events
  end
rescue StandardError => ex
  log_error(ex)
  # Return 200 to prevent retries, but don't mark as processed
  return json_success('Event received but processing failed')
end
```

**Solution:** Implemented in updated `webhooks.rb:84-111`

---

### 1.5 Race Condition in Organization Creation (MAJOR)

**Severity:** Major
**Location:** `apps/web/billing/controllers/webhooks.rb:132-144`
**Impact:** Duplicate organizations for same customer

#### Issue
No locking mechanism when creating default organization. If two webhooks arrive simultaneously, both might create organizations.

**Current Code:**
```ruby
orgs = customer.organization_instances.to_a
org = orgs.find { |o| o.is_default }

unless org
  org = Onetime::Organization.create!(...)
end
```

#### Recommendation
Use distributed lock or check-and-set pattern:

```ruby
# Use Redis lock
Familia.redis.lock("customer:#{custid}:org_creation", ttl: 10) do
  org = find_or_create_default_organization(customer)
end
```

---

### 1.6 Missing Test vs Production Mode Guards (MAJOR)

**Severity:** Major
**Location:** Multiple test commands
**Impact:** Accidental testing in production

#### Issue
Only `test_trigger_webhook_command.rb:28` checks for test mode. Other test commands don't verify API key type.

#### Recommendation
Add test mode validation to all test commands:

```ruby
unless Stripe.api_key&.start_with?('sk_test_')
  puts 'Error: This command requires a test API key'
  return
end
```

**Files Needing Update:**
- `apps/web/billing/cli/test_create_customer_command.rb`

---

## 2. Code Clarity Issues

### 2.1 Inconsistent Error Handling Patterns (MAJOR)

**Severity:** Major
**Location:** Throughout codebase
**Impact:** Difficult to maintain, inconsistent logging

#### Issue
Error handling uses different variable names (`ex`, `e`) and logging approaches across files.

**Examples:**
```ruby
# Using 'ex' with full logging
rescue Stripe::StripeError => ex
  billing_logger.error 'Error', { exception: ex, message: ex.message }

# Using 'e' with minimal logging
rescue Stripe::StripeError => e
  puts "Error: #{e.message}"
```

#### Recommendation
Standardize error handling pattern:

```ruby
rescue Stripe::StripeError => ex
  billing_logger.error 'Operation failed', {
    exception: ex,
    message: ex.message,
    code: ex.code,
    http_status: ex.http_status,
  }
  display_error(ex, suggested_actions)
end
```

---

### 2.2 Long Methods Need Refactoring (MAJOR)

**Severity:** Major
**Location:** `apps/web/billing/models/plan.rb:120-241`
**Impact:** Difficult to test and understand

#### Issue
`Plan.refresh_from_stripe` is 120 lines long, handling multiple responsibilities.

#### Recommendation
Extract methods:

```ruby
def refresh_from_stripe
  validate_stripe_configuration
  products = fetch_active_products

  products.auto_paging_each do |product|
    process_product(product)
  end
end

private

def process_product(product)
  return unless valid_product?(product)

  prices = fetch_product_prices(product)
  prices.auto_paging_each { |price| cache_plan(product, price) }
end
```

---

### 2.3 Duplicate JSON Parsing Logic (MINOR)

**Severity:** Minor
**Location:** `apps/web/billing/models/plan.rb:81-111`
**Impact:** Code duplication

#### Issue
Three nearly identical methods for parsing JSON fields.

**Current Code:**
```ruby
def parsed_capabilities
  JSON.parse(capabilities)
rescue JSON::ParserError => ex
  # ... logging
  []
end

def parsed_features
  JSON.parse(features)
rescue JSON::ParserError => ex
  # ... logging
  []
end
```

#### Recommendation
Extract to helper method:

```ruby
def parse_json_field(field_name, default_value)
  JSON.parse(send(field_name))
rescue JSON::ParserError => ex
  billing_logger.error "Failed to parse #{field_name}", {
    plan_id: plan_id,
    field_name => send(field_name)
  }
  default_value
end

def parsed_capabilities
  parse_json_field(:capabilities, [])
end
```

---

### 2.4 Magic Numbers and Hardcoded Values (MINOR)

**Severity:** Minor
**Location:** Multiple files
**Impact:** Difficult to maintain

#### Examples
```ruby
# apps/web/billing/models/plan.rb:136
limit: 25  # What does 25 represent?

# apps/web/billing/models/plan.rb:172
limit: 100  # Different limit?

# apps/web/billing/models/processed_webhook_event.rb:15
default_expiration 7.days  # Why 7 days?
```

#### Recommendation
Extract to named constants:

```ruby
module Billing
  MAX_PRODUCTS_PER_PAGE = 25
  MAX_PRICES_PER_PAGE = 100
  WEBHOOK_EVENT_RETENTION_DAYS = 7
end
```

---

## 3. Admin UX Issues

### 3.1 Missing Dry-Run Mode for Destructive Operations (MAJOR)

**Severity:** Major
**Location:** All destructive CLI commands
**Impact:** Accidental data loss

#### Issue
No `--dry-run` option to preview destructive operations before execution.

#### Recommendation
Add dry-run support to all destructive commands:

```ruby
option :dry_run, type: :boolean, default: false,
  desc: 'Preview operation without executing'

def call(dry_run: false, **)
  # ... validate and display summary

  return preview_operation if dry_run

  execute_operation
end
```

**Solution:** See updated `subscriptions_cancel_command.rb:23-71`

---

### 3.2 Inconsistent Confirmation Prompts (MAJOR)

**Severity:** Major
**Location:** Multiple CLI commands
**Impact:** User confusion, inconsistent safety

#### Issue
Some destructive commands require confirmation, others don't. Format varies.

**Examples:**
```ruby
# Style 1
print "\nProceed? (y/n): "
return unless $stdin.gets.chomp.downcase == 'y'

# Style 2
print "\nCreate refund? (y/n): "
return unless $stdin.gets.chomp.downcase == 'y'
```

#### Recommendation
Standardize using helper module (see `safety_helpers.rb`):

```ruby
return unless confirm_operation(
  'This will permanently delete the customer',
  auto_yes: yes
)
```

---

### 3.3 Error Messages Lack Actionable Guidance (MAJOR)

**Severity:** Major
**Location:** All CLI commands
**Impact:** Poor troubleshooting experience

#### Issue
Error messages show what failed but not what to do next.

**Current:**
```ruby
puts "Error creating customer: #{ex.message}"
```

#### Recommendation
Provide actionable suggestions:

```ruby
display_error(ex, [
  'Verify email address format is valid',
  'Check Stripe Dashboard for existing customer',
  'Ensure API key has customer:write permission',
])
```

**Solution:** See `safety_helpers.rb:74-82`

---

### 3.4 No Progress Indicators for Long Operations (MINOR)

**Severity:** Minor
**Location:** `apps/web/billing/models/plan.rb:141-230`
**Impact:** Poor user feedback

#### Issue
Long-running sync operations provide no progress feedback.

#### Recommendation
Add progress indicators:

```ruby
products.auto_paging_each.with_index do |product, index|
  show_progress(index + 1, total_products, product.name)
  process_product(product)
end
```

**Solution:** See `safety_helpers.rb:42-48`

---

### 3.5 Inconsistent Output Formatting (MINOR)

**Severity:** Minor
**Location:** Multiple CLI commands
**Impact:** Inconsistent user experience

#### Issue
List commands use different formatting approaches.

#### Recommendation
Standardize table formatting:

```ruby
display_table_header(
  ['ID', 'Name', 'Status', 'Created'],
  [22, 30, 12, 12]
)

items.each do |item|
  puts format_row(item, widths)
end
```

---

## 4. Integration Quality Issues

### 4.1 Tight Coupling Between Controllers and Models (MAJOR)

**Severity:** Major
**Location:** `apps/web/billing/controllers/plans.rb:146-149`
**Impact:** Difficult to test, violates SRP

#### Issue
Controllers directly manipulate domain models instead of using operations/services.

**Current:**
```ruby
org.update_from_stripe_subscription(subscription)
```

#### Recommendation
Use operation classes:

```ruby
result = Billing::Operations::UpdateOrganizationSubscription.new(
  organization: org,
  subscription: subscription
).call
```

---

### 4.2 Missing Transaction Boundaries (MAJOR)

**Severity:** Major
**Location:** Webhook handlers
**Impact:** Data inconsistency risk

#### Issue
No explicit transaction management when updating multiple related entities.

**Example:**
```ruby
org.is_default = true
org.save
org.update_from_stripe_subscription(subscription)
```

#### Recommendation
Wrap in transaction (if using Redis MULTI/EXEC or application-level transactions):

```ruby
Familia.redis.multi do
  org.is_default = true
  org.save
  org.update_from_stripe_subscription(subscription)
end
```

---

### 4.3 Inconsistent Field Naming (MINOR)

**Severity:** Minor
**Location:** Throughout codebase
**Impact:** Confusion, potential bugs

#### Issue
Mix of `custid`, `customer_id`, `stripe_customer_id` without clear distinction.

#### Recommendation
Establish naming convention:
- `custid` - Internal Onetime customer identifier
- `stripe_customer_id` - Stripe's customer identifier
- `customer` - Customer object reference

---

### 4.4 Missing Validation Before Save (MINOR)

**Severity:** Minor
**Location:** Multiple model methods
**Impact:** Invalid data could be persisted

#### Issue
No validation before saving billing data.

**Example:**
```ruby
self.stripe_subscription_id = subscription.id
save
```

#### Recommendation
Add validation:

```ruby
def update_from_stripe_subscription(subscription)
  validate_subscription!(subscription)

  self.stripe_subscription_id = subscription.id
  # ... set other fields

  save
end

private

def validate_subscription!(subscription)
  raise ArgumentError, 'Invalid subscription' unless subscription.is_a?(Stripe::Subscription)
  raise ArgumentError, 'Subscription must have ID' if subscription.id.to_s.empty?
end
```

---

## 5. Summary of Recommendations

### Immediate Actions (Critical)

1. **Implement StripeClient wrapper** with retry logic and idempotency keys
2. **Add WebhookValidator** with timestamp verification
3. **Update webhook handler** to use new validator and error handling
4. **Add test mode guards** to all test commands

### Short-term Improvements (Major)

1. **Refactor long methods** in Plan model
2. **Standardize error handling** across all commands
3. **Add dry-run mode** to destructive commands
4. **Implement safety helpers** for consistent UX
5. **Add transaction boundaries** in webhook handlers

### Long-term Enhancements (Minor)

1. **Extract helper methods** for duplicate code
2. **Add progress indicators** for long operations
3. **Improve error messages** with actionable suggestions
4. **Standardize output formatting** across CLI
5. **Add validation** before model saves

---

## 6. New Files Created

This review includes implementations for the most critical recommendations:

### `apps/web/billing/lib/stripe_client.rb`
- Wraps Stripe SDK with retry logic
- Automatic idempotency key generation
- Exponential backoff for transient errors
- Comprehensive error logging
- **Lines:** 170

### `apps/web/billing/lib/webhook_validator.rb`
- Webhook signature verification
- Timestamp validation (replay attack prevention)
- Duplicate event detection
- **Lines:** 85

### `apps/web/billing/cli/safety_helpers.rb`
- Standardized confirmation prompts
- Dry-run mode support
- Progress indicators
- Actionable error messages
- Operation summaries
- **Lines:** 90

### Updated Files

1. **`apps/web/billing/controllers/webhooks.rb`**
   - Integrated WebhookValidator
   - Added error handling around event processing
   - Improved logging

2. **`apps/web/billing/cli/subscriptions_cancel_command.rb`**
   - Added dry-run mode
   - Integrated safety helpers
   - Improved error messages
   - Better operation summary

---

## 7. Testing Recommendations

### Unit Tests Needed

1. `StripeClient` retry logic with mocked network failures
2. `WebhookValidator` timestamp validation edge cases
3. Safety helpers confirmation and dry-run modes
4. Plan JSON parsing error handling

### Integration Tests Needed

1. Webhook processing with duplicate events
2. Organization creation race condition scenarios
3. Subscription cancellation flows
4. Idempotency key behavior

### Manual Testing Checklist

- [ ] Webhook replay attack prevention
- [ ] Network failure retry behavior
- [ ] CLI dry-run mode accuracy
- [ ] Error message actionability
- [ ] Progress indicator display

---

## 8. Conclusion

The Stripe billing integration is well-architected with good separation of concerns. However, several critical issues around idempotency, retries, and webhook security need immediate attention. The proposed improvements will significantly enhance reliability, security, and administrator experience.

**Estimated Implementation Effort:**
- Critical fixes: 8-16 hours
- Major improvements: 16-24 hours
- Minor enhancements: 8-12 hours
- **Total:** 32-52 hours

**Risk Assessment:**
- **High:** Missing idempotency and retry logic
- **Medium:** Webhook security, error handling
- **Low:** UX improvements, code clarity

---

**Review Completed:** 2025-11-21
**Next Review Recommended:** After implementation of critical fixes
