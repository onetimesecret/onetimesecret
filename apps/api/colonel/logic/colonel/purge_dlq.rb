# apps/api/colonel/logic/colonel/purge_dlq.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/dlq/store'
require 'onetime/operations/dlq/purge'

module ColonelAPI
  module Logic
    module Colonel
      # Purge (permanently delete) a dead-letter queue (Colonel).
      #
      # Thin adapter over {Onetime::Operations::Dlq::Purge} — the single, audited
      # implementation of the DLQ purge verb (epic #42 / CONTRACT 4). This class
      # keeps only the HTTP concerns (param validation + role gate + allowlist +
      # broker-availability); the op owns the `queue.purge` mutation and the
      # AdminAuditEvent (exactly one per non-empty purge).
      #
      # Purge is irreversible message loss, so the UI gates it behind
      # AdminConfirmDialog typed-confirmation (retype the queue name) with the
      # count-in-scope shown. `dry_run` (default false) returns the count that would
      # be purged without deleting anything (no audit).
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class PurgeDlq < ColonelAPI::Logic::Base
        attr_reader :dlq_name, :result

        def process_params
          @queue    = sanitize_queue_name(params['queue'])
          @dlq_name = Onetime::Operations::Dlq::Store.resolve(@queue)
          @dry_run  = truthy?(params['dry_run'])
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          raise_form_error('Queue is required', field: :queue) if @queue.to_s.empty?
          unless Onetime::Operations::Dlq::Store.valid?(dlq_name)
            raise_not_found('Unknown dead-letter queue')
          end
          unless $rmq_conn&.open?
            raise_form_error('Message queue is not connected')
          end
        end

        def process
          # Delegate the mutation + audit to the single op implementation.
          # actor is the acting colonel's PUBLIC id (never an objid).
          @result = Onetime::Operations::Dlq::Purge.new(
            connection: $rmq_conn,
            queue: dlq_name,
            actor: cust.extid,
            dry_run: @dry_run,
          ).call

          success_data
        end

        private

        def sanitize_queue_name(value)
          value.to_s.downcase.gsub(/[^a-z0-9._-]/, '')
        end

        def truthy?(value)
          %w[1 true yes].include?(value.to_s.downcase)
        end

        def success_data
          {
            record: {
              queue: result.queue,
              count: result.count,
              purged: result.purged,
              dry_run: result.status == :dry_run,
            },
            details: {
              message: purge_message,
            },
          }
        end

        def purge_message
          case result.status
          when :dry_run then "#{result.count} message(s) would be purged"
          when :empty then 'No messages to purge'
          else "Purged #{result.purged} message(s)"
          end
        end
      end
    end
  end
end
