# try/integration/billing/pending_federation_edge_cases_try.rb
#
# frozen_string_literal: true

# Edge Case Tests for Pending Federation (#2471).
#
# Tests edge cases and error conditions not covered by the main test suites:
# - Malformed email_hash in find operations
# - Status transitions (active, trialing, past_due, canceled, unpaid)
# - TTL and expiration behavior
# - Idempotent storage (overwriting existing records)
#
# Run: pnpm run test:tryouts:agent try/integration/billing/pending_federation_edge_cases_try.rb

require_relative '../../support/test_helpers'

# Stub the HMAC secret for testing
ENV['FEDERATION_SECRET'] ||= 'test-hmac-secret-for-email-hash-32chars'

require 'onetime/utils/email_hash'
require_relative '../../../apps/web/billing/models/pending_federated_subscription'

# Track created resources for cleanup
@created_pending_records = []

# ============================================================================
# SETUP: Create pending records for various test scenarios
# ============================================================================

# Scenario 1: Idempotent update test
@update_email_hash = Onetime::Utils::EmailHash.compute("status-update-#{SecureRandom.hex(4)}@example.com")
@initial_pending = Billing::PendingFederatedSubscription.new(@update_email_hash)
@initial_pending.subscription_status = 'active'
@initial_pending.subscription_period_end = (Time.now + 30 * 24 * 60 * 60).to_i.to_s
@initial_pending.home_region = 'US'
@initial_pending.received_at = Time.now.to_i.to_s
@initial_pending.save
@created_pending_records << @initial_pending

# Scenario 3: Canceled subscription
@canceled_email_hash = Onetime::Utils::EmailHash.compute("canceled-sub-#{SecureRandom.hex(4)}@example.com")
@canceled_pending = Billing::PendingFederatedSubscription.new(@canceled_email_hash)
@canceled_pending.subscription_status = 'canceled'
@canceled_pending.subscription_period_end = (Time.now + 30 * 24 * 60 * 60).to_i.to_s
@canceled_pending.home_region = 'EU'
@canceled_pending.received_at = Time.now.to_i.to_s
@canceled_pending.save
@created_pending_records << @canceled_pending

# Scenario 4: Trialing subscription
@trialing_email_hash = Onetime::Utils::EmailHash.compute("trialing-sub-#{SecureRandom.hex(4)}@example.com")
@trialing_pending = Billing::PendingFederatedSubscription.new(@trialing_email_hash)
@trialing_pending.subscription_status = 'trialing'
@trialing_pending.subscription_period_end = (Time.now + 30 * 24 * 60 * 60).to_i.to_s
@trialing_pending.home_region = 'US'
@trialing_pending.received_at = Time.now.to_i.to_s
@trialing_pending.save
@created_pending_records << @trialing_pending

# Scenario 5: Past_due subscription
@past_due_email_hash = Onetime::Utils::EmailHash.compute("past-due-sub-#{SecureRandom.hex(4)}@example.com")
@past_due_pending = Billing::PendingFederatedSubscription.new(@past_due_email_hash)
@past_due_pending.subscription_status = 'past_due'
@past_due_pending.subscription_period_end = (Time.now + 30 * 24 * 60 * 60).to_i.to_s
@past_due_pending.home_region = 'US'
@past_due_pending.received_at = Time.now.to_i.to_s
@past_due_pending.save
@created_pending_records << @past_due_pending

# Scenario 6: Unpaid subscription
@unpaid_email_hash = Onetime::Utils::EmailHash.compute("unpaid-sub-#{SecureRandom.hex(4)}@example.com")
@unpaid_pending = Billing::PendingFederatedSubscription.new(@unpaid_email_hash)
@unpaid_pending.subscription_status = 'unpaid'
@unpaid_pending.subscription_period_end = (Time.now + 30 * 24 * 60 * 60).to_i.to_s
@unpaid_pending.home_region = 'US'
@unpaid_pending.received_at = Time.now.to_i.to_s
@unpaid_pending.save
@created_pending_records << @unpaid_pending

# Scenario 7: Expired subscription (past period_end)
@expired_email_hash = Onetime::Utils::EmailHash.compute("expired-sub-#{SecureRandom.hex(4)}@example.com")
@expired_pending = Billing::PendingFederatedSubscription.new(@expired_email_hash)
@expired_pending.subscription_status = 'active'
@expired_pending.subscription_period_end = (Time.now - 24 * 60 * 60).to_i.to_s  # Yesterday
@expired_pending.home_region = 'US'
@expired_pending.received_at = Time.now.to_i.to_s
@expired_pending.save
@created_pending_records << @expired_pending

