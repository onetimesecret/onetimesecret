# spec/unit/onetime/application/auth_strategies/dev_basic_auth_strategy_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/application/auth_strategies/dev_basic_auth_strategy'

RSpec.describe Onetime::Application::AuthStrategies::DevBasicAuthStrategy do
  subject(:strategy) { described_class.new }

  let(:identity) { Onetime::Application::AuthStrategies::DevWorkerIdentity }
  let(:env_vars) { %w[DEV_WORKER_ID GITHUB_JOB TEST_ENV_NUMBER CIRCLE_NODE_INDEX] }
  let(:original_env) { env_vars.to_h { |k| [k, ENV[k]] } }

  before do
    # Clear all worker ID env vars before each test
    env_vars.each { |k| ENV.delete(k) }
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
    identity.instance_variable_set(:@process_suffix, nil)
  end

  describe '#namespace_dev_username' do
    context 'with GITHUB_JOB set' do
      before { ENV['GITHUB_JOB'] = 'ruby-integration-simple' }

      it 'preserves dev_ prefix and adds namespace' do
        result = strategy.send(:namespace_dev_username, 'dev_alice')
        expect(result).to start_with('dev_alice_w')
        expect(result).to match(/^dev_alice_w[a-f0-9]{4}$/)
      end

      it 'handles username without dev_ prefix gracefully' do
        # The method assumes input has dev_ prefix but handles missing prefix
        result = strategy.send(:namespace_dev_username, 'alice')
        # Without prefix, it would produce dev_alice_w... after re-adding
        expect(result).to start_with('dev_')
      end
    end

    context 'collision resistance across jobs' do
      it 'produces different namespaces for different GITHUB_JOB values' do
        ENV['GITHUB_JOB'] = 'ruby-integration-simple'
        simple_namespace = strategy.send(:namespace_dev_username, 'dev_alice')

        ENV['GITHUB_JOB'] = 'ruby-integration-full-postgres'
        postgres_namespace = strategy.send(:namespace_dev_username, 'dev_alice')

        expect(simple_namespace).not_to eq(postgres_namespace)
      end

      it 'produces same namespace for same GITHUB_JOB value' do
        ENV['GITHUB_JOB'] = 'ruby-integration-simple'
        first_call = strategy.send(:namespace_dev_username, 'dev_alice')
        second_call = strategy.send(:namespace_dev_username, 'dev_alice')

        expect(first_call).to eq(second_call)
      end
    end

    context 'with DEV_WORKER_ID override' do
      it 'allows explicit worker ID for testing' do
        ENV['DEV_WORKER_ID'] = 'test-worker-1'
        result1 = strategy.send(:namespace_dev_username, 'dev_alice')

        ENV['DEV_WORKER_ID'] = 'test-worker-2'
        result2 = strategy.send(:namespace_dev_username, 'dev_alice')

        expect(result1).not_to eq(result2)
      end
    end
  end

  describe 'parallel CI scenario simulation' do
    # Simulates what happens when multiple CI jobs run against same Redis
    it 'generates unique email addresses per job' do
      jobs = %w[
        ruby-integration-simple
        ruby-integration-full-sqlite
        ruby-integration-full-postgres
        ruby-integration-disabled
      ]

      emails = jobs.map do |job|
        ENV['GITHUB_JOB'] = job
        namespace = strategy.send(:namespace_dev_username, 'dev_alice')
        "#{namespace}@dev.local"
      end

      # All emails should be unique
      expect(emails.uniq.size).to eq(jobs.size)

      # All should match the expected pattern
      emails.each do |email|
        expect(email).to match(/^dev_alice_w[a-f0-9]{4}@dev\.local$/)
      end
    end
  end
end
