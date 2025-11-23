# apps/api/v2/logic/colonel/get_customer_health.rb

require_relative '../base'
require_relative '../../../../lib/onetime/zombie_detection/detector'

module V2
  module Logic
    module Colonel
      ##
      # GetCustomerHealth - Analyze health and zombie status of a specific customer
      #
      # Provides detailed health analysis including:
      # - Health score breakdown
      # - Anomaly detection results
      # - Re-engagement recommendations
      # - Detailed usage metrics
      #
      class GetCustomerHealth < V2::Logic::Base
        attr_reader :customer_id, :analysis_result

        def process_params
          @customer_id = params[:customer_id] || params[:custid]

          raise V2::Errors::InvalidInput, "customer_id is required" if @customer_id.to_s.empty?
        end

        def raise_concerns
          limit_action :view_colonel
        end

        def process
          analyze_customer_health
        end

        def analyze_customer_health
          customer = V2::Customer.load(@customer_id)

          unless customer
            raise V2::Errors::NotFound, "Customer not found: #{@customer_id}"
          end

          detector = Onetime::ZombieDetection::Detector.new

          OT.info "[API] Analyzing customer health: #{@customer_id}"

          @analysis_result = detector.analyze_customer(customer)

          OT.info "[API] Customer #{@customer_id} health score: #{@analysis_result[:health_score]}"
        end
        private :analyze_customer_health

        def success_data
          {
            record: {
              customer_id: analysis_result[:customer_id],
              email: analysis_result[:email],
              plan: analysis_result[:plan],
              is_zombie: analysis_result[:is_zombie],
              health_score: analysis_result[:health_score],
              risk_level: analysis_result[:risk_level]
            },
            details: {
              anomalies: analysis_result[:anomalies],
              health_breakdown: analysis_result[:health_breakdown],
              re_engagement_plan: analysis_result[:re_engagement_plan]
            }
          }
        end
      end
    end
  end
end
