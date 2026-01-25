# apps/web/core/controllers/registration.rb
#
# frozen_string_literal: true

require_relative 'base'

module Core
  module Controllers
    # Handles account creation and password reset requests.
    #
    # For basic authentication mode only.
    #
    # Security: Identical responses for new/existing accounts prevent email
    # enumeration. This is how it plays out:
    #
    # Scenario                           | Message       | Accurate?
    # -----------------------------------|---------------|-------------------------
    # Autoverify + new                   | "Sign in"     | Yes
    # Autoverify + existing              | "Sign in"     | Yes
    # No-autoverify + new                | "Check email" | Yes
    # No-autoverify + existing unverifed | "Check email" | Yes (resent)
    # No-autoverify + existing verified  | "Check email" | Acceptable misdirection
    #
    # @see OWASP Authentication Cheat Sheet.
    #
    class Registration
      include Controllers::Base

      def create_account
        unless signup_enabled?
          raise OT::Redirect.new('/')
        end

        logic = AccountAPI::Logic::Account::CreateAccount.new(strategy_result, req.params, locale)

        # Same message for new/existing accounts (email enumeration prevention)
        autoverify      = OT.conf.dig('site', 'authentication', 'autoverify')
        success_message = if autoverify.to_s == 'true'
                            'You can now sign in.'
                          else
                            'Check your email for verification.'
                          end

        execute_with_error_handling(
          logic,
          success_message: success_message,
          success_redirect: '/signin',
        )
      end

      def request_reset_email
        request_password_reset_email
      end

      def reset_password
        reset_password_with_token
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
        logic = AccountAPI::Logic::Authentication::ResetPassword.new(strategy_result, req.params, locale)
        execute_with_error_handling(
          logic,
          success_message: 'Your password has been reset',
          success_redirect: '/signin',
          error_redirect: '/forgot',
        )
      end

      def request_password_reset_email
        logic = AccountAPI::Logic::Authentication::ResetPasswordRequest.new(strategy_result, req.params, locale)
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
