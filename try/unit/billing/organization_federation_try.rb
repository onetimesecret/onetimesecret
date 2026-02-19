# try/unit/billing/organization_federation_try.rb
#
# frozen_string_literal: true

# Tests Organization federation methods for cross-region subscription matching.
#
# Run: bundle exec try try/unit/billing/organization_federation_try.rb

require_relative '../../support/test_helpers'
require 'onetime/models'

# Setup: Configure test secret and create test data
@original_secret = ENV['FEDERATION_SECRET']
ENV['FEDERATION_SECRET'] = 'test-secret-for-org-federation-12345'

# Create a test customer to own organizations
@test_email = generate_unique_test_email('org_fed')
@customer = Onetime::Customer.new(
  custid: "cust_#{SecureRandom.hex(8)}",
  email: @test_email,
  role: 'customer'
)
@customer.save

# Create test organization
@org = Onetime::Organization.create!(
  'Federation Test Org',
  @customer,
  "billing_#{SecureRandom.hex(4)}@example.com"
)

## Organization can compute email hash from billing_email
@org.billing_email = 'test@federation.com'
hash = @org.compute_email_hash!
[hash.length, hash.match?(/\A[a-f0-9]+\z/)]
#=> [32, true]

## compute_email_hash! sets email_hash field
@org.billing_email = 'another@federation.com'
@org.compute_email_hash!
!@org.email_hash.to_s.empty?
#=> true

## compute_email_hash! sets email_hash_synced_at timestamp
@org.billing_email = 'timestamped@federation.com'
@org.compute_email_hash!
@org.email_hash_synced_at.to_s.match?(/\d{4}-\d{2}-\d{2}@\d{2}:\d{2}Z/)
#=> true

## subscription_owner? returns false when no stripe_customer_id
@org.stripe_customer_id = nil
@org.subscription_owner?
#=> false

## subscription_owner? returns true when stripe_customer_id is set
@org.stripe_customer_id = 'cus_test123'
@org.subscription_owner?
#=> true

## subscription_federated? returns false when not federated
@org.stripe_customer_id = nil
@org.subscription_federated_at = nil
@org.subscription_federated?
#=> false

## subscription_federated? returns true when federated and not owner
@org.stripe_customer_id = nil
@org.subscription_federated_at = Familia.now.to_i.to_s
@org.subscription_federated?
#=> true

## subscription_federated? returns false when owner even with federated_at set
@org.stripe_customer_id = 'cus_owner123'
@org.subscription_federated_at = Familia.now.to_i.to_s
@org.subscription_federated?
#=> false

## mark_subscription_federated! sets timestamp for non-owners
@org.stripe_customer_id = nil
@org.subscription_federated_at = nil
result = @org.mark_subscription_federated!
[result.is_a?(Integer), result > 0]
#=> [true, true]

## mark_subscription_federated! returns nil for owners
@org.stripe_customer_id = 'cus_owner456'
@org.subscription_federated_at = nil
@org.mark_subscription_federated!
#=> nil

## mark_subscription_federated! does not overwrite existing timestamp for owners
@org.stripe_customer_id = 'cus_owner789'
@org.subscription_federated_at = nil
@org.mark_subscription_federated!
@org.subscription_federated_at.to_s.empty?
#=> true

## clear_federated_status! clears the timestamp
@org.subscription_federated_at = Familia.now.to_i.to_s
@org.clear_federated_status!
@org.subscription_federated_at.nil?
#=> true

## Email hash is consistent across compute calls
@org.billing_email = 'consistent@test.com'
hash1 = @org.compute_email_hash!
hash2 = @org.compute_email_hash!
hash1 == hash2
#=> true

## Email hash changes when billing_email changes
@org.billing_email = 'email1@test.com'
hash1 = @org.compute_email_hash!
@org.billing_email = 'email2@test.com'
hash2 = @org.compute_email_hash!
hash1 != hash2
#=> true

## Email hash is nil when billing_email is empty
@org.billing_email = ''
hash = @org.compute_email_hash!
hash.nil?
#=> true

# Teardown: Clean up test data
@org.destroy! if @org&.exists?
@customer.destroy! if @customer&.exists?
ENV['FEDERATION_SECRET'] = @original_secret
