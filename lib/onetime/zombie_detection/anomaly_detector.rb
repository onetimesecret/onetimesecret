require 'onetime'
require_relative 'health_scorer'

module Onetime
  module ZombieDetection
    ##
    # AnomalyDetector - Identifies unusual usage patterns indicating zombie subscriptions
    #
    # This class implements multiple detection algorithms to identify customers who:
    # - Have active subscriptions but show little to no usage
    # - Exhibit sudden drops in engagement
    # - Show patterns consistent with abandoned accounts
    #
    class AnomalyDetector
      # Thresholds for zombie detection
      THRESHOLDS = {
        min_subscription_age_days: 30,      # Must be subscribed for at least 30 days
        max_inactivity_days: 60,            # No login for 60+ days
        min_usage_threshold: 5,             # Less than 5 secrets created
        usage_drop_percentage: 80,          # 80% drop from previous period
        max_healthy_inactivity_days: 14,    # Healthy users login at least every 14 days
        zombie_score_threshold: 70          # Health score below 70 = zombie candidate
      }.freeze

      attr_reader :customer, :metrics, :anomalies

      ##
      # Initialize detector for a specific customer
      #
      # @param customer [V2::Customer] The customer to analyze
      #
      def initialize(customer)
        @customer = customer
        @metrics = calculate_metrics
        @anomalies = []
      end

      ##
      # Run all anomaly detection algorithms
      #
      # @return [Hash] Detection results with anomaly flags and scores
      #
      def detect
        detect_never_used
        detect_prolonged_inactivity
        detect_minimal_usage
        detect_usage_drop
        detect_no_recent_logins
        detect_subscription_without_engagement

        {
          customer_id: customer.custid,
          email: customer.email,
          is_zombie: zombie?,
          anomalies: @anomalies,
          metrics: @metrics,
          health_score: health_score,
          risk_level: risk_level,
          detected_at: Time.now.to_i
        }
      end

      ##
      # Checks if customer meets zombie criteria
      #
      # @return [Boolean] True if customer is classified as zombie
      #
      def zombie?
        @anomalies.any? && health_score < THRESHOLDS[:zombie_score_threshold]
      end

      ##
      # Calculate health score using HealthScorer
      #
      # @return [Integer] Health score (0-100)
      #
      def health_score
        @health_score ||= HealthScorer.new(customer).calculate
      end

      ##
      # Determine risk level based on anomalies and health score
      #
      # @return [String] Risk level: critical, high, medium, low
      #
      def risk_level
        return 'critical' if @anomalies.length >= 4 && health_score < 30
        return 'high' if @anomalies.length >= 3 && health_score < 50
        return 'medium' if @anomalies.length >= 2 && health_score < 70
        return 'low' if @anomalies.any?
        'healthy'
      end

      private

      ##
      # Calculate key metrics for anomaly detection
      #
      def calculate_metrics
        now = Time.now.to_i
        created_time = customer.created.to_i
        last_login_time = customer.last_login.to_i
        subscription_age_days = ((now - created_time) / 86400.0).round

        {
          subscription_age_days: subscription_age_days,
          days_since_last_login: last_login_time > 0 ? ((now - last_login_time) / 86400.0).round : nil,
          total_secrets_created: customer.secrets_created.to_i,
          total_secrets_shared: customer.secrets_shared.to_i,
          total_secrets_burned: customer.secrets_burned.to_i,
          emails_sent: customer.emails_sent.to_i,
          has_stripe_subscription: !customer.stripe_subscription_id.to_s.empty?,
          plan_id: customer.planid.to_s,
          is_paid_plan: paid_plan?,
          created_at: created_time,
          last_login_at: last_login_time
        }
      end

      ##
      # Check if customer has a paid plan
      #
      def paid_plan?
        plan_id = customer.planid.to_s
        plan_id != 'anonymous' && !plan_id.empty?
      end

      ##
      # Detect: Customer never used the service
      #
      def detect_never_used
        if paid_plan? &&
           @metrics[:total_secrets_created] == 0 &&
           @metrics[:subscription_age_days] >= THRESHOLDS[:min_subscription_age_days]

          add_anomaly(
            type: 'never_used',
            severity: 'critical',
            description: 'Paid subscription with zero usage after 30+ days',
            details: {
              days_subscribed: @metrics[:subscription_age_days],
              secrets_created: 0
            }
          )
        end
      end

      ##
      # Detect: Prolonged inactivity (no login for extended period)
      #
      def detect_prolonged_inactivity
        if paid_plan? &&
           @metrics[:days_since_last_login] &&
           @metrics[:days_since_last_login] >= THRESHOLDS[:max_inactivity_days]

          add_anomaly(
            type: 'prolonged_inactivity',
            severity: 'high',
            description: "No login activity for #{@metrics[:days_since_last_login]} days",
            details: {
              days_inactive: @metrics[:days_since_last_login],
              last_login_at: @metrics[:last_login_at]
            }
          )
        end
      end

      ##
      # Detect: Minimal usage despite paid subscription
      #
      def detect_minimal_usage
        if paid_plan? &&
           @metrics[:subscription_age_days] >= THRESHOLDS[:min_subscription_age_days] &&
           @metrics[:total_secrets_created] > 0 &&
           @metrics[:total_secrets_created] < THRESHOLDS[:min_usage_threshold]

          usage_per_month = (@metrics[:total_secrets_created].to_f /
                            [@metrics[:subscription_age_days] / 30.0, 1].max).round(2)

          add_anomaly(
            type: 'minimal_usage',
            severity: 'high',
            description: 'Very low usage relative to subscription duration',
            details: {
              total_secrets: @metrics[:total_secrets_created],
              subscription_age_days: @metrics[:subscription_age_days],
              secrets_per_month: usage_per_month
            }
          )
        end
      end

      ##
      # Detect: Significant drop in usage patterns
      # Compares recent 30 days vs previous 30 days
      #
      def detect_usage_drop
        # Note: This requires time-series data which isn't available in current schema
        # Placeholder for future implementation when activity logs are available
        #
        # Would compare:
        # - Secrets created in last 30 days vs previous 30 days
        # - Login frequency recent vs historical
        # - Email sends recent vs historical
        #
        # For now, we can infer from overall low usage + old last_login
        if paid_plan? &&
           @metrics[:total_secrets_created] > THRESHOLDS[:min_usage_threshold] &&
           @metrics[:days_since_last_login] &&
           @metrics[:days_since_last_login] >= 30

          add_anomaly(
            type: 'usage_drop',
            severity: 'medium',
            description: 'Potential usage drop - historically active but recently inactive',
            details: {
              total_historical_usage: @metrics[:total_secrets_created],
              days_since_activity: @metrics[:days_since_last_login]
            }
          )
        end
      end

      ##
      # Detect: No recent logins despite active subscription
      #
      def detect_no_recent_logins
        if paid_plan? &&
           (!@metrics[:last_login_at] || @metrics[:last_login_at] == 0)

          add_anomaly(
            type: 'never_logged_in',
            severity: 'critical',
            description: 'Paid subscription but customer has never logged in',
            details: {
              subscription_age_days: @metrics[:subscription_age_days]
            }
          )
        end
      end

      ##
      # Detect: Subscription purchased but no engagement
      # (created account, subscribed, but never created secrets or logged in regularly)
      #
      def detect_subscription_without_engagement
        if paid_plan? &&
           @metrics[:subscription_age_days] >= THRESHOLDS[:min_subscription_age_days] &&
           @metrics[:total_secrets_created] < 3 &&
           @metrics[:emails_sent].to_i < 2

          add_anomaly(
            type: 'no_engagement',
            severity: 'high',
            description: 'Subscription with minimal engagement across all metrics',
            details: {
              secrets_created: @metrics[:total_secrets_created],
              secrets_shared: @metrics[:total_secrets_shared],
              emails_sent: @metrics[:emails_sent],
              subscription_age_days: @metrics[:subscription_age_days]
            }
          )
        end
      end

      ##
      # Add an anomaly to the detected list
      #
      def add_anomaly(type:, severity:, description:, details: {})
        @anomalies << {
          type: type,
          severity: severity,
          description: description,
          details: details
        }
      end
    end
  end
end
