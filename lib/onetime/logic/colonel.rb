
require_relative 'base'
require_relative '../refinements/stripe_refinements'

module Onetime::Logic
  module Colonel

    class GetColonel < OT::Logic::Base
      attr_reader :plans_enabled, :title, :stathat_chart, :body_class, :session_count,
                  :today_feedback, :yesterday_feedback, :older_feedback, :feedback_count,
                  :today_feedback_count, :yesterday_feedback_count, :older_feedback_count,
                  :recent_customers, :customer_count, :recent_customer_count, :metadata_count,
                  :secret_count, :secrets_created, :secrets_shared, :emails_sent, :split_tests,
                  :has_split_tests, :entropy_count, :redis_info

      def process_params
        site = OT.conf.fetch(:site, {})
        @plans_enabled = site.dig(:plans, :enabled) || false
      end

      def raise_concerns
        limit_action :view_colonel
      end

      def process
        @title = "Home"
        @stathat_chart = OT.conf[:stathat][:default_chart] if OT.conf[:stathat]
        @body_class = :colonel
        @session_count = OT::Session.recent(5.minutes).size

        process_feedback
        process_customers
        process_statistics
        process_split_tests

        @redis_info = redis_info
        @entropy_count = OT::Entropy.count
      end

      private

      def process_feedback
        now = OT.now.to_i
        @today_feedback = process_feedback_for_period(24.hours, now)
        @yesterday_feedback = process_feedback_for_period(48.hours, now - 24.hours)
        @older_feedback = process_feedback_for_period(14.days, now - 48.hours)

        @feedback_count = OT::Feedback.values.size
        @today_feedback_count = @today_feedback.size
        @yesterday_feedback_count = @yesterday_feedback.size
        @older_feedback_count = @older_feedback.size
      end

      def process_feedback_for_period(period, end_time)
        OT::Feedback.recent(period, end_time).collect do |k, v|
          { msg: k, stamp: natural_time(v) }
        end.reverse
      end

      def process_customers
        @recent_customers = OT::Customer.recent.collect do |this_cust|
          next if this_cust.nil?
          {
            custid: this_cust.custid,
            planid: this_cust.planid,
            colonel: this_cust.role?(:colonel),
            secrets_created: this_cust.secrets_created,
            secrets_shared: this_cust.secrets_shared,
            emails_sent: this_cust.emails_sent,
            verified: this_cust.verified?,
            stamp: natural_time(this_cust.created) || '[no create stamp]'
          }
        end.compact.reverse

        @customer_count = OT::Customer.values.size
        @recent_customer_count = @recent_customers.size
      end

      def process_statistics
        @metadata_count = OT::Metadata.new.redis.keys('metadata*:object').count
        @secret_count = OT::Secret.new.redis.keys('secret*:object').count
        @secrets_created = OT::Customer.global.secrets_created.to_s
        @secrets_shared = OT::Customer.global.secrets_shared.to_s
        @emails_sent = OT::Customer.global.emails_sent.to_s
      end

      def redis_info
        # Fetch Redis INFO
        info = Familia.redis.info

        # Extract relevant information
        db_info = info.select { |key, _| key.start_with?('db') }
        memory_info = info.slice('used_memory', 'used_memory_human', 'used_memory_peak', 'used_memory_peak_human')

        # Combine the extracted information
        filtered_info = db_info.merge(memory_info)

        # Convert to YAML and print
        filtered_info.to_yaml
      end

      def success_data
        {
          record: {
            recent_customers:,
            today_feedback:,
            yesterday_feedback:,
            older_feedback:,
            redis_info:
          },
          details: {
            plans_enabled:,
            counts: {
              session_count:,
              customer_count:,
              recent_customer_count:,
              metadata_count:,
              secret_count:,
              secrets_created:,
              secrets_shared:,
              emails_sent:,
              feedback_count:,
              today_feedback_count:,
              yesterday_feedback_count:,
              older_feedback_count:
            }

          }
        }
      end

    end
  end
end