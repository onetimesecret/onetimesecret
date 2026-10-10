# apps/api/colonel/logic/colonel/replay_dlq_message.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative 'dlq_message_target'
require 'onetime/operations/dlq/store'
require 'onetime/operations/dlq/replay'

module ColonelAPI
  module Logic
    module Colonel
      # Replay ONE dead-lettered message back to its original queue (Colonel,
      # #4343).
      #
      # Thin adapter over {Onetime::Operations::Dlq::Replay} with `message_id:`
      # — the same audited op as the bulk ReplayDlq, which owns the bounded
      # scan, the republish/ack transaction, the email DLQ consumer's
      # reservation and the ColonelAuditEvent. A miss is HTTP 200 with
      # `outcome: 'not_visible'` (see {DlqMessageTarget}).
      #
      # TIER 2, like ReplayDlq: replay re-triggers side effects (emails,
      # webhooks) but destroys nothing. `dry_run` (default false) previews
      # without the confirmation gate.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class ReplayDlqMessage < ColonelAPI::Logic::Base
        include DlqMessageTarget

        SCHEMAS = { response: 'colonelDlqMessageReplay' }.freeze

        attr_reader :result

        def process_params
          read_dlq_message_target
          @dry_run = truthy?(params['dry_run'])
          # OPTIONAL operator-supplied why (#4338), threaded onto the preview
          # observation too.
          @reason  = operator_reason_param
        end

        def raise_concerns
          verify_dlq_message_target!

          # PREVIEW EXEMPTION (#4326): a dry run finds, it does not republish.
          return if @dry_run

          # TIER 2. Same token as the queue-level replay: the queue name. A
          # message id is a UUID nobody can retype, and it adds no proof
          # (decision 9).
          guard_destructive_action!(
            tier: :sensitive,
            confirm_with: queue,
            confirm_subject: 'the queue name',
            field: :queue,
          )
        end

        def process
          # actor is the acting colonel's PUBLIC id (never an objid).
          @result = Onetime::Operations::Dlq::Replay.new(
            connection: $rmq_conn, # rubocop:disable Style/GlobalVars
            queue: dlq_name,
            message_id: message_id,
            actor: cust.extid,
            dry_run: @dry_run,
            reason: @reason,
          ).call

          success_data
        end

        private

        def success_data
          {
            record: dlq_message_scan_record(
              found: result.found,
              outcome: result.outcome,
              scanned: result.scanned,
              truncated: result.truncated,
            ).merge(
              replayed: result.replayed,
              failed: result.failed,
              would_replay: result.would_replay,
              dry_run: @dry_run,
            ),
            details: {
              message: replay_text,
              errors: result.errors,
            },
          }
        end

        def replay_text
          case result.status
          when :dry_run then '1 message would be replayed'
          when :not_visible then not_visible_text(result.scanned, result.truncated)
          when :refused then result.errors.first&.fetch(:error, nil) || "Not replayed (#{result.outcome})"
          else result.replayed.positive? ? 'Replayed message' : 'Replay failed'
          end
        end
      end
    end
  end
end
