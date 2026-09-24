# apps/api/colonel/logic/colonel/get_stripe_webhook_event.rb
#
# frozen_string_literal: true

require 'onetime/models/colonel_audit_event'

require_relative '../base'
require 'onetime/operations/billing/webhook_visibility'

module ColonelAPI
  module Logic
    module Colonel
      # Read the safe diagnostic projection of one locally retained webhook.
      #
      # This endpoint never reads from Stripe and never exposes event_payload,
      # data_object_id, request_id, or error_message. A successful named event
      # inspection is recorded as an observation because its processing history
      # can be operationally sensitive.
      class GetStripeWebhookEvent < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelWebhookEventDetail' }.freeze

        AUDIT_VERB = 'billing.webhook.inspect'

        attr_reader :event_id, :event

        def process_params
          @event_id = sanitize_identifier(params['event_id'])
          raise_form_error('Event ID is required', field: :event_id) if event_id.to_s.empty?
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          @event = visibility.find_webhook_event(event_id)
          raise_not_found('Webhook event not found') unless event
        end

        def process
          record_access_event
          success_data
        end

        def success_data
          {
            record: visibility.webhook_event_row(event),
            details: visibility.webhook_event_detail(event),
          }
        end

        private

        def visibility
          @visibility ||= Onetime::Operations::Billing::WebhookVisibility.new
        end

        # Exactly one best-effort observation on a successful detail response.
        # It records the safe processing shape only — never error text, payload,
        # customer/object identifiers, or pending email hashes.
        def record_access_event
          row = visibility.webhook_event_row(event)

          Onetime::ColonelAuditEvent.record_access(
            actor: cust&.extid,
            verb: AUDIT_VERB,
            target: event_id,
            result: :success,
            detail: {
              event_type: row[:event_type],
              processing_status: row[:processing_status],
              processing_outcome: row[:processing_outcome],
            },
          )
        end
      end
    end
  end
end
