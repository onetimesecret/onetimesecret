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
        res.no_cache!

        strategy_result = Otto::Security::Authentication::StrategyResult.new(
          session: session,
          user: cust,
          auth_method: 'session',
          metadata: {
            ip: req.client_ipaddress,
            user_agent: req.user_agent
          }
        )

        logic = V2::Logic::Authentication::AuthenticateSession.new(strategy_result, req.params, locale)

        if authenticated?
          session['info_message'] = 'You are already logged in.'
          res.redirect '/'
        elsif req.post?
          logic.raise_concerns
          logic.process
          sess = logic.sess
          cust_after = logic.cust

          # Session cookie handled by Rack::Session middleware

          if cust_after.role?(:colonel)
            res.redirect '/colonel/'
          else
            res.redirect '/'
          end
        end
      end

      def logout
        res.no_cache!

        strategy_result = Otto::Security::Authentication::StrategyResult.new(
          session: session,
          user: cust,
          auth_method: 'session',
          metadata: {
            ip: req.client_ipaddress,
            user_agent: req.user_agent
          }
        )

        logic = V2::Logic::Authentication::DestroySession.new(strategy_result, req.params, locale)
        logic.raise_concerns
        logic.process

        res.redirect res.app_path('/')
      end

      private

      def _auth_settings
        OT.conf.dig('site', 'authentication')
      end
    end
  end
end
