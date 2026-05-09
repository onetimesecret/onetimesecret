# try/jobs/housekeeping_job_try.rb
#
# frozen_string_literal: true

# Tests the HousekeepingJob class — its scheduling guard, model discovery,
# and per-instance chore execution against a stub Familia::Horreum class.
#
# We construct an isolated, non-Onetime model with the upstream
# `feature :housekeeping` and a couple of `chore :name` blocks, then verify
# perform() iterates instances, calls tidy!, and aggregates stats.

require_relative '../support/test_helpers'

OT.boot! :test, false

require_relative '../../lib/onetime/jobs/scheduled/housekeeping_job'

@job = Onetime::Jobs::Scheduled::HousekeepingJob

# Helper to call private class methods
def call_private(method, *args, &block)
  @job.send(method, *args, &block)
end

# A throwaway Horreum model so we don't pollute production keyspace.
# Familia must already provide :housekeeping for this to load.
class HousekeepingTryModel < Familia::Horreum
  feature :housekeeping
  feature :object_identifier

  prefix :housekeeping_try
  identifier_field :objid

  field :status

  chore :uppercase_status do |obj|
    next unless obj.status && obj.status != obj.status.upcase

    obj.status = obj.status.upcase
    obj.save
    true
  end

  chore :always_noop do |_obj|
    nil
  end
end

@cleanup_objids = []
@created_records = []

def make_record(status:)
  rec = HousekeepingTryModel.new(status: status)
  rec.save
  @created_records << rec
  @cleanup_objids << rec.identifier
  rec
end

# TRYOUTS

## HousekeepingJob is a ScheduledJob subclass
@job < Onetime::Jobs::ScheduledJob
#=> true

## JOB_KEY is 'housekeeping'
@job::JOB_KEY
#=> 'housekeeping'

## job_enabled? returns false when maintenance.housekeeping is not enabled
call_private(:job_enabled?)
#=> false

## job_cron has a sensible default
call_private(:job_cron)
#=> '0 2 * * *'

## resolve_model handles top-level constant lookup
call_private(:resolve_model, 'HousekeepingTryModel').name
#=> 'HousekeepingTryModel'

## resolve_model handles nested namespace
call_private(:resolve_model, 'Onetime::Customer').name
#=> 'Onetime::Customer'

## models_with_chores skips models without the housekeeping feature
@job.models_with_chores.none? { |k| k == Onetime::Customer }
#=> true

## perform raises ArgumentError for models without housekeeping
begin
  @job.perform('Onetime::Customer')
  false
rescue ArgumentError => ex
  ex.message.include?('feature :housekeeping')
end
#=> true

## perform raises ArgumentError for unknown chore name
make_record(status: 'active')
begin
  @job.perform('HousekeepingTryModel', :no_such_chore)
  false
rescue ArgumentError => ex
  ex.message.include?('unknown chore')
end
#=> true

## perform runs all chores on every instance and reports per-chore stats
record = make_record(status: 'mixed_case')
report = @job.perform('HousekeepingTryModel')
[
  report[:model],
  report[:scanned] >= 1,
  report[:chores].key?(:uppercase_status),
  report[:chores].key?(:always_noop),
  report[:chores][:always_noop][:modified],
]
#=> ['HousekeepingTryModel', true, true, true, 0]

## perform records modifications when chore returns truthy
target = make_record(status: 'lowercase')
report = @job.perform('HousekeepingTryModel')
[
  report[:chores][:uppercase_status][:modified] >= 1,
  HousekeepingTryModel.load(target.identifier).status,
]
#=> [true, 'LOWERCASE']

## perform respects limit option (caps records scanned)
report = @job.perform('HousekeepingTryModel', limit: 1)
report[:scanned]
#=> 1

## perform with explicit chore name only runs that chore
target = make_record(status: 'oneoff')
report = @job.perform('HousekeepingTryModel', :uppercase_status)
[
  report[:chores].keys,
  report[:chores][:uppercase_status][:modified] >= 1,
]
#=> [[:uppercase_status], true]

## perform counts errors per chore instead of crashing the run
class HousekeepingTryModel
  chore :always_raises do |_obj|
    raise StandardError, 'boom'
  end
end
make_record(status: 'errors')
report = @job.perform('HousekeepingTryModel', :always_raises)
report[:chores][:always_raises][:errors] >= 1
#=> true

# TEARDOWN

@created_records.each do |rec|
  rec.destroy! if rec.respond_to?(:destroy!)
rescue StandardError
  nil
end

@cleanup_objids.each do |objid|
  HousekeepingTryModel.instances.remove(objid)
rescue StandardError
  nil
end
