# frozen_string_literal: true

require_relative 'base'

module Core
  module Controllers
    class Authentication
      include Controllers::Base

      def authenticate # rubocop:disable Metrics/AbcSize
        unless signin_enabled?
          raise OT::Redirect.new('/')
        end

        # Prevent browser refresh re-submission
        res.do_not_cache!

        logic = V2::Logic::Authentication::AuthenticateSession.new(_strategy_result, req.params, locale)

        if authenticated?
          if json_requested?
            json_success('You are already logged in')
          else
            session['info_message'] = 'You are already logged in.'
            res.redirect '/'
          end
        elsif req.post?
          begin
            logic.raise_concerns
            logic.process
            cust_after = logic.cust

            # Set authenticated_at for session validation consistency
            session['authenticated_at'] = Time.now.to_i

            # Session cookie handled by Rack::Session middleware

            if json_requested?
              json_success('You have been logged in')
            elsif cust_after.role?(:colonel)
              res.redirect '/colonel/'
            else
              res.redirect '/'
            end
          rescue OT::FormError => ex
            if json_requested?
              json_error('Invalid email or password', field_error: %w[email invalid], status: 401)
            else
              # HTML fallback: set error message and redirect back to login
              session['error_message'] = 'Invalid email or password'
              res.redirect '/signin'
            end
          end
        end
      end

      def logout
        res.do_not_cache!

        logic = V2::Logic::Authentication::DestroySession.new(_strategy_result, req.params, locale)
        logic.raise_concerns
        logic.process

        if json_requested?
          json_success('You have been logged out')
        else
          res.redirect res.app_path('/')
        end
      end
    end
  end
end