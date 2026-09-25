# apps/web/auth/spec/integration/full/install_oidc_issuer_mismatch_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full Rack stack, real OIDC request phase)
# =============================================================================
#
# Install-wide OIDC (OIDC_ISSUER) whose discovery document declares a
# different issuer (#4513).
#
# OpenID Connect Discovery 1.0 §4.3 requires the discovered `issuer` to be
# IDENTICAL to the configured issuer. The classic operator mistake is a
# trailing slash: Auth0 publishes `https://tenant.auth0.com/` and the
# operator configures `https://tenant.auth0.com`.
#
# The gem stack (omniauth_openid_connect -> OpenIDConnect::Discovery) already
# compares the two exactly in the request phase and raises DiscoveryFailed,
# so the browser is never sent to the IdP. The first group pins that premise.
#
# On top of it, the omniauth_setup hook checks the install-wide issuer first
# (Auth::Config::Hooks::OmniAuthTenant.enforce_install_discovery_issuer!,
# cached in Onetime::SsoProvider::IssuerValidation): a mismatch redirects to
# /signin?auth_error=sso_issuer_mismatch and the provider stops being
# advertised, while the shared `oidc` route keeps serving tenant OIDC and
# password login is untouched.
#
# HOW INSTALL-WIDE OIDC IS SIMULATED. The full lane boots with no platform
# OIDC env, so the `oidc` route registers with placeholder options, and
# registration is one-shot per process. Each example points the registered
# strategy's options at a test issuer (and sets the matching env vars), then
# restores both. Every request dups the strategy and its options, so this is
# exactly what a boot-time OIDC_ISSUER registration looks like at request time.
#
# RUN:
#   bundle exec rake spec:integration:full
#
# =============================================================================

require_relative '../../spec_helper'
require 'webmock/rspec'
require_relative '../../support/tenant_test_fixtures'

