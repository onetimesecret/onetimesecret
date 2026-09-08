# lib/onetime/helpers/session_helpers.rb
#
# frozen_string_literal: true

#
# Session-based authentication helpers that minimize database/Redis lookups.
#
# Performance Pattern:
# - Authentication checks use session data only (no DB/Redis hit)
# - Customer object is lazy-loaded only when actually needed
# - Role checks use session data for common permission checks
#
# Session Data Stored:
# - external_id: Links to Customer.extid (Redis primary key)
# - email: User's email address
# - role: User's role (customer, colonel, etc.) for quick permission checks
# - authenticated: Boolean flag
# - authenticated_at: Unix timestamp
#
# Usage:
#   authenticated?      # Fast - checks session only
#   has_role?(:colonel) # Fast - checks session only
#   current_customer    # Slow - loads from Redis (use sparingly)

require_relative '../session/active_session_gate'
require_relative '../session/impersonation'

module Onetime
  module Helpers
    module SessionHelpers
      def authenticated?
        session['authenticated'] == true &&
          !session['external_id'].to_s.empty? &&
          session_auth_enforced? &&
          !active_session_revoked?
      end

      # Check user role without loading Customer (uses session data)
      def has_role?(role_name)
        return false unless authenticated?

        session['role'].to_s == role_name.to_s
      end

      def colonel?
        has_role?(:colonel)
      end

      def current_customer
        @current_customer ||= load_current_customer
      end

      def authenticate!(customer)
        # Clear any existing session data
        session.clear
        forget_active_session_verdict

        # Regenerate session ID to prevent fixation (Rack::Session pattern)
        request.session_options[:renew] = true if request.respond_to?(:session_options)

        # Set authentication data
        session['external_id']      = customer.extid
        session['email']            = customer.email
        session['role']             = customer.role  # Store role for permission checks
        session['authenticated']    = true
        session['authenticated_at'] = Familia.now.to_i
        session['ip_address']       = request.ip
        session['user_agent']       = request.user_agent

        # NOTE: CSRF tokens are managed by Rack::Protection::AuthenticityToken middleware
        # The token is generated on first access via AuthenticityToken.token(session)
      end

      def logout!
        session_id = session.id&.private_id if session.respond_to?(:id)

        # Close the impersonation FIRST. session.clear would take the marker
        # with it and leave the audit trail holding a start with no end.
        Onetime::SessionImpersonation.stop!(
          session,
          ended_by: Onetime::SessionImpersonation::ENDED_BY_LOGOUT,
        )

        session.clear
        forget_active_session_verdict
        OT.info "[logout] Session #{session_id} destroyed" if session_id
      end

      private

      # Full-mode active-session enforcement (Onetime::ActiveSessionGate, terms
      # defined there): the controller-side twin of the check in
      # BaseSessionAuthStrategy, so a page render and an API call answer the
      # same way once the Rack session's active-session row is revoked or
      # cannot be checked. Memoized per request through the Rack env when there
      # is one (the strategy shares the memo), else per helper instance, so
      # the many `authenticated?` calls in one request cost one SELECT.
      def active_session_revoked?
        return @active_session_revoked unless @active_session_revoked.nil?

        @active_session_revoked = Onetime::ActiveSessionGate.revoked?(session, env: rack_env_for_impersonation)
      end

      # The session identity just changed inside this request (login or
      # logout): a verdict reached for the previous identity must not outlive
      # it, in this helper or in the shared env memo.
      def forget_active_session_verdict
        @active_session_revoked = nil
        env                     = rack_env_for_impersonation
        env&.delete(Onetime::ActiveSessionGate::ENV_KEY)
      end

      def load_current_customer
        return nil unless authenticated?

        # The PRINCIPAL — always the session owner, never the impersonation
        # target. session['external_id'] stays the colonel's extid for the
        # whole impersonation (overlay, not swap).
        principal = Onetime::Customer.find_by_extid(session['external_id'])
        return nil unless principal

        customer, impersonating = Onetime::SessionImpersonation.resolve(
          session, principal, env: rack_env_for_impersonation
        )

        # Refresh the cached role from the PRINCIPAL only. Writing the target's
        # role here would stamp a customer role into the colonel's own session
        # blob, and `has_role?`/`colonel?` read that cache without loading a
        # Customer — so a single impersonation would silently demote the
        # operator for the rest of the session, surviving the stop.
        session['role']      = principal.role if !impersonating && session['role'] != principal.role
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
