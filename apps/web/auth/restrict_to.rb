# apps/web/auth/restrict_to.rb
#
# frozen_string_literal: true

#
# Runtime enforcement of `restrict_to` (ADR-024 A1 + A7, issue #4139).
#
# WHAT THIS CLOSES
#   PR #4130 shipped the DISPLAY half: a restricted host renders exactly one
#   sign-in method. The server still ACCEPTED a crafted POST to every other
#   method's endpoint. A1 makes `restrict_to` an access control: when
#   resolution yields a single method for a request host, the server MUST
#   reject submission of every other method on that host.
#
# REJECT SHAPE — 404, not 403 (A7)
#   A restricted-away method presents NO reachable surface, matching Rodauth's
#   behavior for a feature that was never loaded. A 403 gate would leave the
#   handler mounted and reachable — "configuration presenting as availability",
#   the exact shape A1 exists to kill. The body is the router's shared
#   Auth::ErrorTranslator::NOT_FOUND_BODY so a gated route is byte-identical to
#   an undefined one.
#
#   SsoOnlyGating's 403 + error_key is DELIBERATELY NOT reconciled with this
#   (A7, "Scope, settled"): it governs account-scoped credential MANAGEMENT for
#   an already-identified user, where an actionable error beats a mystery.
#
# MECHANISM — before_rodauth
#   Rodauth builds `route_hash` once and FREEZES it in post_configure, and
#   `route!` is a frozen-hash lookup — returning nil from `login_route` per
#   request does nothing, and routes cannot be un-mounted per host. The gate is
#   therefore request-time and *emulates* non-existence. `before_rodauth` fires
#   inside the matched route, after `@current_route` is set and after CSRF has
#   been checked (rodauth.rb, `define_method(handle_meth)`), which is exactly
#   where the route's identity is known and nothing has executed yet.
#
# WHERE THIS LIVES, AND WHY NOT UNDER config/hooks/. This is the POLICY, and it
# has three callers in two different worlds: the Rodauth hook
# (config/hooks/restrict_to.rb), the OmniAuth hooks
# (config/hooks/omniauth_tenant.rb), and two plain Roda routes
# (routes/link_sso.rb, routes/sso_link_confirm.rb). Everything under config/ can
# only be required once Auth::Config exists (it is namespaced into it), which
# the route files and their unit specs do not require and must not be made to.
# So the policy lives here, beside error_translator.rb, as a plain module with
# no boot chain, and config/hooks/restrict_to.rb is the thin Rodauth wiring.
#
# THIS IS NOT THE WHOLE GATE. Three surfaces, and a gap in any one leaves
# enforcement open while looking closed:
#   1. Rodauth routes — config/hooks/restrict_to.rb, which calls .enforce_route!
#      from before_rodauth.
#   2. SSO (OmniAuth request phase) — NOT in route_hash at all; served by
#      middleware, so before_rodauth never fires. Gated in
#      config/hooks/omniauth_tenant.rb (omniauth_setup +
#      before_omniauth_callback_route) and in the app-owned SSO linking routes
#      (routes/link_sso.rb, routes/sso_link_confirm.rb) via .allows?.
#   3. Simple mode — POST /auth/login is served by Core, not Rodauth
#      (apps/web/core/routes.txt). Gated in
#      Core::Controllers::Base#restrict_to_allows?.
#
# See: docs/architecture/decision-records/adr-024-custom-domain-auth-override-resolution.md
#      (A1, A3, A7 — normative), lib/onetime/models/custom_domain/signin_config.rb
#      (the A2 resolver; resolution is owned there and re-derived nowhere).
#

require 'json'

require 'onetime/models/custom_domain/signin_config'
require 'onetime/models/custom_domain/sso_config'
require_relative 'error_translator'
require_relative 'lib/logging'

