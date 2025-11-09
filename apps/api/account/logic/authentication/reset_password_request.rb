# apps/api/account/logic/authentication/reset_password_request.rb
#
# frozen_string_literal: true

require_relative '../base'

module AccountAPI::Logic
  module Authentication
    using Familia::Refinements::TimeLiterals

    class ResetPasswordRequest < AccountAPI::Logic::Base
      include Onetime::LoggerMethods

      attr_reader :login_or_email
      attr_accessor :token

      def process_params
        @login_or_email = params[:u].to_s.downcase
      end

      def raise_concerns
        raise_form_error 'Not a valid email address', field: 'email', error_type: 'invalid' unless valid_email?(@login_or_email)
        raise_form_error 'No account found', field: 'email', error_type: 'not_found' unless Onetime::Customer.exists?(@login_or_email)
      end

      def process
        # Important: don't store the customer record as an instance variable
        # which obviously makes it available to other methods and potentially
        # leaks data. This reset password request logic is sensitive and not
        # authenticated, so be careful about what is returned or logged.
        cust = Onetime::Customer.load @login_or_email

        if cust.pending?
          auth_logger.info 'Resending verification email for pending customer', {
            customer_id: cust.objid,
            email: cust.obscure_email,
            status: :pending
          }

          send_verification_email
          msg = "#{i18n.dig(:web, :COMMON, :verification_sent_to)} #{cust.objid}."
          return set_info_message(msg)
        end

        secret                    = Onetime::Secret.create! @login_or_email, [@login_or_email]
        secret.default_expiration = 24.hours
        secret.verification       = 'true'
        secret.save

        cust.reset_secret = secret.identifier  # as a standalone dbkey, writes immediately

        view = OT::Mail::PasswordRequest.new cust, locale, secret

        auth_logger.debug 'Delivering password reset email', {
          customer_id: cust.objid,
          email: cust.obscure_email,
          secret_identifier: secret.identifier,
          token: token&.slice(0, 8) # Only log first 8 chars for debugging
        }

        begin
          view.deliver_email token
        rescue StandardError => ex
          errmsg = "Couldn't send the notification email. Let know below."
          auth_logger.error 'Password reset email delivery failed', {
            customer_id: cust.objid,
            email: cust.obscure_email,
            error: ex.message,
            session_id: sess&.id
          }

          set_error_message(errmsg)
        else
          auth_logger.info 'Password reset email sent', {
            customer_id: cust.objid,
            email: cust.obscure_email,
            session_id: sess&.id,
            secret_identifier: secret.identifier
          }

          set_info_message "We sent instructions to #{cust.objid}"
        end

        success_data
      end

      def success_data
        { objid: nil, sent: true }
      end
    end
  end
end
