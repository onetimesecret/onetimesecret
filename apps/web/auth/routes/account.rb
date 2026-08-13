# apps/web/auth/routes/account.rb
#
# frozen_string_literal: true

module Auth
  module Routes
    module Account
      # Rodauth account status IDs
      VERIFIED_STATUS_ID = 2

      # Validates account exists for current session, returns account or halts with 401
      def require_valid_account
        account = rodauth.account_from_session
        return account if account

        # Handle orphaned session (account deleted while session active)
        # Use rodauth.clear_session for complete cleanup (cookie + server-side)
        rodauth.clear_session
        response.status = 401
        request.halt({ error: 'web.auth.security.session_expired', success: false })
      end

      # Helper to count recovery codes for an account
      # Queries database directly to avoid auto-generation side effects
      def recovery_codes_count_for(account_id)
        return 0 unless rodauth.respond_to?(:recovery_codes_available?)

        rodauth.db[:account_recovery_codes]
          .where(id: account_id)
          .count
      end

      # Builds the standard account info hash used by account endpoints.
      # Queries MFA status, active sessions, and password presence.
      def build_account_info(account, rodauth)
        mfa_enabled          = rodauth.respond_to?(:otp_exists?) && rodauth.otp_exists?
        recovery_codes_count = recovery_codes_count_for(account[:id])

        active_sessions_count = rodauth.db[:account_active_session_keys]
          .where(account_id: account[:id])
          .count

        has_password = rodauth.db[:account_password_hashes]
          .where(id: account[:id]).any?

        # Deliberately NOT gated on the webauthn feature being loaded (unlike
        # mfa-status's webauthn_enabled): passkeys_count is management /
        # visibility data for Settings -> Security, not an offer of a
        # completable factor. With AUTH_WEBAUTHN_ENABLED temporarily off,
        # hiding existing credentials would misreport account state.
        passkeys_count = rodauth.db[:account_webauthn_keys]
          .where(account_id: account[:id])
          .count

        {
          id: account[:id],
          email: account[:email],
          created_at: account[:created_at],
          status: account[:status_id],
          email_verified: account[:status_id] == VERIFIED_STATUS_ID,
          has_password: has_password,
          mfa_enabled: mfa_enabled,
          recovery_codes_count: recovery_codes_count,
          active_sessions_count: active_sessions_count,
          passkeys_count: passkeys_count,
        }
      end

      def handle_account_routes(r)
        # Account info endpoint (JSON extension support)
        r.get 'account.json' do
            unless rodauth.logged_in?
              response.status = 401
              next { error: 'Authentication required' }
            end

            account = require_valid_account
            build_account_info(account, rodauth)
          rescue StandardError => ex
            puts "Error: #{ex.class} - #{ex.message}"
            puts ex.backtrace.join("\n") if ENV['RACK_ENV'] == 'development'

            response.status = 500
            { error: 'Internal server error' }
        end

        # MFA status endpoint
        r.get 'mfa-status' do
            unless rodauth.logged_in?
              response.status = 401
              next { error: 'Authentication required' }
            end

            require_valid_account

            # Check if MFA features are enabled (OTP or recovery codes)
            #
            # NOTE: We check for the method first b/c it only exists while the
            # feature is enabled. Otherwise this would raise a MethodNotFound error.
            has_otp = rodauth.respond_to?(:otp_exists?) && rodauth.otp_exists?

            # Get count of unused recovery codes
            # Note: Don't use rodauth.recovery_codes.size as it may auto-generate codes
            recovery_codes_remaining = recovery_codes_count_for(rodauth.account_id)

            # MFA is enabled if either OTP is setup OR recovery codes exist.
            #
            # NOTE: webauthn deliberately does NOT feed into `enabled` — other
            # UI consumes it as "TOTP-family MFA on". The MFA challenge page
            # reads the per-factor booleans below instead.
            enabled = has_otp || recovery_codes_remaining > 0

            # Per-factor booleans for the MFA challenge page: it must offer a
            # passkey factor and must not auto-complete auth for an account
            # whose only second factor is webauthn.
            #
            # Gated on the completion route being loaded, mirroring has_otp
            # above: with AUTH_WEBAUTHN_ENABLED=false the /auth/webauthn-auth
            # route is not mounted, so advertising leftover credential rows
            # here would send the SPA's "Use a passkey instead" POST into a
            # 404. Feature off => false, rows or not. (passkeys_count in
            # build_account_info deliberately stays ungated — see there.)
            webauthn_enabled = rodauth.respond_to?(:webauthn_auth_route) &&
                               rodauth.db[:account_webauthn_keys]
                                 .where(account_id: rodauth.account_id)
                                 .any?

            # Get last_use timestamp from account_otp_keys table if OTP is enabled
            last_used_at = nil
            if has_otp
              otp_record   = rodauth.db[:account_otp_keys]
                .where(id: rodauth.account_id)
                .first
              last_used_at = otp_record[:last_use]&.iso8601 if otp_record
            end

            response.headers['Content-Type'] = 'application/json'
            {
              enabled: enabled,
              otp_enabled: has_otp,
              webauthn_enabled: webauthn_enabled,
              last_used_at: last_used_at,
              recovery_codes_remaining: recovery_codes_remaining,
              recovery_codes_limit: Auth::Config::Features::MFA::RECOVERY_CODES_LIMIT,
            }
          rescue StandardError => ex
            puts "Error: #{ex.class} - #{ex.message}"
            puts ex.backtrace.join("\n") if ENV['RACK_ENV'] == 'development'

            response.status = 500
            { error: 'Internal server error' }
        end

        # Account info endpoint
        r.get 'account' do
            unless rodauth.logged_in?
              response.status = 401
              next { error: 'Authentication required' }
            end

            account = require_valid_account
            build_account_info(account, rodauth)
          rescue StandardError => ex
            puts "Error: #{ex.class} - #{ex.message}"
            puts ex.backtrace.join("\n") if ENV['RACK_ENV'] == 'development'

            response.status = 500
            { error: 'Internal server error' }
        end
      end
    end
  end
end
