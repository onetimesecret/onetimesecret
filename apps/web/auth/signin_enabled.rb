# apps/web/auth/signin_enabled.rb
#
# frozen_string_literal: true

#
# Runtime enforcement of the per-domain `signin_enabled` OPT-IN
# (ADR-024 "custom domains default OFF, opt-in only";
#  ADR-034#resolution-is-model-owned + #reject-as-not-found-not-forbidden).
#
# WHAT THIS CLOSES
#   ADR-024 promises that password/email sign-in is NOT available on a custom
#   domain unless the domain owner explicitly opted in with an *enabled*
#   SigninConfig carrying signin_enabled=true. That promise was implemented in
#   the model (SigninConfig.resolve_signin_enabled_for_custom_domain /
#   _for_request) and enforced on three surfaces:
#
#     - simple mode  — Core::Controllers::Base#signin_enabled?, because in
#                      simple mode Core serves POST /auth/login itself;
#     - display      — the branded masthead's Sign In link
#                      (DomainSerializer#effective_signin_enabled?) and the
#                      /signin page availability verdict (ConfigSerializer);
#     - settings API — DomainsAPI signin_config details (#3814).
#
#   In FULL mode nothing consulted it. Rodauth serves POST /auth/login there,
#   and the only per-domain policy on that path was `restrict_to`. So a custom
#   domain that had never opted in (no SigninConfig at all — the DEFAULT shape)
#   or had explicitly opted OUT (enabled config, signin_enabled=false) still
#   accepted a valid credential at POST /auth/login and authenticated: 200,
#   real session. The promise held in simple mode and on every display surface
#   and silently did not hold on the route that matters most.
#
#   It looked covered because `restrict_to` DID reject on such hosts whenever a
#   restriction happened to exist and degrade to :unavailable. That coverage is
#   incidental and it is not this policy.
#
# WHY THIS IS A SIBLING OF Auth::RestrictTo AND NOT PART OF IT
#   `restrict_to` is a NARROWING FILTER OVER METHODS: given that sign-in is
#   available here, WHICH methods may be offered. Its resolver's explicit
#   invariant is that an absence of restriction resolves :unrestricted and
#   gates NOTHING ("an unrestricted install must not go dark"). Teaching it to
#   manufacture a restriction out of an absence would fight that invariant and
#   overload a method filter into an availability check — two different
#   questions with two different defaults (restrict_to defaults OPEN, per-domain
#   signin_enabled defaults CLOSED on custom hosts). They are ANDed at the hook,
#   not merged in the resolver.
#
#   FAILURE MODE A FUTURE EDIT WOULD REINTRODUCE: "simplifying" this away by
#   making resolve_restrict_to return :unavailable when signin_enabled is false.
#   That takes SSO down with it on every SSO-only tenant, which is #4139
#   verbatim — see restriction_available_for_custom_domain?'s `when 'sso'`
#   branch in signin_config.rb.
#
# NEVER GATE SSO ON THIS FLAG
#   `signin_enabled` is the PASSWORD/EMAIL opt-in and has never governed SSO.
#   An SSO-only tenant sets signin_enabled=false precisely to say "no passwords
#   on this host"; gating SSO on it would take that tenant's ONLY working
#   sign-in path dark. SSO availability is SsoConfig's question
#   (tenant_sso_available_for? / sso_available_for_tenant_host?). Hence
#   GATED_ROUTES below covers the 'password' and 'email_auth' entries of
#   Auth::RestrictTo::PRE_AUTH_ROUTES and nothing else — not 'webauthn', not the
#   middleware-served OmniAuth request phase, not the app-owned SSO linking
#   routes.
#
# NEVER GATE ACCOUNT CREATION ON THIS FLAG EITHER
#   The account-creation ceremony (create_account / verify_account /
#   verify_account_resend) is classified 'password' in PRE_AUTH_ROUTES, but
#   registration availability answers to the SIGN-UP opt-in
#   (SignupConfig#signup_enabled), not this one. A tenant may run SSO-only
#   sign-in with open self-service registration (signin_enabled=false,
#   signup_enabled=true); gating those routes here 404s a working registration
#   flow on a policy its owner never applied to it. They are subtracted from
#   GATED_ROUTES and owned by the sibling Auth::SignupEnabled.
#
# SCOPE — pre-auth password/email SIGN-IN routes only
#   The route classification is REUSED from Auth::RestrictTo::PRE_AUTH_ROUTES
#   rather than re-transcribed, so a route that gets classified for one gate
#   cannot be missed by the other. Deliberately untouched, for the reasons
#   documented on those constants: UNGATED_ROUTES (account-scoped credential
#   management — wrong axis, that is ADR-035/SsoOnlyGating), SECOND_FACTOR_ROUTES
#   (a second factor is a property of the ACCOUNT, not the request host; gating
#   it is a lockout), and :logout, which must never 404.
#
# REJECT SHAPE — 404, byte-identical to an undefined route
#   ADR-034#reject-as-not-found-not-forbidden. A host that never opted into
#   sign-in presents NO reachable password surface; a 403 would leave the
#   handler mounted and reachable, i.e. "configuration presenting as
#   availability". Reuses Auth::RestrictTo.not_found_response so the two gates
#   cannot drift in body shape.
#
# UNREADABLE POLICY — 503, NOT a fail-closed 404
#   Deliberate, and the same answer its sibling gives (see
#   Auth::RestrictTo.resolution_for and SigninConfig.resolve_lookup_failure).
#   Two datastore reads feed this gate on the hot path of every request to a
#   custom host — the CustomDomain identity lookup and the SigninConfig lookup —
#   so this path is reached by a transient Valkey blip, not only by a real
#   outage.
#
#   404 would be the gate claiming an opt-out it never managed to look up:
#   mystery not-founds on the sign-in routes of an install whose domains may all
#   be opted IN, indistinguishable from a routing regression and invisible to
#   alerting. A 404 exists to hide a policy-gated surface; an unreadable policy
#   has nothing to hide, and "the backend read failed, retry" is both the truth
#   and the alertable signal. It is still FAIL-CLOSED — 503 denies the sign-in —
#   just fail-closed with an honest shape.
#
#   The operator/tenant split is the model's rule, not a local one:
#   SigninConfig.operator_host? is a POSITIVE test, so :custom, :invalid and nil
#   all take the tenant-safe raising branch, while a positively-classified
#   :canonical/:subdomain host keeps working from in-memory config that a
#   datastore failure cost it nothing
#   (ADR-024#operator-defaults-require-positive-classification).
#
# WHERE THIS LIVES — beside restrict_to.rb, for its reasons
#   A plain module with no boot chain, so any surface can require it without
#   dragging in Auth::Config (see restrict_to.rb's header). The Rodauth wiring
#   is the thin config/hooks/signin_enabled.rb, registered from the same
#   before_rodauth area as the restrict_to hook.
#
# THIS IS THE FULL-MODE HALF ONLY. Simple mode's POST /auth/login is served by
# Core, not Rodauth, and is already gated by
# Core::Controllers::Base#signin_enabled? — the same model resolver, the same
# omitted domain_id. Nothing here changes that surface.
#
# See: docs/adr/adr-024-custom-domain-auth-override-resolution.md,
#      lib/onetime/models/custom_domain/signin_config.rb (the resolver; it is
#      owned there and re-derived nowhere).
#

