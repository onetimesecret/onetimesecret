# apps/web/auth/spec/support/omniauth_test_helper.rb
#
# frozen_string_literal: true

require 'webmock/rspec'
require 'omniauth'

# =============================================================================
# OmniAuth Test Helpers
# =============================================================================
#
# Provides mock OIDC configuration for testing OmniAuth integration without
# requiring a real identity provider.
#
# IMPORTANT: The env vars and WebMock stubs for OIDC discovery are set up
# in spec_helper.rb BEFORE this file is loaded. This ensures they're available
# before any code that might trigger Onetime config loading.
#
# The key insight: OmniAuth test_mode mocks the *callback* phase, but our
# CSRF tests need the *request* phase (OAuth redirect). The request phase
# requires the OmniAuth strategy to be registered during boot, which means
# OIDC discovery must be stubbed before the app boots.
#
# For tests that can run with mock callbacks (callback phase testing),
# use the :omniauth_mock tag and the helper methods below.
#
# =============================================================================

module OmniAuthTestHelper
  MOCK_ISSUER = 'https://mock-idp.example.com'
  MOCK_CLIENT_ID = 'test-client-id'
  MOCK_CLIENT_SECRET = 'test-client-secret'
  MOCK_REDIRECT_URI = 'http://localhost:3000/auth/sso/oidc/callback'

  # OIDC Discovery document that omniauth_openid_connect expects
  MOCK_OIDC_DISCOVERY = {
    issuer: MOCK_ISSUER,
    authorization_endpoint: "#{MOCK_ISSUER}/authorize",
    token_endpoint: "#{MOCK_ISSUER}/token",
    userinfo_endpoint: "#{MOCK_ISSUER}/userinfo",
    jwks_uri: "#{MOCK_ISSUER}/.well-known/jwks.json",
    response_types_supported: %w[code],
    subject_types_supported: %w[public],
    id_token_signing_alg_values_supported: %w[RS256],
    scopes_supported: %w[openid email profile],
    token_endpoint_auth_methods_supported: %w[client_secret_basic client_secret_post],
    claims_supported: %w[sub email email_verified name],
    code_challenge_methods_supported: %w[S256],
  }.freeze

  # Stub the OIDC discovery endpoint
  # This allows omniauth_openid_connect to register the provider
  def stub_oidc_discovery
    stub_request(:get, "#{MOCK_ISSUER}/.well-known/openid-configuration")
      .to_return(
        status: 200,
        body: MOCK_OIDC_DISCOVERY.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    # Also stub the JWKS endpoint (needed for token validation)
    stub_request(:get, "#{MOCK_ISSUER}/.well-known/jwks.json")
      .to_return(
        status: 200,
        body: { keys: [] }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  # Check if real OIDC is configured (non-mock issuer)
  def real_oidc_configured?
    issuer = ENV['OIDC_ISSUER'].to_s.strip
    !issuer.empty? && issuer != MOCK_ISSUER
  end

  # Enable OmniAuth test mode for callback mocking
  # Use this for tests that need to mock the callback phase
  def enable_omniauth_test_mode
    OmniAuth.config.test_mode = true
    OmniAuth.config.allowed_request_methods = %i[get post]
    OmniAuth.config.silence_get_warning = true
  end

  # Reset OmniAuth configuration
  def reset_omniauth_config
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth.clear
  end

  # Mock a successful OIDC authentication hash
  # Use for testing callback handling
  def mock_oidc_success(email: 'test@example.com', name: 'Test User', uid: 'test-uid-123')
    OmniAuth.config.mock_auth[:oidc] = OmniAuth::AuthHash.new({
      provider: 'oidc',
      uid: uid,
      info: {
        email: email,
        name: name,
        email_verified: true,
      },
      credentials: {
        token: 'mock_access_token',
        refresh_token: 'mock_refresh_token',
        expires_at: Time.now.to_i + 3600,
        expires: true,
      },
      extra: {
        raw_info: {
          sub: uid,
          email: email,
          name: name,
          email_verified: true,
        },
      },
    })
  end

  # Mock a failed OIDC authentication
  # @param error_type [Symbol] :invalid_credentials, :access_denied, :timeout, etc.
  def mock_oidc_failure(error_type = :invalid_credentials)
    OmniAuth.config.mock_auth[:oidc] = error_type
  end

  # Mock a successful Entra ID authentication hash
  # NOTE: Provider name is 'entra' (not 'entra_id') because configure_entra_id_provider
  # uses name: :entra which overrides the gem's default 'entra_id' provider name.
  # The name: option controls both the route segment and the auth hash provider value.
  def mock_entra_success(email: 'user@contoso.onmicrosoft.com', name: 'Contoso User', uid: 'entra-uid-456')
    OmniAuth.config.mock_auth[:entra] = OmniAuth::AuthHash.new({
      provider: 'entra',
      uid: uid,
      info: {
        email: email,
        name: name,
        email_verified: true,
        first_name: name.split(' ').first,
        last_name: name.split(' ').last,
      },
      credentials: {
        token: 'mock_entra_access_token',
        refresh_token: 'mock_entra_refresh_token',
        expires_at: Time.now.to_i + 3600,
        expires: true,
      },
      extra: {
        raw_info: {
          sub: uid,
          email: email,
          name: name,
          email_verified: true,
          oid: uid,
          tid: 'mock-tenant-id',
        },
      },
    })
  end

  # Mock a failed Entra ID authentication
  # @param error_type [Symbol] :invalid_credentials, :access_denied, :timeout, etc.
  def mock_entra_failure(error_type = :invalid_credentials)
    OmniAuth.config.mock_auth[:entra] = error_type
  end

  # Mock a successful Google authentication hash
  def mock_google_success(email: 'user@gmail.com', name: 'Google User', uid: 'google-uid-789')
    OmniAuth.config.mock_auth[:google] = OmniAuth::AuthHash.new({
      provider: 'google',
      uid: uid,
      info: {
        email: email,
        name: name,
        email_verified: true,
        first_name: name.split(' ').first,
        last_name: name.split(' ').last,
        image: "https://lh3.googleusercontent.com/a/default-user",
      },
      credentials: {
        token: 'mock_google_access_token',
        refresh_token: 'mock_google_refresh_token',
        expires_at: Time.now.to_i + 3600,
        expires: true,
      },
      extra: {
        raw_info: {
          sub: uid,
          email: email,
          name: name,
          email_verified: true,
        },
      },
    })
  end

  # Mock a failed Google authentication
  # @param error_type [Symbol] :invalid_credentials, :access_denied, :timeout, etc.
  def mock_google_failure(error_type = :invalid_credentials)
    OmniAuth.config.mock_auth[:google] = error_type
  end

  # Mock a successful GitHub authentication hash
  def mock_github_success(email: 'user@github.com', name: 'GitHub User', uid: 'github-uid-101', nickname: 'ghuser')
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new({
      provider: 'github',
      uid: uid,
      info: {
        email: email,
        name: name,
        nickname: nickname,
        image: "https://avatars.githubusercontent.com/u/#{uid}",
      },
      credentials: {
        token: 'mock_github_access_token',
        expires: false,
      },
      extra: {
        raw_info: {
          login: nickname,
          id: uid.to_i,
          email: email,
          name: name,
        },
      },
    })
  end

  # Mock a failed GitHub authentication
  # @param error_type [Symbol] :invalid_credentials, :access_denied, :timeout, etc.
  def mock_github_failure(error_type = :invalid_credentials)
    OmniAuth.config.mock_auth[:github] = error_type
  end
end

# RSpec configuration for automatic setup/teardown
RSpec.configure do |config|
  config.include OmniAuthTestHelper

  # Re-stub OIDC discovery for tests tagged with :omniauth_mock
  # Ensures stubs are fresh after any WebMock.reset!
  config.before(:each, :omniauth_mock) do
    stub_oidc_discovery
  end

  config.after(:each, :omniauth_mock) do
    reset_omniauth_config
  end

  # Ensure WebMock allows localhost for integration tests
  config.before(:each, type: :integration) do
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  config.after(:each, type: :integration) do
    WebMock.allow_net_connect!
  end
end
