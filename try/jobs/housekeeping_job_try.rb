# try/jobs/housekeeping_job_try.rb
#
# frozen_string_literal: true

# Tests the HousekeepingJob class — its scheduling guard, model discovery,
# and per-instance chore execution.
#
# Uses a duck-typed stub class instead of a real Familia::Horreum so the
# tests don't depend on the upstream `feature :housekeeping` being shipped
# in the locked gem version. HousekeepingJob only cares about the shape of
# the model interface (.chores, .instances, .load_multi, #do_chore!, #identifier).
#
# IMPLEMENTATION NOTE: Tryouts evaluates test bodies via
# `container.instance_eval(string)`. A top-level `class HousekeepingStubModel`
# in this file is therefore NOT registered on `Object`, so `resolve_model`
# (which uses `Object.const_get`) can't find it from inside a test body.
# Tests pass the class object directly to `perform`, which accepts either a
# String or a Class. The `resolve_model` test uses a real Ruby stdlib
# constant instead.

require_relative '../support/test_helpers'
require 'securerandom'

OT.boot! :test, false

require_relative '../../lib/onetime/jobs/scheduled/housekeeping_job'

# Minimal stand-in that mirrors the surface HousekeepingJob touches.
class HousekeepingStubModel
  attr_accessor :status
  attr_reader :identifier

  def initialize(status:)
    @status     = status
    @identifier = SecureRandom.hex(8)
  end

  def do_chore!(name)
    block = HousekeepingStubModel.chores[name.to_sym]
    block&.call(self)
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
    StubInstances.new(records)
  end

  # Wrapper that mimics Familia's instances interface with each_record support
  class StubInstances
    def initialize(records)
      @records = records
    end

    def to_a
      @records.map(&:identifier)
    end

    def each_record(batch_size: 100, &block)
      @records.each(&block)
    end
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

@job  = Onetime::Jobs::Scheduled::HousekeepingJob
@stub = HousekeepingStubModel

def call_private(method, *args, &block)
  @job.send(method, *args, &block)
end

@stub.reset!
@stub.chore(:uppercase_status) do |obj|
  next unless obj.status && obj.status != obj.status.upcase

  obj.status = obj.status.upcase
  true
end
@stub.chore(:always_noop) { |_obj| nil }

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

## resolve_model resolves a top-level stdlib constant
call_private(:resolve_model, 'String').name
#=> 'String'

## resolve_model raises NameError for unknown classes
begin
  call_private(:resolve_model, 'No::Such::Class')
  false
rescue NameError
  true
end
#=> true

## models_with_chores does NOT pick up the stub (it's outside INSTANCE_MODELS)
@job.models_with_chores.none? { |k| k.name == 'HousekeepingStubModel' }
#=> true

## perform raises ArgumentError for models without the housekeeping shape
begin
  @job.perform(Onetime::Feedback)
  false
rescue ArgumentError => ex
  ex.message.include?('feature :housekeeping')
end
#=> true

## perform raises ArgumentError for unknown chore name
@stub.add(status: 'active')
begin
  @job.perform(@stub, :no_such_chore)
  false
rescue ArgumentError => ex
  ex.message.include?('unknown chore')
end
#=> true

## perform runs all chores on every instance and reports per-chore stats
@stub.reset!
@stub.chore(:uppercase_status) do |obj|
  next unless obj.status && obj.status != obj.status.upcase

  obj.status = obj.status.upcase
  true
end
@stub.chore(:always_noop) { |_obj| nil }
@stub.add(status: 'mixed_case')
report = @job.perform(@stub)
# `report[:model]` is `klass.name`. When the stub class is defined at the
# top of a tryouts file, instance_eval binds it to the container's
# singleton class, giving it a name like
# "#<Class:0x...>::HousekeepingStubModel". Match on suffix.
[
  report[:model].end_with?('HousekeepingStubModel'),
  report[:scanned],
  report[:chores].key?(:uppercase_status),
  report[:chores].key?(:always_noop),
  report[:chores][:always_noop][:modified],
]
#=> [true, 1, true, true, 0]

## perform records modifications when chore returns truthy
@stub.reset!
@stub.chore(:uppercase_status) do |obj|
  next unless obj.status && obj.status != obj.status.upcase

  obj.status = obj.status.upcase
  true
end
target = @stub.add(status: 'lowercase')
report = @job.perform(@stub)
[
  report[:chores][:uppercase_status][:modified],
  target.status,
]
#=> [1, 'LOWERCASE']

## perform respects the limit option (caps records scanned)
@stub.reset!
@stub.chore(:noop) { |_| nil }
3.times { |i| @stub.add(status: "s#{i}") }
report = @job.perform(@stub, limit: 1)
report[:scanned]
#=> 1

## perform with an explicit chore name only runs that chore
@stub.reset!
@stub.chore(:keep)  { |_| true }
@stub.chore(:other) { |_| true }
@stub.add(status: 'oneoff')
report = @job.perform(@stub, :keep)
report[:chores].keys
#=> [:keep]

## perform counts errors per chore instead of crashing the run
@stub.reset!
@stub.chore(:always_raises) { |_| raise StandardError, 'boom' }
@stub.add(status: 'errors')
report = @job.perform(@stub, :always_raises)
report[:chores][:always_raises][:errors]
#=> 1

# TEARDOWN

@stub.reset!
