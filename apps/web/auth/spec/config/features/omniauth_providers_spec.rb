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

        ClimateControl.modify({}) do
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

          ClimateControl.modify({}) do
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

        ClimateControl.modify({}) do
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

          ClimateControl.modify({}) do
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

        ClimateControl.modify({}) do
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

          ClimateControl.modify({}) do
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
end
