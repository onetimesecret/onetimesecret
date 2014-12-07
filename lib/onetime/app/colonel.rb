require 'onetime/app/web/base'

class Onetime::App
  class Colonel
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

    def generate_entropy
      colonels do
        Onetime::Entropy.generate 5000
        sess.set_info_message "Added 5000 elements to entropy"
        res.redirect '/colonel' unless req.ajax?
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
        def init *args
          self[:title] = "Home"
          self[:stathat_chart] = OT.conf[:stathat][:default_chart]
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
          self[:subdomain_count] = OT::Subdomain.values.size
          self[:subdomains] = OT::Subdomain.all.collect do |v|
            { :cname => v['cname'], :custid => v.custid, :fulldomain => v.fulldomain }
          end.reverse
          self[:feedback_count] = OT::Feedback.values.size
          self[:today_feedback_count] = self[:today_feedback].size
          self[:yesterday_feedback_count] = self[:yesterday_feedback].size
          self[:older_feedback_count] = self[:older_feedback].size
          self[:recent_customers] = OT::Customer.recent.collect do |this_cust|
            next if this_cust.nil?
            { :custid => this_cust.custid,
              :planid => this_cust.planid,
              :colonel => this_cust.role?(:colonel),
              :secrets_created => this_cust.secrets_created,
              :secrets_shared => this_cust.secrets_shared,
              :emails_sent => this_cust.emails_sent,
              :stamp => natural_time(this_cust.created) || '[no create stamp]' }
          end.reverse
          self[:customer_count] = OT::Customer.values.size
          self[:recent_customer_count] = self[:recent_customers].size
          self[:metadata_count] = OT::Metadata.new.redis.keys('metadata*:object').count
          self[:secret_count] = OT::Secret.new.redis.keys('secret*:object').count
          self[:secrets_created] = OT::Customer.global.get_value(:secrets_created, true)
          self[:secrets_shared] = OT::Customer.global.get_value(:secrets_shared, true)
          self[:emails_sent] = OT::Customer.global.get_value(:emails_sent, true)
          self[:split_tests] = OT::SplitTest.tests.collect do |plan|
            { :name => plan[1].testname, :values => plan[1].values, :samples => plan[1].samples }
          end
          self[:has_split_tests] = !self[:split_tests].empty?
          self[:entropy_count] = OT::Entropy.count
        end
        def redis_info
          Familia.redis.info.to_yaml
        end

      end
    end

  end
end
