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

# Load the OpenID Connect strategy before configuring
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

      # Register OpenID Connect provider
      # Uses discovery document from issuer URL for endpoint configuration
      configure_oidc_provider(auth)
    end

    def self.configure_oidc_provider(auth)
      # NOTE: No explicit state parameter (though rodauth-omniauth should handle this).
      issuer        = ENV.fetch('OIDC_ISSUER', nil)
      client_id     = ENV.fetch('OIDC_CLIENT_ID', nil)

      # NOTE: Client secret can be empty for PKCE-only flows, but ensure the IdP
      # actually supports PKCE-only.
      client_secret = ENV.fetch('OIDC_CLIENT_SECRET', '') # Optional for PKCE-only flows
      redirect_uri  = ENV.fetch('OIDC_REDIRECT_URI', nil)

      # Issue: The route name is configurable via OIDC_ROUTE_NAME env var. If someone sets
      #        OIDC_ROUTE_NAME=google, the route becomes /auth/sso/google, but the frontend hardcodes /auth/sso/oidc.

      #        Recommendation: Either:
      #        - Expose the route name via bootstrap state, or
      #        - Document that OIDC_ROUTE_NAME must stay oidc for frontend compatibility
      provider_name = ENV.fetch('OIDC_ROUTE_NAME', 'oidc').to_sym

      # Validate required configuration - check for empty strings too
      missing = []
      missing << 'OIDC_ISSUER' if issuer.nil? || issuer.empty?
      missing << 'OIDC_CLIENT_ID' if client_id.nil? || client_id.empty?

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
  end
end
