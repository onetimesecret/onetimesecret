# apps/web/core/controllers/registration.rb

require_relative 'base'

module Core
  module Controllers
    class Registration
      include Controllers::Base

      def create_account
        publically('/signup') do
          unless _auth_settings['enabled'] && _auth_settings['signup']
            return disabled_response(req.path)
          end

          raise OT::Redirect.new('/') if req.blocked_user_agent?(blocked_agents: BADAGENTS)

          strategy_result = Otto::Security::Authentication::StrategyResult.new(
            session: session,
            user: cust,
            auth_method: 'session',
            metadata: {
              ip: req.client_ipaddress,
              user_agent: req.user_agent
            }
          )

          logic = V2::Logic::Account::CreateAccount.new strategy_result, req.params, locale
          logic.raise_concerns
          logic.process
          res.redirect '/'
        end
      end

      private

      def _auth_settings
        OT.conf.dig('site', 'authentication')
      end
    end
  end
end
