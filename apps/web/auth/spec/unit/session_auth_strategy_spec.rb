# apps/web/auth/spec/unit/session_auth_strategy_spec.rb
#
# frozen_string_literal: true

# Unit tests for SessionAuthStrategy — requires authenticated Rack session.
#
# Requires Valkey on port 2121 (pnpm run test:database:start).
#
# Run:
#   pnpm run test:rspec apps/web/auth/spec/unit/session_auth_strategy_spec.rb

require_relative '../spec_helper'
require_relative '../support/strategy_test_context'
require_relative '../support/shared_examples/session_contract_examples'

RSpec.describe Onetime::Application::AuthStrategies::SessionAuthStrategy, type: :integration do
  include_context 'strategy test'

  describe '#authenticate' do
    # -----------------------------------------------------------------
    # Valid authenticated session
    # -----------------------------------------------------------------
    context 'with valid authenticated session' do
      let(:result) { session_auth_strategy.authenticate(env_session_authenticated, nil) }

      it 'returns a StrategyResult' do
        expect(result).to be_a(Otto::Security::Authentication::StrategyResult)
      end

      it 'is authenticated' do
        expect(result.authenticated?).to be true
      end

      it 'sets user to the matching Customer' do
        expect(result.user).to be_a(Onetime::Customer)
        expect(result.user.custid).to eq(test_customer.custid)
      end

      it 'sets auth_method to SessionAuthStrategy' do
        # @auth_method_name is a class instance variable, not an instance variable,
        # so the attr_reader returns nil and Otto's success() falls back to
        # self.class.name.split('::').last => "SessionAuthStrategy"
        expect(result.auth_method).to eq('SessionAuthStrategy')
      end

      # Session contract — session must not be nil, must support bracket access
      include_examples 'a valid session contract'

      it 'session is the env rack.session (same object reference)' do
        expect(result.session).to be(env_session_authenticated['rack.session'])
      end
    end

    # -----------------------------------------------------------------
    # Missing session (no rack.session key)
    # -----------------------------------------------------------------
    context 'with missing session (no rack.session key)' do
      let(:env_no_session) do
        {
          'REMOTE_ADDR' => '127.0.0.1',
          'HTTP_USER_AGENT' => 'Test/1.0',
        }
      end

      let(:result) { session_auth_strategy.authenticate(env_no_session, nil) }

      it 'returns an AuthFailure' do
        expect(result).to be_a(Otto::Security::Authentication::AuthFailure)
      end
    end

    # -----------------------------------------------------------------
    # Missing session (rack.session is empty hash — no authenticated flag)
    # -----------------------------------------------------------------
    context 'with empty session hash' do
      let(:result) { session_auth_strategy.authenticate(env_anonymous, nil) }

      it 'returns an AuthFailure' do
        expect(result).to be_a(Otto::Security::Authentication::AuthFailure)
      end
    end

    # -----------------------------------------------------------------
    # Unauthenticated session (session exists but authenticated is not true)
    # -----------------------------------------------------------------
    context 'with unauthenticated session' do
      let(:env_unauthenticated_session) do
        {
          'rack.session' => {
            'authenticated' => false,
            'external_id' => test_customer.extid,
            'email' => test_customer.email,
          },
          'REMOTE_ADDR' => '127.0.0.1',
          'HTTP_USER_AGENT' => 'Test/1.0',
        }
      end

      let(:result) { session_auth_strategy.authenticate(env_unauthenticated_session, nil) }

      it 'returns an AuthFailure' do
        expect(result).to be_a(Otto::Security::Authentication::AuthFailure)
      end
    end

    # -----------------------------------------------------------------
    # Session without external_id
    # -----------------------------------------------------------------
    context 'with session missing external_id' do
      let(:env_no_external_id) do
        {
          'rack.session' => {
            'authenticated' => true,
          },
          'REMOTE_ADDR' => '127.0.0.1',
          'HTTP_USER_AGENT' => 'Test/1.0',
        }
      end

      let(:result) { session_auth_strategy.authenticate(env_no_external_id, nil) }

      it 'returns an AuthFailure' do
        expect(result).to be_a(Otto::Security::Authentication::AuthFailure)
      end
    end

    # -----------------------------------------------------------------
    # Nonexistent customer (external_id doesn't match any Customer)
    # -----------------------------------------------------------------
    context 'with nonexistent customer' do
      let(:env_nonexistent_customer) do
        {
          'rack.session' => {
            'authenticated' => true,
            'external_id' => "nonexistent_#{SecureRandom.uuid}",
            'email' => 'nobody@example.com',
          },
          'REMOTE_ADDR' => '127.0.0.1',
          'HTTP_USER_AGENT' => 'Test/1.0',
        }
      end

      let(:result) { session_auth_strategy.authenticate(env_nonexistent_customer, nil) }

      it 'returns an AuthFailure' do
        expect(result).to be_a(Otto::Security::Authentication::AuthFailure)
      end
    end

    # -----------------------------------------------------------------
    # Metadata on successful auth
    # -----------------------------------------------------------------
    context 'metadata on successful auth' do
      let(:result) { session_auth_strategy.authenticate(env_session_authenticated, nil) }

      it 'includes ip in metadata' do
        expect(result.metadata[:ip]).to eq('127.0.0.1')
      end

      it 'includes user_agent in metadata' do
        expect(result.metadata[:user_agent]).to eq('Test/1.0')
      end

      it 'includes user_roles as an array' do
        expect(result.metadata[:user_roles]).to be_an(Array)
        expect(result.metadata[:user_roles]).not_to be_empty
      end
    end
  end
end
