# spec/unit/onetime/jobs/scheduled/plan_cache_refresh_job_spec.rb
#
# frozen_string_literal: true

# PlanCacheRefreshJob Test Suite
#
# Tests the scheduled job that refreshes Billing::Plan cache from Stripe API.
#
# Test Categories:
#
#   1. Scheduling (Unit)
#      - Verifies job schedules when enabled
#      - Verifies job skips scheduling when disabled
#
#   2. Skip Behavior (Unit)
#      - Skips when no Stripe API key configured
#
#   3. Success Path (Unit)
#      - Logs completion with plans_synced and duration
#
#   4. Error Dispatch (Unit)
#      - :stripe_api error_type raises Stripe::StripeError
#      - :validation error_type logs warning, no raise
#      - :internal/unknown error_type raises StandardError
#
#   5. Exception Handlers (Unit)
#      - Stripe::AuthenticationError handling
#      - Stripe::RateLimitError handling
#      - Stripe::APIConnectionError handling
#      - Stripe::StripeError handling
#      - StandardError handling
#
# Run with: bundle exec rspec spec/unit/onetime/jobs/scheduled/plan_cache_refresh_job_spec.rb

require 'billing/spec/support/billing_spec_helper'
require 'rufus-scheduler'
require 'onetime/jobs/scheduled/plan_cache_refresh_job'

# Guard: PlanCacheRefreshJob is only defined when billing is enabled (mocked by billing_spec_helper)
unless defined?(Onetime::Jobs::Scheduled::PlanCacheRefreshJob)
  RSpec.describe 'Onetime::Jobs::Scheduled::PlanCacheRefreshJob' do
    it 'is skipped because billing is disabled' do
      skip 'PlanCacheRefreshJob requires billing to be enabled (load billing_spec_helper first)'
    end
  end
  return # Exit early to avoid loading the full spec
end

