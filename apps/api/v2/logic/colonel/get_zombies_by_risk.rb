# apps/api/v2/logic/colonel/get_zombies_by_risk.rb

require_relative '../base'
require_relative '../../../../lib/onetime/zombie_detection/detector'

module V2
  module Logic
    module Colonel
      ##
      # GetZombiesByRisk - Get all customers at a specific risk level
      #
      # Allows filtering customers by risk level:
      # - critical: Immediate intervention needed
      # - high: Likely zombie, re-engagement recommended
      # - medium: At-risk, should be monitored
      # - low: Minor concerns
      # - healthy: No concerns
      #
      class GetZombiesByRisk < V2::Logic::Base
        attr_reader :risk_level, :customers

        def process_params
          @risk_level = params[:risk_level]

          raise V2::Errors::InvalidInput, "risk_level is required" if @risk_level.to_s.empty?

          valid_levels = %w[critical high medium low healthy]
          unless valid_levels.include?(@risk_level)
            raise V2::Errors::InvalidInput, "risk_level must be one of: #{valid_levels.join(', ')}"
          end
        end

        def raise_concerns
          limit_action :view_colonel
        end

        def process
          get_customers_at_risk_level
        end

        def get_customers_at_risk_level
          detector = Onetime::ZombieDetection::Detector.new

          OT.info "[API] Getting customers at risk level: #{@risk_level}"

          @customers = detector.get_customers_by_risk(@risk_level)

          OT.info "[API] Found #{@customers.length} customers at #{@risk_level} risk"
        end
        private :get_customers_at_risk_level

        def success_data
          {
            record: {
              risk_level: risk_level,
              customer_count: customers.length
            },
            details: {
              customers: customers.map { |c|
                {
                  customer_id: c[:customer_id],
                  email: c[:email],
                  plan: c[:plan],
                  health_score: c[:health_score],
                  anomaly_count: c[:anomalies].length,
                  has_re_engagement_plan: !c[:re_engagement_plan].nil?
                }
              },
              full_details: customers
            }
          }
        end
      end
    end
  end
end
