# apps/web/auth/operations/reauthenticate.rb
#
# frozen_string_literal: true

require 'json'
require 'webauthn'

require 'onetime/session/recent_reauth'
require 'onetime/session/reauth_policy'
require 'onetime/session/sidecar'

require_relative 'mfa_state_checker'

module Auth
  module Operations
    # Verify a complete local re-authentication ceremony for the account already
    # bound to the current session. This operation never establishes or replaces
    # the login session; it only writes RecentReauth after all required factors
    # have succeeded.
    class Reauthenticate
      Result          = Data.define(:status, :body, :password_verified)
      CHALLENGE_FIELD = 'reauth_webauthn_challenge'

      def initialize(db, rodauth:, session:, env:)
        @db      = db
        @rodauth = rodauth
        @session = session
        @env     = env
      end

      def call(account_id:, offer:, params:)
        method = params['method'].to_s
        return error(400, 'Unsupported re-authentication method.', 'invalid_method') unless offer[:methods].include?(method)

        account = @rodauth.account_from_session
        return error(401, 'Invalid session.', 'invalid_session') unless account
        return error(401, 'Invalid session.', 'invalid_session') unless account[:id].to_s == account_id.to_s

        case method
        when 'password'
          authenticate_password(account, offer, params)
        when 'webauthn'
          authenticate_webauthn(account_id, offer, params, primary: true)
        else
          error(400, 'Unsupported re-authentication method.', 'invalid_method')
        end
      rescue WebAuthn::Error, JSON::ParserError, ArgumentError, TypeError
        error(401, 'Passkey authentication failed.', 'invalid_webauthn')
      end

      private

      def authenticate_password(account, offer, params)
        password = params['password'].to_s
        return error(400, 'Password is required.', 'invalid_request') if password.empty?

        verified = begin
          Auth::Config.valid_login_and_password?(login: account[:email], password: password)
        rescue StandardError
          false
        end
        return error(401, 'Incorrect password.', 'invalid_password') unless verified

        state = MfaStateChecker.new(@db).check(account[:id])
        unless state.mfa_enabled?
          return record(account[:id], %w[password], password_verified: true)
        end

        unless params['otp_code'].to_s.empty?
          return authenticate_otp(account[:id], params['otp_code'])
        end

        unless params['recovery_code'].to_s.empty?
          return authenticate_recovery_code(account[:id], params['recovery_code'])
        end

        if params.key?('webauthn_auth') || params['mfa_method'] == 'webauthn' || webauthn_mfa_only?(state)
          return authenticate_webauthn(account[:id], offer, params, primary: false)
        end

        methods = password_mfa_methods(state, offer)
        return error(403, 'No supported second factor is available on this surface.', 'mfa_unavailable', true) if methods.empty?

        Result.new(status: 200, body: { 'mfa_required' => true, 'mfa_methods' => methods }, password_verified: true)
      end

      def authenticate_otp(account_id, code)
        unless @rodauth.respond_to?(:otp_valid_code?) && @rodauth.otp_exists? && !@rodauth.otp_locked_out?
          return error(401, 'Invalid authentication code.', 'invalid_otp', true)
        end

        if @rodauth.otp_valid_code?(code.to_s) && @rodauth.otp_update_last_use
          @rodauth.otp_remove_auth_failures
          return record(account_id, %w[password totp], password_verified: true)
        end

        @rodauth.otp_record_authentication_failure
        error(401, 'Invalid authentication code.', 'invalid_otp', true)
      end

      def authenticate_recovery_code(account_id, code)
        if @rodauth.respond_to?(:recovery_code_match?) && @rodauth.recovery_code_match?(code.to_s)
          return record(account_id, %w[password recovery_code], password_verified: true)
        end

        error(401, 'Invalid recovery code.', 'invalid_recovery_code', true)
      end

      def authenticate_webauthn(account_id, offer, params, primary:)
        rows = eligible_webauthn_rows(account_id, offer)
        return error(403, 'No passkey is available on this surface.', 'webauthn_unavailable', !primary) if rows.empty?

        assertion = params['webauthn_auth']
        unless assertion.is_a?(Hash)
          return webauthn_challenge(
            rows,
            account_id: account_id,
            surface: offer[:surface],
            primary: primary,
          )
        end

        credential = WebAuthn::Credential.from_get(assertion)
        row        = rows.find { |candidate| candidate[:webauthn_id].to_s == credential.id.to_s }
        return error(401, 'Passkey authentication failed.', 'invalid_webauthn', !primary) unless row

        rp_id   = effective_rp_id(row)
        pending = consume_webauthn_challenge
        unless valid_pending_challenge?(pending, account_id, offer, params, rp_id, primary)
          return error(
            401,
            'Passkey challenge expired or was already used.',
            'invalid_webauthn',
            !primary,
          )
        end
        return error(401, 'Passkey authentication failed.', 'invalid_webauthn', !primary) unless valid_challenge_hmac?(params)

        origin = @rodauth.webauthn_origin
        credential.response.define_singleton_method(:verify) do |expected_challenge, expected_origin = nil, **options|
          options[:rp_id] = rp_id
          super(expected_challenge, expected_origin || origin, **options)
        end

        challenge = params['webauthn_auth_challenge'].to_s
        verified  = credential.verify(
          challenge,
          public_key: row[:public_key],
          sign_count: row[:sign_count],
        )
        return error(401, 'Passkey authentication failed.', 'invalid_webauthn', !primary) unless verified

        updated = @db[:account_webauthn_keys]
          .where(account_id: Integer(account_id), webauthn_id: row[:webauthn_id])
          .update(sign_count: Integer(credential.sign_count), last_use: Sequel::CURRENT_TIMESTAMP)
        return error(409, 'Passkey authentication could not be completed.', 'webauthn_conflict', !primary) unless updated == 1

        methods = primary ? %w[webauthn] : %w[password webauthn]
        record(account_id, methods, password_verified: !primary)
      end

      def webauthn_challenge(rows, account_id:, surface:, primary:)
        rp_id = effective_rp_id(rows.first)
        rows  = rows.select { |row| effective_rp_id(row) == rp_id }

        options = WebAuthn::Credential.options_for_get(
          allow: rows.map { |row| row[:webauthn_id] },
          timeout: @rodauth.webauthn_auth_timeout,
          user_verification: @rodauth.webauthn_user_verification,
          rp_id: rp_id,
        )

        pending = {
          'account_id' => account_id.to_s,
          'challenge' => options.challenge,
          'surface' => surface,
          'rp_id' => rp_id,
          'primary' => primary,
        }
        written = Onetime::SessionSidecar.write(
          session_id,
          CHALLENGE_FIELD,
          pending,
        )
        unless written
          return error(
            503,
            'Passkey authentication is temporarily unavailable.',
            'webauthn_unavailable',
            !primary,
          )
        end

        Result.new(
          status: 200,
          body: {
            'webauthn_auth' => options.as_json,
            'webauthn_auth_challenge' => options.challenge,
            'webauthn_auth_challenge_hmac' => @rodauth.send(:compute_hmac, options.challenge),
          },
          password_verified: !primary,
        )
      end

      def eligible_webauthn_rows(account_id, offer)
        columns = [:webauthn_id, :public_key, :sign_count, :surface_scope]
        columns << :rp_id if @db.schema(:account_webauthn_keys).any? { |column, _| column == :rp_id }

        @db[:account_webauthn_keys]
          .where(account_id: Integer(account_id))
          .select(*columns)
          .all
          .select { |row| credential_eligible?(row, offer) }
      end

      def credential_eligible?(row, offer)
        descriptor = credential_descriptor(row[:surface_scope])
        descriptor = descriptor.merge(rp_id: row[:rp_id]) unless row[:rp_id].to_s.empty?

        Onetime::ReauthPolicy.webauthn_offerable?(
          offer[:surface],
          [descriptor],
          offer[:related_origins],
          current_origin: offer[:current_origin],
        )
      end

      def credential_descriptor(raw_scope)
        parsed = raw_scope.to_s.empty? ? {} : JSON.parse(raw_scope)
        case parsed['kind'].to_s
        when 'custom'
          parsed['id'].to_s.empty? ? { scope: :platform } : { scope: :tenant, id: parsed['id'].to_s }
        when 'subdomain'
          parsed['host'].to_s.empty? ? { scope: :platform } : { scope: :subdomain, host: parsed['host'].to_s.downcase }
        else
          { scope: :platform }
        end
      rescue JSON::ParserError
        { scope: :platform }
      end

      def effective_rp_id(row)
        row[:rp_id].to_s.empty? ? @rodauth.webauthn_rp_id : row[:rp_id].to_s
      end

      def session_id
        @session.id&.public_id
      rescue StandardError
        nil
      end

      def consume_webauthn_challenge
        Onetime::SessionSidecar.consume(session_id, CHALLENGE_FIELD)
      end

      def valid_pending_challenge?(pending, account_id, offer, params, rp_id, primary)
        return false unless pending.is_a?(Hash)

        pending['account_id'] == account_id.to_s &&
          pending['challenge'] == params['webauthn_auth_challenge'].to_s &&
          pending['surface'] == offer[:surface] &&
          pending['rp_id'] == rp_id &&
          pending['primary'] == primary
      end

      def valid_challenge_hmac?(params)
        challenge = params['webauthn_auth_challenge'].to_s
        supplied  = params['webauthn_auth_challenge_hmac'].to_s
        return false if challenge.empty? || supplied.empty?

        expected = @rodauth.send(:compute_hmac, challenge)
        supplied.bytesize == expected.bytesize && Rack::Utils.secure_compare(supplied, expected)
      end

      def password_mfa_methods(state, offer)
        methods = []
        methods << 'otp' if state.has_otp_secret
        methods << 'recovery_codes' if state.has_recovery_codes
        methods << 'webauthn' if state.has_webauthn && offer[:methods].include?('webauthn')
        methods
      end

      def webauthn_mfa_only?(state)
        state.has_webauthn && !state.has_otp_secret && !state.has_recovery_codes
      end

      def record(account_id, methods, password_verified: false)
        proof = Onetime::RecentReauth.record(
          @session,
          @env,
          account_id: account_id,
          methods: methods,
        )
        return error(403, 'Re-authentication is unavailable on this surface.', 'invalid_surface', password_verified) unless proof

        Result.new(
          status: 200,
          body: { 'success' => 'Re-authentication complete' },
          password_verified: password_verified,
        )
      end

      def error(status, message, code, password_verified = false)
        Result.new(
          status: status,
          body: { 'error' => message, 'error_code' => code },
          password_verified: password_verified,
        )
      end
    end
  end
end
