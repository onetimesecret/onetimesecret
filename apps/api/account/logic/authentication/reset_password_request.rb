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
        # Scrub invalid bytes BEFORE sanitizing. Form params arrive UTF-8-TAGGED
        # but not UTF-8-VALIDATED: Rack::Parser parses the urlencoded body
        # eagerly and caches it in rack.request.form_hash (middleware_stack.rb),
        # so the UTF8Sanitizer's replacement rack.input never reaches these
        # values — and sanitize_email -> Sanitize.fragment RAISES ArgumentError
        # on an invalid byte sequence.
        #
        # This method runs in Onetime::Logic::Base's constructor, which the
        # controller invokes OUTSIDE execute_with_error_handling and therefore
        # BEFORE raise_concerns runs the rate limiter. An unhandled raise here
        # would be an unauthenticated 500 that costs the caller no limiter
        # budget — an uncapped hole in the cap this class exists to enforce (no
        # enumeration oracle and no mail dispatch, since it dies before the
        # lookup, but unbounded 500s and Sentry noise all the same).
        #
        # scrub('') is a no-op for valid input; a garbage login then flows
        # through the limiter and fails the ordinary format check below.
        @login_or_email = sanitize_email(params['login'].to_s.scrub(''))
      end

      def raise_concerns
        # Throughput cap (#3872), FIRST — before the format check, before any
        # account lookup. Simple mode (the application default) routes
        # POST /auth/reset-password-request straight here via
        # Core::Controllers::Registration#request_reset_email; the Rodauth
        # before_reset_password_request_route hook that enforces the same
        # limiter (apps/web/auth/config/hooks/reset_password_request.rb) only
        # loads in full mode, so without this call the endpoint had no
        # throughput cap at all in the default configuration. #process below is
        # enumeration-safe by response CONTENT but keeps the statistical timing
        # residual documented there — exploiting it needs many samples per
        # target, and an uncapped endpoint also mail-bombs arbitrary addresses.
        #
        # Ordering mirrors the full-mode hook, which fires before Rodauth's own
        # param validation: every submission costs limiter budget, and a
        # throttled probe never reaches valid_email? (a Truemail call) or the
        # timing-sensitive lookup in #process. Raises Onetime::LimitExceeded,
        # which the Otto error handler renders as the ADR-013 429
        # (lib/onetime/application/otto_hooks.rb).
        #
        # ENUMERATION SAFETY: both limiter tiers key only on request-observable
        # inputs (client IP, submitted login), never on account existence, so
        # the 429 introduces no new oracle.
        #
        # The login subject is @login_or_email — the SANITIZED value #process
        # feeds to Customer.find_by_email — not the raw param. Keying on the
        # exact string this mode resolves accounts with is what keeps the
        # backstop bucket 1:1 with the lookup: submissions that differ only in
        # what sanitize_email strips collapse into one bucket instead of minting
        # a fresh budget each. (The full-mode hook passes the raw param for the
        # same reason: there Rodauth's normalize_login is the lookup key.)
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

        # owner_id keyword, matching RequestEmailChange. The legacy positional
        # call (`create! @login_or_email, [@login_or_email]`) mapped the EMAIL
        # into the identifier and left owner_id nil, which (a) made the emailed
        # reset token (/forgot/:identifier) the user's own email address —
        # guessable by anyone — and (b) broke ResetPassword#process, whose
        # `secret.load_owner` returned nil and 500'd every simple-mode reset
        # before it could change the password. With owner_id set, the
        # identifier is the auto-generated objid (an unguessable token) and
        # load_owner resolves the customer.
        secret                    = Onetime::Secret.create!(owner_id: cust.objid)
        secret.default_expiration = 24.hours
        secret.verification       = 'true'
        secret.save

        cust.reset_secret = secret.identifier  # as a standalone dbkey, writes immediately

        # Log only the truncated shortid: the full identifier IS the live reset
        # token now that it is unguessable — logging it would let anyone with
        # log access take over accounts mid-reset.
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

      # Client IP for the limiter's per-IP tier, read from the same strategy
      # metadata the other logic-layer limiters use
      # (AuthenticateSession#login_rate_limit_ip,
      # CreateIncomingSecret#incoming_client_ip). That value comes from
      # AuthStrategies::Helpers#client_ip, which prefers env['otto.client_ip'] —
      # the trusted-proxy-resolved, privacy-masked address the full-mode hook
      # reads — so neither mode's key is spoofable via forwarded headers from an
      # untrusted hop, and both bucket a caller identically.
      #
      # A nil/blank IP (no strategy metadata, e.g. a bare unit invocation) skips
      # the IP tier inside the limiter rather than pooling unknown callers into
      # one shared bucket; the per-login backstop still applies.
      def reset_request_client_ip
        strategy_result&.metadata&.[](:ip)
      end
    end
  end
end
