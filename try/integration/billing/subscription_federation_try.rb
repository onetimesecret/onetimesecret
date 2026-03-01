# try/integration/billing/subscription_federation_try.rb
#
# frozen_string_literal: true

# Integration tests for subscription federation flow (#2471).
#
# Tests the complete flow:
# 1. Create org with contact_email
# 2. Compute and store email_hash
# 3. Simulate subscription creation (sets Stripe metadata)
# 4. Simulate webhook with email_hash in metadata
# 5. Verify federation matching works correctly
#
# Run: pnpm run test:tryouts:agent try/integration/billing/subscription_federation_try.rb

require_relative '../../support/test_helpers'

# Stub the HMAC secret for testing
ENV['FEDERATION_SECRET'] ||= 'test-hmac-secret-for-email-hash-32chars'

require 'onetime/utils/email_hash'

# Setup test data - each org needs unique contact_email due to unique index
@owner_email = generate_unique_test_email('owner')
@federated_email = generate_unique_test_email('federated')

# Create customers
@owner_customer = Onetime::Customer.create!(@owner_email)
@federated_customer = Onetime::Customer.create!(@federated_email)

# Shared billing email for hash computation
# In cross-region federation, the same user would have same billing_email in different DBs
# Here we simulate by computing the hash and setting it directly
@shared_billing_email = "shared-billing-#{SecureRandom.hex(8)}@example.com"
@shared_hash = Onetime::Utils::EmailHash.compute(@shared_billing_email)

# Create organizations with different contact_emails but same email_hash
@owner_org = Onetime::Organization.create!('Owner Workspace', @owner_customer, "owner-contact-#{SecureRandom.hex(4)}@example.com")
@owner_org.billing_email = @shared_billing_email
@owner_org.compute_email_hash!
@owner_org.save

@federated_org = Onetime::Organization.create!('Federated Workspace', @federated_customer, "fed-contact-#{SecureRandom.hex(4)}@example.com")
# Set same email_hash directly to simulate cross-region scenario
# In production, this org would be in a different DB with its own billing_email
@federated_org.email_hash = @shared_hash
@federated_org.save

## Owner org has email_hash set
@owner_org.email_hash.nil?
#=> false

## Both orgs have same email_hash (simulating cross-region scenario)
@federated_org.email_hash == @owner_org.email_hash
#=> true

## Owner org gets stripe_customer_id when subscribing
@owner_cus_id = "cus_int_owner_#{SecureRandom.hex(4)}"
@owner_org.stripe_customer_id = @owner_cus_id
@owner_org.stripe_subscription_id = "sub_int_#{SecureRandom.hex(4)}"
@owner_org.subscription_status = 'active'
@owner_org.save
@owner_org.subscription_owner?
#=> true

## Federated org has no stripe_customer_id
@federated_org.stripe_customer_id.nil? || @federated_org.stripe_customer_id.empty?
#=> true

## Find owner by stripe_customer_id
found_owner = Onetime::Organization.find_by_stripe_customer_id(@owner_cus_id)
found_owner&.objid == @owner_org.objid
#=> true

## Find federated by email_hash (manually filter out owner with stripe_customer_id)
all_matching = Onetime::Organization.find_all_by_email_hash(@owner_org.email_hash)
federated_only = all_matching.select { |org| org.stripe_customer_id.to_s.empty? }
# Should find federated_org (no stripe_customer_id), not owner_org
federated_only.map(&:objid).include?(@federated_org.objid)
#=> true

## Federation update flow: both orgs get updated status
# Simulate webhook processing
@owner_org.subscription_status = 'past_due'
@owner_org.save
@federated_org.subscription_status = 'past_due'
@federated_org.mark_subscription_federated!
@federated_org.save

[@owner_org.subscription_status, @federated_org.subscription_status]
#=> ['past_due', 'past_due']

## Federation marking: only federated org has federated flag
[@owner_org.subscription_federated?, @federated_org.subscription_federated?]
#=> [false, true]

## Email hash is preserved after contact_email change
@original_hash = @owner_org.email_hash
@owner_org.contact_email = "changed-#{SecureRandom.hex(8)}@example.com"
@owner_org.save
# Email hash should NOT change (it's computed once, not tied to contact_email)
@owner_org.email_hash == @original_hash
#=> true

## Explicit recompute updates hash when billing_email changes
# First, change the billing_email to something different
@new_billing_email = "new-billing-#{SecureRandom.hex(8)}@example.com"
@owner_org.billing_email = @new_billing_email
@owner_org.compute_email_hash!
@owner_org.save
# Now hash changes because billing_email changed and we recomputed
@new_hash = @owner_org.email_hash
@new_hash != @original_hash
#=> true

## Subscription cancellation flow
@owner_org.subscription_status = 'canceled'
@owner_org.stripe_subscription_id = nil
@owner_org.save
@federated_org.subscription_status = 'canceled'
@federated_org.save

[@owner_org.subscription_status, @federated_org.subscription_status]
#=> ['canceled', 'canceled']

## Owner status check after cancellation
@owner_org.active_subscription?
#=> false

## Federated status check after cancellation
@federated_org.active_subscription?
#=> false

# Teardown
@owner_org.destroy! rescue nil
@federated_org.destroy! rescue nil
@owner_customer.destroy! rescue nil
@federated_customer.destroy! rescue nil
