# apps/web/auth/spec/unit/omniauth_tenant_helpers_spec.rb
#
# frozen_string_literal: true

# Unit tests for OmniAuthTenant HELPERS module methods
#
# Issue: #2786 - Per-domain SSO credential injection
#
# These tests verify the credential injection, strategy matching,
# options merging, and OIDC memoization clearing logic in isolation.
# No Valkey, no HTTP -- pure Ruby method testing with doubles.
#
# Run:
#   pnpm run test:rspec apps/web/auth/spec/unit/omniauth_tenant_helpers_spec.rb

require_relative '../spec_helper'

# Define the Auth::Config namespace (normally provided by auth app boot).
# Auth::Config MUST be a Rodauth::Auth subclass here, never a plain
# `module Config` or `class Config`: if this file is ever loaded in a process
# that also boots the real app, the application registry reopens
# `class Config < Rodauth::Auth`. A plain module/class fixes the constant to the
# wrong type, so the reopen raises a TypeError ("Config is not a class") and boot
# is marked permanently not-ready for every later spec in the process.
require 'rodauth'

# Load the OmniAuth strategy classes the verifying doubles below reference.
# This spec deliberately skips the app boot, so nothing else in the process
# pulls the provider gems in; without these requires every
# `instance_double(OmniAuth::Strategies::X)` raises NameError.
require 'omniauth_openid_connect'
require 'omniauth-entra-id'
require 'omniauth-github'
require 'omniauth-google-oauth2'

module Auth; end
Auth.const_set(:Config, Class.new(Rodauth::Auth)) unless defined?(Auth::Config)
Auth::Config.const_set(:Hooks, Module.new) unless Auth::Config.const_defined?(:Hooks, false)

# Require Auth::Logging (used by the hook for audit events)
require_relative '../../lib/logging'

# Require the hook module under test
require_relative '../../config/hooks/omniauth_tenant'

# The model + fixtures, for the provider-type tripwire and the SAML arm (#4450)
require 'onetime/models/custom_domain/sso_config'
require_relative '../support/domain_sso_test_fixtures'

