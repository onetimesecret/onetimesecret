require_relative '../base'

module V1::Logic
  module Authentication
    class ResetPassword < V1::Logic::Base
      attr_reader :secret, :is_confirmed
      def process_params
        @secret = V1::Secret.load params[:key].to_s
        @newp = self.class.normalize_password(params[:newp])
        @newp2 = self.class.normalize_password(params[:newp2])
        @is_confirmed = Rack::Utils.secure_compare(@newp, @newp2)
      end

      def raise_concerns
        raise OT::MissingSecret if secret.nil?
        raise OT::MissingSecret if secret.custid.to_s == 'anon'



        raise_form_error "New passwords do not match" unless is_confirmed
        raise_form_error "New password is too short" unless @newp.size >= 6
      end

      def process
        if is_confirmed
          # Load the customer information from the premade secret
          cust = secret.load_customer

          unless cust.valid_reset_secret!(secret)
            # If the secret is a reset secret, we can proceed to change
            # the password. Otherwise, we should not be able to change
            # the password.
            secret.received!
            raise_form_error "Invalid reset secret"
          end

          if cust.pending?
            # If the customer is pending, we need to verify the account
            # before we can change the password. We should not be able to
            # change the password of an account that has not been verified.
            # This is to prevent unauthorized password changes.
            raise_form_error "Account not verified"
          end

          # Update the customer's passphrase
          cust.update_passphrase @newp

          # Set a success message in the session
          sess.set_success_message "Password changed"

          # Destroy the secret on successful attempt only. Otherwise
          # the user will need to make a new request if the passwords
          # don't match.
          secret.destroy!

          # Log the success message
          OT.info "Password successfully changed for customer #{cust.custid}"

        else
          # Log the failure message
          OT.info "Password change failed: password confirmation not received"
        end

      end

      def success_data
        { custid: @cust.custid }
      end
    end
  end
end
