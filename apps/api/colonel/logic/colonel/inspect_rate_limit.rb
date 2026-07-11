# apps/api/colonel/logic/colonel/inspect_rate_limit.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/ratelimit/inspect'

module ColonelAPI
  module Logic
    module Colonel
      # Inspect a rate limiter's current Redis state for one subject (Colonel).
      #
      # Thin adapter over {Onetime::Operations::RateLimit::Inspect} — the single
      # implementation whose keys the `bin/ots ratelimit keys` CLI also emits
      # (ticket #44). READ-ONLY: reads TTL + value for a bounded, fixed set of keys
      # (CONTRACT 6 — never an unbounded KEYS/SCAN), mutates nothing, records NO
      # AdminAuditEvent (CONTRACT 4).
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class InspectRateLimit < ColonelAPI::Logic::Base
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
          @result = Onetime::Operations::RateLimit::Inspect.new(
            kind: kind,
            subject: subject,
          ).call

          success_data
        end

        def success_data
          {
            record: {
              kind: result.kind,
              subject: result.subject,
            },
            details: {
              entries: result.entries.map do |entry|
                {
                  key: entry.key,
                  ttl: entry.ttl,
                  value: entry.value,
                  exists: entry.exists,
                }
              end,
            },
          }
        end
      end
    end
  end
end
