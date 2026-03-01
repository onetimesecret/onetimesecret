# try/jobs/maintenance_job_try.rb
#
# frozen_string_literal: true

# Tests the MaintenanceJob base class shared infrastructure.
#
# Covers:
#   - Config access helpers (maintenance_config, job_config, etc.)
#   - job_enabled? requires both master and job-level toggle
#   - auto_repair? defaults to false
#   - batch_size and sample_size defaults
#   - with_stats wraps execution with timing
#   - pipeline_exists returns boolean results
#   - zscan_each iterates sorted set members
#   - participation_member_prefix mapping (extracted to base class)

require_relative '../support/test_helpers'

OT.boot! :test, false

require_relative '../../lib/onetime/jobs/maintenance_job'

@job = Onetime::Jobs::MaintenanceJob

# Helper to call private class methods
def call_private(method, *args, &block)
  @job.send(method, *args, &block)
end

@cleanup_keys = []

# TRYOUTS

## maintenance_config returns a hash (possibly empty)
call_private(:maintenance_config).is_a?(Hash)
#=> true

## job_config returns a hash for unknown key
call_private(:job_config, 'nonexistent').is_a?(Hash)
#=> true

## job_enabled? returns false when maintenance is not enabled
call_private(:job_enabled?, 'phantom_cleanup')
#=> false

## auto_repair? returns false by default
call_private(:auto_repair?, 'phantom_cleanup')
#=> false

## batch_size returns 500 default for unconfigured job
call_private(:batch_size, 'phantom_cleanup')
#=> 500

## sample_size returns 100 default for unconfigured job
call_private(:sample_size, 'data_audit')
#=> 100

## INSTANCE_MODELS has 7 entries
@job::INSTANCE_MODELS.size
#=> 7

## INSTANCE_MODELS first entry is Customer
@job::INSTANCE_MODELS[0][0]
#=> 'Customer'

## PARTICIPATION_PATTERNS has 4 entries
@job::PARTICIPATION_PATTERNS.size
#=> 4

## resolve_model resolves Onetime::Customer
call_private(:resolve_model, 'Onetime::Customer').name
#=> 'Onetime::Customer'

## PIPELINE_BATCH is 50
@job::PIPELINE_BATCH
#=> 50

## with_stats yields a report hash and adds timing fields
report = call_private(:with_stats, 'TestJob') do |r|
  r[:test_data] = 'hello'
end
[report.key?(:duration_ms), report.key?(:completed_at), report[:test_data]]
#=> [true, true, 'hello']

## pipeline_exists returns array of booleans
redis = Familia.dbclient
test_key = "maint_test:#{SecureRandom.hex(4)}"
@cleanup_keys << test_key
redis.hset(test_key, 'objid', 'test')
results = call_private(:pipeline_exists, redis, [test_key, "#{test_key}:nonexistent"])
results
#=> [true, false]

## zscan_each yields members of a sorted set
zset_key = "maint_test_zset:#{SecureRandom.hex(4)}"
@cleanup_keys << zset_key
Familia.dbclient.zadd(zset_key, [[1.0, 'alpha'], [2.0, 'beta']])
collected = []
call_private(:zscan_each, Familia.dbclient, zset_key) { |m| collected << m }
collected.sort
#=> ['alpha', 'beta']

## zscan_each handles empty sorted set
empty_key = "maint_test_empty:#{SecureRandom.hex(4)}"
@cleanup_keys << empty_key
empty_collected = []
call_private(:zscan_each, Familia.dbclient, empty_key) { |m| empty_collected << m }
empty_collected
#=> []

## participation_member_prefix maps members to customer
call_private(:participation_member_prefix, 'organization:*:members')
#=> 'customer'

## participation_member_prefix maps domains to custom_domain
call_private(:participation_member_prefix, 'organization:*:domains')
#=> 'custom_domain'

## participation_member_prefix maps receipts to receipt
call_private(:participation_member_prefix, 'custom_domain:*:receipts')
#=> 'receipt'

## participation_member_prefix returns unknown for unrecognized pattern
call_private(:participation_member_prefix, 'organization:*:something_else')
#=> 'unknown'

# TEARDOWN

@cleanup_keys.each do |key|
  Familia.dbclient.del(key)
end
