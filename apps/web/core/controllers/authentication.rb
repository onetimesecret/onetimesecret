# apps/web/core/controllers/authentication.rb
#
# frozen_string_literal: true

require 'onetime/session/impersonation'

require_relative 'base'

module Core
  module Controllers
    class Authentication
      include Controllers::Base
      include Onetime::LoggerMethods

      def authenticate # rubocop:disable Metrics/AbcSize
        unless signin_enabled?
          raise OT::Redirect.new('/')
        end

        # RESTRICT_TO ENFORCEMENT
        # (ADR-034#restrict-to-is-an-access-control-not-a-display-preference
        # / #reject-as-not-found-not-forbidden, #4139). This is the
        # simple-mode half of the gate: POST /auth/login is served here rather
        # than by Rodauth, so without this the same crafted POST that 404s in
        # full mode would still authenticate in simple mode.
        #
        # 404, not the 302 above: ADR-034#reject-as-not-found-not-forbidden
        # settled the reject shape as not-found — a restricted-away method
        # presents no reachable surface. The 302 stays
        # for signin_enabled?, which is a different question (sign-in is off
        # here) with an answer the SPA already handles.
        unless restrict_to_allows?('password')
          raise Onetime::RecordNotFound, 'Not Found'
        end

        # Prevent browser refresh re-submission
        res.do_not_cache!

        if authenticated?
          handle_already_authenticated
        elsif req.post?
          perform_authentication
        end
      end

      def logout
        res.do_not_cache!

        # Capture session info for logging before clearing
        customer_id = session['external_id']
        session_id  = begin
                       session.id&.public_id
        rescue StandardError
                       nil
        end

        auth_logger.debug 'Session destruction initiated',
          {
            customer_id: customer_id,
            session_id: session_id,
            ip: req.ip,
          }

        # Close any impersonation FIRST, so it is stopped and AUDITED rather
        # than silently discarded with the session. GET /logout is a safe
        # method and therefore reachable while impersonating; without this the
        # trail would hold a start with no end.
        Onetime::SessionImpersonation.stop!(
          session,
          ended_by: Onetime::SessionImpersonation::ENDED_BY_LOGOUT,
        )

        # Clear all session data
        session.clear

        # Regenerate session ID to prevent session fixation attacks
        # This invalidates the old session ID entirely
        if req.env['rack.session.options']
          req.env['rack.session.options'][:renew] = true
        end

        auth_logger.info 'Session destroyed',
          {
            customer_id: customer_id,
            session_id: session_id,
            ip: req.ip,
          }

        if json_requested?
          json_success('You have been logged out')
        else
          session['success_message'] = 'You have been logged out'
          res.redirect req.app_path('/')
        end
      end

      private

      def handle_already_authenticated
        if json_requested?
          json_success('You are already logged in')
        else
          session['info_message'] = 'You are already logged in.'
          res.redirect req.app_path('/')
        end
      end

      def perform_authentication
        logic = Core::Logic::Authentication::AuthenticateSession.new(strategy_result, req.params, locale)

        execute_with_error_handling(
          logic,
          success_message: 'You have been logged in',
          success_redirect: '/',
          error_redirect: '/signin',
          error_status: 401,
        ) do
          cust_after = logic.cust

          # Sync session data from logic class to Rack session
          # The logic class modifies its own @sess copy, so we need to copy those changes
          # to the actual Rack session for persistence
          session['external_id']      = cust_after.extid
          session['email']            = cust_after.email
          session['role']             = cust_after.role
          session['authenticated']    = true
          session['authenticated_at'] = Familia.now.to_i

          auth_logger.info 'Session synchronized after authentication',
            {
              user_id: cust_after.custid,
              email: cust_after.obscure_email,
              external_id: cust_after.extid,
              role: cust_after.role,
              session_id: session.id&.public_id,
              ip: req.ip,
            }

          # Override redirect for colonel role
          if !json_requested? && cust_after.role?(:colonel)
            auth_logger.debug 'Redirecting colonel to admin panel',
              {
                user_id: cust_after.custid,
                role: cust_after.role,
              }

            res.redirect req.app_path('/colonel/')
          end
        end
      rescue OT::Unauthorized => ex
        # Fallback for other unauthorized errors
        if json_requested?
          json_error(ex.message, field_error: %w[email invalid], status: 401)
        else
          session['error_message'] = ex.message
          res.redirect req.app_path('/signin')
        end
      end
    end
  end
end
