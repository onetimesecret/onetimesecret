# try/unit/billing/pending_federated_subscription_try.rb
#
# frozen_string_literal: true

# Tests PendingFederatedSubscription model, including the fix for
# store_from_webhook to use item-level current_period_end (#2471).
#
# Run: bundle exec try try/unit/billing/pending_federated_subscription_try.rb

require_relative '../../support/test_helpers'
require_relative '../../../apps/web/billing/models/pending_federated_subscription'

# Setup: Configure test secret for HMAC computation
@original_secret = ENV['FEDERATION_SECRET']
ENV['FEDERATION_SECRET'] = 'test-secret-for-pending-fed-sub-12345'

require 'ostruct'

# Precompute email hashes for all test cases
@eh1 = Onetime::Utils::EmailHash.compute('federation-test-1@example.com')
@eh2 = Onetime::Utils::EmailHash.compute('federation-test-2@example.com')
@eh3 = Onetime::Utils::EmailHash.compute('federation-test-3@example.com')
@eh4 = Onetime::Utils::EmailHash.compute('federation-test-4@example.com')
@eh5 = Onetime::Utils::EmailHash.compute('federation-test-5@example.com')
@eh6 = Onetime::Utils::EmailHash.compute('federation-test-6@example.com')
@eh7 = Onetime::Utils::EmailHash.compute('federation-test-7@example.com')

def build_mock_subscription(status:, period_end:, price_id: 'price_test_123')
  item = OpenStruct.new(
    current_period_end: period_end,
    price: OpenStruct.new(id: price_id)
  )
  items = OpenStruct.new(data: [item])
  OpenStruct.new(status: status, items: items, metadata: {})
end

def build_mock_subscription_no_items(status:)
  items = OpenStruct.new(data: [])
  OpenStruct.new(status: status, items: items, metadata: {})
end

# Store record for subsequent tests
@sub1 = build_mock_subscription(status: 'active', period_end: 1_750_000_000)
@pending1 = Billing::PendingFederatedSubscription.store_from_webhook(
  email_hash: @eh1,
  subscription: @sub1,
  region: 'us-east'
)

# --- store_from_webhook: item-level period_end ---

## store_from_webhook reads current_period_end from items.data.first
@pending1.subscription_period_end.to_s
#=> '1750000000'

## store_from_webhook sets subscription_status from subscription object
@pending1.subscription_status
#=> 'active'

## store_from_webhook sets region
@pending1.region
#=> 'us-east'

## store_from_webhook sets received_at to a recent timestamp
@pending1.received_at.to_i > 0
#=> true

## store_from_webhook handles nil period_end when items list is empty
sub_no_items = build_mock_subscription_no_items(status: 'active')
p2 = Billing::PendingFederatedSubscription.store_from_webhook(
  email_hash: @eh2,
  subscription: sub_no_items,
  region: 'eu-west'
)
p2.subscription_period_end.to_s
#=> ''

## store_from_webhook is idempotent (same email_hash overwrites)
sub_v1 = build_mock_subscription(status: 'active', period_end: 1_700_000_000)
sub_v2 = build_mock_subscription(status: 'past_due', period_end: 1_800_000_000)
Billing::PendingFederatedSubscription.store_from_webhook(email_hash: @eh3, subscription: sub_v1)
p3 = Billing::PendingFederatedSubscription.store_from_webhook(email_hash: @eh3, subscription: sub_v2)
[p3.subscription_status, p3.subscription_period_end.to_s]
#=> ['past_due', '1800000000']

# --- Model instance methods ---

## active? returns true for active status
sub_active = build_mock_subscription(status: 'active', period_end: (Time.now.to_i + 86_400))
p4 = Billing::PendingFederatedSubscription.store_from_webhook(email_hash: @eh4, subscription: sub_active)
p4.active?
#=> true

## active? returns false for canceled status
sub_canceled = build_mock_subscription(status: 'canceled', period_end: Time.now.to_i)
p5 = Billing::PendingFederatedSubscription.store_from_webhook(email_hash: @eh5, subscription: sub_canceled)
p5.active?
#=> false

## expired? returns true when period_end is in the past
sub_expired = build_mock_subscription(status: 'active', period_end: 1_000_000)
p6 = Billing::PendingFederatedSubscription.store_from_webhook(email_hash: @eh6, subscription: sub_expired)
p6.expired?
#=> true

## expired? returns false when period_end is in the future
future_ts = Time.now.to_i + 86_400 * 30
sub_future = build_mock_subscription(status: 'active', period_end: future_ts)
p7 = Billing::PendingFederatedSubscription.store_from_webhook(email_hash: @eh7, subscription: sub_future)
p7.expired?
#=> false

## find_by_email_hash retrieves a stored record
found = Billing::PendingFederatedSubscription.find_by_email_hash(@eh1)
found&.subscription_period_end.to_s
#=> '1750000000'

## pending? returns true for stored hash
Billing::PendingFederatedSubscription.pending?(@eh1)
#=> true

## pending? returns false for unknown hash
Billing::PendingFederatedSubscription.pending?('nonexistent_hash_value')
#=> false

# Teardown: destroy test records and restore secret
[@eh1, @eh2, @eh3, @eh4, @eh5, @eh6, @eh7].each do |h|
  record = Billing::PendingFederatedSubscription.find_by_email_hash(h)
  record&.destroy!
end
ENV['FEDERATION_SECRET'] = @original_secret
