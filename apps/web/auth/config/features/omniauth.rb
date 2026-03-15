# apps/web/auth/config/features/omniauth.rb
#
# frozen_string_literal: true

#
# SSO via external identity providers (OIDC, Entra ID, Google, GitHub).
# Registers OmniAuth strategies at boot based on environment variables.
# Each provider with valid credentials registers automatically.
#
# See: docs/authentication/omniauth-sso.md (full configuration guide)
# See: hooks/omniauth.rb (callback hooks — provider-agnostic)
#

# Load the existing OIDC strategy unconditionally (always available)
require 'omniauth_openid_connect'

module Auth::Config::Features
  module OmniAuth
    def self.configure(auth)
      auth.enable :omniauth

      # Route prefix for OmniAuth endpoints
      # Routes: POST /auth/sso/:provider, GET /auth/sso/:provider/callback
      auth.omniauth_prefix '/sso'

      # Table configuration for identity storage
      auth.omniauth_identities_table :account_identities
      auth.omniauth_identities_account_id_column :account_id
      auth.omniauth_identities_provider_column :provider
      auth.omniauth_identities_uid_column :uid

      # Auto-verify accounts authenticated via SSO
      # SSO providers handle email verification, so we trust them
      auth.omniauth_verify_account? true

      # Auto-create accounts for new SSO users
      #
      # NOTE: omniauth_create_account? true allows any IdP user to create accounts. If the
      # IdP has many users, consider adding domain validation in account_from_omniauth hook.
      #
      auth.omniauth_create_account? true

      # Register providers — each is gated on its own env vars
      configure_oidc_provider(auth)
      configure_entra_id_provider(auth)
      configure_github_provider(auth)
      configure_google_provider(auth)
    end

    # Returns names of env vars that are nil or empty.
    def self.missing_env_vars(required)
      required.select { |name| val = ENV.fetch(name, nil); val.nil? || val.empty? }
    end

    def self.configure_oidc_provider(auth)
      # NOTE: No explicit state parameter (though rodauth-omniauth should handle this).
      issuer        = ENV.fetch('OIDC_ISSUER', nil)
      client_id     = ENV.fetch('OIDC_CLIENT_ID', nil)

      # NOTE: Client secret can be empty for PKCE-only flows, but ensure the IdP
      # actually supports PKCE-only.
      client_secret = ENV.fetch('OIDC_CLIENT_SECRET', '') # Optional for PKCE-only flows
      redirect_uri  = ENV.fetch('OIDC_REDIRECT_URI', nil)

      provider_name = ENV.fetch('OIDC_ROUTE_NAME', 'oidc').to_sym

      missing = missing_env_vars(%w[OIDC_ISSUER OIDC_CLIENT_ID])
      if missing.any?
        OT.le "[OmniAuth] Missing OIDC configuration: #{missing.join(', ')}"
        return
      end

      OT.li "[OmniAuth] Configuring OIDC provider '#{provider_name}' with issuer: #{issuer}, client_id: #{client_id[0..8]}..."

      # Build client options
      client_opts          = {
        identifier: client_id,
        redirect_uri: redirect_uri,
      }
      # Only include secret if provided (PKCE flows may not have one)
      client_opts[:secret] = client_secret unless client_secret.empty?

      auth.omniauth_provider(
        :openid_connect,
        name: provider_name,
        scope: [:openid, :email, :profile],
        response_type: :code,
        issuer: issuer,
        client_options: client_opts,
        discovery: true,
        pkce: true,
      )
    end

    def self.configure_entra_id_provider(auth)
      # NOTE: The name: option controls both the URL route segment AND the
      # provider value stored in account_identities.provider column and
      # returned in the auth hash. Default route name 'entra' means:
      #   - Route: POST /auth/sso/entra, GET /auth/sso/entra/callback
      #   - Auth hash: { provider: 'entra', ... }
      #   - DB: account_identities.provider = 'entra'
      # Without name: override, omniauth-entra-id defaults to 'entra_id'.
      tenant_id     = ENV.fetch('ENTRA_TENANT_ID', nil)
      client_id     = ENV.fetch('ENTRA_CLIENT_ID', nil)
      client_secret = ENV.fetch('ENTRA_CLIENT_SECRET', nil)
      redirect_uri  = ENV.fetch('ENTRA_REDIRECT_URI', nil)
      provider_name = ENV.fetch('ENTRA_ROUTE_NAME', 'entra').to_sym
      # For log message only; the frontend display_name comes from AuthConfig.sso_providers
      display_name  = ENV.fetch('ENTRA_DISPLAY_NAME', 'Microsoft')

      missing = missing_env_vars(%w[ENTRA_TENANT_ID ENTRA_CLIENT_ID ENTRA_CLIENT_SECRET])
      if missing.any?
        OT.le "[OmniAuth] Missing Entra ID configuration: #{missing.join(', ')}"
        return
      end

      OT.li "[OmniAuth] Configuring Entra ID provider '#{provider_name}' (#{display_name}), client_id: #{client_id[0..8]}..."

      require 'omniauth-entra-id'

      auth.omniauth_provider(
        :entra_id,
        name: provider_name,
        client_id: client_id,
        client_secret: client_secret,
        tenant_id: tenant_id,
        redirect_uri: redirect_uri,
        scope: 'openid profile email',
      )
    end

    def self.configure_github_provider(auth)
      client_id     = ENV.fetch('GITHUB_CLIENT_ID', nil)
      client_secret = ENV.fetch('GITHUB_CLIENT_SECRET', nil)
      redirect_uri  = ENV.fetch('GITHUB_REDIRECT_URI', nil)
      provider_name = ENV.fetch('GITHUB_ROUTE_NAME', 'github').to_sym
      display_name  = ENV.fetch('GITHUB_DISPLAY_NAME', 'GitHub')

      missing = missing_env_vars(%w[GITHUB_CLIENT_ID GITHUB_CLIENT_SECRET])
      if missing.any?
        OT.le "[OmniAuth] Missing GitHub configuration: #{missing.join(', ')}"
        return
      end

      OT.li "[OmniAuth] Configuring GitHub provider '#{provider_name}' (#{display_name}), client_id: #{client_id[0..8]}..."

      require 'omniauth-github'

      auth.omniauth_provider(
        :github,
        name: provider_name,
        client_id: client_id,
        client_secret: client_secret,
        redirect_uri: redirect_uri,
        scope: 'user:email',
      )
    end

    def self.configure_google_provider(auth)
      client_id     = ENV.fetch('GOOGLE_CLIENT_ID', nil)
      client_secret = ENV.fetch('GOOGLE_CLIENT_SECRET', nil)
      redirect_uri  = ENV.fetch('GOOGLE_REDIRECT_URI', nil)
      provider_name = ENV.fetch('GOOGLE_ROUTE_NAME', 'google').to_sym
      display_name  = ENV.fetch('GOOGLE_DISPLAY_NAME', 'Google')

      missing = missing_env_vars(%w[GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET])
      if missing.any?
        OT.le "[OmniAuth] Missing Google configuration: #{missing.join(', ')}"
        return
      end

      OT.li "[OmniAuth] Configuring Google provider '#{provider_name}' (#{display_name}), client_id: #{client_id[0..8]}..."

      require 'omniauth-google-oauth2'

      auth.omniauth_provider(
        :google_oauth2,
        name: provider_name,
        client_id: client_id,
        client_secret: client_secret,
        redirect_uri: redirect_uri,
        scope: 'openid,email,profile',
        prompt: 'select_account',
      )
    end
  end
end
