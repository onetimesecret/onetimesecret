# apps/web/auth/spec/support/omniauth_test_helper.rb
#
# frozen_string_literal: true

require 'webmock/rspec'
require 'omniauth'
require 'securerandom'

# =============================================================================
# OmniAuth Test Helpers
# =============================================================================
#
# Provides mock OIDC configuration for testing OmniAuth integration without
# requiring a real identity provider.
#
# IMPORTANT: WebMock stubs for the placeholder OIDC issuer
# (placeholder.invalid) are set in spec_helper.rb BEFORE this file is
# loaded, so boot-time OIDC discovery succeeds. No OIDC env vars are
# injected — all providers register via placeholder when
# ORGS_SSO_ENABLED=true.
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

  # Stub OIDC discovery for the placeholder issuer used during
  # route registration (request-phase discovery at runtime).
  def stub_oidc_discovery
    stub_request(:get, "#{PLACEHOLDER_OIDC_ISSUER}/.well-known/openid-configuration")
      .to_return(
        status: 200,
        body: {
          issuer: PLACEHOLDER_OIDC_ISSUER,
          authorization_endpoint: "#{PLACEHOLDER_OIDC_ISSUER}/authorize",
          token_endpoint: "#{PLACEHOLDER_OIDC_ISSUER}/token",
          userinfo_endpoint: "#{PLACEHOLDER_OIDC_ISSUER}/userinfo",
          jwks_uri: "#{PLACEHOLDER_OIDC_ISSUER}/.well-known/jwks.json",
          response_types_supported: %w[code],
          subject_types_supported: %w[public],
          id_token_signing_alg_values_supported: %w[RS256],
          scopes_supported: %w[openid email profile],
          token_endpoint_auth_methods_supported: %w[client_secret_basic client_secret_post],
          claims_supported: %w[sub email email_verified name],
          code_challenge_methods_supported: %w[S256],
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    stub_request(:get, "#{PLACEHOLDER_OIDC_ISSUER}/.well-known/jwks.json")
      .to_return(
        status: 200,
        body: { keys: [] }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  # Check if real OIDC is configured (non-placeholder issuer)
  def real_oidc_configured?
    issuer = ENV['OIDC_ISSUER'].to_s.strip
    !issuer.empty? && issuer != PLACEHOLDER_OIDC_ISSUER
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
    OmniAuth.config.allowed_request_methods = [:post]
    OmniAuth.config.silence_get_warning = false
  end

  # Mock a successful OIDC authentication hash
  # Use for testing callback handling
  #
  # provider: registers under a provider other than :oidc (the callback route
  #   segment and the auth hash's provider value are the same string).
  # email: nil models an IdP that returns NO email claim — the claim is OMITTED
  #   from info and raw_info rather than sent as null, which is what a real
  #   emailless response looks like and what the app's missing-email paths must
  #   handle. Note '' is not nil: an empty-string claim is still a claim, and
  #   the domain-restriction specs rely on it being passed through.
  def mock_oidc_success(email: 'test@example.com', name: 'Test User', uid: 'test-uid-123', provider: :oidc)
    info     = { name: name }
    raw_info = { sub: uid, name: name }
    unless email.nil?
      info     = info.merge(email: email, email_verified: true)
      raw_info = raw_info.merge(email: email, email_verified: true)
    end

    OmniAuth.config.mock_auth[provider.to_sym] = OmniAuth::AuthHash.new({
      provider: provider.to_s,
      uid: uid,
      info: info,
      credentials: {
        token: 'mock_access_token',
        refresh_token: 'mock_refresh_token',
        expires_at: Time.now.to_i + 3600,
        expires: true,
      },
      extra: {
        raw_info: raw_info,
      },
    })
  end

  # Put OmniAuth in test mode AND register a mock auth hash for `provider` —
  # the pair every callback-driving spec needs, previously mirrored in seven of
  # them. Callers that need a non-default hash shape can still reach for
  # mock_oidc_success/mock_entra_success/etc. directly.
  #
  # uid defaults to a fresh random value, used for BOTH uid and raw_info.sub
  # (the copies in omniauth_domain_restriction_spec.rb generated the fallback
  # twice, so uid and sub disagreed for every example that omitted uid).
  #
  # Pair with teardown_mock_auth in an ensure block, or let the :omniauth_mock
  # tag's after hook (reset_omniauth_config) handle it.
  def setup_mock_auth(email:, uid: nil, provider: :oidc, name: 'Test User')
    enable_omniauth_test_mode
    mock_oidc_success(
      email: email,
      name: name,
      uid: uid || "test-uid-#{SecureRandom.hex(8)}",
      provider: provider,
    )
  end

  # Drive the SSO callback for a mocked IdP assertion and return the response.
  #
  # Unauthenticated by default — the plain sign-in path. A caller that needs the
  # AUTHENTICATED (connect-intent) variant logs in first; the mock and the POST
  # are the same either way.
  def sso_callback(email:, uid:, provider: :oidc)
    setup_mock_auth(email: email, uid: uid, provider: provider)
    clear_body_headers
    post "/auth/sso/#{provider}/callback"
    last_response
  end

  # Leaves session[:validated_omniauth_domain_id] nil == the PLATFORM path, and
  # lets a non-tenant callback proceed on platform credentials instead of
  # redirecting to sso_not_configured.
  def enable_platform_fallback
    allow(Onetime.auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(true)
  end

  # Deep-clone OT.conf before mutating: the stub must not leak the domain list
  # into the next example through the shared config object.
  def configure_allowed_domains(domains)
    config = Marshal.load(Marshal.dump(OT.conf))
    config['site'] ||= {}
    config['site']['authentication'] ||= {}
    config['site']['authentication']['allowed_signup_domains'] = domains
    allow(OT).to receive(:conf).and_return(config)
  end

  # Assert the callback bounced to the SPA sign-in page carrying `code`, which
  # is how every refusal in the OmniAuth callback chain surfaces.
  def expect_auth_error_redirect(code)
    expect(last_response.status).to eq(302),
      "Expected 302 redirect for #{code}, got #{last_response.status}: #{last_response.body}"
    expect(last_response.location.to_s).to include("/signin?auth_error=#{code}"),
      "Expected auth_error=#{code} in Location, got: #{last_response.location.inspect}"
  end

  # Leave OmniAuth out of test mode with no mocks registered. Narrower than
  # reset_omniauth_config on purpose: it does not touch allowed_request_methods,
  # so a spec that tears down mid-example can set up again without re-enabling
  # GET callbacks.
  def teardown_mock_auth
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth.clear
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
#
# AUTH_SPEC_TREE comes from apps/web/auth/spec/spec_helper.rb, which defines it
# before requiring this file; see the HOOK SCOPE block there. It keeps the
# `type: :integration` pair below off the 17 spec files outside this tree that
# declare the same type — WebMock.allow_net_connect! is process-global, so an
# unscoped after-hook would re-enable real network access for every subsequent
# example in a merged rspec process.
RSpec.configure do |config|
  config.include OmniAuthTestHelper, file_path: AUTH_SPEC_TREE

  # Re-stub OIDC discovery for tests tagged with :omniauth_mock
  # Ensures stubs are fresh after any WebMock.reset!
  config.before(:each, :omniauth_mock, file_path: AUTH_SPEC_TREE) do
    stub_oidc_discovery

    # OIDC request-phase traffic now runs through the pinned Net::HTTP adapter
    # installed by Auth::OidcHttpPinning (OpenIDConnect.http_config), which
    # resolves the issuer host itself before dialing. That lookup is real DNS
    # inside the adapter block, below the level WebMock intercepts, so the
    # placeholder issuer (an unresolvable .invalid host) makes the guard raise
    # and the request phase redirect to /signin?auth_error=sso_failed.
    #
    # Stub the resolver seam, not the guard: validation and pinning still run
    # for real, and WebMock serves the stubbed discovery response as before.
    allow(Onetime::Http::Guard).to receive(:resolve_addresses).and_return(['203.0.113.10'])
  end

  config.after(:each, :omniauth_mock, file_path: AUTH_SPEC_TREE) do
    reset_omniauth_config
  end

  # Ensure WebMock allows localhost for integration tests
  config.before(:each, type: :integration, file_path: AUTH_SPEC_TREE) do
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  config.after(:each, type: :integration, file_path: AUTH_SPEC_TREE) do
    WebMock.allow_net_connect!
  end
end
