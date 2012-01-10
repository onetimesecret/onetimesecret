require 'onetime/app/helpers'

module Onetime
  class App
    
    module Base
      include OT::App::Helpers
      attr_reader :subdomain
      
      def publically redirect=nil
        carefully(redirect) do 
          check_session!     # 1. Load or create the session, load customer (or anon)
          check_shrimp!      # 2. Check the shrimp for POST,PUT,DELETE (after session)\
          check_subdomain!   # 3. Check if we're running as a subdomain
          check_referrer!    # 4. Check referrers for public requests
          yield
        end
      end
      
      def authenticated redirect=nil
        carefully(redirect) do 
          check_session!     # 1. Load or create the session, load customer (or anon)
          check_shrimp!      # 2. Check the shrimp for POST,PUT,DELETE (after session)
          check_subdomain!   # 3. Check if we're running as a subdomain
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
      
      def check_subdomain!
        subdomstr = req.env['SERVER_NAME'].split('.').first
        if !subdomstr.to_s.empty? && subdomstr != 'www' && OT::Subdomain.exists?(subdomstr)
          @subdomain = OT::Subdomain.load(subdomstr)
        end
      end
      
      def check_referrer!
        return if @check_referrer_ran
        @check_referrer_ran = true
        return if req.referrer.match(Onetime.conf[:site][:host])
        sess.referrer ||= req.referrer
      end
      
      def handle_form_error ex, redirect
        sess.set_form_fields ex.form_fields
        sess.set_error_message ex.message
        res.redirect redirect
      end
      
      def secret_not_found_response
        view = Onetime::App::Views::UnknownSecret.new req, sess, cust
        res.status = 404
        res.body = view.render
      end
      
      def not_found
        publically do
          not_found_response "Not sure what you're looking for..."
        end
      end
      
      def server_error
        publically do
          error_response "You found a bug. Let us know how it happened!"
        end
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
      
      def is_subdomain?
        ! subdomain.nil?
      end
    end
  end
  
end