# Scenario 8: No period_end set
@no_period_email_hash = Onetime::Utils::EmailHash.compute("no-period-sub-#{SecureRandom.hex(4)}@example.com")
@no_period_pending = Billing::PendingFederatedSubscription.new(@no_period_email_hash)
@no_period_pending.subscription_status = 'active'
@no_period_pending.subscription_period_end = nil
@no_period_pending.home_region = 'US'
@no_period_pending.received_at = Time.now.to_i.to_s
@no_period_pending.save
@created_pending_records << @no_period_pending

# Scenario 9: No home_region
@no_region_email_hash = Onetime::Utils::EmailHash.compute("no-region-sub-#{SecureRandom.hex(4)}@example.com")
@no_region_pending = Billing::PendingFederatedSubscription.new(@no_region_email_hash)
@no_region_pending.subscription_status = 'active'
@no_region_pending.subscription_period_end = (Time.now + 30 * 24 * 60 * 60).to_i.to_s
@no_region_pending.home_region = nil
@no_region_pending.received_at = Time.now.to_i.to_s
@no_region_pending.save
@created_pending_records << @no_region_pending

# ============================================================================
# TEST CASES
# ============================================================================

# --- Edge Case 1: Idempotent Storage ---

## TEST: Initial pending record is active
@initial_pending.subscription_status
#=> 'active'

## TEST: Overwrite with new status (idempotent)
@update_pending2 = Billing::PendingFederatedSubscription.new(@update_email_hash)
@update_pending2.subscription_status = 'past_due'
@update_pending2.subscription_period_end = (Time.now + 30 * 24 * 60 * 60).to_i.to_s
@update_pending2.received_at = Time.now.to_i.to_s
@update_pending2.save
@found = Billing::PendingFederatedSubscription.find_by_email_hash(@update_email_hash)
@found.subscription_status
#=> 'past_due'

# --- Edge Case 2: Malformed email_hash ---

## TEST: Empty email_hash returns nil
Billing::PendingFederatedSubscription.find_by_email_hash('')
#=> nil

## TEST: Nil email_hash returns nil
Billing::PendingFederatedSubscription.find_by_email_hash(nil)
#=> nil

## TEST: Whitespace-only email_hash returns nil
Billing::PendingFederatedSubscription.find_by_email_hash('   ')
#=> nil

## TEST: Non-existent hash returns nil
Billing::PendingFederatedSubscription.find_by_email_hash('definitely_not_a_real_hash_12345')
#=> nil

## TEST: pending? returns false for non-existent hash
Billing::PendingFederatedSubscription.pending?('nonexistent_hash_98765')
#=> false

# --- Edge Case 3: Canceled subscription ---

## TEST: Canceled pending exists
!@canceled_pending.nil?
#=> true

## TEST: Canceled pending has 'canceled' status
@canceled_pending.subscription_status
#=> 'canceled'

## TEST: Canceled pending is NOT active
@canceled_pending.active?
#=> false

# --- Edge Case 4: Trialing subscription ---

## TEST: Trialing pending is active
@trialing_pending.active?
#=> true

## TEST: Trialing pending has 'trialing' status
@trialing_pending.subscription_status
#=> 'trialing'

# --- Edge Case 5: Past_due subscription ---

## TEST: past_due pending is active (grace period)
@past_due_pending.active?
#=> true

## TEST: past_due pending has 'past_due' status
@past_due_pending.subscription_status
#=> 'past_due'

# --- Edge Case 6: Unpaid subscription ---

## TEST: Unpaid pending is NOT active
@unpaid_pending.active?
#=> false

## TEST: Unpaid pending has 'unpaid' status
@unpaid_pending.subscription_status
#=> 'unpaid'

# --- Edge Case 7: Expiration ---

## TEST: Pending with past period_end is expired
@expired_pending.expired?
#=> true

## TEST: Pending with nil period_end is NOT expired
@no_period_pending.expired?
#=> false

# --- Edge Case 8: TTL ---

## TEST: Default TTL is 90 days (in seconds)
Billing::PendingFederatedSubscription.default_expiration
#=> 7776000

# --- Edge Case 9: Optional home_region ---

## TEST: Pending without home_region exists
!@no_region_pending.nil?
#=> true

## TEST: home_region is nil/empty
@no_region_pending.home_region.to_s.empty?
#=> true

## TEST: Pending without home_region is still active
@no_region_pending.active?
#=> true

# ============================================================================
# Teardown
# ============================================================================
@created_pending_records.each { |rec| rec.destroy! rescue nil }
