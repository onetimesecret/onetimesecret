require 'onetime/app/web/base'

class Onetime::App
  class Colonel
    include OT::App::Base
    
    def index
      carefully do
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
    end
    
    module Views
      class Homepage < OT::App::Colonel::View
        def init *args
          self[:recent_feedback] = OT::Feedback.all.collect do |k,v|
            {:msg => k, :stamp => natural_time(v) }
          end
        end
      end
    end
    
  end
end