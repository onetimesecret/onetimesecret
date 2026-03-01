# try/integration/billing/multi_region_federation_try.rb
#
# frozen_string_literal: true

# Multi-Region Integration Tests for Subscription Federation (#2471).
#
# This test simulates the complete cross-region federation flow:
#
# 1. REGION A: User subscribes -> email_hash computed and stored in Stripe metadata
# 2. REGION B: Webhook fires -> no account exists -> PendingFederatedSubscription stored
# 3. REGION B: User creates account -> email_hash computed -> pending matched -> benefits applied
# 4. VERIFY: Both regions have correct subscription state
#
# Since we can't actually run two separate databases, we simulate the multi-region
# scenario by:
# - Region A: Organization with stripe_customer_id (subscription owner)
# - Region B: PendingFederatedSubscription -> later becomes Organization (federated)
#
# The key insight is that email_hash serves as the cross-region identifier,
# allowing subscription benefits to be claimed in any region where the user
# has an account with the same billing_email.
#
# Run: pnpm run test:tryouts:agent try/integration/billing/multi_region_federation_try.rb

require_relative '../../support/test_helpers'

# Stub the HMAC secret for testing
ENV['FEDERATION_SECRET'] ||= 'test-hmac-secret-for-email-hash-32chars'

require 'onetime/utils/email_hash'
require_relative '../../../apps/web/billing/models/pending_federated_subscription'

# Shared billing email for cross-region federation
# In production, this would be the same email in different region databases
@shared_billing_email = "cross-region-user-#{SecureRandom.hex(8)}@example.com"
@shared_email_hash = Onetime::Utils::EmailHash.compute(@shared_billing_email)

# Stripe IDs (simulated)
@stripe_customer_id = "cus_region_a_#{SecureRandom.hex(4)}"
@stripe_subscription_id = "sub_region_a_#{SecureRandom.hex(4)}"

# Track created resources for cleanup
@created_customers = []
@created_organizations = []
@created_pending_records = []

# ============================================================================
# SETUP: Create all test data before test cases
# ============================================================================

# STEP 1: REGION A - User subscribes (creates owner org)
@region_a_email = generate_unique_test_email('region_a_owner')
@region_a_customer = Onetime::Customer.create!(@region_a_email)
@created_customers << @region_a_customer

@region_a_org = Onetime::Organization.create!(
  'Region A Workspace',
  @region_a_customer,
  "contact-region-a-#{SecureRandom.hex(4)}@example.com"
)
@region_a_org.billing_email = @shared_billing_email
@region_a_org.compute_email_hash!
@region_a_org.stripe_customer_id = @stripe_customer_id
@region_a_org.stripe_subscription_id = @stripe_subscription_id
@region_a_org.subscription_status = 'active'
@region_a_org.planid = 'pro_monthly'
@region_a_org.save
@created_organizations << @region_a_org

# STEP 2: REGION B - Create pending record (webhook before account)
@pending = Billing::PendingFederatedSubscription.new(@shared_email_hash)
@pending.subscription_status = 'active'
@pending.planid = 'pro_monthly'
@pending.subscription_period_end = (Time.now + 30 * 24 * 60 * 60).to_i.to_s
@pending.region = 'US'
@pending.received_at = Time.now.to_i.to_s
@pending.save
@created_pending_records << @pending

# STEP 3: REGION B - User creates account
# In production, Region B is a DIFFERENT database, so the same billing_email can exist.
# In our single-database test, we use a different billing_email but SET the same email_hash
# to simulate the cross-region scenario.
@region_b_email = generate_unique_test_email('region_b_user')
@region_b_customer = Onetime::Customer.create!(@region_b_email)
@created_customers << @region_b_customer

@region_b_org = Onetime::Organization.create!(
  'Region B Workspace',
  @region_b_customer,
  "contact-region-b-#{SecureRandom.hex(4)}@example.com"
)
# Use a DIFFERENT billing_email (unique index constraint), but SET same email_hash
# This simulates cross-region: different DBs would have same billing_email -> same hash
@region_b_org.billing_email = "region-b-billing-#{SecureRandom.hex(8)}@example.com"
@region_b_org.email_hash = @shared_email_hash  # Directly set to simulate cross-region
@region_b_org.save
@created_organizations << @region_b_org

