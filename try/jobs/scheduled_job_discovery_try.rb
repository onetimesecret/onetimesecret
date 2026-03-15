# try/jobs/scheduled_job_discovery_try.rb
#
# frozen_string_literal: true

# Tests the scheduler's job discovery logic to ensure abstract
# intermediate classes (like MaintenanceJob) are excluded and
# only concrete jobs that implement .schedule() are registered.
#
# Regression test for production crash: ObjectSpace.each_object(Class)
# picked up MaintenanceJob, which inherits ScheduledJob but does not
# implement .schedule(), causing a NotImplementedError at boot.

require_relative '../support/test_helpers'

OT.boot! :test, false

# Load the full job hierarchy exactly as the scheduler does
require_relative '../../lib/onetime/jobs/scheduled_job'
require_relative '../../lib/onetime/jobs/maintenance_job'

jobs_path = File.join(Onetime::HOME, 'lib', 'onetime', 'jobs', 'scheduled')
Dir.glob(File.join(jobs_path, '**', '*_job.rb')).each { |f| require f }

# Collect all subclasses of ScheduledJob (same query as load_scheduled_jobs)
@all_subclasses = ObjectSpace.each_object(Class).select do |klass|
  klass < Onetime::Jobs::ScheduledJob
end

# The singleton class where ScheduledJob defines `def self.schedule`
# is the owner for any class that inherits but does not override it.
@base_schedule_owner = Onetime::Jobs::ScheduledJob.singleton_class

# Known abstract classes that must NOT be scheduled
@abstract_classes = [
  Onetime::Jobs::MaintenanceJob,
]

# Helper: returns true if a class has its own .schedule implementation
def has_own_schedule?(klass)
  klass.method(:schedule).owner != @base_schedule_owner
end

# TRYOUTS

## MaintenanceJob is a subclass of ScheduledJob
Onetime::Jobs::MaintenanceJob < Onetime::Jobs::ScheduledJob
#=> true

## MaintenanceJob does not override .schedule (inherits NotImplementedError)
Onetime::Jobs::MaintenanceJob.method(:schedule).owner == @base_schedule_owner
#=> true

## Calling .schedule on MaintenanceJob raises NotImplementedError
begin
  Onetime::Jobs::MaintenanceJob.schedule(nil)
  false
rescue NotImplementedError => ex
  ex.message.include?('MaintenanceJob')
end
#=> true

## ScheduledJob.schedule also raises NotImplementedError
begin
  Onetime::Jobs::ScheduledJob.schedule(nil)
  false
rescue NotImplementedError => ex
  ex.message.include?('ScheduledJob')
end
#=> true

## ObjectSpace finds MaintenanceJob among ScheduledJob subclasses
@all_subclasses.include?(Onetime::Jobs::MaintenanceJob)
#=> true

## Unfiltered subclass list contains abstract classes (the bug)
@all_subclasses.any? { |k| k == Onetime::Jobs::MaintenanceJob }
#=> true

## Concrete HeartbeatJob defines its own .schedule
has_own_schedule?(Onetime::Jobs::Scheduled::HeartbeatJob)
#=> true

## Concrete PhantomCleanupJob defines its own .schedule
has_own_schedule?(Onetime::Jobs::Scheduled::Maintenance::PhantomCleanupJob)
#=> true

## All classes that inherit .schedule without overriding are known abstract classes
unimplemented = @all_subclasses.reject { |k| has_own_schedule?(k) }
(unimplemented - @abstract_classes).empty?
#=> true

## No concrete job inherits the base .schedule (would crash the scheduler)
bad_jobs = @all_subclasses
  .reject { |k| @abstract_classes.include?(k) }
  .reject { |k| has_own_schedule?(k) }
bad_jobs
#=> []

## Filtering with owner check excludes MaintenanceJob
filtered = @all_subclasses.select { |k| has_own_schedule?(k) }
filtered.include?(Onetime::Jobs::MaintenanceJob)
#=> false

## Filtering with owner check retains all concrete jobs
filtered = @all_subclasses.select { |k| has_own_schedule?(k) }
[
  Onetime::Jobs::Scheduled::Maintenance::PhantomCleanupJob,
  Onetime::Jobs::Scheduled::HeartbeatJob,
].all? { |klass| filtered.include?(klass) }
#=> true

## At least 5 concrete scheduled jobs are discovered
filtered = @all_subclasses.select { |k| has_own_schedule?(k) }
filtered.size >= 5
#=> true

## A hypothetical new abstract class would also be caught by the filter
stub_abstract = Class.new(Onetime::Jobs::ScheduledJob)
all_with_stub = @all_subclasses + [stub_abstract]
filtered = all_with_stub.select { |k| has_own_schedule?(k) }
filtered.include?(stub_abstract)
#=> false

## A hypothetical concrete subclass of MaintenanceJob passes the filter
stub_concrete = Class.new(Onetime::Jobs::MaintenanceJob) do
  def self.schedule(scheduler)
    # concrete implementation
  end
end
all_with_concrete = @all_subclasses + [stub_concrete]
filtered = all_with_concrete.select { |k| has_own_schedule?(k) }
filtered.include?(stub_concrete)
#=> true
