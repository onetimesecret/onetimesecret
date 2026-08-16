# apps/web/auth/signup_enabled.rb
#
# frozen_string_literal: true

#
# Runtime enforcement of the per-domain `signup_enabled` OPT-IN on the
# full-mode account-creation routes (ADR-024 "custom domains default OFF,
# opt-in only"; ADR-034#resolution-is-model-owned +
# #reject-as-not-found-not-forbidden).
#
# WHY THIS IS ITS OWN GATE AND NOT PART OF Auth::SigninEnabled
#   `signin_enabled` and `signup_enabled` are DIFFERENT OPT-INS answering
#   different tenant questions, stored on different models (SigninConfig /
#   SignupConfig) and resolved by different model-owned resolvers. An SSO-only
#   tenant with open self-service registration is a REAL shape: SigninConfig
#   signin_enabled=false ("no password sign-in here") alongside SignupConfig
#   signup_enabled=true ("anyone may register"). Gating create_account on the
#   SIGN-IN opt-in — which is what falls out of inheriting PRE_AUTH_ROUTES'
#   'password' classification wholesale — takes that tenant's working
#   registration flow to 404 on a policy its owner never applied to
#   registration. Auth::SigninEnabled therefore excludes these routes, and this
#   gate owns them against SignupConfig.
#
#   In simple mode this split already exists: Core gates the sign-in POST with
#   Core::Controllers::Base#signin_enabled? and the signup POST with
#   #signup_enabled?, each against its own resolver. This file is the full-mode
#   half of the SIGNUP side, exactly as signin_enabled.rb is of the sign-in
#   side.
#
# SCOPE — the account-creation ceremony, all credential types
#   create_account, verify_account, verify_account_resend. Unlike its two
#   siblings this gate is NOT method-scoped and takes no webauthn_verify_account
#   carve-out: `signup_enabled` governs whether an account may be CREATED on
#   this host at all, regardless of which credential the ceremony registers.
#   With webauthn_verify_account loaded these routes stop being *password*
#   routes (which is why the method-scoped gates release them) but they do not
#   stop being *signup* routes.
#
#   verify_account / verify_account_resend are gated alongside create_account
#   deliberately: a host that does not offer registration presents no part of
#   the registration ceremony, and leaving verification reachable would let a
#   signup started elsewhere complete on a host whose owner opted out. The cost
#   is that flipping signup_enabled off strands a tenant's own in-flight
#   verifications until it is flipped back — the fail-closed direction, and the
#   owner's own switch.
#
# REJECT SHAPE — 404, byte-identical to an undefined route
#   ADR-034#reject-as-not-found-not-forbidden, reusing
#   Auth::RestrictTo.not_found_response so the three gates cannot drift in
#   body shape.
#
# UNREADABLE POLICY — 503, NOT a fail-closed 404
#   Same rule and same reasoning as its siblings (see signin_enabled.rb's
#   header at length). The decision is the MODEL's:
#   SignupConfig.resolve_lookup_failure raises Onetime::SignupPolicyUnavailable
#   unless the host is positively an operator host, in which case nil ("no
#   per-domain config" — the only answer such a host could ever have had) is
#   returned and resolution proceeds from in-memory global config. This is the
#   same rule Core's simple-mode signup gate already applies via
#   Onetime::Logic::SignupConfigResolution (#4157).
#
# See: docs/adr/adr-024-custom-domain-auth-override-resolution.md,
#      lib/onetime/models/custom_domain/signup_config.rb (the resolver; it is
#      owned there and re-derived nowhere).
#

require 'onetime/models/custom_domain/signup_config'
require_relative 'restrict_to'
require_relative 'lib/logging'

