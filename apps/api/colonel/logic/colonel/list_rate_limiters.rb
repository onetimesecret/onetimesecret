# apps/api/colonel/logic/colonel/list_rate_limiters.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/ratelimit/registry'

module ColonelAPI
  module Logic
    module Colonel
      # List the known rate limiters + their subject types (Colonel).
      #
      # Thin adapter over {Onetime::Operations::RateLimit::Registry} — the single
      # source of truth the `bin/ots ratelimit` CLI also reads (ticket #44).
      # READ-ONLY: nothing mutates, so nothing is audited (CONTRACT 4). Feeds the
      # rate-limit inspect panel's limiter picker.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class ListRateLimiters < ColonelAPI::Logic::Base
        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          success_data
        end

        def success_data
          limiters = Onetime::Operations::RateLimit::Registry::LIMITERS.map do |kind, meta|
            { kind: kind, subject: meta[:subject] }
          end

          {
            record: {
              limiters: limiters,
            },
            details: {
              count: limiters.length,
            },
          }
        end
      end
    end
  end
end
