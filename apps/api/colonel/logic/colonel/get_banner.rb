# apps/api/colonel/logic/colonel/get_banner.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/banner'

module ColonelAPI
  module Logic
    module Colonel
      # Show the current global broadcast banner (Colonel).
      #
      # Thin adapter over {Onetime::Operations::GetBanner} — the single
      # implementation of the banner read (epic #41). Read-only: nothing mutates,
      # so nothing is audited (CONTRACT 4).
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class GetBanner < ColonelAPI::Logic::Base
        attr_reader :result

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          @result = Onetime::Operations::GetBanner.new.call
          success_data
        end

        def success_data
          {
            record: {
              content: result.content,
              ttl: result.ttl,
              active: result.active,
            },
            details: {
              key: result.key,
              database: result.database,
            },
          }
        end
      end
    end
  end
end
