# frozen_string_literal: true

require_relative 'base'

module Core
  module Controllers
    class Registration
      include Controllers::Base

      def create_account
        unless signup_enabled?
          raise OT::Redirect.new('/')
        end

        logic = V2::Logic::Account::CreateAccount.new(_strategy_result, req.params, locale)

        execute_with_error_handling(
          logic,
          success_message: 'Your account has been created',
          success_redirect: '/',
        ) do
          # Set authenticated_at for session validation consistency
          session['authenticated_at'] = Time.now.to_i
        end
      end

      def request_reset
        if req.params[:key]
          # Password reset with token
          reset_password_with_token
        else
          # Request password reset email
          request_password_reset_email
        end
      rescue Onetime::MissingSecret
        if json_requested?
          json_error('Invalid or expired reset token', field_error: %w[key invalid], status: 404)
        else
          session['error_message'] = 'Invalid or expired reset token'
          res.redirect '/forgot'
        end
      end

      private

      def reset_password_with_token
        logic = V2::Logic::Authentication::ResetPassword.new(_strategy_result, req.params, locale)
        execute_with_error_handling(
          logic,
          success_message: 'Your password has been reset',
          success_redirect: '/signin',
          error_redirect: '/forgot',
        )
      end

      def request_password_reset_email
        logic = V2::Logic::Authentication::ResetPasswordRequest.new(_strategy_result, req.params, locale)
        execute_with_error_handling(
          logic,
          success_message: 'An email has been sent to you with a link to reset the password for your account',
          success_redirect: '/',
          error_redirect: '/forgot',
        )
      end
    end
  end
end
