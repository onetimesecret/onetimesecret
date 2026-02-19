# apps/api/account/logic/account/resend_email_change_confirmation.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative '../../../../../lib/onetime/jobs/publisher'

module AccountAPI::Logic
  module Account
    using Familia::Refinements::TimeLiterals

    # Resend the email change confirmation email
    #
    # POST /api/account/resend-email-change-confirmation
    #
    # Requires: Authenticated user with a pending email change
    # Rate-limited to MAX_RESENDS per pending change
    #
    class ResendEmailChangeConfirmation < AccountAPI::Logic::Base
      include Onetime::LoggerMethods

      MAX_RESENDS = 3

      attr_reader :secret

      def process_params
        # No params needed - uses the authenticated user's pending change
      end

      def raise_concerns
        raise_form_error('Authentication required', error_type: :unauthorized) if cust.anonymous?

        # Verify there is a pending email change
        pending_identifier = cust.pending_email_change.to_s
        if pending_identifier.empty?
          raise_form_error('No pending email change', error_type: :not_found)
        end

        # Load the verification secret
        @secret = Onetime::Secret.find_by_identifier(pending_identifier)
        if @secret.nil? || !@secret.exists?
          # Secret expired or was deleted - clean up the stale reference
          cust.pending_email_change.delete!
          raise_form_error('Email change request has expired', error_type: :expired)
        end

        unless @secret.verification?
          raise_form_error('Email change request has expired', error_type: :expired)
        end

        # Rate limit resends
        count = resend_count
        return unless count >= MAX_RESENDS

        raise_form_error(
          "Maximum resend limit (#{MAX_RESENDS}) reached",
          error_type: :rate_limited,
        )
      end

      def process
        new_email = sanitize_email(@secret.decrypted_secret_value)

        if new_email.to_s.empty?
          raise_form_error('Unable to determine new email address', error_type: :system_error)
        end

        increment_resend_count

        OT.info "[resend-email-change] Resending confirmation cid/#{cust.objid} new_email/#{OT::Utils.obscure_email(new_email)} (count: #{resend_count})"

        # Re-send confirmation email to the NEW address
        Onetime::Jobs::Publisher.enqueue_email(
          :email_change_confirmation,
          {
            new_email: new_email,
            confirmation_token: @secret.identifier,
            locale: locale || cust.locale || OT.default_locale,
          },
          fallback: :sync,
        )

        success_data
      end

      def success_data
        { sent: true, resend_count: resend_count }
      end

      private

      # Redis key for tracking resend count, scoped to the customer.
      # TTL matches the pending_email_change (24h) so the counter
      # auto-expires when the change request does.
      def resend_count_key
        "email_change_resend:#{cust.objid}"
      end

      def resend_count
        Familia.dbclient.get(resend_count_key).to_i
      end

      def increment_resend_count
        key = resend_count_key
        Familia.dbclient.incr(key)
        # Set TTL only on the first increment (when TTL is -1, meaning no expiry set)
        Familia.dbclient.expire(key, 24 * 60 * 60) if Familia.dbclient.ttl(key) == -1
      end
    end
  end
end
