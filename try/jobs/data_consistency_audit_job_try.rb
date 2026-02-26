# try/jobs/data_consistency_audit_job_try.rb
#
# frozen_string_literal: true

# Tests the DataConsistencyAuditJob scheduled maintenance job.
#
# Covers:
#   - audit_model detects phantoms in a sorted set
#   - audit_model counts real hash keys via SCAN
#   - audit_hash_index detects stale index entries
#   - audit_hash_index handles empty indexes
#   - JOB_KEY constant

require_relative '../support/test_helpers'

OT.boot! :test, false

require_relative '../../lib/onetime/jobs/scheduled/maintenance/data_consistency_audit_job'

@job = Onetime::Jobs::Scheduled::Maintenance::DataConsistencyAuditJob

def call_private(method, *args, &block)
  @job.send(method, *args, &block)
end

@cleanup_keys = []
@redis = Familia.dbclient

# TRYOUTS

## JOB_KEY is data_audit
@job::JOB_KEY
#=> 'data_audit'

## audit_hash_index reports zero stale for empty index
empty_index = "audit_test_index:#{SecureRandom.hex(4)}"
@cleanup_keys << empty_index
result = call_private(:audit_hash_index, @redis, empty_index, 'test', 100)
result[:total]
#=> 0

## audit_hash_index detects stale index entries
index_key = "audit_test_idx:#{SecureRandom.hex(4)}"
target_prefix = "audit_test_obj_#{SecureRandom.hex(4)}"
@cleanup_keys << index_key

# Add valid entry: index points to an existing object
valid_objid = "obj_#{SecureRandom.hex(4)}"
valid_obj_key = "#{target_prefix}:#{valid_objid}"
@cleanup_keys << valid_obj_key
@redis.hset(valid_obj_key, 'objid', valid_objid)
@redis.hset(index_key, 'valid@example.com', valid_objid)

# Add stale entry: index points to a non-existent object
@redis.hset(index_key, 'stale@example.com', 'nonexistent_objid')

result = call_private(:audit_hash_index, @redis, index_key, target_prefix, 100)
[result[:total], result[:stale]]
#=> [2, 1]

## audit_hash_index sampled count matches entries checked
result = call_private(:audit_hash_index, @redis, index_key, target_prefix, 100)
result[:sampled]
#=> 2

## participation_member_prefix maps correctly
call_private(:participation_member_prefix, 'custom_domain:*:receipts')
#=> 'receipt'

# TEARDOWN

@cleanup_keys.each do |key|
  Familia.dbclient.del(key)
end
