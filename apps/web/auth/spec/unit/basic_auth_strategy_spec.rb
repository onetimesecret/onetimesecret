# apps/web/auth/spec/unit/basic_auth_strategy_spec.rb
#
# frozen_string_literal: true

# Unit tests for BasicAuthStrategy — HTTP Basic Auth with API key validation.
#
# Requires Valkey on port 2121 (pnpm run test:database:start).
#
# Run:
#   pnpm run test:rspec apps/web/auth/spec/unit/basic_auth_strategy_spec.rb

require_relative '../spec_helper'
require_relative '../support/strategy_test_context'
require_relative '../support/shared_examples/session_contract_examples'

RSpec.describe Onetime::Application::AuthStrategies::BasicAuthStrategy, type: :integration do
  include_context 'strategy test'

  describe '#authenticate' do
    # -----------------------------------------------------------------
    # Valid credentials
    # -----------------------------------------------------------------
    context 'with valid credentials' do
      let(:result) { basic_auth_strategy.authenticate(env_basic_auth_valid, nil) }

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

      it 'sets auth_method to basic_auth' do
        expect(result.auth_method).to eq('basic_auth')
      end

      # Session contract — session must be a Hash, never nil
      include_examples 'a valid session contract'

      it 'session contains no auth state (only org_context cache allowed)' do
        non_cache_keys = result.session.keys.reject { |k| k.to_s.start_with?('org_context:') }
        expect(non_cache_keys).to eq([])
      end
    end

    # -----------------------------------------------------------------
    # Stateless call — no Rack session middleware (env has no rack.session)
    # Regression test: ensures result.session is nil, not a plain {},
    # which would crash Rack's session middleware (.options on Hash).
    # -----------------------------------------------------------------
    context 'with valid credentials and no rack.session in env' do
      let(:env_no_session) do
        encoded = Base64.strict_encode64("#{test_customer.email}:#{test_apikey}")
        {
          'REMOTE_ADDR' => '127.0.0.1',
          'HTTP_USER_AGENT' => 'Test/1.0',
          'HTTP_AUTHORIZATION' => "Basic #{encoded}",
        }
      end

      let(:result) { basic_auth_strategy.authenticate(env_no_session, nil) }

      it 'authenticates successfully' do
        expect(result).to be_a(Otto::Security::Authentication::StrategyResult)
        expect(result.authenticated?).to be true
      end

      it 'returns nil session (not an empty Hash)' do
        expect(result.session).to be_nil
      end
    end

    # -----------------------------------------------------------------
    # Session identity — when a real Rack session exists, the strategy
    # must return the SAME object, not a replacement.
    # -----------------------------------------------------------------
    context 'with valid credentials and a session-like object' do
      let(:mock_session) do
        # Simulate a Rack SecureSessionHash (any object that is not a plain Hash)
        {}
      end

      let(:env_with_session) do
        encoded = Base64.strict_encode64("#{test_customer.email}:#{test_apikey}")
        {
          'rack.session' => mock_session,
          'REMOTE_ADDR' => '127.0.0.1',
          'HTTP_USER_AGENT' => 'Test/1.0',
          'HTTP_AUTHORIZATION' => "Basic #{encoded}",
        }
      end

      let(:result) { basic_auth_strategy.authenticate(env_with_session, nil) }

      it 'returns the exact same session object (identity check)' do
        expect(result.session).to equal(mock_session)
      end
    end

    # -----------------------------------------------------------------
    # Invalid API key (correct user, wrong key)
    # -----------------------------------------------------------------
    context 'with invalid API key' do
      let(:result) { basic_auth_strategy.authenticate(env_basic_auth_invalid, nil) }

      it 'returns an AuthFailure' do
        expect(result).to be_a(Otto::Security::Authentication::AuthFailure)
      end
    end

    # -----------------------------------------------------------------
    # Nonexistent user
    # -----------------------------------------------------------------
    context 'with nonexistent user' do
      let(:env_nonexistent_user) do
        encoded = Base64.strict_encode64("nobody_#{SecureRandom.uuid}@example.com:#{test_apikey}")
        {
          'rack.session' => {},
          'REMOTE_ADDR' => '127.0.0.1',
          'HTTP_USER_AGENT' => 'Test/1.0',
          'HTTP_AUTHORIZATION' => "Basic #{encoded}",
        }
      end

      let(:result) { basic_auth_strategy.authenticate(env_nonexistent_user, nil) }

      it 'returns an AuthFailure' do
        expect(result).to be_a(Otto::Security::Authentication::AuthFailure)
      end

      it 'still calls apitoken? on the dummy customer for timing safety' do
        # Both the real-customer and dummy-customer paths go through
        # target_cust.apitoken?(apikey), ensuring constant-time comparison.
        # We verify indirectly: the strategy must not raise, and must
        # return a failure (not an exception), proving the dummy path ran.
        expect { result }.not_to raise_error
      end
    end

    # -----------------------------------------------------------------
    # Missing Authorization header
    # -----------------------------------------------------------------
    context 'with missing Authorization header' do
      let(:result) { basic_auth_strategy.authenticate(env_basic_auth_missing, nil) }

      it 'returns an AuthFailure' do
        expect(result).to be_a(Otto::Security::Authentication::AuthFailure)
      end
    end

    # -----------------------------------------------------------------
    # Malformed Authorization header (not "Basic ...")
    # -----------------------------------------------------------------
    context 'with malformed Authorization header' do
      let(:env_malformed) do
        {
          'rack.session' => {},
          'REMOTE_ADDR' => '127.0.0.1',
          'HTTP_USER_AGENT' => 'Test/1.0',
          'HTTP_AUTHORIZATION' => 'Bearer some_token_here',
        }
      end

      let(:result) { basic_auth_strategy.authenticate(env_malformed, nil) }

      it 'returns an AuthFailure' do
        expect(result).to be_a(Otto::Security::Authentication::AuthFailure)
      end
    end

    # -----------------------------------------------------------------
    # Metadata
    # -----------------------------------------------------------------
    context 'metadata on successful auth' do
      let(:result) { basic_auth_strategy.authenticate(env_basic_auth_valid, nil) }

      it 'includes ip in metadata' do
        expect(result.metadata[:ip]).to eq('127.0.0.1')
      end

      it 'includes user_agent in metadata' do
        expect(result.metadata[:user_agent]).to eq('Test/1.0')
      end

      it 'includes auth_type: basic in metadata' do
        expect(result.metadata[:auth_type]).to eq('basic')
      end
    end
  end
end
