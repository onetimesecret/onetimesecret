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
    # Credential watermark (#3810) — the anonymous-capable path. A session
    # authenticated BEFORE Customer#last_password_update must degrade to
    # anonymous (nil user), never a 401: Helpers#load_user_from_session
    # returns nil when session_predates_credential_change?. The rejecting
    # variant is covered in session_auth_strategy_spec.rb.
    # -----------------------------------------------------------------
    context 'credential watermark (#3810)' do
      let(:watermark) { Familia.now.to_i }

      def env_with_authenticated_at(value)
        {
          'rack.session' => {
            'authenticated' => true,
            'external_id' => test_customer.extid,
            'email' => test_customer.email,
            'authenticated_at' => value,
          },
          'REMOTE_ADDR' => '127.0.0.1',
          'HTTP_USER_AGENT' => 'Test/1.0',
        }
      end

      context 'with a session authenticated before the watermark' do
        before { test_customer.last_password_update!(watermark) }

        let(:result) do
          no_auth_strategy.authenticate(env_with_authenticated_at(watermark - 100), nil)
        end

        it 'returns a StrategyResult (not AuthFailure)' do
          expect(result).to be_a(Otto::Security::Authentication::StrategyResult)
        end

        it 'degrades to anonymous (nil user, not authenticated)' do
          expect(result.user).to be_nil
          expect(result.authenticated?).to be false
        end
      end

      context 'with a session authenticated exactly at the watermark' do
        before { test_customer.last_password_update!(watermark) }

        let(:result) do
          no_auth_strategy.authenticate(env_with_authenticated_at(watermark), nil)
        end

        it 'degrades to anonymous (== watermark is pre-change under <=; nil user, not authenticated)' do
          expect(result).to be_a(Otto::Security::Authentication::StrategyResult)
          expect(result.user).to be_nil
          expect(result.authenticated?).to be false
        end
      end

      context 'with a session authenticated strictly after the watermark' do
        before { test_customer.last_password_update!(watermark) }

        let(:result) do
          no_auth_strategy.authenticate(env_with_authenticated_at(watermark + 1), nil)
        end

        it 'resolves the customer (after_change_password re-stamps the kept session to > watermark)' do
          expect(result.user).to be_a(Onetime::Customer)
          expect(result.user.custid).to eq(test_customer.custid)
          expect(result.authenticated?).to be true
        end
      end
    end

    # -----------------------------------------------------------------
    # Anonymous fallthrough refusal (docs/security/audits/2026-07-29-api.md
    # item 1). On auth=basicauth,noauth chains, Otto's RouteAuthWrapper OR
    # logic runs basicauth first; when it rejects PRESENTED credentials it
    # marks the env, and NoAuthStrategy must then refuse — so the whole
    # chain fails (401) instead of silently succeeding anonymous.
    # -----------------------------------------------------------------
    context 'anonymous fallthrough refusal' do
      let(:marker_key) { Onetime::Application::AuthStrategies::Helpers::CREDENTIALED_FAILURE_ENV_KEY }
      let(:basic_auth_strategy) { Onetime::Application::AuthStrategies::BasicAuthStrategy.new }

      context 'after BasicAuthStrategy rejected invalid credentials (chain simulation)' do
        let(:env_invalid_basic) do
          encoded = Base64.strict_encode64("#{test_customer.email}:wrong_key_entirely")
          {
            'rack.session' => {},
            'REMOTE_ADDR' => '127.0.0.1',
            'HTTP_USER_AGENT' => 'Test/1.0',
            'HTTP_AUTHORIZATION' => "Basic #{encoded}",
          }
        end

        it 'refuses with an AuthFailure instead of anonymous success' do
          # Same env object flows through the chain, exactly as
          # RouteAuthWrapper#authenticate_and_authorize does.
          basic_result = basic_auth_strategy.authenticate(env_invalid_basic, nil)
          expect(basic_result).to be_a(Otto::Security::Authentication::AuthFailure)

          noauth_result = no_auth_strategy.authenticate(env_invalid_basic, nil)
          expect(noauth_result).to be_a(Otto::Security::Authentication::AuthFailure)
        end

        it 'echoes the underlying credential failure reason' do
          basic_auth_strategy.authenticate(env_invalid_basic, nil)
          noauth_result = no_auth_strategy.authenticate(env_invalid_basic, nil)
          expect(noauth_result.failure_reason).to include('CREDENTIALS_INVALID')
        end
      end

      context 'after BasicAuthStrategy rejected a UUIDv7-as-username (real-world trigger)' do
        it 'refuses with an AuthFailure instead of anonymous success' do
          encoded = Base64.strict_encode64('0190b6f0-7d1a-7c3e-8f4a-2b9c1d0e5a6b:some_key')
          env     = {
            'rack.session' => {},
            'REMOTE_ADDR' => '127.0.0.1',
            'HTTP_USER_AGENT' => 'Test/1.0',
            'HTTP_AUTHORIZATION' => "Basic #{encoded}",
          }

          basic_auth_strategy.authenticate(env, nil)
          noauth_result = no_auth_strategy.authenticate(env, nil)
          expect(noauth_result).to be_a(Otto::Security::Authentication::AuthFailure)
          expect(noauth_result.failure_reason).to include('CREDENTIALS_INVALID')
        end
      end

      context 'with no Authorization header (chain simulation)' do
        it 'still degrades to anonymous after AUTH_HEADER_MISSING (unchanged behavior)' do
          basic_result = basic_auth_strategy.authenticate(env_anonymous, nil)
          expect(basic_result).to be_a(Otto::Security::Authentication::AuthFailure)
          expect(basic_result.failure_reason).to include('AUTH_HEADER_MISSING')

          noauth_result = no_auth_strategy.authenticate(env_anonymous, nil)
          expect(noauth_result).to be_a(Otto::Security::Authentication::StrategyResult)
          expect(noauth_result.user).to be_nil
          expect(noauth_result.authenticated?).to be false
        end
      end

      context 'with an Authorization header on a noauth-ONLY route (no credentialed strategy ran)' do
        # Deliberate design choice: without a credentialed strategy in the
        # chain there is nothing to validate the header against, and refusing
        # would break deployments behind Basic-auth reverse proxies that
        # forward the header (and browsers re-sending cached Basic creds).
        # The header is ignored; the request stays anonymous.
        it 'ignores a Basic header and stays anonymous' do
          env = env_anonymous.merge('HTTP_AUTHORIZATION' => "Basic #{Base64.strict_encode64('x:y')}")
          result = no_auth_strategy.authenticate(env, nil)
          expect(result).to be_a(Otto::Security::Authentication::StrategyResult)
          expect(result.user).to be_nil
        end

        it 'ignores a Bearer header and stays anonymous' do
          env = env_anonymous.merge('HTTP_AUTHORIZATION' => 'Bearer some_token')
          result = no_auth_strategy.authenticate(env, nil)
          expect(result).to be_a(Otto::Security::Authentication::StrategyResult)
          expect(result.user).to be_nil
        end
      end

      context 'with a pre-set marker (mechanism-level check)' do
        it 'returns an AuthFailure carrying the recorded reason' do
          env = env_anonymous.merge(marker_key => '[CREDENTIALS_INVALID] Invalid credentials')
          result = no_auth_strategy.authenticate(env, nil)
          expect(result).to be_a(Otto::Security::Authentication::AuthFailure)
          expect(result.failure_reason).to eq('[CREDENTIALS_INVALID] Invalid credentials')
        end
      end
    end

    # -----------------------------------------------------------------
    # Always returns StrategyResult — never AuthFailure — for requests
    # that did not present credentials (no credentialed-failure marker).
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
      let(:source_file) { File.read(File.expand_path('../../../../../lib/onetime/application/auth_strategies/no_auth_strategy.rb', __dir__)) }

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
