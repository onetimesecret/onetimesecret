# try/jobs/instances_rebuild_job_try.rb
#
# frozen_string_literal: true

# Tests the InstancesRebuildJob scheduled maintenance job.
#
# Covers:
#   - reconcile_model detects missing members (key exists, not in instances)
#   - reconcile_model detects phantom members (in instances, key gone)
#   - reconcile_model aborts when drift exceeds threshold
#   - reconcile_model repairs when auto_repair=true
#   - DRIFT_THRESHOLD constant
#   - JOB_KEY constant

require_relative '../support/test_helpers'

OT.boot! :test, false

require_relative '../../lib/onetime/jobs/scheduled/maintenance/instances_rebuild_job'

@job = Onetime::Jobs::Scheduled::Maintenance::InstancesRebuildJob

def call_private(method, *args, &block)
  @job.send(method, *args, &block)
end

@cleanup_keys = []
@redis = Familia.dbclient

# Test prefix
@prefix = "rebuild_test_#{SecureRandom.hex(4)}"
@instances_key = "#{@prefix}:instances"
@cleanup_keys << @instances_key

# Object in both instances and as a key (consistent)
@consistent_id = "con_#{SecureRandom.hex(4)}"
@consistent_key = "#{@prefix}:#{@consistent_id}"
@cleanup_keys << @consistent_key
@redis.hset(@consistent_key, 'objid', @consistent_id)
@redis.zadd(@instances_key, 1.0, @consistent_id)

# Object exists as key but missing from instances
@missing_id = "miss_#{SecureRandom.hex(4)}"
@missing_key = "#{@prefix}:#{@missing_id}"
@cleanup_keys << @missing_key
@redis.hset(@missing_key, 'objid', @missing_id)

# Phantom: in instances but no backing key
@phantom_id = "phant_#{SecureRandom.hex(4)}"
@redis.zadd(@instances_key, 2.0, @phantom_id)

# TRYOUTS

## JOB_KEY is instances_rebuild
@job::JOB_KEY
#=> 'instances_rebuild'

## DRIFT_THRESHOLD is 0.20
@job::DRIFT_THRESHOLD
#=> 0.20

## reconcile_model detects missing members
result = call_private(:reconcile_model, @redis, @instances_key, @prefix, false)
result[:missing_from_instances]
#=> 1

## reconcile_model detects phantom members
result = call_private(:reconcile_model, @redis, @instances_key, @prefix, false)
result[:phantom_in_instances]
#=> 1

## reconcile_model counts scanned keys
result = call_private(:reconcile_model, @redis, @instances_key, @prefix, false)
result[:scanned_keys]
#=> 2

## reconcile_model counts current members
result = call_private(:reconcile_model, @redis, @instances_key, @prefix, false)
result[:current_members]
#=> 2

## reconcile_model does not repair when repair=false
call_private(:reconcile_model, @redis, @instances_key, @prefix, false)
@redis.zscore(@instances_key, @phantom_id).nil?
#=> false

## reconcile_model repairs when repair=true
# Use separate test data for repair
repair_prefix = "rebuild_repair_#{SecureRandom.hex(4)}"
repair_instances = "#{repair_prefix}:instances"
@cleanup_keys << repair_instances

# Add consistent member
r_con_id = "rcon_#{SecureRandom.hex(4)}"
r_con_key = "#{repair_prefix}:#{r_con_id}"
@cleanup_keys << r_con_key
@redis.hset(r_con_key, 'objid', r_con_id)
@redis.zadd(repair_instances, 1.0, r_con_id)

# Add missing key (not in instances)
r_miss_id = "rmiss_#{SecureRandom.hex(4)}"
r_miss_key = "#{repair_prefix}:#{r_miss_id}"
@cleanup_keys << r_miss_key
@redis.hset(r_miss_key, 'objid', r_miss_id)

# Add phantom (in instances, no key)
r_phant_id = "rphant_#{SecureRandom.hex(4)}"
@redis.zadd(repair_instances, 2.0, r_phant_id)

result = call_private(:reconcile_model, @redis, repair_instances, repair_prefix, true)
result[:repaired]
#=> true

## After repair, missing member is added to instances
@redis.zscore(repair_instances, r_miss_id).nil?
#=> false

## After repair, phantom member is removed from instances
@redis.zscore(repair_instances, r_phant_id).nil?
#=> true

## reconcile_model handles empty data gracefully
empty_prefix = "rebuild_empty_#{SecureRandom.hex(4)}"
empty_instances = "#{empty_prefix}:instances"
@cleanup_keys << empty_instances
result = call_private(:reconcile_model, @redis, empty_instances, empty_prefix, false)
[result[:scanned_keys], result[:current_members], result[:aborted]]
#=> [0, 0, false]

# TEARDOWN

@cleanup_keys.each do |key|
  Familia.dbclient.del(key)
end
