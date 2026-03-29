# spec/unit/onetime/application/auth_strategies/dev_worker_identity_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/application/auth_strategies/dev_worker_identity'

RSpec.describe Onetime::Application::AuthStrategies::DevWorkerIdentity do
  subject(:identity) { described_class }

  # Store original env values for restoration
  let(:env_vars) { %w[DEV_WORKER_ID GITHUB_JOB TEST_ENV_NUMBER CIRCLE_NODE_INDEX] }
  let(:original_env) { env_vars.to_h { |k| [k, ENV[k]] } }

  before do
    # Clear all worker ID env vars before each test
    env_vars.each { |k| ENV.delete(k) }
    # Reset the cached process suffix
    identity.instance_variable_set(:@process_suffix, nil)
  end

  after do
    # Restore original env values
    original_env.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
    # Reset the cached process suffix
    identity.instance_variable_set(:@process_suffix, nil)
  end

  describe '.namespaced_username' do
    context 'with DEV_WORKER_ID set' do
      before { ENV['DEV_WORKER_ID'] = 'simple' }

      it 'returns username with deterministic suffix' do
        result = identity.namespaced_username('alice')
        expect(result).to match(/^alice_w[a-f0-9]{4}$/)
      end

      it 'produces same output for same input' do
        result1 = identity.namespaced_username('alice')
        result2 = identity.namespaced_username('alice')
        expect(result1).to eq(result2)
      end

      it 'produces different output for different usernames' do
        result1 = identity.namespaced_username('alice')
        result2 = identity.namespaced_username('bob')
        expect(result1).not_to eq(result2)
      end
    end

    context 'with GITHUB_JOB set' do
      before { ENV['GITHUB_JOB'] = 'ruby-integration-full-postgres' }

      it 'returns username with deterministic suffix' do
        result = identity.namespaced_username('alice')
        expect(result).to match(/^alice_w[a-f0-9]{4}$/)
      end

      it 'produces different suffix than other job names' do
        ENV['GITHUB_JOB'] = 'ruby-integration-simple'
        simple_suffix = identity.namespaced_username('alice')

        ENV['GITHUB_JOB'] = 'ruby-integration-full-postgres'
        postgres_suffix = identity.namespaced_username('alice')

        expect(simple_suffix).not_to eq(postgres_suffix)
      end
    end

    context 'with TEST_ENV_NUMBER set' do
      before { ENV['TEST_ENV_NUMBER'] = '2' }

      it 'returns username with deterministic suffix' do
        result = identity.namespaced_username('alice')
        expect(result).to match(/^alice_w[a-f0-9]{4}$/)
      end
    end

    context 'with CIRCLE_NODE_INDEX set' do
      before { ENV['CIRCLE_NODE_INDEX'] = '3' }

      it 'returns username with deterministic suffix' do
        result = identity.namespaced_username('alice')
        expect(result).to match(/^alice_w[a-f0-9]{4}$/)
      end
    end

    context 'with no env vars set (fallback)' do
      it 'returns username with process-unique suffix' do
        result = identity.namespaced_username('alice')
        expect(result).to match(/^alice_w\d+_\d+$/)
      end

      it 'uses cached suffix within same process' do
        result1 = identity.namespaced_username('alice')
        result2 = identity.namespaced_username('bob')

        # Both should have the same suffix (after username_)
        suffix1 = result1.sub('alice_', '')
        suffix2 = result2.sub('bob_', '')
        expect(suffix1).to eq(suffix2)
      end
    end

    context 'priority order' do
      it 'prefers DEV_WORKER_ID over GITHUB_JOB' do
        ENV['DEV_WORKER_ID'] = 'explicit'
        ENV['GITHUB_JOB'] = 'job-name'

        result_with_both = identity.namespaced_username('alice')

        ENV.delete('GITHUB_JOB')
        result_with_explicit = identity.namespaced_username('alice')

        expect(result_with_both).to eq(result_with_explicit)
      end

      it 'prefers GITHUB_JOB over TEST_ENV_NUMBER' do
        ENV['GITHUB_JOB'] = 'my-job'
        ENV['TEST_ENV_NUMBER'] = '5'

        result_with_both = identity.namespaced_username('alice')

        ENV.delete('TEST_ENV_NUMBER')
        result_with_job = identity.namespaced_username('alice')

        expect(result_with_both).to eq(result_with_job)
      end
    end
  end

  describe '.detect_worker_id' do
    context 'with no env vars' do
      it 'returns nil' do
        expect(identity.detect_worker_id).to be_nil
      end
    end

    context 'with DEV_WORKER_ID' do
      before { ENV['DEV_WORKER_ID'] = 'test-worker' }

      it 'returns the worker ID' do
        expect(identity.detect_worker_id).to eq('test-worker')
      end
    end

    context 'with GITHUB_JOB' do
      before { ENV['GITHUB_JOB'] = 'ruby-unit' }

      it 'returns the job name' do
        expect(identity.detect_worker_id).to eq('ruby-unit')
      end
    end
  end

  describe '.parallel_ci?' do
    context 'with no env vars' do
      it 'returns false' do
        expect(identity.parallel_ci?).to be false
      end
    end

    context 'with GITHUB_JOB set' do
      before { ENV['GITHUB_JOB'] = 'test' }

      it 'returns true' do
        expect(identity.parallel_ci?).to be true
      end
    end
  end

  describe '.worker_id_for_logging' do
    context 'with no env vars' do
      it 'returns "local"' do
        expect(identity.worker_id_for_logging).to eq('local')
      end
    end

    context 'with GITHUB_JOB set' do
      before { ENV['GITHUB_JOB'] = 'ruby-integration-simple' }

      it 'returns the job name' do
        expect(identity.worker_id_for_logging).to eq('ruby-integration-simple')
      end
    end
  end

  describe 'collision resistance' do
    it 'different GITHUB_JOB values produce different namespaces' do
      # Simulate parallel CI jobs
      jobs = %w[
        ruby-integration-simple
        ruby-integration-full-sqlite
        ruby-integration-full-postgres
        ruby-integration-disabled
      ]

      namespaces = jobs.map do |job|
        ENV['GITHUB_JOB'] = job
        identity.namespaced_username('dev_alice')
      end

      # All namespaces should be unique
      expect(namespaces.uniq.size).to eq(jobs.size)
    end
  end
end
