# apps/web/auth/spec/support/oauth_flow_helper.rb
#
# frozen_string_literal: true

require_relative 'omniauth_test_helper'

# =============================================================================
# OAuth Flow Simulation Helper
# =============================================================================
#
# Provides infrastructure for testing full OAuth flows including:
#   - Auth initiation (request phase) with session domain_id storage
#   - Callback simulation with configurable host headers
#   - Cross-domain callback attack simulation
#
# This helper works with OmniAuth test_mode to simulate callbacks without
# requiring a real IdP.
#
# Usage:
#   include OAuthFlowHelper
#
#   it 'rejects callback from different domain' do
#     result = simulate_oauth_flow(
#       initiate_host: 'secrets.acme.com',
#       callback_host: 'evil.attacker.com',
#       provider: :entra
#     )
#     expect(result[:callback_status]).to eq(403)
#   end
#
# =============================================================================

module OAuthFlowHelper
  extend RSpec::Matchers::DSL

  # Default provider for tests
  DEFAULT_PROVIDER = :oidc

  # Session key used by the omniauth_tenant hook
  SESSION_DOMAIN_KEY = :omniauth_tenant_domain_id
  SESSION_HOST_KEY = :omniauth_tenant_host

  # Simulate OAuth initiation phase
  #
  # This POSTs to the SSO route with the specified Host header,
  # triggering the omniauth_setup hook which stores domain_id in session.
  #
  # @param host [String] Host header for the request
  # @param provider [Symbol] OmniAuth provider name
  # @return [Hash] Result containing :status, :location, :session
  def simulate_oauth_initiation(host:, provider: DEFAULT_PROVIDER)
    # Set Host header
    header 'Host', host

    # POST to initiate OAuth flow
    post "/auth/sso/#{provider}"

    {
      status: last_response.status,
      location: last_response.headers['Location'],
      cookies: rack_test_session.instance_variable_get(:@rack_mock_session).cookie_jar,
    }
  end

  # Simulate OAuth callback phase
  #
  # This POSTs to the callback route with the specified Host header,
  # triggering the before_omniauth_callback_route hook which validates
  # the session domain_id matches the callback host.
  #
  # @param host [String] Host header for the callback request
  # @param provider [Symbol] OmniAuth provider name
  # @param auth_hash [Hash] Optional OmniAuth auth hash override
  # @return [Hash] Result containing :status, :location, :body
  def simulate_oauth_callback(host:, provider: DEFAULT_PROVIDER, auth_hash: nil)
    # Set Host header
    header 'Host', host

    # Configure OmniAuth mock auth hash if not already set
    setup_mock_auth_hash(provider, auth_hash) if auth_hash

    # POST to callback
    post "/auth/sso/#{provider}/callback"

    {
      status: last_response.status,
      location: last_response.headers['Location'],
      body: last_response.body,
    }
  end

  # Simulate complete OAuth flow with separate initiation and callback hosts
  #
  # This is the primary method for testing cross-domain callback attacks.
  # It initiates OAuth from one domain and attempts callback from another.
  #
  # @param initiate_host [String] Host header for initiation
  # @param callback_host [String] Host header for callback
  # @param provider [Symbol] OmniAuth provider name
  # @param setup_domain [Boolean] Whether to create CustomDomain fixtures
  # @return [Hash] Combined result with :initiate and :callback sub-hashes
  def simulate_oauth_flow(initiate_host:, callback_host:, provider: DEFAULT_PROVIDER, setup_domain: false)
    # Create domain fixtures if requested
    if setup_domain
      setup_oauth_test_domain(initiate_host)
      setup_oauth_test_domain(callback_host) if callback_host != initiate_host
    end

    # Phase 1: Initiation
    initiate_result = simulate_oauth_initiation(host: initiate_host, provider: provider)

    # Phase 2: Callback (uses same session from initiation)
    callback_result = simulate_oauth_callback(host: callback_host, provider: provider)

    {
      initiate: initiate_result,
      callback: callback_result,
      initiate_status: initiate_result[:status],
      callback_status: callback_result[:status],
    }
  end

  # Create CustomDomain and CustomDomain::SsoConfig fixtures for testing
  #
  # @param display_domain [String] The domain hostname
  # @return [Hash] Created fixtures
  def setup_oauth_test_domain(display_domain)
    # Generate unique IDs for this test - use timestamp + random to ensure uniqueness
    test_id = "#{Time.now.to_i}#{SecureRandom.hex(4)}"
    owner_email = "owner-#{test_id}@oauth-test.local"

    # Create organization owner
    owner = Onetime::Customer.new(email: owner_email)
    owner.save

    # Create organization - use unique name based on domain
    org_name = "OAuth Test #{display_domain.gsub('.', '-')}-#{test_id}"
    org = Onetime::Organization.create!(org_name, owner, "contact-#{test_id}@oauth-test.local")

    # Create custom domain
    domain = Onetime::CustomDomain.new(
      display_domain: display_domain,
      org_id: org.org_id
    )
    domain.save
    Onetime::CustomDomain.display_domains.put(display_domain, domain.domainid)

    # Create SSO config for this domain
    # Use OIDC provider type since that's what's registered in the test environment
    sso_config = Onetime::CustomDomain::SsoConfig.create!(
      domain_id: domain.identifier,
      provider_type: 'oidc',
      display_name: "OAuth Test SSO #{test_id}",
      issuer: OmniAuthTestHelper::MOCK_ISSUER,
      client_id: "client-#{test_id}",
      client_secret: "secret-#{test_id}",
      enabled: true
    )

    # Track fixtures for cleanup
    @oauth_test_fixtures ||= []
    @oauth_test_fixtures << {
      domain: domain,
      org: org,
      owner: owner,
      sso_config: sso_config,
      display_domain: display_domain,
    }

    { domain: domain, org: org, sso_config: sso_config }
  end

  # Clean up OAuth test fixtures
  def cleanup_oauth_test_fixtures
    return unless defined?(@oauth_test_fixtures) && @oauth_test_fixtures

    @oauth_test_fixtures.each do |fixture|
      Onetime::CustomDomain::SsoConfig.delete_for_domain!(fixture[:domain].identifier) rescue nil
      Onetime::CustomDomain.display_domains.remove(fixture[:display_domain]) rescue nil
      fixture[:domain]&.destroy! rescue nil
      fixture[:org]&.destroy! rescue nil
    end

    @oauth_test_fixtures = []
  end

  # Inject session values for callback-only testing
  #
  # NOTE: This method makes a bootstrap request to populate the session,
  # then injects the tenant context values. This is necessary because
  # cookie-based session middleware (used by rodauth) reads session data
  # from the encrypted session cookie, not from rack.session env var.
  # The env 'rack.session' approach does not work with cookie sessions.
  #
  # This approach:
  # 1. Makes a GET request to establish a session cookie
  # 2. Uses Rack::Test's session manipulation to inject values
  # 3. Session values persist in subsequent requests via cookies
  #
  # @param domain_id [String] The domain ID to inject
  # @param host [String] The host to inject
  # @param bootstrap_path [String] Path to request for establishing session (default: '/')
  def inject_oauth_session(domain_id:, host:, bootstrap_path: '/')
    # Make a bootstrap request to establish a session cookie.
    # This creates the session infrastructure in Rack::Test.
    get bootstrap_path

    # Access Rack::Test's internal session and inject values.
    # This modifies the session data that will be sent with subsequent requests.
    rack_mock_session = rack_test_session.instance_variable_get(:@rack_mock_session)

    # The session middleware stores data in the cookie; we need to access
    # the last_request's session hash to modify it for subsequent requests.
    # However, this is tricky with encrypted cookies - consider using
    # simulate_oauth_flow() instead for most test scenarios.
    if last_request&.env && last_request.env['rack.session']
      last_request.env['rack.session'][SESSION_DOMAIN_KEY] = domain_id
      last_request.env['rack.session'][SESSION_HOST_KEY] = host
      true
    else
      # If session injection is not possible, log warning and return false.
      # Tests should handle this by using simulate_oauth_flow() instead.
      warn '[OAuthFlowHelper] Session injection not available. ' \
           'Use simulate_oauth_flow() for full flow testing.'
      false
    end
  end

  # Simulate initiation to establish proper session state
  #
  # This is the recommended way to test callback behavior with tenant context.
  # It goes through the real initiation flow which properly sets session values.
  #
  # @param domain_host [String] Domain host to initiate from
  # @param provider [Symbol] OmniAuth provider name
  # @return [Hash] Initiation result (use for verifying setup succeeded)
  def setup_oauth_session_via_initiation(domain_host:, provider: DEFAULT_PROVIDER)
    # Ensure domain fixtures exist
    setup_oauth_test_domain(domain_host)

    # Configure OmniAuth test mode
    OmniAuth.config.test_mode = true
    OmniAuth.config.allowed_request_methods = %i[get post]

    # Initiate OAuth to populate session with tenant context
    simulate_oauth_initiation(host: domain_host, provider: provider)
  end

  private

  # Set up OmniAuth mock auth hash for a provider
  #
  # @param provider [Symbol] Provider name
  # @param auth_hash [Hash, nil] Custom auth hash or nil for default
  def setup_mock_auth_hash(provider, auth_hash)
    OmniAuth.config.mock_auth[provider] = if auth_hash.is_a?(Hash)
      OmniAuth::AuthHash.new(auth_hash)
    else
      auth_hash
    end
  end
end

# =============================================================================
# RSpec Configuration
# =============================================================================

RSpec.configure do |config|
  config.include OAuthFlowHelper

  # Clean up OAuth test fixtures after each test tagged :oauth_flow
  config.after(:each, :oauth_flow) do
    cleanup_oauth_test_fixtures if respond_to?(:cleanup_oauth_test_fixtures)
  end
end
