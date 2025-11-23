require 'onetime'
require_relative 'anomaly_detector'
require_relative 'health_scorer'
require_relative 're_engagement_workflow'
require_relative 'churn_calculator'

module Onetime
  module ZombieDetection
    ##
    # Detector - Main orchestrator for zombie subscription detection
    #
    # This class coordinates all zombie detection components:
    # - Identifies zombie customers using anomaly detection
    # - Calculates health scores
    # - Generates re-engagement recommendations
    # - Provides aggregate metrics and insights
    #
    class Detector
      attr_reader :options

      ##
      # Initialize detector with options
      #
      # @param options [Hash] Configuration options
      # @option options [Integer] :min_subscription_age_days Minimum subscription age to analyze (default: 30)
      # @option options [Integer] :health_score_threshold Threshold for zombie classification (default: 70)
      # @option options [Boolean] :paid_only Only analyze paid subscriptions (default: true)
      #
      def initialize(options = {})
        @options = {
          min_subscription_age_days: 30,
          health_score_threshold: 70,
          paid_only: true
        }.merge(options)
      end

      ##
      # Scan all customers and identify zombies
      #
      # @return [Hash] Detection results with zombie list and aggregate metrics
      #
      def scan_all_customers
        customers = eligible_customers
        results = []

        OT.info "[ZombieDetection] Scanning #{customers.length} customers..."

        customers.each_with_index do |customer, index|
          begin
            result = analyze_customer(customer)
            results << result if result[:is_zombie]

            # Progress logging every 100 customers
            if (index + 1) % 100 == 0
              OT.info "[ZombieDetection] Processed #{index + 1}/#{customers.length} customers"
            end
          rescue => e
            OT.le "[ZombieDetection] Error analyzing customer #{customer.custid}: #{e.message}"
          end
        end

        OT.info "[ZombieDetection] Scan complete. Found #{results.length} zombie subscriptions."

        {
          scanned_at: Time.now.to_i,
          total_customers_scanned: customers.length,
          zombies_detected: results.length,
          zombie_percentage: customers.length > 0 ? ((results.length.to_f / customers.length) * 100).round(2) : 0,
          zombies: results,
          aggregate_metrics: calculate_aggregate_metrics(results),
          risk_distribution: calculate_risk_distribution(results)
        }
      end

      ##
      # Analyze a specific customer
      #
      # @param customer [V2::Customer] Customer to analyze
      # @return [Hash] Analysis results
      #
      def analyze_customer(customer)
        # Run anomaly detection
        anomaly_detector = AnomalyDetector.new(customer)
        detection_result = anomaly_detector.detect

        # Get health score breakdown
        health_scorer = HealthScorer.new(customer)
        health_breakdown = health_scorer.breakdown

        # Generate re-engagement plan if zombie
        re_engagement_plan = nil
        if detection_result[:is_zombie]
          workflow = ReEngagementWorkflow.new(
            customer,
            detection_result[:health_score],
            detection_result[:risk_level]
          )
          re_engagement_plan = workflow.plan
        end

        {
          customer_id: customer.custid,
          email: customer.email,
          plan: customer.planid,
          is_zombie: detection_result[:is_zombie],
          health_score: detection_result[:health_score],
          risk_level: detection_result[:risk_level],
          anomalies: detection_result[:anomalies],
          health_breakdown: health_breakdown,
          re_engagement_plan: re_engagement_plan,
          detected_at: detection_result[:detected_at]
        }
      end

      ##
      # Get customers at specific risk level
      #
      # @param risk_level [String] Risk level: healthy, low, medium, high, critical
      # @return [Array<Hash>] Customers at this risk level
      #
      def get_customers_by_risk(risk_level)
        customers = eligible_customers
        results = []

        customers.each do |customer|
          begin
            analysis = analyze_customer(customer)
            results << analysis if analysis[:risk_level] == risk_level
          rescue => e
            OT.le "[ZombieDetection] Error analyzing customer #{customer.custid}: #{e.message}"
          end
        end

        results
      end

      ##
      # Calculate revenue at risk from zombie subscriptions
      #
      # @param zombie_results [Array<Hash>] Results from scan_all_customers
      # @return [Hash] Revenue impact analysis
      #
      def calculate_revenue_impact(zombie_results = nil)
        zombie_results ||= scan_all_customers[:zombies]

        revenue_by_plan = {
          'basic' => 3.0,
          'identity' => 12.0
        }

        total_mrr_at_risk = 0
        breakdown_by_plan = Hash.new { |h, k| h[k] = { count: 0, mrr: 0 } }
        breakdown_by_risk = Hash.new { |h, k| h[k] = { count: 0, mrr: 0 } }

        zombie_results.each do |zombie|
          plan = zombie[:plan].to_s
          risk = zombie[:risk_level]
          mrr = revenue_by_plan[plan] || 0

          total_mrr_at_risk += mrr

          breakdown_by_plan[plan][:count] += 1
          breakdown_by_plan[plan][:mrr] += mrr

          breakdown_by_risk[risk][:count] += 1
          breakdown_by_risk[risk][:mrr] += mrr
        end

        {
          total_zombies: zombie_results.length,
          total_mrr_at_risk: total_mrr_at_risk.round(2),
          annual_revenue_at_risk: (total_mrr_at_risk * 12).round(2),
          breakdown_by_plan: breakdown_by_plan,
          breakdown_by_risk: breakdown_by_risk,
          prevention_scenarios: calculate_prevention_scenarios(total_mrr_at_risk)
        }
      end

      ##
      # Generate actionable recommendations based on scan results
      #
      # @param scan_results [Hash] Results from scan_all_customers
      # @return [Hash] Prioritized recommendations
      #
      def generate_recommendations(scan_results)
        zombies = scan_results[:zombies]
        zombie_pct = scan_results[:zombie_percentage]

        recommendations = []

        # High-level strategy
        if zombie_pct > 20
          recommendations << {
            priority: 'critical',
            category: 'strategy',
            action: 'Implement automated zombie detection and re-engagement system',
            impact: 'High revenue recovery potential',
            effort: 'Medium'
          }
        end

        # Immediate actions by risk level
        critical_zombies = zombies.select { |z| z[:risk_level] == 'critical' }
        high_risk_zombies = zombies.select { |z| z[:risk_level] == 'high' }

        if critical_zombies.any?
          recommendations << {
            priority: 'urgent',
            category: 'engagement',
            action: "Immediately engage #{critical_zombies.length} critical risk customers",
            impact: "Prevent imminent churn",
            effort: 'Low',
            customer_count: critical_zombies.length
          }
        end

        if high_risk_zombies.any?
          recommendations << {
            priority: 'high',
            category: 'engagement',
            action: "Launch re-engagement campaign for #{high_risk_zombies.length} high-risk customers",
            impact: "Reduce zombie churn rate",
            effort: 'Medium',
            customer_count: high_risk_zombies.length
          }
        end

        # Revenue-focused recommendations
        revenue_impact = calculate_revenue_impact(zombies)
        if revenue_impact[:total_mrr_at_risk] > 100
          recommendations << {
            priority: 'high',
            category: 'revenue',
            action: "Prioritize retention efforts - $#{revenue_impact[:total_mrr_at_risk]}/month at risk",
            impact: "Up to $#{revenue_impact[:prevention_scenarios][:optimistic_75pct]} annual revenue saved",
            effort: 'Medium'
          }
        end

        # Product improvements
        common_anomalies = find_common_anomaly_patterns(zombies)
        if common_anomalies.any?
          recommendations << {
            priority: 'medium',
            category: 'product',
            action: "Address common issues: #{common_anomalies.join(', ')}",
            impact: "Improve product stickiness",
            effort: 'High'
          }
        end

        {
          total_recommendations: recommendations.length,
          recommendations: recommendations.sort_by { |r|
            { 'urgent' => 0, 'critical' => 1, 'high' => 2, 'medium' => 3, 'low' => 4 }[r[:priority]]
          }
        }
      end

      private

      ##
      # Get eligible customers for zombie detection
      #
      def eligible_customers
        all_customers = V2::Customer.values

        # Filter based on options
        customers = all_customers.select do |customer|
          next false if customer.custid == 'GLOBAL'  # Skip global stats customer

          # Check if paid plan (if required)
          if @options[:paid_only]
            plan = customer.planid.to_s
            next false if plan.empty? || plan == 'anonymous'
          end

          # Check minimum subscription age
          subscription_age_days = ((Time.now.to_i - customer.created.to_i) / 86400.0).round
          next false if subscription_age_days < @options[:min_subscription_age_days]

          true
        end

        OT.info "[ZombieDetection] Filtered to #{customers.length} eligible customers from #{all_customers.length} total"
        customers
      end

      ##
      # Calculate aggregate metrics from zombie results
      #
      def calculate_aggregate_metrics(zombie_results)
        return {} if zombie_results.empty?

        {
          avg_health_score: (zombie_results.sum { |z| z[:health_score] }.to_f / zombie_results.length).round(2),
          avg_anomalies_per_zombie: (zombie_results.sum { |z| z[:anomalies].length }.to_f / zombie_results.length).round(2),
          most_common_anomaly_types: find_common_anomaly_types(zombie_results),
          plans_affected: zombie_results.group_by { |z| z[:plan] }.transform_values(&:count)
        }
      end

      ##
      # Calculate risk distribution
      #
      def calculate_risk_distribution(zombie_results)
        distribution = zombie_results.group_by { |z| z[:risk_level] }.transform_values(&:count)

        {
          critical: distribution['critical'] || 0,
          high: distribution['high'] || 0,
          medium: distribution['medium'] || 0,
          low: distribution['low'] || 0,
          healthy: distribution['healthy'] || 0
        }
      end

      ##
      # Find most common anomaly types
      #
      def find_common_anomaly_types(zombie_results)
        anomaly_counts = Hash.new(0)

        zombie_results.each do |zombie|
          zombie[:anomalies].each do |anomaly|
            anomaly_counts[anomaly[:type]] += 1
          end
        end

        anomaly_counts.sort_by { |_, count| -count }.to_h
      end

      ##
      # Find common patterns in anomalies
      #
      def find_common_anomaly_patterns(zombie_results)
        anomaly_types = find_common_anomaly_types(zombie_results)
        top_patterns = anomaly_types.take(3).map { |type, _| type.to_s.gsub('_', ' ') }
        top_patterns
      end

      ##
      # Calculate prevention scenarios
      #
      def calculate_prevention_scenarios(total_mrr_at_risk)
        {
          conservative_50pct: (total_mrr_at_risk * 0.5 * 12).round(2),
          optimistic_75pct: (total_mrr_at_risk * 0.75 * 12).round(2),
          ideal_90pct: (total_mrr_at_risk * 0.9 * 12).round(2)
        }
      end
    end
  end
end
