require 'onetime/app/helpers'

module Onetime
  class App
    
    module Base
      include OT::App::Helpers
      
      def carefully redirect=nil
        redirect ||= req.request_path
        # We check get here to stop an infinite redirect loop.
        # Pages redirecting from a POST can get by with the same page once. 
        redirect = '/error' if req.get? && redirect.to_s == req.request_path
        res.header['Content-Type'] ||= "text/html; charset=utf-8"
        
        check_session!     # 1. Load or create the session, load customer (or anon)
        check_shrimp!      # 2. Check the shrimp for POST,PUT,DELETE (after session)
        
        yield
      
      rescue Redirect => ex
        res.redirect ex.location, ex.status

      rescue OT::BadShrimp => ex
        sess.set_error_message "Please go back, refresh the page, and try again."
        res.redirect redirect
      
      rescue OT::FormError => ex
        sess.set_form_fields ex.form_fields
        sess.set_error_message ex.message
        res.redirect redirect
        
      rescue OT::MissingSecret => ex
        view = Onetime::App::Views::UnknownSecret.new req, sess, cust
        res.status = 404
        res.body = view.render
        
      rescue OT::LimitExceeded => ex
        err "[limit-exceeded] #{cust.custid}(#{sess.ipaddress}): #{ex.event}(#{ex.count}) #{sess.identifier.shorten(10)}"
        err req.current_absolute_uri
        error_response "Apologies dear citizen! You have been rate limited. Try again in a few minutes."
      
      rescue Familia::NotConnected, Familia::Problem => ex
        err "#{ex.class}: #{ex.message}"
        err ex.backtrace
        error_response "An error occurred :["
      
      rescue => ex
        err "#{ex.class}: #{ex.message}"
        err req.current_absolute_uri
        err ex.backtrace.join("\n")
        error_response "An error occurred :["
      
      end
      
      def not_found_response message
        view = Onetime::App::Views::NotFound.new req, sess, cust
        view.add_error message
        res.status = 404
        res.body = view.render
      end
    
      def error_response message
        view = Onetime::App::Views::Error.new req, sess, cust
        view.add_error message
        res.status = 401
        res.body = view.render
      end
      
    end
  end
  
  class Redirect < RuntimeError
    attr_reader :location, :status
    def initialize l, s=302
      @location, @status = l, s
    end
  end

end
