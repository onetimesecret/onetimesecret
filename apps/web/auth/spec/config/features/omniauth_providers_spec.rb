# apps/web/auth/spec/config/features/omniauth_providers_spec.rb
#
# frozen_string_literal: true

# Tests for provider registration methods in Auth::Config::Features::OmniAuth.
#
# Each configure_X_provider method reads env vars, validates required ones,
# and either:
#   - registers with real credentials (env vars present)
#   - registers with placeholders for tenant SSO (env vars absent, orgs_sso_enabled)
#   - logs error and skips (env vars absent, orgs_sso not enabled)
#
# RUN:
#   source .env.test && pnpm run test:rspec apps/web/auth/spec/config/features/omniauth_providers_spec.rb

require 'rspec'
require 'climate_control'
require_relative '../../../../../../spec/support/saml/test_idp'

# Define the Auth::Config namespace so the feature module can load without a full
# app boot. Auth::Config MUST be a Rodauth::Auth subclass here, never a plain
# `module Config` or `class Config`: if this file is ever loaded in a process
# that also boots the real app, the application registry reopens
# `class Config < Rodauth::Auth`. A plain module/class fixes the constant to the
# wrong type, so the reopen raises a TypeError ("Config is not a class") and boot
# is marked permanently not-ready for every later spec in the process.
require 'rodauth'
module Auth; end
Auth.const_set(:Config, Class.new(Rodauth::Auth)) unless defined?(Auth::Config)
Auth::Config.const_set(:Features, Module.new) unless Auth::Config.const_defined?(:Features, false)

