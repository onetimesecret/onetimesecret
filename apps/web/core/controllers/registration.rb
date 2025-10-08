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

        begin
          logic.raise_concerns
          logic.process

          # Set authenticated_at for session validation consistency
          session['authenticated_at'] = Time.now.to_i

          if json_requested?
            res.headers['Content-Type'] = 'application/json'
            res.body = { success: 'Your account has been created' }.to_json
          else
            res.redirect '/'
          end
        rescue OT::FormError => e
          if json_requested?
            res.status = 400
            res.headers['Content-Type'] = 'application/json'
            # Extract field from error message if possible, default to 'email'
            field = e.message.downcase.include?('password') ? 'password' : 'email'
            res.body = {
              error: e.message,
              'field-error': [field, e.message.downcase]
            }.to_json
          else
            raise
          end
        end
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

        begin
          if req.params[:key]
            # Password reset with token
            logic = V2::Logic::Authentication::ResetPassword.new(strategy_result, req.params, locale)
            logic.raise_concerns
            logic.process

            if json_requested?
              res.headers['Content-Type'] = 'application/json'
              res.body = { success: 'Your password has been reset' }.to_json
            else
              res.redirect '/signin'
            end
          else
            # Request password reset email
            logic = V2::Logic::Authentication::ResetPasswordRequest.new(strategy_result, req.params, locale)
            logic.raise_concerns
            logic.process

            if json_requested?
              res.headers['Content-Type'] = 'application/json'
              res.body = { success: 'An email has been sent to you with a link to reset the password for your account' }.to_json
            else
              res.redirect '/'
            end
          end
        rescue OT::FormError => e
          if json_requested?
            res.status = 400
            res.headers['Content-Type'] = 'application/json'
            res.body = {
              error: e.message,
              'field-error': ['email', e.message.downcase]
            }.to_json
          else
            session['error_message'] = e.message
            res.redirect '/forgot'
          end
        rescue Onetime::MissingSecret => e
          if json_requested?
            res.status = 404
            res.headers['Content-Type'] = 'application/json'
            res.body = {
              error: 'Invalid or expired reset token',
              'field-error': ['key', 'invalid']
            }.to_json
          else
            session['error_message'] = 'Invalid or expired reset token'
            res.redirect '/forgot'
          end
        end
      end

      private

      def _auth_settings
        OT.conf.dig('site', 'authentication')
      end
    end
  end
end
