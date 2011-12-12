require 'onetime/app/helpers'

module Onetime
  class App
    
    module Base
      include OT::App::Helpers
      
      def publically redirect=nil
        carefully(redirect) do 
          check_session!     # 1. Load or create the session, load customer (or anon)
          check_shrimp!      # 2. Check the shrimp for POST,PUT,DELETE (after session)
          check_referrer!
          yield
        end
      end
      
      def authenticated redirect=nil
        carefully(redirect) do 
          check_session!     # 1. Load or create the session, load customer (or anon)
          check_shrimp!      # 2. Check the shrimp for POST,PUT,DELETE (after session)
          sess.authenticated? ? yield : res.redirect(('/')) # TODO: raise OT::Redirect
        end
      end

      def colonels redirect=nil
        carefully(redirect) do
          check_session!     # 1. Load or create the session, load customer (or anon)
          check_shrimp!      # 2. Check the shrimp for POST,PUT,DELETE (after session)
          sess.authenticated? && cust.role?(:colonel) ? yield : res.redirect(('/'))
        end
      end
      
      def check_referrer!
        return if req.referrer.match(Onetime.conf[:site][:host])
        sess.referrer ||= req.referrer
      end
      
      def secret_not_found_response
        view = Onetime::App::Views::UnknownSecret.new req, sess, cust
        res.status = 404
        res.body = view.render
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
  
end