require 'onetime/models/custom_domain/signin_config'
require_relative 'restrict_to'
require_relative 'signup_enabled'
require_relative 'lib/logging'

module Auth
  module SigninEnabled
    # The sign-in methods this opt-in governs. `signin_enabled` is the
    # password/email flag; 'webauthn' and 'sso' answer to their own
    # availability predicates and MUST NOT be listed here (#4139).
    GOVERNED_METHODS = %w[password email_auth].freeze

    # Pre-auth routes gated by this flag, derived from Auth::RestrictTo's
    # classification so the two gates cannot disagree about what a route IS.
    # Derived rather than copied on purpose: a new route added there is
    # automatically considered here, and the coverage spec that guards
    # PRE_AUTH_ROUTES therefore guards this set too.
    #
    # The account-creation ceremony is SUBTRACTED, not because those routes
    # are ungated but because they answer to a DIFFERENT opt-in:
    # `signup_enabled` on SignupConfig, enforced by the sibling
    # Auth::SignupEnabled. PRE_AUTH_ROUTES classifies create_account as a
    # 'password' route — true for the method question restrict_to asks —
    # but registration availability is the signup axis, and gating it here
    # took an SSO-only tenant's open self-service registration
    # (signin_enabled=false, signup_enabled=true) to 404. Subtracting the
    # sibling's own constant means a route is claimed by exactly one
    # availability gate, never both and never neither.
    GATED_ROUTES = (
      Auth::RestrictTo::PRE_AUTH_ROUTES
        .select { |_route, method_name| GOVERNED_METHODS.include?(method_name) }
        .keys - Auth::SignupEnabled::GATED_ROUTES
    ).freeze

    class << self
      # Gate the currently-matched Rodauth route.
      #
      # @param rodauth [Rodauth::Auth]
      def enforce_route!(rodauth)
        route = rodauth.current_route
        return unless GATED_ROUTES.include?(route)

        enforce!(rodauth, route)
      end

      # Gate the password/email opt-in for the current request.
      #
      # @param rodauth [Rodauth::Auth]
      # @param route [Symbol] for logging only
      # @raise [Onetime::SigninPolicyUnavailable] on an unreadable host policy
      def enforce!(rodauth, route)
        # Internal requests (Rodauth's internal_request feature) synthesize a
        # bare env with NO Host and no DomainStrategy classification, and are
        # server-initiated app operations rather than a visitor signing in on a
        # host — invite-signup autologin is one. This policy is about REQUEST
        # HOSTS, which an internal request does not have, and
        # handle_internal_request calls before_rodauth directly, so this guard
        # is load-bearing: without it those flows break.
        return if rodauth.send(:internal_request?)

        env = rodauth.request.env
        return if enabled_for_request?(env)

        Auth::Logging.log_auth_event(
          :signin_enabled_route_rejected,
          level: :info,
          route: route,
          host: env['onetime.display_domain'],
          path: rodauth.request.path,
        )

        rodauth.request.halt(Auth::RestrictTo.not_found_response)
      end

      # Whether password/email sign-in is available on the host this request
      # arrived on.
      #
      # GATHERS INPUTS ONLY (ADR-034#resolution-is-model-owned). The
      # custom-domain default-OFF rule, the global kill-switch AND, and the
      # operator/tenant branch all belong to
      # SigninConfig.resolve_signin_enabled_for_request and are re-derived
      # nowhere — the same call Core::Controllers::Base#signin_enabled? makes,
      # so the simple-mode and full-mode gates cannot drift.
      #
      # domain_id IS DELIBERATELY OMITTED. Passing it enables the tenant-SSO
      # carve-out, which exists for DISPLAY surfaces: an SSO-only tenant has a
      # working /signin page, so the masthead link and the settings page must
      # report sign-in as available. This is the password/email POST gate, and
      # SSO never flows through it, so it must keep the strict-false branch.
      # The asymmetry is specified in
      # SigninConfig.resolve_signin_enabled_for_custom_domain (#3415, #3783).
      # Adding domain_id here would let an SSO-only tenant's password POSTs
      # through — the gap this gate exists to close.
      #
      # @param env [Hash] Rack env
      # @raise [Onetime::SigninPolicyUnavailable] when a datastore read failed
      #   on a host that could carry a per-domain opt-in, so its policy is
      #   unknown (503; see this file's header for why not a 404)
      # @return [Boolean]
      def enabled_for_request?(env)
        signin_config = signin_config_for(env)
        global        = Onetime::CustomDomain::SigninConfig.global_signin_enabled

        Onetime::CustomDomain::SigninConfig.resolve_signin_enabled_for_request(
          global,
          signin_config,
          domain_strategy: env['onetime.domain_strategy'],
        )
      rescue Redis::BaseError => ex
        log_domain_lookup_failure(env, ex)
        resolve_lookup_failure(env)
      end

      # The per-domain opt-in record for the request host, or nil.
      #
      # from_display_domain, NOT load_by_display_domain (#4157): the latter
      # rescues Redis::BaseError internally and returns nil, which would make
      # the rescue above unreachable for the FIRST of the two reads — a blip
      # would silently resolve as "host has no tenant config", and on a
      # :custom-classified host that still means default-OFF, but on any host
      # whose classification ALSO degraded it would inherit operator defaults.
      # Letting the error out keeps the failure explicit.
      #
      # @raise [Redis::BaseError] handled by enabled_for_request?
      def signin_config_for(env)
        display_domain = env['onetime.display_domain']
        return nil if display_domain.to_s.empty?

        domain_id = Onetime::CustomDomain.from_display_domain(display_domain)&.identifier
        return nil unless domain_id

        Onetime::CustomDomain::SigninConfig.find_by_domain_id(domain_id)
      end

      # What an unreadable policy resolves to. Mirrors the rule
      # SigninConfig.resolve_lookup_failure applies for restrict_to, expressed
      # for a boolean: raise (→ 503) unless the host is positively one of the
      # operator's own, whose availability is entirely in-memory config and
      # therefore still fully known.
      #
      # @raise [Onetime::SigninPolicyUnavailable]
      # @return [Boolean]
      def resolve_lookup_failure(env)
        domain_strategy = env['onetime.domain_strategy']
        unless Onetime::CustomDomain::SigninConfig.operator_host?(domain_strategy)
          raise Onetime::SigninPolicyUnavailable
        end

        Onetime::CustomDomain::SigninConfig.resolve_signin_enabled_for_request(
          Onetime::CustomDomain::SigninConfig.global_signin_enabled,
          nil,
          domain_strategy: domain_strategy,
        )
      end

      def log_domain_lookup_failure(env, exception)
        Auth::Logging.log_auth_event(
          :signin_enabled_domain_lookup_failed,
          level: :error,
          host: env['onetime.display_domain'],
          error: exception.message,
        )
      end
    end
  end
end
