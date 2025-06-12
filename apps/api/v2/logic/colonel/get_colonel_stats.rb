# apps/api/v2/logic/colonel/get_colonel_stats.rb

require_relative '../base'

module V2
  module Logic
    module Colonel
      class GetColonelStats < V2::Logic::Base
        attr_reader :session_count, :customer_count, :metadata_count,
          :secret_count, :secrets_created, :secrets_shared, :emails_sent

        def process_params
          # No parameters needed for stats endpoint
        end

        def raise_concerns
          limit_action :view_colonel
        end

        def process
          process_statistics
        end

        def process_statistics
          @session_count = V2::Session.recent(15.minutes).size
          @customer_count = V2::Customer.values.size
          @metadata_count = V2::Metadata.new.redis.keys('metadata*:object').count
          @secret_count = V2::Secret.new.redis.keys('secret*:object').count
          @secrets_created = V2::Customer.global.secrets_created.to_s
          @secrets_shared = V2::Customer.global.secrets_shared.to_s
          @emails_sent = V2::Customer.global.emails_sent.to_s
        end
        private :process_statistics

        def success_data
          {
            record: {},
            details: {
              counts: {
                session_count: session_count,
                customer_count: customer_count,
                metadata_count: metadata_count,
                secret_count: secret_count,
                secrets_created: secrets_created,
                secrets_shared: secrets_shared,
                emails_sent: emails_sent,
              },
            },
          }
        end
      end
    end
  end
end
