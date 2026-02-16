# apps/api/account/logic/account/request_email_change.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative '../../../../../lib/onetime/jobs/publisher'

module AccountAPI::Logic
  module Account
    using Familia::Refinements::TimeLiterals

    class RequestEmailChange < UpdateAccountField
      include Onetime::LoggerMethods

      attr_reader :new_email

      def process_params
        @password  = self.class.normalize_password(params['password'])
        @new_email = sanitize_email(params['new_email'])
      end

      def success_data
        { sent: true }
      end

      private

      def field_name
        :email
      end

      def field_specific_concerns
        raise_form_error 'Password is required', field: 'password', error_type: 'required' if @password.empty?
        raise_form_error 'New email is required', field: 'new_email', error_type: 'required' if @new_email.empty?

        unless verify_password(@password)
          raise_form_error 'Current password is incorrect', field: 'password', error_type: 'incorrect'
        end

        raise_form_error 'Please enter a valid email address', field: 'new_email', error_type: 'invalid' unless valid_email?(@new_email)
        raise_form_error 'New email must be different from current email', field: 'new_email', error_type: 'same_as_current' if @new_email == cust.email

        # Generic message to avoid revealing whether an email is in use
        raise_form_error 'This email cannot be used', field: 'new_email', error_type: 'unavailable' if Onetime::Customer.email_exists?(@new_email)
      end

      def valid_update?
        verify_password(@password) && valid_email?(@new_email) && @new_email != cust.email
      end

      def perform_update
        # Create a verification secret with 24h TTL following ResetPasswordRequest pattern
        secret                    = Onetime::Secret.create!(owner_id: cust.objid)
        secret.default_expiration = 24.hours
        secret.verification       = 'true'
        secret.custid             = cust.objid
        secret.ciphertext         = @new_email
        secret.save

        # Track the pending change on the customer (standalone dbkey, writes immediately)
        cust.pending_email_change = secret.identifier

        OT.info "[request-email-change] Email change requested cid/#{cust.objid} new_email/#{OT::Utils.obscure_email(@new_email)}"

        # Send confirmation email to the NEW address
        begin
          Onetime::Jobs::Publisher.enqueue_email(
            :email_change_confirmation,
            {
              new_email: @new_email,
              confirmation_token: secret.identifier,
              locale: locale || cust.locale || OT.default_locale,
            },
            fallback: :sync,
          )
        rescue StandardError => ex
          OT.le "[request-email-change] Failed to send confirmation email: #{ex.message}"
        end

        # Send notification email to the OLD address
        begin
          Onetime::Jobs::Publisher.enqueue_email(
            :email_changed,
            {
              old_email: cust.email,
              new_email_masked: mask_email(@new_email),
              locale: locale || cust.locale || OT.default_locale,
            },
            fallback: :async_thread,
          )
        rescue StandardError => ex
          OT.le "[request-email-change] Failed to send notification email: #{ex.message}"
        end
      end

      # Verify password using the appropriate mechanism based on auth mode.
      def verify_password(password)
        return false if password.to_s.empty?

        if Onetime.auth_config.full_enabled?
          verify_password_full_mode(password)
        else
          cust.passphrase?(password)
        end
      end

      def verify_password_full_mode(password)
        db = Auth::Database.connection
        return false unless db

        account = db[:accounts].where(external_id: cust.extid).first
        return false unless account

        password_hash_row = db[:account_password_hashes].where(id: account[:id]).first
        return false unless password_hash_row

        stored_hash = password_hash_row[:password_hash]
        return false if stored_hash.to_s.empty?

        ::Argon2::Password.verify_password(password, stored_hash)
      rescue StandardError => ex
        OT.le "[request-email-change] Password verification error: #{ex.message}"
        false
      end

      # Mask email: "user@example.com" → "u***@example.com"
      def mask_email(email)
        OT::Utils.obscure_email(email)
      end
    end
  end
end
