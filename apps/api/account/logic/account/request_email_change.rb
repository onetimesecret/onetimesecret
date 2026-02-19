# apps/api/account/logic/account/request_email_change.rb
#
# frozen_string_literal: true

# ## Security Analysis: Email Change Notification Timing
#
# The request-time notification is the more important of the two because
# it provides the only window for user intervention before account
# takeover is complete.
#
# When an attacker has obtained the user's password (credential stuffing,
# phishing, database breach) or hijacked an active session, the only
# remaining defense is the legitimate user's awareness. Notifying at
# request time gives the user up to 24 hours (the token TTL) to take
# action before the change is finalized. If notification is deferred to
# confirmation time, the user learns about the change only after:
#
# - Their email has been swapped
# - All sessions have been invalidated
# - They can no longer log in with their old email
#
# At that point, the user's only recourse is to contact support. The
# attacker has already completed the takeover.
#
# Password re-authentication is necessary but not sufficient. The flow
# correctly requires the current password, which means a pure session
# hijack without the password cannot initiate the change. However,
# password compromise is the more dangerous scenario, and it is exactly
# the scenario where early notification matters most. The legitimate user
# seeing "someone requested an email change on your account" can
# immediately change their password and revoke the pending change.
#
# The correct approach is to notify the old email at both stages:
# 1. At request time: alert about pending change with intervention guidance
# 2. At confirmation time: definitive notice that the change went through
#
# This matches Google, GitHub, and AWS patterns and satisfies NIST
# 800-63B (Section 6.1.2.1) guidance on pre-change notification for
# authenticator binding changes. OWASP Authentication Cheat Sheet
# recommends notifying when security-sensitive operations occur at
# the existing (old) email address.
#
# From a compliance perspective (SOC 2 CC6.1, CC7.2; NIST 800-53
# AC-2(4), AU-12), credential changes should generate audit events at
# both the initiation and completion of the change.

require_relative '../base'
require_relative '../../../../../lib/onetime/jobs/publisher'

module AccountAPI::Logic
  module Account
    using Familia::Refinements::TimeLiterals

    class RequestEmailChange < UpdateAccountField
      include Onetime::LoggerMethods

      # Per-customer rate limit: at most MAX_REQUESTS email change requests
      # within a 24-hour rolling window. Prevents billing API exhaustion via
      # automated abuse of this authenticated endpoint.
      MAX_REQUESTS = 5

      attr_reader :new_email

      def process_params
        @password  = self.class.normalize_password(params['password'])
        @new_email = sanitize_email(params['new_email'])
      end

      def success_data
        { sent: true, delivery_status: 'queued' }
      end

      private

      def field_name
        :email
      end

      def field_specific_concerns
        raise_form_error 'Password is required', field: 'password', error_type: 'required' if @password.empty?
        raise_form_error 'New email is required', field: 'new_email', error_type: 'required' if @new_email.empty?

        # Rate-limit check (before password verification to avoid timing oracle)
        if request_count >= MAX_REQUESTS
          raise_form_error(
            "Maximum email change attempts (#{MAX_REQUESTS}) reached. Try again in 24 hours.",
            error_type: :rate_limited,
          )
        end

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
        # Increment the per-customer request counter before touching external APIs.
        # Counter is checked in field_specific_concerns; incrementing here (inside
        # the happy-path write path) means failed validations don't burn the quota.
        increment_request_count

        # Create a verification secret with 24h TTL following ResetPasswordRequest pattern
        secret                    = Onetime::Secret.create!(owner_id: cust.objid)
        secret.default_expiration = 24.hours
        secret.verification       = 'true'
        secret.custid             = cust.objid
        secret.ciphertext         = @new_email
        secret.save

        # Track the pending change on the customer (standalone dbkey, writes immediately)
        cust.pending_email_change          = secret.identifier
        cust.pending_email_delivery_status = 'queued'

        OT.info "[request-email-change] Email change requested cid/#{cust.objid} new_email/#{OT::Utils.obscure_email(@new_email)}"

        # Send confirmation email to the NEW address
        begin
          Onetime::Jobs::Publisher.enqueue_email(
            :email_change_confirmation,
            {
              new_email: @new_email,
              confirmation_token: secret.identifier,
              customer_objid: cust.objid,
              locale: locale || cust.locale || OT.default_locale,
            },
            fallback: :sync,
          )
        rescue StandardError => ex
          OT.le "[request-email-change] Failed to send confirmation email: #{ex.message}"
        end

        # Send notification email to the OLD address (request-time, present tense)
        begin
          Onetime::Jobs::Publisher.enqueue_email(
            :email_change_requested,
            {
              old_email: cust.email,
              new_email: @new_email,
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

      # Verify password against Rodauth's auth database (full mode).
      # Uses Rodauth's internal_request feature which handles argon2 secret,
      # password hash lookup, and verification internally.
      def verify_password_full_mode(password)
        Auth::Config.valid_login_and_password?(login: cust.email, password: password)
      rescue Rodauth::InternalRequestError => ex
        OT.le "[request-email-change] Rodauth verification failed: #{ex.message}"
        false
      rescue StandardError => ex
        OT.le "[request-email-change] Password verification error: #{ex.message}"
        false
      end

      # Redis key for per-customer email change request rate limiting.
      # TTL of 24 hours aligns with the verification secret TTL so that
      # the window resets naturally when secrets expire.
      def request_count_key
        "email_change_request:#{cust.objid}"
      end

      def request_count
        Familia.dbclient.get(request_count_key).to_i
      end

      def increment_request_count
        key = request_count_key
        # Use MULTI/EXEC to atomically increment and set TTL, preventing a
        # permanent-block if the process crashes between incr and expire.
        Familia.dbclient.multi do |transaction|
          transaction.incr(key)
          transaction.expire(key, 24 * 60 * 60)
        end
      end

      # Mask email: "user@example.com" → "u***@example.com"
      def mask_email(email)
        OT::Utils.obscure_email(email)
      end
    end
  end
end
