# apps/web/auth/config/hooks/omniauth_tenant.rb
#
# frozen_string_literal: true

#
# Runtime SSO credential injection for multi-tenant configurations.
#
# This hook resolves tenant-specific SSO credentials from the request's
# PUBLIC host (env['onetime.display_domain'] — see .public_host; NOT the raw
# Host header, which a Host-rewriting proxy replaces with the origin target)
# and injects them into the OmniAuth strategy before authentication begins.
# It enables organizations to configure their own IdP connections without
# requiring platform environment variables.
#
# Flow (domain-based resolution):
#   1. display_domain -> CustomDomain lookup
#   2. CustomDomain.identifier -> CustomDomain::SsoConfig
#   3. SSO config -> omniauth strategy.options injection
#
# Each domain has its own SSO configuration, enabling multi-IdP setups where
# different domains owned by the same organization use different identity providers.
#
# Security Model:
#   - Tenant context (domain_id) stored in session during request phase
#   - Callback validates tenant context matches (prevents redirect attacks)
#   - Missing tenant config can either fall back to platform credentials
#     or reject the request based on `allow_platform_fallback_for_tenants`
#
# See: docs/authentication/omniauth-sso.md (full configuration guide)
# See: lib/onetime/models/custom_domain/sso_config.rb (per-domain SSO config)
# See: lib/onetime/models/custom_domain/signin_config.rb (SSO activation authority)
#

require 'onetime/models/custom_domain/signin_config'

require_relative '../../restrict_to'

