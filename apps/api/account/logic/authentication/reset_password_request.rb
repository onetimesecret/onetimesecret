# apps/api/account/logic/authentication/reset_password_request.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative '../../../../../lib/onetime/jobs/publisher'
require 'onetime/security/reset_request_rate_limiter'

module AccountAPI::Logic
  module Authentication
    using Familia::Refinements::TimeLiterals

    class ResetPasswordRequest < AccountAPI::Logic::Base
      include Onetime::LoggerMethods
      include Onetime::Security::ResetRequestRateLimiter

      attr_reader :login_or_email
      attr_accessor :token

      def process_params
        # Scrub BEFORE sanitizing: Rack::Parser caches the parsed form in
        # rack.request.form_hash ahead of the UTF8Sanitizer (middleware_stack.rb),
        # so params arrive UTF-8-TAGGED but not UTF-8-VALIDATED, and
        # sanitize_email -> Sanitize.fragment raises ArgumentError on an invalid
        # byte sequence. This method runs in Onetime::Logic::Base's constructor,
        # BEFORE #raise_concerns runs the limiter, so a raise here is a 500 that
        # costs the caller no limiter budget — an uncapped hole in the cap.
        @login_or_email = sanitize_email(params['login'].to_s.scrub(''))
      end

      def raise_concerns
        # Throughput cap (#3872). First by design: every submission costs
        # budget, and a throttled probe reaches neither the format check below
        # nor the timing-sensitive lookup in #process — the residual channel
        # this bounds. Raises Onetime::LimitExceeded, rendered as the ADR-013
        # 429 (lib/onetime/application/otto_hooks.rb); both tiers key only on
        # request-observable inputs, so the 429 adds no enumeration oracle.
        #
        # Sole limiter call site when the Auth app is not mounted; the other is
        # the Rodauth before_reset_password_request_route hook in
        # apps/web/auth/config/hooks/reset_password_request.rb. Keep them in
        # lockstep on ordering and on subjects — each passes the string ITS path
        # resolves accounts with, keeping a bucket 1:1 with the lookup.
        enforce_reset_request_rate_limit!(reset_request_client_ip, @login_or_email)

        # Security (CWE-204): email enumeration prevention. Validate only the
        # email FORMAT here — do NOT check account existence in the validation
        # layer. Existence is handled in #process, which returns the same generic
        # response whether or not the account exists, so a non-existent address
        # is indistinguishable from a registered one (mirrors CreateAccount). A
        # malformed address is a fact the caller already knows, so rejecting it
        # leaks nothing.
        return if valid_email?(@login_or_email)

        raise_form_error 'Invalid email address', field: 'email', error_type: 'invalid'
      end

      def process
        # Important: don't store the customer record as an instance variable
        # which obviously makes it available to other methods and potentially
        # leaks data. This reset password request logic is sensitive and not
        # authenticated, so be careful about what is returned or logged.
        #
        # Security (CWE-204): raise_concerns validated only the email format, so
        # a well-formed address for a non-existent account reaches here. We
        # perform side effects only for a real account and return the same
        # generic response in every case, so the result never reveals whether the
        # account exists. (Response timing still differs and is a weaker residual
        # channel not addressed here.)
        cust = Onetime::Customer.find_by_email(@login_or_email)

        if cust.nil?
          # Unregistered address: do nothing observable, return the same generic
          # response a real account would get.
          auth_logger.info 'Password reset requested for unregistered email',
            { session_id: safe_session_id }
          return success_data
        end

        if cust.pending?
          auth_logger.info 'Resending verification email for pending customer',
            {
              customer_id: cust.extid,
              email: cust.obscure_email,
              status: :pending,
            }

          # send_verification_email defaults to the request-context cust, which
          # is nil in this unauthenticated flow. Pass the looked-up customer
          # explicitly so the verification secret binds to the right account
          # (PR #3545 review) — otherwise this 500s instead of returning the
          # intended generic success.
          send_verification_email(customer: cust)
          return success_data
        end

        # owner_id, never a positional custid: the auto-generated identifier is
        # emailed as the reset token (it fills the :key slot of /forgot/:key),
        # so it must stay unguessable, and ResetPassword#process resolves the
        # account from it via secret.load_owner.
        secret                    = Onetime::Secret.create!(owner_id: cust.objid)
        secret.default_expiration = 24.hours
        secret.verification       = 'true'
        secret.save

        cust.reset_secret = secret.identifier  # as a standalone dbkey, writes immediately

        # shortid only: the full identifier is the live reset token, so logging
        # it would hand accounts to anyone with log access mid-reset.
        auth_logger.debug 'Delivering password reset email',
          {
            customer_id: cust.extid,
            email: cust.obscure_email,
            secret_identifier: secret.shortid,
            token: token&.slice(0, 8), # Only log first 8 chars for debugging
          }

        # Best-effort delivery (issue #3486). With background jobs enabled the
        # email is queued; with jobs disabled (the default) it is delivered
        # synchronously. Either way the publisher logs/reports a delivery failure
        # (Sentry) rather than raising — the reset secret is already persisted
        # and the user can request another. We return the same generic response
        # whether or not delivery succeeds, so the result never reveals delivery
        # status.
        # Blank ("") locales are truthy and slip past a bare `||`; treat as missing.
        email_locale = locale
        email_locale = cust.locale if email_locale.to_s.strip.empty?
        email_locale = OT.default_locale if email_locale.to_s.strip.empty?
        queued       = Onetime::Jobs::Publisher.enqueue_email(
          :password_request,
          {
            email_address: cust.email,
            secret: secret,
            locale: email_locale,
          },
          fallback: :sync,
        )

        # `queued` is true when handed to RabbitMQ, false when the publisher fell
        # back to best-effort delivery (sync/thread). A synchronous delivery
        # failure is reported by the publisher, not here, so this records the
        # attempt without asserting the message was actually delivered.
        auth_logger.info 'Password reset email dispatch requested',
          {
            customer_id: cust.extid,
            email: cust.obscure_email,
            session_id: safe_session_id,
            secret_identifier: secret.shortid, # truncated: the full identifier is the live token
            queued: queued,
          }

        success_data
      end

      def success_data
        { objid: nil, sent: true }
      end

      private

      # Edge-masked client IP from the same StrategyResult metadata the other
      # logic-layer limiters read (CreateIncomingSecret#incoming_client_ip).
      # AuthStrategies::Helpers#client_ip sources it from env['otto.client_ip'],
      # so the key is trusted-proxy-resolved and not header-spoofable. nil skips
      # the IP tier; the per-login backstop still applies.
      def reset_request_client_ip
        strategy_result&.metadata&.[](:ip)
      end
    end
  end
end
