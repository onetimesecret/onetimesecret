# apps/web/core/controllers/password_reset.rb

require_relative 'base'

module Core
  module Controllers
    class PasswordReset
      include Controllers::Base

      def request_reset
        publically do
          strategy_result = Otto::Security::Authentication::StrategyResult.new(
            session: session,
            user: cust,
            auth_method: 'session',
            metadata: {
              ip: req.client_ipaddress,
              user_agent: req.user_agent
            }
          )

          if req.params[:key]
            logic = V2::Logic::Authentication::ResetPassword.new strategy_result, req.params, locale
            logic.raise_concerns
            logic.process
            res.redirect '/signin'
          else
            logic = V2::Logic::Authentication::ResetPasswordRequest.new strategy_result, req.params, locale
            logic.raise_concerns
            logic.process
            res.redirect '/'
          end
        end
      end
    end
  end
end
