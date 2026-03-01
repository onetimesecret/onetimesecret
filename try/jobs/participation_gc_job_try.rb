# try/jobs/participation_gc_job_try.rb
#
# frozen_string_literal: true

# Tests the ParticipationGCJob scheduled maintenance job.
#
# Covers:
#   - gc_pattern detects stale members in participation sorted sets
#   - gc_pattern respects auto_repair flag
#   - INVITATION_PATTERN constant
#   - JOB_KEY constant
#   - participation_member_prefix mapping

require_relative '../support/test_helpers'

OT.boot! :test, false

require_relative '../../lib/onetime/jobs/scheduled/maintenance/participation_gc_job'

@job = Onetime::Jobs::Scheduled::Maintenance::ParticipationGCJob

def call_private(method, *args, &block)
  @job.send(method, *args, &block)
end

@cleanup_keys = []
@redis = Familia.dbclient

# Set up: a participation sorted set with valid and stale members
@test_org_id = "gc_test_#{SecureRandom.hex(4)}"
@members_key = "organization:#{@test_org_id}:members"
@cleanup_keys << @members_key

# Valid member: has backing customer key
@valid_cust_id = "cust_#{SecureRandom.hex(4)}"
@valid_cust_key = "customer:#{@valid_cust_id}"
@cleanup_keys << @valid_cust_key
@redis.hset(@valid_cust_key, 'objid', @valid_cust_id)
@redis.zadd(@members_key, 1.0, @valid_cust_id)

# Stale member: no backing customer key
@stale_cust_id = "stale_cust_#{SecureRandom.hex(4)}"
@redis.zadd(@members_key, 2.0, @stale_cust_id)

# TRYOUTS

## JOB_KEY is participation_gc
@job::JOB_KEY
#=> 'participation_gc'

## INVITATION_PATTERN is organization:*:pending_invitations
@job::INVITATION_PATTERN
#=> 'organization:*:pending_invitations'

## gc_pattern detects stale members (repair=false)
# We use a specific pattern that matches our test key
# Note: gc_pattern uses SCAN which matches glob patterns
result = call_private(:gc_pattern, @redis, "organization:#{@test_org_id}:members", false, 500)
result[:stale]
#=> 1

## gc_pattern reports keys_scanned
result = call_private(:gc_pattern, @redis, "organization:#{@test_org_id}:members", false, 500)
result[:keys_scanned]
#=> 1

## gc_pattern does not remove when repair=false
call_private(:gc_pattern, @redis, "organization:#{@test_org_id}:members", false, 500)
@redis.zscore(@members_key, @stale_cust_id).nil?
#=> false

## gc_pattern removes stale when repair=true
# Create a separate test set for this
repair_org_id = "gc_repair_#{SecureRandom.hex(4)}"
repair_key = "organization:#{repair_org_id}:members"
@cleanup_keys << repair_key
stale_id = "stale_repair_#{SecureRandom.hex(4)}"
@redis.zadd(repair_key, 1.0, stale_id)
call_private(:gc_pattern, @redis, "organization:#{repair_org_id}:members", true, 500)
@redis.zscore(repair_key, stale_id).nil?
#=> true

## participation_member_prefix maps members to customer
call_private(:participation_member_prefix, 'organization:*:members')
#=> 'customer'

## MAX_CONSECUTIVE_ERRORS constant is defined
@job::MAX_CONSECUTIVE_ERRORS
#=> 5

## gc_pending_invitations returns error count in report
# With no invitation keys, errors should be 0
result = call_private(:gc_pending_invitations, @redis, false, 500)
result[:errors]
#=> 0

# TEARDOWN

@cleanup_keys.each do |key|
  Familia.dbclient.del(key)
end
