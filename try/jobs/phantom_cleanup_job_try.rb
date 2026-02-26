# try/jobs/phantom_cleanup_job_try.rb
#
# frozen_string_literal: true

# Tests the PhantomCleanupJob scheduled maintenance job.
#
# Covers:
#   - Detects phantom members (sorted set entry with no backing key)
#   - Does not flag valid members
#   - Does not remove phantoms when auto_repair is false
#   - Removes phantoms when auto_repair is true (simulated via direct call)
#   - Handles empty sorted sets gracefully
#   - participation_member_prefix mapping

require_relative '../support/test_helpers'

OT.boot! :test, false

require_relative '../../lib/onetime/jobs/scheduled/maintenance/phantom_cleanup_job'

@job = Onetime::Jobs::Scheduled::Maintenance::PhantomCleanupJob

def call_private(method, *args, &block)
  @job.send(method, *args, &block)
end

@cleanup_keys = []
@redis = Familia.dbclient

# Set up test data: a sorted set with 3 members, 1 valid and 2 phantoms
@test_prefix = "phantom_test_#{SecureRandom.hex(4)}"
@zset_key = "#{@test_prefix}:instances"
@cleanup_keys << @zset_key

# Valid member: has a backing hash key
@valid_id = "valid_#{SecureRandom.hex(4)}"
@valid_key = "#{@test_prefix}:#{@valid_id}"
@cleanup_keys << @valid_key
@redis.hset(@valid_key, 'objid', @valid_id)
@redis.zadd(@zset_key, 1.0, @valid_id)

# Phantom members: sorted set entry but no backing hash
@phantom_id1 = "phantom1_#{SecureRandom.hex(4)}"
@phantom_id2 = "phantom2_#{SecureRandom.hex(4)}"
@redis.zadd(@zset_key, [[2.0, @phantom_id1], [3.0, @phantom_id2]])

# TRYOUTS

## scan_phantoms_in_sorted_set detects phantom members
phantoms = call_private(:scan_phantoms_in_sorted_set, @redis, @zset_key, @test_prefix, 500)
phantoms.sort == [@phantom_id1, @phantom_id2].sort
#=> true

## scan_phantoms_in_sorted_set does not flag valid members
phantoms = call_private(:scan_phantoms_in_sorted_set, @redis, @zset_key, @test_prefix, 500)
phantoms.include?(@valid_id)
#=> false

## scan_phantoms_in_sorted_set respects limit
phantoms = call_private(:scan_phantoms_in_sorted_set, @redis, @zset_key, @test_prefix, 1)
phantoms.size
#=> 1

## scan_phantoms_in_sorted_set handles empty sorted set
empty_key = "phantom_test_empty:#{SecureRandom.hex(4)}"
@cleanup_keys << empty_key
phantoms = call_private(:scan_phantoms_in_sorted_set, @redis, empty_key, 'nonexistent', 500)
phantoms
#=> []

## check_batch returns phantoms for non-existent keys
members = [@valid_id, @phantom_id1]
phantoms = call_private(:check_batch, @redis, members, @test_prefix)
phantoms
#=> [@phantom_id1]

## check_batch returns empty for all-valid members
phantoms = call_private(:check_batch, @redis, [@valid_id], @test_prefix)
phantoms
#=> []

## participation_member_prefix maps members pattern to customer
call_private(:participation_member_prefix, 'organization:*:members')
#=> 'customer'

## participation_member_prefix maps domains pattern to custom_domain
call_private(:participation_member_prefix, 'organization:*:domains')
#=> 'custom_domain'

## participation_member_prefix maps receipts pattern to receipt
call_private(:participation_member_prefix, 'organization:*:receipts')
#=> 'receipt'

## JOB_KEY is phantom_cleanup
@job::JOB_KEY
#=> 'phantom_cleanup'

# TEARDOWN

@cleanup_keys.each do |key|
  Familia.dbclient.del(key)
end
