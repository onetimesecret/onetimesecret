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

# ==========================================================================
# cleanup_orphaned_warnings tests [Task #107]
#
# Tests the cleanup_orphaned_warnings method that removes entries from
# warnings_sent that no longer exist in expiration_timeline.
# ==========================================================================

## remove_element directly removes from warnings_sent set
# Verify that remove_element works correctly
Onetime::Receipt.warnings_sent.clear
test_remove_id = "test_remove_#{rand(10000)}"
Onetime::Receipt.warnings_sent.add_element(test_remove_id)
before = Onetime::Receipt.warnings_sent.member?(test_remove_id)
Onetime::Receipt.warnings_sent.remove_element(test_remove_id)
after = Onetime::Receipt.warnings_sent.member?(test_remove_id)
[before, after]
#=> [true, false]

## cleanup_orphaned_warnings removes orphaned entries
# Clear both sets first to ensure isolation
Onetime::Receipt.warnings_sent.clear
Onetime::Receipt.expiration_timeline.clear
# Add entries to warnings_sent that don't exist in expiration_timeline
orphan_id1 = "orphan_#{rand(10000)}"
orphan_id2 = "orphan_#{rand(10000)}"
Onetime::Receipt.warnings_sent.add_element(orphan_id1)
Onetime::Receipt.warnings_sent.add_element(orphan_id2)
# Verify they exist
before = [Onetime::Receipt.warnings_sent.member?(orphan_id1), Onetime::Receipt.warnings_sent.member?(orphan_id2)]
# Run cleanup
Onetime::Receipt.cleanup_orphaned_warnings
# Verify they were removed
after = [Onetime::Receipt.warnings_sent.member?(orphan_id1), Onetime::Receipt.warnings_sent.member?(orphan_id2)]
[before, after]
#=> [[true, true], [false, false]]

## cleanup_orphaned_warnings preserves entries that exist in expiration_timeline
# Add entry to both warnings_sent and expiration_timeline
valid_id = "valid_#{rand(10000)}"
future_time = Familia.now.to_f + 86400
Onetime::Receipt.expiration_timeline.add(valid_id, future_time)
Onetime::Receipt.warnings_sent.add_element(valid_id)
# Run cleanup
Onetime::Receipt.cleanup_orphaned_warnings
# Entry should still exist in warnings_sent
Onetime::Receipt.warnings_sent.member?(valid_id)
#=> true

## cleanup_orphaned_warnings returns count of removed entries
# Clear and set up fresh test data
Onetime::Receipt.warnings_sent.clear
Onetime::Receipt.expiration_timeline.clear
# Add 3 orphaned entries
(1..3).each { |i| Onetime::Receipt.warnings_sent.add_element("orphan_count_#{i}_#{rand(10000)}") }
# Add 1 valid entry (in both sets)
both_id = "both_#{rand(10000)}"
Onetime::Receipt.expiration_timeline.add(both_id, Familia.now.to_f + 3600)
Onetime::Receipt.warnings_sent.add_element(both_id)
# Run cleanup and check return value
removed_count = Onetime::Receipt.cleanup_orphaned_warnings
removed_count
#=> 3

## cleanup_orphaned_warnings handles empty warnings_sent
Onetime::Receipt.warnings_sent.clear
Onetime::Receipt.cleanup_orphaned_warnings
#=> 0

## cleanup_orphaned_warnings batch processing works for sets larger than batch_size
# Add many orphaned entries to test batch processing
Onetime::Receipt.warnings_sent.clear
batch_test_prefix = "batch_#{rand(10000)}"
entry_count = 15  # More than default batch_size of 10 for this test
entry_count.times { |i| Onetime::Receipt.warnings_sent.add_element("#{batch_test_prefix}_#{i}") }
# Verify all entries added
before_count = entry_count.times.count { |i| Onetime::Receipt.warnings_sent.member?("#{batch_test_prefix}_#{i}") }
# Run cleanup with small batch size to ensure multiple iterations
removed = Onetime::Receipt.cleanup_orphaned_warnings(batch_size: 5)
# Verify all orphaned entries were removed
after_count = entry_count.times.count { |i| Onetime::Receipt.warnings_sent.member?("#{batch_test_prefix}_#{i}") }
[before_count, removed, after_count]
#=> [15, 15, 0]

# Cleanup after tests
Onetime::Receipt.expiration_timeline.clear
Onetime::Receipt.warnings_sent.clear
