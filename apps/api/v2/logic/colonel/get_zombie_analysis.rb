# apps/api/v2/logic/colonel/get_zombie_analysis.rb

require_relative '../base'
require_relative '../../../../lib/onetime/zombie_detection/detector'

module V2
  module Logic
    module Colonel
      ##
      # GetZombieAnalysis - Scan for zombie subscriptions and return analysis
      #
      # This endpoint provides comprehensive zombie subscription detection:
      # - Identifies inactive paying customers
      # - Calculates health scores
      # - Provides revenue impact analysis
      # - Generates actionable recommendations
      #
      class GetZombieAnalysis < V2::Logic::Base
        attr_reader :scan_results, :revenue_impact, :recommendations

        def process_params
          # No parameters needed, runs full scan
        end

        def raise_concerns
          limit_action :view_colonel
        end

        def process
          perform_zombie_scan
        end

        def perform_zombie_scan
          detector = Onetime::ZombieDetection::Detector.new(
            min_subscription_age_days: 30,
            health_score_threshold: 70,
            paid_only: true
          )

          OT.info "[API] Running zombie detection scan..."

          @scan_results = detector.scan_all_customers
          @revenue_impact = detector.calculate_revenue_impact(@scan_results[:zombies])
          @recommendations = detector.generate_recommendations(@scan_results)

          OT.info "[API] Zombie scan complete: #{@scan_results[:zombies_detected]} zombies detected"
        end
        private :perform_zombie_scan

        def success_data
          {
            record: {
              scan_metadata: {
                scanned_at: scan_results[:scanned_at],
                total_customers_scanned: scan_results[:total_customers_scanned]
              },
              summary: {
                zombies_detected: scan_results[:zombies_detected],
                zombie_percentage: scan_results[:zombie_percentage],
                total_mrr_at_risk: revenue_impact[:total_mrr_at_risk],
                annual_revenue_at_risk: revenue_impact[:annual_revenue_at_risk]
              },
              risk_distribution: scan_results[:risk_distribution],
              aggregate_metrics: scan_results[:aggregate_metrics]
            },
            details: {
              zombies: scan_results[:zombies],
              revenue_impact: revenue_impact,
              recommendations: recommendations
            }
          }
        end
      end
    end
  end
end
