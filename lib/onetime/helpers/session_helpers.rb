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
# - role: User's role (customer, colonel, etc.) for quick permission checks
# - authenticated: Boolean flag
# - authenticated_at: Unix timestamp
#
# Usage:
#   authenticated?      # Shared evaluator verdict (memoized per request)
#   has_role?(:colonel) # Role of the EFFECTIVE customer (the impersonation target mid-overlay)
#   current_customer    # Effective customer from the same verdict

require_relative '../session/customer_session_evaluator'
require_relative '../session/impersonation'

module Onetime
  module Helpers
    module SessionHelpers
      def authenticated?
        session_auth_enforced? && customer_session_verdict.authenticated?
      end

      # Compatibility role checks derive from the evaluator's effective identity.
      # A session cache may withhold access when stale, but must never grant it.
      def has_role?(role_name)
        return false unless session_auth_enforced?

        customer_session_verdict.customer&.role?(role_name) || false
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
        session_id = session.id&.private_id if session.respond_to?(:id)

        # Close the impersonation FIRST. session.clear would take the marker
        # with it and leave the audit trail holding a start with no end.
        Onetime::SessionImpersonation.stop!(
          session,
          ended_by: Onetime::SessionImpersonation::ENDED_BY_LOGOUT,
        )

        session.clear
        forget_customer_session_verdict
        OT.info "[logout] Session #{session_id} destroyed" if session_id
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
        env&.delete(Onetime::ActiveSessionGate::ENV_KEY)
      end

      def load_current_customer
        return nil unless session_auth_enforced?

        verdict = customer_session_verdict
        return nil unless verdict.authenticated?

        principal = verdict.principal
        customer  = verdict.customer

        # Refresh the cached role from the PRINCIPAL only. The target's role
        # must never be persisted into the operator's session during an overlay.
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
