# apps/api/colonel/logic/colonel/get_dlq_message.rb
#
# frozen_string_literal: true

require 'bunny'
require_relative '../base'
require_relative 'dlq_message_target'
require 'onetime/operations/dlq/store'
require 'onetime/operations/dlq/show'

module ColonelAPI
  module Logic
    module Colonel
      # Inspect one dead-lettered message by id (Colonel, #4343).
      #
      # Thin adapter over {Onetime::Operations::Dlq::Show}: a bounded,
      # read-only scan that leaves the queue as it found it. Returns the full
      # message (headers, death info, parsed payload) on a hit, and
      # `found: false, outcome: 'not_visible'` with HTTP 200 on a miss (see
      # {DlqMessageTarget}).
      #
      # Unlike the peek (GetDlqMessages, a 200-character preview, no audit),
      # this returns the whole payload, which on `dlq.email.message` carries a
      # customer's email address. A hit therefore records ONE access
      # observation (`queue.dlq.inspect`), the rule the colonel applies to
      # other detail read-outs (GetSessionDetail, GetSecretReceipt). A miss
      # exposed nothing and records nothing.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class GetDlqMessage < ColonelAPI::Logic::Base
        include DlqMessageTarget

        SCHEMAS = { response: 'colonelDlqMessageDetail' }.freeze

        AUDIT_VERB = 'queue.dlq.inspect'

        attr_reader :result

        def process_params
          read_dlq_message_target
        end

        def raise_concerns
          verify_dlq_message_target!
        end

        def process
          @result = show_result
          record_access_event if result.found

          success_data
        end

        private

        # A configured queue not yet declared on the broker is a miss, as in
        # GetDlqMessages.
        def show_result
          Onetime::Operations::Dlq::Show.new(
            connection: $rmq_conn, # rubocop:disable Style/GlobalVars
            queue: dlq_name,
            message_id: message_id,
          ).call
        rescue Bunny::NotFound
          Onetime::Operations::Dlq::Show::Result.new(
            found: false, empty: true, message: nil, scanned: 0, truncated: false,
          )
        end

        # The queue and message id only; never payload contents.
        def record_access_event
          Onetime::ColonelAuditEvent.record_access(
            actor: cust&.extid,
            verb: AUDIT_VERB,
            target: dlq_name,
            result: :success,
            detail: { message_id: message_id },
          )
        end

        def success_data
          {
            record: dlq_message_scan_record(
              found: result.found,
              outcome: result.found ? nil : Onetime::Operations::Dlq::Store::NOT_VISIBLE,
              scanned: result.scanned,
              truncated: result.truncated,
            ),
            details: {
              message: result.message,
            },
          }
        end
      end
    end
  end
end
