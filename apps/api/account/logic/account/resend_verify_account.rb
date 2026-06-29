# apps/api/account/logic/account/resend_verify_account.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/logic/sso_only_gating'

module AccountAPI::Logic
  module Account
    # Resend the account verification email for an Unverified account.
    #
    # POST /api/account/resend-verification-email   (auth=noauth)
    #
    # ANTI-ENUMERATION CONTRACT:
    #   Returns an IDENTICAL HTTP 200 + identical body ({ sent: true }) for ALL
    #   outcomes:
    #     - nonexistent login
    #     - already-verified account
    #     - unverified, email just (re)sent
    #     - unverified, throttled within verify_account_skip_resend_email_within
    #     - any internal error
    #     - verify_account / full mode disabled (no-op)
    #   The ONLY observable difference between outcomes is the SERVER-SIDE audit
    #   log (Auth::Logging.log_auth_event). Never branch the HTTP response on
    #   account state. The only allowed non-200 is a structurally malformed
    #   request (blank/missing login) — never an enumeration signal. (/api/
    #   paths are CSRF-exempt by design — see lib/onetime/middleware/security.rb
    #   — so CSRF is not enforced here; the endpoint must work for a cold,
    #   sessionless user.)
    #
    # MECHANISM:
    #   Delegates to Rodauth's verify_account feature via internal_request:
    #     Auth::Config.verify_account_resend(login:)
    #   Rodauth internally enforces:
    #     - status_id == 1 (Unverified) gate
    #     - verify_account_skip_resend_email_within (300s) throttle via
    #       account_verification_keys.email_last_sent
    #     - reuse of create_verify_account_email (Welcome) template
    #   Rodauth raises Rodauth::InternalRequestError for every no-op branch
    #   (unknown login, already-verified, throttled); we catch it and still
    #   return the uniform 200.
    class ResendVerifyAccount < AccountAPI::Logic::Base
      include Onetime::LoggerMethods
      include Onetime::Logic::SsoOnlyGating

      # Frozen, account-state-independent body. Returned for EVERY outcome.
      # success_data returns a .dup so callers can never mutate the shared body.
      UNIFORM_RESPONSE = { sent: true }.freeze

      def process_params
        @login = sanitize_email(params['login'].to_s)
      end

      def raise_concerns
        require_non_sso_only!

        # The ONLY non-uniform failure: a structurally invalid request.
        # A blank email is a client error, not an enumeration signal.
        raise_form_error('Email is required', error_type: :invalid) if @login.to_s.empty?
      end

      def process
        obscured = OT::Utils.obscure_email(@login)

        # full mode only; in non-full modes there is no rodauth verification flow.
        #
        # IMPORTANT: in non-full modes the auth boot chain
        # (apps/web/auth/config.rb) is NOT loaded — the Application Registry
        # rejects `web/auth/` files unless full_enabled? (see
        # lib/onetime/application/registry.rb). That means `Auth::Logging` is
        # UNDEFINED here, so this branch must NOT reference it (doing so raises
        # NameError -> Otto 500, breaking the uniform-200 contract on the
        # default 'simple' deployment). Use auth_logger, which is always loaded
        # via Onetime::LoggerMethods, with a distinct/greppable message.
        unless Onetime.auth_config.full_enabled? &&
               Onetime.auth_config.verify_account_enabled?
          log_resend_event(
            :verify_account_resend_noop,
            level: :debug,
            email: obscured,
            reason: 'verify_account_disabled',
          )
          return success_data
        end

        begin
          # internal_request: runs status check, throttle, send_verify_account_email.
          # Raises Rodauth::InternalRequestError on the no-op branches (unknown
          # login, already verified, throttled). Returns normally on a real send.
          Auth::Config.verify_account_resend(login: @login)

          log_resend_event(
            :verify_account_resend_sent,
            level: :info,
            log_metric: true,
            email: obscured,
          )
        rescue Rodauth::InternalRequestError => ex
          # Expected for: unknown login, already-verified, throttled.
          # These are NOT errors from the caller's perspective — log + uniform 200.
          log_resend_event(
            :verify_account_resend_blocked,
            level: :debug,
            email: obscured,
            reason: ex.message,
          )
        rescue StandardError => ex
          # Infrastructure failure (DB, mailer). Still uniform 200 to the client.
          auth_logger.error '[resend-verify-account] resend failed', exception: ex
          log_resend_event(
            :verify_account_resend_error,
            level: :error,
            email: obscured,
            exception: ex.class.name,
          )
        end

        success_data
      end

      # Override Base#success_data: return the frozen uniform body verbatim.
      # Do NOT call super (which would strip :success / rename :custid) — there
      # is no account context here and the body must be byte-identical every
      # call, for every account state.
      def success_data
        UNIFORM_RESPONSE.dup
      end

      private

      # Emit a differentiated, server-side-only audit event.
      #
      # Prefers Auth::Logging.log_auth_event (the auth subsystem's structured
      # event logger with metric support), but that constant is ONLY defined
      # when the full-mode auth boot chain (apps/web/auth/config.rb) has loaded.
      # In non-full ('simple'/'disabled') modes the Application Registry never
      # loads `web/auth/` files, so Auth::Logging is undefined; referencing it
      # would raise NameError and produce a 500, breaking the uniform-200
      # contract. We therefore fall back to auth_logger (always available via
      # Onetime::LoggerMethods) with a distinct, greppable "[event]" message.
      def log_resend_event(event, level: :info, log_metric: false, **payload)
        if defined?(Auth::Logging)
          Auth::Logging.log_auth_event(event, level: level, log_metric: log_metric, **payload)
        else
          auth_logger.public_send(level, "[#{event}]", **payload)
        end
      end
    end
  end
end
