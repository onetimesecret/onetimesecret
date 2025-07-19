# apps/api/v2/logic/colonel/get_colonel_info.rb

require 'onetime/refinements/stripe_refinements'

require_relative '../base'

module V2
  module Logic
    module Colonel
      class GetColonelInfo < V2::Logic::Base
        attr_reader :plans_enabled, :title, :session_count,
          :today_feedback, :yesterday_feedback, :older_feedback, :feedback_count,
          :today_feedback_count, :yesterday_feedback_count, :older_feedback_count,
          :recent_customers, :customer_count, :recent_customer_count, :metadata_count,
          :secret_count, :secrets_created, :secrets_shared, :emails_sent, :split_tests,
          :has_split_tests, :redis_info

        def process_params
          site           = OT.conf.fetch(:site, {})
          @plans_enabled = site.dig(:plans, :enabled) || false
        end

        def raise_concerns
          limit_action :view_colonel
        end

        def process
          @title         = 'Home'
          @session_count = V2::Session.recent(15.minutes).size

          process_feedback
          process_customers
          process_statistics

          @redis_info = redis_info
        end

        def process_feedback
          now                 = OT.now.to_i
          @today_feedback     = process_feedback_for_period(24.hours, now)
          @yesterday_feedback = process_feedback_for_period(48.hours, now - 24.hours)
          @older_feedback     = process_feedback_for_period(14.days, now - 48.hours)

          @feedback_count           = V2::Feedback.values.size
          @today_feedback_count     = @today_feedback.size
          @yesterday_feedback_count = @yesterday_feedback.size
          @older_feedback_count     = @older_feedback.size
        end
        private :process_feedback

        def process_feedback_for_period(period, end_time)
          V2::Feedback.recent(period, end_time).collect do |k, v|
            { msg: k, stamp: natural_time(v) }
          end.reverse
        end
        private :process_feedback_for_period

        def process_customers
          @recent_customers = V2::Customer.recent.collect do |this_cust|
            next if this_cust.nil?

            {
              custid: this_cust.custid,
              planid: this_cust.planid,
              colonel: this_cust.role?(:colonel),
              secrets_created: this_cust.secrets_created,
              secrets_shared: this_cust.secrets_shared,
              emails_sent: this_cust.emails_sent,
              verified: this_cust.verified?,
              stamp: natural_time(this_cust.created) || '[no create stamp]',
            }
          end.compact.reverse

          @customer_count        = V2::Customer.values.size
          @recent_customer_count = @recent_customers.size
        end
        private :process_customers

        def process_statistics
          @metadata_count  = V2::Metadata.new.redis.keys('metadata*:object').count
          @secret_count    = V2::Secret.new.redis.keys('secret*:object').count
          @secrets_created = V2::Customer.global.secrets_created.to_s
          @secrets_shared  = V2::Customer.global.secrets_shared.to_s
          @emails_sent     = V2::Customer.global.emails_sent.to_s
        end
        private :process_statistics

        def redis_info
          # Fetch Redis INFO
          info = Familia.redis.info

          # Extract relevant information
          db_info     = info.select { |key, _| key.start_with?('db') }
          memory_info = info.slice('used_memory', 'used_memory_human', 'used_memory_peak', 'used_memory_peak_human')

          # Combine the extracted information
          filtered_info = db_info.merge(memory_info)

          # Convert to YAML and print
          filtered_info.to_yaml
        end
        private :redis_info

        def success_data
          {
            record: {},
            details: {
              recent_customers: recent_customers,
              today_feedback: today_feedback,
              yesterday_feedback: yesterday_feedback,
              older_feedback: older_feedback,
              redis_info: redis_info,
              plans_enabled: plans_enabled,
              counts: {
                session_count: session_count,
                customer_count: customer_count,
                recent_customer_count: recent_customer_count,
                metadata_count: metadata_count,
                secret_count: secret_count,
                secrets_created: secrets_created,
                secrets_shared: secrets_shared,
                emails_sent: emails_sent,
                feedback_count: feedback_count,
                today_feedback_count: today_feedback_count,
                yesterday_feedback_count: yesterday_feedback_count,
                older_feedback_count: older_feedback_count,
              },
            },
          }
        end
      end
    end
  end
end
