# apps/api/account/logic/authentication/reset_password_request.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative '../../../../../lib/onetime/jobs/publisher'

module AccountAPI::Logic
  module Authentication
    using Familia::Refinements::TimeLiterals

    class ResetPasswordRequest < AccountAPI::Logic::Base
      include Onetime::LoggerMethods

      attr_reader :login_or_email
      attr_accessor :token

      def process_params
        @login_or_email = sanitize_email(params['login'])
      end

      def raise_concerns
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

          send_verification_email
          return success_data
        end

        secret                    = Onetime::Secret.create! @login_or_email, [@login_or_email]
        secret.default_expiration = 24.hours
        secret.verification       = 'true'
        secret.save

        cust.reset_secret = secret.identifier  # as a standalone dbkey, writes immediately

        auth_logger.debug 'Delivering password reset email',
          {
            customer_id: cust.extid,
            email: cust.obscure_email,
            secret_identifier: secret.identifier,
            token: token&.slice(0, 8), # Only log first 8 chars for debugging
          }

        # Best-effort delivery (issue #3486). With background jobs enabled the
        # email is queued; with jobs disabled (the default) it is delivered
        # synchronously. Either way the publisher logs/reports a delivery failure
        # (Sentry) rather than raising — the reset secret is already persisted
        # and the user can request another. We return the same generic response
        # whether or not delivery succeeds, so the result never reveals delivery
        # status.
        queued = Onetime::Jobs::Publisher.enqueue_email(
          :password_request,
          {
            email_address: cust.email,
            secret: secret,
            locale: locale || cust.locale || OT.default_locale,
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
            secret_identifier: secret.identifier,
            queued: queued,
          }

        success_data
      end

      def success_data
        { objid: nil, sent: true }
      end
    end
  end
end
