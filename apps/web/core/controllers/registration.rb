# frozen_string_literal: true

require_relative 'base'

module Core
  module Controllers
    class Registration
      include Controllers::Base

      def create_account
        unless _auth_settings['enabled'] && _auth_settings['signup']
          raise OT::Redirect.new('/')
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

        logic = V2::Logic::Account::CreateAccount.new(strategy_result, req.params, locale)
        logic.raise_concerns
        logic.process

        res.redirect '/'
      end

      def request_reset
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
          logic = V2::Logic::Authentication::ResetPassword.new(strategy_result, req.params, locale)
          logic.raise_concerns
          logic.process
          res.redirect '/signin'
        else
          logic = V2::Logic::Authentication::ResetPasswordRequest.new(strategy_result, req.params, locale)
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
