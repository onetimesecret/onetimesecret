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
          self[:body_class] = :colonel
          self[:session_count] = OT::Session.values.size
          self[:recent_feedback] = OT::Feedback.recent.collect do |k,v|
            {:msg => k, :stamp => natural_time(v) }
          end.reverse
          self[:feedback_count] = OT::Feedback.values.size
          self[:recent_feedback_count] = self[:recent_feedback].size
          self[:recent_customers] = OT::Customer.recent.collect do |this_cust|
            { :custid => this_cust.custid, 
              :planid => this_cust.planid,
              :colonel => this_cust.role?(:colonel),
              :stamp => natural_time(this_cust.created) || '[no create stamp]' }
          end.reverse
          self[:customer_count] = OT::Customer.values.size
          self[:recent_customer_count] = self[:recent_customers].size
          self[:metadata_count] = OT::Metadata.new.redis.keys('metadata*:object').count
          self[:secret_count] = OT::Secret.new.redis.keys('secret*:object').count
          self[:split_tests] = OT::SplitTest.tests.collect do |plan|
            { :name => plan[1].testname, :values => plan[1].values, :samples => plan[1].samples }
          end
        end
      end
    end
    
  end
end