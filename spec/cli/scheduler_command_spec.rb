# spec/cli/scheduler_command_spec.rb
#
# frozen_string_literal: true

# The scheduler daemon's boot path (#4343): it discovers jobs through
# Onetime::Jobs::Registry, records its own boot for the jobs catalog, and runs
# a liveness heartbeat that is not itself a catalogued job.
#
# `call` blocks on `scheduler.join` and traps INT/TERM, so these drive the
# private steps against a real Rufus::Scheduler and stub the blocking edges.
#
# Run: tests/lanes/run --only spec/cli/scheduler_command_spec.rb

require_relative 'cli_spec_helper'

RSpec.describe Onetime::CLI::SchedulerCommand, type: :cli do
  let(:command) { described_class.new }
  # A short tick so shutdown does not wait out the default 0.3s sleep.
  let(:scheduler) { Rufus::Scheduler.new(frequency: 0.01) }

  after { scheduler.shutdown(:kill) }

  describe '#load_scheduled_jobs' do
    it 'schedules every concrete class the registry discovers, and nothing else' do
      Onetime::Jobs::Registry.load_all!
      classes = Onetime::Jobs::Registry.concrete_classes
      classes.each { |klass| allow(klass).to receive(:schedule) }

      command.send(:load_scheduled_jobs, scheduler)

      expect(classes).to all(have_received(:schedule).with(scheduler).once)
      expect(classes).not_to include(Onetime::Jobs::MaintenanceJob)
    end
  end

  describe '#start_heartbeat' do
    it 'adds one raw rufus job that refreshes the scheduler heartbeat' do
      allow(Onetime::Jobs::JobRun).to receive(:scheduler_heartbeat!)

      command.send(:start_heartbeat, scheduler)

      job = scheduler.jobs.first
      expect(scheduler.jobs.size).to eq(1)
      expect(job.original).to eq("#{Onetime::Jobs::JobRun::HEARTBEAT_INTERVAL}s")
      expect(job.opts).to include(overlap: false)

      job.call
      expect(Onetime::Jobs::JobRun).to have_received(:scheduler_heartbeat!)
    end
  end

  describe '#call' do
    let(:boot_time) { 1_800_000_000 }

    before do
      mock_ot_boot
      allow(Rufus::Scheduler).to receive(:new).and_return(scheduler)
      allow(scheduler).to receive(:join)
      allow(command).to receive(:setup_signal_handlers)
      allow(command).to receive(:log_scheduled_jobs)
      allow(Onetime::Jobs::JobRun).to receive(:scheduler_started!)
      allow(Familia).to receive(:now).and_return(boot_time)
      # Registration takes time; jobs registered by this boot must still sort
      # at or after started_at.
      allow(command).to receive(:load_scheduled_jobs) do |sched|
        allow(Familia).to receive(:now).and_return(boot_time + 5)
        sched.every('1h') { nil }
      end
    end

    around do |example|
      original_mode = OT.execution_mode
      example.run
    ensure
      OT.execution_mode = original_mode
    end

    it 'records the boot with started_at taken before jobs register, counting only jobs' do
      command.call

      expect(Onetime::Jobs::JobRun).to have_received(:scheduler_started!)
        .with(job_count: 1, started_at: boot_time)
      # The heartbeat is added after the count.
      expect(scheduler.jobs.size).to eq(2)
    end
  end
end
