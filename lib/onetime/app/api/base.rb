require 'onetime/app/helpers'

class Onetime::App
  class API
    module Base
      include Onetime::App::Helpers
      
      
      def anonymous
        carefully do 
          begin
            @cust = OT::Customer.anonymous
            if req.cookie?(:sess) && OT::Session.exists?(req.cookie(:sess))
              @sess = OT::Session.load req.cookie(:sess)
            else
              @sess = OT::Session.create req.client_ipaddress, @cust.custid, req.user_agent
            end
            if @sess
              @sess.update_fields  # calls update_time!
              # Only set the cookie after it's been saved
              res.send_cookie :sess, @sess.sessid, @sess.ttl
            end
          end
          yield
        end
      end
    
      def carefully redirect=nil
        redirect ||= req.request_path
        # We check get here to stop an infinite redirect loop.
        # Pages redirecting from a POST can get by with the same page once. 
        redirect = '/error' if req.get? && redirect.to_s == req.request_path
        res.header['Content-Type'] ||= "text/html; charset=utf-8"
        yield
      end
      
      def json hsh
        res.header['Content-Type'] = "application/json; charset=utf-8"
        res.body = hsh.to_json
      end
      
      def not_found hsh
        res.status = 404
        json hsh
      end
      
    end
  end
end