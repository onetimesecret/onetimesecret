# apps/api/colonel/logic/colonel/ingest_email_deliverability_events.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/email/ingest_feedback'

module ColonelAPI
  module Logic
    module Colonel
      # Ingest ESP deliverability feedback (Colonel).
      #
      # Thin adapter over {Onetime::Operations::Email::IngestFeedback} — the
      # single, audited implementation of the feedback-ingest verb. This class
      # keeps only the HTTP concerns (payload shape validation + the batch
      # cap); the op owns validation of individual records, the model writes,
      # and the one-per-batch AdminAuditEvent (CONTRACT 4).
      #
      # ## Intended flow
      #
      # This is deliberately NOT a public webhook: an unauthenticated bounce
      # receiver would let anyone suppress a victim's address. ESP feedback is
      # piped in by an operator-controlled relay (CLI/cron) that authenticates
      # as a colonel and POSTs normalized records:
      #
      #   POST /api/colonel/email/deliverability/events
      #   {
      #     "source": "ses",                        // optional batch default
      #     "events": [
      #       { "email": "a@example.com", "kind": "bounce",    "reason": "550 5.1.1 user unknown" },
      #       { "email": "b@example.com", "kind": "complaint" },
      #       { "email": "c@example.com", "kind": "suppression" }  // import-only, no feed event
      #     ]
      #   }
      #
      # bounce/complaint records land in the event feed AND suppress the
      # address; 'suppression' records import an address onto the list
      # (reason 'manual') without a feed event. Malformed records are counted
      # and described in the response, never fatal to the batch.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class IngestEmailDeliverabilityEvents < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelEmailDeliverabilityIngest' }.freeze

        attr_reader :raw_events, :default_source, :result

        def process_params
          @raw_events     = params['events']
          @default_source = sanitize_plain_text(params['source'], max_length: 64) if params['source']
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          unless raw_events.is_a?(Array) && !raw_events.empty?
            raise_form_error('events must be a non-empty array', field: :events)
          end

          max = Onetime::Operations::Email::IngestFeedback::MAX_BATCH
          if raw_events.size > max
            raise_form_error("events batch too large (max #{max})", field: :events)
          end
        end

        def process
          @result = Onetime::Operations::Email::IngestFeedback.new(
            records: raw_events,
            actor: cust.extid,
            default_source: default_source,
          ).call

          success_data
        end

        def success_data
          {
            record: {
              accepted: result.accepted,
              rejected: result.rejected,
            },
            details: {
              errors: result.errors,
            },
          }
        end
      end
    end
  end
end
