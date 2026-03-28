# apps/web/auth/spec/support/mock_omniauth_strategy.rb
#
# frozen_string_literal: true

require 'omniauth'

module OmniAuth
  module Strategies
    # TenantVerifyingMock - A mock OmniAuth strategy for testing tenant resolution.
    #
    # This strategy captures the credentials injected via the setup proc during
    # the request phase, allowing tests to verify that tenant-specific SSO
    # configurations are properly resolved and injected.
    #
    # Unlike OmniAuth's built-in MockAuth (test_mode), this strategy:
    #   - Actually executes the request phase (setup proc runs)
    #   - Captures injected options for test assertions
    #   - Can simulate IdP redirect behavior
    #
    # Usage:
    #   OmniAuth::Strategies::TenantVerifyingMock.reset!
    #   post '/auth/sso/tenant_verify'
    #   expect(OmniAuth::Strategies::TenantVerifyingMock.last_received_credentials[:client_id]).to eq('expected')
    #
    class TenantVerifyingMock
      include OmniAuth::Strategy

      # Thread-safe storage for captured credentials
      @mutex = Mutex.new
      @last_received_credentials = nil
      @request_count = 0

      class << self
        attr_reader :mutex

        # Get the last received credentials (thread-safe)
        def last_received_credentials
          mutex.synchronize { @last_received_credentials&.dup }
        end

        # Set the last received credentials (thread-safe)
        def last_received_credentials=(value)
          mutex.synchronize { @last_received_credentials = value }
        end

        # Get the request count (thread-safe)
        def request_count
          mutex.synchronize { @request_count }
        end

        # Increment request count (thread-safe)
        def increment_request_count
          mutex.synchronize { @request_count += 1 }
        end

        # Reset all captured state between tests
        def reset!
          mutex.synchronize do
            @last_received_credentials = nil
            @request_count = 0
          end
        end
      end

      # Strategy options with defaults
      option :name, 'tenant_verify'
      option :client_id, nil
      option :client_secret, nil
      option :tenant_id, nil
      option :issuer, nil
      option :scope, nil

      # Request phase - captures credentials and simulates redirect
      #
      # The setup proc (if configured) runs BEFORE this method is called.
      # By the time we reach request_phase, options have been modified
      # by the setup proc with tenant-specific credentials.
      def request_phase
        self.class.increment_request_count

        # Capture the credentials that were injected by the setup proc
        credentials = {
          client_id: options.client_id,
          client_secret: options.client_secret,
          tenant_id: options.tenant_id,
          issuer: options.issuer,
          scope: options.scope,
          host: request.env['HTTP_HOST'],
          name: options.name,
          captured_at: Time.now.to_i,
        }

        self.class.last_received_credentials = credentials

        # Simulate IdP redirect (mimics real OAuth flow)
        mock_authorize_url = build_mock_authorize_url(credentials)
        redirect mock_authorize_url
      end

      # Callback phase - returns mock auth hash
      #
      # For tenant resolution tests, we primarily care about the request phase
      # where credentials are injected. The callback phase returns a standard
      # mock auth hash for completeness.
      def callback_phase
        # Return mock auth hash based on captured credentials
        super
      end

      # Standard OmniAuth info hash
      def info
        {
          email: 'test@tenant.example.com',
          name: 'Test User',
          email_verified: true,
        }
      end

      # Standard OmniAuth uid
      def uid
        'mock-tenant-uid-12345'
      end

      # Standard OmniAuth credentials
      def credentials
        {
          token: 'mock_access_token',
          refresh_token: 'mock_refresh_token',
          expires_at: Time.now.to_i + 3600,
          expires: true,
        }
      end

      # Standard OmniAuth extra info
      def extra
        {
          raw_info: {
            sub: uid,
            email: info[:email],
            name: info[:name],
            email_verified: info[:email_verified],
          },
        }
      end

      private

      # Build a mock authorization URL for testing
      #
      # @param creds [Hash] Captured credentials
      # @return [String] Mock IdP authorize URL
      def build_mock_authorize_url(creds)
        base_url = 'https://mock-idp.test/authorize'
        params = {
          client_id: creds[:client_id] || 'unknown',
          redirect_uri: callback_url,
          scope: creds[:scope] || 'openid email profile',
          response_type: 'code',
          state: session['omniauth.state'] || SecureRandom.hex(16),
        }

        # Add tenant_id for Entra-style flows
        params[:tenant] = creds[:tenant_id] if creds[:tenant_id]

        "#{base_url}?#{URI.encode_www_form(params)}"
      end
    end
  end
end

# =============================================================================
# RSpec Matchers for TenantVerifyingMock
# =============================================================================

RSpec::Matchers.define :have_received_tenant_credentials do |expected|
  match do |_actual|
    creds = OmniAuth::Strategies::TenantVerifyingMock.last_received_credentials
    return false if creds.nil?

    expected.all? do |key, value|
      creds[key] == value
    end
  end

  failure_message do |_actual|
    creds = OmniAuth::Strategies::TenantVerifyingMock.last_received_credentials
    "expected TenantVerifyingMock to have received credentials #{expected.inspect}, " \
      "but got #{creds.inspect}"
  end

  failure_message_when_negated do |_actual|
    "expected TenantVerifyingMock not to have received credentials #{expected.inspect}"
  end
end

RSpec::Matchers.define :have_received_request do
  match do |_actual|
    OmniAuth::Strategies::TenantVerifyingMock.request_count.positive?
  end

  failure_message do |_actual|
    'expected TenantVerifyingMock to have received at least one request, but got none'
  end
end

# =============================================================================
# RSpec Configuration for TenantVerifyingMock
# =============================================================================

RSpec.configure do |config|
  # Reset mock state before each test tagged with :tenant_mock
  config.before(:each, :tenant_mock) do
    OmniAuth::Strategies::TenantVerifyingMock.reset!
  end

  # Include matchers for all tests
  config.include(Module.new do
    def tenant_mock_credentials
      OmniAuth::Strategies::TenantVerifyingMock.last_received_credentials
    end

    def tenant_mock_request_count
      OmniAuth::Strategies::TenantVerifyingMock.request_count
    end

    def reset_tenant_mock!
      OmniAuth::Strategies::TenantVerifyingMock.reset!
    end
  end)
end
