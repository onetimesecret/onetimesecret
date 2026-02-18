# try/unit/models/organization_federation_try.rb
#
# frozen_string_literal: true

# Tests for Organization subscription federation methods (#2471).
#
# Federation allows a single Stripe subscription to grant benefits across
# multiple organizations (e.g., same user in different regions) via
# HMAC-based email hash matching.
#
# Key concepts:
# - Owner org: Has stripe_customer_id (owns the subscription)
# - Federated org: Matched by email_hash only (no stripe_customer_id)
# - Email hash is computed from billing_email (not contact_email)
# - Email hash is immutable - computed once at subscription creation
#
# Run: pnpm run test:tryouts:agent try/unit/models/organization_federation_try.rb

require_relative '../../support/test_helpers'

# Stub the HMAC secret for testing
ENV['FEDERATION_SECRET'] ||= 'test-hmac-secret-for-email-hash-32chars'

require 'onetime/utils/email_hash'

# Setup - Create test customer
@test_email = generate_unique_test_email('federation')
@customer = Onetime::Customer.create!(@test_email)
@created_orgs = []

# Helper to create org with unique emails
def create_test_org(name_prefix, customer)
  org = Onetime::Organization.create!(
    "#{name_prefix} #{SecureRandom.hex(4)}",
    customer,
    "contact-#{SecureRandom.hex(8)}@example.com"
  )
  org.billing_email = "billing-#{SecureRandom.hex(8)}@example.com"
  org.save
  @created_orgs << org
  org
end

# Create test organizations for different scenarios
@org = create_test_org('Basic Test', @customer)

## Organization has email_hash field
@org.respond_to?(:email_hash)
#=> true

## Organization has subscription_federated_at field
@org.respond_to?(:subscription_federated_at)
#=> true

## compute_email_hash! sets email_hash from billing_email
@org.compute_email_hash!
!@org.email_hash.to_s.empty?
#=> true

## email_hash matches expected format (32 hex chars)
@org.email_hash.match?(/^[a-f0-9]{32}$/)
#=> true

## compute_email_hash! sets email_hash_synced_at timestamp
!@org.email_hash_synced_at.to_s.empty?
#=> true

## compute_email_hash! produces deterministic hash
hash_before = @org.email_hash
@org.compute_email_hash!
hash_after = @org.email_hash
hash_before == hash_after
#=> true

## subscription_owner? returns true when stripe_customer_id is present
@owner_org = create_test_org('Owner', @customer)
@owner_org.stripe_customer_id = "cus_owner_#{SecureRandom.hex(4)}"
@owner_org.save
@owner_org.subscription_owner?
#=> true

## subscription_owner? returns false when stripe_customer_id is nil
@non_owner_org = create_test_org('Non-Owner', @customer)
@non_owner_org.stripe_customer_id = nil
@non_owner_org.save
@non_owner_org.subscription_owner?
#=> false

## subscription_federated? returns true when federated_at set and not owner
@federated_test_org = create_test_org('Federated Test', @customer)
@federated_test_org.stripe_customer_id = nil
@federated_test_org.subscription_federated_at = Familia.now.to_i.to_s
@federated_test_org.save
@federated_test_org.subscription_federated?
#=> true

## subscription_federated? returns false when owner (even if federated_at set)
@owner_with_timestamp = create_test_org('Owner With Timestamp', @customer)
@owner_with_timestamp.stripe_customer_id = "cus_owner_ts_#{SecureRandom.hex(4)}"
@owner_with_timestamp.subscription_federated_at = Familia.now.to_i.to_s
@owner_with_timestamp.save
@owner_with_timestamp.subscription_federated?
#=> false

## subscription_federated? returns false when federated_at is nil
@not_federated_org = create_test_org('Not Federated', @customer)
@not_federated_org.stripe_customer_id = nil
@not_federated_org.subscription_federated_at = nil
@not_federated_org.save
@not_federated_org.subscription_federated?
#=> false

## mark_subscription_federated! sets timestamp for non-owner
@mark_test_org = create_test_org('Mark Test', @customer)
@mark_test_org.stripe_customer_id = nil
@mark_test_org.subscription_federated_at = nil
@mark_test_org.save
@mark_test_org.mark_subscription_federated!
!@mark_test_org.subscription_federated_at.to_s.empty?
#=> true

