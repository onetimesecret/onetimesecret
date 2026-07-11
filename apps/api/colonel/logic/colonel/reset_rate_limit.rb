# apps/api/colonel/logic/colonel/reset_rate_limit.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/ratelimit/reset'
require 'onetime/operations/ratelimit/registry'

module ColonelAPI
  module Logic
    module Colonel
      # Reset (clear) a rate limiter's Redis state for one subject (Colonel).
      #
      # Thin adapter over {Onetime::Operations::RateLimit::Reset} — the single,
      # audited implementation whose keys the `bin/ots ratelimit keys` CLI also
      # emits as a `DEL` (ticket #44). This class keeps only the HTTP concerns
      # (param validation); the op owns the delete + the AdminAuditEvent.
      #
      # Clearing a limiter lets a throttled subject act again, so the UI gates this
      # behind an AdminConfirmDialog typed-confirmation. A reset that actually
      # removed a key records EXACTLY ONE audit event (verb `ratelimit.reset`);
      # resetting an already-clear subject is an idempotent no-op that records none.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class ResetRateLimit < ColonelAPI::Logic::Base
        attr_reader :kind, :subject, :result

        def process_params
          @kind    = params['kind'].to_s.strip
          @subject = params['subject'].to_s.strip
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          raise_form_error('Limiter kind is required', field: :kind) if kind.empty?
          raise_form_error('Subject is required', field: :subject) if subject.empty?

          unless Onetime::Operations::RateLimit::Registry.known?(kind)
            raise_not_found("Unknown rate limiter: #{kind}")
          end
        end

        def process
          @result = Onetime::Operations::RateLimit::Reset.new(
            kind: kind,
            subject: subject,
            actor: cust.extid,
          ).call

          success_data
        end

        def success_data
          {
            record: {
              kind: result.kind,
              subject: result.subject,
              cleared: result.status == :success,
            },
            details: {
              deleted: result.deleted,
              message: result.status == :success ? 'Rate limiter reset' : 'No active rate-limit state to reset',
            },
          }
        end
      end
    end
  end
end
