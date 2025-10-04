# apps/web/core/controllers/session.rb

require_relative 'base'

module Core
  module Controllers
    class Session
      include Controllers::Base

      def logout
        authenticated('/') do
          strategy_result = Otto::Security::Authentication::StrategyResult.new(
            session: session,
            user: cust,
            auth_method: 'session',
            metadata: {
              ip: req.client_ipaddress,
              user_agent: req.user_agent
            }
          )

          logic = V2::Logic::Authentication::DestroySession.new strategy_result, req.params, locale
          logic.raise_concerns
          logic.process
          res.redirect res.app_path('/')
        end
      end
    end
  end
end