RSpec.describe 'Install-wide OIDC discovery issuer mismatch', type: :integration do
  include Rack::Test::Methods

  before(:all) { boot_onetime_app }

  # Installs a parseable canonical host so the request classifies as the
  # platform (canonical-domain) path deterministically; provides
  # `canonical_host`.
  include_context 'domains enabled'

  let(:idp_host) { "idp-#{SecureRandom.hex(4)}.example.com" }
  let(:configured_issuer) { "https://#{idp_host}" }
  let(:discovery_url) { "https://#{idp_host}/.well-known/openid-configuration" }

  def discovery_document(issuer)
    {
      issuer: issuer,
      authorization_endpoint: "https://#{idp_host}/authorize",
      token_endpoint: "https://#{idp_host}/oauth/token",
      userinfo_endpoint: "https://#{idp_host}/userinfo",
      jwks_uri: "https://#{idp_host}/.well-known/jwks.json",
      response_types_supported: %w[code],
      subject_types_supported: %w[public],
      id_token_signing_alg_values_supported: %w[RS256],
    }.to_json
  end

  def stub_discovery(issuer)
    stub_request(:get, discovery_url).to_return(
      status: 200,
      body: discovery_document(issuer),
      headers: { 'Content-Type' => 'application/json' },
    )
  end

  # The boot-registered OmniAuth::Strategies::OpenIDConnect instance for the
  # `oidc` route. OmniAuth::Builder chains strategies through @app.
  def registered_oidc_strategy
    app = Auth::Config.allocate.omniauth_app
    while app
      return app if app.is_a?(OmniAuth::Strategy) && app.options[:name].to_s == 'oidc'

      app = app.instance_variable_get(:@app)
    end
    raise 'oidc strategy not registered'
  end

  let(:client_secret) { "install-secret-#{SecureRandom.hex(8)}" }

  before do
    skip 'ORGS_SSO_ENABLED not set at boot — /auth/sso/oidc is not registered' unless Onetime.auth_config.orgs_sso_enabled?

    # Real Guard validation and pinning; only DNS is stubbed (WebMock does not
    # intercept Resolv).
    allow(Onetime::Http::Guard).to receive(:resolve_addresses).and_return(['203.0.113.10'])

    strategy                                       = registered_oidc_strategy
    @saved_options                                 = { issuer: strategy.options[:issuer], client_options: strategy.options[:client_options].to_h }
    @saved_env                                     = %w[OIDC_ISSUER OIDC_CLIENT_ID OIDC_CLIENT_SECRET].to_h { |k| [k, ENV.fetch(k, nil)] }
    strategy.options[:issuer]                      = configured_issuer
    strategy.options[:client_options][:identifier] = 'install-client-id'
    ENV['OIDC_ISSUER']                             = configured_issuer
    ENV['OIDC_CLIENT_ID']                          = 'install-client-id'
    ENV.delete('OIDC_CLIENT_SECRET')
  end

  after do
    if @saved_options
      strategy                          = registered_oidc_strategy
      strategy.options[:issuer]         = @saved_options[:issuer]
      strategy.options[:client_options] = @saved_options[:client_options]
    end
    @saved_env&.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    Onetime::SsoProvider::IssuerValidation.reset!
  end

  def start_sso
    header 'Host', canonical_host
    post '/auth/sso/oidc'
    last_response.headers['Location'].to_s
  end

  describe 'premise: the gem stack already refuses a mismatched issuer' do
    it 'redirects to the IdP when the discovered issuer matches exactly (control)' do
      stub_discovery(configured_issuer)

      expect(start_sso).to start_with("https://#{idp_host}/authorize")
    end

    it 'does not redirect to the IdP when discovery differs only by a trailing slash' do
      stub_discovery("#{configured_issuer}/")

      location = start_sso

      expect(last_response.status).to eq(302)
      expect(location).not_to include(idp_host)
      expect(location).to include('/signin?auth_error=')
    end
  end

  describe 'request-phase issuer check' do
    # The REAL AuthConfig gate (Onetime.auth_config is AuthModeHelpers'
    # MockAuthConfig in this lane, whose sso_providers is canned). An
    # allocated instance reads only the registry and ENV here; platform SSO is
    # switched on for the read because the lane runs with it off.
    let(:real_auth_config) do
      Onetime::AuthConfig.send(:allocate).tap do |config|
        allow(config).to receive(:sso_enabled?).and_return(true)
      end
    end

    def advertised_routes
      real_auth_config.sso_providers.map { |p| p['route_name'] }
    end

    it 'redirects a trailing-slash mismatch to sso_issuer_mismatch' do
      stub_discovery("#{configured_issuer}/")

      location = start_sso

      expect(last_response.status).to eq(302)
      expect(location).to end_with('/signin?auth_error=sso_issuer_mismatch')
      expect(location).not_to include(idp_host)
    end

    it 'logs both issuers and never the client secret' do
      stub_discovery("#{configured_issuer}/")
      logged = []
      allow(Auth::Logging).to receive(:log_auth_event).and_wrap_original do |original, event, **payload|
        logged << [event, payload]
        original.call(event, **payload)
      end

      start_sso

      mismatch = logged.find { |event, _| event == :omniauth_install_issuer_mismatch }
      expect(mismatch).not_to be_nil
      expect(mismatch.last).to include(
        level: :error,
        provider: 'oidc',
        configured_issuer: configured_issuer,
        discovered_issuer: "#{configured_issuer}/",
        reason: :mismatch,
      )
      expect(logged.inspect).not_to include(client_secret)
    end

    it 'treats a missing discovery issuer as a mismatch' do
      stub_request(:get, discovery_url).to_return(
        status: 200,
        body: { authorization_endpoint: "https://#{idp_host}/authorize" }.to_json,
        headers: { 'Content-Type' => 'application/json' },
      )

      expect(start_sso).to end_with('/signin?auth_error=sso_issuer_mismatch')
    end

    it 'stops advertising the provider once the mismatch is known' do
      stub_discovery("#{configured_issuer}/")

      expect(advertised_routes).to include('oidc') # lazy: unknown until the first attempt
      start_sso
      expect(advertised_routes).not_to include('oidc')
      # Display only: the HttpOrigin callback origins ignore the verdict.
      expect(real_auth_config.sso_idp_origins).to include(configured_issuer)
    end

    it 'answers repeat attempts from the cached verdict without refetching' do
      stub_discovery("#{configured_issuer}/")

      start_sso
      expect(start_sso).to end_with('/signin?auth_error=sso_issuer_mismatch')

      expect(a_request(:get, discovery_url)).to have_been_made.once
    end

    it 'keeps an exact match working and advertised' do
      stub_discovery(configured_issuer)

      expect(start_sso).to start_with("https://#{idp_host}/authorize")
      expect(advertised_routes).to include('oidc')
    end

    it 'does not treat a failed discovery fetch as a mismatch' do
      stub_request(:get, discovery_url).to_return(status: 503, body: 'unavailable')

      location = start_sso

      expect(location).not_to include('sso_issuer_mismatch')
      expect(location).to include('/signin?auth_error=') # the gem's own failure path
      expect(advertised_routes).to include('oidc')
    end

    it 'does not check the placeholder registration (no OIDC_ISSUER)' do
      ENV.delete('OIDC_ISSUER')
      stub_discovery("#{configured_issuer}/")

      start_sso

      expect(last_response.headers['Location'].to_s).not_to include('sso_issuer_mismatch')
      expect(Onetime::SsoProvider::IssuerValidation.cached_verdict(configured_issuer)).to be_nil
    end

    it 'leaves password login working while the mismatch is cached' do
      stub_discovery("#{configured_issuer}/")
      start_sso
      expect(Onetime::SsoProvider::IssuerValidation.rejected?(configured_issuer)).to be(true)

      email = unique_test_email('issuer-mismatch')
      seed_account_with_password(email)
      header 'Host', canonical_host
      csrf_login(email)

      expect(last_response.status).to be_between(200, 302)
    end
  end

  describe 'check scope (Auth::Config::Hooks::OmniAuthTenant)' do
    let(:helpers) { Auth::Config::Hooks::OmniAuthTenant }
    let(:fake_strategy) { Struct.new(:name, :options) }

    it 'checks the boot-registered install-wide options' do
      strategy = fake_strategy.new('oidc', { discovery: true, issuer: configured_issuer })

      expect(helpers.install_discovery_issuer_to_check(strategy)).to eq(configured_issuer)
    end

    it 'skips tenant-injected options (a different issuer on the same route)' do
      strategy = fake_strategy.new('oidc', { discovery: true, issuer: 'https://tenant.example.com' })

      expect(helpers.install_discovery_issuer_to_check(strategy)).to be_nil
    end

    it 'skips a strategy without discovery' do
      strategy = fake_strategy.new('oidc', { discovery: false, issuer: configured_issuer })

      expect(helpers.install_discovery_issuer_to_check(strategy)).to be_nil
    end

    it 'skips routes whose definition declares no discovery issuer' do
      strategy = fake_strategy.new('entra', { discovery: true, issuer: configured_issuer })

      expect(helpers.install_discovery_issuer_to_check(strategy)).to be_nil
    end

    it 'skips the placeholder issuer even if OIDC_ISSUER names it' do
      placeholder         = Onetime::SsoProvider::Oidc::DEFINITION.dig(:placeholder_options, :issuer)
      ENV['OIDC_ISSUER']  = placeholder
      strategy            = fake_strategy.new('oidc', { discovery: true, issuer: placeholder })

      expect(helpers.install_discovery_issuer_to_check(strategy)).to be_nil
    end

    it 'fails open (no verdict, no raise) when the check itself errors' do
      strategy = fake_strategy.new('oidc', { discovery: true, issuer: configured_issuer })
      allow(Onetime::SsoProvider::IssuerValidation).to receive(:verify).and_raise(RuntimeError, 'boom')
      allow(Auth::Logging).to receive(:log_auth_event)

      expect(helpers.install_discovery_issuer_verdict(strategy)).to be_nil
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:omniauth_install_issuer_check_error, hash_including(error_class: 'RuntimeError'))
    end
  end

  # Tenant OIDC shares the `oidc` route with the install-wide provider
  # (SsoConfig::PROVIDER_ROUTE_MAP). A cached install-wide rejection must not
  # touch it: the hook only checks the platform path, and the tenant's
  # injected issuer is never the install-wide one.
  describe 'tenant OIDC on the shared route', :shared_db_state do
    let(:tenant_idp_host) { "tenant-idp-#{SecureRandom.hex(4)}.example.com" }
    let(:tenant_issuer) { "https://#{tenant_idp_host}" }

    include_context 'tenant fixtures'

    let!(:test_sso_config) do
      Onetime::CustomDomain::SsoConfig.create!(
        domain_id: test_custom_domain.identifier,
        provider_type: 'oidc',
        display_name: 'Tenant OIDC',
        issuer: tenant_issuer,
        client_id: "client-#{test_run_id}",
        client_secret: "secret-#{test_run_id}",
        enabled: true,
      )
    end

    it 'still redirects to the tenant IdP while the install-wide issuer is rejected' do
      stub_discovery("#{configured_issuer}/")
      start_sso
      expect(Onetime::SsoProvider::IssuerValidation.rejected?(configured_issuer)).to be(true)

      stub_request(:get, "#{tenant_issuer}/.well-known/openid-configuration").to_return(
        status: 200,
        body: {
          issuer: tenant_issuer,
          authorization_endpoint: "#{tenant_issuer}/authorize",
          token_endpoint: "#{tenant_issuer}/token",
          jwks_uri: "#{tenant_issuer}/jwks",
          response_types_supported: %w[code],
          subject_types_supported: %w[public],
          id_token_signing_alg_values_supported: %w[RS256],
        }.to_json,
        headers: { 'Content-Type' => 'application/json' },
      )

      header 'Host', tenant_domain
      post '/auth/sso/oidc'

      expect(last_response.headers['Location'].to_s).to start_with("#{tenant_issuer}/authorize")
    end
  end
end
