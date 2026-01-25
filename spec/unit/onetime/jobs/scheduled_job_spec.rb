# spec/unit/onetime/jobs/scheduled_job_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'rufus-scheduler'
require 'onetime/jobs/scheduled_job'

RSpec.describe Onetime::Jobs::ScheduledJob do
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
    let(:real_scheduler) { Rufus::Scheduler.new }
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
