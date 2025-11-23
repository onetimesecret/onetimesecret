# apps/api/account/logic/colonel/get_redis_metrics.rb
#
# frozen_string_literal: true

require_relative '../base'

module AccountAPI
  module Logic
    module Colonel
      class GetRedisMetrics < AccountAPI::Logic::Base
        attr_reader :redis_full_info

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          # Get full Redis INFO
          @redis_full_info = Familia.dbclient.info

          success_data
        end

        def success_data
          {
            record: {},
            details: {
              redis_info: redis_full_info,
              timestamp: Familia.now.to_i,
              timestamp_human: natural_time(Familia.now.to_i),
            },
          }
        end
      end
    end
  end
end
