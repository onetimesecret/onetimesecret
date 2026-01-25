# apps/web/auth/config/features/omniauth.rb
#
# frozen_string_literal: true

#
# ==============================================================================
# FEATURE: OMNIAUTH (EXTERNAL IDENTITY PROVIDERS)
# ==============================================================================
#
# This feature enables single sign-on (SSO) via external identity providers
# using the OpenID Connect (OIDC) protocol. Supports any OIDC-compliant
# provider: Zitadel, Keycloak, Auth0, Okta, etc.
#
# OVERVIEW:
# OmniAuth is a middleware-based authentication framework that provides a
# standardized interface for multiple authentication providers. This feature
# integrates rodauth-omniauth with the omniauth_openid_connect strategy.
#
# USER JOURNEY - SSO LOGIN:
#
# 1. USER INITIATES SSO LOGIN
#    - User clicks "Login with SSO" button on login page
#    - Browser POSTs to /auth/sso/oidc (or configured provider name)
#    - OmniAuth redirects to identity provider's authorization endpoint
#
# 2. USER AUTHENTICATES AT IDENTITY PROVIDER
#    - User sees identity provider login screen (e.g., Zitadel)
#    - User enters credentials or uses existing session
#    - Provider redirects back with authorization code
#
# 3. TOKEN EXCHANGE & CALLBACK
#    - OmniAuth exchanges code for tokens at provider's token endpoint
#    - Provider returns ID token with user claims
#    - OmniAuth parses claims and populates omniauth_auth hash
#
# 4. ACCOUNT LINKING/CREATION (hooks/omniauth.rb)
#    - account_from_omniauth finds existing account by email
#    - If no account: new account created (if omniauth_create_account? true)
#    - Identity record created in account_identities table
#    - Session synced via after_omniauth_callback hook
#
# 5. AUTHENTICATED SESSION
#    - User redirected to dashboard
#    - Session populated with user data (same as regular login)
#
# CONFIGURATION:
# Requires environment variables:
#   - OIDC_ISSUER: Provider's issuer URL (for discovery)
#   - OIDC_CLIENT_ID: OAuth client ID
#   - OIDC_CLIENT_SECRET: OAuth client secret
#   - OIDC_REDIRECT_URI: Callback URL (https://app/auth/sso/oidc/callback)
#   - OIDC_ROUTE_NAME: Optional route path segment (default: 'oidc')
#   - SSO_DISPLAY_NAME: Optional display name for button (e.g., 'Company SSO')
#
# ==============================================================================

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
