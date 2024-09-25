require_relative '../web/web_base'
require_relative '../app_settings'

module Onetime::App
  class Colonel
    include AppSettings
    include OT::App::Base

    def index
      colonels do
        view = Onetime::App::Colonel::Views::Homepage.new req, sess, cust
        sess.event_incr! :homepage
        res.body = view.render
      end
    end

    def secrets
      colonels do
        res.header['Content-Type'] = 'text/plain'
        obj = OT::Secret.new
        data = obj.redis.keys('secret*:object')
        res.body = data.collect { |key|
          '%s: %i' % [key, obj.redis.ttl(key)]
        }.join($/)
      end
    end

    def metadata
      colonels do
        res.header['Content-Type'] = 'text/plain'
        obj = OT::Metadata.new
        data = obj.redis.keys('metadata:*:object')
        res.body = data.collect { |key|
          '%s: %i' % [key, obj.redis.ttl(key)]
        }.join($/)
      end
    end

    module Views
    end

    class View < OT::App::View
      self.template_path = './templates/colonel'
      self.view_namespace = Onetime::App::Colonel::Views
      self.view_path = './lib/onetime/app/colonel/views'

      def initialize *args
        super
        self[:subtitle] = "Colonel"
      end
    end

    module Views
      class Homepage < OT::App::Colonel::View
        #self.template_name = '../web/vue_point'
        def init *args
          self[:title] = "Home"
          if OT.conf[:stathat]
            self[:stathat_chart] = OT.conf[:stathat][:default_chart]
          end
          self[:body_class] = :colonel
          self[:session_count] = OT::Session.recent(5.minutes).size
          self[:today_feedback] = OT::Feedback.recent(24.hours, OT.now.to_i).collect do |k,v|
            {:msg => k, :stamp => natural_time(v) }
          end.reverse
          self[:yesterday_feedback] = OT::Feedback.recent(48.hours, OT.now.to_i-24.hours).collect do |k,v|
            {:msg => k, :stamp => natural_time(v) }
          end.reverse
          self[:older_feedback] = OT::Feedback.recent(14.days, OT.now.to_i-48.hours).collect do |k,v|
            {:msg => k, :stamp => natural_time(v) }
          end.reverse
          self[:feedback_count] = OT::Feedback.values.size
          self[:today_feedback_count] = self[:today_feedback].size
          self[:yesterday_feedback_count] = self[:yesterday_feedback].size
          self[:older_feedback_count] = self[:older_feedback].size
          self[:recent_customers] = OT::Customer.recent.collect do |this_cust|
            next if this_cust.nil?
            { custid: this_cust.custid,
              planid: this_cust.planid,
              colonel: this_cust.role?(:colonel),
              secrets_created: this_cust.secrets_created,
              secrets_shared: this_cust.secrets_shared,
              emails_sent: this_cust.emails_sent,
              verified: this_cust.verified?,
              stamp: natural_time(this_cust.created) || '[no create stamp]' }
          end.reverse
          self[:customer_count] = OT::Customer.values.size
          self[:recent_customer_count] = self[:recent_customers].size
          self[:metadata_count] = OT::Metadata.new.redis.keys('metadata*:object').count
          self[:secret_count] = OT::Secret.new.redis.keys('secret*:object').count
          self[:secrets_created] = OT::Customer.global.secrets_created.to_s
          self[:secrets_shared] = OT::Customer.global.secrets_shared.to_s
          self[:emails_sent] = OT::Customer.global.emails_sent.to_s
          self[:split_tests] = OT::SplitTest.tests.collect do |plan|
            { :name => plan[1].testname, :values => plan[1].values, :samples => plan[1].samples }
          end
          self[:has_split_tests] = !self[:split_tests].empty?
          self[:entropy_count] = OT::Entropy.count
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

      end
    end

  end
end