module Auth::Config::Hooks
  module OmniAuthTenant
    # Module reference for calling helper methods from within Rodauth blocks
    HELPERS = self

    # Map CustomDomain::SsoConfig provider_type symbols to OmniAuth strategy class names.
    # Used to validate that credentials are being injected into the correct strategy.
    STRATEGY_CLASS_MAP = {
      openid_connect: %w[OmniAuth::Strategies::OpenIDConnect],
      entra_id: %w[OmniAuth::Strategies::EntraId OmniAuth::Strategies::AzureActivedirectoryV2],
      google_oauth2: %w[OmniAuth::Strategies::GoogleOauth2],
      github: %w[OmniAuth::Strategies::GitHub],
    }.freeze

    def self.configure(auth)
      # ========================================================================
      # HOOK: OmniAuth Setup - Runtime Credential Injection
      # ========================================================================
      #
      # USER JOURNEY CONTEXT:
      # This hook fires BEFORE the OmniAuth request phase, allowing us to
      # inject tenant-specific credentials into the strategy. The strategy
      # has already been selected based on the URL path (e.g., /auth/sso/oidc).
      #
      # NOTE: OmniAuth strategies are registered at boot with platform defaults.
      # This hook overrides those defaults at runtime for tenant-specific flows.
      #
      auth.omniauth_setup do
        host = HELPERS.public_host(request)

        # RESTRICT_TO ENFORCEMENT
        # (ADR-034#restrict-to-is-an-access-control-not-a-display-preference
        # / #reject-as-not-found-not-forbidden, #4139).
        #
        # The OmniAuth request phase is NOT in Rodauth's route_hash — it is
        # served by middleware run from route_omniauth!, so the before_rodauth
        # gate in hooks/restrict_to.rb never fires here. Without this block,
        # SSO stays fully reachable on a host restricted to password/email_auth
        # and enforcement is silently partial.
        #
        # Both phases are gated: the callback is a credential-bearing entry
        # point in its own right, so gating only the request phase would leave
        # a replayable surface. 404 (not the tenant-mismatch 403 below) because
        # a restricted-away method must present no reachable surface at all.
        unless Auth::RestrictTo.allows?(request.env, 'sso')
          Auth::Logging.log_auth_event(
            :restrict_to_omniauth_rejected,
            level: :info,
            host: host,
            path: request.path,
          )
          request.halt(Auth::RestrictTo.not_found_response)
        end

        # Skip tenant context storage during callback phase.
        # The setup hook fires for BOTH request and callback phases, but we only
        # want to store the initiating domain during the request phase. During
        # callback, the before_omniauth_callback_route hook validates that the
        # callback host matches the stored initiation host.
        #
        # Without this guard, an attacker could:
        # 1. Initiate auth on domain A (stores domain A's ID in session)
        # 2. Redirect callback to domain B
        # 3. Setup hook fires on domain B, overwrites session with domain B's ID
        # 4. Callback validation sees domain B → no mismatch detected
        strategy          = request.env['omniauth.strategy']
        is_callback_phase = strategy&.on_callback_path?

        # OIDC strategies require an explicit redirect_uri in both the
        # authorize request and token exchange. Unlike OAuth2-based strategies,
        # omniauth_openid_connect reads client_options.redirect_uri verbatim
        # (no auto-construction from the request host). We set it here so the
        # value derives from the current request host — correct for both
        # install-level (canonical domain) and domain-level (custom domain).
        # Must be identical across both phases (authorize + callback).
        if strategy&.options&.dig(:discovery) == true
          redirect_uri                                     = strategy.full_host + strategy.callback_path
          strategy.options[:client_options]              ||= {}
          strategy.options[:client_options][:redirect_uri] = redirect_uri
        end

        Auth::Logging.log_auth_event(
          :omniauth_tenant_resolution_start,
          level: :debug,
          host: host,
          path: request.path,
          ip: request.ip,
          is_callback_phase: is_callback_phase,
        )

        # Attempt to resolve tenant from custom domain
        custom_domain = HELPERS.resolve_custom_domain(host)

        unless custom_domain
          # Check if this is the platform's canonical domain.
          # Canonical domain requests are platform-level, not tenant requests,
          # so tenant fallback policy should not apply.
          if HELPERS.canonical_domain?(host)
            Auth::Logging.log_auth_event(
              :omniauth_canonical_domain_request,
              level: :debug,
              host: host,
            )
            next # Continue with platform defaults
          end

          # Non-canonical domain with no custom domain mapping - apply tenant policy
          HELPERS.handle_missing_tenant_config(host, self)
          next # Continue with platform defaults (if allowed)
        end

        # Look up domain-specific SSO configuration (credentials store) and
        # gate it on SsoConfig.tenant_sso_unavailable_reason — the shared
        # availability authority (enabled credentials + SigninConfig's
        # sso_permitted_for? activation gate + the AUTH_ENABLED master
        # switch), returning the failing rung instead of a bare boolean. This
        # is the runtime half of the parity gate; the display halves (masthead
        # link via DomainSerializer#effective_signin_enabled?, /signin page via
        # config_serializer.rb#resolve_tenant_sso_config) consult the same
        # ladder through its boolean face, tenant_sso_available_for?. All gates
        # MUST produce the same active/inactive decision for any domain so the
        # SSO button is never shown when this route would reject (and never
        # hidden when it works). AUTH_ENABLED=false therefore lands in
        # handle_missing_tenant_config like any unconfigured tenant, where the
        # same master switch withholds platform fallback — the request rejects
        # regardless of fallback policy, matching the darkened display
        # surfaces for that state. (Defense-in-depth: the Auth::Router guard
        # already 404s the whole /auth surface before this hook can fire.)
        # Load once and hand the record to the ladder: the availability check
        # needs the same SsoConfig this hook already loaded for credential
        # injection, so passing it avoids a second identical Redis read per
        # request. Absence is NOT short-circuited here — the ladder reports it
        # as :no_sso_config, which is what gets logged, so operators can tell
        # "no credentials store" apart from "disabled", "SSO withheld by
        # SigninConfig", and "master switch off".
        sso_config         = Onetime::CustomDomain::SsoConfig.find_by_domain_id(custom_domain.identifier)
        unavailable_reason = Onetime::CustomDomain::SsoConfig.tenant_sso_unavailable_reason(
          custom_domain.identifier, sso_config: sso_config
        )

        if unavailable_reason
          Auth::Logging.log_auth_event(
            :omniauth_tenant_sso_not_enabled,
            level: :info,
            host: host,
            domain_id: custom_domain.identifier,
            reason: unavailable_reason,
          )

          # Check if we should fall back to platform credentials
          HELPERS.handle_missing_tenant_config(host, self)
          next # Continue with platform defaults (if allowed)
        end

        # Cache the loaded record for the rest of this rack request: on the
        # callback phase, before_omniauth_callback_route's allowlist
        # enforcement needs the same SsoConfig and would otherwise pay a
        # second identical Redis read per callback.
        request.env['onetime.tenant_sso_config'] = sso_config

        # Store tenant context in session for callback validation.
        # Only during request phase — callback phase must NOT overwrite the
        # stored context, otherwise the mismatch check is defeated.
        unless is_callback_phase
          session[:omniauth_tenant_domain_id] = custom_domain.identifier
          session[:omniauth_tenant_host]      = host
        end

        Auth::Logging.log_auth_event(
          :omniauth_tenant_credentials_injecting,
          level: :info,
          host: host,
          domain_id: custom_domain.identifier,
          provider_type: sso_config.provider_type,
        )

        # Inject tenant-specific credentials into strategy
        HELPERS.inject_tenant_credentials(sso_config, request, self)
      end

      # ========================================================================
      # HOOK: Before OmniAuth Callback - Logging + Tenant Context Validation
      # ========================================================================
      #
      # USER JOURNEY CONTEXT:
      # This hook fires at the very start of callback processing.
      # We validate that the callback is arriving at the same tenant that
      # initiated the auth request. This prevents cross-tenant redirect attacks.
      #
      # OWNERSHIP: Rodauth hooks do NOT chain — each auth.before_omniauth_callback_route
      # call REPLACES the previous definition. This is the SOLE definition of the
      # hook (omniauth.rb used to define one too; registered first in config.rb,
      # it was silently clobbered by this one — the #3275 pattern). This block
      # therefore does both jobs: log callback start, then validate the tenant.
      #
      auth.before_omniauth_callback_route do
        # RESTRICT_TO ENFORCEMENT
        # (ADR-034#restrict-to-is-an-access-control-not-a-display-preference
        # / #reject-as-not-found-not-forbidden, #4139). Belt to
        # omniauth_setup's braces: this hook fires on the callback route even
        # when a strategy short-circuits setup, and it is the last point before
        # the identity is consumed.
        unless Auth::RestrictTo.allows?(request.env, 'sso')
          Auth::Logging.log_auth_event(
            :restrict_to_omniauth_callback_rejected,
            level: :info,
            host: HELPERS.public_host(request),
            path: request.path,
          )
          request.halt(Auth::RestrictTo.not_found_response)
        end

        Auth::Logging.log_auth_event(
          :omniauth_callback_start,
          level: :info,
          provider: omniauth_provider,
          uid: omniauth_uid,
          email: OT::Utils.obscure_email(omniauth_email),
          ip: request.ip,
        )

        expected_domain_id = session.delete(:omniauth_tenant_domain_id)
        expected_host      = session.delete(:omniauth_tenant_host)

        # If no tenant context was stored, this was a platform-level auth
        # (no tenant credentials were injected). Allow it to proceed.
        next unless expected_domain_id

        # Resolve current request's tenant context
        current_domain = HELPERS.resolve_custom_domain(HELPERS.public_host(request))

        # Validate tenant context matches - domain_id must match exactly
        domain_mismatch = current_domain&.identifier != expected_domain_id

        if domain_mismatch
          Auth::Logging.log_auth_event(
            :omniauth_tenant_mismatch,
            level: :warn,
            expected_domain_id: expected_domain_id,
            expected_host: expected_host,
            actual_host: HELPERS.public_host(request),
            actual_domain_id: current_domain&.identifier,
            ip: request.ip,
            session_id_hash: Digest::SHA256.hexdigest(session.id.to_s)[0, 16],
          )

          # Return 403 directly rather than throw_error_status, which throws
          # :rodauth_error that may not be caught in OmniAuth callback context.
          response.status          = 403
          response['Content-Type'] = 'application/json'
          response.write(
            JSON.generate(
              error: 'tenant_mismatch',
              message: 'Authentication context mismatch',
            ),
          )
          request.halt
        end

        # ────────────────────────────────────────────────────────────────
        # TENANT SSO EMAIL-DOMAIN ALLOWLIST
        # ────────────────────────────────────────────────────────────────
        #
        # Enforce CustomDomain::SsoConfig#allowed_domains — the access control
        # the SSO config UI, the API and the provider metadata all present to
        # operators as the way to restrict a generic OIDC IdP to their own
        # email domains ('oidc' declares requires_domain_filter: true,
        # sso_config.rb). It had no runtime call site at all: the only domain
        # gate that ran was before_omniauth_create_account (hooks/omniauth.rb),
        # which consults a DIFFERENT object (CustomDomain::SignupConfig / the
        # global allowed_signup_domains) and runs on the CREATE path only.
        #
        # THIS hook is the enforcement point precisely because it is not the
        # create path: before_omniauth_callback_route is the first statement of
        # rodauth-omniauth's _handle_omniauth_callback, so it runs on EVERY
        # callback — JIT creation and every subsequent sign-in alike — before
        # the gem branches on whether an (provider, issuer, uid) identity row
        # already exists. account_from_omniauth and before_omniauth_create_account
        # are both skipped once that row exists, which is why a create-only gate
        # let a user keep signing in indefinitely after their domain was removed
        # from the allowlist. The auth hash is already available here — the
        # logging above reads omniauth_provider/omniauth_uid/omniauth_email.
        #
        # Placed AFTER the tenant-mismatch check so the allowlist consulted is
        # the one belonging to the domain that actually initiated this flow, and
        # BEFORE the validated stamp below so a rejected callback never leaves
        # :validated_omniauth_domain_id behind for the org-join hooks.
        #
        # Fails closed on every branch it can: a config that has gone missing, an
        # unreadable allowlist, and a missing/malformed asserted email are all
        # denials rather than pass-throughs. An EMPTY allowlist still means
        # allow-all — that is the documented, spec-asserted state and the correct
        # one for Entra ID, where the IdP controls access via app assignment.
        HELPERS.enforce_tenant_email_domain!(
          expected_domain_id,
          omniauth_email,
          self,
          sso_config: request.env['onetime.tenant_sso_config'],
        )

        # Re-store validated domain_id under a separate key so downstream hooks
        # (after_omniauth_create_account, after_login) can join the tenant org.
        # The original :omniauth_tenant_domain_id is intentionally consumed by
        # session.delete above — separating "pending" from "validated" state.
        session[:validated_omniauth_domain_id] = expected_domain_id

        Auth::Logging.log_auth_event(
          :omniauth_tenant_callback_validated,
          level: :debug,
          domain_id: expected_domain_id,
          host: HELPERS.public_host(request),
        )
      end
    end

    # ==========================================================================
    # Helper Methods
    # ==========================================================================
    #
    # These are module methods called via HELPERS constant from Rodauth blocks.
    # They cannot access Rodauth instance methods directly - pass needed objects.
    #

    # The PUBLIC host for this request — the hostname the browser used.
    #
    # Tenant SSO is keyed on CustomDomain#display_domain, so the lookup must
    # use the host the visitor typed, not the authority the origin happens to
    # see. Behind Approximated (and any Host-rewriting proxy) those differ:
    # the browser asks for nz.example.com, Approximated forwards it as
    # `Apx-Incoming-Host` and rewrites `Host:` to the origin target, so
    # `request.host` reads as the platform host and every custom-domain
    # lookup misses — the tenant SSO POST 302s to
    # `/signin?auth_error=sso_not_configured` while the same request's
    # DomainStrategy classification says `custom`.
    #
    # `env['onetime.display_domain']` is that resolution: Rack::DetectHost
    # picks the forwarded host ONLY from trusted infrastructure and
    # DomainStrategy validates it (falling back to the canonical host), so it
    # is also the safer key — Rack 3.2's `request.host` prefers
    # `X-Forwarded-Host`/`Forwarded` from ANY client, ungated by proxy trust.
    #
    # Same source the rest of the custom-domain surface already reads:
    # HttpOriginOptions (#4170), Auth::SigninGate, Auth::RestrictTo and
    # TenantSsoResolution — so the runtime gate here and the display gates
    # that decide whether to render the SSO button cannot disagree about
    # which tenant a request belongs to.
    #
    # @param request [Rack::Request] current request
    # @return [String] display domain, or request.host when the middleware
    #   did not run (bare-Rack specs, tryouts)
    def self.public_host(request)
      display_domain = request.env['onetime.display_domain'].to_s
      return display_domain unless display_domain.empty?

      request.host
    end

    # Resolve custom domain from hostname.
    # Returns nil if no custom domain mapping exists.
    #
    # @param host [String] Request hostname
    # @return [Onetime::CustomDomain, nil]
    def self.resolve_custom_domain(host)
      return nil if host.to_s.empty?

      Onetime::CustomDomain.load_by_display_domain(host)
    rescue Redis::BaseError => ex
      Auth::Logging.log_auth_event(
        :omniauth_tenant_resolution_error,
        level: :error,
        host: host,
        error: ex.message,
      )
      nil
    end

    # Check if host is one of the platform's canonical hosts.
    #
    # Platform-level requests (on any canonical host — site.host or
    # features.domains.default) should not be subject to tenant fallback
    # policy - they are not tenant requests at all. Uses the middleware's
    # set-backed predicate so auth and request classification can never
    # disagree about which hosts are canonical (split deployments).
    #
    # @param host [String] Request hostname (from #public_host, excludes port)
    # @return [Boolean] true if host is in the canonical host set
    def self.canonical_domain?(host)
      return false if host.to_s.empty?

      Onetime::Middleware::DomainStrategy.canonical_host?(host)
    end

    # Enforce a tenant's SSO email-domain allowlist, halting the callback when
    # the IdP-asserted address is not permitted.
    #
    # Runs on both the account-creation and the sign-in path (see the call site
    # in before_omniauth_callback_route for why that hook is the enforcement
    # point). Returns normally only when the address is allowed.
    #
    # FAIL-CLOSED LADDER. Reached only for a callback whose tenant context has
    # already been validated, so every rung below describes a tenant flow we
    # cannot authorize, not an ordinary platform sign-in:
    #
    #   no SsoConfig      - the record backing this flow is gone (deleted or
    #                       unreadable mid-flow). We have no policy to apply and
    #                       cannot conclude "unrestricted", so deny.
    #   corrupt allowlist - a value is present but unparseable. Denying keeps a
    #                       damaged allowlist from silently becoming allow-all;
    #                       see SsoConfig#allowed_domains_corrupt?.
    #   unusable email    - absent, or not matching the accounts.valid_email
    #                       shape. This rung is load-bearing, not hygiene:
    #                       valid_email_domain? takes the segment after the
    #                       LAST '@', so for an allowlist of ['example.com'] the
    #                       asserted address attacker@evil.com@example.com
    #                       resolves to example.com and the allowlist ALONE
    #                       returns true. The structural check rejects it first
    #                       (nothing after the first '@' may contain another
    #                       '@'). Note the mirror image, user@example.com@evil.com,
    #                       proves nothing here — it resolves to evil.com and the
    #                       allowlist rejects it unaided. Any regression test for
    #                       this rung must use the FORMER ordering.
    #   domain not listed - the ordinary rejection.
    #
    # An empty allowlist is NOT a rung — valid_email_domain? returns true and
    # the callback proceeds. That is the documented allow-all state.
    #
    # Rejections reuse auth_error=domain_not_allowed, which Login.vue already
    # renders from a localized key and which deliberately does not disclose the
    # configured domains. The audit event is distinct
    # (:omniauth_tenant_domain_rejected) so operators can still tell a tenant
    # allowlist denial apart from the signup-domain denial in hooks/omniauth.rb.
    # The asserted address is attacker-controlled, so it is obscured in logs.
    #
    # @param domain_id [String] validated CustomDomain identifier for this flow
    # @param email [String, nil] IdP-asserted email address
    # @param rodauth [Rodauth] Rodauth instance (for redirect)
    # @param sso_config [Onetime::CustomDomain::SsoConfig, nil] record already
    #   loaded by omniauth_setup on this request (rack-env cache); trusted only
    #   when its domain_id matches, otherwise re-fetched
    # @return [void]
    def self.enforce_tenant_email_domain!(domain_id, email, rodauth, sso_config: nil)
      # omniauth_setup loads this record on the same request; accepting it
      # avoids a second Redis read per callback. Trust it only when it belongs
      # to the validated domain — anything else (nil, setup short-circuited by
      # the strategy, mismatched record) falls back to a fresh fetch so the
      # ladder below stays fail-closed.
      sso_config   = nil unless sso_config&.domain_id == domain_id
      sso_config ||= Onetime::CustomDomain::SsoConfig.find_by_domain_id(domain_id)

      # Normalized exactly as the sibling signup-domain gate normalizes it
      # (before_omniauth_create_account, hooks/omniauth.rb), so the two gates
      # cannot disagree about what address they are judging. Without the strip
      # an IdP that pads the claim would fail the structural check below and be
      # denied for the wrong reason.
      candidate = email.to_s.strip.downcase

      reason = if sso_config.nil?
                 :no_sso_config
               elsif sso_config.allowed_domains_corrupt?
                 :allowlist_unreadable
               elsif sso_config.allowed_domains.empty?
                 nil # No allowlist configured — every authenticated identity is permitted.
               elsif !Onetime::SignupValidation.structurally_valid_email?(candidate)
                 :unusable_email
               elsif !sso_config.valid_email_domain?(candidate)
                 :domain_not_allowed
               end

      return unless reason

      Auth::Logging.log_auth_event(
        :omniauth_tenant_domain_rejected,
        level: :warn,
        domain_id: domain_id,
        email: OT::Utils.obscure_email(email),
        reason: reason,
      )

      rodauth.send(:redirect, '/signin?auth_error=domain_not_allowed')
    end

    # Handle requests where no tenant SSO config is available.
    # Either allows fallback to platform credentials or rejects.
    #
    # Configured via auth_config.allow_platform_fallback_for_tenants?, but
    # fallback also requires the AUTH_ENABLED master switch: platform
    # credentials must not process sign-ins the app would ignore anyway
    # (SigninConfig.global_auth_enabled false → every session reads as
    # unauthenticated), so a global kill always takes the reject path.
    #
    # @param host [String] Request hostname for logging
    # @param rodauth [Rodauth] Rodauth instance (for throw_error_status)
    # @raise [Rodauth::Error] if fallback not allowed
    def self.handle_missing_tenant_config(host, rodauth)
      if Onetime.auth_config.allow_platform_fallback_for_tenants? &&
         Onetime::CustomDomain::SigninConfig.global_auth_enabled
        Auth::Logging.log_auth_event(
          :omniauth_tenant_fallback_to_platform,
          level: :debug,
          host: host,
        )
        return # Continue with platform defaults
      end

      Auth::Logging.log_auth_event(
        :omniauth_tenant_no_config,
        level: :warn,
        host: host,
      )

      rodauth.send(:redirect, '/signin?auth_error=sso_not_configured')
    end

    # Inject tenant credentials into the OmniAuth strategy.
    #
    # Accesses the strategy from request.env['omniauth.strategy'] and
    # merges in the tenant's OAuth configuration.
    #
    # @param sso_config [Onetime::CustomDomain::SsoConfig] The SSO config
    # @param request [Rack::Request] The current request
    # @param rodauth [Rodauth] Rodauth instance (for throw_error_status)
    # @raise [Rodauth::Error] if strategy type doesn't match configuration
    def self.inject_tenant_credentials(sso_config, request, rodauth)
      strategy = request.env['omniauth.strategy']
      return unless strategy

      options = sso_config.to_omniauth_options

      # Extract the strategy-specific options (excluding :strategy and :name keys
      # which are used for provider registration, not runtime configuration)
      expected_strategy = options.delete(:strategy)
      _strategy_name    = options.delete(:name)

      # Validate strategy type matches configuration to prevent credential injection
      # into wrong strategy (e.g., Google credentials into OIDC strategy)
      unless strategy_matches?(strategy, expected_strategy)
        Auth::Logging.log_auth_event(
          :omniauth_strategy_mismatch,
          level: :warn,
          expected_strategy: expected_strategy,
          actual_strategy: strategy.class.name,
          domain_id: sso_config.domain_id,
          provider_type: sso_config.provider_type,
        )
        rodauth.send(
          :throw_error_status,
          400,
          'provider_mismatch',
          "SSO provider mismatch: tenant configured #{sso_config.provider_type}, but request is for #{strategy.class.name}",
        )
      end

      Auth::Logging.log_auth_event(
        :omniauth_strategy_options_merging,
        level: :debug,
        strategy_class: strategy.class.name,
        options_keys: options.keys.join(','),
      )

      # Merge tenant options into strategy
      # This modifies the strategy's options hash in place
      merge_strategy_options(strategy, options)

      # For OIDC strategies, clear memoized discovery data
      # The strategy may have cached the discovery document and client
      # from boot-time configuration; we need fresh instances.
      clear_oidc_memoization(strategy)
    end

    # Check if the active OmniAuth strategy matches the expected type.
    #
    # @param strategy [OmniAuth::Strategy] The active strategy instance
    # @param expected_type [Symbol] Expected strategy type from CustomDomain::SsoConfig
    # @return [Boolean] true if strategy class matches expected type
    def self.strategy_matches?(strategy, expected_type)
      return false unless strategy && expected_type

      expected_classes = STRATEGY_CLASS_MAP[expected_type]
      return false unless expected_classes

      expected_classes.include?(strategy.class.name)
    end

    # Merge options into the strategy, handling nested client_options.
    #
    # @param strategy [OmniAuth::Strategy] The active strategy
    # @param options [Hash] Options to merge
    def self.merge_strategy_options(strategy, options)
      options.each do |key, value|
        if key == :client_options && value.is_a?(Hash)
          # Deep merge client_options for OIDC
          strategy.options[:client_options] ||= {}
          value.each do |client_key, client_value|
            strategy.options[:client_options][client_key] = client_value
          end
        else
          strategy.options[key] = value
        end
      end
    end

    # Clear memoized OIDC discovery data on the strategy.
    #
    # OmniAuth::Strategies::OpenIDConnect memoizes @config (discovery doc)
    # and @client (OpenIDConnect::Client instance). When we inject new
    # credentials at runtime, these cached objects have stale data.
    #
    # @param strategy [OmniAuth::Strategy] The active strategy
    def self.clear_oidc_memoization(strategy)
      # Only clear for OIDC-based strategies
      return unless strategy.respond_to?(:options) &&
                    strategy.options[:discovery] == true

      # Clear memoized instance variables if they exist
      # This forces the strategy to re-fetch discovery and re-create client
      strategy.instance_variable_set(:@config, nil) if strategy.instance_variable_defined?(:@config)
      strategy.instance_variable_set(:@client, nil) if strategy.instance_variable_defined?(:@client)

      Auth::Logging.log_auth_event(
        :omniauth_oidc_memoization_cleared,
        level: :debug,
        strategy_class: strategy.class.name,
      )
    end
  end
end
