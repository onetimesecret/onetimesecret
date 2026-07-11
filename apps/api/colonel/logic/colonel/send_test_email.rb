# apps/api/colonel/logic/colonel/send_test_email.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/email/send_test'

module ColonelAPI
  module Logic
    module Colonel
      # Send a diagnostic test email to verify delivery connectivity (Colonel).
      #
      # Thin adapter over {Onetime::Operations::Email::SendTest} — the single,
      # audited implementation shared with the `bin/ots email test` CLI (ticket
      # #44). This class keeps only the HTTP concerns (recipient validation, the
      # dry-run/enqueue flags, and mapping a delivery failure to a form error); the
      # op owns the build + dispatch + the AdminAuditEvent (CONTRACT 4).
      #
      # Test send DISPATCHES A REAL EMAIL, so the UI gates it behind an
      # AdminConfirmDialog (one-click confirm, low-risk verb) that shows the
      # recipient. A dry-run previews the exact email without sending (and without
      # auditing). A successful real send records EXACTLY ONE audit event
      # (verb `email.test_send`, actor = colonel extid, target = recipient).
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class SendTestEmail < ColonelAPI::Logic::Base
        attr_reader :recipient, :dry_run, :enqueue, :result

        def process_params
          @recipient = params['to'].to_s.strip
          @dry_run   = truthy?(params['dry_run'])
          @enqueue   = truthy?(params['enqueue'])
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          raise_form_error('Recipient email is required', field: :to) if recipient.empty?
          raise_form_error('Recipient email is invalid', field: :to) unless valid_email?(recipient)
        end

        def process
          @result = Onetime::Operations::Email::SendTest.new(
            to: recipient,
            actor: cust.extid,
            dry_run: dry_run,
            enqueue: enqueue,
          ).call

          success_data
        rescue Onetime::Mail::DeliveryError => ex
          raise_form_error("Delivery failed: #{ex.message}", field: :to)
        rescue StandardError => ex
          raise_form_error("Send failed: #{ex.message}", field: :to)
        end

        def success_data
          diagnostic = result.diagnostic
          {
            record: {
              to: diagnostic.to,
              status: result.status.to_s,
              sent: result.status != :dry_run,
            },
            details: {
              provider: diagnostic.provider,
              host: diagnostic.host,
              from: diagnostic.from,
              subject: diagnostic.subject,
              text_body: diagnostic.text_body,
              timestamp: diagnostic.timestamp,
            },
          }
        end

        private

        def truthy?(value)
          %w[true 1 yes on].include?(value.to_s.strip.downcase)
        end
      end
    end
  end
end
