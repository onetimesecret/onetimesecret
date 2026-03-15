# apps/web/auth/spec/config/features/omniauth_providers_spec.rb
#
# frozen_string_literal: true

# Tests for provider registration methods in Auth::Config::Features::OmniAuth.
#
# Each configure_X_provider method reads env vars, validates required ones,
# and calls auth.omniauth_provider when valid (or logs and returns when not).
# These tests verify that behavior without booting the full app.
#
# RUN:
#   source .env.test && pnpm run test:rspec apps/web/auth/spec/config/features/omniauth_providers_spec.rb

require 'rspec'
require 'climate_control'

RSpec.describe 'Auth::Config::Features::OmniAuth provider registration' do
  # Stub namespaces and logger before loading the module
  before(:all) do
    unless defined?(OT)
      module ::OT
        def self.li(*args); end
        def self.le(*args); end
      end
    end

    # Stub the Auth::Config::Features namespace so the module can be defined
    unless defined?(Auth::Config::Features)
      module ::Auth; module Config; module Features; end; end; end
    end

    require File.expand_path('../../../config/features/omniauth.rb', __dir__)
  end

  let(:auth) { double('auth') }
  let(:log_messages) { [] }

  before do
    allow(OT).to receive(:le) { |msg| log_messages << [:error, msg] }
    allow(OT).to receive(:li) { |msg| log_messages << [:info, msg] }
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
