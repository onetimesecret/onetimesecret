# lib/onetime/helpers/session_helpers.rb
#
# frozen_string_literal: true

#
# Session-based authentication helpers. Identity and role answers come from
# Onetime::CustomerSessionEvaluator, whose verdict is memoized per request, so
# repeated calls in one request cost one evaluation.
#
# Session Data Stored:
# - external_id: Links to Customer.extid (Redis primary key)
# - email: User's email address
# - role: User's role (customer, colonel, etc.). DISPLAY ONLY: read by the
#   colonel Sessions console and `bin/ots session` (Operations::Sessions::Store,
#   Colonel::GetSessionDetail). Never an authorization input; role checks load
#   the Customer through the evaluator.
# - authenticated: Boolean flag
# - authenticated_at: Unix timestamp
#
# Usage:
#   authenticated?      # Shared evaluator verdict (memoized per request)
#   has_role?(:colonel) # Role of the ACTING PRINCIPAL — never the impersonation
#                       # target. Role gates answer about the operator; whether a
#                       # privileged action is allowed on an impersonated surface
#                       # is a decision for the impersonation policy, not for the
#                       # role check.
#   colonel?            # Convenience alias for has_role?(:colonel); same principal-only semantics.
#   current_customer    # EFFECTIVE customer from the same verdict (the
#                       # impersonation target mid-overlay, otherwise the principal).

require_relative '../session/customer_session_evaluator'
require_relative '../session/impersonation'

module Onetime
  module Helpers
    module SessionHelpers
      def authenticated?
        session_auth_enforced? && customer_session_verdict.authenticated?
      end

      # Role checks answer about the ACTING PRINCIPAL, not the effective
      # customer. The principal-role invariant is what keeps `colonel?` true
      # for the operator throughout an impersonation session, so the admin UI
      # remains visible and the operator can end the overlay. Whether a
      # privileged action is allowed on an impersonated surface is a decision
      # for the impersonation policy — never for `has_role?`.
      def has_role?(role_name)
        return false unless session_auth_enforced?

        customer_session_verdict.principal&.role?(role_name) || false
      end

      def colonel?
        has_role?(:colonel)
      end

      def current_customer
        @current_customer ||= load_current_customer
      end

      # There is deliberately no `authenticate!(customer)` here. Every path that
      # marks a Rack session authenticated must also mint its active-session
      # row and join key (Onetime::ActiveSessionGate), which only a Rodauth
      # login-session does; the simple-mode controller writes its own session
      # and the invite flow runs a real login_session. A helper that set
      # `authenticated` without the join key would mint a session the gate
      # exempts from revocation forever.

      def logout!
        # The handle, not an id: it is the identifier every other session log
        # line and the colonel session view carry, and it cannot be replayed
        # as the cookie (#4461). Taken before the clear below.
        handle = Onetime::SessionMetadata.handle_for(session.id&.public_id) if session.respond_to?(:id)

        # Close the impersonation FIRST. session.clear would take the marker
        # with it and leave the audit trail holding a start with no end.
        Onetime::SessionImpersonation.stop!(
          session,
          ended_by: Onetime::SessionImpersonation::ENDED_BY_LOGOUT,
        )

        # The row before the blob: a concurrent request can write the blob
        # back, and only the missing row makes that copy refusable.
        Onetime::ActiveSessionGate.end_session(session, env: rack_env_for_impersonation)

        session.clear

        # Renew the id, as Web Core's #logout does. The store then deletes the
        # old blob and sets its ended-marker (Onetime::SessionEnded), so a
        # request still in flight under the old id cannot write the session
        # back (RISK-2026-09-19-01). Clearing alone leaves the id live, and a
        # live id cannot carry a marker: its own next write would be refused.
        options         = rack_env_for_impersonation&.[]('rack.session.options')
        options[:renew] = true if options.respond_to?(:[]=)

        forget_customer_session_verdict
        OT.info "[logout] Session destroyed (session_handle=#{handle})" if handle
      end

      private

      def customer_session_verdict
        env                         = rack_env_for_impersonation
        @customer_session_verdict ||= Onetime::CustomerSessionEvaluator.evaluate(session, env: env)
      end

      # The session identity just changed inside this request (login or logout):
      # neither the common verdict nor the active-session sub-verdict may outlive it.
      def forget_customer_session_verdict
        @customer_session_verdict = nil
        env                       = rack_env_for_impersonation
        Onetime::CustomerSessionEvaluator.forget(env)
        Onetime::ActiveSessionGate.forget(env)
      end

      def load_current_customer
        return nil unless session_auth_enforced?

        verdict = customer_session_verdict
        return nil unless verdict.authenticated?

        principal = verdict.principal
        customer  = verdict.customer

        # Refresh the session's role from the PRINCIPAL only. It is display data
        # for the colonel Sessions console, which lists the session under its
        # owner; an overlay must never stamp the target's role into the
        # operator's session.
        if verdict.impersonation.nil? && session['role'] != principal.role
          session['role'] = principal.role
        end
        session['last_seen'] = Familia.now.to_i

        customer
      end

      # The Rack env of the current request, or nil outside one (controllers
      # have a request; bare unit harnesses may not, and nil only costs a memo,
      # never a different answer). The core and
      # billing controllers expose the request as `req`; the API controllers
      # and the auth strategies as `request`. Both are tried so the
      # per-request memos (impersonation, active-session verdict) are shared
      # with the strategy on every surface, not only the ones spelling it
      # `request`.
      def rack_env_for_impersonation
        rack_request = if respond_to?(:request)
                         request
                       elsif respond_to?(:req)
                         req
                       end
        return nil unless rack_request.respond_to?(:env)

        rack_request.env
      rescue StandardError
        nil
      end

      # Should sessions enforce authentication checks?
      #
      # Per-request check used by `authenticated?` and V1's `authorized`
      # to determine if the auth system is active for session validation.
      #
      # Defaulting to disabled is the right thing to do. If the site
      # config is missing, we assume that authentication is disabled
      # and that accounts are not used. This prevents situations where
      # the app is running and anyone can create an account without
      # proper authentication configuration in place. Features that
      # require an account are rendered unavailable.
      #
      # Uses `dig` for safe hash access to avoid the `rescue false`
      # anti-pattern that silently swallowed config access errors,
      # masking legitimate configuration problems (see #2620).
      #
      # Distinct from AuthStrategies.account_creation_allowed? which
      # is a boot-time decision about whether to register auth
      # strategies (strict `== true`).
      #
      # @return [Boolean] true only if authentication is explicitly
      #   configured; false when config is absent or disabled.
      #
      def session_auth_enforced?
        return false unless defined?(OT) && OT.respond_to?(:conf)

        auth_conf = OT.conf&.dig('site', 'authentication')
        return false unless auth_conf

        auth_conf['enabled'] != false
      end
    end
  end
end
