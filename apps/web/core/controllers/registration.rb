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

        begin
          logic.raise_concerns
          logic.process

          # Set authenticated_at for session validation consistency
          session['authenticated_at'] = Time.now.to_i

          if json_requested?
            json_success('Your account has been created')
          else
            res.redirect '/'
          end
        rescue OT::FormError => ex
          raise unless json_requested?

          # Extract field from error message if possible, default to 'email'
          field = ex.message.downcase.include?('password') ? 'password' : 'email'
          json_error(ex.message, field_error: [field, ex.message.downcase], status: 400)
        end
      end

      def request_reset
        begin
          if req.params[:key]
            # Password reset with token
            logic = V2::Logic::Authentication::ResetPassword.new(_strategy_result, req.params, locale)
            logic.raise_concerns
            logic.process

            if json_requested?
              json_success('Your password has been reset')
            else
              res.redirect '/signin'
            end
          else
            # Request password reset email
            logic = V2::Logic::Authentication::ResetPasswordRequest.new(_strategy_result, req.params, locale)
            logic.raise_concerns
            logic.process

            if json_requested?
              json_success('An email has been sent to you with a link to reset the password for your account')
            else
              res.redirect '/'
            end
          end
        rescue OT::FormError => ex
          if json_requested?
            json_error(ex.message, field_error: ['email', ex.message.downcase], status: 400)
          else
            session['error_message'] = ex.message
            res.redirect '/forgot'
          end
        rescue Onetime::MissingSecret => ex
          if json_requested?
            json_error('Invalid or expired reset token', field_error: %w[key invalid], status: 404)
          else
            session['error_message'] = 'Invalid or expired reset token'
            res.redirect '/forgot'
          end
        end
      end
    end
  end
end