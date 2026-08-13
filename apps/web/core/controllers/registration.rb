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

        enforce_password_restrict_to!

        logic = AccountAPI::Logic::Account::CreateAccount.new(strategy_result, req.params, locale)

        # Same message for new/existing accounts (email enumeration prevention)
        success_message = if resolve_autoverify
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
        enforce_password_restrict_to!

        request_password_reset_email
      end

      def reset_password
        enforce_password_restrict_to!

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

      # RESTRICT_TO ENFORCEMENT (ADR-024 A1/A7, #4139).
      #
      # A7, "Scope, settled": pre-auth password surfaces are NOT exempt from the
      # 404 rule — create-account, reset-password-request and reset-password are
      # reachable unauthenticated and go dark with the method. In full mode the
      # equivalent Rodauth routes are gated by before_rodauth
      # (apps/web/auth/config/hooks/restrict_to.rb); in simple mode they are
      # served from here, so without this enforcement would be mode-dependent —
      # the exact defect the simple-mode login gate was added to fix.
      #
      # Reject shape matches the sibling gate in
      # Core::Controllers::Authentication#authenticate: Onetime::RecordNotFound,
      # which otto_hooks renders as a 404. Not a 403 — a restricted-away method
      # presents no reachable surface at all (A7).
      #
      # Resolution is not re-derived here (A2): Base#restrict_to_allows? asks
      # the model-owned resolver, same as the display and full-mode gates.
      def enforce_password_restrict_to!
        return if restrict_to_allows?('password')

        raise Onetime::RecordNotFound, 'Not Found'
      end

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
