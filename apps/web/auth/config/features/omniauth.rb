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

# Provider wiring (strategy, gem, env vars, placeholder/real options) is
# data in Onetime::SsoProviderRegistry — the same registry AuthConfig's
# serializer gating and CSP origins read. The strategy gems themselves are
# required lazily, per definition, in configure_provider.
require_relative '../../../../../lib/onetime/sso_provider_registry'

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

      # Register every provider in the registry — platform creds when
      # available, placeholder routes for tenant SSO when orgs_sso_enabled.
      # Adding a provider is a Gemfile line plus a registry entry; see
      # docs/authentication/adding-sso-providers.md.
      Onetime::SsoProviderRegistry::DEFINITIONS.each do |defn|
        configure_provider(auth, defn)
      end

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
    # ISSUERLESS PROVIDERS (GitHub, Google) — the gap Approach A cannot close.
    # Issuer-scoping isolates tenants because each OIDC/Entra tenant resolves a
    # DISTINCT issuer. OAuth2 providers with no issuer concept resolve to the ''
    # sentinel on EVERY surface (resolve_issuer #4), so a TENANT callback's step-1
    # EXACT lookup (provider, '', uid) — which carries no platform_path gate —
    # matches a PLATFORM- or OTHER-TENANT-created (provider, '', uid) row, exactly
    # the (provider, uid) cross-surface bind the re-key was meant to end. (A tenant
    # admin cannot forge a GitHub/Google uid — the provider attests it — so this is
    # not the item-5 uid-forgery takeover; but it still lets a tenant callback
    # AUTHENTICATE, and additively org-join, an account first linked on another
    # surface, breaking the surface-isolation invariant item 3 and the tenant
    # refusals in hooks/omniauth.rb enforce.) There is no per-tenant issuer to scope
    # on, so we FAIL CLOSED: refuse_issuerless_on_tenant? rejects issuerless
    # providers on the tenant surface BEFORE any lookup (wired into
    # retrieve_omniauth_identity). OIDC/Entra carry a real, tenant-distinct issuer
    # and are unaffected; issuerless SSO stays available on the PLATFORM surface.
    #
    # The pure decision functions below are driven verbatim by the auth-class
    # helpers wired in configure_issuer_scoped_identities, and unit/integration
    # tested directly.

    # Sentinel issuer for identities with no known IdP issuer. ALWAYS '' — never
    # nil (a NULL vs '' split breaks the (provider, issuer, uid) unique index).
    ISSUER_SENTINEL = ''

    # Resolve the issuer for the current callback.
    # Precedence:
    #   1. strategy option :issuer — OIDC discovery populates and validates this.
    #   2. token issuer (`iss`) from the auth hash's extra.raw_info — id-token
    #      providers (Entra ID) expose the validated `iss` claim here. OIDC never
    #      reaches this branch (its issuer resolves at #1); its raw_info is the
    #      UserInfo response, which per OIDC core §5.3.2 may omit `iss`.
    #   3. ENV['OIDC_ISSUER'] for the OIDC route.
    #   4. '' sentinel (OAuth2 providers with no issuer concept: GitHub/Google).
    #
    # Entra matters here: its strategy exposes :tenant_id, not :issuer, so #1
    # misses and without #2 every Entra tenant would collapse to '' —
    # reintroducing the item-5 collision for `ignore_tid: true` configs (where
    # the Entra uid degrades from `tid+oid` to `oid` alone). Scoping on the
    # validated `iss` makes the security property explicit rather than an
    # implicit consequence of the gem's uid composition.
    #
    # @param strategy_options [Hash, nil] omniauth_strategy&.options
    # @param provider [String, Symbol] omniauth_provider (route name)
    # @param oidc_route_name [String] configured OIDC route name (OIDC_ROUTE_NAME)
    # @param env_oidc_issuer [String, nil] ENV['OIDC_ISSUER']
    # @param token_issuer [String, nil] validated `iss` claim from extra.raw_info
    # @return [String] resolved issuer or the '' sentinel
    def self.resolve_issuer(strategy_options:, provider:, oidc_route_name:, env_oidc_issuer:,
                            token_issuer: nil)
      option_issuer = strategy_options && strategy_options[:issuer]
      return option_issuer.to_s if option_issuer && !option_issuer.to_s.empty?

      return token_issuer.to_s if token_issuer && !token_issuer.to_s.empty?

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

    # SECURITY-CRITICAL (#3840 follow-up / PR #3900 P1 "Issuerless identities
    # cross tenant boundaries"): must a callback be refused because it is an
    # issuerless provider (resolved issuer == '' sentinel) arriving on the TENANT
    # surface? Such a callback's exact (provider, '', uid) lookup would otherwise
    # match a platform- or other-tenant-created row (see the ISSUERLESS PROVIDERS
    # note above). Refusing here fails closed: no cross-surface match AND no JIT
    # '' row that could later collide on the platform side. Platform issuerless
    # callbacks (platform_path true) and tenant OIDC/Entra callbacks (non-''
    # issuer) are NOT refused.
    #
    # @param platform_path [Boolean] omniauth_platform_path?
    # @param resolved_issuer [String] resolve_issuer output for this callback
    # @return [Boolean] true when the callback must be refused
    def self.refuse_issuerless_on_tenant?(platform_path:, resolved_issuer:)
      !platform_path && resolved_issuer.to_s == ISSUER_SENTINEL
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
        # Resolver: strategy option > token `iss` (Entra) > ENV OIDC_ISSUER > ''.
        def resolved_issuer
          Auth::Config::Features::OmniAuth.resolve_issuer(
            strategy_options: omniauth_strategy&.options,
            provider: omniauth_provider,
            oidc_route_name: ENV.fetch('OIDC_ROUTE_NAME', 'oidc'),
            env_oidc_issuer: ENV.fetch('OIDC_ISSUER', nil),
            token_issuer: omniauth_token_issuer,
          )
        end

        # The validated `iss` claim from the auth hash's extra.raw_info, if the
        # strategy exposes one (Entra ID's raw_info is the decoded id_token). Nil
        # for OIDC (raw_info is the UserInfo response) and OAuth2 (no id_token).
        # Read defensively — extra/raw_info may be a plain Hash or an AuthHash.
        def omniauth_token_issuer
          extra = omniauth_extra
          return nil unless extra

          raw = extra['raw_info'] || extra[:raw_info]
          return nil unless raw

          raw['iss'] || raw[:iss]
        end

        # Platform (non-tenant) callback gate. The tenant hook
        # (hooks/omniauth_tenant.rb) sets session[:validated_omniauth_domain_id]
        # in before_omniauth_callback_route; rodauth-omniauth-0.6.2 runs that
        # hook (features/omniauth.rb:53 handle_omniauth_callback) BEFORE
        # retrieve_omniauth_identity (:62), so the signal is reliable here.
        #
        # VERSION-PINNED INVARIANT: this ordering (before_omniauth_callback_route
        # runs before retrieve_omniauth_identity) is what makes the security gate
        # sound. It holds in rodauth-omniauth >= 0.6.2; RE-VERIFY it whenever the
        # gem is upgraded — if a later version reorders the callback, tenant
        # callbacks could reach the '' legacy fallback and re-open the item-5
        # takeover.
        def omniauth_platform_path?
          Auth::Config::Features::OmniAuth.platform_path?(session[:validated_omniauth_domain_id])
        end
      end
      # rubocop:enable Lint/NestedMethodDefinition

      # SECURITY-CRITICAL override: issuer-aware identity lookup.
      #
      # `retrieve_omniauth_identity` is declared via auth_private_methods, so this
      # DSL block becomes the body of `_retrieve_omniauth_identity(provider, uid)`
      # — Rodauth invokes it with the two positional args (omniauth_provider,
      # omniauth_uid). The block MUST accept them or every callback 500s with
      # ArgumentError (wrong number of arguments).
      auth.retrieve_omniauth_identity do |provider, uid|
        issuer        = resolved_issuer
        platform_path = omniauth_platform_path?

        # SECURITY-CRITICAL: refuse issuerless providers (GitHub/Google) on the
        # tenant surface BEFORE any identity match. Their '' issuer is shared
        # across surfaces, so the exact (provider, '', uid) lookup below would
        # otherwise resolve a platform- or other-tenant-created row and log this
        # callback into it (and the additive org-join would pull that account
        # into this tenant's org). Halting here — before lookup_identity, so no
        # match — also blocks the create path (a tenant JIT-created '' row that
        # could later collide on the platform side). See
        # refuse_issuerless_on_tenant? and the ISSUERLESS PROVIDERS note above.
        # `redirect` throws :halt, caught by Roda in _handle_omniauth_callback
        # (the same mechanism the hooks/omniauth.rb refusals use).
        if Auth::Config::Features::OmniAuth.refuse_issuerless_on_tenant?(
          platform_path: platform_path, resolved_issuer: issuer,
        )
          Auth::Logging.log_auth_event(
            :omniauth_tenant_issuerless_refused,
            level: :warn,
            provider: provider,
          )
          redirect '/signin?auth_error=sso_not_configured'
        end

        Auth::Config::Features::OmniAuth.lookup_identity(
          ds: omniauth_identities_ds,
          id_col: omniauth_identities_id_column,
          provider_col: omniauth_identities_provider_column,
          uid_col: omniauth_identities_uid_column,
          issuer_col: :issuer,
          provider: provider,
          uid: uid,
          resolved_issuer: issuer,
          platform_path: platform_path,
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

    # Register one provider from its Onetime::SsoProviderRegistry definition.
    #
    # NOTE: The route name (name: option) controls both the URL route segment
    # AND the provider value stored in account_identities.provider and
    # returned in the auth hash. E.g. route name 'entra' means:
    #   - Route: POST /auth/sso/entra, GET /auth/sso/entra/callback
    #   - Auth hash: { provider: 'entra', ... }
    #   - DB: account_identities.provider = 'entra'
    #
    # Three outcomes, mirroring the original per-provider methods:
    #   - required env vars present  -> register with real credentials
    #   - vars missing, org SSO on   -> register with placeholder credentials
    #     (the OmniAuthTenant hook injects tenant credentials at request time)
    #   - vars missing, org SSO off  -> log the missing vars and skip
    def self.configure_provider(auth, defn)
      # Lazy per-definition require keeps the registry loadable without the
      # omniauth gems (e.g. simple mode reading provider_definitions).
      require defn[:gem_require]

      provider_name = ENV.fetch(defn[:route_var], defn[:route_default]).to_sym
      display_name  = ENV.fetch(defn[:display_var], nil) || defn[:display_default]

      missing = missing_env_vars(defn[:required_vars])
      if missing.any?
        if Onetime.auth_config.orgs_sso_enabled?
          OT.li "[OmniAuth] Registering #{defn[:label]} route '#{provider_name}' for tenant SSO (no platform credentials)"
          auth.omniauth_provider(defn[:strategy], name: provider_name, **defn[:placeholder_options])
        else
          OT.le "[OmniAuth] Missing #{defn[:label]} configuration: #{missing.join(', ')}"
        end
        return
      end

      client_id = defn[:required_vars].find { |var| var.end_with?('_CLIENT_ID') }
        &.then { |var| ENV.fetch(var, '') }
      OT.li "[OmniAuth] Configuring #{defn[:label]} provider '#{provider_name}' (#{display_name}), client_id: #{client_id.to_s[0..8]}..."

      auth.omniauth_provider(defn[:strategy], name: provider_name, **defn[:strategy_options].call)
    end

    # Named per-provider entry points, kept as thin wrappers over the
    # registry-driven configure_provider (existing specs and callers use
    # them). New providers do NOT need one — the configure loop registers
    # every registry definition.
    def self.configure_oidc_provider(auth)
      configure_provider(auth, Onetime::SsoProviderRegistry.fetch(:oidc))
    end

    def self.configure_entra_id_provider(auth)
      configure_provider(auth, Onetime::SsoProviderRegistry.fetch(:entra))
    end

    def self.configure_github_provider(auth)
      configure_provider(auth, Onetime::SsoProviderRegistry.fetch(:github))
    end

    def self.configure_google_provider(auth)
      configure_provider(auth, Onetime::SsoProviderRegistry.fetch(:google))
    end
  end
end
