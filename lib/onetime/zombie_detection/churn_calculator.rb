require 'onetime'

module Onetime
  module ZombieDetection
    ##
    # ChurnCalculator - Analyzes and categorizes churn into true vs zombie churn
    #
    # This class helps differentiate between:
    #
    # **True Churn**: Customers who actively used the service but decided to cancel
    # - Had consistent usage patterns
    # - Made informed decision to leave
    # - May have switched to competitor or no longer need the service
    #
    # **Zombie Churn**: Customers who were paying but not using the service
    # - Little to no usage despite active subscription
    # - Often forgot they had a subscription
    # - Preventable through engagement and proactive outreach
    #
    # This distinction is critical for:
    # - Understanding true product-market fit issues vs engagement issues
    # - Calculating preventable churn rate
    # - Prioritizing retention efforts
    # - Measuring impact of re-engagement campaigns
    #
    class ChurnCalculator
      # Thresholds for categorizing churn
      ZOMBIE_CHURN_CRITERIA = {
        max_health_score: 40,              # Health score below 40 at cancellation
        max_secrets_per_month: 2,          # Less than 2 secrets/month average
        min_inactivity_days: 45,           # 45+ days inactive before cancel
        max_lifetime_secrets: 10           # Less than 10 total secrets created
      }.freeze

      attr_reader :analysis_period_days

      ##
      # Initialize calculator
      #
      # @param analysis_period_days [Integer] Period to analyze (default: 90 days)
      #
      def initialize(analysis_period_days = 90)
        @analysis_period_days = analysis_period_days
      end

      ##
      # Analyze churn for a specific cancelled customer
      #
      # @param customer [V2::Customer] The cancelled customer
      # @param cancellation_date [Integer] Unix timestamp of cancellation
      # @return [Hash] Churn analysis
      #
      def analyze_customer_churn(customer, cancellation_date = nil)
        cancellation_date ||= Time.now.to_i

        # Calculate metrics at time of cancellation
        subscription_duration = cancellation_date - customer.created.to_i
        subscription_days = (subscription_duration / 86400.0).round

        total_secrets = customer.secrets_created.to_i
        secrets_per_month = total_secrets.to_f / [subscription_days / 30.0, 1].max

        last_activity = customer.last_login.to_i
        days_inactive = last_activity > 0 ? ((cancellation_date - last_activity) / 86400.0).round : subscription_days

        # Calculate health score at cancellation
        health_scorer = HealthScorer.new(customer)
        health_score = health_scorer.calculate

        # Determine churn type
        churn_type = categorize_churn(
          health_score: health_score,
          secrets_per_month: secrets_per_month,
          days_inactive: days_inactive,
          total_secrets: total_secrets,
          subscription_days: subscription_days
        )

        {
          customer_id: customer.custid,
          email: customer.email,
          churn_type: churn_type[:type],
          churn_category: churn_type[:category],
          preventable: churn_type[:preventable],
          confidence: churn_type[:confidence],
          metrics: {
            health_score: health_score,
            subscription_days: subscription_days,
            total_secrets_created: total_secrets,
            secrets_per_month: secrets_per_month.round(2),
            days_inactive_at_cancel: days_inactive,
            last_activity_date: last_activity
          },
          indicators: churn_type[:indicators],
          estimated_revenue_impact: calculate_revenue_impact(customer, subscription_days)
        }
      end

      ##
      # Analyze aggregate churn metrics across multiple customers
      #
      # @param cancelled_customers [Array<Hash>] Array of customer churn analyses
      # @return [Hash] Aggregate churn metrics
      #
      def aggregate_churn_analysis(cancelled_customers)
        return empty_aggregate if cancelled_customers.empty?

        total = cancelled_customers.length
        zombie_churns = cancelled_customers.select { |c| c[:churn_category] == 'zombie' }
        true_churns = cancelled_customers.select { |c| c[:churn_category] == 'true' }

        zombie_count = zombie_churns.length
        true_count = true_churns.length

        {
          analysis_period_days: @analysis_period_days,
          total_churned_customers: total,
          zombie_churn: {
            count: zombie_count,
            percentage: ((zombie_count.to_f / total) * 100).round(2),
            avg_health_score: avg_metric(zombie_churns, :health_score),
            avg_secrets_created: avg_metric(zombie_churns, :total_secrets_created),
            avg_days_inactive: avg_metric(zombie_churns, :days_inactive_at_cancel),
            total_preventable_revenue: zombie_churns.sum { |c| c[:estimated_revenue_impact][:monthly_value] }
          },
          true_churn: {
            count: true_count,
            percentage: ((true_count.to_f / total) * 100).round(2),
            avg_health_score: avg_metric(true_churns, :health_score),
            avg_secrets_created: avg_metric(true_churns, :total_secrets_created),
            avg_days_inactive: avg_metric(true_churns, :days_inactive_at_cancel)
          },
          preventable_churn_rate: ((zombie_count.to_f / total) * 100).round(2),
          insights: generate_insights(zombie_churns, true_churns, total)
        }
      end

      ##
      # Calculate potential revenue impact from preventing zombie churn
      #
      # @param current_churn_rate [Float] Current monthly churn rate (e.g., 7.0 for 7%)
      # @param zombie_percentage [Float] Percentage of churn that's zombie (from aggregate analysis)
      # @param avg_monthly_revenue [Float] Average monthly revenue per customer
      # @param total_customers [Integer] Total active customers
      # @return [Hash] Revenue impact calculations
      #
      def calculate_zombie_prevention_impact(current_churn_rate, zombie_percentage, avg_monthly_revenue, total_customers)
        # Current monthly churn
        monthly_churning_customers = (total_customers * (current_churn_rate / 100.0)).round

        # Zombie churn
        monthly_zombie_churn = (monthly_churning_customers * (zombie_percentage / 100.0)).round

        # If we prevent 50% of zombie churn (realistic target)
        preventable_zombies_50pct = (monthly_zombie_churn * 0.5).round
        preventable_zombies_75pct = (monthly_zombie_churn * 0.75).round
        preventable_zombies_90pct = (monthly_zombie_churn * 0.9).round

        # Revenue impact
        monthly_revenue_at_risk = monthly_zombie_churn * avg_monthly_revenue
        annual_revenue_at_risk = monthly_revenue_at_risk * 12

        {
          current_state: {
            total_customers: total_customers,
            monthly_churn_rate: current_churn_rate,
            monthly_churning_customers: monthly_churning_customers,
            monthly_zombie_churn: monthly_zombie_churn,
            monthly_revenue_lost_to_zombies: monthly_revenue_at_risk.round(2),
            annual_revenue_lost_to_zombies: annual_revenue_at_risk.round(2)
          },
          prevention_scenarios: {
            conservative_50pct: {
              customers_saved: preventable_zombies_50pct,
              monthly_revenue_saved: (preventable_zombies_50pct * avg_monthly_revenue).round(2),
              annual_revenue_saved: (preventable_zombies_50pct * avg_monthly_revenue * 12).round(2),
              new_churn_rate: ((monthly_churning_customers - preventable_zombies_50pct).to_f / total_customers * 100).round(2)
            },
            optimistic_75pct: {
              customers_saved: preventable_zombies_75pct,
              monthly_revenue_saved: (preventable_zombies_75pct * avg_monthly_revenue).round(2),
              annual_revenue_saved: (preventable_zombies_75pct * avg_monthly_revenue * 12).round(2),
              new_churn_rate: ((monthly_churning_customers - preventable_zombies_75pct).to_f / total_customers * 100).round(2)
            },
            ideal_90pct: {
              customers_saved: preventable_zombies_90pct,
              monthly_revenue_saved: (preventable_zombies_90pct * avg_monthly_revenue).round(2),
              annual_revenue_saved: (preventable_zombies_90pct * avg_monthly_revenue * 12).round(2),
              new_churn_rate: ((monthly_churning_customers - preventable_zombies_90pct).to_f / total_customers * 100).round(2)
            }
          },
          recommendations: generate_revenue_recommendations(zombie_percentage, monthly_revenue_at_risk)
        }
      end

      private

      ##
      # Categorize churn as zombie or true churn
      #
      def categorize_churn(health_score:, secrets_per_month:, days_inactive:, total_secrets:, subscription_days:)
        indicators = []
        zombie_signals = 0
        true_churn_signals = 0

        # Check zombie indicators
        if health_score < ZOMBIE_CHURN_CRITERIA[:max_health_score]
          indicators << "Low health score (#{health_score})"
          zombie_signals += 2
        end

        if secrets_per_month < ZOMBIE_CHURN_CRITERIA[:max_secrets_per_month]
          indicators << "Minimal usage (#{secrets_per_month.round(2)} secrets/month)"
          zombie_signals += 2
        end

        if days_inactive >= ZOMBIE_CHURN_CRITERIA[:min_inactivity_days]
          indicators << "Long inactivity period (#{days_inactive} days)"
          zombie_signals += 2
        end

        if total_secrets < ZOMBIE_CHURN_CRITERIA[:max_lifetime_secrets]
          indicators << "Very low lifetime usage (#{total_secrets} total secrets)"
          zombie_signals += 1
        end

        # Check true churn indicators
        if health_score >= 70
          indicators << "High health score at cancellation (#{health_score})"
          true_churn_signals += 2
        end

        if secrets_per_month >= 10
          indicators << "Active usage pattern (#{secrets_per_month.round(2)} secrets/month)"
          true_churn_signals += 2
        end

        if days_inactive < 7
          indicators << "Recently active (#{days_inactive} days since last use)"
          true_churn_signals += 1
        end

        # Determine category
        if zombie_signals >= 4
          category = 'zombie'
          confidence = 'high'
          preventable = true
        elsif zombie_signals >= 2 && true_churn_signals == 0
          category = 'zombie'
          confidence = 'medium'
          preventable = true
        elsif true_churn_signals >= 3
          category = 'true'
          confidence = 'high'
          preventable = false
        elsif true_churn_signals >= 1
          category = 'true'
          confidence = 'medium'
          preventable = false
        else
          category = 'unclear'
          confidence = 'low'
          preventable = false
        end

        {
          type: "#{category}_churn",
          category: category,
          preventable: preventable,
          confidence: confidence,
          indicators: indicators,
          zombie_signals: zombie_signals,
          true_churn_signals: true_churn_signals
        }
      end

      ##
      # Calculate revenue impact for a churned customer
      #
      def calculate_revenue_impact(customer, subscription_days)
        # Estimate based on plan
        monthly_value = case customer.planid.to_s
                       when 'basic' then 3.0
                       when 'identity' then 12.0
                       else 0.0
                       end

        months_subscribed = (subscription_days / 30.0).round(2)
        total_revenue = monthly_value * months_subscribed

        {
          monthly_value: monthly_value,
          months_subscribed: months_subscribed,
          total_lifetime_revenue: total_revenue.round(2)
        }
      end

      ##
      # Calculate average metric from customer analyses
      #
      def avg_metric(customers, metric_key)
        return 0 if customers.empty?
        values = customers.map { |c| c.dig(:metrics, metric_key) }.compact
        return 0 if values.empty?
        (values.sum.to_f / values.length).round(2)
      end

      ##
      # Generate insights from churn analysis
      #
      def generate_insights(zombie_churns, true_churns, total)
        insights = []

        zombie_pct = (zombie_churns.length.to_f / total * 100).round(2)

        if zombie_pct > 60
          insights << "CRITICAL: #{zombie_pct}% of churn is preventable zombie churn. Immediate re-engagement needed."
        elsif zombie_pct > 40
          insights << "HIGH: #{zombie_pct}% of churn is zombie churn. Strong ROI potential from retention campaigns."
        elsif zombie_pct > 20
          insights << "MODERATE: #{zombie_pct}% of churn is zombie churn. Consider implementing engagement workflows."
        else
          insights << "LOW: Only #{zombie_pct}% of churn is zombie churn. Focus on product improvements for true churn."
        end

        # Analyze zombie patterns
        if zombie_churns.any?
          avg_zombie_health = avg_metric(zombie_churns, :health_score)
          avg_zombie_inactivity = avg_metric(zombie_churns, :days_inactive_at_cancel)

          insights << "Zombie customers average #{avg_zombie_inactivity} days inactive before cancellation."
          insights << "Average health score of zombie churn: #{avg_zombie_health}/100."
        end

        # Analyze true churn patterns
        if true_churns.any?
          avg_true_health = avg_metric(true_churns, :health_score)
          insights << "True churn customers had average health score of #{avg_true_health}/100."
          insights << "True churn indicates product-market fit or competitive issues to address."
        end

        insights
      end

      ##
      # Generate revenue-focused recommendations
      #
      def generate_revenue_recommendations(zombie_percentage, monthly_revenue_at_risk)
        recommendations = []

        if zombie_percentage > 50
          recommendations << "Implement automated re-engagement workflows immediately."
          recommendations << "Consider proactive cancellation warnings for inactive users."
          recommendations << "Add usage reminders and feature education campaigns."
        end

        if monthly_revenue_at_risk > 1000
          recommendations << "Revenue at risk justifies dedicated retention specialist."
          recommendations << "Implement health score monitoring and alerting."
        end

        if zombie_percentage > 30
          recommendations << "A/B test re-engagement messaging to optimize conversion."
          recommendations << "Add usage-based alerts to catch declining engagement early."
        end

        recommendations << "Track health scores over time to identify at-risk customers before they churn."
        recommendations
      end

      ##
      # Empty aggregate for when no data available
      #
      def empty_aggregate
        {
          analysis_period_days: @analysis_period_days,
          total_churned_customers: 0,
          zombie_churn: { count: 0, percentage: 0 },
          true_churn: { count: 0, percentage: 0 },
          preventable_churn_rate: 0,
          insights: ['No churn data available for analysis period.']
        }
      end
    end
  end
end