## mark_subscription_federated! does NOT set timestamp for owner
@owner_mark_test = create_test_org('Owner Mark Test', @customer)
@owner_mark_test.stripe_customer_id = "cus_owner_mark_#{SecureRandom.hex(4)}"
@owner_mark_test.subscription_federated_at = nil
@owner_mark_test.save
@owner_mark_test.mark_subscription_federated!
@owner_mark_test.subscription_federated_at.to_s.empty?
#=> true

## find_all_by_email_hash returns array with organization matching hash
@lookup_org = create_test_org('Lookup Test', @customer)
@lookup_org.compute_email_hash!
@lookup_org.save
found = Onetime::Organization.find_all_by_email_hash(@lookup_org.email_hash)
found.is_a?(Array)
#=> true

## find_all_by_email_hash includes organization with matching hash
found = Onetime::Organization.find_all_by_email_hash(@lookup_org.email_hash)
found.map(&:objid).include?(@lookup_org.objid)
#=> true

## find_all_by_email_hash returns empty array for non-existent hash
Onetime::Organization.find_all_by_email_hash('nonexistent_hash_00000000').empty?
#=> true

## find_all_by_email_hash returns empty array for nil hash
Onetime::Organization.find_all_by_email_hash(nil).empty?
#=> true

## find_federated_by_email_hash filters out owners
# In production, two orgs in the same DB can't share billing_email (unique index).
# Cross-region federation happens when DIFFERENT databases have orgs with same billing_email.
# For testing, we simulate by manually setting the same email_hash on two orgs with different billing_emails.

@federated_for_filter = create_test_org('Federated For Filter', @customer)
@federated_for_filter.stripe_customer_id = nil  # federated (no stripe link)
@federated_for_filter.compute_email_hash!
@federated_for_filter.save
@shared_hash = @federated_for_filter.email_hash

@owner_for_filter = create_test_org('Owner For Filter', @customer)
@owner_for_filter.stripe_customer_id = "cus_owner_filter_#{SecureRandom.hex(4)}"  # owner
# Manually set same hash to simulate cross-region scenario
@owner_for_filter.email_hash = @shared_hash
@owner_for_filter.save

# Verify both have same hash (simulating cross-region scenario)
@owner_for_filter.email_hash == @federated_for_filter.email_hash
#=> true

## find_federated_by_email_hash excludes owner and includes federated
federated_results = Onetime::Organization.find_federated_by_email_hash(@shared_hash)
federated_results.map(&:objid).include?(@federated_for_filter.objid) &&
  !federated_results.map(&:objid).include?(@owner_for_filter.objid)
#=> true

## show_federation_notification? returns true when federated and not dismissed
@notify_org = create_test_org('Notification Test', @customer)
@notify_org.stripe_customer_id = nil
@notify_org.subscription_federated_at = Familia.now.to_i.to_s
@notify_org.federation_notification_dismissed_at = nil
@notify_org.save
@notify_org.show_federation_notification?
#=> true

## show_federation_notification? returns false when dismissed
@notify_org.dismiss_federation_notification!
@notify_org.save
@notify_org.show_federation_notification?
#=> false

## dismiss_federation_notification! sets timestamp
@dismiss_test_org = create_test_org('Dismiss Test', @customer)
@dismiss_test_org.stripe_customer_id = nil
@dismiss_test_org.subscription_federated_at = Familia.now.to_i.to_s
@dismiss_test_org.federation_notification_dismissed_at = nil
@dismiss_test_org.save
@dismiss_test_org.dismiss_federation_notification!
!@dismiss_test_org.federation_notification_dismissed_at.to_s.empty?
#=> true

## federation_notification_dismissed? returns true after dismiss
@dismiss_test_org.federation_notification_dismissed?
#=> true

## show_federation_notification? returns false when not federated
@not_federated = create_test_org('Not Federated Show', @customer)
@not_federated.stripe_customer_id = nil
@not_federated.subscription_federated_at = nil
@not_federated.federation_notification_dismissed_at = nil
@not_federated.save
@not_federated.show_federation_notification?
#=> false

# Teardown - Clean up test data
@created_orgs.each { |org| org.destroy! rescue nil }
@customer.destroy! rescue nil
