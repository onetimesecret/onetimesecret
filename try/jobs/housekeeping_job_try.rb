# try/jobs/housekeeping_job_try.rb
#
# frozen_string_literal: true

# Tests the HousekeepingJob class — its scheduling guard, model discovery,
# and per-instance chore execution.
#
# Uses a duck-typed stub class instead of a real Familia::Horreum so the
# tests don't depend on the upstream `feature :housekeeping` being shipped
# in the locked gem version. HousekeepingJob only cares about the shape of
# the model interface (.chores, .instances, .load_multi, #tidy!, #identifier).

require_relative '../support/test_helpers'
require 'securerandom'

OT.boot! :test, false

require_relative '../../lib/onetime/jobs/scheduled/housekeeping_job'

# Minimal stand-in that mirrors the surface HousekeepingJob touches.
# Top-level, outside the Onetime namespace, so the default model-name
# fallback (MaintenanceJob::INSTANCE_MODELS) never picks it up.
# Avoids `class << self` and `Struct.new do ... end` patterns because
# tryouts' Prism-based parser doesn't reliably register the constant on
# Object when those forms appear at the file's top level.
class HousekeepingStubModel
  attr_accessor :status
  attr_reader :identifier

  def initialize(status:)
    @status     = status
    @identifier = SecureRandom.hex(8)
  end

  def tidy!(name = nil)
    chores = HousekeepingStubModel.chores
    keys   = name ? [name.to_sym] : chores.keys
    keys.to_h { |k| [k, chores[k].call(self)] }
  end

  def self.reset!
    @chores  = {}
    @records = []
  end

  def self.chores
    @chores ||= {}
  end

  def self.chore(name, &block)
    chores[name.to_sym] = block
  end

  def self.instances
    records.map(&:identifier)
  end

  def self.load_multi(objids)
    objids.map { |id| records.find { |r| r.identifier == id } }
  end

  def self.add(status:)
    record = new(status: status)
    records << record
    record
  end

  def self.records
    @records ||= []
  end
end

@job = Onetime::Jobs::Scheduled::HousekeepingJob

def call_private(method, *args, &block)
  @job.send(method, *args, &block)
end

HousekeepingStubModel.reset!
HousekeepingStubModel.chore(:uppercase_status) do |obj|
  next unless obj.status && obj.status != obj.status.upcase

  obj.status = obj.status.upcase
  true
end
HousekeepingStubModel.chore(:always_noop) { |_obj| nil }

# TRYOUTS

## HousekeepingJob inherits from MaintenanceJob
@job < Onetime::Jobs::MaintenanceJob
#=> true

## HousekeepingJob is ultimately a ScheduledJob
@job < Onetime::Jobs::ScheduledJob
#=> true

## JOB_KEY is 'housekeeping'
@job::JOB_KEY
#=> 'housekeeping'

## DEFAULT_BATCH_SIZE is a positive integer
@job::DEFAULT_BATCH_SIZE.positive?
#=> true

## job_enabled? returns false when maintenance.housekeeping is not enabled
call_private(:job_enabled?, @job::JOB_KEY)
#=> false

## job_cron returns the inherited default when unconfigured
call_private(:job_cron, @job::JOB_KEY)
#=> '0 4 * * *'

## resolve_model resolves a nested namespace
call_private(:resolve_model, 'Onetime::Customer').name
#=> 'Onetime::Customer'

## resolve_model raises NameError for unknown classes
begin
  call_private(:resolve_model, 'No::Such::Class')
  false
rescue NameError
  true
end
#=> true

## resolve_model resolves a top-level constant
call_private(:resolve_model, 'HousekeepingStubModel').name
#=> 'HousekeepingStubModel'

## models_with_chores does NOT pick up the stub (it's outside INSTANCE_MODELS)
@job.models_with_chores.none? { |k| k.name == 'HousekeepingStubModel' }
#=> true

## perform raises ArgumentError for models without the housekeeping shape
begin
  @job.perform('Onetime::Customer')
  false
rescue ArgumentError => ex
  ex.message.include?('feature :housekeeping')
end
#=> true

## perform raises ArgumentError for unknown chore name
HousekeepingStubModel.add(status: 'active')
begin
  @job.perform('HousekeepingStubModel', :no_such_chore)
  false
rescue ArgumentError => ex
  ex.message.include?('unknown chore')
end
#=> true

## perform runs all chores on every instance and reports per-chore stats
HousekeepingStubModel.reset!
HousekeepingStubModel.chore(:uppercase_status) do |obj|
  next unless obj.status && obj.status != obj.status.upcase

  obj.status = obj.status.upcase
  true
end
HousekeepingStubModel.chore(:always_noop) { |_obj| nil }
HousekeepingStubModel.add(status: 'mixed_case')
report = @job.perform('HousekeepingStubModel')
[
  report[:model],
  report[:scanned],
  report[:chores].key?(:uppercase_status),
  report[:chores].key?(:always_noop),
  report[:chores][:always_noop][:modified],
]
#=> ['HousekeepingStubModel', 1, true, true, 0]

## perform records modifications when chore returns truthy
HousekeepingStubModel.reset!
HousekeepingStubModel.chore(:uppercase_status) do |obj|
  next unless obj.status && obj.status != obj.status.upcase

  obj.status = obj.status.upcase
  true
end
target = HousekeepingStubModel.add(status: 'lowercase')
report = @job.perform('HousekeepingStubModel')
[
  report[:chores][:uppercase_status][:modified],
  target.status,
]
#=> [1, 'LOWERCASE']

## perform respects the limit option (caps records scanned)
HousekeepingStubModel.reset!
HousekeepingStubModel.chore(:noop) { |_| nil }
3.times { |i| HousekeepingStubModel.add(status: "s#{i}") }
report = @job.perform('HousekeepingStubModel', limit: 1)
report[:scanned]
#=> 1

## perform with an explicit chore name only runs that chore
HousekeepingStubModel.reset!
HousekeepingStubModel.chore(:keep)  { |_| true }
HousekeepingStubModel.chore(:other) { |_| true }
HousekeepingStubModel.add(status: 'oneoff')
report = @job.perform('HousekeepingStubModel', :keep)
report[:chores].keys
#=> [:keep]

## perform counts errors per chore instead of crashing the run
HousekeepingStubModel.reset!
HousekeepingStubModel.chore(:always_raises) { |_| raise StandardError, 'boom' }
HousekeepingStubModel.add(status: 'errors')
report = @job.perform('HousekeepingStubModel', :always_raises)
report[:chores][:always_raises][:errors]
#=> 1

# TEARDOWN

HousekeepingStubModel.reset!
