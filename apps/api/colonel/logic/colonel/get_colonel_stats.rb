# apps/api/account/logic/colonel/get_colonel_stats.rb
#
# frozen_string_literal: true

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      class GetColonelStats < ColonelAPI::Logic::Base
        attr_reader :session_count, :customer_count, :metadata_count,
          :secret_count, :secrets_created, :secrets_shared, :emails_sent

        def process_params
          # No parameters needed for stats endpoint
        end

        def raise_concerns; end

        def process
          process_statistics

          success_data
        end

        def process_statistics
          @customer_count = Onetime::Customer.count
          @metadata_count = Onetime::Metadata.count
          @secret_count   = Onetime::Secret.count
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
