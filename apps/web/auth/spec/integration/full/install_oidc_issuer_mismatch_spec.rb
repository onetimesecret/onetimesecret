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
# so the browser is never sent to the IdP. These examples pin that premise
# before anything is layered on top of it.
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
end
