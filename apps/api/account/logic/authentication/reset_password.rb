# apps/api/account/logic/authentication/reset_password.rb
#
# frozen_string_literal: true

module AccountAPI::Logic
  module Authentication
    using Familia::Refinements::TimeLiterals

    class ResetPassword < AccountAPI::Logic::Base
      include Onetime::Logging

      attr_reader :secret, :is_confirmed

      def process_params
        @secret          = Onetime::Secret.load params[:key].to_s
        @newpassword     = self.class.normalize_password(params['newpassword']) # was newp
        @passwordconfirm = self.class.normalize_password(params['password-confirm']) # was newp2
        @is_confirmed    = Rack::Utils.secure_compare(@newpassword, @passwordconfirm)
      end

      def raise_concerns
        raise OT::MissingSecret if secret.nil?
        raise OT::MissingSecret if secret.custid.to_s == 'anon'

        raise_form_error 'New passwords do not match', field: 'password-confirm', error_type: 'mismatch' unless is_confirmed
        raise_form_error 'New password is too short', field: 'newpassword', error_type: 'too_short' unless @newpassword.size >= 6
      end

      def process
        # Load the customer information from the premade secret
        @cust = secret.load_owner

        unless @cust.valid_reset_secret!(secret)
          # If the secret is a reset secret, we can proceed to change
          # the password. Otherwise, we should not be able to change
          # the password.
          secret.received!

          auth_logger.warn 'Invalid reset secret attempted', {
            customer_id: @cust.custid,
            email: @cust.obscure_email,
            secret_identifier: secret.identifier,
            ip: @strategy_result&.metadata&.dig(:ip)
          }

          raise_form_error 'Invalid reset secret'
        end

        if @cust.pending?
          # If the customer is pending, we need to verify the account
          # before we can change the password. We should not be able to
          # change the password of an account that has not been verified.
          # This is to prevent unauthorized password changes.

          auth_logger.warn 'Password reset attempted for unverified account', {
            customer_id: @cust.custid,
            email: @cust.obscure_email,
            status: :pending,
            ip: @strategy_result&.metadata&.dig(:ip)
          }

          raise_form_error 'Account not verified'
        end

        # Update the customer's passphrase
        @cust.update_passphrase @newpassword

        # Set a success message in the session
        sess.set_success_message 'Password changed'

        # Destroy the secret on successful attempt only. Otherwise
        # the user will need to make a new request if the passwords
        # don't match.
        secret.destroy!

        auth_logger.info 'Password successfully changed', {
          customer_id: @cust.custid,
          email: @cust.obscure_email,
          ip: @strategy_result&.metadata&.dig(:ip),
          session_id: sess&.id
        }

        success_data
      end

      def success_data
        { user_id: @cust.objid }
      end
    end
  end
end
