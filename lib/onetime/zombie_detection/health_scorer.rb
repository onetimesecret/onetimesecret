require 'onetime'

module Onetime
  module ZombieDetection
    ##
    # HealthScorer - Calculates a comprehensive health score (0-100) for customers
    #
    # The health score is a weighted composite of multiple engagement metrics:
    # - Recency: How recently the customer was active
    # - Frequency: How often they use the service
    # - Volume: How much they use the service
    # - Engagement: Breadth of feature usage
    #
    # Score Ranges:
    # - 90-100: Excellent health, highly engaged
    # - 70-89:  Good health, regular user
    # - 50-69:  Fair health, at-risk user
    # - 30-49:  Poor health, zombie candidate
    # - 0-29:   Critical, likely zombie
    #
    class HealthScorer
      # Weights for different health components (must sum to 100)
      WEIGHTS = {
        recency: 35,      # Most important: recent activity
        frequency: 25,    # Usage frequency
        volume: 20,       # Total usage amount
        engagement: 20    # Feature breadth
      }.freeze

      # Scoring thresholds
      EXCELLENT_LOGIN_DAYS = 7      # Logged in within 7 days
      GOOD_LOGIN_DAYS = 30          # Logged in within 30 days
      FAIR_LOGIN_DAYS = 60          # Logged in within 60 days
      POOR_LOGIN_DAYS = 90          # Logged in within 90 days

      EXCELLENT_SECRETS_MONTHLY = 20  # 20+ secrets per month
      GOOD_SECRETS_MONTHLY = 10       # 10+ secrets per month
      FAIR_SECRETS_MONTHLY = 5        # 5+ secrets per month
      POOR_SECRETS_MONTHLY = 1        # 1+ secrets per month

      attr_reader :customer

      ##
      # Initialize scorer for a customer
      #
      # @param customer [V2::Customer] The customer to score
      #
      def initialize(customer)
        @customer = customer
      end

      ##
      # Calculate overall health score
      #
      # @return [Integer] Health score from 0-100
      #
      def calculate
        return 0 unless customer.planid.to_s != 'anonymous' && !customer.planid.to_s.empty?

        scores = {
          recency: calculate_recency_score,
          frequency: calculate_frequency_score,
          volume: calculate_volume_score,
          engagement: calculate_engagement_score
        }

        weighted_score = scores.map { |component, score|
          score * (WEIGHTS[component] / 100.0)
        }.sum

        weighted_score.round.clamp(0, 100)
      end

      ##
      # Get detailed score breakdown
      #
      # @return [Hash] Detailed scoring information
      #
      def breakdown
        {
          overall_score: calculate,
          components: {
            recency: {
              score: calculate_recency_score,
              weight: WEIGHTS[:recency],
              weighted_score: calculate_recency_score * (WEIGHTS[:recency] / 100.0)
            },
            frequency: {
              score: calculate_frequency_score,
              weight: WEIGHTS[:frequency],
              weighted_score: calculate_frequency_score * (WEIGHTS[:frequency] / 100.0)
            },
            volume: {
              score: calculate_volume_score,
              weight: WEIGHTS[:volume],
              weighted_score: calculate_volume_score * (WEIGHTS[:volume] / 100.0)
            },
            engagement: {
              score: calculate_engagement_score,
              weight: WEIGHTS[:engagement],
              weighted_score: calculate_engagement_score * (WEIGHTS[:engagement] / 100.0)
            }
          },
          metrics: gather_metrics,
          interpretation: interpret_score(calculate)
        }
      end

      private

      ##
      # Calculate recency score (0-100) based on last login
      # Most recent activity = highest score
      #
      def calculate_recency_score
        last_login = customer.last_login.to_i
        return 0 if last_login == 0  # Never logged in

        days_since_login = ((Time.now.to_i - last_login) / 86400.0).round

        case days_since_login
        when 0..EXCELLENT_LOGIN_DAYS
          100  # Excellent: logged in within a week
        when (EXCELLENT_LOGIN_DAYS + 1)..GOOD_LOGIN_DAYS
          # Good: decay from 100 to 70
          70 + (30 * (1 - (days_since_login - EXCELLENT_LOGIN_DAYS).to_f / (GOOD_LOGIN_DAYS - EXCELLENT_LOGIN_DAYS)))
        when (GOOD_LOGIN_DAYS + 1)..FAIR_LOGIN_DAYS
          # Fair: decay from 70 to 40
          40 + (30 * (1 - (days_since_login - GOOD_LOGIN_DAYS).to_f / (FAIR_LOGIN_DAYS - GOOD_LOGIN_DAYS)))
        when (FAIR_LOGIN_DAYS + 1)..POOR_LOGIN_DAYS
          # Poor: decay from 40 to 10
          10 + (30 * (1 - (days_since_login - FAIR_LOGIN_DAYS).to_f / (POOR_LOGIN_DAYS - FAIR_LOGIN_DAYS)))
        else
          # Critical: 90+ days inactive
          [10 - (days_since_login - POOR_LOGIN_DAYS) / 10, 0].max
        end.round.clamp(0, 100)
      end

      ##
      # Calculate frequency score (0-100) based on usage rate
      # Higher usage frequency = higher score
      #
      def calculate_frequency_score
        subscription_age_days = ((Time.now.to_i - customer.created.to_i) / 86400.0).round
        return 50 if subscription_age_days < 7  # Too early to judge

        total_secrets = customer.secrets_created.to_i
        secrets_per_month = (total_secrets.to_f / [subscription_age_days / 30.0, 1].max)

        case secrets_per_month
        when EXCELLENT_SECRETS_MONTHLY..Float::INFINITY
          100  # Excellent: 20+ secrets per month
        when GOOD_SECRETS_MONTHLY...EXCELLENT_SECRETS_MONTHLY
          # Good: scale from 70 to 100
          70 + (30 * (secrets_per_month - GOOD_SECRETS_MONTHLY) / (EXCELLENT_SECRETS_MONTHLY - GOOD_SECRETS_MONTHLY))
        when FAIR_SECRETS_MONTHLY...GOOD_SECRETS_MONTHLY
          # Fair: scale from 40 to 70
          40 + (30 * (secrets_per_month - FAIR_SECRETS_MONTHLY) / (GOOD_SECRETS_MONTHLY - FAIR_SECRETS_MONTHLY))
        when POOR_SECRETS_MONTHLY...FAIR_SECRETS_MONTHLY
          # Poor: scale from 20 to 40
          20 + (20 * (secrets_per_month - POOR_SECRETS_MONTHLY) / (FAIR_SECRETS_MONTHLY - POOR_SECRETS_MONTHLY))
        else
          # Critical: less than 1 secret per month
          secrets_per_month > 0 ? (20 * secrets_per_month).round : 0
        end.round.clamp(0, 100)
      end

      ##
      # Calculate volume score (0-100) based on total usage
      # More total usage = higher score
      #
      def calculate_volume_score
        total_secrets = customer.secrets_created.to_i
        secrets_shared = customer.secrets_shared.to_i
        secrets_burned = customer.secrets_burned.to_i

        # Combined activity score
        total_activity = total_secrets + (secrets_shared * 0.5) + (secrets_burned * 0.3)

        case total_activity
        when 100..Float::INFINITY
          100  # Excellent: 100+ total activities
        when 50...100
          70 + (30 * (total_activity - 50) / 50.0)  # Good: 50-99
        when 20...50
          40 + (30 * (total_activity - 20) / 30.0)  # Fair: 20-49
        when 5...20
          20 + (20 * (total_activity - 5) / 15.0)   # Poor: 5-19
        when 1...5
          10 + (10 * total_activity / 5.0)          # Critical: 1-4
        else
          0  # None
        end.round.clamp(0, 100)
      end

      ##
      # Calculate engagement score (0-100) based on feature breadth
      # More diverse usage = higher score
      #
      def calculate_engagement_score
        engagement_points = 0
        max_points = 0

        # Check various engagement indicators
        indicators = [
          { metric: customer.secrets_created.to_i > 0, points: 25 },
          { metric: customer.secrets_shared.to_i > 0, points: 25 },
          { metric: customer.secrets_burned.to_i > 0, points: 15 },
          { metric: customer.emails_sent.to_i > 0, points: 20 },
          { metric: customer.last_login.to_i > 0, points: 15 }
        ]

        indicators.each do |indicator|
          max_points += indicator[:points]
          engagement_points += indicator[:points] if indicator[:metric]
        end

        ((engagement_points.to_f / max_points) * 100).round.clamp(0, 100)
      end

      ##
      # Gather relevant metrics for reporting
      #
      def gather_metrics
        now = Time.now.to_i
        created_time = customer.created.to_i
        last_login = customer.last_login.to_i
        subscription_age_days = ((now - created_time) / 86400.0).round

        {
          customer_id: customer.custid,
          email: customer.email,
          plan: customer.planid,
          subscription_age_days: subscription_age_days,
          days_since_last_login: last_login > 0 ? ((now - last_login) / 86400.0).round : nil,
          total_secrets_created: customer.secrets_created.to_i,
          total_secrets_shared: customer.secrets_shared.to_i,
          total_secrets_burned: customer.secrets_burned.to_i,
          emails_sent: customer.emails_sent.to_i,
          secrets_per_month: (customer.secrets_created.to_i.to_f / [subscription_age_days / 30.0, 1].max).round(2)
        }
      end

      ##
      # Interpret the overall score
      #
      def interpret_score(score)
        case score
        when 90..100
          { level: 'excellent', status: 'healthy', action: 'none' }
        when 70...90
          { level: 'good', status: 'healthy', action: 'monitor' }
        when 50...70
          { level: 'fair', status: 'at_risk', action: 'engage' }
        when 30...50
          { level: 'poor', status: 'zombie_candidate', action: 'urgent_engagement' }
        else
          { level: 'critical', status: 'likely_zombie', action: 'immediate_intervention' }
        end
      end
    end
  end
end
