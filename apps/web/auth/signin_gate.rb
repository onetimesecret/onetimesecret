# apps/web/auth/signin_gate.rb
#
# frozen_string_literal: true

#
# Runtime enforcement of the sign-in / sign-up OPT-IN axis on the full-mode
# Rodauth routes (ADR-024, issue #4163).
#
# WHAT THIS CLOSES
#   Simple mode consults the ADR-024 resolvers at its POST handlers
#   (Core::Controllers::Base#signin_enabled? / #signup_enabled?). Full mode did
#   not: its pre-auth routes are served by Rodauth and only the `restrict_to`
#   axis was gated (Auth::RestrictTo, #4139). So a custom domain with no
#   enabled SigninConfig — a host whose /signin page offers nothing and whose
#   masthead hides the link — still ACCEPTED POST /auth/login and authenticated
#   canonical accounts. Enforcement of an access control must not depend on
#   which auth mode the install runs.
#
# TWO AXES OVER ONE ROUTE TABLE. `restrict_to` answers "WHICH sign-in method
# may this host offer"; this gate answers "may this host offer sign-in (or
# sign-up) AT ALL". They are independent, so the classification here is by
# FUNCTION and does not reuse RestrictTo's method table. One visible
# consequence: RestrictTo reclassifies the create/verify routes as 'webauthn'
# when the webauthn_verify_account feature is loaded, because the METHOD
# changes; the function does not, so this gate's SIGNUP_ROUTES are unchanged
# by that feature.
#
# ORDER — AFTER RestrictTo.enforce_route!, from the same before_rodauth hook
# (config/hooks/restrict_to.rb). Both gates reject as the same 404 body, so
# order cannot leak which one fired; running restrict_to first keeps the
# narrower, method-level verdict authoritative on a host where both apply.
#
# REJECT SHAPE — 404 (ADR-034#reject-as-not-found-not-forbidden). A host that
# never opted into sign-in presents no reachable sign-in surface; the body is
# the router's shared Auth::ErrorTranslator::NOT_FOUND_BODY so a gated route is
# byte-identical to an undefined one. The one exception is an unreadable
# policy → 503 (see below).
#
# WHERE THIS LIVES: beside restrict_to.rb, same reason — a plain module with no
# boot chain, so callers that must not load anything under config/ (unit specs,
# non-Rodauth surfaces) can require it. config/hooks/restrict_to.rb is the thin
# Rodauth wiring.
#
# THIS IS NOT THE WHOLE GATE on this axis:
#   1. Rodauth routes — here.
#   2. Simple mode — Core::Controllers::Base#signin_enabled? / #signup_enabled?.
#   3. SSO (OmniAuth) — deliberately NOT on this axis: tenant SSO is gated by
#      SsoConfig, and resolve_signin_enabled_for_custom_domain's SSO carve-out
#      exists for the DISPLAY surface only. See signin_allowed?.
#
# See: docs/adr/adr-024-custom-domain-auth-override-resolution.md,
#      lib/onetime/models/custom_domain/signin_config.rb and
#      lib/onetime/models/custom_domain/signup_config.rb (resolution is owned
#      there and re-derived nowhere — ADR-034#resolution-is-model-owned).
#

require 'json'

require 'onetime/errors'
require 'onetime/models/custom_domain/signin_config'
require 'onetime/models/custom_domain/signup_config'
require_relative 'error_translator'
require_relative 'lib/logging'