RSpec.describe Onetime::Jobs::Scheduled::PlanCacheRefreshJob, type: :billing do
  let(:scheduler) { instance_double(Rufus::Scheduler) }
  let(:logger) { instance_double(SemanticLogger::Logger) }

  # Helper to create Result objects matching Pull::Result signature
  def make_result(success:, plans_synced: 0, errors: [], error_type: nil)
    Billing::Operations::Catalog::Pull::Result.new(
      success: success,
      plans_synced: plans_synced,
      errors: errors,
      error_type: error_type
    )
  end

  before do
    # Stub scheduler_logger on the class
    allow(described_class).to receive(:scheduler_logger).and_return(logger)
    allow(logger).to receive(:info)
    allow(logger).to receive(:debug)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:error)
  end

  describe '.schedule' do
    context 'when enabled' do
      before do
        allow(OT).to receive(:conf).and_return({
          'jobs' => {
            'plan_cache_refresh_enabled' => true
          }
        })
      end

      it 'registers an interval job with the scheduler' do
        expect(scheduler).to receive(:every).with('6h', first_in: '1m')
        described_class.schedule(scheduler)
      end

      it 'logs scheduling message' do
        allow(scheduler).to receive(:every)
        expect(logger).to receive(:info).with('[PlanCacheRefreshJob] Scheduling with interval: 6h')
        described_class.schedule(scheduler)
      end
    end

    context 'when disabled' do
      before do
        allow(OT).to receive(:conf).and_return({
          'jobs' => {
            'plan_cache_refresh_enabled' => false
          }
        })
      end

      it 'does not register any job' do
        expect(scheduler).not_to receive(:every)
        described_class.schedule(scheduler)
      end
    end

    context 'when config is missing' do
      before do
        allow(OT).to receive(:conf).and_return({})
      end

      it 'does not register any job' do
        expect(scheduler).not_to receive(:every)
        described_class.schedule(scheduler)
      end
    end
  end

  describe '.refresh_plan_cache (via send)' do
    describe 'skip behavior' do
      context 'when no Stripe API key configured' do
        before do
          allow(Onetime.billing_config).to receive(:stripe_key).and_return(nil)
        end

        it 'logs debug message and returns early' do
          expect(logger).to receive(:debug).with('[PlanCacheRefreshJob] Skipping: No Stripe API key configured')
          expect(Billing::Operations::Catalog::Pull).not_to receive(:call)

          described_class.send(:refresh_plan_cache)
        end
      end

      context 'when Stripe API key is empty string' do
        before do
          allow(Onetime.billing_config).to receive(:stripe_key).and_return('   ')
        end

        it 'logs debug message and returns early' do
          expect(logger).to receive(:debug).with('[PlanCacheRefreshJob] Skipping: No Stripe API key configured')
          expect(Billing::Operations::Catalog::Pull).not_to receive(:call)

          described_class.send(:refresh_plan_cache)
        end
      end
    end

    describe 'success path' do
      it 'logs start message' do
        result = make_result(success: true, plans_synced: 3)
        allow(Billing::Operations::Catalog::Pull).to receive(:call).and_return(result)

        expect(logger).to receive(:info).with('[PlanCacheRefreshJob] Starting plan cache refresh from Stripe')

        described_class.send(:refresh_plan_cache)
      end

      it 'calls Pull.call and logs completion with plans_synced' do
        result = make_result(success: true, plans_synced: 5)
        allow(Billing::Operations::Catalog::Pull).to receive(:call).and_return(result)

        expect(logger).to receive(:info).with(match(/Completed: 5 plans cached in \d+ms/))

        described_class.send(:refresh_plan_cache)
      end
    end

    describe 'error dispatch on result.error_type' do
      context 'when error_type is :stripe_api' do
        it 'raises Stripe::StripeError with the error message' do
          result = make_result(success: false, error_type: :stripe_api, errors: ['API rate limit exceeded'])
          allow(Billing::Operations::Catalog::Pull).to receive(:call).and_return(result)

          # The rescue block catches and logs Stripe::StripeError
          expect(logger).to receive(:error).with('[PlanCacheRefreshJob] Stripe API error: API rate limit exceeded')

          described_class.send(:refresh_plan_cache)
        end
      end

      context 'when error_type is :validation' do
        it 'logs warning and returns without raising' do
          result = make_result(success: false, error_type: :validation, errors: ['Invalid metadata format'])
          allow(Billing::Operations::Catalog::Pull).to receive(:call).and_return(result)

          expect(logger).to receive(:warn).with('[PlanCacheRefreshJob] Validation error: Invalid metadata format')
          # Should not raise or log error
          expect(logger).not_to receive(:error)

          described_class.send(:refresh_plan_cache)
        end
      end

      context 'when error_type is :internal' do
        it 'raises StandardError with the error message' do
          result = make_result(success: false, error_type: :internal, errors: ['Redis connection failed'])
          allow(Billing::Operations::Catalog::Pull).to receive(:call).and_return(result)

          # The rescue block catches StandardError
          expect(logger).to receive(:error).with('[PlanCacheRefreshJob] Unexpected error: StandardError - Redis connection failed')

          described_class.send(:refresh_plan_cache)
        end
      end

      context 'when error_type is unknown/nil' do
        it 'raises StandardError with default message when errors empty' do
          result = make_result(success: false, error_type: nil, errors: [])
          allow(Billing::Operations::Catalog::Pull).to receive(:call).and_return(result)

          expect(logger).to receive(:error).with('[PlanCacheRefreshJob] Unexpected error: StandardError - Unknown error')

          described_class.send(:refresh_plan_cache)
        end

        it 'raises StandardError with first error message' do
          result = make_result(success: false, error_type: :something_else, errors: ['Unexpected state'])
          allow(Billing::Operations::Catalog::Pull).to receive(:call).and_return(result)

          expect(logger).to receive(:error).with('[PlanCacheRefreshJob] Unexpected error: StandardError - Unexpected state')

          described_class.send(:refresh_plan_cache)
        end
      end
    end

    describe 'exception handlers' do
      before do
        # Let the info log through
        allow(logger).to receive(:info)
      end

      context 'Stripe::AuthenticationError' do
        it 'logs error message' do
          allow(Billing::Operations::Catalog::Pull).to receive(:call)
            .and_raise(Stripe::AuthenticationError.new('Invalid API key'))

          expect(logger).to receive(:error).with('[PlanCacheRefreshJob] Stripe authentication failed: Invalid API key')

          # Should not raise
          expect { described_class.send(:refresh_plan_cache) }.not_to raise_error
        end
      end

      context 'Stripe::RateLimitError' do
        it 'logs warn message' do
          allow(Billing::Operations::Catalog::Pull).to receive(:call)
            .and_raise(Stripe::RateLimitError.new('Too many requests'))

          expect(logger).to receive(:warn).with('[PlanCacheRefreshJob] Stripe rate limit hit, will retry next interval: Too many requests')

          expect { described_class.send(:refresh_plan_cache) }.not_to raise_error
        end
      end

      context 'Stripe::APIConnectionError' do
        it 'logs error message' do
          allow(Billing::Operations::Catalog::Pull).to receive(:call)
            .and_raise(Stripe::APIConnectionError.new('Network unreachable'))

          expect(logger).to receive(:error).with('[PlanCacheRefreshJob] Stripe API connection error: Network unreachable')

          expect { described_class.send(:refresh_plan_cache) }.not_to raise_error
        end
      end

      context 'Stripe::StripeError (generic)' do
        it 'logs error message' do
          allow(Billing::Operations::Catalog::Pull).to receive(:call)
            .and_raise(Stripe::StripeError.new('Something went wrong'))

          expect(logger).to receive(:error).with('[PlanCacheRefreshJob] Stripe API error: Something went wrong')

          expect { described_class.send(:refresh_plan_cache) }.not_to raise_error
        end
      end

      context 'StandardError' do
        it 'logs error message' do
          allow(Billing::Operations::Catalog::Pull).to receive(:call)
            .and_raise(StandardError.new('Unexpected failure'))

          expect(logger).to receive(:error).with('[PlanCacheRefreshJob] Unexpected error: StandardError - Unexpected failure')

          expect { described_class.send(:refresh_plan_cache) }.not_to raise_error
        end

        context 'when OT.debug? is true' do
          it 'logs backtrace' do
            allow(OT).to receive(:debug?).and_return(true)
            error = StandardError.new('Debug error')
            error.set_backtrace(['line1', 'line2', 'line3', 'line4', 'line5', 'line6'])

            allow(Billing::Operations::Catalog::Pull).to receive(:call).and_raise(error)

            expect(logger).to receive(:error).with('[PlanCacheRefreshJob] Unexpected error: StandardError - Debug error')
            expect(logger).to receive(:error).with("line1\nline2\nline3\nline4\nline5")

            described_class.send(:refresh_plan_cache)
          end
        end

        context 'when OT.debug? is false' do
          it 'does not log backtrace' do
            allow(OT).to receive(:debug?).and_return(false)

            allow(Billing::Operations::Catalog::Pull).to receive(:call)
              .and_raise(StandardError.new('Production error'))

            expect(logger).to receive(:error).with('[PlanCacheRefreshJob] Unexpected error: StandardError - Production error')
            expect(logger).to receive(:error).with(anything).at_most(:once)

            described_class.send(:refresh_plan_cache)
          end
        end
      end
    end
  end

  describe '.enabled?' do
    it 'returns true when config is true' do
      allow(OT).to receive(:conf).and_return({
        'jobs' => {
          'plan_cache_refresh_enabled' => true
        }
      })

      expect(described_class.send(:enabled?)).to be true
    end

    it 'returns false when config is false' do
      allow(OT).to receive(:conf).and_return({
        'jobs' => {
          'plan_cache_refresh_enabled' => false
        }
      })

      expect(described_class.send(:enabled?)).to be false
    end

    it 'returns false when config is missing' do
      allow(OT).to receive(:conf).and_return({})

      expect(described_class.send(:enabled?)).to be false
    end

    it 'returns false when config is not exactly true' do
      allow(OT).to receive(:conf).and_return({
        'jobs' => {
          'plan_cache_refresh_enabled' => 'yes'
        }
      })

      expect(described_class.send(:enabled?)).to be false
    end
  end
end
