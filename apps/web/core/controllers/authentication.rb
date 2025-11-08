# apps/web/core/controllers/authentication.rb
#
# frozen_string_literal: true

require_relative 'base'

module Core
  module Controllers
    class Authentication
      include Controllers::Base
      include Onetime::Logging

      def authenticate # rubocop:disable Metrics/AbcSize
        unless signin_enabled?
          raise OT::Redirect.new('/')
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

        logic = AccountAPI::Logic::Authentication::DestroySession.new(strategy_result, req.params, locale)
        execute_with_error_handling(
          logic,
          success_message: 'You have been logged out',
          success_redirect: res.app_path('/'),
        )
      end

      private

      def handle_already_authenticated
        if json_requested?
          json_success('You are already logged in')
        else
          session['info_message'] = 'You are already logged in.'
          res.redirect '/'
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
          session['external_id'] = cust_after.extid
          session['email'] = cust_after.email
          session['role'] = cust_after.role
          session['authenticated'] = true
          session['authenticated_at'] = Familia.now.to_i

          auth_logger.info "Session synchronized after authentication", {
            user_id: cust_after.custid,
            email: cust_after.obscure_email,
            external_id: cust_after.extid,
            role: cust_after.role,
            session_id: session.id&.public_id,
            ip: req.ip
          }

          # Override redirect for colonel role
          if !json_requested? && cust_after.role?(:colonel)
            auth_logger.debug "Redirecting colonel to admin panel", {
              user_id: cust_after.custid,
              role: cust_after.role
            }

            res.redirect '/colonel/'
          end
        end
      rescue OT::Unauthorized => ex
        # Fallback for other unauthorized errors
        if json_requested?
          json_error(ex.message, field_error: %w[email invalid], status: 401)
        else
          session['error_message'] = ex.message
          res.redirect '/signin'
        end
      end
    end
  end
end