RSpec.describe 'Auth::Config::Features::OmniAuth provider registration' do
  # Stub namespaces and logger before loading the module
  before(:all) do
    unless defined?(OT)
      module ::OT
        def self.li(*args); end
        def self.le(*args); end
        def self.conf; end
      end
    end

    unless defined?(Onetime)
      module ::Onetime
        def self.auth_config; end
      end
    end

    # Auth::Config::Features namespace is established by the top-level shim above.
    require File.expand_path('../../../config/features/omniauth.rb', __dir__)
  end

  let(:auth) { double('auth') }
  let(:log_messages) { [] }
  let(:orgs_sso_enabled) { false }

  before do
    allow(OT).to receive(:le) { |msg| log_messages << [:error, msg] }
    allow(OT).to receive(:li) { |msg| log_messages << [:info, msg] }

    auth_config_stub = double('auth_config', orgs_sso_enabled?: orgs_sso_enabled)
    allow(Onetime).to receive(:auth_config).and_return(auth_config_stub)

    # A SAML-compatible session cookie. Under any other, Saml.platform_options
    # raises and the platform provider is SKIPPED (and the tenant placeholder
    # logs a warning), which would change the log sequences examples assert
    # on. The rule itself is pinned under 'the session-cookie prerequisite'.
    allow(Onetime).to receive(:session_config).and_return('same_site' => 'none', 'secure' => true)
  end

  # ================================================================
  # Entra ID Provider
  # ================================================================

  describe '.configure_entra_id_provider' do
    context 'when all required env vars are present' do
      it 'registers the :entra_id strategy' do
        expect(auth).to receive(:omniauth_provider).with(
          :entra_id,
          hash_including(
            name: :entra,
            client_id: 'test-entra-client',
            client_secret: 'test-entra-secret',
            tenant_id: 'test-tenant',
          )
        )

        ClimateControl.modify(
          ENTRA_TENANT_ID: 'test-tenant',
          ENTRA_CLIENT_ID: 'test-entra-client',
          ENTRA_CLIENT_SECRET: 'test-entra-secret',
          ENTRA_REDIRECT_URI: 'http://localhost:3000/auth/sso/entra/callback',
        ) do
          Auth::Config::Features::OmniAuth.configure_entra_id_provider(auth)
        end
      end

      it 'uses custom route name when ENTRA_ROUTE_NAME is set' do
        expect(auth).to receive(:omniauth_provider).with(
          :entra_id,
          hash_including(name: :microsoft)
        )

        ClimateControl.modify(
          ENTRA_TENANT_ID: 'test-tenant',
          ENTRA_CLIENT_ID: 'test-entra-client',
          ENTRA_CLIENT_SECRET: 'test-entra-secret',
          ENTRA_ROUTE_NAME: 'microsoft',
        ) do
          Auth::Config::Features::OmniAuth.configure_entra_id_provider(auth)
        end
      end
    end

    context 'when required env vars are missing' do
      let(:entra_clear) { { ENTRA_TENANT_ID: nil, ENTRA_CLIENT_ID: nil, ENTRA_CLIENT_SECRET: nil } }

      it 'skips registration when ENTRA_TENANT_ID is missing' do
        expect(auth).not_to receive(:omniauth_provider)

        ClimateControl.modify(
          ENTRA_CLIENT_ID: 'test-entra-client',
          ENTRA_CLIENT_SECRET: 'test-entra-secret',
        ) do
          Auth::Config::Features::OmniAuth.configure_entra_id_provider(auth)
        end

        expect(log_messages.last).to match([:error, /Missing Entra ID.*ENTRA_TENANT_ID/])
      end

      it 'skips registration when ENTRA_CLIENT_ID is missing' do
        expect(auth).not_to receive(:omniauth_provider)

        ClimateControl.modify(
          ENTRA_TENANT_ID: 'test-tenant',
          ENTRA_CLIENT_SECRET: 'test-entra-secret',
        ) do
          Auth::Config::Features::OmniAuth.configure_entra_id_provider(auth)
        end

        expect(log_messages.last).to match([:error, /Missing Entra ID.*ENTRA_CLIENT_ID/])
      end

      it 'skips registration when ENTRA_CLIENT_SECRET is missing' do
        expect(auth).not_to receive(:omniauth_provider)

        ClimateControl.modify(
          ENTRA_TENANT_ID: 'test-tenant',
          ENTRA_CLIENT_ID: 'test-entra-client',
        ) do
          Auth::Config::Features::OmniAuth.configure_entra_id_provider(auth)
        end

        expect(log_messages.last).to match([:error, /Missing Entra ID.*ENTRA_CLIENT_SECRET/])
      end

      it 'logs all missing vars at once' do
        expect(auth).not_to receive(:omniauth_provider)

        ClimateControl.modify(entra_clear) do
          Auth::Config::Features::OmniAuth.configure_entra_id_provider(auth)
        end

        msg = log_messages.last[1]
        expect(msg).to include('ENTRA_TENANT_ID')
        expect(msg).to include('ENTRA_CLIENT_ID')
        expect(msg).to include('ENTRA_CLIENT_SECRET')
      end

      context 'with orgs_sso_enabled' do
        let(:orgs_sso_enabled) { true }

        it 'registers placeholder route for tenant SSO' do
          expect(auth).to receive(:omniauth_provider).with(
            :entra_id,
            hash_including(
              name: :entra,
              client_id: 'placeholder',
              client_secret: 'placeholder',
              tenant_id: 'placeholder',
            )
          )

          ClimateControl.modify(entra_clear) do
            Auth::Config::Features::OmniAuth.configure_entra_id_provider(auth)
          end

          expect(log_messages.last).to match([:info, /Registering Entra ID route.*tenant SSO/])
        end

        context 'when only ENTRA_TENANT_ID is set' do
          it 'registers with placeholder values, not the partial real credentials' do
            expect(auth).to receive(:omniauth_provider).with(
              :entra_id,
              hash_including(
                client_id: 'placeholder',
                client_secret: 'placeholder',
                tenant_id: 'placeholder',
              )
            )

            ClimateControl.modify(
              ENTRA_TENANT_ID: 'real-tenant-id',
              ENTRA_CLIENT_ID: nil,
              ENTRA_CLIENT_SECRET: nil,
            ) do
              Auth::Config::Features::OmniAuth.configure_entra_id_provider(auth)
            end
          end
        end
      end
    end
  end

  # ================================================================
  # GitHub Provider
  # ================================================================

  describe '.configure_github_provider' do
    context 'when all required env vars are present' do
      it 'registers the :github strategy' do
        expect(auth).to receive(:omniauth_provider).with(
          :github,
          hash_including(
            name: :github,
            client_id: 'gh-client-id',
            client_secret: 'gh-client-secret',
            scope: 'user:email',
          )
        )

        ClimateControl.modify(
          GITHUB_CLIENT_ID: 'gh-client-id',
          GITHUB_CLIENT_SECRET: 'gh-client-secret',
          GITHUB_REDIRECT_URI: 'http://localhost:3000/auth/sso/github/callback',
        ) do
          Auth::Config::Features::OmniAuth.configure_github_provider(auth)
        end
      end

      it 'uses custom route name when GITHUB_ROUTE_NAME is set' do
        expect(auth).to receive(:omniauth_provider).with(
          :github,
          hash_including(name: :gh)
        )

        ClimateControl.modify(
          GITHUB_CLIENT_ID: 'gh-client-id',
          GITHUB_CLIENT_SECRET: 'gh-client-secret',
          GITHUB_ROUTE_NAME: 'gh',
        ) do
          Auth::Config::Features::OmniAuth.configure_github_provider(auth)
        end
      end
    end

    context 'when required env vars are missing' do
      let(:github_clear) { { GITHUB_CLIENT_ID: nil, GITHUB_CLIENT_SECRET: nil } }

      it 'skips registration when GITHUB_CLIENT_ID is missing' do
        expect(auth).not_to receive(:omniauth_provider)

        ClimateControl.modify(
          GITHUB_CLIENT_SECRET: 'gh-client-secret',
        ) do
          Auth::Config::Features::OmniAuth.configure_github_provider(auth)
        end

        expect(log_messages.last).to match([:error, /Missing GitHub.*GITHUB_CLIENT_ID/])
      end

      it 'skips registration when GITHUB_CLIENT_SECRET is missing' do
        expect(auth).not_to receive(:omniauth_provider)

        ClimateControl.modify(
          GITHUB_CLIENT_ID: 'gh-client-id',
        ) do
          Auth::Config::Features::OmniAuth.configure_github_provider(auth)
        end

        expect(log_messages.last).to match([:error, /Missing GitHub.*GITHUB_CLIENT_SECRET/])
      end

      it 'skips registration when both are missing' do
        expect(auth).not_to receive(:omniauth_provider)

        ClimateControl.modify(github_clear) do
          Auth::Config::Features::OmniAuth.configure_github_provider(auth)
        end

        msg = log_messages.last[1]
        expect(msg).to include('GITHUB_CLIENT_ID')
        expect(msg).to include('GITHUB_CLIENT_SECRET')
      end

      context 'with orgs_sso_enabled' do
        let(:orgs_sso_enabled) { true }

        it 'registers placeholder route for tenant SSO' do
          expect(auth).to receive(:omniauth_provider).with(
            :github,
            hash_including(
              name: :github,
              client_id: 'placeholder',
              client_secret: 'placeholder',
            )
          )

          ClimateControl.modify(github_clear) do
            Auth::Config::Features::OmniAuth.configure_github_provider(auth)
          end

          expect(log_messages.last).to match([:info, /Registering GitHub route.*tenant SSO/])
        end
      end
    end
  end

  # ================================================================
  # Google Provider
  # ================================================================

  describe '.configure_google_provider' do
    context 'when all required env vars are present' do
      it 'registers the :google_oauth2 strategy' do
        expect(auth).to receive(:omniauth_provider).with(
          :google_oauth2,
          hash_including(
            name: :google,
            client_id: 'google-client-id',
            client_secret: 'google-client-secret',
            scope: 'openid,email,profile',
          )
        )

        ClimateControl.modify(
          GOOGLE_CLIENT_ID: 'google-client-id',
          GOOGLE_CLIENT_SECRET: 'google-client-secret',
          GOOGLE_REDIRECT_URI: 'http://localhost:3000/auth/sso/google/callback',
        ) do
          Auth::Config::Features::OmniAuth.configure_google_provider(auth)
        end
      end

      it 'uses custom route name when GOOGLE_ROUTE_NAME is set' do
        expect(auth).to receive(:omniauth_provider).with(
          :google_oauth2,
          hash_including(name: :goog)
        )

        ClimateControl.modify(
          GOOGLE_CLIENT_ID: 'google-client-id',
          GOOGLE_CLIENT_SECRET: 'google-client-secret',
          GOOGLE_ROUTE_NAME: 'goog',
        ) do
          Auth::Config::Features::OmniAuth.configure_google_provider(auth)
        end
      end
    end

    context 'when required env vars are missing' do
      let(:google_clear) { { GOOGLE_CLIENT_ID: nil, GOOGLE_CLIENT_SECRET: nil } }

      it 'skips registration when GOOGLE_CLIENT_ID is missing' do
        expect(auth).not_to receive(:omniauth_provider)

        ClimateControl.modify(
          GOOGLE_CLIENT_SECRET: 'google-client-secret',
        ) do
          Auth::Config::Features::OmniAuth.configure_google_provider(auth)
        end

        expect(log_messages.last).to match([:error, /Missing Google.*GOOGLE_CLIENT_ID/])
      end

      it 'skips registration when GOOGLE_CLIENT_SECRET is missing' do
        expect(auth).not_to receive(:omniauth_provider)

        ClimateControl.modify(
          GOOGLE_CLIENT_ID: 'google-client-id',
        ) do
          Auth::Config::Features::OmniAuth.configure_google_provider(auth)
        end

        expect(log_messages.last).to match([:error, /Missing Google.*GOOGLE_CLIENT_SECRET/])
      end

      it 'skips registration when both are missing' do
        expect(auth).not_to receive(:omniauth_provider)

        ClimateControl.modify(google_clear) do
          Auth::Config::Features::OmniAuth.configure_google_provider(auth)
        end

        msg = log_messages.last[1]
        expect(msg).to include('GOOGLE_CLIENT_ID')
        expect(msg).to include('GOOGLE_CLIENT_SECRET')
      end

      context 'with orgs_sso_enabled' do
        let(:orgs_sso_enabled) { true }

        it 'registers placeholder route for tenant SSO' do
          expect(auth).to receive(:omniauth_provider).with(
            :google_oauth2,
            hash_including(
              name: :google,
              client_id: 'placeholder',
              client_secret: 'placeholder',
            )
          )

          ClimateControl.modify(google_clear) do
            Auth::Config::Features::OmniAuth.configure_google_provider(auth)
          end

          expect(log_messages.last).to match([:info, /Registering Google route.*tenant SSO/])
        end
      end
    end
  end

  # ================================================================
  # OIDC Provider
  # ================================================================

  describe '.configure_oidc_provider' do
    context 'when all required env vars are present' do
      it 'registers the :openid_connect strategy' do
        expect(auth).to receive(:omniauth_provider).with(
          :openid_connect,
          hash_including(
            name: :oidc,
            issuer: 'https://idp.example.com',
            client_options: hash_including(
              identifier: 'oidc-client-id',
              secret: 'oidc-client-secret',
            ),
            pkce: true,
            discovery: true,
          )
        )

        ClimateControl.modify(
          OIDC_ISSUER: 'https://idp.example.com',
          OIDC_CLIENT_ID: 'oidc-client-id',
          OIDC_CLIENT_SECRET: 'oidc-client-secret',
        ) do
          Auth::Config::Features::OmniAuth.configure_oidc_provider(auth)
        end
      end

      it 'omits secret from client_options when OIDC_CLIENT_SECRET is empty (PKCE-only)' do
        expect(auth).to receive(:omniauth_provider).with(
          :openid_connect,
          hash_including(
            client_options: hash_including(identifier: 'oidc-client-id'),
          )
        ) do |_strategy, opts|
          expect(opts[:client_options]).not_to have_key(:secret)
        end

        ClimateControl.modify(
          OIDC_ISSUER: 'https://idp.example.com',
          OIDC_CLIENT_ID: 'oidc-client-id',
          OIDC_CLIENT_SECRET: '',
        ) do
          Auth::Config::Features::OmniAuth.configure_oidc_provider(auth)
        end
      end

      it 'uses custom route name when OIDC_ROUTE_NAME is set' do
        expect(auth).to receive(:omniauth_provider).with(
          :openid_connect,
          hash_including(name: :custom_oidc)
        )

        ClimateControl.modify(
          OIDC_ISSUER: 'https://idp.example.com',
          OIDC_CLIENT_ID: 'oidc-client-id',
          OIDC_CLIENT_SECRET: 'oidc-client-secret',
          OIDC_ROUTE_NAME: 'custom_oidc',
        ) do
          Auth::Config::Features::OmniAuth.configure_oidc_provider(auth)
        end
      end

      it 'logs info on successful configuration' do
        allow(auth).to receive(:omniauth_provider)

        ClimateControl.modify(
          OIDC_ISSUER: 'https://idp.example.com',
          OIDC_CLIENT_ID: 'oidc-client-id',
          OIDC_CLIENT_SECRET: 'oidc-client-secret',
        ) do
          Auth::Config::Features::OmniAuth.configure_oidc_provider(auth)
        end

        expect(log_messages.last).to match([:info, /Configuring OIDC/])
      end
    end

    context 'when required env vars are missing' do
      # Explicitly clear OIDC vars that may be set in the shell environment
      let(:oidc_clear) { { OIDC_ISSUER: nil, OIDC_CLIENT_ID: nil, OIDC_CLIENT_SECRET: nil } }

      context 'with orgs_sso_enabled' do
        let(:orgs_sso_enabled) { true }

        it 'registers placeholder route for tenant SSO' do
          expect(auth).to receive(:omniauth_provider).with(
            :openid_connect,
            hash_including(
              name: :oidc,
              issuer: 'https://placeholder.invalid',
              discovery: true,
            )
          )

          ClimateControl.modify(oidc_clear) do
            Auth::Config::Features::OmniAuth.configure_oidc_provider(auth)
          end

          expect(log_messages.last).to match([:info, /Registering OIDC route.*tenant SSO/])
        end
      end

      context 'without orgs_sso_enabled' do
        it 'skips registration and logs error' do
          expect(auth).not_to receive(:omniauth_provider)

          ClimateControl.modify(oidc_clear) do
            Auth::Config::Features::OmniAuth.configure_oidc_provider(auth)
          end

          expect(log_messages.last).to match([:error, /Missing OIDC/])
        end
      end
    end
  end

  # ================================================================
  # Default values
  # ================================================================

  describe 'default env var values' do
    it 'Entra defaults route_name to "entra" and display_name to "Microsoft"' do
      expect(auth).to receive(:omniauth_provider).with(
        :entra_id,
        hash_including(name: :entra)
      )

      ClimateControl.modify(
        ENTRA_TENANT_ID: 'tid',
        ENTRA_CLIENT_ID: 'cid',
        ENTRA_CLIENT_SECRET: 'cs',
      ) do
        Auth::Config::Features::OmniAuth.configure_entra_id_provider(auth)
      end

      expect(log_messages.last[1]).to include('Microsoft')
    end

    it 'GitHub defaults route_name to "github" and display_name to "GitHub"' do
      expect(auth).to receive(:omniauth_provider).with(
        :github,
        hash_including(name: :github)
      )

      ClimateControl.modify(
        GITHUB_CLIENT_ID: 'cid',
        GITHUB_CLIENT_SECRET: 'cs',
      ) do
        Auth::Config::Features::OmniAuth.configure_github_provider(auth)
      end

      expect(log_messages.last[1]).to include('GitHub')
    end

    it 'Google defaults route_name to "google" and display_name to "Google"' do
      expect(auth).to receive(:omniauth_provider).with(
        :google_oauth2,
        hash_including(name: :google)
      )

      ClimateControl.modify(
        GOOGLE_CLIENT_ID: 'cid',
        GOOGLE_CLIENT_SECRET: 'cs',
      ) do
        Auth::Config::Features::OmniAuth.configure_google_provider(auth)
      end

      expect(log_messages.last[1]).to include('Google')
    end
  end

  # ================================================================
  # Registry-driven providers (no named wrapper)
  # ================================================================
  #
  # Apple is registered by the configure loop
  # straight from the registry — see the comment above the named wrappers in
  # features/omniauth.rb. These exercise configure_provider directly, which is
  # the path every provider added from here on will take.
  describe 'registry-driven provider registration' do
    def configure(key)
      Auth::Config::Features::OmniAuth.configure_provider(
        auth, Onetime::SsoProvider::Registry.fetch(key)
      )
    end

    it 'registers Apple with the strategy, route and pinned issuer' do
      expect(auth).to receive(:omniauth_provider).with(
        :apple,
        hash_including(
          name: :apple,
          client_id: 'com.example.web',
          team_id: 'TEAM123456',
          key_id: 'KEY1234567',
          issuer: 'https://appleid.apple.com',
        )
      )

      ClimateControl.modify(
        APPLE_CLIENT_ID: 'com.example.web',
        APPLE_TEAM_ID: 'TEAM123456',
        APPLE_KEY_ID: 'KEY1234567',
        APPLE_PRIVATE_KEY: 'pem',
      ) do
        configure(:apple)
      end

      expect(log_messages.last[1]).to include('Apple')
    end

    # BLAST RADIUS. configure_provider runs inside Rodauth configuration, so an
    # exception escaping strategy_options fails the whole auth app — password,
    # MFA and magic links included — over one optional SSO provider. A
    # definition that validates a URL variable raises on a schemeless value,
    # so this is reachable from a plausible typo, not a contrived input.
    it 'skips a provider whose strategy_options raises instead of failing boot' do
      expect(auth).not_to receive(:omniauth_provider)

      raising = Onetime::SsoProvider::Registry.fetch(:apple).merge(
        strategy_options: -> { raise ArgumentError, 'APPLE_PRIVATE_KEY must be a PEM' },
      )

      ClimateControl.modify(
        APPLE_CLIENT_ID: 'com.example.web',
        APPLE_TEAM_ID: 'TEAM123456',
        APPLE_KEY_ID: 'KEY1234567',
        APPLE_PRIVATE_KEY: 'pem',
      ) do
        expect { Auth::Config::Features::OmniAuth.configure_provider(auth, raising) }.not_to raise_error
      end

      expect(log_messages.last[0]).to eq(:error)
      expect(log_messages.last[1]).to include('Skipping Apple', 'APPLE_PRIVATE_KEY must be a PEM')
    end

    # The skip path must not require the gem — that is what lets a deployment
    # carry a registry entry for a provider it never configures.
    it 'skips an unconfigured provider without registering it' do
      expect(auth).not_to receive(:omniauth_provider)

      ClimateControl.modify(
        APPLE_CLIENT_ID: nil,
        APPLE_TEAM_ID: nil,
        APPLE_KEY_ID: nil,
        APPLE_PRIVATE_KEY: nil,
      ) do
        configure(:apple)
      end

      expect(log_messages.last).to eq(
        [:error, '[OmniAuth] Missing Apple configuration: ' \
                 'APPLE_CLIENT_ID, APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY']
      )
    end

    # ------------------------------------------------------------------
    # SAML (#4450)
    # ------------------------------------------------------------------
    describe 'SAML' do
      let(:idp) { SamlSpec::TestIdp.new }
      let(:saml_env) do
        {
          SAML_IDP_SSO_SERVICE_URL: 'https://idp.example.com/saml/sso',
          SAML_IDP_ENTITY_ID: 'https://idp.example.com/saml/metadata',
          SAML_IDP_CERT: idp.cert_pem,
          SAML_SP_ENTITY_ID: 'https://ots.example.com/auth/sso/saml/metadata',
          SAML_UID_ATTRIBUTE: nil,
          SAML_ROUTE_NAME: nil,
        }
      end

      # The platform ACS URL derives from site.host / site.ssl
      # (Saml.platform_acs_url); the registry stays loadable without a
      # booted config, so it is stubbed here.
      before do
        allow(OT).to receive(:conf).and_return({ 'site' => { 'host' => 'ots.example.com', 'ssl' => true } })
      end

      it 'registers the request-bound subclass with the trio, hardened options, pinned ACS and NO issuer' do
        registered = nil
        allow(auth).to receive(:omniauth_provider) { |strategy, **opts| registered = [strategy, opts] }

        ClimateControl.modify(saml_env) { configure(:saml) }

        strategy, opts = registered
        expect(strategy).to eq(:request_bound_saml)
        expect(opts).to include(
          name: :saml,
          idp_sso_service_url: 'https://idp.example.com/saml/sso',
          idp_entity_id: 'https://idp.example.com/saml/metadata',
          sp_entity_id: 'https://ots.example.com/auth/sso/saml/metadata',
          assertion_consumer_service_url: 'https://ots.example.com/auth/sso/saml/callback',
          slo_enabled: false,
          security: Onetime::SsoProvider::Saml::SECURITY,
        )
        # `issuer` is ruby-saml's alias for OUR SP EntityID, and resolve_issuer
        # precedence #1 — see lib/onetime/sso_provider/saml.rb.
        expect(opts).not_to have_key(:issuer)
        # No fingerprint trust anchor; idp_cert_fingerprint_algorithm is the
        # SHA-256 digest ruby-saml matches a response-embedded certificate
        # against the pinned one with (registry_spec pins it), not a fingerprint.
        expect(opts.keys.map(&:to_s).grep(/fingerprint/)).to eq(['idp_cert_fingerprint_algorithm'])
        expect(opts[:idp_cert_fingerprint_algorithm]).to eq(Onetime::SsoProvider::Saml::DIGEST_SHA256)
        expect(log_messages.last[1]).to include('SAML', 'client_id: (none)')
      end

      # The symbol only resolves because the gem_require'd file defines the
      # class and registers its camelization; rodauth-omniauth resolves it the
      # same way OmniAuth::Builder does.
      it 'loads a strategy class the :request_bound_saml symbol resolves to' do
        allow(auth).to receive(:omniauth_provider)
        ClimateControl.modify(saml_env) { configure(:saml) }

        class_name = OmniAuth::Utils.camelize('request_bound_saml')
        expect(OmniAuth::Strategies.const_get(class_name)).to be(OmniAuth::Strategies::RequestBoundSAML)
        expect(OmniAuth::Strategies::RequestBoundSAML.ancestors).to include(OmniAuth::Strategies::SAML)
      end

      it 'uses SAML_ROUTE_NAME for the route' do
        expect(auth).to receive(:omniauth_provider).with(:request_bound_saml, hash_including(name: :okta))

        ClimateControl.modify(saml_env.merge(SAML_ROUTE_NAME: 'okta')) { configure(:saml) }
      end

      %w[SAML_IDP_SSO_SERVICE_URL SAML_IDP_ENTITY_ID SAML_IDP_CERT].each do |var|
        it "skips registration when #{var} is missing" do
          expect(auth).not_to receive(:omniauth_provider)

          ClimateControl.modify(saml_env.merge(var.to_sym => nil)) { configure(:saml) }

          expect(log_messages.last).to eq([:error, "[OmniAuth] Missing SAML configuration: #{var}"])
        end
      end

      # #4450 asks for a boot failure here. configure_provider never fails
      # boot (it would take every other sign-in method down with it): the
      # provider is skipped, loudly, and :vars_valid keeps it unadvertised.
      {
        'an unparseable certificate' => [{ SAML_IDP_CERT: 'not a certificate' }, 'IdP certificate'],
        'an http SSO service URL' => [{ SAML_IDP_SSO_SERVICE_URL: 'http://idp.example.com/sso' }, 'https://'],
        'a whitespace EntityID' => [{ SAML_IDP_ENTITY_ID: '  ' }, 'EntityID is blank'],
      }.each do |label, (overrides, message)|
        it "skips (does not fail boot) on #{label}" do
          expect(auth).not_to receive(:omniauth_provider)

          ClimateControl.modify(saml_env.merge(overrides)) do
            expect { configure(:saml) }.not_to raise_error
          end

          expect(log_messages.last[0]).to eq(:error)
          expect(log_messages.last[1]).to include('Skipping SAML', message, 'SAML_IDP_CERT')
        end
      end

      # The HTTP-POST callback is a cross-site POST: under the shipped
      # SameSite=Lax cookie every sign-in ends as saml_no_pending_request.
      # PLATFORM vars present: the provider takes the skip contract (one
      # error line naming the settings, no route, unadvertised via
      # :vars_valid). Tenant PLACEHOLDER: one warning line, the route still
      # registers. Boot goes on either way.
      describe 'the session-cookie prerequisite' do
        before { allow(auth).to receive(:omniauth_provider) }

        def cookie_warnings
          log_messages.select { |level, msg| level == :error && msg.include?('SAML is enabled') }
        end

        def cookie_mentions
          log_messages.select { |_level, msg| msg.include?('same_site') }
        end

        it 'skips the platform provider, naming both settings and the consequence, under a lax cookie' do
          allow(Onetime).to receive(:session_config).and_return('same_site' => 'lax', 'secure' => true)
          expect(auth).not_to receive(:omniauth_provider)

          ClimateControl.modify(saml_env) { configure(:saml) }

          expect(log_messages.last[0]).to eq(:error)
          expect(log_messages.last[1]).to include(
            "Skipping SAML provider 'saml'", "same_site is 'lax'", 'secure is true',
            'same_site: none with secure: true', 'saml_no_pending_request'
          )
          # One line, not a warning plus a skip.
          expect(cookie_mentions.size).to eq(1)
          expect(cookie_warnings).to be_empty
          expect(Onetime::SsoProvider::Saml.platform_usable?).to be false
        end

        it 'skips under SameSite=None without Secure' do
          allow(Onetime).to receive(:session_config).and_return('same_site' => 'none', 'secure' => false)
          expect(auth).not_to receive(:omniauth_provider)

          ClimateControl.modify(saml_env) { configure(:saml) }

          expect(log_messages.last[1]).to include('Skipping SAML', "same_site is 'none'", 'secure is false')
          expect(cookie_mentions.size).to eq(1)
        end

        it 'registers, silently, under SameSite=None with Secure' do
          allow(Onetime).to receive(:session_config).and_return('same_site' => 'none', 'secure' => true)
          expect(auth).to receive(:omniauth_provider).with(:request_bound_saml, hash_including(name: :saml))

          ClimateControl.modify(saml_env) { configure(:saml) }

          expect(cookie_mentions).to be_empty
          expect(log_messages.last[1]).to include('Configuring SAML')
        end

        it 'is silent when SAML is not enabled at all (no vars, no org SSO)' do
          allow(Onetime).to receive(:session_config).and_return('same_site' => 'lax', 'secure' => true)

          ClimateControl.modify(saml_env.transform_values { nil }) { configure(:saml) }

          expect(cookie_warnings).to be_empty
        end

        it 'does not warn for a provider other than saml' do
          allow(Onetime).to receive(:session_config).and_return('same_site' => 'lax', 'secure' => true)

          ClimateControl.modify(OIDC_CLIENT_ID: 'x', OIDC_CLIENT_SECRET: 'y', OIDC_ISSUER: 'https://issuer.example.com') do
            configure(:oidc)
          end

          expect(cookie_warnings).to be_empty
        end

        context 'with orgs_sso_enabled and no platform vars (tenant placeholder)' do
          let(:orgs_sso_enabled) { true }

          it 'warns, naming ORGS_SSO_ENABLED, before the placeholder registration line' do
            allow(Onetime).to receive(:session_config).and_return('same_site' => 'lax', 'secure' => true)

            ClimateControl.modify(saml_env.transform_values { nil }) { configure(:saml) }

            expect(cookie_warnings.size).to eq(1)
            expect(cookie_warnings.first[1]).to include('tenant SSO (ORGS_SSO_ENABLED=true)')
            expect(cookie_mentions.size).to eq(1)
            expect(log_messages.last[1]).to include('for tenant SSO')
          end
        end

        # Platform vars present AND org SSO on: the skip line names the
        # cookie, the placeholder registers for tenants, and the cookie is
        # mentioned exactly once (no tenant-only warning on top of the skip).
        context 'with orgs_sso_enabled and platform vars under a lax cookie' do
          let(:orgs_sso_enabled) { true }

          it 'skips the platform provider naming the cookie, then registers the placeholder' do
            allow(Onetime).to receive(:session_config).and_return('same_site' => 'lax', 'secure' => true)
            registered = nil
            allow(auth).to receive(:omniauth_provider) { |strategy, **opts| registered = [strategy, opts] }

            ClimateControl.modify(saml_env) { configure(:saml) }

            expect(registered[0]).to eq(:request_bound_saml)
            expect(registered[1]).to include(name: :saml, idp_entity_id: '', sp_entity_id: '')
            expect(log_messages.map(&:first)).to eq([:info, :error, :info])
            expect(log_messages[1][1]).to include("Skipping SAML provider 'saml'", "same_site is 'lax'")
            expect(cookie_mentions.size).to eq(1)
            expect(cookie_warnings).to be_empty
          end
        end
      end

      context 'with orgs_sso_enabled' do
        let(:orgs_sso_enabled) { true }

        it 'registers the placeholder route (blank trust anchors, no issuer) when unconfigured' do
          expect(auth).to receive(:omniauth_provider).with(
            :request_bound_saml,
            hash_including(name: :saml, idp_entity_id: '', sp_entity_id: '', idp_cert: '', slo_enabled: false),
          )

          ClimateControl.modify(saml_env.transform_values { nil }) { configure(:saml) }

          expect(log_messages.last[1]).to include('for tenant SSO')
        end

        # A typo in the PLATFORM's SAML config must not delete the route every
        # TENANT's SAML config is injected into.
        it 'falls back to the placeholder route when the platform config is present but invalid' do
          registered = nil
          allow(auth).to receive(:omniauth_provider) { |strategy, **opts| registered = [strategy, opts] }

          ClimateControl.modify(saml_env.merge(SAML_IDP_CERT: 'not a certificate')) { configure(:saml) }

          expect(registered[0]).to eq(:request_bound_saml)
          expect(registered[1]).to include(name: :saml, idp_entity_id: '', idp_cert: '')
          expect(registered[1]).not_to have_key(:issuer)
          expect(log_messages.map(&:first)).to eq([:info, :error, :info])
          expect(log_messages[1][1]).to include('Skipping SAML')
        end
      end
    end
  end
end