module Auth
  module SignupEnabled
    # The account-creation ceremony. Auth::SigninEnabled derives its own set
    # by SUBTRACTING this one from the password/email pre-auth routes, so a
    # route listed here is claimed by this gate and automatically released by
    # that one — the two cannot both gate or both miss a route.
    GATED_ROUTES = %i[
      create_account
      verify_account
      verify_account_resend
    ].freeze

    class << self
      # Gate the currently-matched Rodauth route.
      #
      # @param rodauth [Rodauth::Auth]
      def enforce_route!(rodauth)
        route = rodauth.current_route
        return unless GATED_ROUTES.include?(route)

        enforce!(rodauth, route)
      end

      # Gate the sign-up opt-in for the current request.
      #
      # @param rodauth [Rodauth::Auth]
      # @param route [Symbol] for logging only
      # @raise [Onetime::SignupPolicyUnavailable] on an unreadable host policy
      def enforce!(rodauth, route)
        # Internal requests synthesize a bare env with no Host and no
        # DomainStrategy classification, and are server-initiated app
        # operations rather than a visitor registering on a host —
        # invite-signup account creation is one, and it MUST NOT be gated by a
        # per-host opt-in the request does not have a host for. Same
        # load-bearing guard as both sibling gates.
        return if rodauth.send(:internal_request?)

        env = rodauth.request.env
        return if enabled_for_request?(env)

        Auth::Logging.log_auth_event(
          :signup_enabled_route_rejected,
          level: :info,
          route: route,
          host: env['onetime.display_domain'],
          path: rodauth.request.path,
        )

        rodauth.request.halt(Auth::RestrictTo.not_found_response)
      end

      # Whether account creation is available on the host this request
      # arrived on.
      #
      # GATHERS INPUTS ONLY (ADR-034#resolution-is-model-owned). The
      # custom-domain default-OFF rule, the global kill-switch AND, and the
      # operator/tenant branch all belong to
      # SignupConfig.resolve_signup_enabled_for_request and are re-derived
      # nowhere — the same call Core::Controllers::Base#signup_enabled? makes,
      # so the simple-mode and full-mode gates cannot drift. There is no
      # domain_id / display carve-out on the signup side at all: unlike
      # sign-in, sign-up has no SSO path that works without an enabled config
      # (the resolver documents this).
      #
      # @param env [Hash] Rack env
      # @raise [Onetime::SignupPolicyUnavailable] when a datastore read failed
      #   on a host that could carry a per-domain opt-in, so its policy is
      #   unknown (503; see signin_enabled.rb's header for why not a 404)
      # @return [Boolean]
      def enabled_for_request?(env)
        signup_config = signup_config_for(env)
        global        = Onetime::CustomDomain::SignupConfig.global_signup_enabled

        Onetime::CustomDomain::SignupConfig.resolve_signup_enabled_for_request(
          global,
          signup_config,
          domain_strategy: env['onetime.domain_strategy'],
        )
      rescue Redis::BaseError => ex
        log_domain_lookup_failure(env, ex)
        resolve_lookup_failure(env)
      end

      # The per-domain opt-in record for the request host, or nil.
      #
      # from_display_domain, NOT load_by_display_domain, for the reason
      # documented on Auth::SigninEnabled.signin_config_for (#4157): the
      # failure must reach the rescue above explicitly, not dissolve into
      # "host has no tenant config".
      #
      # @raise [Redis::BaseError] handled by enabled_for_request?
      def signup_config_for(env)
        display_domain = env['onetime.display_domain']
        return nil if display_domain.to_s.empty?

        domain_id = Onetime::CustomDomain.from_display_domain(display_domain)&.identifier
        return nil unless domain_id

        Onetime::CustomDomain::SignupConfig.find_by_domain_id(domain_id)
      end

      # What an unreadable policy resolves to. The rule is the model's
      # (SignupConfig.resolve_lookup_failure): raise (→ 503) unless the host
      # is positively an operator host, whose availability is entirely
      # in-memory config and therefore still fully known — the read could only
      # ever have produced nil there, which is what the model returns for us
      # to resolve with.
      #
      # @raise [Onetime::SignupPolicyUnavailable]
      # @return [Boolean]
      def resolve_lookup_failure(env)
        domain_strategy = env['onetime.domain_strategy']
        config          = Onetime::CustomDomain::SignupConfig.resolve_lookup_failure(
          domain_strategy: domain_strategy,
        )

        Onetime::CustomDomain::SignupConfig.resolve_signup_enabled_for_request(
          Onetime::CustomDomain::SignupConfig.global_signup_enabled,
          config,
          domain_strategy: domain_strategy,
        )
      end

      def log_domain_lookup_failure(env, exception)
        Auth::Logging.log_auth_event(
          :signup_enabled_domain_lookup_failed,
          level: :error,
          host: env['onetime.display_domain'],
          error: exception.message,
        )
      end
    end
  end
end
