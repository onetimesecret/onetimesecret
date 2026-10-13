# lib/onetime/sso_provider/oidc.rb
#
# frozen_string_literal: true

# Generic OIDC provider definition. Field reference and the issuer-scoping
# background live in the registry header (lib/onetime/sso_provider/registry.rb).

module Onetime
  module SsoProvider
    module Oidc
      # How the client secret reaches the token endpoint (#4764). Keys are
      # the values the tenant record (CustomDomain::SsoConfig
      # #token_endpoint_auth_method) and the platform OIDC_CLIENT_AUTH_METHOD
      # variable accept — the RFC 7591 / OIDC Discovery names, so they can
      # be compared with the IdP's token_endpoint_auth_methods_supported.
      # Values are what omniauth_openid_connect's top-level
      # client_auth_method option receives and forwards to
      # Rack::OAuth2::Client#authenticated_context_from:
      #
      #   :basic               — Authorization: Basic header; rack-oauth2
      #                          form-urlencodes id and secret (RFC 6749 2.3.1).
      #   :client_secret_post  — no branch of its own in rack-oauth2 2.3.0:
      #                          every unlisted symbol falls to the `else`
      #                          arm, which puts client_id / client_secret in
      #                          the request body. Pinned in
      #                          spec/unit/auth/oidc_client_auth_method_spec.rb.
      #
      # Blank (no selection) maps to nil, which rack-oauth2 treats as :basic.
      # The tenant builder ALWAYS emits the key (nil included) because tenant
      # options are merged over the platform strategy's key by key — an
      # omitted key would let OIDC_CLIENT_AUTH_METHOD leak into a tenant that
      # chose the default.
      CLIENT_AUTH_METHODS = {
        'client_secret_basic' => :basic,
        'client_secret_post' => :client_secret_post,
      }.freeze

      # @param value [String, nil] a CLIENT_AUTH_METHODS key, or blank
      # @return [Symbol, nil] the strategy's client_auth_method option
      # @raise [ArgumentError] on a non-blank value that is not a known method
      def self.client_auth_method_for(value)
        key = value.to_s.strip
        return nil if key.empty?

        CLIENT_AUTH_METHODS.fetch(key) do
          raise ArgumentError,
            "token endpoint auth method must be one of: #{CLIENT_AUTH_METHODS.keys.join(', ')} (got #{key.inspect})"
        end
      end

      # The platform variable. An unknown value is logged and treated as
      # blank rather than raised: strategy_options runs at boot, and a typo
      # in an optional variable must not take the provider (or the boot)
      # down — the install keeps the gem default (:basic).
      def self.env_client_auth_method
        client_auth_method_for(ENV.fetch('OIDC_CLIENT_AUTH_METHOD', ''))
      rescue ArgumentError => ex
        OT.lw "[OmniAuth] Ignoring OIDC_CLIENT_AUTH_METHOD: #{ex.message}"
        nil
      end

      DEFINITION = {
        key: :oidc,
        label: 'OIDC',
        strategy: :openid_connect,
        gem_require: 'omniauth_openid_connect',
        issuer_capable: true,
        # OIDC_CLIENT_SECRET is intentionally NOT required: PKCE flows may
        # run without one (see strategy_options).
        required_vars: %w[OIDC_ISSUER OIDC_CLIENT_ID],
        route_var: 'OIDC_ROUTE_NAME',
        route_default: 'oidc',
        display_var: 'OIDC_DISPLAY_NAME',
        # AuthConfig#provider_definitions overlays the operator's legacy
        # sso_display_name over this default at read time.
        display_default: 'SSO',
        trust_var: 'OIDC_TRUST_EMAIL_FOR_LINKING',
        trust_default: false,
        idp_origin_from: 'OIDC_ISSUER',
        # Install-wide issuer checked against its discovery document on the
        # first sign-in attempt (#4513, SsoProvider::IssuerValidation).
        discovery_issuer_var: 'OIDC_ISSUER',
        placeholder_options: {
          scope: [:openid, :email, :profile],
          response_type: :code,
          issuer: 'https://placeholder.invalid',
          client_options: { identifier: 'placeholder' },
          discovery: true,
          pkce: true,
        }.freeze,
        strategy_options: -> {
          client_secret        = ENV.fetch('OIDC_CLIENT_SECRET', '')
          # redirect_uri is omitted here — the omniauth_setup hook injects it
          # at runtime from the request host (see omniauth_tenant.rb).
          client_opts          = { identifier: ENV.fetch('OIDC_CLIENT_ID', nil) }
          # Only include secret if provided (PKCE flows may not have one)
          client_opts[:secret] = client_secret unless client_secret.empty?

          {
            scope: [:openid, :email, :profile],
            response_type: :code,
            issuer: ENV.fetch('OIDC_ISSUER', nil),
            client_options: client_opts,
            discovery: true,
            pkce: true,
            # nil = gem default (:basic). See CLIENT_AUTH_METHODS.
            client_auth_method: env_client_auth_method,
          }
        },
      }.freeze
    end
  end
end
