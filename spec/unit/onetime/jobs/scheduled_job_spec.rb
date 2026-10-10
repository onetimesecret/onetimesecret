# spec/unit/onetime/jobs/scheduled_job_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'rufus-scheduler'
require 'onetime/jobs/scheduled_job'

RSpec.describe Onetime::Jobs::ScheduledJob do
  include_context 'with isolated job run records'

  let(:scheduler) { instance_double(Rufus::Scheduler) }

  describe '.schedule' do
    it 'raises NotImplementedError when not overridden' do
      expect { described_class.schedule(scheduler) }
        .to raise_error(NotImplementedError, /must implement .schedule/)
    end
  end

  describe '.cron' do
    let(:test_job_class) do
      Class.new(described_class) do
        def self.name
          'TestCronJob'
        end
      end
    end

    it 'registers a cron job with the scheduler' do
      expect(scheduler).to receive(:cron).with('0 * * * *')
      test_job_class.cron(scheduler, '0 * * * *') { 'work' }
    end

    it 'records the registration (#4343)' do
      allow(scheduler).to receive(:cron)
      expect(Onetime::Jobs::JobRun).to receive(:register)
        .with(test_job_class, kind: :cron, expression: '0 * * * *', next_time: nil)
      test_job_class.cron(scheduler, '0 * * * *') { 'work' }
    end
  end

  describe '.every' do
    let(:test_job_class) do
      Class.new(described_class) do
        def self.name
          'TestEveryJob'
        end
      end
    end

    it 'registers an interval job with the scheduler' do
      expect(scheduler).to receive(:every).with('1h')
      test_job_class.every(scheduler, '1h') { 'work' }
    end

    it 'passes options to the scheduler' do
      expect(scheduler).to receive(:every).with('30m', first_in: '5s')
      test_job_class.every(scheduler, '30m', first_in: '5s') { 'work' }
    end

    it 'passes overlap: false through (DomainRefreshJob relies on it)' do
      expect(scheduler).to receive(:every).with('30m', first_in: '2m', overlap: false)
      test_job_class.every(scheduler, '30m', first_in: '2m', overlap: false) { 'work' }
    end

    it 'records the registration with next_time: nil when the scheduler returns nothing (#4343)' do
      allow(scheduler).to receive(:every)
      expect(Onetime::Jobs::JobRun).to receive(:register)
        .with(test_job_class, kind: :every, expression: '1h', next_time: nil)
      test_job_class.every(scheduler, '1h') { 'work' }
    end

    it 'returns what the scheduler returned' do
      allow(scheduler).to receive(:every).and_return('every_123')
      allow(scheduler).to receive(:job).with('every_123').and_return(nil)
      expect(test_job_class.every(scheduler, '1h') { 'work' }).to eq('every_123')
    end
  end

  describe '.in_time' do
    let(:test_job_class) do
      Class.new(described_class) do
        def self.name
          'TestInJob'
        end
      end
    end

    it 'registers a delayed job with the scheduler' do
      expect(scheduler).to receive(:in).with('10s')
      test_job_class.in_time(scheduler, '10s') { 'work' }
    end
  end

  describe '.at_time' do
    let(:test_job_class) do
      Class.new(described_class) do
        def self.name
          'TestAtJob'
        end
      end
    end

    it 'registers a job at a specific time' do
      future_time = Time.now + 3600
      expect(scheduler).to receive(:at).with(future_time)
      test_job_class.at_time(scheduler, future_time) { 'work' }
    end
  end

  describe 'error handling' do
    # A short tick so shutdown does not wait out the default 0.3s sleep.
    let(:real_scheduler) { Rufus::Scheduler.new(frequency: 0.01) }
    let(:error_job_class) do
      Class.new(described_class) do
        def self.name
          'ErrorJob'
        end

        def self.schedule(scheduler)
          every(scheduler, '1s') do
            raise StandardError, 'Test error'
          end
        end
      end
    end

    after { real_scheduler.shutdown(:kill) }

    it 'catches and logs errors without crashing' do
      # Register the job
      error_job_class.schedule(real_scheduler)

      # Job should be registered
      expect(real_scheduler.jobs.size).to eq(1)

      # Scheduler should still be running after error
      expect(real_scheduler).not_to be_down
    end

    it 'records the failed run and keeps the scheduler up (#4343)' do
      error_job_class.schedule(real_scheduler)
      real_scheduler.jobs.first.call # runs the block in this thread, rescue on

      record = Onetime::Jobs::JobRun.read('error')
      expect(record).to include(
        'last_status' => 'error', 'last_error' => 'StandardError: Test error',
        'run_count' => 1, 'error_count' => 1
      )
      expect(real_scheduler).not_to be_down
    end
  end

  describe 'run records (#4343)' do
    # A short tick so shutdown does not wait out the default 0.3s sleep.
    let(:real_scheduler) { Rufus::Scheduler.new(frequency: 0.01) }
    let(:job_class) do
      Class.new(described_class) do
        def self.name = 'RecordedJob'
      end
    end

    after { real_scheduler.shutdown(:kill) }

    # Schedules `block` hourly with blocking: true, so a manual trigger runs
    # the work in this thread, and triggers it once.
    def run_once(&block)
      job_id = job_class.every(real_scheduler, '1h', blocking: true, &block)
      job    = real_scheduler.job(job_id)
      job.trigger(EtOrbi::EoTime.now)
      job
    end

    it 'records registration with the real next_time' do
      job_id = job_class.every(real_scheduler, '1h') { nil }

      record = Onetime::Jobs::JobRun.read('recorded')
      expect(record).to include('schedule_kind' => 'every', 'schedule_expression' => '1h', 'job_class' => 'RecordedJob')
      expect(record['next_time']).to eq(real_scheduler.job(job_id).next_time.to_i)
    end

    it 'records a successful run' do
      job = run_once { :done }

      record = Onetime::Jobs::JobRun.read('recorded')
      expect(record).to include('last_status' => 'success', 'run_count' => 1, 'last_error' => nil)
      expect(record['error_count']).to be_nil
      expect(record['last_duration_ms']).to be >= 0
      # The trigger computed the following occurrence before the work ran.
      expect(record['next_time']).to eq(job.next_time.to_i)
    end

    it 'records a report with :skipped as skipped' do
      run_once { { skipped: 'no_stripe_key' } }

      expect(Onetime::Jobs::JobRun.read('recorded')).to include('last_status' => 'skipped', 'last_error' => nil)
    end

    it 'records a report with :aborted as an error naming the reason' do
      run_once { { aborted: 'catalog_pull_failed' } }

      expect(Onetime::Jobs::JobRun.read('recorded')).to include(
        'last_status' => 'error', 'last_error' => 'aborted: catalog_pull_failed', 'error_count' => 1
      )
    end

    it 'never fails the job when the record cannot be written' do
      allow(Onetime::Jobs::JobRun).to receive(:dbclient).and_raise(Redis::CannotConnectError, 'down')
      ran = false

      expect { run_once { ran = true } }.not_to raise_error
      expect(ran).to be(true)
    end
  end

  describe 'subclass implementation' do
    let(:real_scheduler) { Rufus::Scheduler.new }

    after { real_scheduler.shutdown(:kill) }

    it 'allows subclasses to implement schedule method' do
      # Define a proper subclass
      job_class = Class.new(described_class) do
        def self.name
          'WorkingJob'
        end

        def self.schedule(scheduler)
          every(scheduler, '1h') do
            # Job work here
          end
        end
      end

      # Should not raise
      expect { job_class.schedule(real_scheduler) }.not_to raise_error

      # Should register one job
      expect(real_scheduler.jobs.size).to eq(1)
    end
  end
end