module Auth
  module RestrictTo
    # Sign-in method a pre-auth Rodauth route belongs to, keyed by
    # `@current_route` (the symbol passed to Rodauth's `route(...)`, NOT the
    # URL — the URLs are configurable and several are renamed in
    # config/features/).
    #
    # Every route here goes dark when its method is restricted away. Secondary
    # endpoints are included on purpose (A7): a gate that covers POST /login
    # and misses the ceremony-start endpoint leaves the gap open while looking
    # closed, which is worse than no gate because it invites documenting
    # restrict_to as an access control it does not provide.
    PRE_AUTH_ROUTES = {
      # --- password ---------------------------------------------------------
      login: 'password',
      # These three are password routes by default, but become WebAuthn routes
      # when Rodauth's webauthn_verify_account feature is loaded. See
      # WEBAUTHN_VERIFY_ACCOUNT_ROUTES below.
      create_account: 'password',
      verify_account: 'password',
      verify_account_resend: 'password',
      reset_password_request: 'password',
      reset_password: 'password',

      # --- email_auth (magic links) ----------------------------------------
      email_auth_request: 'email_auth',
      email_auth: 'email_auth',

      # --- webauthn (passkeys) ---------------------------------------------
      webauthn_login: 'webauthn',
      webauthn_autofill_js: 'webauthn',
    }.freeze

    # Rodauth's webauthn_verify_account feature changes the signup ceremony
    # without changing its route names: create_account_set_password? and
    # verify_account_set_password? become false, verification registers a
    # WebAuthn credential, and its autologin is marked as `webauthn`. Resending
    # the verification email must follow the same classification so that a
    # WebAuthn-only signup can complete after an expired or lost email.
    WEBAUTHN_VERIFY_ACCOUNT_ROUTES = [
      :create_account,
      :verify_account,
      :verify_account_resend,
    ].freeze

    # WebAuthn routes that are reachable only with a partially-authenticated
    # session (require_login + require_two_factor_not_authenticated), i.e. the
    # SECOND-FACTOR ceremony rather than a sign-in method offer.
    #
    # NOT gated, per ADR-024 A10. A7's endpoint enumeration listed these; the
    # enumeration was wrong and A7's own principle overrides it. `restrict_to`
    # governs which methods may be OFFERED as a sign-in choice on a host. A
    # second factor is not a choice — the account already authenticated with a
    # first factor the host permits, and the second factor is a property of the
    # ACCOUNT, which is the #4138 axis, not the request host.
    #
    # Gating them is a lockout: on a host restricted to 'sso' or 'password', an
    # account whose second factor is a passkey could never complete the
    # challenge. Note the internal inconsistency that made this obvious —
    # `otp_auth` (the TOTP second-factor ceremony) sits in UNGATED_ROUTES. The
    # same ceremony must not be gated for one authenticator and exempt for
    # another.
    SECOND_FACTOR_ROUTES = {
      webauthn_auth: 'webauthn',
      webauthn_auth_js: 'webauthn',
    }.freeze

    GATED_ROUTES = PRE_AUTH_ROUTES.freeze

    # Routes this gate deliberately does NOT touch. Named explicitly (rather
    # than defaulted-open) so the coverage spec can fail when a new Rodauth
    # route appears and nobody classified it — an unclassified route silently
    # defaulting to "allowed" is how surface #1 rots.
    #
    # Three reasons appear here:
    #   - ACCOUNT-SCOPED (A7 "Scope, settled"): reachable only when
    #     authenticated, so keying them to the REQUEST HOST is the wrong axis.
    #     They belong to SsoOnlyGating / #4138.
    #   - INSTALL-WIDE SECURITY POSTURE: MFA/lockout are explicitly not
    #     per-domain overridable (ADR-024 scope boundary).
    #   - NOT A SIGN-IN METHOD: logout must never 404.
    UNGATED_ROUTES = [
      *SECOND_FACTOR_ROUTES.keys, # second-factor ceremony, not a method offer (A10)
      :logout,
      :remember,
      :close_account,
      :change_password,
      :change_login,
      :verify_login_change,
      :confirm_password,
      :unlock_account,
      :unlock_account_request,
      :otp_auth,
      :otp_setup,
      :otp_disable,
      :otp_unlock,
      :recovery_auth,
      :recovery_codes,
      :two_factor_auth,
      :two_factor_manage,
      :two_factor_disable,
      :webauthn_setup,
      :webauthn_setup_js,
      :webauthn_remove,
    ].freeze

    class << self
      # Gate the currently-matched Rodauth route.
      #
      # @param rodauth [Rodauth::Auth]
      def enforce_route!(rodauth)
        route       = rodauth.current_route
        method_name = GATED_ROUTES[route]
        return unless method_name

        if WEBAUTHN_VERIFY_ACCOUNT_ROUTES.include?(route) && rodauth.features.include?(:webauthn_verify_account)
          method_name = 'webauthn'
        end

        enforce_method!(rodauth, method_name, route)
      end

      # Gate an explicit sign-in method for the current request.
      #
      # @param rodauth [Rodauth::Auth]
      # @param method_name [String] one of SigninConfig::RESTRICT_TO_VALUES
      # @param route [Symbol] for logging only
      def enforce_method!(rodauth, method_name, route)
        # Internal requests (Rodauth's internal_request feature) synthesize a
        # bare env with no Host and no DomainStrategy classification, and are
        # server-initiated app operations rather than a visitor choosing a
        # sign-in method on a host — e.g. invite signup autologin. Gating them
        # would break app flows for a policy about REQUEST HOSTS that an
        # internal request does not have. handle_internal_request calls
        # before_rodauth directly, so this guard is load-bearing.
        return if rodauth.send(:internal_request?)

        resolution = resolution_for(rodauth.request.env)
        return if resolution.allows?(method_name)

        Auth::Logging.log_auth_event(
          :restrict_to_route_rejected,
          level: :info,
          route: route,
          auth_method: method_name,
          restrict_to: resolution.restrict_to,
          restrict_state: resolution.state,
          restrict_source: resolution.source,
          host: rodauth.request.env['onetime.display_domain'],
          path: rodauth.request.path,
        )

        rodauth.request.halt(not_found_response)
      end

      # Whether `method_name` may be used on the host this request arrived on.
      #
      # Public entry point for the surfaces that are NOT Rodauth routes: the
      # OmniAuth hooks (middleware-served request phase) and the app-owned SSO
      # linking routes.
      #
      # NARROWING FILTER ONLY — callers still AND this with the method's own
      # enablement check (see RestrictToResolution#allows?).
      #
      # @param env [Hash] Rack env
      # @param method_name [String, Symbol]
      # @return [Boolean]
      def allows?(env, method_name)
        resolution_for(env).allows?(method_name)
      end

      # Resolver output for the request host (ADR-024 A2).
      #
      # This method GATHERS INPUTS ONLY. Precedence between global and domain,
      # and the fail-closed degradation of a restriction whose method cannot be
      # honored, are decided by SigninConfig.resolve_restrict_to and re-derived
      # nowhere — mirroring ConfigSerializer#restrict_to_resolution, the display
      # consumer, so the rendered page and the route gate cannot disagree.
      #
      # @param env [Hash] Rack env
      # @return [Onetime::CustomDomain::SigninConfig::RestrictToResolution]
      def resolution_for(env)
        domain_id     = domain_id_for(env)
        signin_config = Onetime::CustomDomain::SigninConfig.find_by_domain_id(domain_id) if domain_id
        global        = global_restrict_to(env, domain_id, signin_config)

        Onetime::CustomDomain::SigninConfig.resolve_restrict_to(
          global,
          signin_config,
          available: restriction_available_for_host?(
            env,
            global,
            signin_config,
            domain_id,
          ),
        )
      rescue Redis::BaseError => ex
        lookup_failure_resolution(env, ex, signin_config)
      end

      # Resolution for a request whose datastore reads failed.
      #
      # THREE READS CAN RAISE HERE, all on the hot path of every request to a
      # custom host: the CustomDomain lookup, the SigninConfig lookup, and the
      # SSO probes behind the 'sso' host pin and the availability gathering. So
      # this path is reached by a transient blip, not only by a real outage, and
      # what it returns is what every gated route on every custom domain does
      # until the blip clears.
      #
      # FAIL CLOSED WHERE THAT IS LOAD-BEARING, AND ONLY THERE. When a
      # restriction IS in force — the operator's global one, or a domain one we
      # had already read before the failure — we cannot establish that its
      # method is usable here, and A3 says a restriction whose method we cannot
      # honor offers nothing. Widening would re-expose exactly the methods that
      # restriction hides, which is the failure mode A3 exists to prevent.
      #
      # BUT A BLIP MUST NOT MANUFACTURE A RESTRICTION. On an install with
      # nothing restricted anywhere, there is no access control to preserve and
      # nothing to fail closed about; returning :unavailable would take every
      # gated route on every custom domain to 404 — a self-inflicted auth
      # outage, on an install whose correct answer is :unrestricted. That is a
      # widening no one asked for in the other direction. #4139 shipped it
      # briefly by moving the rescue up from domain_id_for, where it could only
      # ever see the domain lookup.
      #
      # Note the asymmetry is decided by the GLOBAL value, which is in-memory
      # config and cannot itself have failed, so the degrade path never guesses.
      #
      # @param env [Hash] Rack env
      # @param exception [Redis::BaseError]
      # @param signin_config [SigninConfig, nil] the domain config, when the
      #   failure came after it was read
      # @return [Onetime::CustomDomain::SigninConfig::RestrictToResolution]
      def lookup_failure_resolution(env, exception, signin_config = nil)
        global = Onetime.auth_config.restrict_to

        unless env['onetime.domain_strategy'] == :custom
          # A non-custom host has no per-domain half to lose: the global
          # restriction is still fully known and still enforced.
          log_domain_lookup_failure(env, exception)
          return Onetime::CustomDomain::SigninConfig.resolve_restrict_to(
            global,
            nil,
            available: Onetime::CustomDomain::SigninConfig.global_restriction_available?(global),
          )
        end

        known = known_restriction(global, signin_config)
        if known.nil?
          log_domain_lookup_degraded(env, exception)
          return Onetime::CustomDomain::SigninConfig::RestrictToResolution.unrestricted(:global)
        end

        log_domain_lookup_failure(env, exception)
        Onetime::CustomDomain::SigninConfig::RestrictToResolution.unavailable(known[:restrict_to], known[:source])
      end

      # The restriction we can still name after a lookup failure, or nil when
      # this install has none. The domain half wins the name when we got far
      # enough to read it — it is the more specific of the two, and the
      # :unavailable resolution carries the name only so a caller can render a
      # method-specific notice.
      def known_restriction(global, signin_config)
        domain_value = signin_config&.enabled? ? signin_config.restrict_to.to_s.strip : ''
        return { restrict_to: domain_value, source: :domain } unless domain_value.empty?

        global_value = global.to_s.strip
        return nil if global_value.empty?

        { restrict_to: global_value, source: :global }
      end

      # Whether an inherited restriction is usable on this request host.
      #
      # Thin wrapper, on purpose: the availability POLICY is
      # SigninConfig.restriction_available_for_request? (ADR-024 A2 — the
      # display serializer and the settings API ask the same method, so no
      # consumer can narrow an inherited restriction the others do not). All
      # that belongs to the web layer is reading the request classification out
      # of the Rack env, which is what this does.
      def restriction_available_for_host?(env, global, signin_config, domain_id)
        Onetime::CustomDomain::SigninConfig.restriction_available_for_request?(
          global,
          signin_config,
          domain_id: domain_id,
          custom_host: env['onetime.domain_strategy'] == :custom,
        )
      end

      def log_domain_lookup_failure(env, exception)
        Auth::Logging.log_auth_event(
          :restrict_to_domain_lookup_failed,
          level: :error,
          host: env['onetime.display_domain'],
          error: exception.message,
        )
      end

      # Distinct event for the degrade-to-unrestricted path: the gate is down
      # on this host and NOTHING is being enforced. An operator watching only
      # the fail-closed event would see 404s and know; this one is silent by
      # design and must be visible on its own.
      def log_domain_lookup_degraded(env, exception)
        Auth::Logging.log_auth_event(
          :restrict_to_domain_lookup_degraded,
          level: :error,
          host: env['onetime.display_domain'],
          error: exception.message,
        )
      end

      # The restriction the request HOST inherits when no enabled per-domain
      # config speaks — the `global` input to the resolver.
      #
      # SSO PIN, parity with ConfigSerializer#effective_global_restrict_to: a
      # custom domain with no enabled SigninConfig keeps a working /signin page
      # only because tenant SSO is available there, and password/email default
      # OFF on custom domains. Pinning 'sso' keeps this gate in lockstep with
      # the page that host actually renders.
      #
      # The availability predicate is SsoConfig.sso_available_for_tenant_host? —
      # the SAME predicate ConfigSerializer#effective_global_restrict_to pins
      # on, platform fallback included. It used to be the narrower
      # tenant_sso_available_for?, which left this gate MORE permissive than
      # the page it guards whenever allow_platform_fallback_for_tenants? was on
      # and the tenant had no SsoConfig: the page offered SSO alone, the gate
      # pinned nothing and accepted crafted password POSTs. See that predicate
      # for why converging on the display's answer is the narrowing direction.
      def global_restrict_to(env, domain_id, signin_config)
        # NO-CONFIG CASE ONLY. Under A8's intersection semantics two different
        # restrictions have no intersection and fail closed as :conflict, so
        # pinning 'sso' on a tenant that HAS spoken (an enabled SigninConfig
        # naming, say, 'password') would take that host dark instead of honoring
        # the owner's choice. The pin exists to describe a host that has NOT
        # configured sign-in and is reachable only via SSO; that is the only
        # case it may apply to.
        return Onetime.auth_config.restrict_to if signin_config&.enabled?

        return 'sso' if env['onetime.domain_strategy'] == :custom &&
                        domain_id &&
                        Onetime::CustomDomain::SsoConfig.sso_available_for_tenant_host?(domain_id)

        Onetime.auth_config.restrict_to
      end

      # CustomDomain identifier for the request host, or nil.
      def domain_id_for(env)
        display_domain = env['onetime.display_domain']
        return nil if display_domain.to_s.empty?

        Onetime::CustomDomain.load_by_display_domain(display_domain)&.identifier
      end

      # The router's shared 404 — a gated route must be indistinguishable from
      # an undefined one (A7). Built here rather than reusing the router's
      # status_handler because request.halt bypasses Roda's status handlers.
      def not_found_response
        [
          404,
          { 'content-type' => 'application/json' },
          [JSON.generate(Auth::ErrorTranslator::NOT_FOUND_BODY)],
        ]
      end
    end
  end
end
