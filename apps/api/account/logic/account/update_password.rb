# apps/api/account/logic/account/update_password.rb
#
# frozen_string_literal: true

require 'onetime/logic/credential_change_session_revocation'
require 'onetime/logic/sso_only_gating'

module AccountAPI::Logic
  module Account
    class UpdatePassword < UpdateAccountField
      include Onetime::LoggerMethods
      include Onetime::Logic::CredentialChangeSessionRevocation
      include Onetime::Logic::SsoOnlyGating

      def raise_concerns
        require_non_sso_only!
        super
      end

      def process_params
        auth_logger.debug '[UpdatePassword#process_params] param keys', param_keys: params.keys.sort
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
          revoke_other_sessions_simple_mode
        end
      end

      # SECURITY (M-2): changing the password must sign out every OTHER session
      # (the standard "someone may know my password" remediation) while KEEPING
      # the session the user is changing it from. In full mode the Rodauth
      # after_change_password hook does this; that hook never fires in simple
      # mode, so enforce it here via the same watermark + revoke sequence
      # (CredentialChangeSessionRevocation).
      def revoke_other_sessions_simple_mode
        # Resolve the current sid (== the sid tracked in Customer#active_sessions).
        # If it cannot be determined we fail SECURE: except_session_id stays nil,
        # revoking ALL sessions incl. the current one, so the user is simply
        # logged out rather than a stale session surviving.
        current_sid = begin
          sid = safe_session_id
          sid.respond_to?(:public_id) ? sid.public_id : sid&.to_s
        rescue StandardError => ex
          auth_logger.warn '[update-password] current session id unresolved', error: ex.message
          nil
        end

        watermark = revoke_sessions_for_credential_change(cust, except_session_id: current_sid)

        # The watermark's `<=` auth-time check retires any session authenticated
        # at-or-before it — including the one just preserved. Re-stamp the kept
        # session STRICTLY past the watermark (same maneuver as the full-mode
        # hook's post-rotation re-stamp) so both that check and the
        # watermark-honoring async sweep spare it. When the stamp failed
        # (watermark 0) fall back to now + 1 so the invariant still holds
        # against a same-second stamp retry. A sess that cannot be written
        # (nil / frozen) degrades to the fail-secure logout above.
        return unless sess.respond_to?(:[]=)

        sess['authenticated_at'] =
          watermark.positive? ? [Familia.now.to_i, watermark + 1].max : Familia.now.to_i + 1
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
        auth_logger.error '[update-password] Rodauth verification failed', exception: ex
        false
      rescue StandardError => ex
        auth_logger.error '[update-password] Password verification error', exception: ex
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
        auth_logger.error '[update-password] Rodauth change_password failed', exception: ex
        raise_form_error 'Password change failed', error_type: 'system_error'
      end
    end
  end
end
