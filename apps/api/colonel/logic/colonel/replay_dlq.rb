# apps/api/colonel/logic/colonel/replay_dlq.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/dlq/store'
require 'onetime/operations/dlq/replay'

module ColonelAPI
  module Logic
    module Colonel
      # Replay (re-enqueue) a dead-letter queue back to its original queue (Colonel).
      #
      # Thin adapter over {Onetime::Operations::Dlq::Replay} — the single, audited
      # implementation of the DLQ replay verb (epic #42 / CONTRACT 4). This class
      # keeps only the HTTP concerns (param validation + role gate + allowlist +
      # broker-availability); the op owns the republish/ack/nack loop and the
      # AdminAuditEvent (exactly one per replay that processes ≥ 1 message).
      #
      # Replay can re-trigger side effects (emails, webhooks), so the UI gates it
      # behind an explicit confirm dialog. `dry_run` (default false) is honoured so
      # a caller may preview the in-scope count without republishing.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class ReplayDlq < ColonelAPI::Logic::Base
        attr_reader :dlq_name, :result

        def process_params
          @queue    = sanitize_queue_name(params['queue'])
          @dlq_name = Onetime::Operations::Dlq::Store.resolve(@queue)
          @count    = params['count'].to_i if params['count']
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
          @result = Onetime::Operations::Dlq::Replay.new(
            connection: $rmq_conn,
            queue: dlq_name,
            count: @count,
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
              replayed: result.replayed,
              failed: result.failed,
              would_replay: result.would_replay,
              dry_run: result.status == :dry_run,
            },
            details: {
              message: replay_message,
              errors: result.errors,
            },
          }
        end

        def replay_message
          case result.status
          when :dry_run then "#{result.would_replay} message(s) would be replayed"
          when :empty, :noop then 'No messages to replay'
          else "Replayed #{result.replayed} message(s), #{result.failed} failed"
          end
        end
      end
    end
  end
end
