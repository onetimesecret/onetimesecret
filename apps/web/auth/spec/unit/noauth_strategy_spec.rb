# apps/web/auth/spec/unit/noauth_strategy_spec.rb
#
# frozen_string_literal: true

# Unit tests for NoAuthStrategy — allows all requests, tries session first.
#
# Requires Valkey on port 2121 (pnpm run test:database:start).
#
# Run:
#   pnpm run test:rspec apps/web/auth/spec/unit/noauth_strategy_spec.rb

require_relative '../spec_helper'
require_relative '../support/strategy_test_context'
require_relative '../support/shared_examples/session_contract_examples'

RSpec.describe Onetime::Application::AuthStrategies::NoAuthStrategy, type: :integration do
  include_context 'strategy test'

  describe '#authenticate' do
    # -----------------------------------------------------------------
    # Anonymous / empty session
    # -----------------------------------------------------------------
    context 'with empty session (anonymous)' do
      let(:result) { no_auth_strategy.authenticate(env_anonymous, nil) }

      it 'returns a StrategyResult' do
        expect(result).to be_a(Otto::Security::Authentication::StrategyResult)
      end

      it 'user is nil' do
        expect(result.user).to be_nil
      end

      it 'is not authenticated' do
        expect(result.authenticated?).to be false
      end

      it 'sets auth_method to noauth' do
        expect(result.auth_method).to eq('noauth')
      end
    end

    # -----------------------------------------------------------------
    # Authenticated session (session carries identity)
    # -----------------------------------------------------------------
    context 'with authenticated session' do
      let(:result) { no_auth_strategy.authenticate(env_session_authenticated, nil) }

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

      it 'sets auth_method to noauth' do
        expect(result.auth_method).to eq('noauth')
      end

      # Session contract — session must not be nil, must support bracket access
      include_examples 'a valid session contract'

      it 'session is the env rack.session (same object reference)' do
        expect(result.session).to be(env_session_authenticated['rack.session'])
      end
    end

    # -----------------------------------------------------------------
    # Session with nonexistent customer falls back to anonymous
    # -----------------------------------------------------------------
    context 'with session referencing nonexistent customer' do
      let(:env_nonexistent_session) do
        {
          'rack.session' => {
            'authenticated' => true,
            'external_id' => "gone_#{SecureRandom.uuid}@example.com",
            'email' => 'gone@example.com',
          },
          'REMOTE_ADDR' => '127.0.0.1',
          'HTTP_USER_AGENT' => 'Test/1.0',
        }
      end

      let(:result) { no_auth_strategy.authenticate(env_nonexistent_session, nil) }

      it 'returns a StrategyResult (not AuthFailure)' do
        expect(result).to be_a(Otto::Security::Authentication::StrategyResult)
      end

      it 'user is nil (falls back to anonymous)' do
        expect(result.user).to be_nil
      end

      it 'is not authenticated' do
        expect(result.authenticated?).to be false
      end
    end

    # -----------------------------------------------------------------
    # Always returns StrategyResult — never AuthFailure
    # -----------------------------------------------------------------
    context 'across multiple env variations' do
      let(:envs) do
        [
          # Completely empty session
          { 'rack.session' => {} },
          # Session with a stale external_id
          { 'rack.session' => { 'external_id' => 'fake' } },
          # Session with nil values
          { 'rack.session' => { 'authenticated' => nil, 'external_id' => nil } },
          # Minimal env — only rack.session key
          { 'rack.session' => {}, 'REMOTE_ADDR' => '10.0.0.1' },
        ]
      end

      it 'always returns StrategyResult, never AuthFailure' do
        envs.each do |env|
          result = no_auth_strategy.authenticate(env, nil)
          expect(result).to be_a(Otto::Security::Authentication::StrategyResult),
            "Expected StrategyResult for env #{env.inspect}, got #{result.class}"
        end
      end
    end

    # -----------------------------------------------------------------
    # Source comment accuracy
    # -----------------------------------------------------------------
    context 'source documentation' do
      let(:source_file) { File.read(File.expand_path('../../../../../lib/onetime/application/auth_strategies.rb', __dir__)) }

      it 'comment says "Try session first, then fall back to anonymous" (no mention of Basic auth handling here)' do
        # The NoAuthStrategy comment must describe its own scope accurately:
        # it tries session, falls back to anonymous, and defers Basic auth
        # to a separate strategy.
        expect(source_file).to include('Try session first, then fall back to anonymous')
        expect(source_file).to include('Basic auth is')
        expect(source_file).to include('handled by a separate strategy')
      end
    end
  end
end
