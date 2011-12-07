
module Onetime
  class App
    
    class Info
      include Base
      def privacy
        carefully do
          view = Onetime::App::Views::Info::Privacy.new req, sess, cust
          res.body = view.render
        end
      end
      def security
        carefully do
          view = Onetime::App::Views::Info::Security.new req, sess, cust
          res.body = view.render
        end
      end
      def terms 
        carefully do
          view = Onetime::App::Views::Info::Terms.new req, sess, cust
          res.body = view.render
        end
      end
    end
    
  end
end
