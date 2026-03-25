# apps/api/account/logic/account/update_password.rb
#
# frozen_string_literal: true

require 'onetime/logic/sso_only_gating'

module AccountAPI::Logic
  module Account
    class UpdatePassword < UpdateAccountField
      include Onetime::Logic::SsoOnlyGating

      def raise_concerns
        require_non_sso_only!
        super
      end

      def process_params
        OT.ld "[UpdatePassword#process_params] param keys: #{params.keys.sort}"
        @password        = self.class.normalize_password(params['password']) # was currentp
        @newpassword     = self.class.normalize_password(params['newpassword']) # was newp
        @passwordconfirm = self.class.normalize_password(params['password-confirm']) # was newp2
      end

      def success_data
        {}
      end

      private

      def field_name
        :password
      end

      def field_specific_concerns
        raise_form_error 'Current password is required', field: 'password', error_type: 'missing' if @password.empty?

        raise_form_error 'Current password is incorrect', field: 'password', error_type: 'incorrect' unless verify_password(@password)
        raise_form_error 'New password cannot be the same as current password', field: 'newpassword', error_type: 'same_as_current' if @newpassword == @password
        raise_form_error 'New password is too short', field: 'newpassword', error_type: 'too_short' unless @newpassword.size >= 6
        raise_form_error 'New passwords do not match', field: 'passwordconfirm', error_type: 'mismatch' unless @newpassword == @passwordconfirm
      end

      def valid_update?
        verify_password(@password) && @newpassword == @passwordconfirm
      end

      def perform_update
        if Onetime.auth_config.full_enabled?
          perform_update_full_mode
        else
          cust.update_passphrase! @newpassword
        end
      end

      # Verify password using the appropriate mechanism based on auth mode.
      # In full_enabled mode (Rodauth), the Redis passphrase field is not
      # the source of truth — use Rodauth's internal request instead.
      def verify_password(password)
        return false if password.to_s.empty?

        if Onetime.auth_config.full_enabled?
          verify_password_full_mode(password)
        else
          cust.passphrase?(password)
        end
      end

      # Verify password via Rodauth internal request in full auth mode.
      # Uses Rodauth's internal_request feature which handles argon2 secret,
      # password hash lookup, and verification internally.
      def verify_password_full_mode(password)
        Auth::Config.valid_login_and_password?(login: cust.email, password: password)
      rescue Rodauth::InternalRequestError => ex
        OT.le "[update-password] Rodauth verification failed: #{ex.message}"
        false
      rescue StandardError => ex
        OT.le "[update-password] Password verification error: #{ex.message}"
        false
      end

      # Change password via Rodauth internal request in full auth mode.
      # Rodauth handles updating the auth DB; the after_change_password hook
      # syncs metadata back to the Customer record.
      def perform_update_full_mode
        Auth::Config.change_password(
          login: cust.email,
          password: @password,
          new_password: @newpassword,
        )
      rescue Rodauth::InternalRequestError => ex
        OT.le "[update-password] Rodauth change_password failed: #{ex.message}"
        raise_form_error 'Password change failed', error_type: 'system_error'
      end
    end
  end
end