# STEP 4: Claim pending subscription
@found_pending = Billing::PendingFederatedSubscription.find_by_email_hash(@region_b_org.email_hash)
if @found_pending&.active?
  @region_b_org.subscription_status = @found_pending.subscription_status
  @region_b_org.planid = @found_pending.planid
  @region_b_org.mark_subscription_federated!
  @region_b_org.save
  @found_pending.destroy!
end

# ============================================================================
# TEST CASES: Verify the federation state
# ============================================================================

## VERIFY REGION A: Owner org has email_hash matching shared hash
@region_a_org.email_hash == @shared_email_hash
#=> true

## VERIFY REGION A: Owner org is subscription owner (has stripe_customer_id)
@region_a_org.subscription_owner?
#=> true

## VERIFY REGION A: Owner org is NOT marked as federated
@region_a_org.subscription_federated?
#=> false

## VERIFY REGION A: Owner org has active subscription
@region_a_org.active_subscription?
#=> true

## VERIFY REGION B: Federated org has email_hash matching shared hash
@region_b_org.email_hash == @shared_email_hash
#=> true

## VERIFY REGION B: Federated org has subscription status applied
@region_b_org.subscription_status
#=> 'active'

## VERIFY REGION B: Federated org is marked as federated (not owner)
@region_b_org.subscription_federated?
#=> true

## VERIFY REGION B: Federated org does NOT have stripe_customer_id
@region_b_org.stripe_customer_id.to_s.empty?
#=> true

## VERIFY REGION B: Federated org has active subscription benefits
@region_b_org.active_subscription?
#=> true

## VERIFY: Pending record was consumed after claiming
Billing::PendingFederatedSubscription.find_by_email_hash(@shared_email_hash).nil?
#=> true

## FINAL CHECK: Both orgs have same email_hash (cross-region identifier)
@region_a_org.email_hash == @region_b_org.email_hash
#=> true

## FINAL CHECK: Region A org is owner
@region_a_org.subscription_owner?
#=> true

## FINAL CHECK: Region B org is federated
@region_b_org.subscription_federated?
#=> true

## FINAL CHECK: Both orgs have active subscription
[@region_a_org.active_subscription?, @region_b_org.active_subscription?]
#=> [true, true]

## FINAL CHECK: Both orgs have same subscription status
@region_a_org.subscription_status == @region_b_org.subscription_status
#=> true

## FINAL CHECK: Only owner has stripe_customer_id
[@region_a_org.stripe_customer_id.to_s.empty?, @region_b_org.stripe_customer_id.to_s.empty?]
#=> [false, true]

## FINAL CHECK: Only federated org has subscription_federated_at timestamp
[@region_a_org.subscription_federated_at.to_s.empty?, !@region_b_org.subscription_federated_at.to_s.empty?]
#=> [true, true]

# ============================================================================
# STEP 5: VERIFY - Subscription status updates (simulated webhook)
# ============================================================================

## VERIFY: Status update to past_due is reflected after save+refresh
@region_a_org.subscription_status = 'past_due'
@region_a_org.save
@region_b_org.subscription_status = 'past_due'
@region_b_org.save
@region_a_org.refresh!
@region_b_org.refresh!
[@region_a_org.subscription_status, @region_b_org.subscription_status]
#=> ['past_due', 'past_due']

## VERIFY: past_due is NOT considered active_subscription (only 'active' and 'trialing' are)
# Note: active_subscription? is strict - past_due is a warning state, not fully active
[@region_a_org.active_subscription?, @region_b_org.active_subscription?]
#=> [false, false]

# ============================================================================
# STEP 6: VERIFY - Subscription cancellation
# ============================================================================

## VERIFY: Cancellation is reflected after save+refresh
@region_a_org.subscription_status = 'canceled'
@region_a_org.stripe_subscription_id = nil
@region_a_org.save
@region_b_org.subscription_status = 'canceled'
@region_b_org.save
@region_a_org.refresh!
@region_b_org.refresh!
[@region_a_org.subscription_status, @region_b_org.subscription_status]
#=> ['canceled', 'canceled']

## VERIFY: Canceled is not active
[@region_a_org.active_subscription?, @region_b_org.active_subscription?]
#=> [false, false]

# ============================================================================
# Teardown
# ============================================================================
@created_pending_records.each { |rec| rec.destroy! rescue nil }
@created_organizations.each { |org| org.destroy! rescue nil }
@created_customers.each { |cust| cust.destroy! rescue nil }
