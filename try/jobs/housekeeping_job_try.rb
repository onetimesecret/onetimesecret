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

## perform stops between records when the budget runs out (#4343)
@stub.reset!
@stub.chore(:touch) { |_| true }
4.times { |i| @stub.add(status: "b#{i}") }
# Answers false for the first two checks, then true.
budget = Class.new do
  def initialize = @checks = 0
  def exhausted? = (@checks += 1) > 2
end.new
report = @job.perform(@stub, :touch, budget: budget)
[report[:scanned], report[:budget_exhausted], report[:chores][:touch][:modified]]
#=> [2, true, 2]

## perform reports budget_exhausted false when the budget lasts
@stub.reset!
@stub.chore(:touch) { |_| true }
2.times { |i| @stub.add(status: "c#{i}") }
roomy = Class.new { def exhausted? = false }.new
report = @job.perform(@stub, :touch, budget: roomy)
[report[:scanned], report[:budget_exhausted]]
#=> [2, false]

## perform checks the limit before the budget: a capped run is not budget_exhausted
@stub.reset!
@stub.chore(:touch) { |_| true }
3.times { |i| @stub.add(status: "d#{i}") }
roomy = Class.new { def exhausted? = false }.new
report = @job.perform(@stub, :touch, limit: 1, budget: roomy)
[report[:scanned], report[:budget_exhausted]]
#=> [1, false]

## perform without a budget leaves the stats shape unchanged (no budget key)
@stub.reset!
@stub.chore(:touch) { |_| true }
@stub.add(status: 'e')
@job.perform(@stub, :touch).keys
#=> [:model, :scanned, :chores]

## perform reports truncated when a record follows the limit-th one (#4343)
@stub.reset!
@stub.chore(:touch) { |_| true }
4.times { |i| @stub.add(status: "f#{i}") }
report = @job.perform(@stub, :touch, limit: 3)
[report[:scanned], report[:truncated], report[:chores][:touch][:modified]]
#=> [3, true, 3]

## perform reports truncated false when the population is exactly the limit
@stub.reset!
@stub.chore(:touch) { |_| true }
3.times { |i| @stub.add(status: "g#{i}") }
report = @job.perform(@stub, :touch, limit: 3)
[report[:scanned], report[:truncated]]
#=> [3, false]

## perform with a limit but no budget adds only the truncated key
@stub.reset!
@stub.chore(:touch) { |_| true }
@stub.add(status: 'h')
@job.perform(@stub, :touch, limit: 5).keys
#=> [:model, :scanned, :chores, :truncated]

## run_outcome maps a nightly report with chore errors to 'partial' (#4343)
# The nightly report nests one perform stats hash per model under :models;
# errors are summed across models and chores, naming the first failing chore.
report = {
  models: {
    'Onetime::Organization' => {
      model: 'Onetime::Organization', scanned: 10,
      chores: { standardize_planid: { modified: 7, errors: 2 }, other: { modified: 0, errors: 1 } },
    },
    'Onetime::Customer' => { model: 'Onetime::Customer', scanned: 4, chores: { tidy: { modified: 4, errors: 0 } } },
  },
}
@job.send(:run_outcome, report)
#=> ['partial', '3 record(s) failed (first chore: standardize_planid)']

## run_outcome counts a model whose whole scan raised as a failure too
report = {
  models: {
    'Onetime::Organization' => { model: 'Onetime::Organization', scanned: 2, chores: { tidy: { modified: 2, errors: 0 } } },
    'Onetime::Customer' => { error: 'boom' },
  },
}
@job.send(:run_outcome, report)
#=> ['partial', '1 model(s) failed: Onetime::Customer: boom']

## run_outcome is success when no chore and no model failed
report = {
  models: {
    'Onetime::Organization' => { model: 'Onetime::Organization', scanned: 2, chores: { tidy: { modified: 2, errors: 0 } } },
  },
}
@job.send(:run_outcome, report)
#=> ['success', nil]

## run_outcome is success for a nightly run with no models to scan
@job.send(:run_outcome, { models: {} })
#=> ['success', nil]

# TEARDOWN

@stub.reset!