RSpec.describe Auth::Config::Hooks::OmniAuthTenant do
  let(:helpers) { described_class }

  # Stub Auth::Logging globally -- these are unit tests, not audit tests
  before do
    allow(Auth::Logging).to receive(:log_auth_event)
  end

  # ==========================================================================
  # strategy_matches?
  # ==========================================================================

  describe '.strategy_matches?' do
    context 'with a matching strategy class' do
      it 'returns true for OpenIDConnect strategy matched to :openid_connect' do
        strategy = instance_double(OmniAuth::Strategies::OpenIDConnect)
        allow(strategy).to receive_message_chain(:class, :name).and_return('OmniAuth::Strategies::OpenIDConnect')

        expect(helpers.strategy_matches?(strategy, :openid_connect)).to be true
      end

      it 'returns true for EntraId strategy matched to :entra_id' do
        strategy = instance_double(OmniAuth::Strategies::EntraId)
        allow(strategy).to receive_message_chain(:class, :name).and_return('OmniAuth::Strategies::EntraId')

        expect(helpers.strategy_matches?(strategy, :entra_id)).to be true
      end

      it 'returns true for AzureActivedirectoryV2 (legacy Entra alias)' do
        # rubocop:disable RSpec/VerifiedDoubleReference -- the legacy alias
        # constant no longer exists in the entra-id gem; the string form
        # deliberately skips verification.
        strategy = instance_double('OmniAuth::Strategies::AzureActivedirectoryV2')
        # rubocop:enable RSpec/VerifiedDoubleReference
        allow(strategy).to receive_message_chain(:class, :name).and_return('OmniAuth::Strategies::AzureActivedirectoryV2')

        expect(helpers.strategy_matches?(strategy, :entra_id)).to be true
      end

      it 'returns true for GoogleOauth2 strategy' do
        strategy = instance_double(OmniAuth::Strategies::GoogleOauth2)
        allow(strategy).to receive_message_chain(:class, :name).and_return('OmniAuth::Strategies::GoogleOauth2')

        expect(helpers.strategy_matches?(strategy, :google_oauth2)).to be true
      end

      it 'returns true for GitHub strategy' do
        strategy = instance_double(OmniAuth::Strategies::GitHub)
        allow(strategy).to receive_message_chain(:class, :name).and_return('OmniAuth::Strategies::GitHub')

        expect(helpers.strategy_matches?(strategy, :github)).to be true
      end
    end

    # #4450. Compared by class NAME, so neither this spec nor the hook loads
    # omniauth-saml.
    context 'with SAML' do
      def strategy_named(name)
        double(name).tap { |s| allow(s).to receive_message_chain(:class, :name).and_return(name) }
      end

      it 'returns true for the request-bound subclass' do
        strategy = strategy_named('OmniAuth::Strategies::RequestBoundSAML')

        expect(helpers.strategy_matches?(strategy, :request_bound_saml)).to be true
      end

      # Every SAML-specific gate lives in the subclass. Tenant trust anchors
      # injected into the gem's own strategy would run with none of them.
      it 'returns false for the plain omniauth-saml strategy' do
        strategy = strategy_named('OmniAuth::Strategies::SAML')

        expect(helpers.strategy_matches?(strategy, :request_bound_saml)).to be false
      end
    end

    # Drift tripwire. A provider type whose :strategy has no entry here
    # validates, saves, renders its button — and then 400s provider_mismatch
    # on every login.
    context 'with every configurable tenant provider type' do
      it 'has a STRATEGY_CLASS_MAP entry for the strategy the model dispatches' do
        trio = {
          idp_sso_service_url: 'https://idp.example.com/saml/sso',
          idp_entity_id: 'https://idp.example.com/saml/metadata',
          idp_cert: DomainSsoTestFixtures.saml_cert_pem,
        }

        strategies = Onetime::CustomDomain::SsoConfig::PROVIDER_TYPES.map do |provider_type|
          config = Onetime::CustomDomain::SsoConfig.new(domain_id: 'dom_tripwire', provider_type: provider_type)
          allow(config).to receive_messages(custom_domain: double(extid: 'cd_tripwire'), saml_trio: trio)
          config.to_omniauth_options[:strategy]
        end

        expect(strategies - described_class::STRATEGY_CLASS_MAP.keys).to eq([])
      end
    end

    context 'with a mismatched strategy class' do
      it 'returns false when Google credentials target an OIDC strategy' do
        strategy = instance_double(OmniAuth::Strategies::OpenIDConnect)
        allow(strategy).to receive_message_chain(:class, :name).and_return('OmniAuth::Strategies::OpenIDConnect')

        expect(helpers.strategy_matches?(strategy, :google_oauth2)).to be false
      end

      it 'returns false when Entra credentials target a GitHub strategy' do
        strategy = instance_double(OmniAuth::Strategies::GitHub)
        allow(strategy).to receive_message_chain(:class, :name).and_return('OmniAuth::Strategies::GitHub')

        expect(helpers.strategy_matches?(strategy, :entra_id)).to be false
      end
    end

    context 'with nil or missing inputs' do
      it 'returns false when strategy is nil' do
        expect(helpers.strategy_matches?(nil, :openid_connect)).to be false
      end

      it 'returns false when expected_type is nil' do
        strategy = instance_double(OmniAuth::Strategies::OpenIDConnect)
        allow(strategy).to receive_message_chain(:class, :name).and_return('OmniAuth::Strategies::OpenIDConnect')

        expect(helpers.strategy_matches?(strategy, nil)).to be false
      end

      it 'returns false when both are nil' do
        expect(helpers.strategy_matches?(nil, nil)).to be false
      end

      it 'returns false for an unknown expected_type symbol' do
        strategy = instance_double(OmniAuth::Strategies::OpenIDConnect)
        allow(strategy).to receive_message_chain(:class, :name).and_return('OmniAuth::Strategies::OpenIDConnect')

        expect(helpers.strategy_matches?(strategy, :saml)).to be false
      end
    end
  end

  # ==========================================================================
  # canonical_domain?
  # ==========================================================================

  # ==========================================================================
  # public_host
  # ==========================================================================

  describe '.public_host' do
    # The regression this method exists for: behind Approximated (and any
    # Host-rewriting proxy) request.host is the origin target while the
    # browser's custom domain rides in env['onetime.display_domain'], so a
    # tenant lookup keyed on request.host misses and the SSO POST 302s to
    # auth_error=sso_not_configured.
    def request_double(host:, display_domain:, detected_host: nil)
      env = {}
      env['onetime.display_domain'] = display_domain unless display_domain.nil?
      env[Rack::DetectHost.result_field_name] = detected_host unless detected_host.nil?
      instance_double(Rack::Request, host: host, env: env)
    end

    it 'prefers the display domain over a rewritten Host header' do
      request = request_double(host: 'nz.onetime.co', display_domain: 'nz.metalbaum.com')

      expect(helpers.public_host(request)).to eq('nz.metalbaum.com')
    end

    it 'falls back to request.host when the middleware did not run' do
      request = request_double(host: 'example.com', display_domain: nil)

      expect(helpers.public_host(request)).to eq('example.com')
    end

    it 'falls back to request.host when the display domain is blank' do
      request = request_double(host: 'example.com', display_domain: '')

      expect(helpers.public_host(request)).to eq('example.com')
    end

    # The second half of the same regression: DomainStrategy pins
    # display_domain to the CANONICAL host whenever the domains feature is off
    # (it never classifies the request at all) or a detected host fails
    # validation. Reading that as the public host makes every custom-domain
    # lookup miss — and, because the setup hook then exits early, makes
    # before_omniauth_callback_route skip tenant validation wholesale. Only
    # DetectHost's result still holds the host the browser used.
    context 'when DomainStrategy pinned the display domain to the canonical host' do
      before do
        allow(Onetime::Middleware::DomainStrategy)
          .to receive(:canonical_host?) { |host| host.to_s == 'onetimesecret.com' }
      end

      it 'reads the detected host rather than the canonical pin' do
        request = request_double(
          host: 'onetimesecret.com',
          display_domain: 'onetimesecret.com',
          detected_host: 'nz.metalbaum.com',
        )

        expect(helpers.public_host(request)).to eq('nz.metalbaum.com')
      end

      # Rack 3.2's request.host prefers X-Forwarded-Host/Forwarded from ANY
      # client; DetectHost honors them only behind trusted infrastructure, so
      # it is the fallback and request.host is merely the no-middleware floor.
      it 'still prefers a resolved display domain over the detected host' do
        request = request_double(
          host: 'nz.onetime.co',
          display_domain: 'nz.metalbaum.com',
          detected_host: 'spoofed.example.com',
        )

        expect(helpers.public_host(request)).to eq('nz.metalbaum.com')
      end

      it 'falls back to request.host when DetectHost did not run either' do
        request = request_double(host: 'example.com', display_domain: 'onetimesecret.com')

        expect(helpers.public_host(request)).to eq('example.com')
      end
    end
  end

  describe '.canonical_domain?' do
    it 'returns false for an empty host' do
      expect(helpers.canonical_domain?('')).to be false
    end

    # Split deployment: site.host serves the app while
    # features.domains.default anchors generated links. Both hosts are
    # canonical to the DomainStrategy middleware, so the auth hook must
    # agree — otherwise SSO initiation on site.host resolves as a tenant
    # request and dead-ends in handle_missing_tenant_config.
    context 'with a split-deployment canonical set' do
      before do
        require 'onetime/middleware/domain_strategy'

        allow(OT).to receive(:conf).and_return(
          {
            'site' => { 'host' => 'api.example.com' },
            'features' => { 'domains' => { 'enabled' => true, 'default' => 'secrets.example.com' } },
          },
        )
        Onetime::Middleware::DomainStrategy.reset!
        Onetime::Middleware::DomainStrategy.initialize_from_config(
          { 'enabled' => true, 'default' => 'secrets.example.com' },
        )
      end

      after do
        Onetime::Middleware::DomainStrategy.reset!
      end

      it 'treats site.host as canonical' do
        expect(helpers.canonical_domain?('api.example.com')).to be true
      end

      it 'treats the default link domain as canonical' do
        expect(helpers.canonical_domain?('secrets.example.com')).to be true
      end

      it 'rejects a host outside the canonical set' do
        expect(helpers.canonical_domain?('tenant.example.org')).to be false
      end
    end
  end

  # ==========================================================================
  # merge_strategy_options
  # ==========================================================================

  describe '.merge_strategy_options' do
    let(:options_hash) { {} }
    let(:strategy) do
      double('strategy').tap do |s|
        allow(s).to receive(:options).and_return(options_hash)
      end
    end

    context 'with flat options' do
      it 'writes simple key/value pairs into strategy.options' do
        helpers.merge_strategy_options(strategy, { issuer: 'https://idp.example.com', pkce: true })

        expect(options_hash[:issuer]).to eq('https://idp.example.com')
        expect(options_hash[:pkce]).to be true
      end
    end

    # #4450. omniauth-saml builds ruby-saml Settings WITHOUT
    # keep_security_attributes, so whatever :security hash the strategy holds
    # REPLACES ruby-saml's defaults and every absent key reads as nil. The
    # tenant arm always supplies the FULL hash; replacement (not a key-by-key
    # merge) is what guarantees the strategy ends up with exactly that set.
    context 'with a nested SAML security hash' do
      let(:registered_security) do
        { want_assertions_signed: false, digest_method: 'sha1', registered_only_key: true }
      end
      let(:options_hash) { { security: registered_security } }

      it 'replaces the registered hash wholesale with the full tenant hash' do
        full = Onetime::SsoProvider::Saml::SECURITY.dup

        helpers.merge_strategy_options(strategy, { security: full })

        expect(options_hash[:security]).to eq(full)
        expect(options_hash[:security]).not_to have_key(:registered_only_key)
        expect(options_hash[:security][:want_assertions_signed]).to be true
      end

      it 'does not mutate the shared frozen constant' do
        helpers.merge_strategy_options(strategy, Onetime::SsoProvider::Saml.hardened_options)

        expect(options_hash[:security]).not_to be(Onetime::SsoProvider::Saml::SECURITY)
        expect(Onetime::SsoProvider::Saml::SECURITY).to be_frozen
      end
    end

    context 'with nested client_options' do
      it 'deep-merges client_options into strategy.options[:client_options]' do
        helpers.merge_strategy_options(
          strategy,
          {
            client_options: { identifier: 'my-client', secret: 'my-secret' },
          },
        )

        expect(options_hash[:client_options][:identifier]).to eq('my-client')
        expect(options_hash[:client_options][:secret]).to eq('my-secret')
      end

      it 'preserves existing client_options keys not in the merge' do
        options_hash[:client_options] = { host: 'existing.example.com' }

        helpers.merge_strategy_options(
          strategy,
          {
            client_options: { identifier: 'new-client' },
          },
        )

        expect(options_hash[:client_options][:host]).to eq('existing.example.com')
        expect(options_hash[:client_options][:identifier]).to eq('new-client')
      end

      it 'overwrites conflicting client_options keys' do
        options_hash[:client_options] = { identifier: 'old-client', secret: 'old-secret' }

        helpers.merge_strategy_options(
          strategy,
          {
            client_options: { identifier: 'new-client' },
          },
        )

        expect(options_hash[:client_options][:identifier]).to eq('new-client')
        expect(options_hash[:client_options][:secret]).to eq('old-secret')
      end

      it 'initializes client_options hash when it does not exist' do
        helpers.merge_strategy_options(
          strategy,
          {
            client_options: { identifier: 'first-client' },
          },
        )

        expect(options_hash[:client_options]).to be_a(Hash)
        expect(options_hash[:client_options][:identifier]).to eq('first-client')
      end
    end

    context 'with mixed flat and nested options' do
      it 'handles both in a single call' do
        helpers.merge_strategy_options(
          strategy,
          {
            issuer: 'https://idp.example.com',
            discovery: true,
            client_options: { identifier: 'cid', secret: 'csecret' },
          },
        )

        expect(options_hash[:issuer]).to eq('https://idp.example.com')
        expect(options_hash[:discovery]).to be true
        expect(options_hash[:client_options][:identifier]).to eq('cid')
        expect(options_hash[:client_options][:secret]).to eq('csecret')
      end
    end
  end

  # ==========================================================================
  # clear_oidc_memoization
  # ==========================================================================

  describe '.clear_oidc_memoization' do
    context 'when strategy has discovery enabled' do
      let(:strategy) do
        obj = Object.new
        obj.instance_variable_set(:@config, { some: 'cached_config' })
        obj.instance_variable_set(:@client, double('OpenIDConnect::Client'))

        # Provide an options hash with discovery: true
        opts = { discovery: true }
        obj.define_singleton_method(:options) { opts }
        obj.define_singleton_method(:respond_to?) { |m, *| m == :options ? true : super(m) }
        obj
      end

      it 'clears @config instance variable' do
        helpers.clear_oidc_memoization(strategy)
        expect(strategy.instance_variable_get(:@config)).to be_nil
      end

      it 'clears @client instance variable' do
        helpers.clear_oidc_memoization(strategy)
        expect(strategy.instance_variable_get(:@client)).to be_nil
      end
    end

    context 'when strategy does not have discovery enabled' do
      let(:strategy) do
        obj  = Object.new
        obj.instance_variable_set(:@config, { some: 'data' })
        obj.instance_variable_set(:@client, double('client'))
        opts = { discovery: false }
        obj.define_singleton_method(:options) { opts }
        obj
      end

      it 'does not clear @config' do
        helpers.clear_oidc_memoization(strategy)
        expect(strategy.instance_variable_get(:@config)).not_to be_nil
      end

      it 'does not clear @client' do
        helpers.clear_oidc_memoization(strategy)
        expect(strategy.instance_variable_get(:@client)).not_to be_nil
      end
    end

    context 'when strategy has no memoized ivars' do
      let(:strategy) do
        obj  = Object.new
        opts = { discovery: true }
        obj.define_singleton_method(:options) { opts }
        obj
      end

      it 'does not raise' do
        expect { helpers.clear_oidc_memoization(strategy) }.not_to raise_error
      end
    end

    context 'when strategy does not respond to options' do
      let(:strategy) { Object.new }

      it 'does not raise' do
        expect { helpers.clear_oidc_memoization(strategy) }.not_to raise_error
      end
    end
  end

  # ==========================================================================
  # platform SAML fallback
  # ==========================================================================

  describe '.handle_missing_tenant_config with platform SAML' do
    let(:options) do
      {
        name: 'saml',
        sp_entity_id: 'urn:example:platform-sp',
        assertion_consumer_service_url: 'https://canonical.example/auth/sso/saml/callback',
        idp_entity_id: 'https://platform-idp.example/metadata',
        idp_cert: 'PLATFORM CERT',
      }
    end
    let(:strategy) do
      double('OmniAuth::Strategies::RequestBoundSAML').tap do |s|
        allow(s).to receive_message_chain(:class, :name).and_return('OmniAuth::Strategies::RequestBoundSAML')
        allow(s).to receive_messages(
          options: options,
          full_host: 'https://tenant.example',
          callback_path: '/auth/sso/saml/callback',
          on_request_path?: true,
        )
      end
    end
    let(:request) { double('Rack::Request', env: { 'omniauth.strategy' => strategy }) }
    let(:session) do
      {
        omniauth_tenant_domain_id: 'stale-domain-id',
        omniauth_tenant_host: 'tenant.example',
      }
    end
    let(:rodauth) do
      double('Rodauth', session: session).tap do |r|
        allow(r).to receive(:redirect) { throw :halt }
      end
    end

    before do
      allow(Onetime.auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(true)
      allow(Onetime::CustomDomain::SigninConfig).to receive(:global_auth_enabled).and_return(true)
    end

    it 'overrides only ACS for a verified custom-domain fallback' do
      allow(Auth::PublicHost).to receive(:resolve).with(request.env).and_return('tenant.example')

      result = catch(:halt) do
        helpers.handle_missing_tenant_config('tenant.example', rodauth, request: request)
        :allowed
      end

      expect(result).to eq(:allowed)
      expect(options[:assertion_consumer_service_url]).to eq('https://tenant.example/auth/sso/saml/callback')
      expect(options[:sp_entity_id]).to eq('urn:example:platform-sp')
      expect(options[:idp_entity_id]).to eq('https://platform-idp.example/metadata')
      expect(options[:idp_cert]).to eq('PLATFORM CERT')
      expect(session).not_to include(:omniauth_tenant_domain_id, :omniauth_tenant_host)
    end

    it 'retains pending tenant context during callback setup' do
      allow(strategy).to receive(:on_request_path?).and_return(false)
      allow(Auth::PublicHost).to receive(:resolve).with(request.env).and_return('tenant.example')

      result = catch(:halt) do
        helpers.handle_missing_tenant_config('tenant.example', rodauth, request: request)
        :allowed
      end

      expect(result).to eq(:allowed)
      expect(session).to include(
        omniauth_tenant_domain_id: 'stale-domain-id',
        omniauth_tenant_host: 'tenant.example',
      )
    end

    # An abandoned tenant request leaves more than the two markers behind: the
    # strategy's own request/callback binding (the pending SAML AuthnRequest
    # id, the OAuth/OIDC state). Those are STRING keys, as the strategies
    # write them; the markers are symbols. Both forms are exercised on a plain
    # Hash so a key-form drift in the hook fails here rather than only on the
    # stringifying live session.
    context 'with an abandoned tenant request binding in the session' do
      let(:session) do
        {
          omniauth_tenant_domain_id: 'stale-domain-id',
          omniauth_tenant_host: 'tenant.example',
          'saml_authn_request_id' => '_stale-authn-request-id',
          'omniauth.state' => 'stale-oauth-state',
          account_id: 42,
        }
      end

      before do
        allow(Auth::PublicHost).to receive(:resolve).with(request.env).and_return('tenant.example')
      end

      it 'supersedes the pending SAML request id and OAuth state along with the markers on the request path' do
        result = catch(:halt) do
          helpers.handle_missing_tenant_config('tenant.example', rodauth, request: request)
          :allowed
        end

        expect(result).to eq(:allowed)
        expect(session).not_to include(
          :omniauth_tenant_domain_id,
          :omniauth_tenant_host,
          'saml_authn_request_id',
          'omniauth.state',
        )
        # Only the flow is superseded; unrelated session state is untouched.
        expect(session).to eq(account_id: 42)
      end

      it 'retains the pending binding together with the markers during callback setup' do
        allow(strategy).to receive(:on_request_path?).and_return(false)

        result = catch(:halt) do
          helpers.handle_missing_tenant_config('tenant.example', rodauth, request: request)
          :allowed
        end

        expect(result).to eq(:allowed)
        expect(session).to include(
          omniauth_tenant_domain_id: 'stale-domain-id',
          omniauth_tenant_host: 'tenant.example',
          'saml_authn_request_id' => '_stale-authn-request-id',
          'omniauth.state' => 'stale-oauth-state',
        )
      end
    end

    it 'fails closed when PublicHost cannot verify the request host' do
      allow(Auth::PublicHost).to receive(:resolve).with(request.env).and_return(nil)

      catch(:halt) do
        helpers.handle_missing_tenant_config('unknown.example', rodauth, request: request)
      end

      expect(rodauth).to have_received(:redirect).with('/signin?auth_error=sso_not_configured')
      expect(options[:assertion_consumer_service_url]).to eq('https://canonical.example/auth/sso/saml/callback')
    end

    it 'does not override ACS when the explicit fallback policy denies access' do
      allow(Onetime.auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(false)
      allow(Auth::PublicHost).to receive(:resolve)

      catch(:halt) do
        helpers.handle_missing_tenant_config('tenant.example', rodauth, request: request)
      end

      expect(Auth::PublicHost).not_to have_received(:resolve)
      expect(options[:assertion_consumer_service_url]).to eq('https://canonical.example/auth/sso/saml/callback')
    end
  end

  # ==========================================================================
  # inject_tenant_credentials (integration of the above)
  # ==========================================================================

  describe '.inject_tenant_credentials' do
    let(:options_hash) { {} }

    let(:strategy) do
      double('OmniAuth::Strategies::OpenIDConnect').tap do |s|
        allow(s).to receive_message_chain(:class, :name).and_return('OmniAuth::Strategies::OpenIDConnect')
        allow(s).to receive(:options).and_return(options_hash)
        allow(s).to receive(:respond_to?).with(:options).and_return(true)
        allow(s).to receive(:instance_variable_defined?).with(:@config).and_return(false)
        allow(s).to receive(:instance_variable_defined?).with(:@client).and_return(false)
      end
    end

    let(:request) do
      double('Rack::Request').tap do |r|
        allow(r).to receive(:env).and_return({ 'omniauth.strategy' => strategy })
      end
    end

    let(:rodauth) do
      double('Rodauth').tap do |r|
        allow(r).to receive(:throw_error_status)
      end
    end

    let(:sso_config) do
      double(
        'Onetime::CustomDomain::SsoConfig',
        domain_id: 'dom_test_123',
        provider_type: 'oidc',
        to_omniauth_options: {
          strategy: :openid_connect,
          name: 'dom_test_123',
          issuer: 'https://auth.tenant.com',
          discovery: true,
          pkce: true,
          client_options: {
            identifier: 'tenant-client-id',
            secret: 'tenant-client-secret',
          },
        },
      )
    end

    it 'writes tenant credentials into strategy.options' do
      helpers.inject_tenant_credentials(sso_config, request, rodauth)

      expect(options_hash[:issuer]).to eq('https://auth.tenant.com')
      expect(options_hash[:discovery]).to be true
      expect(options_hash[:pkce]).to be true
      expect(options_hash[:client_options][:identifier]).to eq('tenant-client-id')
      expect(options_hash[:client_options][:secret]).to eq('tenant-client-secret')
    end

    it 'does not leak :strategy or :name keys into strategy.options' do
      helpers.inject_tenant_credentials(sso_config, request, rodauth)

      # :strategy and :name are consumed by inject_tenant_credentials,
      # not passed through to the strategy's runtime options
      expect(options_hash).not_to have_key(:strategy)
      expect(options_hash).not_to have_key(:name)
    end

    context 'when strategy type does not match configuration' do
      let(:mismatched_strategy) do
        double('OmniAuth::Strategies::GitHub').tap do |s|
          allow(s).to receive_message_chain(:class, :name).and_return('OmniAuth::Strategies::GitHub')
          allow(s).to receive(:options).and_return({})
        end
      end

      let(:request) do
        double('Rack::Request').tap do |r|
          allow(r).to receive(:env).and_return({ 'omniauth.strategy' => mismatched_strategy })
        end
      end

      it 'calls throw_error_status with 400 provider_mismatch' do
        helpers.inject_tenant_credentials(sso_config, request, rodauth)

        expect(rodauth).to have_received(:throw_error_status).with(
          400,
          'provider_mismatch',
          /SSO provider mismatch/,
        )
      end
    end

    context 'when no strategy is present in the request env' do
      let(:request) do
        double('Rack::Request').tap do |r|
          allow(r).to receive(:env).and_return({ 'omniauth.strategy' => nil })
        end
      end

      it 'returns early without calling throw_error_status' do
        helpers.inject_tenant_credentials(sso_config, request, rodauth)

        expect(rodauth).not_to have_received(:throw_error_status)
      end
    end

    it 'derives no SAML SP identifiers for a non-SAML strategy' do
      helpers.inject_tenant_credentials(sso_config, request, rodauth)

      expect(options_hash).not_to have_key(:sp_entity_id)
      expect(options_hash).not_to have_key(:assertion_consumer_service_url)
    end

    # ────────────────────────────────────────────────────────────────────
    # SAML (#4450)
    # ────────────────────────────────────────────────────────────────────
    context 'with a SAML tenant config' do
      # What the platform registered: a real platform SAML config, including
      # values a tenant flow must NOT inherit.
      let(:options_hash) do
        {
          idp_entity_id: 'https://platform-idp.example/metadata',
          idp_cert: 'PLATFORM CERT',
          sp_entity_id: 'https://app.example.com/auth/sso/saml/metadata',
          uid_attribute: 'platformEmployeeId',
          security: { want_assertions_signed: false },
        }
      end

      let(:strategy) do
        double('OmniAuth::Strategies::RequestBoundSAML').tap do |s|
          allow(s).to receive_message_chain(:class, :name).and_return('OmniAuth::Strategies::RequestBoundSAML')
          allow(s).to receive_messages(
            options: options_hash,
            full_host: 'https://secrets.tenant.example',
            request_path: '/auth/sso/saml',
            callback_path: '/auth/sso/saml/callback',
          )
          allow(s).to receive(:respond_to?).with(:options).and_return(true)
        end
      end

      let(:sso_config) do
        config = Onetime::CustomDomain::SsoConfig.new(domain_id: 'dom_saml_123', provider_type: 'saml')
        allow(config).to receive_messages(
          custom_domain: double(extid: 'cd_saml_123'),
          saml_trio: {
            idp_sso_service_url: 'https://idp.tenant.example/saml/sso',
            idp_entity_id: 'https://idp.tenant.example/saml/metadata',
            idp_cert: DomainSsoTestFixtures.saml_cert_pem,
          },
        )
        config
      end

      it 'replaces every platform trust anchor with the tenant trio' do
        helpers.inject_tenant_credentials(sso_config, request, rodauth)

        expect(options_hash[:idp_entity_id]).to eq('https://idp.tenant.example/saml/metadata')
        expect(options_hash[:idp_sso_service_url]).to eq('https://idp.tenant.example/saml/sso')
        expect(options_hash[:idp_cert]).to eq(DomainSsoTestFixtures.saml_cert_pem)
      end

      it 'installs the full hardened security hash over the registered one' do
        helpers.inject_tenant_credentials(sso_config, request, rodauth)

        expect(options_hash[:security]).to eq(Onetime::SsoProvider::Saml::SECURITY)
      end

      it 'does not let the platform uid_attribute leak into the tenant flow' do
        helpers.inject_tenant_credentials(sso_config, request, rodauth)

        expect(options_hash[:uid_attribute]).to be_nil
      end

      # The platform sp_entity_id names the canonical host. The tenant's IdP
      # is configured against the tenant's domain.
      it 'derives the SP identifiers from full_host (the PUBLIC host), not the registered value' do
        helpers.inject_tenant_credentials(sso_config, request, rodauth)

        expect(options_hash[:sp_entity_id]).to eq('https://secrets.tenant.example/auth/sso/saml/metadata')
        expect(options_hash[:assertion_consumer_service_url])
          .to eq('https://secrets.tenant.example/auth/sso/saml/callback')
      end

      it 'follows an operator-renamed route' do
        allow(strategy).to receive_messages(request_path: '/auth/sso/okta', callback_path: '/auth/sso/okta/callback')

        helpers.inject_tenant_credentials(sso_config, request, rodauth)

        expect(options_hash[:sp_entity_id]).to eq('https://secrets.tenant.example/auth/sso/okta/metadata')
        expect(options_hash[:assertion_consumer_service_url])
          .to eq('https://secrets.tenant.example/auth/sso/okta/callback')
      end

      it 'never sets :issuer (ruby-saml reads it as OUR SP EntityID)' do
        helpers.inject_tenant_credentials(sso_config, request, rodauth)

        expect(options_hash).not_to have_key(:issuer)
      end

      # A record that cannot produce a usable trio is REFUSED. It must not
      # reach handle_missing_tenant_config, whose platform-fallback arm would
      # run this tenant's login through the platform IdP with the tenant
      # context still pending.
      context 'when the record cannot produce usable options' do
        let(:session) { { omniauth_tenant_domain_id: 'dom_saml_123', omniauth_tenant_host: 'secrets.tenant.example' } }
        let(:rodauth) do
          double('Rodauth', session: session).tap do |r|
            allow(r).to receive(:redirect) { throw :halt }
            allow(r).to receive(:throw_error_status)
          end
        end

        before do
          allow(sso_config).to receive(:to_omniauth_options)
            .and_raise(Onetime::Problem, 'SAML SSO config for domain dom_saml_123 is unusable: IdP certificate expired on 2020-01-01')
          allow(helpers).to receive(:handle_missing_tenant_config)
        end

        # sso_config_unusable, not sso_not_configured: a record exists and is
        # advertised, so the visitor must be told it is broken, not absent.
        it 'redirects to sso_config_unusable and injects nothing' do
          before_options = options_hash.dup

          catch(:halt) { helpers.inject_tenant_credentials(sso_config, request, rodauth) }

          expect(rodauth).to have_received(:redirect).with('/signin?auth_error=sso_config_unusable')
          expect(options_hash).to eq(before_options)
        end

        it 'never consults the platform-fallback policy' do
          catch(:halt) { helpers.inject_tenant_credentials(sso_config, request, rodauth) }

          expect(helpers).not_to have_received(:handle_missing_tenant_config)
        end

        it 'clears the pending tenant context so no callback can validate against it' do
          catch(:halt) { helpers.inject_tenant_credentials(sso_config, request, rodauth) }

          expect(session).to be_empty
        end

        it 'audits at :error with scalars only' do
          catch(:halt) { helpers.inject_tenant_credentials(sso_config, request, rodauth) }

          expect(Auth::Logging).to have_received(:log_auth_event).with(
            :omniauth_tenant_config_unusable,
            level: :error,
            domain_id: 'dom_saml_123',
            provider_type: 'saml',
            error: a_string_matching(/unusable: IdP certificate expired/),
          )
        end
      end
    end
  end

  # ==========================================================================
  # inject_saml_sp_identifiers (#4450)
  # ==========================================================================

  describe '.inject_saml_sp_identifiers' do
    it 'leaves a platform (non-injected) strategy of another class untouched' do
      options  = {}
      strategy = double('OmniAuth::Strategies::OpenIDConnect', options: options)
      allow(strategy).to receive_message_chain(:class, :name).and_return('OmniAuth::Strategies::OpenIDConnect')

      helpers.inject_saml_sp_identifiers(strategy)

      expect(options).to be_empty
    end
  end
end
