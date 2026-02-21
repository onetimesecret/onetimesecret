# apps/web/auth/spec/support/strategy_test_context.rb
#
# frozen_string_literal: true

# Shared RSpec context for testing auth strategies (NoAuth, BasicAuth, SessionAuth).
#
# Provides mock Rack env hashes for each authentication scenario, a helper
# to build StrategyResult instances, and a test customer with automatic cleanup.
#
# Usage:
#   include_context 'strategy test'
#
# Requires Valkey on port 2121 (pnpm run test:database:start).

require 'securerandom'
require 'base64'

RSpec.shared_context 'strategy test' do
  # ---------------------------------------------------------------------------
  # Test customer (persisted to Valkey, cleaned up in after hook)
  # ---------------------------------------------------------------------------
  let(:test_email) { "strategy_test_#{SecureRandom.uuid}@example.com" }
  let(:test_apikey) { SecureRandom.hex(20) }

  before do
    Onetime.boot! :test unless Onetime.ready?

    @test_customer = Onetime::Customer.new(email: test_email)
    @test_customer.save
    # Set an API token so BasicAuth tests can validate against it
    @test_customer.apitoken = test_apikey
    @test_customer.save
  end

  after do
    @test_customer&.delete!
  end

  # Convenience accessor as a let-style method
  let(:test_customer) { @test_customer }

  # ---------------------------------------------------------------------------
  # Mock Rack env hashes
  # ---------------------------------------------------------------------------

  # Anonymous request — empty session, no auth header
  let(:env_anonymous) do
    {
      'rack.session' => {},
      'REMOTE_ADDR' => '127.0.0.1',
      'HTTP_USER_AGENT' => 'Test/1.0',
    }
  end

  # Session-authenticated request — session carries identity
  let(:env_session_authenticated) do
    {
      'rack.session' => {
        'authenticated' => true,
        'external_id' => test_customer.extid,
        'email' => test_customer.email,
      },
      'REMOTE_ADDR' => '127.0.0.1',
      'HTTP_USER_AGENT' => 'Test/1.0',
    }
  end

  # Basic auth with valid credentials
  let(:env_basic_auth_valid) do
    encoded = Base64.strict_encode64("#{test_customer.email}:#{test_apikey}")
    {
      'rack.session' => {},
      'REMOTE_ADDR' => '127.0.0.1',
      'HTTP_USER_AGENT' => 'Test/1.0',
      'HTTP_AUTHORIZATION' => "Basic #{encoded}",
    }
  end

  # Basic auth with invalid credentials (wrong key)
  let(:env_basic_auth_invalid) do
    encoded = Base64.strict_encode64("#{test_customer.email}:wrong_key_entirely")
    {
      'rack.session' => {},
      'REMOTE_ADDR' => '127.0.0.1',
      'HTTP_USER_AGENT' => 'Test/1.0',
      'HTTP_AUTHORIZATION' => "Basic #{encoded}",
    }
  end

  # Basic auth with missing Authorization header
  let(:env_basic_auth_missing) do
    {
      'rack.session' => {},
      'REMOTE_ADDR' => '127.0.0.1',
      'HTTP_USER_AGENT' => 'Test/1.0',
    }
  end

  # ---------------------------------------------------------------------------
  # StrategyResult helper
  # ---------------------------------------------------------------------------

  # Build an Otto StrategyResult with controlled values.
  #
  # @param session [Hash] session hash (default: empty)
  # @param user [Onetime::Customer, nil] authenticated customer or nil
  # @param auth_method [String] e.g. 'noauth', 'basic_auth', 'sessionauth'
  # @param strategy_name [String] strategy class label
  # @param metadata [Hash] additional metadata
  # @return [Otto::Security::Authentication::StrategyResult]
  def build_strategy_result(
    session: {},
    user: nil,
    auth_method: 'noauth',
    strategy_name: 'noauth',
    metadata: {}
  )
    Otto::Security::Authentication::StrategyResult.new(
      session: session,
      user: user,
      auth_method: auth_method,
      strategy_name: strategy_name,
      metadata: metadata,
    )
  end

  # ---------------------------------------------------------------------------
  # Strategy class shortcuts
  # ---------------------------------------------------------------------------
  let(:no_auth_strategy) { Onetime::Application::AuthStrategies::NoAuthStrategy.new }
  let(:basic_auth_strategy) { Onetime::Application::AuthStrategies::BasicAuthStrategy.new }
  let(:session_auth_strategy) { Onetime::Application::AuthStrategies::SessionAuthStrategy.new }
end
