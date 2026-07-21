# apps/web/auth/config/features/omniauth.rb
#
# frozen_string_literal: true

#
# SSO via external identity providers (OIDC, Entra ID, Google, GitHub).
#
# Registers OmniAuth strategies at boot. When platform env vars are present,
# strategies use real credentials. When org-level SSO is enabled
# (ORGS_SSO_ENABLED=true) but platform vars are absent, strategies register
# with placeholder credentials — the OmniAuthTenant hook injects real
# tenant-specific credentials at request time.
#
# See: docs/authentication/omniauth-sso.md (full configuration guide)
# See: hooks/omniauth.rb (callback hooks — provider-agnostic)
#

require 'omniauth_openid_connect'
require 'omniauth-entra-id'
require 'omniauth-github'
require 'omniauth-google-oauth2'

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

      # Register providers — platform creds when available, placeholder
      # routes for tenant SSO when orgs_sso_enabled
      configure_oidc_provider(auth)
      configure_entra_id_provider(auth)
      configure_github_provider(auth)
      configure_google_provider(auth)

      # Issuer-scoped identity lookup (#3840 Phase 0 / #3838 item 5).
      configure_issuer_scoped_identities(auth)
    end

    # ========================================================================
    # Issuer-scoped SSO identities — cross-tenant takeover fix (#3838 item 5)
    # ========================================================================
    #
    # account_identities is keyed on (provider, issuer, uid). `provider` is the
    # strategy NAME ('oidc', 'entra'), identical across every tenant using that
    # strategy, so (provider, uid) alone let a second IdP asserting the same
    # `sub` match the FIRST tenant's row → account takeover. Adding `issuer`
    # makes colliding identities distinct rows.
    #
    # APPROACH A — platform grace + lazy upgrade. Pre-existing rows have the
    # sentinel issuer '' (migration 008 backfills unconditionally; the real
    # issuer is unreconstructable per #3838). The read path resolves it:
    #   1. Exact lookup (provider, resolved_issuer, uid).
    #   2. PLATFORM path only: fall back to the legacy (provider, '', uid) row
    #      and lazily upgrade its issuer to resolved_issuer (self-heal).
    #   3. TENANT path: issuer-exact ONLY — NEVER the '' fallback. The legacy
    #      fallback on the tenant path IS the item-5 takeover.
    #
    # The pure decision functions below are driven verbatim by the auth-class
    # helpers wired in configure_issuer_scoped_identities, and unit/integration
    # tested directly.

    # Sentinel issuer for identities with no known IdP issuer. ALWAYS '' — never
    # nil (a NULL vs '' split breaks the (provider, issuer, uid) unique index).
    ISSUER_SENTINEL = ''

    # Resolve the issuer for the current callback.
    # Precedence: strategy option (authoritative) > ENV['OIDC_ISSUER'] for OIDC
    # > '' sentinel (non-OIDC / unknown).
    #
    # @param strategy_options [Hash, nil] omniauth_strategy&.options
    # @param provider [String, Symbol] omniauth_provider (route name)
    # @param oidc_route_name [String] configured OIDC route name (OIDC_ROUTE_NAME)
    # @param env_oidc_issuer [String, nil] ENV['OIDC_ISSUER']
    # @return [String] resolved issuer or the '' sentinel
    def self.resolve_issuer(strategy_options:, provider:, oidc_route_name:, env_oidc_issuer:)
      option_issuer = strategy_options && strategy_options[:issuer]
      return option_issuer.to_s if option_issuer && !option_issuer.to_s.empty?

      is_oidc = (strategy_options && strategy_options[:discovery] == true) ||
                provider.to_s == oidc_route_name.to_s
      return env_oidc_issuer.to_s if is_oidc && env_oidc_issuer && !env_oidc_issuer.to_s.empty?

      ISSUER_SENTINEL
    end

    # Platform path == no validated tenant domain in session. The tenant hook
    # (hooks/omniauth_tenant.rb) sets session[:validated_omniauth_domain_id] in
    # before_omniauth_callback_route, which the gem runs BEFORE
    # retrieve_omniauth_identity — so this signal is reliable at lookup time.
    #
    # @param validated_domain_id [Object] session[:validated_omniauth_domain_id]
    # @return [Boolean] true when this is a platform (non-tenant) callback
    def self.platform_path?(validated_domain_id)
      validated_domain_id.nil? || validated_domain_id.to_s.empty?
    end

    # Issuer-scoped identity lookup (Approach A). Returns the identity row hash
    # or nil. SECURITY-CRITICAL: the legacy '' fallback + lazy upgrade is gated
    # on platform_path — it must NEVER run on a tenant callback.
    #
    # @param ds [Sequel::Dataset] omniauth_identities dataset
    # @return [Hash, nil]
    def self.lookup_identity(ds:, id_col:, provider_col:, uid_col:, issuer_col:,
                             provider:, uid:, resolved_issuer:, platform_path:)
      provider_s = provider.to_s

      # 1. Exact lookup — (provider, resolved_issuer, uid).
      exact = ds.first(provider_col => provider_s, issuer_col => resolved_issuer, uid_col => uid)
      return exact if exact

      # 2. Platform-path legacy grace + lazy upgrade ONLY. Never on tenant path.
      #    When resolved_issuer is the sentinel, the exact query above already
      #    covered the legacy '' row — there is nothing to upgrade TO, so bail
      #    (also avoids a pointless '' -> '' write).
      return nil unless platform_path
      return nil if resolved_issuer == ISSUER_SENTINEL

      legacy = ds.first(provider_col => provider_s, issuer_col => ISSUER_SENTINEL, uid_col => uid)
      return nil unless legacy

      # Lazy self-heal: bind the legacy row to the now-known issuer so future
      # callbacks match exactly (and the '' row can never be re-graced).
      ds.where(id_col => legacy[id_col]).update(issuer_col => resolved_issuer)
      legacy[issuer_col] = resolved_issuer
      legacy
    end

    # Wire the issuer-scoped lookup, resolver, and insert/update hashes onto the
    # Rodauth auth class. The auth-class helpers are thin adapters over the pure
    # module functions above.
    def self.configure_issuer_scoped_identities(auth)
      # rubocop:disable Lint/NestedMethodDefinition -- Rodauth's auth_class_eval pattern
      auth.auth_class_eval do
        # Resolver: strategy option > ENV OIDC_ISSUER (OIDC) > '' sentinel.
        def resolved_issuer
          Auth::Config::Features::OmniAuth.resolve_issuer(
            strategy_options: omniauth_strategy&.options,
            provider: omniauth_provider,
            oidc_route_name: ENV.fetch('OIDC_ROUTE_NAME', 'oidc'),
            env_oidc_issuer: ENV.fetch('OIDC_ISSUER', nil),
          )
        end

        # Platform (non-tenant) callback gate. See hooks/omniauth_tenant.rb.
        def omniauth_platform_path?
          Auth::Config::Features::OmniAuth.platform_path?(session[:validated_omniauth_domain_id])
        end
      end
      # rubocop:enable Lint/NestedMethodDefinition

      # SECURITY-CRITICAL override: issuer-aware identity lookup.
      auth.retrieve_omniauth_identity do
        Auth::Config::Features::OmniAuth.lookup_identity(
          ds: omniauth_identities_ds,
          id_col: omniauth_identities_id_column,
          provider_col: omniauth_identities_provider_column,
          uid_col: omniauth_identities_uid_column,
          issuer_col: :issuer,
          provider: omniauth_provider,
          uid: omniauth_uid,
          resolved_issuer: resolved_issuer,
          platform_path: omniauth_platform_path?,
        )
      end

      # Persist the resolved issuer when a NEW identity row is created.
      auth.omniauth_identity_insert_hash do
        {
          omniauth_identities_account_id_column => account_id,
          omniauth_identities_provider_column => omniauth_provider.to_s,
          omniauth_identities_uid_column => omniauth_uid,
          issuer: resolved_issuer,
        }
      end

      # On re-login, keep the row's issuer in sync with the resolved value
      # (self-heals any row still carrying the '' sentinel on the platform path).
      auth.omniauth_identity_update_hash do
        { issuer: resolved_issuer }
      end
    end

    # Returns names of env vars that are nil or empty.
    def self.missing_env_vars(required)
      required.select do |name|
        val = ENV.fetch(name, nil)
        val.nil? || val.empty?
      end
    end

    def self.configure_oidc_provider(auth)
      issuer        = ENV.fetch('OIDC_ISSUER', nil)
      client_id     = ENV.fetch('OIDC_CLIENT_ID', nil)
      client_secret = ENV.fetch('OIDC_CLIENT_SECRET', '')
      provider_name = ENV.fetch('OIDC_ROUTE_NAME', 'oidc').to_sym

      missing = missing_env_vars(%w[OIDC_ISSUER OIDC_CLIENT_ID])
      if missing.any?
        if Onetime.auth_config.orgs_sso_enabled?
          OT.li "[OmniAuth] Registering OIDC route '#{provider_name}' for tenant SSO (no platform credentials)"
          auth.omniauth_provider(
            :openid_connect,
            name: provider_name,
            scope: [:openid, :email, :profile],
            response_type: :code,
            issuer: 'https://placeholder.invalid',
            client_options: { identifier: 'placeholder' },
            discovery: true,
            pkce: true,
          )
        else
          OT.le "[OmniAuth] Missing OIDC configuration: #{missing.join(', ')}"
        end
        return
      end

      OT.li "[OmniAuth] Configuring OIDC provider '#{provider_name}' with issuer: #{issuer}, client_id: #{client_id[0..8]}..."

      # redirect_uri is omitted here — the omniauth_setup hook injects it
      # at runtime from the request host (see omniauth_tenant.rb).
      client_opts          = { identifier: client_id }
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
      provider_name = ENV.fetch('ENTRA_ROUTE_NAME', 'entra').to_sym
      display_name  = ENV.fetch('ENTRA_DISPLAY_NAME', 'Microsoft')

      missing = missing_env_vars(%w[ENTRA_TENANT_ID ENTRA_CLIENT_ID ENTRA_CLIENT_SECRET])
      if missing.any?
        if Onetime.auth_config.orgs_sso_enabled?
          OT.li "[OmniAuth] Registering Entra ID route '#{provider_name}' for tenant SSO (no platform credentials)"
          auth.omniauth_provider(
            :entra_id,
            name: provider_name,
            client_id: 'placeholder',
            client_secret: 'placeholder',
            tenant_id: 'placeholder',
            scope: 'openid profile email',
          )
        else
          OT.le "[OmniAuth] Missing Entra ID configuration: #{missing.join(', ')}"
        end
        return
      end

      OT.li "[OmniAuth] Configuring Entra ID provider '#{provider_name}' (#{display_name}), client_id: #{client_id[0..8]}..."

      opts = {
        name: provider_name,
        client_id: client_id,
        client_secret: client_secret,
        tenant_id: tenant_id,
        scope: 'openid profile email',
      }
      auth.omniauth_provider(:entra_id, **opts)
    end

    def self.configure_github_provider(auth)
      client_id     = ENV.fetch('GITHUB_CLIENT_ID', nil)
      client_secret = ENV.fetch('GITHUB_CLIENT_SECRET', nil)
      provider_name = ENV.fetch('GITHUB_ROUTE_NAME', 'github').to_sym
      display_name  = ENV.fetch('GITHUB_DISPLAY_NAME', 'GitHub')

      missing = missing_env_vars(%w[GITHUB_CLIENT_ID GITHUB_CLIENT_SECRET])
      if missing.any?
        if Onetime.auth_config.orgs_sso_enabled?
          OT.li "[OmniAuth] Registering GitHub route '#{provider_name}' for tenant SSO (no platform credentials)"
          auth.omniauth_provider(
            :github,
            name: provider_name,
            client_id: 'placeholder',
            client_secret: 'placeholder',
            scope: 'user:email',
          )
        else
          OT.le "[OmniAuth] Missing GitHub configuration: #{missing.join(', ')}"
        end
        return
      end

      OT.li "[OmniAuth] Configuring GitHub provider '#{provider_name}' (#{display_name}), client_id: #{client_id[0..8]}..."

      opts = {
        name: provider_name,
        client_id: client_id,
        client_secret: client_secret,
        scope: 'user:email',
      }
      auth.omniauth_provider(:github, **opts)
    end

    def self.configure_google_provider(auth)
      client_id     = ENV.fetch('GOOGLE_CLIENT_ID', nil)
      client_secret = ENV.fetch('GOOGLE_CLIENT_SECRET', nil)
      provider_name = ENV.fetch('GOOGLE_ROUTE_NAME', 'google').to_sym
      display_name  = ENV.fetch('GOOGLE_DISPLAY_NAME', 'Google')

      missing = missing_env_vars(%w[GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET])
      if missing.any?
        if Onetime.auth_config.orgs_sso_enabled?
          OT.li "[OmniAuth] Registering Google route '#{provider_name}' for tenant SSO (no platform credentials)"
          auth.omniauth_provider(
            :google_oauth2,
            name: provider_name,
            client_id: 'placeholder',
            client_secret: 'placeholder',
            scope: 'openid,email,profile',
            prompt: 'select_account',
          )
        else
          OT.le "[OmniAuth] Missing Google configuration: #{missing.join(', ')}"
        end
        return
      end

      OT.li "[OmniAuth] Configuring Google provider '#{provider_name}' (#{display_name}), client_id: #{client_id[0..8]}..."

      opts = {
        name: provider_name,
        client_id: client_id,
        client_secret: client_secret,
        scope: 'openid,email,profile',
        prompt: 'select_account',
      }
      auth.omniauth_provider(:google_oauth2, **opts)
    end
  end
end
