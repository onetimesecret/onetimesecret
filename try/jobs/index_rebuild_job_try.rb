# try/jobs/index_rebuild_job_try.rb
#
# frozen_string_literal: true

# Tests the IndexRebuildJob scheduled maintenance job.
#
# Covers:
#   - reconcile_index detects stale index entries (forward check)
#   - reconcile_index detects missing index entries (reverse check)
#   - reconcile_index repairs stale entries when auto_repair=true
#   - reconcile_index repairs missing entries when auto_repair=true
#   - INDEXES constant structure
#   - JOB_KEY constant

require_relative '../support/test_helpers'

OT.boot! :test, false

require_relative '../../lib/onetime/jobs/scheduled/maintenance/index_rebuild_job'

@job = Onetime::Jobs::Scheduled::Maintenance::IndexRebuildJob

def call_private(method, *args, &block)
  @job.send(method, *args, &block)
end

@cleanup_keys = []
@redis = Familia.dbclient

# Test prefix to avoid collisions
@prefix = "idx_test_#{SecureRandom.hex(4)}"
@index_key = "#{@prefix}:email_index"
@cleanup_keys << @index_key

# Valid object with matching index
@valid_id = "obj_#{SecureRandom.hex(4)}"
@valid_key = "#{@prefix}:#{@valid_id}"
@cleanup_keys << @valid_key
@redis.hset(@valid_key, 'objid', @valid_id)
@redis.hset(@valid_key, 'email', 'valid@example.com')
@redis.hset(@index_key, 'valid@example.com', @valid_id)

# Stale index entry: points to non-existent object
@redis.hset(@index_key, 'stale@example.com', 'nonexistent_objid')

# Object with no index entry (missing)
@unindexed_id = "unidx_#{SecureRandom.hex(4)}"
@unindexed_key = "#{@prefix}:#{@unindexed_id}"
@cleanup_keys << @unindexed_key
@redis.hset(@unindexed_key, 'objid', @unindexed_id)
@redis.hset(@unindexed_key, 'email', 'missing@example.com')

# TRYOUTS

## JOB_KEY is index_rebuild
@job::JOB_KEY
#=> 'index_rebuild'

## INDEXES has 3 entries
@job::INDEXES.size
#=> 3

## INDEXES first entry is customer_email
@job::INDEXES[0][0]
#=> 'customer_email'

## reconcile_index detects stale entries (repair=false)
result = call_private(:reconcile_index, @redis, @index_key, @prefix, 'email', false)
result[:stale_entries]
#=> 1

## reconcile_index detects missing entries (repair=false)
result = call_private(:reconcile_index, @redis, @index_key, @prefix, 'email', false)
result[:missing_entries]
#=> 1

## reconcile_index does not repair when repair=false
call_private(:reconcile_index, @redis, @index_key, @prefix, 'email', false)
@redis.hget(@index_key, 'stale@example.com')
#=> 'nonexistent_objid'

## reconcile_index removes stale entries when repair=true
# Use a separate index for repair test
repair_index = "#{@prefix}:repair_index"
@cleanup_keys << repair_index
@redis.hset(repair_index, 'stale@test.com', 'nonexistent')
@redis.hset(repair_index, 'valid@example.com', @valid_id)
call_private(:reconcile_index, @redis, repair_index, @prefix, 'email', true)
@redis.hget(repair_index, 'stale@test.com').nil?
#=> true

## reconcile_index adds missing entries when repair=true
repair_index2 = "#{@prefix}:repair_index2"
@cleanup_keys << repair_index2
@redis.hset(repair_index2, 'valid@example.com', @valid_id)
result = call_private(:reconcile_index, @redis, repair_index2, @prefix, 'email', true)
@redis.hget(repair_index2, 'missing@example.com').nil?
#=> false

## reconcile_index reports entries_checked count
result = call_private(:reconcile_index, @redis, @index_key, @prefix, 'email', false)
result[:entries_checked]
#=> 2

## reconcile_index reports objects_checked count
result = call_private(:reconcile_index, @redis, @index_key, @prefix, 'email', false)
result[:objects_checked] >= 2
#=> true

# TEARDOWN

@cleanup_keys.each do |key|
  Familia.dbclient.del(key)
end
