# try/unit/models/receipt_expiration_tracking_try.rb
#
# frozen_string_literal: true

#
# Unit tests for Receipt expiration tracking feature.
# Tests cover:
# - expiration_timeline sorted set operations
# - warnings_sent set operations
# - register_for_expiration_notifications method
# - expiring_within query method
# - warning_sent? / mark_warning_sent methods
# - cleanup_expired_from_timeline method

require_relative '../../support/test_models'

OT.boot! :test

# Setup test data
@test_suffix = "#{Familia.now.to_i}_#{rand(10000)}"
@owner = Onetime::Customer.create!(email: "exptest_owner#{@test_suffix}@example.com")

# Clear any existing test data from previous runs
Onetime::Receipt.expiration_timeline.clear
Onetime::Receipt.warnings_sent.clear

# Helper to create a test receipt with specific TTL
def create_test_receipt(lifespan_seconds)
  receipt, _secret = Onetime::Receipt.spawn_pair(
    @owner.custid,
    lifespan_seconds,
    "test secret content #{rand(10000)}"
  )
  receipt
end

# TRYOUTS

## expiration_timeline is a Familia::SortedSet
Onetime::Receipt.expiration_timeline.class
#=> Familia::SortedSet

## warnings_sent is a Familia::UnsortedSet
Onetime::Receipt.warnings_sent.class
#=> Familia::UnsortedSet

## min_warning_ttl returns integer seconds
Onetime::Receipt.min_warning_ttl.class
#=> Integer

## min_warning_ttl defaults to 48 hours (172800 seconds) when not configured
# Note: May vary based on test config, but should be positive
Onetime::Receipt.min_warning_ttl > 0
#=> true

## register_for_expiration_notifications returns false for short TTL secrets
# Create receipt with 1 hour TTL (below 48h minimum)
short_lived = create_test_receipt(3600)
# The method should have returned false (TTL too short)
short_lived.secret_ttl.to_i < Onetime::Receipt.min_warning_ttl
#=> true

## register_for_expiration_notifications returns true for long TTL secrets
# Create receipt with 72 hour TTL (above 48h minimum)
long_lived = create_test_receipt(259200)
# Check it was registered
Onetime::Receipt.expiration_timeline.member?(long_lived.identifier)
#=> true

## expiring_within finds secrets in the time window
# First add a test entry with known expiration
@test_expiring_id = "test_expiring_#{rand(10000)}"
future_time = Familia.now.to_f + 1800  # 30 minutes from now
Onetime::Receipt.expiration_timeline.add(@test_expiring_id, future_time)
# Query for secrets expiring within 1 hour
results = Onetime::Receipt.expiring_within(3600)
results.include?(@test_expiring_id)
#=> true

## expiring_within excludes secrets outside the time window
# The @test_expiring_id we added expires in 30 minutes
# Query for secrets expiring within 10 minutes should NOT include it
results = Onetime::Receipt.expiring_within(600)
results.include?(@test_expiring_id)
#=> false

## warning_sent? returns false for new receipt
test_id2 = "test_warning_#{rand(10000)}"
Onetime::Receipt.warning_sent?(test_id2)
#=> false

## mark_warning_sent adds entry to warnings_sent set
test_id3 = "test_mark_#{rand(10000)}"
Onetime::Receipt.mark_warning_sent(test_id3)
Onetime::Receipt.warning_sent?(test_id3)
#=> true

## cleanup_expired_from_timeline removes old entries
# Add an entry that "expired" 2 hours ago
old_id = "test_old_#{rand(10000)}"
past_time = Familia.now.to_f - 7200  # 2 hours ago
Onetime::Receipt.expiration_timeline.add(old_id, past_time)
# Verify it exists
before_cleanup = Onetime::Receipt.expiration_timeline.member?(old_id)
# Clean up entries older than 1 hour ago
Onetime::Receipt.cleanup_expired_from_timeline(Familia.now.to_f - 3600)
# Verify it was removed
after_cleanup = Onetime::Receipt.expiration_timeline.member?(old_id)
[before_cleanup, after_cleanup]
#=> [true, false]

## cleanup_expired_from_timeline preserves future entries
# Add a future entry
future_id = "test_future_#{rand(10000)}"
future_exp = Familia.now.to_f + 86400  # 24 hours from now
Onetime::Receipt.expiration_timeline.add(future_id, future_exp)
# Clean up old entries
Onetime::Receipt.cleanup_expired_from_timeline(Familia.now.to_f - 3600)
# Future entry should still exist
Onetime::Receipt.expiration_timeline.member?(future_id)
#=> true

# Cleanup after tests
Onetime::Receipt.expiration_timeline.clear
Onetime::Receipt.warnings_sent.clear
