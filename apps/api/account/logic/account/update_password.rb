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

        rotate_and_restamp_kept_session(current_sid, watermark)
        send_password_changed_notification
      end

      # Rotate the kept session's id + re-stamp it past the watermark — the
      # same ordering-coupled pair as the full-mode hook (see the ROTATION /
      # RE-STAMP rationale in apps/web/auth/config/hooks/account.rb):
      #
      # ROTATION (session fixation): a credential change is a privilege
      # boundary, so the sid that existed before the change must not remain
      # valid after it. Setting :renew makes Rack's commit path delete the old
      # sid's blob and re-persist the session under a fresh sid (the logout
      # controller uses the same lever); write_session then re-creates the
      # sidecar + index entry for the NEW sid via TrackMetadata, so only the
      # old sid's metadata needs tidying here.
      #
      # RE-STAMP (watermark survival): the auth-time `<=` check retires any
      # session authenticated at-or-before the watermark — including the one
      # just preserved — so the kept session must be stamped STRICTLY past it.
      # The re-stamp runs ONLY after rotation has been requested: when the
      # renew lever is unavailable (sess is not a live Rack session), we do
      # NOT re-stamp, so the un-rotated pre-change sid keeps its stale
      # authenticated_at and the watermark retires it on its next request —
      # fail SECURE (the user re-authenticates) rather than re-legitimizing a
      # possibly fixated sid.
      def rotate_and_restamp_kept_session(current_sid, watermark)
        # Blank sid → the revoke above ran in ALL-sessions mode, and the
        # "user is simply logged out" promise must survive session commit:
        # left alone, the middleware can write the in-memory session back and
        # resurrect the just-revoked blob — and a rotation/re-stamp here would
        # re-legitimize it outright. Clear the session (rotating the sid when
        # the lever exists, like the logout controller) and skip
        # rotation/re-stamp entirely.
        if current_sid.to_s.empty?
          sess.clear if sess.respond_to?(:clear)
          sess.options[:renew] = true if sess.respond_to?(:options) && sess.options
          return
        end

        options = sess.respond_to?(:options) ? sess.options : nil
        if options.nil?
          auth_logger.error '[update-password] session rotation unavailable',
            customer_id: cust.extid,
            security_warning: 'session id not rotated and not re-stamped; the watermark will retire the pre-change session on its next request'
          return
        end

        options[:renew] = true

        # Strictly postdate the watermark. [now, watermark + 1].max is
        # > watermark under any clock relationship; with no usable watermark
        # (stamp failed → 0) fall back to now + 1 so the invariant still holds
        # against a same-second stamp retry.
        sess['authenticated_at'] =
          watermark.positive? ? [Familia.now.to_i, watermark + 1].max : Familia.now.to_i + 1

        # Tidy the pre-rotation sid's metadata (the tidy_sidecars pattern);
        # the new sid is tracked at session commit.
        Onetime::SessionMetadata.load(current_sid)&.destroy!
        cust.active_sessions&.remove(current_sid)
      rescue StandardError => ex
        # Rotation failure must never fail the password change, but must never
        # be silent either: without rotation the pre-change sid stays live
        # until watermark validation or TTL retires it.
        auth_logger.error '[update-password] session rotation failed',
          customer_id: cust.extid,
          error: ex.message,
          security_warning: 'password change succeeded but the session id was not rotated'
      end

      # Best-effort security notification that the password changed (parity
      # with the full-mode hook). Never let a delivery problem surface as a
      # password-change failure.
      def send_password_changed_notification
        Onetime::ErrorHandler.safe_execute('password_changed_email', external_id: cust.extid) do
          # Customers default locale to "" (matches Redis string load), which
          # is truthy and would slip past a bare `||`. Treat blank as missing.
          locale = cust.locale
          locale = OT.default_locale if locale.to_s.strip.empty?
          Onetime::Jobs::Publisher.enqueue_email(
            :password_changed,
            {
              email_address: cust.email,
              changed_at: Time.now.utc.iso8601,
              locale: locale,
            },
            fallback: :async_thread,
          )
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
