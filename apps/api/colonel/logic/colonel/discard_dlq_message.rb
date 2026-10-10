# apps/api/colonel/logic/colonel/discard_dlq_message.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative 'dlq_message_target'
require 'onetime/operations/dlq/store'
require 'onetime/operations/dlq/discard'

module ColonelAPI
  module Logic
    module Colonel
      # Discard (permanently drop) ONE dead-lettered message (Colonel, #4343).
      #
      # Thin adapter over {Onetime::Operations::Dlq::Discard}, which owns the
      # bounded scan, the confirmed ack and the fail-closed ColonelAuditEvent.
      # A miss is HTTP 200 with `outcome: 'not_visible'` (see
      # {DlqMessageTarget}).
      #
      # TIER 1, the single-message twin of PurgeDlq: irreversible message loss.
      # Same gate and token (the queue name), same tight budget charged last.
      # `dry_run` (default false) previews without the gate.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class DiscardDlqMessage < ColonelAPI::Logic::Base
        include DlqMessageTarget

        SCHEMAS = { response: 'colonelDlqMessageDiscard' }.freeze

        attr_reader :result

        def process_params
          read_dlq_message_target
          @dry_run = truthy?(params['dry_run'])
          # OPTIONAL operator-supplied why (#4338), threaded onto the preview
          # observation too.
          @reason  = operator_reason_param
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
          verify_dlq_message_target!

          # PREVIEW EXEMPTION (#4326): a dry run finds, it does not drop.
          return if @dry_run

          # TIER 1. As PurgeDlq, the token is the queue name: a message id is a
          # UUID nobody can retype, and it adds no proof (decision 9).
          guard_destructive_action!(
            tier: :destructive,
            confirm_with: queue,
            confirm_subject: 'the queue name',
            field: :queue,
          )
          charge_destructive_budget!
        end

        def process
          # actor is the acting colonel's PUBLIC id (never an objid).
          @result = Onetime::Operations::Dlq::Discard.new(
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
              discarded: result.status == :success,
              original_queue: result.original_queue,
              dry_run: @dry_run,
            ),
            details: {
              message: discard_text,
            },
          }
        end

        def discard_text
          case result.status
          when :dry_run then '1 message would be discarded'
          when :not_visible then not_visible_text(result.scanned, result.truncated)
          when :unconfirmed then result.error
          else 'Discarded message'
          end
        end
      end
    end
  end
end
