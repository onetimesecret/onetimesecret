# frozen_string_literal: true

require_relative 'base'

module Core
  module Controllers
    class Authentication
      include Controllers::Base

      def authenticate # rubocop:disable Metrics/AbcSize
        unless _auth_settings['enabled'] && _auth_settings['signin']
          raise OT::Redirect.new('/')
        end

        # Prevent browser refresh re-submission
        res.do_not_cache!

        strategy_result = Otto::Security::Authentication::StrategyResult.new(
          session: session,
          user: cust,
          auth_method: 'session',
          metadata: {
            ip: req.client_ipaddress,
            user_agent: req.user_agent,
          },
        )

        logic = V2::Logic::Authentication::AuthenticateSession.new(strategy_result, req.params, locale)

        if authenticated?
          if json_requested?
            res.headers['Content-Type'] = 'application/json'
            res.body                    = { success: 'You are already logged in' }.to_json
          else
            session['info_message'] = 'You are already logged in.'
            res.redirect '/'
          end
        elsif req.post?
          begin
            logic.raise_concerns
            logic.process
            sess       = logic.sess
            cust_after = logic.cust

            # Set authenticated_at for session validation consistency
            session['authenticated_at'] = Time.now.to_i

            # Session cookie handled by Rack::Session middleware

            if json_requested?
              res.headers['Content-Type'] = 'application/json'
              res.body                    = { success: 'You have been logged in' }.to_json
            elsif cust_after.role?(:colonel)
              res.redirect '/colonel/'
            else
              res.redirect '/'
            end
          rescue OT::FormError => ex
            if json_requested?
              res.status                  = 401
              res.headers['Content-Type'] = 'application/json'
              res.body                    = {
                error: 'Invalid email or password',
                'field-error': %w[email invalid],
              }.to_json
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

        strategy_result = Otto::Security::Authentication::StrategyResult.new(
          session: session,
          user: cust,
          auth_method: 'session',
          metadata: {
            ip: req.client_ipaddress,
            user_agent: req.user_agent,
          },
        )

        logic = V2::Logic::Authentication::DestroySession.new(strategy_result, req.params, locale)
        logic.raise_concerns
        logic.process

        if json_requested?
          res.headers['Content-Type'] = 'application/json'
          res.body                    = { success: 'You have been logged out' }.to_json
        else
          res.redirect res.app_path('/')
        end
      end

      private

      def _auth_settings
        OT.conf.dig('site', 'authentication')
      end
    end
  end
end