module Auth
  module SigninGate
    # Routes that let a visitor OBTAIN or RECOVER a session on the request host.
    # Keyed by `@current_route` (the symbol passed to Rodauth's `route(...)`,
    # not the URL — several URLs are renamed in config/features/).
    #
    # reset_password* is here rather than under sign-up or ungated: password
    # recovery is a sign-in path. A host that never opted into sign-in must not
    # accept a reset request, or the opt-in becomes advisory — the credential
    # it mints is usable on the canonical host.
    #
    # webauthn_autofill_js serves the conditional-UI challenge; without it the
    # ceremony-start endpoint stays live on a host that offers no sign-in.
    SIGNIN_ROUTES = [
      :login,
      :email_auth_request,
      :email_auth,
      :webauthn_login,
      :webauthn_autofill_js,
      :reset_password_request,
      :reset_password,
    ].freeze

    # Sign-in routes that ALSO require effective email-auth (magic links) to be
    # enabled for the host — the per-domain override can turn magic links off
    # while leaving password sign-in on (SigninConfig.resolve_email_auth_enabled).
    #
    # The login route is NOT here even though multi-phase login can dispatch a
    # magic link from it: that path is closed at its own chokepoint
    # (before_email_auth_request, config/hooks/restrict_to.rb), which is the
    # only place both entry points meet.
    EMAIL_AUTH_ROUTES = [
      :email_auth_request,
      :email_auth,
    ].freeze

    # Routes that CREATE an account on the request host. Classified by
    # function, so unchanged by Rodauth's webauthn_verify_account feature (it
    # changes the credential the ceremony mints, not what the ceremony is).
    #
    # verify_account and verify_account_resend complete a creation that started
    # here; leaving them open would let a host that revoked its sign-up opt-in
    # still finish accounts mid-flight.
    SIGNUP_ROUTES = [
      :create_account,
      :verify_account,
      :verify_account_resend,
    ].freeze

    GATED_ROUTES = (SIGNIN_ROUTES + SIGNUP_ROUTES).freeze

    # Routes this axis deliberately does NOT touch. Named explicitly (rather
    # than defaulted-open) so the coverage spec fails when a new Rodauth route
    # appears and nobody classified it on this axis — an unclassified route
    # silently defaulting to "allowed" is the exact defect #4163 fixes.
    #
    # Two reasons appear here:
    #   - ACCOUNT-SCOPED: reachable only when already authenticated, so keying
    #     them to the REQUEST HOST is the wrong axis. Sign-in opt-in governs
    #     whether a session may be OBTAINED here, never what an existing
    #     session may do. Gating them would strand a signed-in user mid-session
    #     when a domain owner flips the opt-in off.
    #   - NOT A SIGN-IN OFFER: second-factor ceremonies (the account already
    #     presented a first factor this host permitted — same reasoning as
    #     Auth::RestrictTo::SECOND_FACTOR_ROUTES) and logout, which must never
    #     404.
    UNGATED_ROUTES = [
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
      :webauthn_auth,
      :webauthn_auth_js,
      :webauthn_setup,
      :webauthn_setup_js,
      :webauthn_remove,
    ].freeze

    class << self
      # Gate the currently-matched Rodauth route on the opt-in axis.
      #
      # @param rodauth [Rodauth::Auth]
      # @raise [Onetime::SigninPolicyUnavailable, Onetime::SignupPolicyUnavailable]
      #   when the host's policy could not be read (→ 503, Auth::ErrorTranslator)
      def enforce_route!(rodauth)
        route = rodauth.current_route
        axis  = axis_for(route)
        return unless axis

        # Internal requests (Rodauth's internal_request feature) synthesize a
        # bare env with no Host and no DomainStrategy classification, and are
        # server-initiated app operations rather than a visitor signing in or up
        # on a host — e.g. invite signup autologin. Gating them would break app
        # flows for a policy about REQUEST HOSTS that an internal request does
        # not have. handle_internal_request calls before_rodauth directly, so
        # this guard is load-bearing. Same guard, same rationale as
        # Auth::RestrictTo.enforce_method!.
        return if rodauth.send(:internal_request?)

        env = rodauth.request.env
        return if allowed?(env, axis, route)

        Auth::Logging.log_auth_event(
          :signin_gate_route_rejected,
          level: :info,
          route: route,
          axis: axis,
          domain_strategy: env['onetime.domain_strategy'],
          host: env['onetime.display_domain'],
          path: rodauth.request.path,
        )

        rodauth.request.halt(not_found_response)
      end

      # Which axis a route belongs to, or nil when this gate does not touch it.
      #
      # @param route [Symbol] Rodauth's `@current_route`
      # @return [Symbol, nil] :signin, :signup
      def axis_for(route)
        return :signup if SIGNUP_ROUTES.include?(route)
        return :signin if SIGNIN_ROUTES.include?(route)

        nil
      end

      # @param env [Hash] Rack env
      # @param axis [Symbol] :signin or :signup
      # @param route [Symbol]
      # @return [Boolean]
      def allowed?(env, axis, route)
        return signup_allowed?(env) if axis == :signup

        signin_allowed?(env, email_auth: EMAIL_AUTH_ROUTES.include?(route))
      end

      # Whether this host may accept sign-in submissions.
      #
      # domain_id is OMITTED, mirroring Core::Controllers::Base#signin_enabled?
      # exactly: the tenant-SSO carve-out inside
      # resolve_signin_enabled_for_custom_domain keeps the /signin PAGE
      # reachable on a custom domain that has SSO but no SigninConfig. This is
      # the password/email POST gate, where that carve-out would re-open
      # precisely the credential submission ADR-024 closes.
      #
      # The branch between operator default and tenant default is chosen by
      # resolve_signin_enabled_for_request — a POSITIVE :canonical/:subdomain
      # test, never `== :custom`
      # (ADR-024#operator-defaults-require-positive-classification), so the
      # :invalid classification a failing domain-index read manufactures for a
      # real customer domain cannot inherit the operator's global default.
      #
      # @param env [Hash] Rack env
      # @param email_auth [Boolean] AND in effective magic-link availability
      # @raise [Onetime::SigninPolicyUnavailable] on an unreadable host policy
      # @return [Boolean]
      def signin_allowed?(env, email_auth: false)
        config   = signin_config_for(env)
        strategy = env['onetime.domain_strategy']

        enabled = Onetime::CustomDomain::SigninConfig.resolve_signin_enabled_for_request(
          Onetime::CustomDomain::SigninConfig.global_signin_enabled,
          config,
          domain_strategy: strategy,
        )
        return false unless enabled
        return true unless email_auth

        Onetime::CustomDomain::SigninConfig.resolve_email_auth_enabled(
          Onetime.auth_config.email_auth_enabled?,
          config,
        )
      end

      # Whether this host may accept account creation.
      #
      # Same polarity and the same positive operator test as signin_allowed?;
      # sign-up has no SSO carve-out, so there is no domain_id argument to omit.
      #
      # @param env [Hash] Rack env
      # @raise [Onetime::SignupPolicyUnavailable] on an unreadable host policy
      # @return [Boolean]
      def signup_allowed?(env)
        Onetime::CustomDomain::SignupConfig.resolve_signup_enabled_for_request(
          Onetime::CustomDomain::SignupConfig.global_signup_enabled,
          signup_config_for(env),
          domain_strategy: env['onetime.domain_strategy'],
        )
      end

      # The tenant's SigninConfig for the request host, or nil.
      #
      # @raise [Onetime::SigninPolicyUnavailable] on an unreadable non-operator host
      def signin_config_for(env)
        domain_id = domain_id_for(env)
        return nil unless domain_id

        Onetime::CustomDomain::SigninConfig.find_by_domain_id(domain_id)
      rescue Redis::BaseError => ex
        signin_policy_read_failed!(env, ex)
      end

      # The tenant's SignupConfig for the request host, or nil.
      #
      # @raise [Onetime::SignupPolicyUnavailable] on an unreadable non-operator host
      def signup_config_for(env)
        domain_id = domain_id_for(env)
        return nil unless domain_id

        Onetime::CustomDomain::SignupConfig.find_by_domain_id(domain_id)
      rescue Redis::BaseError => ex
        log_policy_read_failure(:signup, env, ex)
        # DECIDED BY THE MODEL, not here: SignupConfig.resolve_lookup_failure
        # raises on any host not positively an operator host and returns nil —
        # "no per-domain config", the only answer such a host could ever have
        # had — on :canonical/:subdomain, whose policy is in-memory config that
        # cannot have failed. Same rule the simple-mode gate uses
        # (Onetime::Logic::SignupConfigResolution#signup_policy_read_failed!),
        # so the two modes cannot drift.
        Onetime::CustomDomain::SignupConfig.resolve_lookup_failure(
          domain_strategy: env['onetime.domain_strategy'],
        )
      end

      # The per-domain sign-in policy could not be read.
      #
      # NOT SigninConfig.resolve_lookup_failure: that helper answers the
      # restrict_to axis and returns a RestrictToResolution. This axis needs the
      # CONFIG shape (nil = no per-domain config), which is what the sign-up
      # sibling's resolve_lookup_failure returns and what
      # Core::Controllers::Base#signin_policy_read_failed! does for simple mode.
      # The RULE is shared even though the return shape is not:
      # SigninConfig.operator_host? is the single owner of "which hosts may
      # inherit operator auth defaults", and it is a POSITIVE test — :custom,
      # :invalid and nil all fail closed, because :invalid is exactly what
      # DomainStrategy answers for a real customer domain when the same blip
      # broke its own read.
      #
      # @raise [Onetime::SigninPolicyUnavailable] on any non-operator host
      # @return [nil] on an operator host
      def signin_policy_read_failed!(env, exception)
        log_policy_read_failure(:signin, env, exception)
        strategy = env['onetime.domain_strategy']
        raise Onetime::SigninPolicyUnavailable unless
          Onetime::CustomDomain::SigninConfig.operator_host?(strategy)

        nil
      end

      def log_policy_read_failure(axis, env, exception)
        Auth::Logging.log_auth_event(
          :signin_gate_policy_lookup_failed,
          level: :error,
          axis: axis,
          host: env['onetime.display_domain'],
          domain_strategy: env['onetime.domain_strategy'],
          error: exception.message,
        )
      end

      # CustomDomain identifier for the request host, or nil.
      #
      # from_display_domain, NOT load_by_display_domain (#4157): the latter
      # rescues Redis::BaseError internally and returns nil, which would make
      # the rescues above unreachable for the FIRST of the two policy reads — a
      # blip would resolve as "host has no tenant config" and, on the :invalid
      # classification the same blip produces, silently inherit the operator's
      # global sign-in default.
      #
      # @raise [Redis::BaseError] handled by the callers
      def domain_id_for(env)
        display_domain = env['onetime.display_domain']
        return nil if display_domain.to_s.empty?

        Onetime::CustomDomain.from_display_domain(display_domain)&.identifier
      end

      # The router's shared 404 — a gated route must be indistinguishable from
      # an undefined one (ADR-034#reject-as-not-found-not-forbidden). Built here
      # rather than reusing the router's status_handler because request.halt
      # bypasses Roda's status handlers. Byte-identical to
      # Auth::RestrictTo.not_found_response, so the reject cannot reveal which
      # gate fired.
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
